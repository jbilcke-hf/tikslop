"""
Data models and dataclasses used throughout the application.
"""
from dataclasses import dataclass
from typing import Literal, Set, List, Dict, Any


# User role type
UserRole = Literal['anon', 'normal', 'pro', 'admin']


@dataclass
class Endpoint:
    """Represents a video generation endpoint."""
    id: int
    url: str
    busy: bool = False
    last_used: float = 0
    error_count: int = 0
    error_until: float = 0  # Timestamp until which this endpoint is considered in error state


class ChatRoom:
    """Represents a chat room for a video."""
    def __init__(self):
        self.messages: List[Dict[str, Any]] = []
        self.connected_clients: Set[Any] = set()
        self.max_history: int = 100

    def add_message(self, message: Dict[str, Any]) -> None:
        """Add a message to the chat room history."""
        self.messages.append(message)
        if len(self.messages) > self.max_history:
            self.messages.pop(0)

    def get_recent_messages(self, limit: int = 50) -> List[Dict[str, Any]]:
        """Get the most recent messages from the chat room."""
        return self.messages[-limit:]