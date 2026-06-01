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
if [ -z "${GITHUB_TOKEN:-}" ]; then
    log "WARNING: GITHUB_TOKEN not set — skipping wiki vault clone"
elif [ ! -d "$WIKI_PATH/.git" ]; then
    log "Cloning wiki vault..."
    WIKI_AUTH_URL="https://x-access-token:${GITHUB_TOKEN}@github.com/$(echo "$WIKI_VAULT_REPO" | sed 's|https://github.com/||')"
    if git clone "$WIKI_AUTH_URL" "$WIKI_PATH" 2>&1 | tail -3; then
        log "Wiki vault: cloned"
    else
        log "WARNING: wiki vault clone failed — continuing without it"
    fi
else
    log "Pulling wiki vault updates..."
    git -C "$WIKI_PATH" pull --rebase 2>&1 | tail -3 || true
fi

# ── 3. Health check FIRST (Railway needs this to pass) ──────────
export PATH="/hermes-venv/bin:${PATH:-}"
log "Starting health check on port ${PORT:-8080}..."
python3 /app/health.py > "$LOG/health.log" 2>&1 &
HEALTH_PID=$!
sleep 2
log "Health check started"

# ── 4. Config generation (Python — safe secret handling) ────
python3 /app/generate_config.py

# ── 5. Tailscale (userspace networking, smart state) ──────
log "Starting Tailscaled..."
tailscaled --tun=userspace-networking --state=/hermes-data/tailscale.state &
TAILSCALE_PID=$!
TAILSCALE_READY=false
for i in $(seq 1 30); do
    if [ -S /var/run/tailscale/tailscaled.sock ]; then
        TAILSCALE_READY=true
        break
    fi
    sleep 1
done

if $TAILSCALE_READY; then
    TS_HOST="${TS_HOSTNAME:-hermes-agent}"
    TS_CONNECTED=false

    # Try to bring up Tailscale with existing state
    if tailscale up --accept-routes --hostname="$TS_HOST" 2>&1 | tail -5; then
        sleep 2
        TS_IP=$(tailscale ip -4 2>/dev/null || echo "")
        if [ -n "$TS_IP" ]; then
            TS_CONNECTED=true
            log "Tailscale: $TS_IP (existing state)"
        fi
    fi

    # If existing state didn't work, reset and use auth key
    if ! $TS_CONNECTED; then
        log "Tailscale: existing state failed, resetting with auth key..."
        tailscale down 2>/dev/null || true
        sleep 1
        rm -f /hermes-data/tailscale.state
        tailscaled --tun=userspace-networking --state=/hermes-data/tailscale.state &
        for i in $(seq 1 30); do
            [ -S /var/run/tailscale/tailscaled.sock ] && break
            sleep 1
        done
        if tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOST" --accept-routes 2>&1 | tail -3; then
            sleep 3
            TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
            log "Tailscale: $TS_IP (new auth)"
        else
            log "Tailscale up failed — continuing"
        fi
    fi

    # Enable SSH on Tailscale
    tailscale set --ssh 2>&1 | tail -3 || true

    # SSHD
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    [ -n "${SSH_PUBLIC_KEY:-}" ] && echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
    /usr/sbin/sshd -D &
    log "SSHD started"
else
    log "Tailscale not ready in 30s — continuing without it"
fi

# ── 6. Hermes Gateway (best-effort) ──────────────────────────
log "Starting Hermes Gateway..."
hermes gateway run > "$LOG/gateway.log" 2>&1 &
GW_PID=$!
# Wait up to 2min for gateway (soft timeout)
for i in $(seq 1 60); do
    sleep 2
    if ! kill -0 $GW_PID 2>/dev/null; then
        log "Gateway died early"
        cat "$LOG/gateway.log" || true
        GW_PID=""
        break
    fi
done
if [ -n "$GW_PID" ]; then
    log "Gateway: running (or still starting)"
fi

# ── 7. Dashboard (best-effort) ──────────────────────────────
hermes-web-ui start --port 8648 > "$LOG/dashboard.log" 2>&1 &

log "LIVE — Tailscale: ${TS_IP:-pending} | Dashboard:8648 | API:8642 | Hindsight:8888"
log "Wiki vault: $WIKI_PATH"
wait ${GW_PID:-$HEALTH_PID}
