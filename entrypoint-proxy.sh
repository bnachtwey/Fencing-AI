#!/bin/sh
set -eu
: "${SQUIDLOG:=/squidlog}"
mkdir -p "$SQUIDLOG"
sed "s|@SQUIDLOG@|${SQUIDLOG}|g" /etc/squid/squid.conf.template > /tmp/squid.conf
exec "$@"