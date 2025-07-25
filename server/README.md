
  server/
  ├── __init__.py
  ├── api_config.py           # Configuration constants
  ├── api_core.py            # Main API class (now much cleaner!)
  ├── api_metrics.py         # Metrics functionality  
  ├── api_session.py         # Session management
  ├── chat.py               # Chat room management
  ├── config_utils.py       # Configuration utilities
  ├── endpoint_manager.py   # Endpoint management with error handling
  ├── llm_utils.py         # LLM client and text generation
  ├── models.py            # Data models and types
  ├── utils.py             # Generic utilities (YAML parsing, etc.)
  └── video_utils.py       # Video generation (HF endpoints + Gradio)