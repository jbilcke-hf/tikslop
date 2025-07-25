"""
Configuration utilities for user role-based settings.
"""
from typing import Any, Dict, Optional
from .models import UserRole
from .api_config import (
    CONFIG_FOR_ADMIN_HF_USERS,
    CONFIG_FOR_PRO_HF_USERS,
    CONFIG_FOR_STANDARD_HF_USERS,
    CONFIG_FOR_ANONYMOUS_USERS
)


def get_config_value(role: UserRole, field: str, options: Optional[Dict[str, Any]] = None) -> Any:
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