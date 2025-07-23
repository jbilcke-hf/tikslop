[](#chat-completion)Chat Completion
-----------------------------------

Generate a response given a list of messages in a conversational context, supporting both conversational Language Models (LLMs) and conversational Vision-Language Models (VLMs). This is a subtask of [`text-generation`](https://huggingface.co/docs/inference-providers/tasks/text-generation) and [`image-text-to-text`](https://huggingface.co/docs/inference-providers/tasks/image-text-to-text).

### [](#recommended-models)Recommended models

#### [](#conversational-large-language-models-llms)Conversational Large Language Models (LLMs)

*   [google/gemma-2-2b-it](https://huggingface.co/google/gemma-2-2b-it): A text-generation model trained to follow instructions.
*   [deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B](https://huggingface.co/deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B): Smaller variant of one of the most powerful models.
*   [meta-llama/Meta-Llama-3.1-8B-Instruct](https://huggingface.co/meta-llama/Meta-Llama-3.1-8B-Instruct): Very powerful text generation model trained to follow instructions.
*   [microsoft/phi-4](https://huggingface.co/microsoft/phi-4): Powerful text generation model by Microsoft.
*   [Qwen/Qwen2.5-7B-Instruct-1M](https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-1M): Strong conversational model that supports very long instructions.
*   [Qwen/Qwen2.5-Coder-32B-Instruct](https://huggingface.co/Qwen/Qwen2.5-Coder-32B-Instruct): Text generation model used to write code.
*   [deepseek-ai/DeepSeek-R1](https://huggingface.co/deepseek-ai/DeepSeek-R1): Powerful reasoning based open large language model.

#### [](#conversational-vision-language-models-vlms)Conversational Vision-Language Models (VLMs)

*   [Qwen/Qwen2.5-VL-7B-Instruct](https://huggingface.co/Qwen/Qwen2.5-VL-7B-Instruct): Strong image-text-to-text model.

Explore all available models and find the one that suits you best [here](https://huggingface.co/models?inference=warm&pipeline_tag=image-text-to-text&sort=trending).

### [](#api-playground)API Playground

For Chat Completion models, we provide an interactive UI Playground for easier testing:

*   Quickly iterate on your prompts from the UI.
*   Set and override system, assistant and user messages.
*   Browse and select models currently available on the Inference API.
*   Compare the output of two models side-by-side.
*   Adjust requests parameters from the UI.
*   Easily switch between UI view and code snippets.

[![](https://cdn-uploads.huggingface.co/production/uploads/5f17f0a0925b9863e28ad517/9_Tgf0Tv65srhBirZQMTp.png)](https://huggingface.co/playground)

Access the Inference UI Playground and start exploring: [https://huggingface.co/playground](https://huggingface.co/playground)

### [](#using-the-api)Using the API

The API supports:

*   Using the chat completion API compatible with the OpenAI SDK.
*   Using grammars, constraints, and tools.
*   Streaming the output

#### [](#code-snippet-example-for-conversational-llms)Code snippet example for conversational LLMs

Language

Python JavaScript cURL

Client

huggingface\_hub requests openai

Provider

Featherless Nscale

+9

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
    model="meta-llama/Llama-3.3-70B-Instruct",
    messages=\[
        {
            "role": "user",
            "content": "What is the capital of France?"
        }
    \],
)

print(completion.choices\[0\].message)

#### [](#code-snippet-example-for-conversational-vlms)Code snippet example for conversational VLMs

Language

Python JavaScript cURL

Client

huggingface\_hub requests openai

Provider

Fireworks Featherless

+10

Settings

Settings

Settings

Copied

import os
from huggingface\_hub import InferenceClient

client = InferenceClient(
    provider="fireworks-ai",
    api\_key=os.environ\["HF\_TOKEN"\],
)

completion = client.chat.completions.create(
    model="meta-llama/Llama-4-Scout-17B-16E-Instruct",
    messages=\[
        {
            "role": "user",
            "content": \[
                {
                    "type": "text",
                    "text": "Describe this image in one sentence."
                },
                {
                    "type": "image\_url",
                    "image\_url": {
                        "url": "https://cdn.britannica.com/61/93061-050-99147DCE/Statue-of-Liberty-Island-New-York-Bay.jpg"
                    }
                }
            \]
        }
    \],
)

print(completion.choices\[0\].message)

### [](#api-specification)API specification

#### [](#request)Request

Headers

**authorization**

_string_

Authentication header in the form `'Bearer: hf_****'` when `hf_****` is a personal user access token with “Inference Providers” permission. You can generate one from [your settings page](https://huggingface.co/settings/tokens/new?ownUserPermissions=inference.serverless.write&tokenType=fineGrained).

Payload

**frequency\_penalty**

_number_

Number between -2.0 and 2.0. Positive values penalize new tokens based on their existing frequency in the text so far, decreasing the model’s likelihood to repeat the same line verbatim.

**logprobs**

_boolean_

Whether to return log probabilities of the output tokens or not. If true, returns the log probabilities of each output token returned in the content of message.

**max\_tokens**

_integer_

The maximum number of tokens that can be generated in the chat completion.

**messages\***

_object\[\]_

A list of messages comprising the conversation so far.

         **(#1)**

_unknown_

One of the following:

                 **(#1)**

_object_

                        **content\***

_unknown_

One of the following:

                                 **(#1)**

_string_

                                 **(#2)**

_object\[\]_

                                         **(#1)**

_object_

                                                **text\***

_string_

                                                **type\***

_enum_

Possible values: text.

                                         **(#2)**

_object_

                                                **image\_url\***

_object_

                                                        **url\***

_string_

                                                **type\***

_enum_

Possible values: image\_url.

                 **(#2)**

_object_

                        **tool\_calls\***

_object\[\]_

                                **function\***

_object_

                                        **parameters\***

_unknown_

                                        **description**

_string_

                                        **name\***

_string_

                                **id\***

_string_

                                **type\***

_string_

         **(#2)**

_object_

                **name**

_string_

                **role\***

_string_

**presence\_penalty**

_number_

Number between -2.0 and 2.0. Positive values penalize new tokens based on whether they appear in the text so far, increasing the model’s likelihood to talk about new topics

**response\_format**

_unknown_

One of the following:

         **(#1)**

_object_

                **type\***

_enum_

Possible values: text.

         **(#2)**

_object_

                **type\***

_enum_

Possible values: json\_schema.

                **json\_schema\***

_object_

                        **name\***

_string_

The name of the response format.

                        **description**

_string_

A description of what the response format is for, used by the model to determine how to respond in the format.

                        **schema**

_object_

The schema for the response format, described as a JSON Schema object. Learn how to build JSON schemas [here](https://json-schema.org/).

                        **strict**

_boolean_

Whether to enable strict schema adherence when generating the output. If set to true, the model will always follow the exact schema defined in the `schema` field.

         **(#3)**

_object_

                **type\***

_enum_

Possible values: json\_object.

**seed**

_integer_

**stop**

_string\[\]_

Up to 4 sequences where the API will stop generating further tokens.

**stream**

_boolean_

**stream\_options**

_object_

        **include\_usage**

_boolean_

If set, an additional chunk will be streamed before the data: \[DONE\] message. The usage field on this chunk shows the token usage statistics for the entire request, and the choices field will always be an empty array. All other chunks will also include a usage field, but with a null value.

**temperature**

_number_

What sampling temperature to use, between 0 and 2. Higher values like 0.8 will make the output more random, while lower values like 0.2 will make it more focused and deterministic. We generally recommend altering this or `top_p` but not both.

**tool\_choice**

_unknown_

One of the following:

         **(#1)**

_enum_

Possible values: auto.

         **(#2)**

_enum_

Possible values: none.

         **(#3)**

_enum_

Possible values: required.

         **(#4)**

_object_

                **function\***

_object_

                        **name\***

_string_

**tool\_prompt**

_string_

A prompt to be appended before the tools

**tools**

_object\[\]_

A list of tools the model may call. Currently, only functions are supported as a tool. Use this to provide a list of functions the model may generate JSON inputs for.

        **function\***

_object_

                **parameters\***

_unknown_

                **description**

_string_

                **name\***

_string_

        **type\***

_string_

**top\_logprobs**

_integer_

An integer between 0 and 5 specifying the number of most likely tokens to return at each token position, each with an associated log probability. logprobs must be set to true if this parameter is used.

**top\_p**

_number_

An alternative to sampling with temperature, called nucleus sampling, where the model considers the results of the tokens with top\_p probability mass. So 0.1 means only the tokens comprising the top 10% probability mass are considered.

#### [](#response)Response

Output type depends on the `stream` input parameter. If `stream` is `false` (default), the response will be a JSON object with the following fields:

Body

**choices**

_object\[\]_

        **finish\_reason**

_string_

        **index**

_integer_

        **logprobs**

_object_

                **content**

_object\[\]_

                        **logprob**

_number_

                        **token**

_string_

                        **top\_logprobs**

_object\[\]_

                                **logprob**

_number_

                                **token**

_string_

        **message**

_unknown_

One of the following:

                 **(#1)**

_object_

                        **content**

_string_

                        **role**

_string_

                        **tool\_call\_id**

_string_

                 **(#2)**

_object_

                        **role**

_string_

                        **tool\_calls**

_object\[\]_

                                **function**

_object_

                                        **arguments**

_string_

                                        **description**

_string_

                                        **name**

_string_

                                **id**

_string_

                                **type**

_string_

**created**

_integer_

**id**

_string_

**model**

_string_

**system\_fingerprint**

_string_

**usage**

_object_

        **completion\_tokens**

_integer_

        **prompt\_tokens**

_integer_

        **total\_tokens**

_integer_

If `stream` is `true`, generated tokens are returned as a stream, using Server-Sent Events (SSE). For more information about streaming, check out [this guide](https://huggingface.co/docs/text-generation-inference/conceptual/streaming).

Body

**choices**

_object\[\]_

        **delta**

_unknown_

One of the following:

                 **(#1)**

_object_

                        **content**

_string_

                        **role**

_string_

                        **tool\_call\_id**

_string_

                 **(#2)**

_object_

                        **role**

_string_

                        **tool\_calls**

_object\[\]_

                                **function**

_object_

                                        **arguments**

_string_

                                        **name**

_string_

                                **id**

_string_

                                **index**

_integer_

                                **type**

_string_

        **finish\_reason**

_string_

        **index**

_integer_

        **logprobs**

_object_

                **content**

_object\[\]_

                        **logprob**

_number_

                        **token**

_string_

                        **top\_logprobs**

_object\[\]_

                                **logprob**

_number_

                                **token**

_string_

**created**

_integer_

**id**

_string_

**model**

_string_

**system\_fingerprint**

_string_

**usage**

_object_

        **completion\_tokens**

_integer_

        **prompt\_tokens**

_integer_

        **total\_tokens**

_integer_

[< \> Update on GitHub](https://github.com/huggingface/hub-docs/blob/main/docs/inference-providers/tasks/chat-completion.md)