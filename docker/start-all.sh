#!/usr/bin/env bash
set -euo pipefail
LOG="/hermes-data/logs"
mkdir -p "$LOG"
log() { echo "[$(date -u +%H:%M:%S)] $*"; }

log "Hermes Agent starting..."

# ── Config generation (from env vars) ────────────────────
if [ ! -f /root/.hermes/.env ]; then
    log "Creating .env..."
    : > /root/.hermes/.env
    [ -n "${OPENROUTER_API_KEY:-}" ] && echo "OPENROUTER_API_KEY=*** >> /root/.hermes/.env
    [ -n "${DATABASE_URL:-}" ] && echo "DATABASE_URL=${DATABASE_URL}" >> /root/.hermes/.env
    echo "API_SERVER_ENABLED=true" >> /root/.hermes/.env
    echo "API_SERVER_PORT=8642" >> /root/.hermes/.env
    echo "HINDSIGHT_MODE=local_embedded" >> /root/.hermes/.env
    echo "HINDSIGHT_BANK_ID=${HINDSIGHT_BANK_ID:-hermes-railway}" >> /root/.hermes/.env
    log "Created .env ($(wc -l < /root/.hermes/.env) lines)"
fi

if [ ! -f /root/.hermes/config.yaml ]; then
    log "Creating config.yaml..."
    cat > /root/.hermes/config.yaml << 'YAMLEOF'
model:
  provider: openrouter
  default: "@preset/hermes"
  api_mode: chat_completions
  context_length: 131072
agent:
  max_turns: 90
terminal:
  backend: local
  cwd: /root
  timeout: 180
compression:
  enabled: true
  threshold: 0.50
  target_ratio: 0.20
display:
  personality: default
  reasoning: off
  bell: false
memory:
  memory_enabled: true
  user_profile_enabled: true
  provider: hindsight
plugins:
  enabled:
    - hindsight
security:
  tirith_enabled: false
delegation:
  max_iterations: 50
checkpoints:
  enabled: true
  max_snapshots: 50
stt:
  enabled: false
tts:
  provider: edge
YAMLEOF
    log "Created config.yaml"
fi

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
    log "FATAL: tailscaled did not start (no socket)"; exit 1
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

# ── Hermes Gateway ───────────────────────────────────────
log "Starting Hermes Gateway..."
export PATH="/hermes-venv/bin:$PATH"
hermes gateway run > "$LOG/gateway.log" 2>&1 &
GW_PID=$!
for i in $(seq 1 30); do sleep 2; kill -0 $GW_PID 2>/dev/null || { log "Gateway died"; exit 1; }; done
log "Gateway running"

# ── Dashboard ────────────────────────────────────────────
log "Starting Dashboard..."
hermes-web-ui start --port 8648 > "$LOG/dashboard.log" 2>&1 &
sleep 3
log "Dashboard: port 8648"

# ── Health check ─────────────────────────────────────────
python3 -c "
import http.server,socketserver
H=type('H',(http.server.BaseHTTPRequestHandler,),{'do_GET':lambda s:(s.send_response(200),s.send_header('Content-Type','text/plain'),s.end_headers(),s.wfile.write(b'ok')),'log_message':lambda *a:None})
socketserver.TCPServer(('0.0.0.0',8080),H).serve_forever()
" > "$LOG/health.log" 2>&1 &

log "LIVE — Tailscale: $TS_IP"
wait $GW_PID
