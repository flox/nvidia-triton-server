"""BLS (Business Logic Scripting) model that orchestrates the TRT-LLM
ensemble pipeline: preprocessing -> tensorrt_llm -> token decoding.

Replaces the static ensemble to support streaming (decoupled mode).
For streaming requests, computes text deltas from cumulative output_ids.
For non-streaming requests, returns full decoded text.
"""

import json

import numpy as np
import triton_python_backend_utils as pb_utils
from transformers import AutoTokenizer


class TritonPythonModel:
    def initialize(self, args):
        model_config = json.loads(args["model_config"])
        params = model_config.get("parameters", {})
        self.preprocess_model = params["preprocessing_model"]["string_value"]
        self.trtllm_model = params["trtllm_model"]["string_value"]
        tokenizer_dir = params["tokenizer_dir"]["string_value"]
        self.tokenizer = AutoTokenizer.from_pretrained(tokenizer_dir)

    def execute(self, requests):
        for req in requests:
            sender = req.get_response_sender()
            try:
                self._handle_request(req, sender)
            except Exception as e:
                sender.send(
                    pb_utils.InferenceResponse(
                        error=pb_utils.TritonError(str(e))
                    ),
                    flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL,
                )
        return None

    def _handle_request(self, req, sender):
        text_input = pb_utils.get_input_tensor_by_name(req, "text_input")
        max_tokens = pb_utils.get_input_tensor_by_name(req, "max_tokens")
        stream_tensor = pb_utils.get_input_tensor_by_name(req, "stream")
        is_streaming = False
        if stream_tensor is not None:
            is_streaming = bool(stream_tensor.as_numpy().flatten()[0])

        # --- Step 1: Preprocessing (tokenize) ---
        preprocess_inputs = [
            pb_utils.Tensor("QUERY", text_input.as_numpy()),
        ]
        if max_tokens is not None:
            preprocess_inputs.append(
                pb_utils.Tensor("REQUEST_OUTPUT_LEN", max_tokens.as_numpy())
            )

        preprocess_resp = pb_utils.InferenceRequest(
            model_name=self.preprocess_model,
            requested_output_names=[
                "INPUT_ID", "REQUEST_INPUT_LEN", "REQUEST_OUTPUT_LEN",
                "OUT_END_ID", "OUT_PAD_ID",
            ],
            inputs=preprocess_inputs,
        ).exec()

        if preprocess_resp.has_error():
            raise RuntimeError(
                f"Preprocessing failed: {preprocess_resp.error()}"
            )

        # --- Step 2: TRT-LLM inference ---
        trtllm_inputs = [
            pb_utils.Tensor(
                "input_ids",
                pb_utils.get_output_tensor_by_name(
                    preprocess_resp, "INPUT_ID"
                ).as_numpy(),
            ),
            pb_utils.Tensor(
                "input_lengths",
                pb_utils.get_output_tensor_by_name(
                    preprocess_resp, "REQUEST_INPUT_LEN"
                ).as_numpy(),
            ),
            pb_utils.Tensor(
                "request_output_len",
                pb_utils.get_output_tensor_by_name(
                    preprocess_resp, "REQUEST_OUTPUT_LEN"
                ).as_numpy(),
            ),
            pb_utils.Tensor(
                "end_id",
                pb_utils.get_output_tensor_by_name(
                    preprocess_resp, "OUT_END_ID"
                ).as_numpy(),
            ),
            pb_utils.Tensor(
                "pad_id",
                pb_utils.get_output_tensor_by_name(
                    preprocess_resp, "OUT_PAD_ID"
                ).as_numpy(),
            ),
            pb_utils.Tensor(
                "streaming",
                np.array([[is_streaming]], dtype=bool),
            ),
        ]

        # Forward optional sampling parameters
        param_map = {
            "temperature": "temperature",
            "top_p": "runtime_top_p",
            "seed": "seed",
            "repetition_penalty": "repetition_penalty",
            "stop_words": "stop_words",
            "frequency_penalty": "frequency_penalty",
            "presence_penalty": "presence_penalty",
            "return_num_input_tokens": "return_num_input_tokens",
            "return_num_output_tokens": "return_num_output_tokens",
        }
        for input_name, trtllm_name in param_map.items():
            tensor = pb_utils.get_input_tensor_by_name(req, input_name)
            if tensor is not None:
                trtllm_inputs.append(
                    pb_utils.Tensor(trtllm_name, tensor.as_numpy())
                )

        trtllm_req = pb_utils.InferenceRequest(
            model_name=self.trtllm_model,
            requested_output_names=["output_ids", "sequence_length"],
            inputs=trtllm_inputs,
        )

        # --- Step 3: Decode and send responses ---
        # TRT-LLM decoupled mode sends one token per response (not
        # cumulative).  We accumulate token IDs ourselves and compute
        # text deltas via decode(all) - decode(all-but-last) to handle
        # BPE boundaries correctly.
        all_token_ids = []
        prev_text = ""
        prev_resp = None

        for trtllm_resp in trtllm_req.exec(decoupled=True):
            if trtllm_resp.has_error():
                raise RuntimeError(
                    f"TRT-LLM inference failed: {trtllm_resp.error()}"
                )

            # Send the previous buffered response (not final)
            if prev_resp is not None:
                sender.send(prev_resp)

            # Extract new token(s) from this response
            output_ids = pb_utils.get_output_tensor_by_name(
                trtllm_resp, "output_ids"
            ).as_numpy()
            seq_lens = pb_utils.get_output_tensor_by_name(
                trtllm_resp, "sequence_length"
            ).as_numpy()

            seq_len = int(seq_lens[0][0])
            new_ids = output_ids[0][0][:seq_len].tolist()
            all_token_ids.extend(new_ids)

            full_text = self.tokenizer.decode(
                all_token_ids, skip_special_tokens=True
            )

            if is_streaming:
                text_out = full_text[len(prev_text):]
                prev_text = full_text
            else:
                text_out = full_text

            prev_resp = pb_utils.InferenceResponse(
                output_tensors=[
                    pb_utils.Tensor(
                        "text_output",
                        np.array([[text_out]], dtype=object),
                    )
                ]
            )

        # Send the last buffered response with COMPLETE_FINAL
        if prev_resp is not None:
            sender.send(
                prev_resp,
                flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL,
            )
        else:
            sender.send(
                flags=pb_utils.TRITONSERVER_RESPONSE_COMPLETE_FINAL,
            )

    def finalize(self):
        pass
