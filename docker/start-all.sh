#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# start-all.sh — Hermes Agent on Railway
#
# Boot order:
#   1. Generate config (using Railway DATABASE_URL for Postgres)
#   2. Start Tailscale
#   3. Enable Tailnet SSH
#   4. Start SSHD (traditional SSH on port 22)
#   5. Start Hermes Gateway (with Hindsight via DATABASE_URL)
#   6. Start Hermes Dashboard
#   7. Health check endpoint
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

LOG_DIR="/hermes-data/logs"
mkdir -p "$LOG_DIR"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

echo "═══════════════════════════════════════════════════════"
log "Hermes Agent — Railway"
echo "═══════════════════════════════════════════════════════"

# ── 0. Validate ──────────────────────────────────────────────────────────
log "[0/7] Validating environment..."
if [ -z "${OPENROUTER_API_KEY:-}" ]; then log "FATAL: OPENROUTER_API_KEY not set"; exit 1; fi
if [ -z "${TS_AUTHKEY:-}" ];      then log "FATAL: TS_AUTHKEY not set"; exit 1; fi
if [ -z "${DATABASE_URL:-}" ];    then log "WARN: DATABASE_URL not set — Hindsight will not persist memory"; fi
log "Env vars OK"

# ── 1. Generate config ───────────────────────────────────────────────────
log "[1/7] Generating configuration..."
DATABASE_URL="${DATABASE_URL:-}"
python3 -c "
import os, json, sys
from pathlib import Path
data_dir = Path('/hermes-data')
data_dir.mkdir(parents=True, exist_ok=True)

db_url = os.environ.get('DATABASE_URL', '')

# config.yaml
cfg = '''# Hermes Agent — Auto-generated

model:
  default: '{model}'
  provider: openrouter
  base_url: https://openrouter.ai/api/v1
  api_key: ${{OPENROUTER_API_KEY}}

agent:
  max_turns: 150

terminal:
  backend: local
  timeout: 180

display:
  personality: '{personality}'
  show_reasoning: false
  show_cost: true

compression:
  enabled: true
  threshold: 0.50
  target_ratio: 0.20

memory:
  memory_enabled: true
  provider: hindsight
  auto_retain: true
  retain_every_n_turns: 1
  auto_recall: true

checkpoints:
  enabled: true
  max_snapshots: 50

stt:
  enabled: false

tts:
  provider: edge
'''.format(model=os.environ.get('HERMES_MODEL', '@preset/hermes'), personality=os.environ.get('HERMES_PERSONALITY', 'kawaii'))

(data_dir / 'config.yaml').write_text(cfg)

# .env — secrets only
env_lines = ['API_SERVER_ENABLED=true', 'API_SERVER_PORT=8642', 'HINDSIGHT_MODE=local_embedded', 'HINDSIGHT_URL=http://127.0.0.1:8888']
for key in ['OPENROUTER_API_KEY', 'API_SERVER_KEY', 'DISCORD_BOT_TOKEN', 'TELEGRAM_BOT_TOKEN', 'GH_TOKEN']:
    val = os.environ.get(key, '')
    if val:
        env_lines.append(f'{key}={val}')
if db_url:
    env_lines.append(f'HINDSIGHT_DB_URL={db_url}')
    env_lines.append(f'DATABASE_URL={db_url}')
(data_dir / '.env').write_text('\\n'.join(env_lines) + '\\n')

# hindsight/config.json
hdir = data_dir / 'hindsight'
hdir.mkdir(parents=True, exist_ok=True)
hcfg = {'mode': 'local_embedded', 'api_url': 'http://127.0.0.1:8888', 'bank_id': os.environ.get('HINDSIGHT_BANK_ID', 'hermes-railway'), 'recall_budget': 'mid', 'auto_retain': True, 'retain_every_n_turns': 1, 'auto_recall': True, 'retain_async': True}
(hdir / 'config.json').write_text(json.dumps(hcfg, indent=2) + '\\n')

# Symlink into /root/.hermes/
hh = Path('/root/.hermes')
hh.mkdir(parents=True, exist_ok=True)
for name in ['config.yaml', '.env', 'hindsight']:
    src = data_dir / name
    dst = hh / name
    if src.exists() and not dst.exists():
        dst.symlink_to(src)

print('config.yaml ✓')
print(f'.env ✓ ({len(env_lines)} vars)')
print('hindsight/config.json ✓')
if db_url:
    print(f'Hindsight DB: connected')
else:
    print('Hindsight DB: NOT CONFIGURED (set DATABASE_URL)')
" 2>&1 | while read l; do log "  $l"; done
log "Config generated"

# ── 2. Start Tailscale ───────────────────────────────────────────────────
log "[2/7] Starting Tailscale..."
mkdir -p /var/run/tailscale
tailscaled --tun=userspace-networking \
    --sockets=/var/run/tailscale/tailscaled.sock \
    --state=/hermes-data/tailscale.state &
TAILSCALED_PID=$!

for i in $(seq 1 20); do
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 1
done
if [ ! -S /var/run/tailscale/tailscaled.sock ]; then
    log "FATAL: tailscaled did not start"; exit 1
fi

HOSTNAME="${TS_HOSTNAME:-hermes-$(openssl rand -hex 4)}"
tailscale up --authkey="$TS_AUTHKEY" --hostname="$HOSTNAME" --accept-routes 2>&1 | tail -3 | while read l; do log "  $l"; done
sleep 3

# ── 3. Enable Tailnet SSH ────────────────────────────────────────────────
log "[3/7] Enabling Tailnet SSH..."
tailscale set --ssh 2>&1 | tail -3 | while read l; do log "  $l"; done
sleep 2

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
log "Tailscale ready (ip=$TAILSCALE_IP)"

# ── 4. Start SSHD (traditional SSH) ─────────────────────────────────────
log "[4/7] Starting SSHD..."
mkdir -p /root/.ssh && chmod 700 /root/.ssh

if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
    printf '%s\n' "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    log "SSH key authorized"
fi

/usr/sbin/sshd &
SSHD_PID=$!
log "SSHD running (port 22)"

# ── 5. Hermes Gateway ────────────────────────────────────────────────────
log "[5/7] Starting Hermes Gateway..."
export PATH="/hermes-venv/bin:$PATH"

if ! command -v hermes &>/dev/null; then
    log "FATAL: hermes command not found"; exit 1
fi

hermes gateway run > "$LOG_DIR/gateway.log" 2>&1 &
GATEWAY_PID=$!

log "Waiting for gateway..."
for i in $(seq 1 30); do
    sleep 2
    if ! kill -0 $GATEWAY_PID 2>/dev/null; then
        log "Gateway died — check $LOG_DIR/gateway.log"; exit 1
    fi
    [ "$i" -eq 30 ] && log "Gateway starting (continuing)"
done
log "Gateway running"

# ── 6. Hermes Dashboard ─────────────────────────────────────────────────
log "[6/7] Starting Hermes Dashboard..."
cd /hermes-data
hermes-web-ui start --port 8648 > "$LOG_DIR/dashboard.log" 2>&1 &
DASHBOARD_PID=$!

sleep 3
if kill -0 $DASHBOARD_PID 2>/dev/null; then
    log "Dashboard running (port 8648)"
else
    log "Dashboard may have failed — check logs/dashboard.log"
fi

# ── 7. Health check server ───────────────────────────────────────────────
log "[7/7] Health check endpoint..."
python3 -c "
import http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain')
        self.end_headers()
        self.wfile.write(b'ok')
    def log_message(self, *a): pass
with socketserver.TCPServer(('0.0.0.0', 8080), H) as h:
    h.serve_forever()
" > "$LOG_DIR/health.log" 2>&1 &
log "Health check on port 8080"

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  Hermes Agent is LIVE"
echo ""
echo "  Gateway:   PID $GATEWAY_PID"
echo "  Dashboard: http://0.0.0.0:8648"
echo "  API:       http://0.0.0.0:8642"
echo "  Tailscale: $TAILSCALE_IP"
echo "  Tailnet SSH: enabled"
echo "  SSHD:      port 22"
echo "  Health:    http://0.0.0.0:8080/"
echo "  Logs:      $LOG_DIR/"
echo "═══════════════════════════════════════════════════════"

wait $GATEWAY_PID $DASHBOARD_PID $TAILSCALED_PID $SSHD_PID
