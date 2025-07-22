GENERAL CONTEXT:

TikSlop is an app where users can generate videos using AI. What is interesting is that both search results are generated (so there is no actual search in a DB, instead a LLM hallucinate search result items, simulation a video platform à la YouTube), but also the video streams (a video is composed of an infinite stream of a few seconds long MP4 clips, that are also generated using AI, using a fast generative model that works in nearly real-time, eg it takes 4s to generate 2s of footage).

The architecture is simple: a Flutter frontend UI with two main view (home_screen.dart for search, video_screen.dart for the ifinite video stream player). The frontend UI talks to a Python API (see api.py) using WebSockets, as we have various real-time communication needs (chat, streaming of MP4 chunks etc). This Python API is responsible for performing the actual calls to the generative video model and the LLM model (those are external servers hosted on Hugging Face, but explaining how they work is outside the scope of this documentation).

There is a simulator integrated, which evolves a description (video prompt) over time, using a LLM.

Users can be anonymous, but if they connect using a Hugging Face API key, they get some extra perks.

TASK:


Note: For the task to be validated, running the shell command "flutter build web" must succeeed.