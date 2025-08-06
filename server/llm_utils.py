"""
LLM-related utilities, templates, and text generation functions.
"""
import asyncio
import logging
from typing import Optional, Dict, Any
from huggingface_hub import InferenceClient
from .api_config import HF_TOKEN, TEXT_MODEL

logger = logging.getLogger(__name__)


# LLM prompt templates
SEARCH_VIDEO_PROMPT_TEMPLATE = """# Instruction
Your response MUST be a YAML object containing a title and description, consistent with what we can find on a video sharing platform.
Format your YAML response with only those fields: "title" (a short string) and "description" (string caption of the scene). Do not add any other field.
In the description field, describe in a very synthetic way the visuals of the first shot (first scene), eg "<STYLE>, medium close-up shot, high angle view. In the foreground a <OPTIONAL AGE> <OPTIONAL GENDER> <CHARACTERS> <ACTIONS>. In the background <DESCRIBE LOCATION, BACKGROUND CHARACTERS, OBJECTS ETC>. The scene is lit by <LIGHTING> <WEATHER>". This is just an example! you MUST replace the <TAGS>!!.
Don't forget to replace <STYLE> etc, by the actual fields!!
For the style, be creative, for instance you can use anything like a "documentary footage", "japanese animation", "movie scene", "tv series", "tv show", "security footage" etc.
If the user ask for something specific eg "movie screencap", "movie scene", "documentary footage" "animation" as a style etc.
Keep it minimalist but still descriptive, don't use bullets points, use simple words, go to the essential to describe style (cinematic, documentary footage, 3D rendering..), camera modes and angles, characters, age, gender, action, location, lighting, country, costume, time, weather, textures, color palette.. etc). Write about 80 words, and use between 2 and 3 sentences.
The most import part is to describe the actions and movements in the scene, so don't forget that!
Don't describe sound, never say things like "atmospheric music playing in the background".
Only describe the visual elements, be precise, (if there are anything, cars, objects, people, bricks, birds, clouds, trees, leaves or grass then make sure to include it in your caption).
Make the result unique and different from previous search results. ONLY RETURN YAML AND WITH ENGLISH CONTENT, NOT CHINESE - DO NOT ADD YOU OWN OBSERVATIONS, INTERPREATIONS OR PERSONAL COMMENT!

# Context
This is attempt {current_attempt}.

# Input
Describe the first scene/shot for: "{query}".

# Output

```yaml
title: \""""

GENERATE_CAPTION_PROMPT_TEMPLATE = """Generate a detailed story for a video named: "{title}"
Visual description of the video: {description}.
Instructions: Write the story summary, including the plot, action, what should happen.
Make it around 200-300 words long.
A video can be anything from a tutorial, webcam, trailer, movie, live stream etc."""

SIMULATE_VIDEO_FIRST_PROMPT_TEMPLATE = """You are tasked with evolving the narrative for a video titled: "{original_title}"

Original description:
{original_description}
{chat_section}

Instructions:
1. Imagine the next logical scene or development that would follow the current description.
2. Consider the video context and recent events
3. Create a natural progression from previous clips
4. Take into account user suggestions (chat messages) into the scene
5. IMPORTANT: viewers have shared messages, consider their input in priority to guide your story, and incorporate relevant suggestions or reactions into your narrative evolution.
6. Keep visual consistency with previous clips (in most cases you should repeat the same exact and detailed description of the location, characters etc but only change a few elements. If this is a webcam scenario, don't touch the camera orientation or focus)
7. Return ONLY the caption text, no additional formatting or explanation
8. Write in English, about 200 words.
9. Keep the visual style consistant, but content as well (repeat the style, character, locations, appearance etc..from the previous description, when it makes sense).
10. Your caption must describe visual elements of the scene in extreme details, including: camera angle and focus, people's appearance, age, look, costumes, clothes, the location visual characteristics and geometry, lighting, action, objects, weather, textures, lighting.
11. Please write in the same style as the original description, by keeping things brief etc.

Remember to obey to what users said in the chat history!!

Now, you must write down the new scene description (don't write a long story! write a synthetic description!):"""

SIMULATE_VIDEO_CONTINUE_PROMPT_TEMPLATE = """You are tasked with continuing to evolve the narrative for a video titled: "{original_title}"

Original description:
{original_description}

Condensed history of scenes so far:
{condensed_history}

Current description (most recent scene):
{current_description}
{chat_section}

Instructions:
1. Imagine the next logical scene or development that would follow the current description.
2. Consider the video context and recent events
3. Create a natural progression from previous clips
4. Take into account user suggestions (chat messages) into the scene
5. IMPORTANT: if viewers have shared messages, consider their input in priority to guide your story, and incorporate relevant suggestions or reactions into your narrative evolution.
6. Keep visual consistency with previous clips (in most cases you should repeat the same exact description of the location, characters etc but only change a few elements. If this is a webcam scenario, don't touch the camera orientation or focus)
7. Return ONLY the caption text, no additional formatting or explanation
8. Write in English, about 200 words.
9. Keep the visual style consistant, descriptive, detailed, but content as well (repeat the style, character, locations, appearance etc..from the previous description, when it makes sense).
10. Your caption must describe visual elements of the scene in extreme details, including: camera angle and focus, people's appearance, age, look, costumes, clothes, the location visual characteristics and geometry, lighting, action, objects, weather, textures, lighting.
11. Please write in the same style as the original description, by keeping things brief etc.

Remember to obey to what users said in the chat history!!

Now, you must write down the new scene description (don't write a long story! write a synthetic description!):"""

GENERATE_CLIP_PROMPT_TEMPLATE = """# Context and task
Please write the caption for a new clip.

# Instructions
1. Consider the video context and recent events
2. Create a natural progression from previous clips
3. Take into account user suggestions (chat messages) into the scene
4. Don't generate hateful, political, violent or sexual content
5. Keep visual consistency with previous clips (in most cases you should repeat the same exact description of the location, characters etc but only change a few elements. If this is a webcam scenario, don't touch the camera orientation or focus)
6. Return ONLY the caption text, no additional formatting or explanation
7. Write in English, about 200 words.
8. Keep the visual style consistant, but content as well (repeat the style, character, locations, appearance etc.. across scenes, when it makes sense).
8. Your caption must describe visual elements of the scene in details, including: camera angle and focus, people's appearance, age, look, costumes, clothes, the location visual characteristics and geometry, lighting, action, objects, weather, textures, lighting.

# Examples
Here is a demo scenario, with fake data:
{{"time": "2024-11-29T13:36:15Z", "event": "new_stream_clip", "caption": "webcam view of a beautiful park, squirrels are playing in the lush grass, blablabla etc... (rest omitted for brevity)"}}
{{"time": "2024-11-29T13:36:20Z", "event": "new_chat_message", "username": "MonkeyLover89", "data": "hi"}}
{{"time": "2024-11-29T13:36:25Z", "event": "new_chat_message", "username": "MonkeyLover89", "data": "more squirrels plz"}}
{{"time": "2024-11-29T13:36:26Z", "event": "new_stream_clip", "caption": "webcam view of a beautiful park, a lot of squirrels are playing in the lush grass, blablabla etc... (rest omitted for brevity)"}}

# Real scenario and data

We are inside a video titled "{title}"
The video is described by: "{description}".
Here is a summary of the {event_count} most recent events:
{events_json}

# Your response
Your caption:"""


def get_inference_client(llm_config: Optional[dict] = None) -> InferenceClient:
    """
    Get an InferenceClient configured with the provided LLM settings.
    
    Priority order for API keys:
    1. Provider-specific API key (if provided)
    2. User's HF token (if provided)
    3. Server's HF token (only for built-in provider)
    4. Raise exception if no valid key is available
    """

    if not llm_config:
        if HF_TOKEN:
            return InferenceClient(
                model=TEXT_MODEL,
                token=HF_TOKEN
            )
        else:
            raise ValueError("Built-in provider is not available. Server HF_TOKEN is not configured.")
        
    provider = llm_config.get('provider', '').lower()
    #logger.info(f"provider = {provider}")

    # If no provider or model specified, use default
    if not provider or provider == 'built-in':
        if HF_TOKEN:
            return InferenceClient(
                model=TEXT_MODEL,
                token=HF_TOKEN
            )
        else:
            raise ValueError("Built-in provider is not available. Server HF_TOKEN is not configured.")

    model = llm_config.get('model', '')
    user_hf_token = llm_config.get('hf_token', '')  # User's HF token
    
    try:
        # Use provider with user's HF token if available
        if user_hf_token:
            return InferenceClient(
                provider=provider,
                model=model,
                token=user_hf_token
            )
        else:
            raise ValueError(f"No Hugging Face API key provided for provider '{provider}'. Please provide your Hugging Face API key.")

    except ValueError:
        # Re-raise ValueError for missing API keys
        raise
    except Exception as e:
        logger.error(f"Error creating InferenceClient for provider '{provider}' and model '{model}': {e}")
        # Re-raise all other exceptions
        raise


async def generate_text(prompt: str, llm_config: Optional[dict] = None, 
                       max_new_tokens: int = 200, temperature: float = 0.7,
                       model_override: Optional[str] = None) -> str:
    """
    Helper method to generate text using the appropriate client and configuration.
    Tries chat_completion first (modern standard), falls back to text_generation.
    
    Args:
        prompt: The prompt to generate text from
        llm_config: Optional LLM configuration dict
        max_new_tokens: Maximum number of new tokens to generate
        temperature: Temperature for generation
        model_override: Optional model to use instead of the one in llm_config
        
    Returns:
        Generated text string
    """
    # Add game master prompt if provided
    if llm_config and llm_config.get('game_master_prompt'):
        game_master_prompt = llm_config['game_master_prompt'].strip()
        if game_master_prompt:
            prompt = f"Important contextual rules: {game_master_prompt}\n\n{prompt}"
    
    # Get the appropriate client
    client = get_inference_client(llm_config)
    
    # Determine the model to use
    if model_override:
        model_to_use = model_override
    elif llm_config:
        model_to_use = llm_config.get('model', TEXT_MODEL)
    else:
        model_to_use = TEXT_MODEL
    
    # Try chat_completion first (modern standard, more widely supported)
    try:
        messages = [{"role": "user", "content": prompt}]
        
        if llm_config and llm_config.get('provider') != 'huggingface':
            # For third-party providers
            completion = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: client.chat.completions.create(
                    messages=messages,
                    max_tokens=max_new_tokens,
                    temperature=temperature
                )
            )
        else:
            # For HuggingFace models, specify the model
            completion = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: client.chat.completions.create(
                    model=model_to_use,
                    messages=messages,
                    max_tokens=max_new_tokens,
                    temperature=temperature
                )
            )
        
        # Extract the generated text from the chat completion response
        return completion.choices[0].message.content
        
    except Exception as e:
        error_message = str(e).lower()
        # Check if the error is related to task compatibility or API not supported
        if ("not supported for task" in error_message or 
            "conversational" in error_message or
            "chat" in error_message):
            logger.info(f"chat_completion not supported, falling back to text_generation: {e}")
            
            # Fall back to text_generation API
            try:
                if llm_config and llm_config.get('provider') != 'huggingface':
                    # For third-party providers
                    response = await asyncio.get_event_loop().run_in_executor(
                        None,
                        lambda: client.text_generation(
                            prompt,
                            max_new_tokens=max_new_tokens,
                            temperature=temperature
                        )
                    )
                else:
                    # For HuggingFace models, specify the model
                    response = await asyncio.get_event_loop().run_in_executor(
                        None,
                        lambda: client.text_generation(
                            prompt,
                            model=model_to_use,
                            max_new_tokens=max_new_tokens,
                            temperature=temperature
                        )
                    )
                return response
                
            except Exception as text_error:
                logger.error(f"Both chat_completion and text_generation failed: {text_error}")
                raise text_error
        else:
            # Re-raise the original error if it's not a task compatibility issue
            logger.error(f"chat_completion failed with non-compatibility error: {e}")
            raise e