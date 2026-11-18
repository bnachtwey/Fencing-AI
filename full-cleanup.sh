#!/bin/sh
# kill ALL containers / pods
podman kill $(podman compose -f compose-claude.yaml ps -q)

# remove ALL conatainers / pods (must run twice)
podman rm $(podman compose -f compose-claude.yaml ps -q)
podman rm $(podman compose -f compose-claude.yaml ps -q)

# remove ALL images
podman image rm $(podman compose -f compose-claude.yaml images -q)