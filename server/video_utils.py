"""
Video generation utilities for HuggingFace endpoints and Gradio spaces.
"""
import asyncio
import time
import uuid
import logging
from typing import Dict
from aiohttp import ClientSession
from gradio_client import Client
from .models import UserRole, Endpoint
from .api_config import HF_TOKEN, GUIDANCE_SCALE
from .logging_utils import get_logger

logger = get_logger(__name__)


async def generate_video_content_with_inference_endpoints(
    endpoint_manager, prompt: str, negative_prompt: str, width: int, 
    height: int, num_frames: int, num_inference_steps: int, 
    frame_rate: int, seed: int, options: dict, user_role: UserRole
) -> str:
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
    async with endpoint_manager.get_endpoint() as endpoint:
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
                        await endpoint_manager.mark_endpoint_error(endpoint)
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
                        await endpoint_manager.mark_endpoint_error(endpoint)
                        if "paused" in str(error_msg).lower():
                            logger.error(f"[{request_id}] Endpoint is paused")
                            return ""
                        raise Exception(f"Video generation failed: {error_msg}")
                    
                    video_data_uri = result.get("video")
                    if not video_data_uri:
                        logger.error(f"[{request_id}] No video data in response")
                        # Mark endpoint as in error state
                        await endpoint_manager.mark_endpoint_error(endpoint)
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
            await endpoint_manager.mark_endpoint_error(endpoint, is_timeout=True)
            return ""
        except Exception as e:
            # Handle all other exceptions
            logger.error(f"[{request_id}] Exception during video generation: {str(e)}")
            if not isinstance(e, asyncio.TimeoutError):  # Already handled above
                await endpoint_manager.mark_endpoint_error(endpoint)
            return ""


async def generate_video_content_with_gradio(
    endpoint_manager, prompt: str, negative_prompt: str, width: int, 
    height: int, num_frames: int, num_inference_steps: int, 
    frame_rate: int, seed: int, options: dict, user_role: UserRole
) -> str:
    """
    Internal method to generate video content with specific parameters.
    Used by both regular video generation and thumbnail generation.
    This version uses our generic gradio space.
    """
    is_thumbnail = options.get('thumbnail', False)
    request_id = options.get('request_id', str(uuid.uuid4())[:8])  # Get or generate request ID
    video_id = options.get('video_id', 'unknown')
    
    # logger.info(f"[{request_id}] Generating {'thumbnail' if is_thumbnail else 'video'} for video {video_id} with seed {seed}")

    # Define the synchronous function
    def _sync_gradio_call():
        client = Client("jbilcke-hf/fast-rendering-node", hf_token=HF_TOKEN)
        
        return client.predict(
            prompt=prompt,
            seed=seed,
            fps=8, # frame_rate, # attention, right now tilslop asks for 25 FPS
            width=640, # width, # attention, right now tikslop asks for 1152
            height=320, # height, # attention, righ tnow tikslop asks for 640
            duration=3, # num_frames // frame_rate
        )
    
    # Run in a thread using asyncio.to_thread (Python 3.9+)
    video_data_uri = await asyncio.to_thread(_sync_gradio_call)
    
    return video_data_uri


