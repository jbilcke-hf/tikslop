"""
Colored logging utilities for the TikSlop server.
"""
import logging
import re

# ANSI color codes
class Colors:
    RESET = '\033[0m'
    BOLD = '\033[1m'
    DIM = '\033[2m'
    
    # Foreground colors
    BLACK = '\033[30m'
    RED = '\033[31m'
    GREEN = '\033[32m'
    YELLOW = '\033[33m'
    BLUE = '\033[34m'
    MAGENTA = '\033[35m'
    CYAN = '\033[36m'
    WHITE = '\033[37m'
    
    # Bright colors
    BRIGHT_BLACK = '\033[90m'
    BRIGHT_RED = '\033[91m'
    BRIGHT_GREEN = '\033[92m'
    BRIGHT_YELLOW = '\033[93m'
    BRIGHT_BLUE = '\033[94m'
    BRIGHT_MAGENTA = '\033[95m'
    BRIGHT_CYAN = '\033[96m'
    BRIGHT_WHITE = '\033[97m'
    
    # Background colors
    BG_BLACK = '\033[40m'
    BG_RED = '\033[41m'
    BG_GREEN = '\033[42m'
    BG_YELLOW = '\033[43m'
    BG_BLUE = '\033[44m'
    BG_MAGENTA = '\033[45m'
    BG_CYAN = '\033[46m'
    BG_WHITE = '\033[47m'

class ColoredFormatter(logging.Formatter):
    """Custom formatter with colors and patterns"""
    
    def __init__(self):
        super().__init__()
        
    def format(self, record):
        # Color mapping for log levels
        level_colors = {
            'DEBUG': Colors.BRIGHT_BLACK,
            'INFO': Colors.BRIGHT_CYAN,
            'WARNING': Colors.BRIGHT_YELLOW,
            'ERROR': Colors.BRIGHT_RED,
            'CRITICAL': Colors.BRIGHT_MAGENTA + Colors.BOLD
        }
        
        # Format timestamp
        timestamp = f"{Colors.DIM}{self.formatTime(record, '%H:%M:%S.%f')[:-3]}{Colors.RESET}"
        
        # Format level with color
        level_color = level_colors.get(record.levelname, Colors.WHITE)
        level = f"{level_color}{record.levelname:>7}{Colors.RESET}"
        
        # Format logger name
        logger_name = f"{Colors.BRIGHT_BLACK}[{record.name}]{Colors.RESET}"
        
        # Format message with keyword highlighting
        message = self.colorize_message(record.getMessage())
        
        return f"{timestamp} {level} {logger_name} {message}"
    
    def colorize_message(self, message):
        """Add colors to specific keywords and patterns in the message"""
        
        # Highlight request IDs in brackets (gray like logger names)
        message = re.sub(r'\[([a-f0-9-]{36})\]', f'{Colors.BRIGHT_BLACK}[\\1]{Colors.RESET}', message)
        
        # Highlight user IDs
        message = re.sub(r'user ([a-zA-Z0-9-]+)', f'user {Colors.BRIGHT_BLUE}\\1{Colors.RESET}', message)
        
        # Highlight actions
        message = re.sub(r'(generate_video|search|simulate|join_chat|leave_chat|chat_message)', 
                        f'{Colors.BRIGHT_YELLOW}\\1{Colors.RESET}', message)
        
        # Highlight status keywords
        message = re.sub(r'\b(success|successful|completed|connected|ready)\b', 
                        f'{Colors.BRIGHT_GREEN}\\1{Colors.RESET}', message, flags=re.IGNORECASE)
        
        message = re.sub(r'\b(error|failed|timeout|exception)\b', 
                        f'{Colors.BRIGHT_RED}\\1{Colors.RESET}', message, flags=re.IGNORECASE)
        
        message = re.sub(r'\b(warning|retry|reconnect)\b', 
                        f'{Colors.BRIGHT_YELLOW}\\1{Colors.RESET}', message, flags=re.IGNORECASE)
        
        # Highlight numbers (timing, counts, etc.) but not those inside UUIDs
        message = re.sub(r'(?<![a-f0-9-])\b(\d+\.?\d*)(s|ms|chars|bytes)?\b(?![a-f0-9-])', 
                        f'{Colors.BRIGHT_MAGENTA}\\1{Colors.CYAN}\\2{Colors.RESET}', message)
        
        # Highlight roles
        message = re.sub(r'\b(role|user_role)=([a-zA-Z]+)', 
                        f'\\1={Colors.BRIGHT_CYAN}\\2{Colors.RESET}', message)
        
        # Highlight titles in quotes
        message = re.sub(r"title='([^']*)'", f"title='{Colors.GREEN}\\1{Colors.RESET}'", message)
        
        return message

def setup_colored_logging():
    """Set up colored logging for the entire application"""
    
    # Configure logging with colors
    logging.basicConfig(
        level=logging.INFO,
        handlers=[
            logging.StreamHandler()
        ]
    )

    # Set up colored formatter
    handler = logging.StreamHandler()
    handler.setFormatter(ColoredFormatter())

    # Apply to root logger and clear default handlers
    root_logger = logging.getLogger()
    root_logger.handlers.clear()
    root_logger.addHandler(handler)

def get_logger(name):
    """Get a logger with the given name"""
    return logging.getLogger(name)