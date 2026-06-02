#!/usr/bin/env bash
# railway-start.sh — Full startup: volume symlinks, health, config, Tailscale, Hindsight init, gateway, dashboard.

LOG="/hermes-data/logs"
mkdir -p "$LOG"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG/startup.log"; }

log "=== STARTUP BEGIN ==="
log "PID: $$ HOSTNAME: $(hostname) USER: $(whoami) PWD: $(pwd)"
log "PATH: $PATH"

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

# Persist memory/personality files on volume so they survive redeployments
for f in MEMORY.md USER.md HERMES.md AGENTS.md; do
    src="/hermes-data/$f" dst="/root/.hermes/$f"
    if [ -e "$src" ] && [ ! -L "$dst" ]; then
        # Volume has the file, local doesn't — symlink it
        [ -e "$dst" ] && cp "$dst" "$src" 2>/dev/null
        rm -f "$dst" 2>/dev/null
        ln -sf "$src" "$dst" && log "Symlinked $dst -> $src (persisted)"
    elif [ ! -e "$dst" ] && [ ! -e "$src" ]; then
        # Neither exists — create empty on volume and symlink
        touch "$src"
        ln -sf "$src" "$dst" && log "Symlinked $dst -> $src (new)"
    elif [ -e "$dst" ] && [ ! -L "$dst" ] && [ ! -e "$src" ]; then
        # Local exists but not on volume — copy to volume, then symlink
        cp "$dst" "$src"
        rm -f "$dst"
        ln -sf "$src" "$dst" && log "Symlinked $dst -> $src (migrated)"
    fi
done

log "Step 1 done"

# ── Step 1b: Ensure hermes is in PATH for all shells ─────────
log "--- Step 1b: PATH setup ---"
# Add to system PATH
ln -sf /hermes-venv/bin/hermes /usr/local/bin/hermes 2>/dev/null || true
# Ensure login shells also get the venv
grep -q '/hermes-venv/bin' /root/.bashrc 2>/dev/null || echo 'export PATH="/hermes-venv/bin:$PATH"' >> /root/.bashrc
grep -q '/hermes-venv/bin' /root/.profile 2>/dev/null || echo 'export PATH="/hermes-venv/bin:$PATH"' >> /root/.profile
# Source it for this script too
export PATH="/hermes-venv/bin:${PATH:-}"
log "PATH setup done (hermes -> /usr/local/bin/hermes)"

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

# ── Step 3b: Hindsight initialization ───────────────────────
log "--- Step 3b: Hindsight init ---"
if [ -n "${DATABASE_URL:-}" ]; then
    log "DATABASE_URL found — initializing Hindsight with PostgreSQL"

    # Ensure pgvector extension exists
    psql "$DATABASE_URL" -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>&1 | tail -3 && log "pgvector extension: OK" || log "pgvector CREATE failed (may already exist or not supported)"

    # Check if hindsight-client is installed
    if /hermes-venv/bin/pip show hindsight-client &>/dev/null; then
        log "hindsight-client: installed ($(/hermes-venv/bin/pip show hindsight-client 2>/dev/null | grep Version))"
        # The Hindsight bank is auto-initialized when the gateway starts with the
        # hindsight plugin enabled. No CLI init needed — just verify the config.
        if [ -f /root/.hermes/hindsight/config.json ]; then
            log "Hindsight config.json present — bank will init on first gateway use"
        else
            log "WARNING: No hindsight config.json found"
        fi
    else
        log "hindsight-client NOT installed — installing..."
        /hermes-venv/bin/pip install --no-cache-dir "hindsight-client>=0.4.22" 2>&1 | tail -5 && log "hindsight-client installed" || log "hindsight-client install FAILED"
    fi
else
    log "No DATABASE_URL — Hindsight will use SQLite fallback"
fi
log "Step 3b done"

# ── Step 4: Verify hermes binary ────────────────────────────
log "--- Step 4: Check hermes ---"
which hermes 2>/dev/null && log "hermes in PATH" || log "hermes NOT IN PATH"
ls -la /hermes-venv/bin/hermes 2>/dev/null && log "hermes binary found" || log "hermes binary NOT FOUND"
hermes --version 2>&1 | head -3 && log "hermes version OK" || log "hermes --version FAILED"
log "Step 4 done"

# ── Step 5: Tailscale (preserve state, fallback to --reset) ───
log "--- Step 5: Tailscale ---"
if [ -z "${TS_AUTHKEY:-}" ]; then
    log "TS_AUTHKEY not set — skipping Tailscale"
elif ! command -v tailscaled &>/dev/null; then
    log "tailscaled not found — skipping Tailscale"
else
    TS_HOST="${TS_HOSTNAME:-hermes-agent}"

    # Kill any stale tailscaled process and clean up socket (but NOT state file)
    pkill -f tailscaled 2>/dev/null || true
    sleep 1
    rm -f /var/run/tailscale/tailscaled.sock 2>/dev/null || true

    log "Starting tailscaled (userspace-networking)..."
    tailscaled --tun=userspace-networking --state=/hermes-data/tailscale.state &

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
        # Phase 1: Try to bring up with existing state (preserves node identity)
        TS_IP=""
        log "Phase 1: Trying tailscale up with existing state..."
        if tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOST" --accept-routes 2>&1 | tee -a "$LOG/startup.log"; then
            sleep 3
            TS_IP=$(tailscale ip -4 2>/dev/null || echo "")
        fi

        # Phase 2: If Phase 1 failed, clean state and retry with --reset
        if [ -z "$TS_IP" ]; then
            log "Phase 1 failed — Phase 2: removing stale state and retrying with --reset..."
            tailscale down 2>/dev/null || true
            # Stop tailscaled, remove state, restart
            pkill -f tailscaled 2>/dev/null || true
            sleep 2
            rm -f /hermes-data/tailscale.state /var/run/tailscale/tailscaled.sock 2>/dev/null || true
            tailscaled --tun=userspace-networking --state=/hermes-data/tailscale.state &
            sleep 3
            if tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOST" --accept-routes --reset 2>&1 | tee -a "$LOG/startup.log"; then
                sleep 5
                TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
            else
                TS_IP="FAILED"
            fi
        fi

        log "Tailscale IP: $TS_IP"

        # Enable Tailscale SSH (allows `ssh root@hermes-agent` from tailnet)
        tailscale set --ssh 2>&1 | tail -1 || true

        # Also start SSHD on port 2222 for direct SSH
        mkdir -p /root/.ssh && chmod 700 /root/.ssh
        [ -n "${SSH_PUBLIC_KEY:-}" ] && echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
        /usr/sbin/sshd -D -p 2222 &
        log "SSHD started on port 2222 (PID: $!)"
    else
        log "tailscaled not ready in 30s — skipping Tailscale"
    fi
fi
log "Step 5 done"

# ── Step 6: Hermes Gateway ──────────────────────────────────
log "--- Step 6: Gateway ---"
log "Launching hermes gateway run..."
hermes gateway run 2>&1 | tee "$LOG/gateway.log" &
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
log "Tailscale IP: $(tailscale ip -4 2>/dev/null || echo N/A)"
log "hermes CLI: $(which hermes 2>/dev/null || echo 'not found')"
log "Hindsight: config at /root/.hermes/hindsight/config.json $([ -f /root/.hermes/hindsight/config.json ] && echo '(present)' || echo '(missing)')"

wait ${GW_PID:-$HEALTH_PID}
log "=== EXIT (wait returned) ==="
