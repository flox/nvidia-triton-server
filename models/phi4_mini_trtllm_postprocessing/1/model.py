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

    def execute(self, requests):
        responses = []
        for req in requests:
            tokens = pb_utils.get_input_tensor_by_name(
                req, "TOKENS_BATCH"
            ).as_numpy()
            seq_lens = pb_utils.get_input_tensor_by_name(
                req, "SEQUENCE_LENGTH"
            ).as_numpy()

            texts = []
            for batch_idx in range(tokens.shape[0]):
                for beam_idx in range(tokens.shape[1]):
                    seq_len = seq_lens[batch_idx][beam_idx]
                    token_ids = tokens[batch_idx][beam_idx][:seq_len].tolist()
                    text = self.tokenizer.decode(
                        token_ids, skip_special_tokens=True
                    )
                    texts.append(text)

            output = np.array(texts, dtype=object)
            responses.append(
                pb_utils.InferenceResponse(
                    output_tensors=[pb_utils.Tensor("OUTPUT", output)]
                )
            )
        return responses

    def finalize(self):
        pass
