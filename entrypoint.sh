#!/bin/bash
set -eo pipefail

echo "=========================================================="
echo " Starting Turnkey Multi-Service Gateway on Render"
echo "=========================================================="

# Default PORT to 10000 if not set by Render
export PORT="${PORT:-10000}"
echo "[*] Ingress Port configured: ${PORT}"

# Template Nginx configuration using envsubst
echo "[*] Interpolating Nginx configuration template..."
envsubst '${PORT}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

# Validate Nginx syntax
echo "[*] Testing Nginx configuration integrity..."
nginx -t -c /etc/nginx/nginx.conf

echo "[*] Handing over execution to Supervisord (PID 1)..."
echo "=========================================================="
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
