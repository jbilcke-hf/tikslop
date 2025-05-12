import logging
import os
import io
import re
import base64
import uuid
from typing import Dict, Any, Optional, List, Literal
from dataclasses import dataclass
from asyncio import Lock, Queue
import asyncio
import time
import datetime
from contextlib import asynccontextmanager
from collections import defaultdict
from aiohttp import web, ClientSession
from huggingface_hub import InferenceClient, HfApi
from gradio_client import Client
import random
import yaml
import json

from api_config import *

# User role type
UserRole = Literal['anon', 'normal', 'pro', 'admin']

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


def generate_seed():
    """Generate a random positive 32-bit integer seed."""
    return random.randint(0, 2**32 - 1)

def sanitize_yaml_response(response_text: str) -> str:
    """
    Sanitize and format AI response into valid YAML.
    Returns properly formatted YAML string.
    """

    response_text = response_text.split("```")[0]

    # Remove any markdown code block indicators and YAML document markers
    clean_text = re.sub(r'```yaml|```|---|\.\.\.$', '', response_text.strip())
    
    # Split into lines and process each line
    lines = clean_text.split('\n')
    sanitized_lines = []
    current_field = None
    
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
            
        # Handle field starts
        if stripped.startswith('title:') or stripped.startswith('description:'):
            # Ensure proper YAML format with space after colon and proper quoting
            field_name = stripped.split(':', 1)[0]
            field_value = stripped.split(':', 1)[1].strip().strip('"\'')
            
            # Quote the value if it contains special characters
            if any(c in field_value for c in ':[]{},&*#?|-<>=!%@`'):
                field_value = f'"{field_value}"'
                
            sanitized_lines.append(f"{field_name}: {field_value}")
            current_field = field_name
            
        elif stripped.startswith('tags:'):
            sanitized_lines.append('tags:')
            current_field = 'tags'
            
        elif stripped.startswith('-') and current_field == 'tags':
            # Process tag values
            tag = stripped[1:].strip().strip('"\'')
            if tag:
                # Clean and format tag
                tag = re.sub(r'[^\x00-\x7F]+', '', tag)  # Remove non-ASCII
                tag = re.sub(r'[^a-zA-Z0-9\s-]', '', tag)  # Keep only alphanumeric and hyphen
                tag = tag.strip().lower().replace(' ', '-')
                if tag:
                    sanitized_lines.append(f"  - {tag}")
                    
        elif current_field in ['title', 'description']:
            # Handle multi-line title/description continuation
            value = stripped.strip('"\'')
            if value:
                # Append to previous line
                prev = sanitized_lines[-1]
                sanitized_lines[-1] = f"{prev} {value}"
    
    # Ensure the YAML has all required fields
    required_fields = {'title', 'description', 'tags'}
    found_fields = {line.split(':')[0].strip() for line in sanitized_lines if ':' in line}
    
    for field in required_fields - found_fields:
        if field == 'tags':
            sanitized_lines.extend(['tags:', '  - default'])
        else:
            sanitized_lines.append(f'{field}: "No {field} provided"')
    
    return '\n'.join(sanitized_lines)

@dataclass
class Endpoint:
    id: int
    url: str
    busy: bool = False
    last_used: float = 0
    error_count: int = 0
    error_until: float = 0  # Timestamp until which this endpoint is considered in error state

class EndpointManager:
    def __init__(self):
        self.endpoints: List[Endpoint] = []
        self.lock = Lock()
        self.initialize_endpoints()
        self.last_used_index = -1  # Track the last used endpoint for round-robin

    def initialize_endpoints(self):
        """Initialize the list of endpoints"""
        for i, url in enumerate(VIDEO_ROUND_ROBIN_ENDPOINT_URLS):
            endpoint = Endpoint(id=i + 1, url=url)
            self.endpoints.append(endpoint)

    def _get_next_free_endpoint(self):
        """Get the next available non-busy endpoint, or oldest endpoint if all are busy"""
        current_time = time.time()
        
        # First priority: Get any non-busy and non-error endpoint
        free_endpoints = [
            ep for ep in self.endpoints 
            if not ep.busy and current_time > ep.error_until
        ]
        
        if free_endpoints:
            # Return the least recently used free endpoint
            return min(free_endpoints, key=lambda ep: ep.last_used)
        
        # Second priority: If all busy/error, use round-robin but skip error endpoints
        tried_count = 0
        next_index = self.last_used_index
        
        while tried_count < len(self.endpoints):
            next_index = (next_index + 1) % len(self.endpoints)
            tried_count += 1
            
            # If endpoint is not in error state, use it
            if current_time > self.endpoints[next_index].error_until:
                self.last_used_index = next_index
                return self.endpoints[next_index]
        
        # If all endpoints are in error state, use the one with earliest error expiry
        self.last_used_index = next_index
        return min(self.endpoints, key=lambda ep: ep.error_until)

    @asynccontextmanager
    async def get_endpoint(self, max_wait_time: int = 10):
        """Get the next available endpoint using a context manager"""
        start_time = time.time()
        endpoint = None
        
        try:
            while True:
                if time.time() - start_time > max_wait_time:
                    raise TimeoutError(f"Could not acquire an endpoint within {max_wait_time} seconds")

                async with self.lock:
                    # Get the next available endpoint using our selection strategy
                    endpoint = self._get_next_free_endpoint()
                    
                    # Mark it as busy
                    endpoint.busy = True
                    endpoint.last_used = time.time()
                    #logger.info(f"Using endpoint {endpoint.id} (busy: {endpoint.busy}, last used: {endpoint.last_used})")
                    break

            yield endpoint

        finally:
            if endpoint:
                async with self.lock:
                    endpoint.busy = False
                    endpoint.last_used = time.time()
                    # We don't need to put back into queue - our strategy now picks directly from the list

class ChatRoom:
    def __init__(self):
        self.messages = []
        self.connected_clients = set()
        self.max_history = 100

    def add_message(self, message):
        self.messages.append(message)
        if len(self.messages) > self.max_history:
            self.messages.pop(0)

    def get_recent_messages(self, limit=50):
        return self.messages[-limit:]

class VideoGenerationAPI:
    def __init__(self):
        self.inference_client = InferenceClient(token=HF_TOKEN)
        self.hf_api = HfApi(token=HF_TOKEN)
        self.endpoint_manager = EndpointManager()
        self.active_requests: Dict[str, asyncio.Future] = {}
        self.chat_rooms = defaultdict(ChatRoom)
        self.video_events: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
        self.event_history_limit = 50
        # Cache for user roles to avoid repeated API calls
        self.user_role_cache: Dict[str, Dict[str, Any]] = {}
        # Cache expiration time (10 minutes)
        self.cache_expiration = 600


    def _add_event(self, video_id: str, event: Dict[str, Any]):
        """Add an event to the video's history and maintain the size limit"""
        events = self.video_events[video_id]
        events.append(event)
        if len(events) > self.event_history_limit:
            events.pop(0)
    
    async def validate_user_token(self, token: str) -> UserRole:
        """
        Validates a Hugging Face token and determines the user's role.
        
        Returns one of:
        - 'anon': Anonymous user (no token or invalid token)
        - 'normal': Standard Hugging Face user
        - 'pro': Hugging Face Pro user
        - 'admin': Admin user (username in ADMIN_ACCOUNTS)
        """
        # If no token is provided, the user is anonymous
        if not token:
            return 'anon'
        
        # Check if we have a cached result for this token
        current_time = time.time()
        if token in self.user_role_cache:
            cached_data = self.user_role_cache[token]
            # If the cache is still valid
            if current_time - cached_data['timestamp'] < self.cache_expiration:
                logger.info(f"Using cached user role: {cached_data['role']}")
                return cached_data['role']
        
        # No valid cache, need to check the token with the HF API
        try:
            # Use HF API to validate the token and get user info
            logger.info("Validating Hugging Face token...")
            
            # Run in executor to avoid blocking the event loop
            user_info = await asyncio.get_event_loop().run_in_executor(
                None, 
                lambda: self.hf_api.whoami(token=token)
            )
            
            # Handle both object and dict response formats from whoami
            username = user_info.get('name') if isinstance(user_info, dict) else getattr(user_info, 'name', None)
            is_pro = user_info.get('is_pro') if isinstance(user_info, dict) else getattr(user_info, 'is_pro', False)
            
            if not username:
                logger.error(f"Could not determine username from user_info: {user_info}")
                return 'anon'
                
            logger.info(f"Token valid for user: {username}")
            
            # Determine the user role based on the information
            user_role: UserRole
            
            # Check if the user is an admin
            if username in ADMIN_ACCOUNTS:
                user_role = 'admin'
            # Check if the user has a pro account
            elif is_pro:
                user_role = 'pro'
            else:
                user_role = 'normal'
            
            # Cache the result
            self.user_role_cache[token] = {
                'role': user_role,
                'timestamp': current_time,
                'username': username
            }
            
            return user_role
            
        except Exception as e:
            logger.error(f"Failed to validate Hugging Face token: {str(e)}")
            # If validation fails, the user is treated as anonymous
            return 'anon'

    async def download_video(self, url: str) -> bytes:
        """Download video file from URL and return bytes"""
        async with ClientSession() as session:
            async with session.get(url) as response:
                if response.status != 200:
                    raise Exception(f"Failed to download video: HTTP {response.status}")
                return await response.read()

    async def search_video(self, query: str, attempt_count: int = 0) -> Optional[dict]:
        """Generate a single search result using HF text generation"""
        # Maximum number of attempts to generate a description without placeholder tags
        max_attempts = 2
        current_attempt = attempt_count
        # Use a random temperature between 0.68 and 0.72 to generate more diverse results
        # and prevent duplicate results from successive calls with the same prompt
        temperature = random.uniform(0.68, 0.72)

        while current_attempt <= max_attempts:
            prompt = f"""# Instruction
Your response MUST be a YAML object containing a title and description, consistent with what we can find on a video sharing platform.
Format your YAML response with only those fields: "title" (a short string) and "description" (string caption of the scene). Do not add any other field.
In the description field, describe in a very synthetic way the visuals of the first shot (first scene), eg "<STYLE>, medium close-up shot, high angle view. In the foreground a <OPTIONAL AGE> <OPTIONAL GENDER> <CHARACTERS> <ACTIONS>. In the background <DESCRIBE LOCATION, BACKGROUND CHARACTERS, OBJECTS ETC>. The scene is lit by <LIGHTING> <WEATHER>". This is just an example! you MUST replace the <TAGS>!!.
Don't forget to replace <STYLE> etc, by the actual fields!!
For the style, be creative, for instance you can use anything like a "documentary footage", "japanese animation", "movie scene", "tv series", "tv show", "security footage" etc.
If the user ask for something specific eg "movie screencap", "movie scene", "documentary footage" "animation" as a style etc.
Keep it minimalist but still descriptive, don't use bullets points, use simple words, go to the essential to describe style (cinematic, documentary footage, 3D rendering..), camera modes and angles, characters, age, gender, action, location, lighting, country, costume, time, weather, textures, color palette.. etc). Write about 80 words, and use between 2 and 3 sentences.
The most import part is to describe the actions and movements in the scene, so don't forget that!
Don't describe sound, so ever say things like "atmospheric music playing in the background".
Instead describe the visual elements we can see in the background, be precise, (if there are anything, cars, objects, people, bricks, birds, clouds, trees, leaves or grass then say it so etc).
Make the result unique and different from previous search results. ONLY RETURN YAML AND WITH ENGLISH CONTENT, NOT CHINESE - DO NOT ADD ANY OTHER COMMENT!

# Context
This is attempt {current_attempt}.

# Input
Describe the first scene/shot for: "{query}".

# Output

```yaml
title: \""""

            try:
                response = await asyncio.get_event_loop().run_in_executor(
                    None,
                    lambda: self.inference_client.text_generation(
                        prompt,
                        model=TEXT_MODEL,
                        max_new_tokens=200,
                        temperature=temperature
                    )
                )

                response_text = re.sub(r'^\s*\.\s*\n', '', f"title: \"{response.strip()}")
                sanitized_yaml = sanitize_yaml_response(response_text)
                
                try:
                    result = yaml.safe_load(sanitized_yaml)
                except yaml.YAMLError as e:
                    logger.error(f"YAML parsing failed: {str(e)}")
                    result = None
                
                if not result or not isinstance(result, dict):
                    logger.error(f"Invalid result format: {result}")
                    current_attempt += 1
                    temperature = random.uniform(0.68, 0.72)  # Try with different random temperature on next attempt
                    continue

                # Extract fields with defaults
                title = str(result.get('title', '')).strip() or 'Untitled Video'
                description = str(result.get('description', '')).strip() or 'No description available'
                
                # Check if the description still contains placeholder tags like <LOCATION>, <GENDER>, etc.
                if re.search(r'<[A-Z_]+>', description):
                    #logger.warning(f"Description still contains placeholder tags: {description}")
                    if current_attempt < max_attempts:
                        # Try again with a different random temperature
                        current_attempt += 1
                        temperature = random.uniform(0.68, 0.72)
                        continue
                    else:
                        # If we've reached max attempts, use the title as description
                        description = title

                # Return valid result with all required fields
                return {
                    'id': str(uuid.uuid4()),
                    'title': title,
                    'description': description,
                    'thumbnailUrl': '',
                    'videoUrl': '',

                    # not really used yet, maybe one day if we pre-generate or store content
                    'isLatent': True,

                    'useFixedSeed': "webcam" in description.lower(),

                    'seed': generate_seed(),
                    'views': 0,
                    'tags': []
                }

            except Exception as e:
                logger.error(f"Search video generation failed: {str(e)}")
                current_attempt += 1
                temperature = random.uniform(0.68, 0.72)  # Try with different random temperature on next attempt
        
        # If all attempts failed, return a simple result with title only
        return {
            'id': str(uuid.uuid4()),
            'title': f"Video about {query}",
            'description': f"Video about {query}",
            'thumbnailUrl': '',
            'videoUrl': '',
            'isLatent': True,
            'useFixedSeed': "query" in description.lower(),
            'seed': generate_seed(),
            'views': 0,
            'tags': []
        }

    # The generate_thumbnail function has been removed because we now use
    # generate_video_thumbnail for all thumbnails, which generates a video clip
    # instead of a static image

    async def generate_caption(self, title: str, description: str) -> str:
        """Generate detailed caption using HF text generation"""
        try:
            prompt = f"""Generate a detailed story for a video named: "{title}"
Visual description of the video: {description}.
Instructions: Write the story summary, including the plot, action, what should happen.
Make it around 200-300 words long.
A video can be anything from a tutorial, webcam, trailer, movie, live stream etc."""

            response = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.inference_client.text_generation(
                    prompt,
                    model=TEXT_MODEL,
                    max_new_tokens=180,
                    temperature=0.7
                )
            )
     
            if "Caption: " in response:
                response = response.replace("Caption: ", "")
            
            chunks = f" {response} ".split(". ")
            if len(chunks) > 1:
                text = ". ".join(chunks[:-1])
            else:
                text = response

            return text.strip()
        except Exception as e:
            logger.error(f"Error generating caption: {str(e)}")
            return ""
            
    async def simulate(self, original_title: str, original_description: str, 
                         current_description: str, condensed_history: str, 
                         evolution_count: int = 0, chat_messages: str = '') -> dict:
        """
        Simulate a video by evolving its description to create a dynamic narrative.
        
        Args:
            original_title: The original video title
            original_description: The original video description
            current_description: The current description (last evolved or original if first evolution)
            condensed_history: A condensed summary of previous scene developments
            evolution_count: How many times the simulation has already evolved
            chat_messages: Chat messages from users to incorporate into the simulation
            
        Returns:
            A dictionary containing the evolved description and updated condensed history
        """
        try:
            # Determine if this is the first simulation
            is_first_simulation = evolution_count == 0 or not condensed_history
            
            logger.info(f"simulate(): is_first_simulation={is_first_simulation}")
                
            # Create an appropriate prompt based on whether this is the first simulation
            chat_section = ""
            if chat_messages:
                chat_section = f"""
People are watching this content right now and have shared their thoughts. Like a game master, please take their feedback as input to adjust the story and/or the scene. Here are their messages:

{chat_messages}
"""

            if is_first_simulation:
                prompt = f"""You are tasked with evolving the narrative for a video titled: "{original_title}"

Original description:
{original_description}
{chat_section}

Instructions:
1. Imagine the next logical scene or development that would follow this description.
2. Create a compelling new description (200-300 words) that builds on the original but introduces new elements, developments, or perspectives.
3. Maintain the original style, tone, and setting.
4. If viewers have shared messages, consider their input and incorporate relevant suggestions or reactions into your narrative evolution.
5. Also create a brief "scene history" (50-75 words) that summarizes what has happened so far.

Return your response in this format:
EVOLVED_DESCRIPTION: [your new evolved description here]
CONDENSED_HISTORY: [your scene history summary]"""
            else:
                prompt = f"""You are tasked with continuing to evolve the narrative for a video titled: "{original_title}"

Original description:
{original_description}

Condensed history of scenes so far:
{condensed_history}

Current description (most recent scene):
{current_description}
{chat_section}

Instructions:
1. Imagine the next logical scene or development that would follow the current description.
2. Create a compelling new description (200-300 words) that builds on the narrative but introduces new elements, developments, or perspectives.
3. Maintain consistency with the previous scenes while advancing the story.
4. If viewers have shared messages, consider their input and incorporate relevant suggestions or reactions into your narrative evolution.
5. Also update the condensed history (50-75 words) to include this new development.

Return your response in this format:
EVOLVED_DESCRIPTION: [your new evolved description here]
CONDENSED_HISTORY: [your updated scene history summary]"""

            # Generate the evolved description
            response = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.inference_client.text_generation(
                    prompt,
                    model=TEXT_MODEL,
                    max_new_tokens=200,
                    temperature=0.7
                )
            )
            
            # Extract the evolved description and condensed history from the response
            evolved_description = ""
            new_condensed_history = ""
            
            # Parse the response
            if "EVOLVED_DESCRIPTION:" in response and "CONDENSED_HISTORY:" in response:
                parts = response.split("CONDENSED_HISTORY:")
                if len(parts) >= 2:
                    desc_part = parts[0].strip()
                    if "EVOLVED_DESCRIPTION:" in desc_part:
                        evolved_description = desc_part.split("EVOLVED_DESCRIPTION:", 1)[1].strip()
                    new_condensed_history = parts[1].strip()
            
            # If parsing failed, use some fallbacks
            if not evolved_description:
                evolved_description = current_description
                logger.warning(f"Failed to parse evolved description, using current description as fallback")
            
            if not new_condensed_history and condensed_history:
                new_condensed_history = condensed_history
                logger.warning(f"Failed to parse condensed history, using current history as fallback")
            elif not new_condensed_history:
                new_condensed_history = f"The video begins with {original_title}: {original_description[:100]}..."
            
            return {
                "evolved_description": evolved_description,
                "condensed_history": new_condensed_history
            }
            
        except Exception as e:
            logger.error(f"Error simulating video: {str(e)}")
            return {
                "evolved_description": current_description,
                "condensed_history": condensed_history or f"The video shows {original_title}."
            }


    def get_config_value(self, role: UserRole, field: str, options: dict = None) -> Any:
        """
        Get the appropriate config value for a user role.
        
        Args:
            role: The user role ('anon', 'normal', 'pro', 'admin')
            field: The config field name to retrieve
            options: Optional user-provided options that may override defaults
            
        Returns:
            The config value appropriate for the user's role with respect to
            min/max boundaries and user overrides.
        """
        # Select the appropriate config based on user role
        if role == 'admin':
            config = CONFIG_FOR_ADMIN_HF_USERS
        elif role == 'pro':
            config = CONFIG_FOR_PRO_HF_USERS
        elif role == 'normal':
            config = CONFIG_FOR_STANDARD_HF_USERS
        else:  # Anonymous users
            config = CONFIG_FOR_ANONYMOUS_USERS
        
        # Get the default value for this field from the config
        default_value = config.get(f"default_{field}", None)
        
        # For fields that have min/max bounds
        min_field = f"min_{field}"
        max_field = f"max_{field}"
        
        # Check if min/max constraints exist for this field
        has_constraints = min_field in config or max_field in config
        
        if not has_constraints:
            # For fields without constraints, just return the value from config
            return default_value
        
        # Get min and max values from config (if they exist)
        min_value = config.get(min_field, None)
        max_value = config.get(max_field, None)
        
        # If user provided options with this field
        if options and field in options:
            user_value = options[field]
            
            # Apply constraints if they exist
            if min_value is not None and user_value < min_value:
                return min_value
            if max_value is not None and user_value > max_value:
                return max_value
                
            # If within bounds, use the user's value
            return user_value
        
        # If no user value, return the default
        return default_value

    async def _generate_clip_prompt(self, video_id: str, title: str, description: str) -> str:
        """Generate a new prompt for the next clip based on event history"""
        events = self.video_events.get(video_id, [])
        events_json = "\n".join(json.dumps(event) for event in events)
        
        prompt = f"""# Context and task
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
Here is a summary of the {len(events)} most recent events:
{events_json}

# Your response
Your caption:"""

        try:
            response = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: self.inference_client.text_generation(
                    prompt,
                    model=TEXT_MODEL,
                    max_new_tokens=200,
                    temperature=0.7
                )
            )
            
            # Clean up the response
            caption = response.strip()
            if caption.lower().startswith("caption:"):
                caption = caption[8:].strip()
                
            return caption
            
        except Exception as e:
            logger.error(f"Error generating clip prompt: {str(e)}")
            # Fallback to original description if prompt generation fails
            return description

    async def generate_video_thumbnail(self, title: str, description: str, video_prompt_prefix: str, options: dict, user_role: UserRole = 'anon') -> str:
        """
        Generate a short, low-resolution video thumbnail for search results and previews.
        Optimized for quick generation and low resource usage.
        """
        video_id = options.get('video_id', str(uuid.uuid4()))
        seed = options.get('seed', generate_seed())
        request_id = str(uuid.uuid4())[:8]  # Generate a short ID for logging
        
        logger.info(f"[{request_id}] Starting video thumbnail generation for video_id: {video_id}")
        logger.info(f"[{request_id}] Title: '{title}', User role: {user_role}")
        
        # Create a more concise prompt for the thumbnail
        clip_caption = f"{video_prompt_prefix} - {title.strip()}"
        
        # Add the thumbnail generation to event history
        self._add_event(video_id, {
            "time": datetime.datetime.utcnow().isoformat() + "Z",
            "event": "thumbnail_generation",
            "caption": clip_caption,
            "seed": seed,
            "request_id": request_id
        })
        
        # Use a shorter prompt for thumbnails
        prompt = f"{clip_caption}, {POSITIVE_PROMPT_SUFFIX}"
        logger.info(f"[{request_id}] Using prompt: '{prompt}'")
        
        # Specialized configuration for thumbnails - smaller size, single frame
        width = 512  # Reduced size for thumbnails
        height = 288  # 16:9 aspect ratio
        num_frames = THUMBNAIL_FRAMES  # Just one frame for static thumbnail
        num_inference_steps = 4  # Fewer steps for faster generation
        frame_rate = 25  # Standard frame rate
        
        # Optionally override with options if specified
        width = options.get('width', width)
        height = options.get('height', height)
        num_frames = options.get('num_frames', num_frames)
        num_inference_steps = options.get('num_inference_steps', num_inference_steps)
        frame_rate = options.get('frame_rate', frame_rate)
        
        logger.info(f"[{request_id}] Configuration: width={width}, height={height}, frames={num_frames}, steps={num_inference_steps}, fps={frame_rate}")
        
        # Add thumbnail-specific tag to help debugging and metrics
        options['thumbnail'] = True
        
        # Check for available endpoints before attempting generation
        available_endpoints = sum(1 for ep in self.endpoint_manager.endpoints 
                               if not ep.busy and time.time() > ep.error_until)
        logger.info(f"[{request_id}] Available endpoints: {available_endpoints}/{len(self.endpoint_manager.endpoints)}")
        
        if available_endpoints == 0:
            logger.error(f"[{request_id}] No available endpoints for thumbnail generation")
            return ""
        
        # Use the same logic as regular video generation but with thumbnail settings
        try:
            # logger.info(f"[{request_id}] Generating thumbnail for video {video_id} with seed {seed}")
            
            start_time = time.time()
            # Rest of thumbnail generation logic same as regular video but with optimized settings
            result = await self._generate_video_content(
                prompt=prompt,
                negative_prompt=options.get('negative_prompt', NEGATIVE_PROMPT),
                width=width,
                height=height,
                num_frames=num_frames,
                num_inference_steps=num_inference_steps,
                frame_rate=frame_rate,
                seed=seed,
                options=options,
                user_role=user_role
            )
            duration = time.time() - start_time
            
            if result:
                data_length = len(result)
                logger.info(f"[{request_id}] Successfully generated thumbnail in {duration:.2f}s, data length: {data_length} chars")
                return result
            else:
                logger.error(f"[{request_id}] Empty result returned from video generation")
                return ""
            
        except Exception as e:
            logger.error(f"[{request_id}] Error generating thumbnail: {e}")
            if hasattr(e, "__traceback__"):
                import traceback
                logger.error(f"[{request_id}] Traceback: {traceback.format_exc()}")
            return ""  # Return empty string instead of raising to avoid crashes
    
    async def generate_video(self, title: str, description: str, video_prompt_prefix: str, options: dict, user_role: UserRole = 'anon') -> str:
        """Generate video using available space from pool"""
        video_id = options.get('video_id', str(uuid.uuid4()))
        
        # Generate a new prompt based on event history
        #clip_caption = await self._generate_clip_prompt(video_id, title, description)
        clip_caption = f"{video_prompt_prefix} - {title.strip()} - {description.strip()}"

        # Add the new clip to event history
        self._add_event(video_id, {
            "time": datetime.datetime.utcnow().isoformat() + "Z",
            "event": "new_stream_clip",
            "caption": clip_caption
        })

        # Use the generated caption as the prompt
        prompt = f"{clip_caption}, {POSITIVE_PROMPT_SUFFIX}"
        
        # Get the config values based on user role
        width = self.get_config_value(user_role, 'clip_width', options)
        height = self.get_config_value(user_role, 'clip_height', options)
        num_frames = self.get_config_value(user_role, 'num_frames', options)
        num_inference_steps = self.get_config_value(user_role, 'num_inference_steps', options)
        frame_rate = self.get_config_value(user_role, 'clip_framerate', options)
        
        # Get orientation from options
        orientation = options.get('orientation', 'LANDSCAPE')
        
        # Adjust width and height based on orientation if needed
        if orientation == 'PORTRAIT' and width > height:
            # Swap width and height for portrait orientation
            width, height = height, width
            # logger.info(f"Orientation: {orientation}, swapped dimensions to width={width}, height={height}")
        elif orientation == 'LANDSCAPE' and height > width:
            # Swap height and width for landscape orientation
            height, width = width, height
            # logger.info(f"generate_video()  Orientation: {orientation}, swapped dimensions to width={width}, height={height}, steps={num_inference_steps}, fps={frame_rate} | role: {user_role}")
        else:
            # logger.info(f"generate_video()  Orientation: {orientation}, using original dimensions width={width}, height={height}, steps={num_inference_steps}, fps={frame_rate} | role: {user_role}")
            pass
        
        # Generate the video with standard settings
        return await self._generate_video_content(
            prompt=prompt,
            negative_prompt=options.get('negative_prompt', NEGATIVE_PROMPT),
            width=width,
            height=height,
            num_frames=num_frames,
            num_inference_steps=num_inference_steps,
            frame_rate=frame_rate,
            seed=options.get('seed', 42),
            options=options,
            user_role=user_role
        )
        
    async def _generate_video_content(self, prompt: str, negative_prompt: str, width: int, 
                                     height: int, num_frames: int, num_inference_steps: int, 
                                     frame_rate: int, seed: int, options: dict, user_role: UserRole) -> str:
        """
        Internal method to generate video content with specific parameters.
        Used by both regular video generation and thumbnail generation.
        """
        is_thumbnail = options.get('thumbnail', False)
        request_id = options.get('request_id', str(uuid.uuid4())[:8])  # Get or generate request ID
        video_id = options.get('video_id', 'unknown')
        
        # logger.info(f"[{request_id}] Generating {'thumbnail' if is_thumbnail else 'video'} for video {video_id} with seed {seed}")
        
        json_payload = {
            "inputs": {
                "prompt": prompt,
            },
            "parameters": {
                # ------------------- settings for LTX-Video -----------------------
                "negative_prompt": negative_prompt,
                "width": width,
                "height": height,
                "num_frames": num_frames,
                "num_inference_steps": num_inference_steps,
                "guidance_scale": options.get('guidance_scale', GUIDANCE_SCALE),
                "seed": seed,
            
                # ------------------- settings for Varnish -----------------------
                "double_num_frames": False,  # <- False for real-time generation
                "fps": frame_rate,
                "super_resolution": False,  # <- False for real-time generation
                "grain_amount": 0,  # No film grain (on low-res, low-quality generation the effects aren't worth it + it adds weight to the MP4 payload)
            }
        }
        
        # Add thumbnail flag to help with metrics and debugging
        if is_thumbnail:
            json_payload["metadata"] = {
                "is_thumbnail": True,
                "thumbnail_version": "1.0",
                "request_id": request_id
            }

        # logger.info(f"[{request_id}] Waiting for an available endpoint...")
        async with self.endpoint_manager.get_endpoint() as endpoint:
            # logger.info(f"[{request_id}] Using endpoint {endpoint.id} for generation")
            
            try:
                async with ClientSession() as session:
                    #logger.info(f"[{request_id}] Sending request to endpoint {endpoint.id}: {endpoint.url}")
                    start_time = time.time()
                    
                    # Proceed with actual request
                    async with session.post(
                        endpoint.url,
                        headers={
                            "Accept": "application/json",
                            "Authorization": f"Bearer {HF_TOKEN}",
                            "Content-Type": "application/json",
                            "X-Request-ID": request_id  # Add request ID to headers
                        },
                        json=json_payload,
                        timeout=12  # Extended timeout for thumbnails (was 8s)
                    ) as response:
                        request_duration = time.time() - start_time
                        #logger.info(f"[{request_id}] Received response from endpoint {endpoint.id} in {request_duration:.2f}s: HTTP {response.status}")
                        
                        if response.status != 200:
                            error_text = await response.text()
                            logger.error(f"[{request_id}] Failed response: {error_text}")
                            # Mark endpoint as in error state
                            await self._mark_endpoint_error(endpoint)
                            if "paused" in error_text:
                                logger.error(f"[{request_id}] Endpoint is paused")
                                return ""
                            raise Exception(f"Video generation failed: HTTP {response.status} - {error_text}")
                        
                        result = await response.json()
                        #logger.info(f"[{request_id}] Successfully parsed JSON response")
                        
                        if "error" in result:
                            error_msg = result['error']
                            logger.error(f"[{request_id}] Error in response: {error_msg}")
                            # Mark endpoint as in error state
                            await self._mark_endpoint_error(endpoint)
                            if "paused" in str(error_msg).lower():
                                logger.error(f"[{request_id}] Endpoint is paused")
                                return ""
                            raise Exception(f"Video generation failed: {error_msg}")
                        
                        video_data_uri = result.get("video")
                        if not video_data_uri:
                            logger.error(f"[{request_id}] No video data in response")
                            # Mark endpoint as in error state
                            await self._mark_endpoint_error(endpoint)
                            raise Exception("No video data in response")
                        
                        # Get data size
                        data_size = len(video_data_uri)
                        #logger.info(f"[{request_id}] Received video data: {data_size} chars")
                        
                        # Reset error count on successful call
                        endpoint.error_count = 0
                        endpoint.error_until = 0
                        
                        return video_data_uri
                        
            except asyncio.TimeoutError:
                # Handle timeout specifically
                logger.error(f"[{request_id}] Timeout occurred after {time.time() - start_time:.2f}s")
                await self._mark_endpoint_error(endpoint, is_timeout=True)
                return ""
            except Exception as e:
                # Handle all other exceptions
                logger.error(f"[{request_id}] Exception during video generation: {str(e)}")
                if not isinstance(e, asyncio.TimeoutError):  # Already handled above
                    await self._mark_endpoint_error(endpoint)
                return ""
                
    async def _mark_endpoint_error(self, endpoint: Endpoint, is_timeout: bool = False):
        """Mark an endpoint as being in error state with exponential backoff"""
        async with self.endpoint_manager.lock:
            endpoint.error_count += 1
            
            # Calculate backoff time exponentially based on error count
            # Start with 15 seconds, then 30, 60, etc. up to a max of 5 minutes
            # Using shorter backoffs since generation should be fast
            backoff_seconds = min(15 * (2 ** (endpoint.error_count - 1)), 300)
            
            # Add extra backoff for timeouts which are more indicative of serious issues
            if is_timeout:
                backoff_seconds *= 2
                
            endpoint.error_until = time.time() + backoff_seconds
            
            logger.warning(
                f"Endpoint {endpoint.id} marked as in error state (count: {endpoint.error_count}, "
                f"unavailable until: {datetime.datetime.fromtimestamp(endpoint.error_until).strftime('%H:%M:%S')})"
            )


    async def handle_chat_message(self, data: dict, ws: web.WebSocketResponse) -> dict:
        """Process and broadcast a chat message"""
        video_id = data.get('videoId')
        request_id = data.get('requestId')
        
        if not video_id:
            return {
                'action': 'chat_message',
                'requestId': request_id,
                'success': False,
                'error': 'No video ID provided'
            }

        # Add chat message to event history
        self._add_event(video_id, {
            "time": datetime.datetime.utcnow().isoformat() + "Z",
            "event": "new_chat_message",
            "username": data.get('username', 'Anonymous'),
            "data": data.get('content', '')
        })

        room = self.chat_rooms[video_id]
        message_data = {k: v for k, v in data.items() if k != '_ws'}
        room.add_message(message_data)
        
        for client in room.connected_clients:
            if client != ws:
                try:
                    await client.send_json({
                        'action': 'chat_message',
                        'broadcast': True,
                        **message_data
                    })
                except Exception as e:
                    logger.error(f"Failed to broadcast to client: {e}")
                    room.connected_clients.remove(client)
        
        return {
            'action': 'chat_message',
            'requestId': request_id,
            'success': True,
            'message': message_data
        }

    async def handle_join_chat(self, data: dict, ws: web.WebSocketResponse) -> dict:
        """Handle a request to join a chat room"""
        video_id = data.get('videoId')
        request_id = data.get('requestId')
        
        if not video_id:
            return {
                'action': 'join_chat',
                'requestId': request_id,
                'success': False,
                'error': 'No video ID provided'
            }

        room = self.chat_rooms[video_id]
        room.connected_clients.add(ws)
        recent_messages = room.get_recent_messages()
        
        return {
            'action': 'join_chat',
            'requestId': request_id,
            'success': True,
            'messages': recent_messages
        }

    async def handle_leave_chat(self, data: dict, ws: web.WebSocketResponse) -> dict:
        """Handle a request to leave a chat room"""
        video_id = data.get('videoId')
        request_id = data.get('requestId')
        
        if not video_id:
            return {
                'action': 'leave_chat',
                'requestId': request_id,
                'success': False,
                'error': 'No video ID provided'
            }

        room = self.chat_rooms[video_id]
        if ws in room.connected_clients:
            room.connected_clients.remove(ws)
        
        return {
            'action': 'leave_chat',
            'requestId': request_id,
            'success': True
        }