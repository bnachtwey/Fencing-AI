#!/bin/sh
set -e

mkdir -p "$HOME"
cp -a -n /etc/skel/. "$HOME"/ 2>/dev/null || true
exec "$@"
