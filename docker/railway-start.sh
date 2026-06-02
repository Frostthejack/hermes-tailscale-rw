#!/usr/bin/env bash
# railway-start.sh — Full startup: volume symlinks, health, config, Tailscale Phase 2, gateway, dashboard.
LOG="/hermes-data/logs"
mkdir -p "$LOG"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG/startup.log"; }

log "=== STARTUP BEGIN ==="
log "PID: $$ HOSTNAME: $(hostname) USER: $(whoami) PWD: $(pwd)"
log "PATH: $PATH"

# ── Step 0: Ensure hermes commands are accessible from any shell ──
log "--- Step 0: PATH setup ---"
# Add to shell RC files so SSH/Tailscale SSH sessions have PATH
grep -q '/hermes-venv/bin' /root/.bashrc 2>/dev/null || echo 'export PATH="/hermes-venv/bin:$PATH"' >> /root/.bashrc
grep -q '/hermes-venv/bin' /root/.profile 2>/dev/null || echo 'export PATH="/hermes-venv/bin:$PATH"' >> /root/.profile
# Symlink hermes binary to system PATH
ln -sf /hermes-venv/bin/hermes /usr/local/bin/hermes 2>/dev/null || true
# Also symlink hindsight if available
ln -sf /hermes-venv/bin/hindsight /usr/local/bin/hindsight 2>/dev/null || true
export PATH="/hermes-venv/bin:${PATH:-}"
log "PATH now includes /hermes-venv/bin"
log "Step 0 done"

# ── Step 1: Symlink persistent data ──────────────────────────
log "--- Step 1: Symlinking ---"
for f in state.db response_store.db; do
    src="/hermes-data/$f" dst="/root/.hermes/$f"
    if [ -e "$src" ] && [ ! -L "$dst" ] && [ ! -d "$dst" ]; then
        [ -e "$dst" ] && mv "$dst" "$dst.bak" 2>/dev/null || true
        ln -sf "$src" "$dst" && log "Symlinked $dst -> $src"
    elif [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
        ln -sf "$src" "$dst" && log "Symlinked $dst -> $src (new)"
    else
        log "Skip symlink $dst (already exists or is symlink)"
    fi
done

# Persist memory files on volume
for f in MEMORY.md USER.md HERMES.md AGENTS.md; do
    src="/hermes-data/$f" dst="/root/.hermes/$f"
    if [ -e "$src" ] && [ ! -L "$dst" ]; then
        [ -e "$dst" ] && cp "$dst" "$src" 2>/dev/null
        rm -f "$dst" 2>/dev/null
        ln -sf "$src" "$dst"
        log "Memory symlinked $dst -> $src (volume had file)"
    elif [ ! -e "$dst" ] && [ ! -e "$src" ]; then
        touch "$src"
        ln -sf "$src" "$dst"
        log "Memory created $src and symlinked $dst"
    elif [ -e "$dst" ] && [ ! -L "$dst" ] && [ ! -e "$src" ]; then
        cp "$dst" "$src"
        rm -f "$dst"
        ln -sf "$src" "$dst"
        log "Memory copied $dst to volume and symlinked"
    else
        log "Memory $f: already OK (symlink exists)"
    fi
done
log "Step 1 done"

# ── Step 2: Health check (must pass for Railway) ────────────
log "--- Step 2: Health check ---"
python3 /app/health.py > "$LOG/health.log" 2>&1 &
HEALTH_PID=$!
log "Health PID: $HEALTH_PID"
sleep 3
if kill -0 $HEALTH_PID 2>/dev/null; then log "Health: ALIVE"; else log "Health: DEAD"; fi
log "Step 2 done"

# ── Step 3: Config generation ────────────────────────────────
log "--- Step 3: Config generation ---"
if python3 /app/generate_config.py 2>&1 | tee -a "$LOG/startup.log"; then
    log "Config: OK"
else
    log "Config generation FAILED (non-zero exit)"
fi
log "Step 3 done"

# ── Step 3b: Initialize Hindsight with PostgreSQL ────────────
log "--- Step 3b: Hindsight init ---"
if [ -n "$DATABASE_URL" ]; then
    log "Initializing Hindsight database..."
    # Create pgvector extension if not exists
    psql "$DATABASE_URL" -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>&1 | tail -2
    log "pgvector extension: done"
    # Initialize the Hindsight bank
    if /hermes-venv/bin/hindsight init --bank hermes-railway 2>&1 | tail -3; then
        log "Hindsight: initialized"
    else
        log "Hindsight init failed (may already exist)"
    fi
else
    log "No DATABASE_URL — Hindsight using SQLite fallback"
fi
log "Step 3b done"

# ── Step 4: Verify hermes binary ────────────────────────────
log "--- Step 4: Check hermes ---"
which hermes 2>/dev/null && log "hermes in PATH" || log "hermes NOT IN PATH"
ls -la /hermes-venv/bin/hermes 2>/dev/null && log "hermes binary found" || log "hermes binary NOT FOUND"
/hermes-venv/bin/hermes --version 2>&1 | head -3 && log "hermes version OK" || log "hermes --version FAILED"
# Check hindsight
which hindsight 2>/dev/null && log "hindsight in PATH" || log "hindsight NOT IN PATH"
ls -la /hermes-venv/bin/hindsight 2>/dev/null && log "hindsight binary found" || log "hindsight binary NOT FOUND"
log "Step 4 done"

# ── Step 5: Tailscale Phase 2 (authkey + --reset) ───────────
log "--- Step 5: Tailscale Phase 2 ---"
if [ -z "${TS_AUTHKEY:-}" ]; then
    log "TS_AUTHKEY not set — skipping Tailscale"
elif ! command -v tailscaled &>/dev/null; then
    log "tailscaled not found — skipping Tailscale"
else
    TS_HOST="${TS_HOSTNAME:-hermes-agent}"

    # Kill any stale tailscaled process and clean up socket
    pkill -f tailscaled 2>/dev/null || true
    sleep 1
    rm -f /var/run/tailscale/tailscaled.sock 2>/dev/null || true
    rm -f /hermes-data/tailscale.state 2>/dev/null || true

    log "Starting tailscaled (userspace-networking)..."
    tailscaled --tun=userspace-networking --state=/hermes-data/tailscale.state &
    TAILSCALE_PID=$!

    # Wait for tailscaled socket
    TAILSCALE_READY=false
    for i in $(seq 1 30); do
        if [ -S /var/run/tailscale/tailscaled.sock ]; then
            TAILSCALE_READY=true
            log "tailscaled socket ready (attempt $i)"
            break
        fi
        sleep 1
    done

    if $TAILSCALE_READY; then
        log "Bringing up Tailscale with auth key + --reset..."
        if tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOST" --accept-routes --reset 2>&1 | tee -a "$LOG/startup.log"; then
            sleep 3
            TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
            log "Tailscale UP: $TS_IP"
        else
            log "Tailscale up FAILED"
        fi

        # Enable SSH over Tailscale
        tailscale set --ssh 2>&1 | tail -1 || true

        # Start SSHD on port 2222 (Railway may block port 22; Tailscale SSH on 22 still works via tailscaled)
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        [ -n "${SSH_PUBLIC_KEY:-}" ] && echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
        /usr/sbin/sshd -p 2222 &
        log "SSHD started on port 2222 (PID: $!)"
    else
        log "tailscaled not ready in 30s — skipping Tailscale"
    fi
fi
log "Step 5 done"

# ── Step 6: Hermes Gateway ──────────────────────────────────
log "--- Step 6: Gateway ---"
log "Launching hermes gateway run..."
hermes gateway run > "$LOG/gateway.log" 2>&1 &
GW_PID=$!
log "Gateway PID: $GW_PID"
for i in $(seq 1 20); do
    sleep 3
    if ! kill -0 $GW_PID 2>/dev/null; then
        log "GATEWAY DIED at check $i"
        if [ -f "$LOG/gateway.log" ]; then
            while IFS= read -r line; do log "GW: $line"; done < "$LOG/gateway.log"
        else
            log "No gateway.log found"
        fi
        GW_PID=""
        break
    fi
    log "Gateway alive at check $i"
done
if [ -n "$GW_PID" ]; then log "Gateway still running after 60s — GOOD"; fi
log "Step 6 done"

# ── Step 7: Dashboard ───────────────────────────────────────
log "--- Step 7: Dashboard ---"
hermes-web-ui start --port 8648 > "$LOG/dashboard.log" 2>&1 &
log "Dashboard PID: $!"
log "Step 7 done"

log "=== STARTUP COMPLETE ==="
wait ${GW_PID:-$HEALTH_PID}
log "=== EXIT (wait returned) ==="
