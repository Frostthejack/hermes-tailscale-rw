#!/bin/bash
set -e

echo "[entrypoint] Starting Tailscale daemon..."
tailscaled --tun=userspace-networking &
TAILSCALED_PID=$!

# Wait for tailscaled to be ready
sleep 2

echo "[entrypoint] Authenticating with Tailscale..."
if [ -z "$TS_AUTHKEY" ]; then
    echo "[entrypoint] ERROR: TS_AUTHKEY not set"
    exit 1
fi

tailscale up --authkey="$TS_AUTHKEY" --hostname=hermes-agent

echo "[entrypoint] Tailscale connected. Starting Hermes Agent..."
cd /app
python server.py &
SERVER_PID=$!

# Keep container alive
wait $TAILSCALED_PID $SERVER_PID
