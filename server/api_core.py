import logging
import os
import io
import re
import base64
import uuid
from typing import Dict, Any, Optional, List
import asyncio
import time
import datetime
from collections import defaultdict
from aiohttp import web, ClientSession
from huggingface_hub import HfApi
from gradio_client import Client
import random
import yaml
import json

from .api_config import *
from .models import UserRole
from .endpoint_manager import EndpointManager
from .utils import generate_seed, sanitize_yaml_response
from .chat import ChatManager
from .config_utils import get_config_value
from .video_utils import (
    generate_video_content_with_inference_endpoints,
    generate_video_content_with_gradio
)
from .llm_utils import (
    get_inference_client,
    generate_text,
    SEARCH_VIDEO_PROMPT_TEMPLATE,
    GENERATE_CAPTION_PROMPT_TEMPLATE,
    SIMULATE_VIDEO_FIRST_PROMPT_TEMPLATE,
    SIMULATE_VIDEO_CONTINUE_PROMPT_TEMPLATE,
    GENERATE_CLIP_PROMPT_TEMPLATE
)

# Configure logging
from .logging_utils import get_logger
logger = get_logger(__name__)



class VideoGenerationAPI:
    def __init__(self):
        self.hf_api = HfApi(token=HF_TOKEN)
        self.endpoint_manager = EndpointManager()
        self.active_requests: Dict[str, asyncio.Future] = {}
        self.chat_manager = ChatManager()
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

    async def search_video(self, query: str, attempt_count: int = 0, llm_config: Optional[dict] = None) -> Optional[dict]:
        """Generate a single search result using HF text generation"""
        # Maximum number of attempts to generate a description without placeholder tags
        max_attempts = 2
        current_attempt = attempt_count
        # Use a random temperature between 0.68 and 0.72 to generate more diverse results
        # and prevent duplicate results from successive calls with the same prompt
        temperature = random.uniform(0.68, 0.72)

        while current_attempt <= max_attempts:
            prompt = SEARCH_VIDEO_PROMPT_TEMPLATE.format(
                current_attempt=current_attempt,
                query=query
            )

            try:
                raw_yaml_str = await generate_text(
                    prompt,
                    llm_config=llm_config,
                    max_new_tokens=200,
                    temperature=temperature
                )

                raw_yaml_str = raw_yaml_str.strip()
        
                #logger.info(f"search_video(): raw_yaml_str = {raw_yaml_str}")

                # All pre-processing is now handled in sanitize_yaml_response
                sanitized_yaml = sanitize_yaml_response(raw_yaml_str)

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
        

        # List of video types to randomly choose from
        video_types = ["documentary", "movie screencap, movie scene", "POV, gopro footage", "music video", "videogame gameplay", "creepy found footage"]

        video_type = random.choice(video_types)

        # If all attempts failed, return a simple result with title only
        return {
            'id': str(uuid.uuid4()),
            'title': f"{query} ({video_type})",
            'description': f"{video_type}, {query}, engaging, detailed, dynamic, high quality, 4K, intricate details",
            'thumbnailUrl': '',
            'videoUrl': '',
            'isLatent': True,
            'useFixedSeed': "query" in query.lower(),
            'seed': generate_seed(),
            'views': 0,
            'tags': []
        }

    # The generate_thumbnail function has been removed because we now use
    # generate_video_thumbnail for all thumbnails, which generates a video clip
    # instead of a static image

    async def generate_caption(self, title: str, description: str, llm_config: Optional[dict] = None) -> str:
        """Generate detailed caption using HF text generation"""
        try:
            prompt = GENERATE_CAPTION_PROMPT_TEMPLATE.format(
                title=title,
                description=description
            )

            response = await generate_text(
                prompt,
                llm_config=llm_config,
                max_new_tokens=180,
                temperature=0.7
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
                         evolution_count: int = 0, chat_messages: str = '', llm_config: Optional[dict] = None) -> dict:
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
            
            #logger.info(f"simulate(): is_first_simulation={is_first_simulation}")
                
            # Create an appropriate prompt based on whether this is the first simulation
            chat_section = ""
            if chat_messages:
                logger.info(f"CHAT_DEBUG: Server received chat messages for simulation: {chat_messages}")
                chat_section = f"""
People are watching this content right now and have shared their thoughts. Like a game master, please take their feedback as input to adjust the story and/or the scene. Here are their messages:

{chat_messages}
"""
            else:
                logger.info("CHAT_DEBUG: Server simulation called with no chat messages")

            if is_first_simulation:
                prompt = SIMULATE_VIDEO_FIRST_PROMPT_TEMPLATE.format(
                    original_title=original_title,
                    original_description=original_description,
                    chat_section=chat_section
                )
            else:
                prompt = SIMULATE_VIDEO_CONTINUE_PROMPT_TEMPLATE.format(
                    original_title=original_title,
                    original_description=original_description,
                    condensed_history=condensed_history,
                    current_description=current_description,
                    chat_section=chat_section
                )

            # Generate the evolved description using the helper method
            response = await generate_text(
                prompt,
                llm_config=llm_config,
                max_new_tokens=240,
                temperature=0.60
            )

            # print("RAW RESPONSE: ", response)
            
            # Just use the whole response as the evolved description
            evolved_description = response.strip()
            
            # If response is empty, use fallback
            if not evolved_description:
                evolved_description = current_description
                logger.warning(f"Empty response, using current description as fallback")
            
            # Pass the condensed history through unchanged
            return {
                "evolved_description": evolved_description,
                "condensed_history": condensed_history
            }
            
        except Exception as e:
            logger.error(f"Error simulating video: {str(e)}")
            return {
                "evolved_description": current_description,
                "condensed_history": condensed_history
            }

    async def _generate_clip_prompt(self, video_id: str, title: str, description: str) -> str:
        """Generate a new prompt for the next clip based on event history"""
        events = self.video_events.get(video_id, [])
        events_json = "\n".join(json.dumps(event) for event in events)
        
        prompt = GENERATE_CLIP_PROMPT_TEMPLATE.format(
            title=title,
            description=description,
            event_count=len(events),
            events_json=events_json
        )

        try:
            # Use the imported generate_text function instead
            response = await generate_text(
                prompt,
                llm_config=None,  # Use default config
                max_new_tokens=200,
                temperature=0.7
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
        
        logger.info(f"[{request_id}] Starting video thumbnail generation for video_id: {video_id}, tTitle: '{title}', User role: {user_role}")
        
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
            result = await generate_video_content_with_inference_endpoints(
                self.endpoint_manager,
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
        width = get_config_value(user_role, 'clip_width', options)
        height = get_config_value(user_role, 'clip_height', options)
        num_frames = get_config_value(user_role, 'num_frames', options)
        num_inference_steps = get_config_value(user_role, 'num_inference_steps', options)
        frame_rate = get_config_value(user_role, 'clip_framerate', options)
        
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
        # historically we used _generate_video_content_with_inference_endpoints,
        # which offers better performance and relability, but costs were spinning out of control
        return await generate_video_content_with_inference_endpoints(
            self.endpoint_manager,
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

    async def handle_chat_message(self, data: dict, ws: web.WebSocketResponse) -> dict:
        """Process and broadcast a chat message"""
        video_id = data.get('videoId')
        
        # Add chat message to event history
        if video_id:
            self._add_event(video_id, {
                "time": datetime.datetime.utcnow().isoformat() + "Z",
                "event": "new_chat_message",
                "username": data.get('username', 'Anonymous'),
                "data": data.get('content', '')
            })
        
        return await self.chat_manager.handle_chat_message(data, ws)

    async def handle_join_chat(self, data: dict, ws: web.WebSocketResponse) -> dict:
        """Handle a request to join a chat room"""
        return await self.chat_manager.handle_join_chat(data, ws)

    async def handle_leave_chat(self, data: dict, ws: web.WebSocketResponse) -> dict:
        """Handle a request to leave a chat room"""
        return await self.chat_manager.handle_leave_chat(data, ws)