#!/usr/bin/env bash
set -euo pipefail
LOG="/hermes-data/logs"
mkdir -p "$LOG"
log() { echo "[$(date -u +%H:%M:%S)] $*"; }

log "Hermes Agent starting..."

# ── Tailscale ────────────────────────────────────────────
log "Starting Tailscale..."
tailscaled --tun=userspace-networking --state=/hermes-data/tailscale.state &
TAILSCALED_PID=$!
log "Waiting for tailscaled socket..."
for i in $(seq 1 20); do
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 1
done
if [ ! -S /var/run/tailscale/tailscaled.sock ]; then
    log "FATAL: tailscaled did not start (no socket)"
    exit 1
fi

TS_HOST="${TS_HOSTNAME:-hermes-$(openssl rand -hex 4)}"
tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOST" --accept-routes 2>&1 | tail -3
sleep 3
tailscale set --ssh 2>&1 | tail -3
sleep 2
TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
log "Tailscale: $TS_IP"

# ── SSHD ─────────────────────────────────────────────────
log "Starting SSHD..."
mkdir -p /root/.ssh && chmod 700 /root/.ssh
[ -n "${SSH_PUBLIC_KEY:-}" ] && echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
/usr/sbin/sshd &
log "SSHD: port 22"

# ── Hermes Gateway (background with auto-restart) ────────
log "Starting Hermes Gateway..."
export PATH="/hermes-venv/bin:$PATH"

# Start gateway in a subshell that auto-restarts
(
    count=0
    while [ $count -lt 50 ]; do
        hermes gateway run >> "$LOG/gateway.log" 2>&1
        code=$?
        count=$((count + 1))
        log "Gateway exited (code: $code), restarting in 3s... (#$count)"
        sleep 3
    done
    log "Gateway restart limit reached"
) &
GW_LOOP_PID=$!
log "Gateway restart loop started"

# Give gateway a moment to start
sleep 5

# Verify it's running
if kill -0 $GW_LOOP_PID 2>/dev/null; then
    log "Gateway loop running"
else
    log "WARNING: Gateway loop failed to start"
fi

# ── Dashboard ────────────────────────────────────────────
log "Starting Dashboard..."
hermes-web-ui start --port 8648 >> "$LOG/dashboard.log" 2>&1 &
DASH_PID=$!
sleep 3
log "Dashboard: port 8648"

# ── Health check ─────────────────────────────────────────
python3 -c "
import http.server,socketserver
H=type('H',(http.server.BaseHTTPRequestHandler,),{'do_GET':lambda s:(s.send_response(200),s.send_header('Content-Type','text/plain'),s.end_headers(),s.wfile.write(b'ok')),'log_message':lambda *a:None})
socketserver.TCPServer(('0.0.0.0',8080),H).serve_forever()
" > "$LOG/health.log" 2>&1 &

log "LIVE — Tailscale: $TS_IP"

# — Wait for all critical processes —
# If any critical process dies, the script exits and container restarts
wait $GW_LOOP_PID $TAILSCALED_PID
log "Critical process exited, container will restart..."
sleep 2
