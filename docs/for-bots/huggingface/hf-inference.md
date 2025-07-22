[](#run-inference-on-servers)Run Inference on servers
=====================================================

Inference is the process of using a trained model to make predictions on new data. Because this process can be compute-intensive, running on a dedicated or external service can be an interesting option. The `huggingface_hub` library provides a unified interface to run inference across multiple services for models hosted on the Hugging Face Hub:

1.  [Inference Providers](https://huggingface.co/docs/inference-providers/index): a streamlined, unified access to hundreds of machine learning models, powered by our serverless inference partners. This new approach builds on our previous Serverless Inference API, offering more models, improved performance, and greater reliability thanks to world-class providers. Refer to the [documentation](https://huggingface.co/docs/inference-providers/index#partners) for a list of supported providers.
2.  [Inference Endpoints](https://huggingface.co/docs/inference-endpoints/index): a product to easily deploy models to production. Inference is run by Hugging Face in a dedicated, fully managed infrastructure on a cloud provider of your choice.
3.  Local endpoints: you can also run inference with local inference servers like [llama.cpp](https://github.com/ggerganov/llama.cpp), [Ollama](https://ollama.com/), [vLLM](https://github.com/vllm-project/vllm), [LiteLLM](https://docs.litellm.ai/docs/simple_proxy), or [Text Generation Inference (TGI)](https://github.com/huggingface/text-generation-inference) by connecting the client to these local endpoints.

These services can all be called from the [InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient) object. It acts as a replacement for the legacy [InferenceApi](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceApi) client, adding specific support for tasks and third-party providers. Learn how to migrate to the new client in the [Legacy InferenceAPI client](#legacy-inferenceapi-client) section.

[InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient) is a Python client making HTTP calls to our APIs. If you want to make the HTTP calls directly using your preferred tool (curl, postman,…), please refer to the [Inference Providers](https://huggingface.co/docs/inference-providers/index) documentation or to the [Inference Endpoints](https://huggingface.co/docs/inference-endpoints/index) documentation pages.

For web development, a [JS client](https://huggingface.co/docs/huggingface.js/inference/README) has been released. If you are interested in game development, you might have a look at our [C# project](https://github.com/huggingface/unity-api).

[](#getting-started)Getting started
-----------------------------------

Let’s get started with a text-to-image task:

Copied

\>>> from huggingface\_hub import InferenceClient

\# Example with an external provider (e.g. replicate)
\>>> replicate\_client = InferenceClient(
    provider="replicate",
    api\_key="my\_replicate\_api\_key",
)
\>>> replicate\_image = replicate\_client.text\_to\_image(
    "A flying car crossing a futuristic cityscape.",
    model="black-forest-labs/FLUX.1-schnell",
)
\>>> replicate\_image.save("flying\_car.png")

In the example above, we initialized an [InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient) with a third-party provider, [Replicate](https://replicate.com/). When using a provider, you must specify the model you want to use. The model id must be the id of the model on the Hugging Face Hub, not the id of the model from the third-party provider. In our example, we generated an image from a text prompt. The returned value is a `PIL.Image` object that can be saved to a file. For more details, check out the [text\_to\_image()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.text_to_image) documentation.

Let’s now see an example using the [chat\_completion()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.chat_completion) API. This task uses an LLM to generate a response from a list of messages:

Copied

\>>> from huggingface\_hub import InferenceClient
\>>> messages = \[
    {
        "role": "user",
        "content": "What is the capital of France?",
    }
\]
\>>> client = InferenceClient(
    provider="together",
    model="meta-llama/Meta-Llama-3-8B-Instruct",
    api\_key="my\_together\_api\_key",
)
\>>> client.chat\_completion(messages, max\_tokens=100)
ChatCompletionOutput(
    choices=\[
        ChatCompletionOutputComplete(
            finish\_reason="eos\_token",
            index=0,
            message=ChatCompletionOutputMessage(
                role="assistant", content="The capital of France is Paris.", name=None, tool\_calls=None
            ),
            logprobs=None,
        )
    \],
    created=1719907176,
    id\="",
    model="meta-llama/Meta-Llama-3-8B-Instruct",
    object\="text\_completion",
    system\_fingerprint="2.0.4-sha-f426a33",
    usage=ChatCompletionOutputUsage(completion\_tokens=8, prompt\_tokens=17, total\_tokens=25),
)

In the example above, we used a third-party provider ([Together AI](https://www.together.ai/)) and specified which model we want to use (`"meta-llama/Meta-Llama-3-8B-Instruct"`). We then gave a list of messages to complete (here, a single question) and passed an additional parameter to the API (`max_token=100`). The output is a `ChatCompletionOutput` object that follows the OpenAI specification. The generated content can be accessed with `output.choices[0].message.content`. For more details, check out the [chat\_completion()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.chat_completion) documentation.

The API is designed to be simple. Not all parameters and options are available or described for the end user. Check out [this page](https://huggingface.co/docs/api-inference/detailed_parameters) if you are interested in learning more about all the parameters available for each task.

### [](#using-a-specific-provider)Using a specific provider

If you want to use a specific provider, you can specify it when initializing the client. The default value is “auto” which will select the first of the providers available for the model, sorted by the user’s order in [https://hf.co/settings/inference-providers](https://hf.co/settings/inference-providers). Refer to the [Supported providers and tasks](#supported-providers-and-tasks) section for a list of supported providers.

Copied

\>>> from huggingface\_hub import InferenceClient
\>>> client = InferenceClient(provider="replicate", api\_key="my\_replicate\_api\_key")

### [](#using-a-specific-model)Using a specific model

What if you want to use a specific model? You can specify it either as a parameter or directly at an instance level:

Copied

\>>> from huggingface\_hub import InferenceClient
\# Initialize client for a specific model
\>>> client = InferenceClient(provider="together", model="meta-llama/Llama-3.1-8B-Instruct")
\>>> client.text\_to\_image(...)
\# Or use a generic client but pass your model as an argument
\>>> client = InferenceClient(provider="together")
\>>> client.text\_to\_image(..., model="meta-llama/Llama-3.1-8B-Instruct")

When using the “hf-inference” provider, each task comes with a recommended model from the 1M+ models available on the Hub. However, this recommendation can change over time, so it’s best to explicitly set a model once you’ve decided which one to use. For third-party providers, you must always specify a model that is compatible with that provider.

Visit the [Models](https://huggingface.co/models?inference=warm) page on the Hub to explore models available through Inference Providers.

### [](#using-inference-endpoints)Using Inference Endpoints

The examples we saw above use inference providers. While these prove to be very useful for prototyping and testing things quickly. Once you’re ready to deploy your model to production, you’ll need to use a dedicated infrastructure. That’s where [Inference Endpoints](https://huggingface.co/docs/inference-endpoints/index) comes into play. It allows you to deploy any model and expose it as a private API. Once deployed, you’ll get a URL that you can connect to using exactly the same code as before, changing only the `model` parameter:

Copied

\>>> from huggingface\_hub import InferenceClient
\>>> client = InferenceClient(model="https://uu149rez6gw9ehej.eu-west-1.aws.endpoints.huggingface.cloud/deepfloyd-if")
\# or
\>>> client = InferenceClient()
\>>> client.text\_to\_image(..., model="https://uu149rez6gw9ehej.eu-west-1.aws.endpoints.huggingface.cloud/deepfloyd-if")

Note that you cannot specify both a URL and a provider - they are mutually exclusive. URLs are used to connect directly to deployed endpoints.

### [](#using-local-endpoints)Using local endpoints

You can use [InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient) to run chat completion with local inference servers (llama.cpp, vllm, litellm server, TGI, mlx, etc.) running on your own machine. The API should be OpenAI API-compatible.

Copied

\>>> from huggingface\_hub import InferenceClient
\>>> client = InferenceClient(model="http://localhost:8080")

\>>> response = client.chat.completions.create(
...     messages=\[
...         {"role": "user", "content": "What is the capital of France?"}
...     \],
...     max\_tokens=100
... )
\>>> print(response.choices\[0\].message.content)

Similarily to the OpenAI Python client, [InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient) can be used to run Chat Completion inference with any OpenAI REST API-compatible endpoint.

### [](#authentication)Authentication

Authentication can be done in two ways:

**Routed through Hugging Face** : Use Hugging Face as a proxy to access third-party providers. The calls will be routed through Hugging Face’s infrastructure using our provider keys, and the usage will be billed directly to your Hugging Face account.

You can authenticate using a [User Access Token](https://huggingface.co/docs/hub/security-tokens). You can provide your Hugging Face token directly using the `api_key` parameter:

Copied

\>>> client = InferenceClient(
    provider="replicate",
    api\_key="hf\_\*\*\*\*"  \# Your HF token
)

If you _don’t_ pass an `api_key`, the client will attempt to find and use a token stored locally on your machine. This typically happens if you’ve previously logged in. See the [Authentication Guide](https://huggingface.co/docs/huggingface_hub/quick-start#authentication) for details on login.

Copied

\>>> client = InferenceClient(
    provider="replicate",
    token="hf\_\*\*\*\*"  \# Your HF token
)

**Direct access to provider**: Use your own API key to interact directly with the provider’s service:

Copied

\>>> client = InferenceClient(
    provider="replicate",
    api\_key="r8\_\*\*\*\*"  \# Your Replicate API key
)

For more details, refer to the [Inference Providers pricing documentation](https://huggingface.co/docs/inference-providers/pricing#routed-requests-vs-direct-calls).

[](#supported-providers-and-tasks)Supported providers and tasks
---------------------------------------------------------------

[InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient)’s goal is to provide the easiest interface to run inference on Hugging Face models, on any provider. It has a simple API that supports the most common tasks. Here is a table showing which providers support which tasks:

Task

Black Forest Labs

Cerebras

Cohere

fal-ai

Featherless AI

Fireworks AI

Groq

HF Inference

Hyperbolic

Nebius AI Studio

Novita AI

Replicate

Sambanova

Together

[audio\_classification()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.audio_classification)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[audio\_to\_audio()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.audio_to_audio)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[automatic\_speech\_recognition()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.automatic_speech_recognition)

❌

❌

❌

✅

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[chat\_completion()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.chat_completion)

❌

✅

✅

❌

✅

✅

✅

✅

✅

✅

✅

❌

✅

✅

[document\_question\_answering()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.document_question_answering)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[feature\_extraction()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.feature_extraction)

❌

❌

❌

❌

❌

❌

❌

✅

❌

✅

❌

❌

✅

❌

[fill\_mask()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.fill_mask)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[image\_classification()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.image_classification)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[image\_segmentation()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.image_segmentation)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[image\_to\_image()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.image_to_image)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[image\_to\_text()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.image_to_text)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[object\_detection()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.object_detection)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[question\_answering()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.question_answering)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[sentence\_similarity()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.sentence_similarity)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[summarization()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.summarization)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[table\_question\_answering()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.table_question_answering)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[text\_classification()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.text_classification)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[text\_generation()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.text_generation)

❌

❌

❌

❌

✅

❌

❌

✅

✅

✅

✅

❌

❌

✅

[text\_to\_image()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.text_to_image)

✅

❌

❌

✅

❌

❌

❌

✅

✅

✅

❌

✅

❌

✅

[text\_to\_speech()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.text_to_speech)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

✅

❌

❌

[text\_to\_video()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.text_to_video)

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

[tabular\_classification()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.tabular_classification)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[tabular\_regression()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.tabular_regression)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[token\_classification()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.token_classification)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[translation()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.translation)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[visual\_question\_answering()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.visual_question_answering)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[zero\_shot\_image\_classification()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.zero_shot_image_classification)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

[zero\_shot\_classification()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.zero_shot_classification)

❌

❌

❌

❌

❌

❌

❌

✅

❌

❌

❌

❌

❌

❌

Check out the [Tasks](https://huggingface.co/tasks) page to learn more about each task.

[](#openai-compatibility)OpenAI compatibility
---------------------------------------------

The `chat_completion` task follows [OpenAI’s Python client](https://github.com/openai/openai-python) syntax. What does it mean for you? It means that if you are used to play with `OpenAI`’s APIs you will be able to switch to `huggingface_hub.InferenceClient` to work with open-source models by updating just 2 line of code!

Copied

\- from openai import OpenAI
\+ from huggingface\_hub import InferenceClient

\- client = OpenAI(
\+ client = InferenceClient(
    base\_url=...,
    api\_key=...,
)


output = client.chat.completions.create(
    model="meta-llama/Meta-Llama-3-8B-Instruct",
    messages=\[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Count to 10"},
    \],
    stream=True,
    max\_tokens=1024,
)

for chunk in output:
    print(chunk.choices\[0\].delta.content)

And that’s it! The only required changes are to replace `from openai import OpenAI` by `from huggingface_hub import InferenceClient` and `client = OpenAI(...)` by `client = InferenceClient(...)`. You can choose any LLM model from the Hugging Face Hub by passing its model id as `model` parameter. [Here is a list](https://huggingface.co/models?pipeline_tag=text-generation&other=conversational,text-generation-inference&sort=trending) of supported models. For authentication, you should pass a valid [User Access Token](https://huggingface.co/settings/tokens) as `api_key` or authenticate using `huggingface_hub` (see the [authentication guide](https://huggingface.co/docs/huggingface_hub/quick-start#authentication)).

All input parameters and output format are strictly the same. In particular, you can pass `stream=True` to receive tokens as they are generated. You can also use the [AsyncInferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.AsyncInferenceClient) to run inference using `asyncio`:

Copied

import asyncio
\- from openai import AsyncOpenAI
\+ from huggingface\_hub import AsyncInferenceClient

\- client = AsyncOpenAI()
\+ client = AsyncInferenceClient()

async def main():
    stream = await client.chat.completions.create(
        model="meta-llama/Meta-Llama-3-8B-Instruct",
        messages=\[{"role": "user", "content": "Say this is a test"}\],
        stream=True,
    )
    async for chunk in stream:
        print(chunk.choices\[0\].delta.content or "", end="")

asyncio.run(main())

You might wonder why using [InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient) instead of OpenAI’s client? There are a few reasons for that:

1.  [InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient) is configured for Hugging Face services. You don’t need to provide a `base_url` to run models with Inference Providers. You also don’t need to provide a `token` or `api_key` if your machine is already correctly logged in.
2.  [InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient) is tailored for both Text-Generation-Inference (TGI) and `transformers` frameworks, meaning you are assured it will always be on-par with the latest updates.
3.  [InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient) is integrated with our Inference Endpoints service, making it easier to launch an Inference Endpoint, check its status and run inference on it. Check out the [Inference Endpoints](./inference_endpoints.md) guide for more details.

`InferenceClient.chat.completions.create` is simply an alias for `InferenceClient.chat_completion`. Check out the package reference of [chat\_completion()](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient.chat_completion) for more details. `base_url` and `api_key` parameters when instantiating the client are also aliases for `model` and `token`. These aliases have been defined to reduce friction when switching from `OpenAI` to `InferenceClient`.

[](#function-calling)Function Calling
-------------------------------------

Function calling allows LLMs to interact with external tools, such as defined functions or APIs. This enables users to easily build applications tailored to specific use cases and real-world tasks. `InferenceClient` implements the same tool calling interface as the OpenAI Chat Completions API. Here is a simple example of tool calling using [Nebius](https://nebius.com/) as the inference provider:

Copied

from huggingface\_hub import InferenceClient

tools = \[
        {
            "type": "function",
            "function": {
                "name": "get\_weather",
                "description": "Get current temperature for a given location.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "location": {
                            "type": "string",
                            "description": "City and country e.g. Paris, France"
                        }
                    },
                    "required": \["location"\],
                },
            }
        }
\]

client = InferenceClient(provider="nebius")

response = client.chat.completions.create(
    model="Qwen/Qwen2.5-72B-Instruct",
    messages=\[
    {
        "role": "user",
        "content": "What's the weather like the next 3 days in London, UK?"
    }
    \],
    tools=tools,
    tool\_choice="auto",
)

print(response.choices\[0\].message.tool\_calls\[0\].function.arguments)

Please refer to the providers’ documentation to verify which models are supported by them for Function/Tool Calling.

[](#structured-outputs--json-mode)Structured Outputs & JSON Mode
----------------------------------------------------------------

InferenceClient supports JSON mode for syntactically valid JSON responses and Structured Outputs for schema-enforced responses. JSON mode provides machine-readable data without strict structure, while Structured Outputs guarantee both valid JSON and adherence to a predefined schema for reliable downstream processing.

We follow the OpenAI API specs for both JSON mode and Structured Outputs. You can enable them via the `response_format` argument. Here is an example of Structured Outputs using [Cerebras](https://www.cerebras.ai/) as the inference provider:

Copied

from huggingface\_hub import InferenceClient

json\_schema = {
    "name": "book",
    "schema": {
        "properties": {
            "name": {
                "title": "Name",
                "type": "string",
            },
            "authors": {
                "items": {"type": "string"},
                "title": "Authors",
                "type": "array",
            },
        },
        "required": \["name", "authors"\],
        "title": "Book",
        "type": "object",
    },
    "strict": True,
}

client = InferenceClient(provider="cerebras")


completion = client.chat.completions.create(
    model="Qwen/Qwen3-32B",
    messages=\[
        {"role": "system", "content": "Extract the books information."},
        {"role": "user", "content": "I recently read 'The Great Gatsby' by F. Scott Fitzgerald."},
    \],
    response\_format={
        "type": "json\_schema",
        "json\_schema": json\_schema,
    },
)

print(completion.choices\[0\].message)

Please refer to the providers’ documentation to verify which models are supported by them for Structured Outputs and JSON Mode.

[](#async-client)Async client
-----------------------------

An async version of the client is also provided, based on `asyncio` and `aiohttp`. You can either install `aiohttp` directly or use the `[inference]` extra:

Copied

pip install --upgrade huggingface\_hub\[inference\]
\# or
\# pip install aiohttp

After installation all async API endpoints are available via [AsyncInferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.AsyncInferenceClient). Its initialization and APIs are strictly the same as the sync-only version.

Copied

\# Code must be run in an asyncio concurrent context.
\# $ python -m asyncio
\>>> from huggingface\_hub import AsyncInferenceClient
\>>> client = AsyncInferenceClient()

\>>> image = await client.text\_to\_image("An astronaut riding a horse on the moon.")
\>>> image.save("astronaut.png")

\>>> async for token in await client.text\_generation("The Huggingface Hub is", stream=True):
...     print(token, end="")
 a platform for sharing and discussing ML-related content.

For more information about the `asyncio` module, please refer to the [official documentation](https://docs.python.org/3/library/asyncio.html).

[](#mcp-client)MCP Client
-------------------------

The `huggingface_hub` library now includes an experimental [MCPClient](/docs/huggingface_hub/v0.33.4/en/package_reference/mcp#huggingface_hub.MCPClient), designed to empower Large Language Models (LLMs) with the ability to interact with external Tools via the [Model Context Protocol](https://modelcontextprotocol.io) (MCP). This client extends an [AsyncInferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.AsyncInferenceClient) to seamlessly integrate Tool usage.

The [MCPClient](/docs/huggingface_hub/v0.33.4/en/package_reference/mcp#huggingface_hub.MCPClient) connects to MCP servers (either local `stdio` scripts or remote `http`/`sse` services) that expose tools. It feeds these tools to an LLM (via [AsyncInferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.AsyncInferenceClient)). If the LLM decides to use a tool, [MCPClient](/docs/huggingface_hub/v0.33.4/en/package_reference/mcp#huggingface_hub.MCPClient) manages the execution request to the MCP server and relays the Tool’s output back to the LLM, often streaming results in real-time.

In the following example, we use [Qwen/Qwen2.5-72B-Instruct](https://huggingface.co/Qwen/Qwen2.5-72B-Instruct) model via [Nebius](https://nebius.com/) inference provider. We then add a remote MCP server, in this case, an SSE server which made the Flux image generation tool available to the LLM.

Copied

import os

from huggingface\_hub import ChatCompletionInputMessage, ChatCompletionStreamOutput, MCPClient

async def main():
    async with MCPClient(
        provider="nebius",
        model="Qwen/Qwen2.5-72B-Instruct",
        api\_key=os.environ\["HF\_TOKEN"\],
    ) as client:
        await client.add\_mcp\_server(type\="sse", url="https://evalstate-flux1-schnell.hf.space/gradio\_api/mcp/sse")

        messages = \[
            {
                "role": "user",
                "content": "Generate a picture of a cat on the moon",
            }
        \]

        async for chunk in client.process\_single\_turn\_with\_tools(messages):
            \# Log messages
            if isinstance(chunk, ChatCompletionStreamOutput):
                delta = chunk.choices\[0\].delta
                if delta.content:
                    print(delta.content, end="")

            \# Or tool calls
            elif isinstance(chunk, ChatCompletionInputMessage):
                print(
                    f"\\nCalled tool '{chunk.name}'. Result: '{chunk.content if len(chunk.content) < 1000 else chunk.content\[:1000\] + '...'}'"
                )

if \_\_name\_\_ == "\_\_main\_\_":
    import asyncio

    asyncio.run(main())

For even simpler development, we offer a higher-level [Agent](/docs/huggingface_hub/v0.33.4/en/package_reference/mcp#huggingface_hub.Agent) class. This ‘Tiny Agent’ simplifies creating conversational Agents by managing the chat loop and state, essentially acting as a wrapper around [MCPClient](/docs/huggingface_hub/v0.33.4/en/package_reference/mcp#huggingface_hub.MCPClient). It’s designed to be a simple while loop built right on top of an [MCPClient](/docs/huggingface_hub/v0.33.4/en/package_reference/mcp#huggingface_hub.MCPClient). You can run these Agents directly from the command line:

Copied

\# install latest version of huggingface\_hub with the mcp extra
pip install -U huggingface\_hub\[mcp\]
\# Run an agent that uses the Flux image generation tool
tiny-agents run julien-c/flux-schnell-generator

When launched, the Agent will load, list the Tools it has discovered from its connected MCP servers, and then it’s ready for your prompts!

[](#advanced-tips)Advanced tips
-------------------------------

In the above section, we saw the main aspects of [InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient). Let’s dive into some more advanced tips.

### [](#billing)Billing

As an HF user, you get monthly credits to run inference through various providers on the Hub. The amount of credits you get depends on your type of account (Free or PRO or Enterprise Hub). You get charged for every inference request, depending on the provider’s pricing table. By default, the requests are billed to your personal account. However, it is possible to set the billing so that requests are charged to an organization you are part of by simply passing `bill_to="<your_org_name>"` to `InferenceClient`. For this to work, your organization must be subscribed to Enterprise Hub. For more details about billing, check out [this guide](https://huggingface.co/docs/api-inference/pricing#features-using-inference-providers).

Copied

\>>> from huggingface\_hub import InferenceClient
\>>> client = InferenceClient(provider="fal-ai", bill\_to="openai")
\>>> image = client.text\_to\_image(
...     "A majestic lion in a fantasy forest",
...     model="black-forest-labs/FLUX.1-schnell",
... )
\>>> image.save("lion.png")

Note that it is NOT possible to charge another user or an organization you are not part of. If you want to grant someone else some credits, you must create a joint organization with them.

### [](#timeout)Timeout

Inference calls can take a significant amount of time. By default, [InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient) will wait “indefinitely” until the inference complete. If you want more control in your workflow, you can set the `timeout` parameter to a specific value in seconds. If the timeout delay expires, an [InferenceTimeoutError](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceTimeoutError) is raised, which you can catch in your code:

Copied

\>>> from huggingface\_hub import InferenceClient, InferenceTimeoutError
\>>> client = InferenceClient(timeout=30)
\>>> try:
...     client.text\_to\_image(...)
... except InferenceTimeoutError:
...     print("Inference timed out after 30s.")

### [](#binary-inputs)Binary inputs

Some tasks require binary inputs, for example, when dealing with images or audio files. In this case, [InferenceClient](/docs/huggingface_hub/v0.33.4/en/package_reference/inference_client#huggingface_hub.InferenceClient) tries to be as permissive as possible and accept different types:

*   raw `bytes`
*   a file-like object, opened as binary (`with open("audio.flac", "rb") as f: ...`)
*   a path (`str` or `Path`) pointing to a local file
*   a URL (`str`) pointing to a remote file (e.g. `https://...`). In this case, the file will be downloaded locally before being sent to the API.

Copied

\>>> from huggingface\_hub import InferenceClient
\>>> client = InferenceClient()
\>>> client.image\_classification("https://upload.wikimedia.org/wikipedia/commons/thumb/4/43/Cute\_dog.jpg/320px-Cute\_dog.jpg")
\[{'score': 0.9779096841812134, 'label': 'Blenheim spaniel'}, ...\]

[< \> Update on GitHub](https://github.com/huggingface/huggingface_hub/blob/main/docs/source/en/guides/inference.md)