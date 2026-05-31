#!/usr/bin/env bash
set -euo pipefail

LOG="/hermes-data/logs"
mkdir -p "$LOG"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# ── Ensure persistent directories ────────────────────────
mkdir -p /hermes-data/logs /hermes-data/tailscale

# ── Tailscale ────────────────────────────────────────────
log "Starting Tailscale..."
tailscaled --tun=userspace-networking --state=/hermes-data/tailscale.state &
TAILSCALED_PID=$!

log "Waiting for tailscaled socket..."
for i in $(seq 1 30); do
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 1
done
if [ ! -S /var/run/tailscale/tailscaled.sock ]; then
    log "FATAL: tailscaled did not start (no socket)"
    # Don't exit — keep container alive for debugging
    tail -f /dev/null
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
/usr/sbin/sshd -D &
SSHD_PID=$!
log "SSHD: port 22"

# ── Config generation ────────────────────────────────────
log "Generating Hermes config..."
python3 /hermes-agent/scripts/generate_config_helper.py 2>/dev/null || true

# ── Hermes Gateway ───────────────────────────────────────
log "Starting Hermes Gateway..."
export PATH="/hermes-venv/bin:$PATH"

# Read OPENROUTER_API_KEY from environment
if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    log "WARNING: OPENROUTER_API_KEY not set in environment"
fi

# Start gateway — restart loop so it survives crashes
(
    while true; do
        log "Gateway starting (PID $$)..."
        hermes gateway run >> "$LOG/gateway.log" 2>&1
        GW_EXIT=$?
        log "Gateway exited with code $GW_EXIT, restarting in 5s..."
        sleep 5
    done
) &
GW_LOOP_PID=$!
log "Gateway loop started (PID: $GW_LOOP_PID)"

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

# ── Wait forever ─────────────────────────────────────────
# Wait for any child — if one dies, the script stays alive
wait -n $TAILSCALED_PID $SSHD_PID $GW_LOOP_PID $DASH_PID 2>/dev/null || true
log "A child process exited, keeping container alive..."
sleep 5

# If we get here, keep the container running
tail -f /dev/null
