import os

PRODUCT_NAME = os.environ.get('PRODUCT_NAME', 'AiTube')
PRODUCT_VERSION = "2.0.0"

# you should use Mistral 7b instruct for good performance and accuracy balance
TEXT_MODEL = os.environ.get('HF_TEXT_MODEL', '')

# Environment variable to control maintenance mode
MAINTENANCE_MODE = os.environ.get('MAINTENANCE_MODE', 'false').lower() in ('true', 'yes', '1', 't')

# Environment variable to control how many nodes to use
MAX_NODES = int(os.environ.get('MAX_NODES', '8'))

ADMIN_ACCOUNTS = [
    "jbilcke-hf"
]

RAW_VIDEO_ROUND_ROBIN_ENDPOINT_URLS = [
    os.environ.get('VIDEO_ROUND_ROBIN_SERVER_1', ''),
    os.environ.get('VIDEO_ROUND_ROBIN_SERVER_2', ''),
    os.environ.get('VIDEO_ROUND_ROBIN_SERVER_3', ''),
    os.environ.get('VIDEO_ROUND_ROBIN_SERVER_4', ''),
    os.environ.get('VIDEO_ROUND_ROBIN_SERVER_5', ''),
    os.environ.get('VIDEO_ROUND_ROBIN_SERVER_6', ''),
    os.environ.get('VIDEO_ROUND_ROBIN_SERVER_7', ''),
    os.environ.get('VIDEO_ROUND_ROBIN_SERVER_8', ''),
]

# Filter out empty strings from the endpoint list
filtered_urls = [url for url in RAW_VIDEO_ROUND_ROBIN_ENDPOINT_URLS if url]

# Limit the number of URLs based on MAX_NODES environment variable
VIDEO_ROUND_ROBIN_ENDPOINT_URLS = filtered_urls[:MAX_NODES]

HF_TOKEN = os.environ.get('HF_TOKEN')

# use the same secret token as you used to secure your BASE_SPACE_NAME spaces
SECRET_TOKEN = os.environ.get('SECRET_TOKEN')

# altenative words we could use: "saturated, highlight, overexposed, highlighted, overlit, shaking, too bright, worst quality, inconsistent motion, blurry, jittery, distorted, cropped, watermarked, watermark, logo, subtitle, subtitles, lowres"
NEGATIVE_PROMPT = "low quality, worst quality, deformed, distorted, disfigured, blurry, text, watermark"

POSITIVE_PROMPT_SUFFIX = "high quality, cinematic, 4K, intricate details"

GUIDANCE_SCALE = 1.0

THUMBNAIL_FRAMES = 65

# anonymous users are people browing AiTube2 without being connected
# this category suffers from regular abuse so we need to enforce strict limitations
CONFIG_FOR_ANONYMOUS_USERS = {

    # anons can only watch 2 minutes per video
    "max_rendering_time_per_client_per_video_in_sec": 2 * 60,

    "min_num_inference_steps": 2,
    "default_num_inference_steps": 3,
    "max_num_inference_steps": 3,

    "min_num_frames": 9, # 8 + 1
    "default_max_num_frames": 65, # 8*8 + 1
    "max_num_frames": 65, # 8*8 + 1

    "min_clip_duration_seconds": 1,
    "default_clip_duration_seconds": 2,
    "max_clip_duration_seconds": 2,

    "min_clip_playback_speed": 0.7,
    "default_clip_playback_speed": 0.7,
    "max_clip_playback_speed": 0.7,

    "min_clip_framerate": 8,
    "default_clip_framerate": 16,
    "max_clip_framerate": 16,

    "min_clip_width": 544,
    "default_clip_width": 544,
    "max_clip_width": 544,

    "min_clip_height": 320,
    "default_clip_height": 320,
    "max_clip_height": 320,
}

# Hugging Face users enjoy a more normal and calibrated experience
CONFIG_FOR_STANDARD_HF_USERS = {
    "max_rendering_time_per_client_per_video_in_sec": 15 * 60,

    "min_num_inference_steps": 2,
    "default_num_inference_steps": 4,
    "max_num_inference_steps": 4,
    
    "min_num_frames": 9, # 8 + 1
    "default_num_frames": 81, # 8*10 + 1
    "max_num_frames": 81,

    "min_clip_duration_seconds": 1,
    "default_clip_duration_seconds": 3,
    "max_clip_duration_seconds": 3,

    "min_clip_playback_speed": 0.7,
    "default_clip_playback_speed": 0.7,
    "max_clip_playback_speed": 0.7,

    "min_clip_framerate": 8,
    "default_clip_framerate": 25,
    "max_clip_framerate": 25,

    "min_clip_width": 544,
    "default_clip_width": 1152, # 928, # 1216, # 768, # 640,
    "max_clip_width": 1152, # 928, # 1216, # 768, # 640,

    "min_clip_height": 320,
    "default_clip_height": 640, # 512, # 448, # 416,
    "max_clip_height": 640, # 512, # 448, # 416,
}

# Hugging Face users with a Pro may enjoy an improved experience
CONFIG_FOR_PRO_HF_USERS = {
    "max_rendering_time_per_client_per_video_in_sec": 20 * 60,

    "min_num_inference_steps": 2,
    "default_num_inference_steps": 4,
    "max_num_inference_steps": 4,
    
    "min_num_frames": 9, # 8 + 1
    "default_num_frames": 81, # 8*10 + 1
    "max_num_frames": 81,

    "min_clip_duration_seconds": 1,
    "default_clip_duration_seconds": 3,
    "max_clip_duration_seconds": 3,

    "min_clip_playback_speed": 0.7,
    "default_clip_playback_speed": 0.7,
    "max_clip_playback_speed": 0.7,

    "min_clip_framerate": 8,
    "default_clip_framerate": 25,
    "max_clip_framerate": 25,

    "min_clip_width": 544,
    "default_clip_width": 1152, # 928, # 1216, # 768, # 640,
    "max_clip_width": 1152, # 928, # 1216, # 768, # 640,

    "min_clip_height": 320,
    "default_clip_height": 640, # 512, # 448, # 416,
    "max_clip_height": 640, # 512, # 448, # 416,
}

CONFIG_FOR_ADMIN_HF_USERS = {
    "max_rendering_time_per_client_per_video_in_sec": 60 * 60,

    "min_num_inference_steps": 2,
    "default_num_inference_steps": 4,
    "max_num_inference_steps": 4,

    "min_num_frames": 9, # 8 + 1
    "default_num_frames": 81, # (8 * 10) + 1
    "max_num_frames": 129, # (8 * 16) + 1

    "min_clip_duration_seconds": 1,
    "default_clip_duration_seconds": 2,
    "max_clip_duration_seconds": 4,

    "min_clip_playback_speed": 0.7,
    "default_clip_playback_speed": 0.7,
    "max_clip_playback_speed": 1.0,

    "min_clip_framerate": 8,
    "default_clip_framerate": 30,
    "max_clip_framerate": 60,

    "min_clip_width": 544,
    "default_clip_width": 1152, # 928, # 1216, # 768, # 640,
    "max_clip_width": 1152, # 928, # 1216, # 768, # 640,

    "min_clip_height": 320,
    "default_clip_height": 640, # 512, # 448, # 416,
    "max_clip_height": 640, # 512, # 448, # 416,
}

CONFIG_FOR_ANONYMOUS_USERS = CONFIG_FOR_STANDARD_HF_USERS