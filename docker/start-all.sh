#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# start-all.sh — Master startup for Hermes Agent on Railway
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

LOG_DIR="/hermes-data/logs"
mkdir -p "$LOG_DIR"

log() { echo "[$(date -u +%H:%M:%S)] $*"; }

echo "═══════════════════════════════════════════════════════"
log "Hermes Agent — Railway All-in-One"
echo "═══════════════════════════════════════════════════════"

# ── 0. Validate ──────────────────────────────────────────────────────────
log "[0/6] Validating environment..."
if [ -z "${OPENROUTER_API_KEY:-}" ]; then log "FATAL: OPENROUTER_API_KEY not set"; exit 1; fi
if [ -z "${TS_AUTHKEY:-}" ];      then log "FATAL: TS_AUTHKEY not set"; exit 1; fi
log "Env vars OK"

# ── 1. Start PostgreSQL ──────────────────────────────────────────────────
log "[1/6] Starting PostgreSQL..."
PGDATA=/var/lib/postgresql/data
mkdir -p "$PGDATA"

if [ ! -f "$PGDATA/PG_VERSION" ]; then
    chown -R postgres:postgres "$PGDATA" /var/run/postgresql 2>/dev/null || true
    su - postgres -c "initdb -D $PGDATA --auth=trust --no-locale" 2>&1 | tail -3 | while read l; do log "  $l"; done
fi

su - postgres -c "pg_ctl -D $PGDATA -l $LOG_DIR/postgres.log start" 2>&1
sleep 2

su - postgres -c "psql -tc \"SELECT 1 FROM pg_database WHERE datname='hindsight'\"" 2>/dev/null | grep -q 1 || \
    su - postgres -c "createdb hindsight" 2>/dev/null || true

log "PostgreSQL running (port 5432)"

# ── 2. Generate config ───────────────────────────────────────────────────
log "[2/6] Generating configuration..."

export PGHOST="${PGHOST:-127.0.0.1}"
export PGPORT="${PGPORT:-5432}"
export PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPORT:-}"          # suppress unused; real PG conn uses peer auth locally
export PGDATABASE="${PGDATABASE:-hindsight}"

python3 /docker/generate_config.py 2>&1 | while read l; do log "  $l"; done
log "Config generated"

# ── 3. Tailscale ─────────────────────────────────────────────────────────
log "[3/6] Starting Tailscale..."
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
sleep 5

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
log "Tailscale connected (hostname=$HOSTNAME ip=$TAILSCALE_IP)"

# ── 4. SSHD ──────────────────────────────────────────────────────────────
log "[4/6] Starting SSH daemon..."
mkdir -p /root/.ssh && chmod 700 /root/.ssh

if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
    printf '%s\n' "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    log "SSH key authorized"
fi

/usr/sbin/sshd &
SSHD_PID=$!
log "SSHD running (port 22)"

# ── 5. Hermes Gateway (with embedded Hindsight) ─────────────────────────
log "[5/6] Starting Hermes Gateway..."
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
    if curl -sf http://127.0.0.1:8642/health >/dev/null 2>&1; then
        log "Gateway & API server ready"; break
    fi
    [ "$i" -eq 30 ] && log "Gateway running (API not yet responding)"
done

# ── 6. Hermes Dashboard ─────────────────────────────────────────────────
log "[6/6] Starting Hermes Dashboard..."
cd /hermes-data
hermes-web-ui start --port 8648 > "$LOG_DIR/dashboard.log" 2>&1 &
DASHBOARD_PID=$!

sleep 3
if kill -0 $DASHBOARD_PID 2>/dev/null; then
    log "Dashboard running (port 8648)"
else
    log "Dashboard may have failed — check $LOG_DIR/dashboard.log"
fi

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
log "Hermes Agent is LIVE"
echo ""
echo "  Gateway:   PID $GATEWAY_PID"
echo "  Dashboard: http://0.0.0.0:8648"
echo "  API:       http://0.0.0.0:8642"
echo "  Hindsight: http://127.0.0.1:8888 (embedded)"
echo "  Postgres:  127.0.0.1:5432"
echo "  Tailscale: $TAILSCALE_IP"
echo "  SSH:       ssh root@$TAILSCALE_IP"
wait $GATEWAY_PID $DASHBOARD_PID $TAILSCALED_PID $SSHD_PID
