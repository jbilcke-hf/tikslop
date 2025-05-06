import asyncio
import json
import logging
import os
import pathlib
import time
import uuid
from aiohttp import web, WSMsgType
from typing import Dict, Any

from api_core import VideoGenerationAPI
from api_session import SessionManager
from api_metrics import MetricsTracker
from api_config import *

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Create global session and metrics managers
session_manager = SessionManager()
metrics_tracker = MetricsTracker()

# Dictionary to track connected anonymous clients by IP address
anon_connections = {}
anon_connection_lock = asyncio.Lock()

async def status_handler(request: web.Request) -> web.Response:
    """Handler for API status endpoint"""
    api = session_manager.shared_api
    
    # Get current busy status of all endpoints
    endpoint_statuses = []
    for ep in api.endpoint_manager.endpoints:
        endpoint_statuses.append({
            'id': ep.id,
            'url': ep.url,
            'busy': ep.busy,
            'last_used': ep.last_used,
            'error_count': ep.error_count,
            'error_until': ep.error_until
        })
    
    # Get session statistics
    session_stats = session_manager.get_session_stats()
    
    # Get metrics
    api_metrics = metrics_tracker.get_metrics()
    
    return web.json_response({
        'product': PRODUCT_NAME,
        'version': PRODUCT_VERSION,
        'maintenance_mode': MAINTENANCE_MODE,
        'available_endpoints': len(VIDEO_ROUND_ROBIN_ENDPOINT_URLS),
        'endpoint_status': endpoint_statuses,
        'active_endpoints': sum(1 for ep in endpoint_statuses if not ep['busy'] and ('error_until' not in ep or ep['error_until'] < time.time())),
        'active_sessions': session_stats,
        'metrics': api_metrics
    })

async def metrics_handler(request: web.Request) -> web.Response:
    """Handler for detailed metrics endpoint (protected)"""
    # Check for API key in header or query param
    auth_header = request.headers.get('Authorization', '')
    api_key = None
    
    if auth_header.startswith('Bearer '):
        api_key = auth_header[7:]
    else:
        api_key = request.query.get('key')
    
    # Validate API key (using SECRET_TOKEN as the API key)
    if not api_key or api_key != SECRET_TOKEN:
        return web.json_response({
            'error': 'Unauthorized'
        }, status=401)
    
    # Get detailed metrics
    detailed_metrics = metrics_tracker.get_detailed_metrics()
    
    return web.json_response(detailed_metrics)

async def websocket_handler(request: web.Request) -> web.WebSocketResponse:
    # Check if maintenance mode is enabled
    if MAINTENANCE_MODE:
        # Return an error response indicating maintenance mode
        return web.json_response({
            'error': 'Server is in maintenance mode',
            'maintenance': True
        }, status=503)  # 503 Service Unavailable
    
    ws = web.WebSocketResponse(
        max_msg_size=1024*1024*20,  # 20MB max message size
        timeout=30.0  # we want to keep things tight and short
    )
    
    await ws.prepare(request)
    
    # Get the Hugging Face token from query parameters
    hf_token = request.query.get('hf_token', '')
    
    # Generate a unique user ID for this connection
    user_id = str(uuid.uuid4())
    
    # Validate the token and determine the user role
    user_role = await session_manager.shared_api.validate_user_token(hf_token)
    logger.info(f"User {user_id} connected with role: {user_role}")
    
    # Get client IP address
    peername = request.transport.get_extra_info('peername')
    if peername is not None:
        client_ip = peername[0]
    else:
        client_ip = request.headers.get('X-Forwarded-For', 'unknown').split(',')[0].strip()
    
    logger.info(f"Client {user_id} connecting from IP: {client_ip} with role: {user_role}")
    
    # Check for anonymous user connection limits
    if user_role == 'anon':
        async with anon_connection_lock:
            # Track this connection
            anon_connections[client_ip] = anon_connections.get(client_ip, 0) + 1
            # Store the IP so we can clean up later
            ws.client_ip = client_ip
            
            # Log multiple connections from same IP but don't restrict them
            if anon_connections[client_ip] > 1:
                logger.info(f"Multiple anonymous connections from IP {client_ip}: {anon_connections[client_ip]} connections")
    
    # Store the user role in the websocket for easy access
    ws.user_role = user_role
    ws.user_id = user_id
    
    # Register with metrics
    metrics_tracker.register_session(user_id, client_ip)
    
    # Create a new session for this user
    user_session = await session_manager.create_session(user_id, user_role, ws)

    try:
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    action = data.get('action')
                    
                    # Check for rate limiting
                    request_type = 'other'
                    if action in ['join_chat', 'leave_chat', 'chat_message']:
                        request_type = 'chat'
                    elif action in ['generate_video']:
                        request_type = 'video'
                    elif action == 'search':
                        request_type = 'search'
                    
                    # Record the request for metrics
                    await metrics_tracker.record_request(user_id, client_ip, request_type, user_role)
                    
                    # Check rate limits (except for admins)
                    if user_role != 'admin' and await metrics_tracker.is_rate_limited(user_id, request_type, user_role):
                        await ws.send_json({
                            'action': action,
                            'requestId': data.get('requestId'),
                            'success': False,
                            'error': f'Rate limit exceeded for {request_type} requests. Please try again later.'
                        })
                        continue
                    
                    # Route requests to appropriate queues
                    if action in ['join_chat', 'leave_chat', 'chat_message']:
                        await user_session.chat_queue.put(data)
                    elif action in ['generate_video']:
                        await user_session.video_queue.put(data)
                    elif action == 'search':
                        await user_session.search_queue.put(data)
                    else:
                        await user_session.process_generic_request(data)
                        
                except Exception as e:
                    logger.error(f"Error processing WebSocket message for user {user_id}: {str(e)}")
                    await ws.send_json({
                        'action': data.get('action') if 'data' in locals() else 'unknown',
                        'success': False,
                        'error': f'Error processing message: {str(e)}'
                    })
                    
            elif msg.type in (WSMsgType.ERROR, WSMsgType.CLOSE):
                break
                
    finally:
        # Cleanup session
        await session_manager.delete_session(user_id)
        
        # Cleanup anonymous connection tracking
        if getattr(ws, 'user_role', None) == 'anon' and hasattr(ws, 'client_ip'):
            client_ip = ws.client_ip
            async with anon_connection_lock:
                if client_ip in anon_connections:
                    anon_connections[client_ip] = max(0, anon_connections[client_ip] - 1)
                    if anon_connections[client_ip] == 0:
                        del anon_connections[client_ip]
                    logger.info(f"Anonymous connection from {client_ip} closed. Remaining: {anon_connections.get(client_ip, 0)}")
        
        # Unregister from metrics
        metrics_tracker.unregister_session(user_id, client_ip)
        logger.info(f"Connection closed for user {user_id}")
    
    return ws

async def init_app() -> web.Application:
    app = web.Application(
        client_max_size=1024**2*20  # 20MB max size
    )
    
    # Add cleanup logic
    async def cleanup(app):
        logger.info("Shutting down server, closing all sessions...")
        await session_manager.close_all_sessions()
    
    app.on_shutdown.append(cleanup)
    
    # Add routes
    app.router.add_get('/ws', websocket_handler)
    app.router.add_get('/api/status', status_handler)
    app.router.add_get('/api/metrics', metrics_handler)
    
    # Set up static file serving
    # Define the path to the public directory
    public_path = pathlib.Path(__file__).parent / 'build' / 'web'
    if not public_path.exists():
        public_path.mkdir(parents=True, exist_ok=True)
    
    # Set up static file serving with proper security considerations
    async def static_file_handler(request):
        # Get the path from the request (removing leading /)
        path_parts = request.path.lstrip('/').split('/')
        
        # Convert to safe path to prevent path traversal attacks
        safe_path = public_path.joinpath(*path_parts)
        
        # Make sure the path is within the public directory (prevent directory traversal)
        try:
            safe_path = safe_path.resolve()
            if not str(safe_path).startswith(str(public_path.resolve())):
                return web.HTTPForbidden(text="Access denied")
        except (ValueError, FileNotFoundError):
            return web.HTTPNotFound()
        
        # If path is a directory, look for index.html
        if safe_path.is_dir():
            safe_path = safe_path / 'index.html'
        
        # Check if the file exists
        if not safe_path.exists() or not safe_path.is_file():
            # If not found, serve index.html (for SPA routing)
            safe_path = public_path / 'index.html'
            if not safe_path.exists():
                return web.HTTPNotFound()
        
        # Determine content type based on file extension
        content_type = 'text/plain'
        ext = safe_path.suffix.lower()
        if ext == '.html':
            content_type = 'text/html'
        elif ext == '.js':
            content_type = 'application/javascript'
        elif ext == '.css':
            content_type = 'text/css'
        elif ext in ('.jpg', '.jpeg'):
            content_type = 'image/jpeg'
        elif ext == '.png':
            content_type = 'image/png'
        elif ext == '.gif':
            content_type = 'image/gif'
        elif ext == '.svg':
            content_type = 'image/svg+xml'
        elif ext == '.json':
            content_type = 'application/json'
        
        # Return the file with appropriate headers
        return web.FileResponse(safe_path, headers={'Content-Type': content_type})
    
    # Add catch-all route for static files (lower priority than API routes)
    app.router.add_get('/{path:.*}', static_file_handler)
    
    return app

if __name__ == '__main__':
    app = asyncio.run(init_app())
    web.run_app(app, host='0.0.0.0', port=8080)