"""
Endpoint management for video generation services.
"""
import time
import datetime
import logging
from asyncio import Lock
from contextlib import asynccontextmanager
from typing import List
from .models import Endpoint
from .api_config import VIDEO_ROUND_ROBIN_ENDPOINT_URLS

logger = logging.getLogger(__name__)


class EndpointManager:
    """Manages multiple video generation endpoints with load balancing and error handling."""
    
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
                    break

            yield endpoint

        finally:
            if endpoint:
                async with self.lock:
                    endpoint.busy = False
                    endpoint.last_used = time.time()
    
    async def mark_endpoint_error(self, endpoint: Endpoint, is_timeout: bool = False):
        """Mark an endpoint as being in error state with exponential backoff"""
        async with self.lock:
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