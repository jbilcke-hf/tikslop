[](#text-generation)Text Generation
-----------------------------------

Generate text based on a prompt.

If you are interested in a Chat Completion task, which generates a response based on a list of messages, check out the [`chat-completion`](./chat_completion) task.

For more details about the `text-generation` task, check out its [dedicated page](https://huggingface.co/tasks/text-generation)! You will find examples and related materials.

### [](#recommended-models)Recommended models

*   [google/gemma-2-2b-it](https://huggingface.co/google/gemma-2-2b-it): A text-generation model trained to follow instructions.
*   [deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B](https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B): Smaller variant of one of the most powerful models.
*   [meta-llama/Meta-Llama-3.1-8B-Instruct](https://huggingface.co/meta-llama/Meta-Llama-3.1-8B-Instruct): Very powerful text generation model trained to follow instructions.
*   [microsoft/phi-4](https://huggingface.co/microsoft/phi-4): Powerful text generation model by Microsoft.
*   [Qwen/Qwen2.5-7B-Instruct-1M](https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-1M): Strong conversational model that supports very long instructions.
*   [Qwen/Qwen2.5-Coder-32B-Instruct](https://huggingface.co/Qwen/Qwen2.5-Coder-32B-Instruct): Text generation model used to write code.
*   [deepseek-ai/DeepSeek-R1](https://huggingface.co/deepseek-ai/DeepSeek-R1): Powerful reasoning based open large language model.

Explore all available models and find the one that suits you best [here](https://huggingface.co/models?inference=warm&pipeline_tag=text-generation&sort=trending).

### [](#using-the-api)Using the API

Language

Python JavaScript cURL

Client

huggingface\_hub requests openai

Provider

Featherless Together AI

Settings

Settings

Settings

Copied

import os
from huggingface\_hub import InferenceClient

client = InferenceClient(
    provider="featherless-ai",
    api\_key=os.environ\["HF\_TOKEN"\],
)

completion = client.chat.completions.create(
    model="mistralai/Magistral-Small-2506",
    messages="\\"Can you please let us know more details about your \\"",
)

print(completion.choices\[0\].message)

### [](#api-specification)API specification

#### [](#request)Request

Headers

**authorization**

_string_

Authentication header in the form `'Bearer: hf_****'` when `hf_****` is a personal user access token with “Inference Providers” permission. You can generate one from [your settings page](https://huggingface.co/settings/tokens/new?ownUserPermissions=inference.serverless.write&tokenType=fineGrained).

Payload

**inputs\***

_string_

**parameters**

_object_

        **adapter\_id**

_string_

Lora adapter id

        **best\_of**

_integer_

Generate best\_of sequences and return the one if the highest token logprobs.

        **decoder\_input\_details**

_boolean_

Whether to return decoder input token logprobs and ids.

        **details**

_boolean_

Whether to return generation details.

        **do\_sample**

_boolean_

Activate logits sampling.

        **frequency\_penalty**

_number_

The parameter for frequency penalty. 1.0 means no penalty Penalize new tokens based on their existing frequency in the text so far, decreasing the model’s likelihood to repeat the same line verbatim.

        **grammar**

_unknown_

One of the following:

                 **(#1)**

_object_

                        **type\***

_enum_

Possible values: json.

                        **value\***

_unknown_

A string that represents a [JSON Schema](https://json-schema.org/). JSON Schema is a declarative language that allows to annotate JSON documents with types and descriptions.

                 **(#2)**

_object_

                        **type\***

_enum_

Possible values: regex.

                        **value\***

_string_

                 **(#3)**

_object_

                        **type\***

_enum_

Possible values: json\_schema.

                        **value\***

_object_

                                **name**

_string_

Optional name identifier for the schema

                                **schema\***

_unknown_

The actual JSON schema definition

        **max\_new\_tokens**

_integer_

Maximum number of tokens to generate.

        **repetition\_penalty**

_number_

The parameter for repetition penalty. 1.0 means no penalty. See [this paper](https://arxiv.org/pdf/1909.05858.pdf) for more details.

        **return\_full\_text**

_boolean_

Whether to prepend the prompt to the generated text

        **seed**

_integer_

Random sampling seed.

        **stop**

_string\[\]_

Stop generating tokens if a member of `stop` is generated.

        **temperature**

_number_

The value used to module the logits distribution.

        **top\_k**

_integer_

The number of highest probability vocabulary tokens to keep for top-k-filtering.

        **top\_n\_tokens**

_integer_

The number of highest probability vocabulary tokens to keep for top-n-filtering.

        **top\_p**

_number_

Top-p value for nucleus sampling.

        **truncate**

_integer_

Truncate inputs tokens to the given size.

        **typical\_p**

_number_

Typical Decoding mass See [Typical Decoding for Natural Language Generation](https://arxiv.org/abs/2202.00666) for more information.

        **watermark**

_boolean_

Watermarking with [A Watermark for Large Language Models](https://arxiv.org/abs/2301.10226).

**stream**

_boolean_

#### [](#response)Response

Output type depends on the `stream` input parameter. If `stream` is `false` (default), the response will be a JSON object with the following fields:

Body

**details**

_object_

        **best\_of\_sequences**

_object\[\]_

                **finish\_reason**

_enum_

Possible values: length, eos\_token, stop\_sequence.

                **generated\_text**

_string_

                **generated\_tokens**

_integer_

                **prefill**

_object\[\]_

                        **id**

_integer_

                        **logprob**

_number_

                        **text**

_string_

                **seed**

_integer_

                **tokens**

_object\[\]_

                        **id**

_integer_

                        **logprob**

_number_

                        **special**

_boolean_

                        **text**

_string_

                **top\_tokens**

_array\[\]_

                        **id**

_integer_

                        **logprob**

_number_

                        **special**

_boolean_

                        **text**

_string_

        **finish\_reason**

_enum_

Possible values: length, eos\_token, stop\_sequence.

        **generated\_tokens**

_integer_

        **prefill**

_object\[\]_

                **id**

_integer_

                **logprob**

_number_

                **text**

_string_

        **seed**

_integer_

        **tokens**

_object\[\]_

                **id**

_integer_

                **logprob**

_number_

                **special**

_boolean_

                **text**

_string_

        **top\_tokens**

_array\[\]_

                **id**

_integer_

                **logprob**

_number_

                **special**

_boolean_

                **text**

_string_

**generated\_text**

_string_

If `stream` is `true`, generated tokens are returned as a stream, using Server-Sent Events (SSE). For more information about streaming, check out [this guide](https://huggingface.co/docs/text-generation-inference/conceptual/streaming).

Body

**details**

_object_

        **finish\_reason**

_enum_

Possible values: length, eos\_token, stop\_sequence.

        **generated\_tokens**

_integer_

        **input\_length**

_integer_

        **seed**

_integer_

**generated\_text**

_string_

**index**

_integer_

**token**

_object_

        **id**

_integer_

        **logprob**

_number_

        **special**

_boolean_

        **text**

_string_

**top\_tokens**

_object\[\]_

        **id**

_integer_

        **logprob**

_number_

        **special**

_boolean_

        **text**

_string_

[< \> Update on GitHub](https://github.com/huggingface/hub-docs/blob/main/docs/inference-providers/tasks/text-generation.md)

Chat Completion