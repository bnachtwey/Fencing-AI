#!/bin/sh
# Populate $HOME from /etc/skel; -n = never overwrite existing files
mkdir -p "$HOME"
cp -a -n /etc/skel/. "$HOME"/ 2>/dev/null || true
exec "$@"
