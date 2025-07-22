import asyncio
import logging
from typing import Dict, Set
from aiohttp import web, WSMsgType
import json
import time
import datetime
from api_core import VideoGenerationAPI

logger = logging.getLogger(__name__)

class UserSession:
    """
    Represents a user's session with the API.
    Each WebSocket connection gets its own session with separate queues and rate limits.
    """
    def __init__(self, user_id: str, user_role: str, ws: web.WebSocketResponse, shared_api):
        self.user_id = user_id
        self.user_role = user_role
        self.ws = ws
        self.shared_api = shared_api  # For shared resources like endpoint manager
        
        # Create separate queues for this user session
        self.chat_queue = asyncio.Queue()
        self.video_queue = asyncio.Queue()
        self.search_queue = asyncio.Queue()
        self.simulation_queue = asyncio.Queue()  # New queue for description evolution
        
        # Track request counts and rate limits
        self.request_counts = {
            'chat': 0,
            'video': 0,
            'search': 0,
            'simulation': 0  # New counter for simulation requests
        }
        
        # Last request timestamps for rate limiting
        self.last_request_times = {
            'chat': time.time(),
            'video': time.time(),
            'search': time.time(),
            'simulation': time.time()  # New timestamp for simulation requests
        }
        
        # Session creation time
        self.created_at = time.time()
        
        self.background_tasks = []
        
    async def start(self):
        """Start all the queue processors for this session"""
        # Start background tasks for handling different request types
        self.background_tasks = [
            asyncio.create_task(self._process_chat_queue()),
            asyncio.create_task(self._process_video_queue()),
            asyncio.create_task(self._process_search_queue()),
            asyncio.create_task(self._process_simulation_queue())  # New worker for simulation requests
        ]
        logger.info(f"Started session for user {self.user_id} with role {self.user_role}")
        
    async def stop(self):
        """Stop all background tasks for this session"""
        for task in self.background_tasks:
            task.cancel()
        
        try:
            # Wait for tasks to complete cancellation
            await asyncio.gather(*self.background_tasks, return_exceptions=True)
        except asyncio.CancelledError:
            pass
        
        logger.info(f"Stopped session for user {self.user_id}")
        
    async def _process_chat_queue(self):
        """High priority queue for chat operations"""
        while True:
            data = await self.chat_queue.get()
            try:
                if data['action'] == 'join_chat':
                    result = await self.shared_api.handle_join_chat(data, self.ws)
                elif data['action'] == 'chat_message':
                    result = await self.shared_api.handle_chat_message(data, self.ws)
                elif data['action'] == 'leave_chat':
                    result = await self.shared_api.handle_leave_chat(data, self.ws)
                # Redirect thumbnail requests to process_generic_request for consistent handling
                elif data['action'] == 'generate_video_thumbnail':
                    # Pass to the generic request handler to maintain consistent logic
                    await self.process_generic_request(data)
                    # Skip normal response handling since process_generic_request already sends a response
                    self.chat_queue.task_done()
                    continue
                else:
                    raise ValueError(f"Unknown chat action: {data['action']}")
                    
                await self.ws.send_json(result)
                
                # Update metrics
                self.request_counts['chat'] += 1
                self.last_request_times['chat'] = time.time()
                
            except Exception as e:
                logger.error(f"Error processing chat request for user {self.user_id}: {e}")
                try:
                    await self.ws.send_json({
                        'action': data['action'],
                        'requestId': data.get('requestId'),
                        'success': False,
                        'error': f'Chat error: {str(e)}'
                    })
                except Exception as send_error:
                    logger.error(f"Error sending error response: {send_error}")
            finally:
                self.chat_queue.task_done()

    async def _process_video_queue(self):
        """Process multiple video generation requests in parallel for this user"""
        from api_config import VIDEO_ROUND_ROBIN_ENDPOINT_URLS
        
        active_tasks = set()
        # Set a per-user concurrent limit based on role
        max_concurrent = len(VIDEO_ROUND_ROBIN_ENDPOINT_URLS)
        if self.user_role == 'anon':
            max_concurrent = min(2, max_concurrent)  # Limit anonymous users
        elif self.user_role == 'normal':
            max_concurrent = min(4, max_concurrent)  # Standard users
        # Pro and admin can use all endpoints

        async def process_single_request(data):
            try:
                title = data.get('title', '')
                description = data.get('description', '')
                video_prompt_prefix = data.get('video_prompt_prefix', '')
                options = data.get('options', {})
                
                # Pass the user role to generate_video
                video_data = await self.shared_api.generate_video(
                    title, description, video_prompt_prefix, options, self.user_role
                )
                
                result = {
                    'action': 'generate_video',
                    'requestId': data.get('requestId'),
                    'success': True,
                    'video': video_data,
                }
                
                await self.ws.send_json(result)
                
                # Update metrics
                self.request_counts['video'] += 1
                self.last_request_times['video'] = time.time()
                
            except Exception as e:
                logger.error(f"Error processing video request for user {self.user_id}: {e}")
                try:
                    await self.ws.send_json({
                        'action': 'generate_video',
                        'requestId': data.get('requestId'),
                        'success': False,
                        'error': f'Video generation error: {str(e)}'
                    })
                except Exception as send_error:
                    logger.error(f"Error sending error response: {send_error}")
            finally:
                active_tasks.discard(asyncio.current_task())

        while True:
            # Clean up completed tasks
            active_tasks = {task for task in active_tasks if not task.done()}
            
            # Start new tasks if we have capacity
            while len(active_tasks) < max_concurrent:
                try:
                    # Use try_get to avoid blocking if queue is empty
                    data = await asyncio.wait_for(self.video_queue.get(), timeout=0.1)
                    
                    # Create and start new task
                    task = asyncio.create_task(process_single_request(data))
                    active_tasks.add(task)
                    
                except asyncio.TimeoutError:
                    # No items in queue, break inner loop
                    break
                except Exception as e:
                    logger.error(f"Error creating video generation task for user {self.user_id}: {e}")
                    break

            # Wait a short time before checking queue again
            await asyncio.sleep(0.1)

            # Handle any completed tasks' errors
            for task in list(active_tasks):
                if task.done():
                    try:
                        await task
                    except Exception as e:
                        logger.error(f"Task failed with error for user {self.user_id}: {e}")
                    active_tasks.discard(task)

    async def _process_search_queue(self):
        """Medium priority queue for search operations"""
        while True:
            try:
                data = await self.search_queue.get()
                request_id = data.get('requestId')
                query = data.get('query', '').strip()
                attempt_count = data.get('attemptCount', 0)
                llm_config = data.get('llm_config')

                # logger.info(f"Processing search request for user {self.user_id}, attempt={attempt_count}")

                if not query:
                    logger.warning(f"Empty query received in request from user {self.user_id}: {data}")
                    result = {
                        'action': 'search',
                        'requestId': request_id,
                        'success': False,
                        'error': 'No search query provided'
                    }
                else:
                    try:
                        search_result = await self.shared_api.search_video(
                            query,
                            attempt_count=attempt_count,
                            llm_config=llm_config
                        )
                        
                        if search_result:
                            # logger.info(f"Search successful for user {self.user_id}, query '{query}'")
                            result = {
                                'action': 'search',
                                'requestId': request_id,
                                'success': True,
                                'result': search_result
                            }
                        else:
                            # logger.warning(f"No results found for user {self.user_id}, query '{query}'")
                            result = {
                                'action': 'search',
                                'requestId': request_id,
                                'success': False,
                                'error': 'No results found'
                            }
                    except Exception as e:
                        logger.error(f"Search error for user {self.user_id}, (attempt {attempt_count}): {str(e)}")
                        result = {
                            'action': 'search',
                            'requestId': request_id,
                            'success': False,
                            'error': f'Search error: {str(e)}'
                        }

                await self.ws.send_json(result)
                
                # Update metrics
                self.request_counts['search'] += 1
                self.last_request_times['search'] = time.time()
                
            except Exception as e:
                logger.error(f"Error in search queue processor for user {self.user_id}: {str(e)}")
                try:
                    error_response = {
                        'action': 'search',
                        'requestId': data.get('requestId') if 'data' in locals() else None,
                        'success': False,
                        'error': f'Internal server error: {str(e)}'
                    }
                    await self.ws.send_json(error_response)
                except Exception as send_error:
                    logger.error(f"Error sending error response: {send_error}")
            finally:
                if 'search_queue' in self.__dict__:
                    self.search_queue.task_done()
                    
    async def _process_simulation_queue(self):
        """Dedicated queue for video simulation requests"""
        while True:
            try:
                data = await self.simulation_queue.get()
                request_id = data.get('requestId')
                
                # Extract parameters from the request
                video_id = data.get('video_id', '')
                original_title = data.get('original_title', '')
                original_description = data.get('original_description', '')
                current_description = data.get('current_description', '')
                condensed_history = data.get('condensed_history', '')
                evolution_count = data.get('evolution_count', 0)
                chat_messages = data.get('chat_messages', '')
                llm_config = data.get('llm_config')
                
                # logger.info(f"Processing video simulation for user {self.user_id}, video_id={video_id}, evolution_count={evolution_count}")
                
                # Validate required parameters
                if not original_title or not original_description or not current_description:
                    result = {
                        'action': 'simulate',
                        'requestId': request_id,
                        'success': False,
                        'error': 'Missing required parameters'
                    }
                else:
                    try:
                        # Call the simulate method in the API
                        simulation_result = await self.shared_api.simulate(
                            original_title=original_title,
                            original_description=original_description,
                            current_description=current_description,
                            condensed_history=condensed_history,
                            evolution_count=evolution_count,
                            chat_messages=chat_messages,
                            llm_config=llm_config
                        )
                        
                        result = {
                            'action': 'simulate',
                            'requestId': request_id,
                            'success': True,
                            'evolved_description': simulation_result['evolved_description'],
                            'condensed_history': simulation_result['condensed_history']
                        }
                    except Exception as e:
                        logger.error(f"Error simulating video for user {self.user_id}, video_id={video_id}: {str(e)}")
                        result = {
                            'action': 'simulate',
                            'requestId': request_id,
                            'success': False,
                            'error': f'Simulation error: {str(e)}'
                        }
                
                await self.ws.send_json(result)
                
                # Update metrics
                self.request_counts['simulation'] += 1
                self.last_request_times['simulation'] = time.time()
                
            except Exception as e:
                logger.error(f"Error in simulation queue processor for user {self.user_id}: {str(e)}")
                try:
                    error_response = {
                        'action': 'simulate',
                        'requestId': data.get('requestId') if 'data' in locals() else None,
                        'success': False,
                        'error': f'Internal server error: {str(e)}'
                    }
                    await self.ws.send_json(error_response)
                except Exception as send_error:
                    logger.error(f"Error sending error response: {send_error}")
            finally:
                if 'simulation_queue' in self.__dict__:
                    self.simulation_queue.task_done()
                    
    async def process_generic_request(self, data: dict) -> None:
        """Handle general requests that don't fit into specialized queues"""
        try:
            request_id = data.get('requestId')
            action = data.get('action')
            
            def error_response(message: str):
                return {
                    'action': action,
                    'requestId': request_id,
                    'success': False,
                    'error': message
                }

            if action == 'heartbeat':
                # Include user role info in heartbeat response
                await self.ws.send_json({
                    'action': 'heartbeat',
                    'requestId': request_id,
                    'success': True,
                    'user_role': self.user_role
                })
            
            elif action == 'get_user_role':
                # Return the user role information
                await self.ws.send_json({
                    'action': 'get_user_role',
                    'requestId': request_id,
                    'success': True,
                    'user_role': self.user_role
                })
            
            elif action == 'generate_caption':
                params = data.get('params', {})
                title = params.get('title')
                description = params.get('description')
                llm_config = params.get('llm_config')
                
                if not title or not description:
                    await self.ws.send_json(error_response('Missing title or description'))
                    return
                    
                caption = await self.shared_api.generate_caption(title, description, llm_config=llm_config)
                await self.ws.send_json({
                    'action': action,
                    'requestId': request_id,
                    'success': True,
                    'caption': caption
                })
                
            # evolve_description is now handled by the dedicated simulation queue processor
                
            elif action == 'generate_video_thumbnail':
                title = data.get('title', '') or data.get('params', {}).get('title', '')
                description = data.get('description', '') or data.get('params', {}).get('description', '')
                video_prompt_prefix = data.get('video_prompt_prefix', '') or data.get('params', {}).get('video_prompt_prefix', '')
                options = data.get('options', {}) or data.get('params', {}).get('options', {})
                
                if not title:
                    await self.ws.send_json(error_response('Missing title for thumbnail generation'))
                    return
                
                # Ensure the options include the thumbnail flag
                options['thumbnail'] = True
                
                # Prioritize thumbnail generation with higher priority
                options['priority'] = 'high'
                
                # Add small size settings if not already specified
                if 'width' not in options:
                    options['width'] = 512  # Default thumbnail width
                if 'height' not in options:
                    options['height'] = 288  # Default 16:9 aspect ratio
                if 'num_frames' not in options:
                    options['num_frames'] = 25  # 1 second @ 25fps
                
                # Let the API know this is a thumbnail for a specific video
                options['video_id'] = data.get('video_id', f"thumbnail-{request_id}")
                
                logger.info(f"Generating thumbnail for video {options['video_id']} for user {self.user_id}")
                
                try:
                    # Generate the thumbnail
                    thumbnail_data = await self.shared_api.generate_video_thumbnail(
                        title, description, video_prompt_prefix, options, self.user_role
                    )
                    
                    # Respond with appropriate format based on the parameter names used in the request
                    if 'thumbnailUrl' in data or 'thumbnailUrl' in data.get('params', {}):
                        # Legacy format using thumbnailUrl
                        await self.ws.send_json({
                            'action': action,
                            'requestId': request_id,
                            'success': True,
                            'thumbnailUrl': thumbnail_data or "",
                        })
                    else:
                        # New format using thumbnail
                        await self.ws.send_json({
                            'action': action,
                            'requestId': request_id,
                            'success': True,
                            'thumbnail': thumbnail_data,
                        })
                except Exception as e:
                    logger.error(f"Error generating thumbnail: {str(e)}")
                    await self.ws.send_json(error_response(f"Thumbnail generation failed: {str(e)}"))
                
            # Handle deprecated thumbnail actions
            elif action == 'generate_thumbnail' or action == 'old_generate_thumbnail':
                # Redirect to video thumbnail generation
                logger.warning(f"Deprecated thumbnail action '{action}' used, redirecting to generate_video_thumbnail")
                
                # Extract parameters
                title = data.get('title', '') or data.get('params', {}).get('title', '')
                description = data.get('description', '') or data.get('params', {}).get('description', '')
                
                if not title or not description:
                    await self.ws.send_json(error_response('Missing title or description'))
                    return
                
                # Create a new request with the correct action
                new_request = {
                    'action': 'generate_video_thumbnail',
                    'requestId': request_id,
                    'title': title,
                    'description': description,
                    'options': {
                        'width': 512,
                        'height': 288,
                        'thumbnail': True,
                        'video_id': f"thumbnail-{request_id}"
                    }
                }
                
                # Process with the new action
                await self.process_generic_request(new_request)
                
            else:
                await self.ws.send_json(error_response(f'Unknown action: {action}'))
                
        except Exception as e:
            logger.error(f"Error processing generic request for user {self.user_id}: {str(e)}")
            try:
                await self.ws.send_json({
                    'action': data.get('action'),
                    'requestId': data.get('requestId'),
                    'success': False,
                    'error': f'Internal server error: {str(e)}'
                })
            except Exception as send_error:
                logger.error(f"Error sending error response: {send_error}")

class SessionManager:
    """
    Manages all active user sessions and shared resources.
    """
    def __init__(self):
        self.sessions = {}
        self.shared_api = VideoGenerationAPI()  # Single instance for shared resources
        self.session_lock = asyncio.Lock()
    
    async def create_session(self, user_id: str, user_role: str, ws: web.WebSocketResponse) -> UserSession:
        """Create a new user session"""
        async with self.session_lock:
            # Create a new session for this user
            session = UserSession(user_id, user_role, ws, self.shared_api)
            await session.start()
            self.sessions[user_id] = session
            return session
    
    async def delete_session(self, user_id: str) -> None:
        """Delete a user session and clean up resources"""
        async with self.session_lock:
            if user_id in self.sessions:
                session = self.sessions[user_id]
                await session.stop()
                del self.sessions[user_id]
                logger.info(f"Deleted session for user {user_id}")
    
    def get_session(self, user_id: str) -> UserSession:
        """Get a user session if it exists"""
        return self.sessions.get(user_id)
    
    async def close_all_sessions(self) -> None:
        """Close all active sessions (used during shutdown)"""
        async with self.session_lock:
            for user_id, session in list(self.sessions.items()):
                await session.stop()
            self.sessions.clear()
            logger.info("Closed all active sessions")
    
    @property
    def session_count(self) -> int:
        """Get the number of active sessions"""
        return len(self.sessions)
    
    def get_session_stats(self) -> Dict:
        """Get statistics about active sessions"""
        stats = {
            'total_sessions': len(self.sessions),
            'by_role': {
                'anon': 0,
                'normal': 0,
                'pro': 0,
                'admin': 0
            },
            'requests': {
                'chat': 0,
                'video': 0,
                'search': 0,
                'simulation': 0
            }
        }
        
        for session in self.sessions.values():
            stats['by_role'][session.user_role] += 1
            stats['requests']['chat'] += session.request_counts['chat']
            stats['requests']['video'] += session.request_counts['video']
            stats['requests']['search'] += session.request_counts['search']
            stats['requests']['simulation'] += session.request_counts['simulation']
            
        return stats