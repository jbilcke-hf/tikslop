---
title: AiTube2
emoji: 🍿
colorFrom: red
colorTo: red
sdk: docker
app_file: api.py
pinned: true
short_description: The Latent Video Platform
app_port: 8080
disable_embedding: false
hf_oauth: true
hf_oauth_expiration_minutes: 43200
hf_oauth_scopes:
  - inference-api
---


# AiTube2

## Configuration

### WebSocket Connection
- **Web Platform**: Automatically connects to the host serving the page (adapts to both HTTP/HTTPS)
- **Native Platforms**: 
  - Production: Uses `wss://aitube.at/ws` when built with `--dart-define=PRODUCTION_MODE=true`
  - Development: Uses `ws://localhost:8080/ws` by default
  - Custom: Set `API_WS_URL` during build with `--dart-define=API_WS_URL=ws://your-server:port/ws` (highest priority)

## News

aitube2 is coming sooner than expected!

Stay hooked at @flngr on X!


## What is AiTube?

AiTube 2 is a reboot of [AiTube 1](https://x.com/danielpikl/status/1737882643625078835), a project made in 2023 which generated AI videos in the background using LLM agents, to simulate an AI generated video platform.

In [AiTube 2](https://x.com/flngr/status/1864127796945011016), this concept is put upside down: now the content is generated on demand (when the user types something in the latent search input) and on the fly (video chunks are generated within a few seconds and streamed continuously).

This allows for new ways of consuming AI generated content, such as collaborative and interactive prompting.

# Where can I use it?

AiTube 2 is not ready yet: this is an experimental side project and the [platform](https://aitube.at), code and documentation will be in development for most of 2025.

# Why can't I use it?

As this is a personal project I only have limited ressources to develop it on the side, but there are also technological bottlenecks.

Right now it is not economically viable to operate a platform like AiTube, it requires hardware that is too expensive and/or not powerful enough to give an enjoyable and reactive streaming experience.

I am evaluating various options to make it available sooner for people with the financial ressources to try it, such as creating a system to deploy render nodes to Hugging Face, GPU-on-demand blockchains.. etc.

# When can I use it?

I estimate it will take up to 1 to 2 years for more powerful and/or cheaper hardware to become available.

I already have a open-source prototype of AiTube which I use for R&D, based on free (as in "can run on your own machine") AI video models that can run fast with low quality settings (such as LTX Video).

It's not representative of the final experience, but that's a start and I use that as a basis to imagine the experiences of the future (collaborative generation, broadcasted live streams, interactive gaming, and artistic experiences that are hybrid between video and gaming).
