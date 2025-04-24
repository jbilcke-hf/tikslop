
## Deploying aitube2 to https://aitube.at

Note: this document is meant for aitube administrators only, not the general public.

Aitube is not an app/tool but a website, it is not designed to be cloned (technically you can, but since this is not a goal it is not documented).

### Setup the domain

TODO

### Seting up the Python virtual environment

```bash
python3 -m venv .python_venv
source .python_venv/bin/activate
python3 -m pip install --no-cache-dir --upgrade -r requirements.txt 
```

### Deployment to production

To deploy the aitube2 api to production:

    $ git push space main

To deploy the aitube2 client to production, simply run:

    $ flutter run web

and upload the assets to:

    https://huggingface.co/spaces/jbilcke-hf/aitube2/tree/main/public

#### Running a rendering node

Current aitube uses `jbilcke-hf/LTX-Video-0-9-6-HFIE` as a rendering node.

aitube uses a round-robin schedule implemented on the gateway.
This helps ensuring a smooth attribution of requests.

What works well is to use the target number of users in parallel (eg. 3) and use 50% more capability to make sure we can handle the load, so in this case about 5 servers.

```bash
# note: you need to replace <YOUR_ACCOUNT_NAME>, <ROUND_ROBIN_INDEX> and <YOUR_HF_TOKEN>

curl https://api.endpoints.huggingface.cloud/v2/endpoint/<YOUR_ACCOUNT_NAME> 	-X POST 	-d '{"cacheHttpResponses":false,"compute":{"accelerator":"gpu","instanceSize":"x1","instanceType":"nvidia-l40s","scaling":{"maxReplica":1,"measure":{"hardwareUsage":80},"minReplica":0,"scaleToZeroTimeout":120,"metric":"hardwareUsage"}},"model":{"env":{},"framework":"custom","image":{"huggingface":{}},"repository":"jbilcke-hf/LTX-Video-0-9-6-HFIE","secrets":{},"task":"custom","fromCatalog":false},"name":"ltx-video-0-9-6-round-robin-<ROUND_ROBIN_INDEX>","provider":{"region":"us-east-1","vendor":"aws"},"tags":[""],"type":"protected"}' 	-H "Content-Type: application/json" 	-H "Authorization: Bearer <YOUR_HF_TOKEN>"
```

#### Running the gateway scheduler

```bash
# load the environment
# (if you haven't done it already for this shell session)
source .python_venv/bin/activate

HF_TOKEN="<USE YOUR OWN TOKEN>" \
    SECRET_TOKEN="<USE YOUR OWN TOKEN>" \
    VIDEO_ROUND_ROBIN_SERVER_1="https:/<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    VIDEO_ROUND_ROBIN_SERVER_2="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    VIDEO_ROUND_ROBIN_SERVER_3="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    VIDEO_ROUND_ROBIN_SERVER_4="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    HF_IMAGE_MODEL="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    HF_TEXT_MODEL="https://<USE YOUR OWN SERVER>.endpoints.huggingface.cloud" \
    python3 api.py
```

### Run the client (web)

```bash

flutter run --dart-define=CONFIG_PATH=assets/config/aitube_low.yaml -d chrome
```

