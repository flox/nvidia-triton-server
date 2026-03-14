import json

import numpy as np
import triton_python_backend_utils as pb_utils
from transformers import AutoTokenizer


class TritonPythonModel:
    def initialize(self, args):
        model_config = json.loads(args["model_config"])
        params = model_config.get("parameters", {})
        tokenizer_dir = params["tokenizer_dir"]["string_value"]
        self.tokenizer = AutoTokenizer.from_pretrained(tokenizer_dir)
        if self.tokenizer.pad_token is None:
            self.tokenizer.pad_token = self.tokenizer.eos_token
        self._end_id = self._resolve_end_id()

    def _resolve_end_id(self):
        """Detect the end-of-turn token for chat models.

        Many chat models use a dedicated end-of-turn token that differs
        from eos_token_id (e.g. Phi-4 uses <|end|> not <|endoftext|>).
        We detect it by applying the chat template to a minimal
        conversation and inspecting the tokens after the assistant content.
        Falls back to eos_token_id for non-chat or unparseable tokenizers.
        """
        if not getattr(self.tokenizer, "chat_template", None):
            return self.tokenizer.eos_token_id or 0
        try:
            full = self.tokenizer.apply_chat_template(
                [
                    {"role": "user", "content": "hi"},
                    {"role": "assistant", "content": "x"},
                ],
                add_generation_prompt=False,
                tokenize=True, return_dict=False,
            )
            prompt = self.tokenizer.apply_chat_template(
                [{"role": "user", "content": "hi"}],
                add_generation_prompt=True,
                tokenize=True, return_dict=False,
            )
            suffix = full[len(prompt):]
            content_ids = self.tokenizer.encode("x", add_special_tokens=False)
            end_markers = suffix[len(content_ids):]
            if end_markers:
                return end_markers[0]
        except Exception:
            pass
        return self.tokenizer.eos_token_id or 0

    def execute(self, requests):
        responses = []
        for req in requests:
            query = pb_utils.get_input_tensor_by_name(req, "QUERY")
            query_str = query.as_numpy().flatten()[0].decode("utf-8")

            req_out_len = pb_utils.get_input_tensor_by_name(
                req, "REQUEST_OUTPUT_LEN"
            )
            out_len = req_out_len.as_numpy().flatten()[0]

            token_ids = self.tokenizer.encode(query_str, add_special_tokens=True)
            input_id = np.array([token_ids], dtype=np.int32)
            input_len = np.array([[len(token_ids)]], dtype=np.int32)
            out_len_arr = np.array([[out_len]], dtype=np.int32)
            end_id = np.array([[self._end_id]], dtype=np.int32)
            pad_id = np.array([[self.tokenizer.pad_token_id or 0]], dtype=np.int32)

            out_tensors = [
                pb_utils.Tensor("INPUT_ID", input_id),
                pb_utils.Tensor("REQUEST_INPUT_LEN", input_len),
                pb_utils.Tensor("REQUEST_OUTPUT_LEN", out_len_arr),
                pb_utils.Tensor("OUT_END_ID", end_id),
                pb_utils.Tensor("OUT_PAD_ID", pad_id),
            ]
            responses.append(
                pb_utils.InferenceResponse(output_tensors=out_tensors)
            )
        return responses

    def finalize(self):
        pass
