"""
Chat-related functionality for video interactions.
"""
import datetime
import logging
from collections import defaultdict
from typing import Dict, List, Any
from aiohttp import web
from .models import ChatRoom

logger = logging.getLogger(__name__)


class ChatManager:
    """Manages multiple chat rooms for different videos."""
    
    def __init__(self):
        self.chat_rooms = defaultdict(ChatRoom)

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