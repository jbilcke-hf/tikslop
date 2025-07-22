
## Deploying TikSlop to https://tikslop.com

Note: this document is meant for TikSlop administrators only, not the general public.

TikSlop is not an app/tool but a website, it is not designed to be cloned (technically you can, but since this is not a goal it is not documented).

### Setup the domain

TODO

### Seting up the Python virtual environment

```bash
python3 -m venv .python_venv
source .python_venv/bin/activate
python3 -m pip install --no-cache-dir --upgrade -r requirements.txt 
```

### Local testing

First you need to build the app:

    $ flutter build web

Then run the server.

See paragraph "Running the gateway scheduler"

### Deployment to production

To deploy the TikSlop api to production:

    $ flutter build web
    $ git add .
    $ got commit -m "<description>"
    $ git push public main

and upload the assets to:

    https://huggingface.co/spaces/jbilcke-hf/tikslop/tree/main/public

#### Running a rendering node

Currently TikSlop uses [jbilcke-hf/LTX-Video-2b-0-9-8-distilled-HFIE](https://huggingface.co/jbilcke-hf/LTX-Video-2b-0-9-8-distilled-HFIE) as a rendering node.

TikSlop uses a round-robin schedule implemented on the gateway.
This helps ensuring a smooth attribution of requests.

What works well is to use the target number of users in parallel (eg. 3) and use 50% more capability to make sure we can handle the load, so in this case about 5 or 6 servers.

```bash
# note: you need to replace <YOUR_ACCOUNT_NAME>, <ROUND_ROBIN_INDEX> and <YOUR_HF_TOKEN>

curl https://api.endpoints.huggingface.cloud/v2/endpoint/<YOUR_ACCOUNT_NAME> 	-X POST 	-d '{"cacheHttpResponses":false,"compute":{"accelerator":"gpu","instanceSize":"x1","instanceType":"nvidia-l40s","scaling":{"maxReplica":1,"measure":{"hardwareUsage":80},"minReplica":0,"scaleToZeroTimeout":120,"metric":"hardwareUsage"}},"model":{"env":{},"framework":"custom","image":{"huggingface":{}},"repository":"jbilcke-hf/LTX-Video-2b-0-9-8-distilled-HFIE","secrets":{},"task":"custom","fromCatalog":false},"name":"ltx-video-2b-0-9-8-node-<ROUND_ROBIN_INDEX>","provider":{"region":"us-east-1","vendor":"aws"},"tags":[""],"type":"protected"}' 	-H "Content-Type: application/json" 	-H "Authorization: Bearer <YOUR_HF_TOKEN>"
```

#### Running the gateway scheduler

```bash
# load the environment
# (if you haven't done it already for this shell session)
source .python_venv/bin/activate
    
PRODUCT_NAME="TikSlop" \
    MAX_NODES="3" \
    MAINTENANCE_MODE=false \
    HF_TOKEN="<USE YOUR OWN HF TOKEN>" \
    SECRET_TOKEN="<USE YOUR OWN TIKSLOP SECRET>" \
    VIDEO_ROUND_ROBIN_SERVER_1="https:/<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    VIDEO_ROUND_ROBIN_SERVER_2="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    VIDEO_ROUND_ROBIN_SERVER_3="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    VIDEO_ROUND_ROBIN_SERVER_4="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    VIDEO_ROUND_ROBIN_SERVER_5="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    VIDEO_ROUND_ROBIN_SERVER_6="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    HF_IMAGE_MODEL="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    HF_TEXT_MODEL="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    python3 api.py
```

### Run the client (web)

```bash
# For local development with default configuration
flutter run --dart-define=CONFIG_PATH=assets/config/tikslop.yaml -d chrome

# For production build to be deployed on a server
flutter build web --dart-define=CONFIG_PATH=assets/config/tikslop.yaml
```

### WebSocket Connection

The application automatically determines the WebSocket URL:

1. **Web Platform**: 
   - Automatically uses the same host that serves the web app
   - Handles HTTP/HTTPS protocol correctly (ws/wss)
   - No configuration needed for deployment

2. **Native Platforms**:
   - Production: Automatically uses `wss://tikslop.com/ws` when built with production flag
   - Development: Uses `ws://localhost:8080/ws` by default
   - Custom: Can override with `API_WS_URL` environment variable (highest priority)

#### Production Native Build

For production builds (connecting to tikslop.com):
```bash
flutter build apk --dart-define=CONFIG_PATH=assets/config/tikslop.yaml --dart-define=PRODUCTION_MODE=true
```

#### Custom API Server

For connecting to a different server:
```bash
flutter build apk --dart-define=CONFIG_PATH=assets/config/tikslop.yaml --dart-define=API_WS_URL=ws://custom-api.example.com/ws
```

Note: The `API_WS_URL` parameter takes precedence over the production setting.

