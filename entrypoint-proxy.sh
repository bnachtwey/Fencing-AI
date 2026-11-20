#!/bin/sh
set -e

# Squid drops privileges to the "squid" user before opening its log files,
# and a bind mount hides any chown done at build time -> fix it at start.
# Also generate squid.conf from template with SQUIDLOG substituted.
mkdir -p "${SQUIDLOG:-/squidlog}"
chown squid:squid "${SQUIDLOG:-/squidlog}"
sed -e "s|@SQUIDLOG@|${SQUIDLOG:-/squidlog}|g" /etc/squid/squid.conf.template > /etc/squid/squid.conf

# Hand over to the CMD (squid -N ...). exec keeps squid as PID 1 so it
# receives SIGTERM from `compose stop` and shuts down cleanly.
exec "$@"