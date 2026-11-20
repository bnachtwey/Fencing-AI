#!/bin/sh
set -e

# Populate $HOME from /etc/skel; -n = never overwrite existing files
mkdir -p "$HOME"
cp -a -n /etc/skel/. "$HOME"/ 2>/dev/null || true

# Register the vendored ponytail plugin (local path, no network needed)
MP_NAME=ponytail   # must match "name" in /opt/ponytail/.claude-plugin/marketplace.json
if [ -d /opt/ponytail ]; then
  claude plugin marketplace list 2>/dev/null | grep -q "$MP_NAME" \
    || claude plugin marketplace add /opt/ponytail \
    || echo "warn: could not add ponytail marketplace" >&2
  claude plugin list 2>/dev/null | grep -q ponytail \
    || claude plugin install "ponytail@$MP_NAME" \
    || echo "warn: could not install ponytail plugin" >&2
fi

exec "$@"
