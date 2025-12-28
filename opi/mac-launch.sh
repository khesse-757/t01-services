#!/bin/bash
THIS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
NETWORK="t01-services_channel_access"

# Allow XQuartz connections
xhost + 127.0.0.1 > /dev/null

echo "Launching Phoebus on network: $NETWORK"

docker run -it --rm \
  --platform linux/amd64 \
  -e DISPLAY=host.docker.internal:0 \
  --network $NETWORK \
  -v "${THIS_DIR}:/workspace" \
  ghcr.io/epics-containers/ec-phoebus:latest \
  -resource /workspace/demo.bob \
  -settings /workspace/settings.ini
