import time
import logging
import asyncio
from collections import defaultdict
from typing import Dict, List, Set, Optional
import datetime

logger = logging.getLogger(__name__)

class MetricsTracker:
    """
    Tracks usage metrics across the API server.
    """
    def __init__(self):
        # Total metrics since server start
        self.total_requests = {
            'chat': 0,
            'video': 0, 
            'search': 0,
            'other': 0,
        }
        
        # Per-user metrics
        self.user_metrics = defaultdict(lambda: {
            'requests': {
                'chat': 0,
                'video': 0,
                'search': 0,
                'other': 0,
            },
            'first_seen': time.time(),
            'last_active': time.time(),
            'role': 'anon'
        })
        
        # Rate limiting buckets (per minute)
        self.rate_limits = {
            'anon': {
                'video': 30,
                'search': 45,
                'chat': 90,
                'other': 45
            },
            'normal': {
                'video': 60,
                'search': 90,
                'chat': 180,
                'other': 90 
            },
            'pro': {
                'video': 120,
                'search': 180,
                'chat': 300,
                'other': 180
            },
            'admin': {
                'video': 240,
                'search': 360,
                'chat': 450,
                'other': 360
            }
        }
        
        # Minute-based rate limiting buckets
        self.time_buckets = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))
        
        # Lock for thread safety
        self.lock = asyncio.Lock()
        
        # Track concurrent sessions by IP
        self.ip_sessions = defaultdict(set)
        
        # Server start time
        self.start_time = time.time()
        
    async def record_request(self, user_id: str, ip: str, request_type: str, role: str):
        """Record a request for metrics and rate limiting"""
        async with self.lock:
            # Update total metrics
            if request_type in self.total_requests:
                self.total_requests[request_type] += 1
            else:
                self.total_requests['other'] += 1
                
            # Update user metrics
            user_data = self.user_metrics[user_id]
            user_data['last_active'] = time.time()
            user_data['role'] = role
            
            if request_type in user_data['requests']:
                user_data['requests'][request_type] += 1
            else:
                user_data['requests']['other'] += 1
                
            # Update time bucket for rate limiting
            current_minute = int(time.time() / 60)
            self.time_buckets[user_id][current_minute][request_type] += 1
            
            # Clean up old time buckets (keep only last 10 minutes)
            cutoff = current_minute - 10
            for minute in list(self.time_buckets[user_id].keys()):
                if minute < cutoff:
                    del self.time_buckets[user_id][minute]
    
    def register_session(self, user_id: str, ip: str):
        """Register a new session for an IP address"""
        self.ip_sessions[ip].add(user_id)
        
    def unregister_session(self, user_id: str, ip: str):
        """Unregister a session when it disconnects"""
        if user_id in self.ip_sessions[ip]:
            self.ip_sessions[ip].remove(user_id)
            if not self.ip_sessions[ip]:
                del self.ip_sessions[ip]
    
    def get_session_count_for_ip(self, ip: str) -> int:
        """Get the number of active sessions for an IP address"""
        return len(self.ip_sessions.get(ip, set()))
    
    async def is_rate_limited(self, user_id: str, request_type: str, role: str) -> bool:
        """Check if a user is currently rate limited for a request type"""
        async with self.lock:
            current_minute = int(time.time() / 60)
            prev_minute = current_minute - 1
            
            # Count requests in current and previous minute
            current_count = self.time_buckets[user_id][current_minute][request_type]
            prev_count = self.time_buckets[user_id][prev_minute][request_type]
            
            # Calculate requests per minute rate (weighted average)
            # Weight current minute more as it's more recent
            rate = (current_count * 0.7) + (prev_count * 0.3)
            
            # Get rate limit based on user role
            limit = self.rate_limits.get(role, self.rate_limits['anon']).get(
                request_type, self.rate_limits['anon']['other'])
            
            # Check if rate exceeds limit
            return rate >= limit
    
    def get_metrics(self) -> Dict:
        """Get a snapshot of current metrics"""
        active_users = {
            'total': len(self.user_metrics),
            'anon': 0,
            'normal': 0,
            'pro': 0,
            'admin': 0,
        }
        
        # Count active users in the last 5 minutes
        active_cutoff = time.time() - (5 * 60)
        for user_data in self.user_metrics.values():
            if user_data['last_active'] >= active_cutoff:
                active_users[user_data['role']] += 1
        
        return {
            'uptime_seconds': int(time.time() - self.start_time),
            'total_requests': dict(self.total_requests),
            'active_users': active_users,
            'active_ips': len(self.ip_sessions),
            'timestamp': datetime.datetime.now().isoformat()
        }

    def get_detailed_metrics(self) -> Dict:
        """Get detailed metrics including per-user data"""
        metrics = self.get_metrics()
        
        # Add anonymized user metrics
        user_list = []
        for user_id, data in self.user_metrics.items():
            # Skip users inactive for more than 1 hour
            if time.time() - data['last_active'] > 3600:
                continue
                
            user_list.append({
                'id': user_id[:8] + '...',  # Anonymize ID
                'role': data['role'],
                'requests': data['requests'],
                'active_ago': int(time.time() - data['last_active']),
                'session_duration': int(time.time() - data['first_seen'])
            })
        
        metrics['users'] = user_list
        return metrics