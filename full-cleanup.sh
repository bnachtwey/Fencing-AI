#!/bin/sh
set -eu

COMPOSE_FILE="${COMPOSE_FILE:-compose-claude.yaml}"
PODMAN_COMPOSE="${PODMAN_COMPOSE:-podman-compose}"

podman_compose() { "$PODMAN_COMPOSE" -f "$COMPOSE_FILE" "$@"; }

# 1. Tear down compose stack, remove containers, pods and networks
podman_compose down --remove-orphans 2>/dev/null || true

# 2. Remove any remaining containers across all projects (including proxy pods)
remaining=$(podman ps -aq 2>/dev/null | grep -v '^$' || true)
if [ -n "$remaining" ]
then
    for cid in $remaining
    do
        podman rm -f "$cid" 2>/dev/null || true
    done
fi

# 3. Remove any remaining pods
remaining_pods=$(podman pod ls -q 2>/dev/null || true)
if [ -n "$remaining_pods" ]
then
    for pid in $remaining_pods
    do
        podman pod rm -f "$pid" 2>/dev/null || true
    done
fi

# 4. Remove ALL images
podman image prune -a -f 2>/dev/null || true