#!/bin/bash
set -eo pipefail

echo "=========================================================="
echo " Starting Turnkey Multi-Service Gateway on Render"
echo "=========================================================="

# Default PORT to 10000 if not set by Render
export PORT="${PORT:-10000}"
echo "[*] Ingress Port configured: ${PORT}"

# Automatically propagate Redis URL to REDIS_URL for services like data-pulse if VAULT_ADDRESS is configured
if [ -z "${REDIS_URL}" ] && [ -n "${VAULT_ADDRESS}" ]; then
    export REDIS_URL="${VAULT_ADDRESS}"
    echo "[*] Mapped VAULT_ADDRESS to REDIS_URL for multi-service telemetry caching"
fi

# Template Nginx configuration using envsubst
echo "[*] Interpolating Nginx configuration template..."
envsubst '${PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Validate Nginx syntax
echo "[*] Testing Nginx configuration integrity..."
nginx -t -c /etc/nginx/nginx.conf

echo "[*] Handing over execution to Supervisord (PID 1)..."
echo "=========================================================="
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
