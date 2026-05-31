#!/usr/bin/env bash
# railway-start.sh — Full Railway startup script with volume symlinks,
# config generation, Tailscale, SSHD, Hermes Gateway, Dashboard, Health.
#
# This script handles FIRST RUN (migrate data to volume) and every
# subsequent restart (symlink volume back into ephemeral filesystem).
#
# It NEVER modifies the Docker image layers — only /hermes-data/ (volume).

set -euo pipefail
LOG="/hermes-data/logs"
mkdir -p "$LOG"
log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# ── 1. Symlink persistent data ──────────────────────────────
symlink_persist() {
    local src="/hermes-data/$1" dst="/root/.hermes/$1"
    if [ -e "$src" ] && [ ! -L "$dst" ]; then
        [ -e "$dst" ] && cp -a "$dst" "$src" 2>/dev/null && rm -rf "$dst"
        ln -sf "$src" "$dst"
        log "Symlinked $dst → $src"
    elif [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
        ln -sf "$src" "$dst"
        log "Symlinked $dst → $src (new)"
    fi
}

symlink_persist "state.db"
symlink_persist "response_store.db"

# Trading DB
if [ -f "/hermes-data/trading.db" ] && [ ! -L "/app/Hermes-Trading/trading.db" ]; then
    [ -f "/app/Hermes-Trading/trading.db" ] && mv /app/Hermes-Trading/trading.db /hermes-data/trading.db
    ln -sf /hermes-data/trading.db /app/Hermes-Trading/trading.db
elif [ ! -L "/app/Hermes-Trading/trading.db" ]; then
    ln -sf /hermes-data/trading.db /app/Hermes-Trading/trading.db
fi

# Profile state.dbs
for prof in /root/.hermes/profiles/*/; do
    pname=$(basename "$prof")
    [ -f "$prof/state.db" ] || continue
    mkdir -p "/hermes-data/profiles/$pname"
    vol="/hermes-data/profiles/$pname/state.db"
    if [ ! -e "$vol" ]; then
        mv "$prof/state.db" "$vol" 2>/dev/null || true
        log "Migrated $pname state.db"
    elif [ ! -L "$prof/state.db" ]; then
        rm -f "$prof/state.db" "$prof/state.db-shm" "$prof/state.db-wal" 2>/dev/null || true
    fi
    ln -sf "$vol" "$prof/state.db"
done

# Wiki state
mkdir -p /hermes-data/wiki-state
ln -sf /hermes-data/wiki-state /root/.hermes/wiki-state 2>/dev/null || true

# Logs
ln -sf /hermes-data/logs /root/.hermes/logs 2>/dev/null || true

# ── 2. Clone/pull wiki vault ────────────────────────────────
if [ ! -d "$WIKI_PATH/.git" ]; then
    log "Cloning wiki vault..."
    git clone "$WIKI_VAULT_REPO" "$WIKI_PATH" 2>&1 | tail -3
    log "Wiki vault: cloned"
else
    log "Pulling wiki vault updates..."
    git -C "$WIKI_PATH" pull --rebase 2>&1 | tail -3 || true
fi

# ── 3. Config generation (Python — safe secret handling) ────
python3 /app/generate_config.py

# ── 4. Tailscale (userspace networking) ─────────────────────
log "Starting Tailscale..."
tailscaled --tun=userspace-networking --state=/hermes-data/tailscale.state &
for i in $(seq 1 20); do
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 1
done
[ -S /var/run/tailscale/tailscaled.sock ] || { log "FATAL: tailscaled failed"; exit 1; }

TS_HOST="${TS_HOSTNAME:-hermes-$(openssl rand -hex 4)}"
tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOST" --accept-routes 2>&1 | tail -3
sleep 3
tailscale set --ssh 2>&1 | tail -3
sleep 2
TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
log "Tailscale: $TS_IP"

# ── 5. SSHD ─────────────────────────────────────────────────
mkdir -p /root/.ssh && chmod 700 /root/.ssh
[ -n "${SSH_PUBLIC_KEY:-}" ] && echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
/usr/sbin/sshd -D &

# ── 6. Hermes Gateway ──────────────────────────────────────
log "Starting Hermes Gateway..."
export PATH="/hermes-venv/bin:$PATH"
hermes gateway run > "$LOG/gateway.log" 2>&1 &
GW_PID=$!
for i in $(seq 1 60); do
    sleep 2
    kill -0 $GW_PID 2>/dev/null || { log "Gateway died early"; cat "$LOG/gateway.log"; exit 1; }
done
log "Gateway: running"

# ── 7. Dashboard + Health ───────────────────────────────────
hermes-web-ui start --port 8648 > "$LOG/dashboard.log" 2>&1 &
sleep 3
python3 /app/health.py > "$LOG/health.log" 2>&1 &

log "LIVE — Tailscale: $TS_IP | Dashboard:8648 | API:8642 | Hindsight:8888"
wait $GW_PID
