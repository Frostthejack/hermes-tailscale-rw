#!/usr/bin/env bash
# DEBUG startup — maximum logging, never crash
LOG="/hermes-data/logs"
mkdir -p "$LOG"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG/startup.log"; }

log "=== STARTUP BEGIN ==="
log "PID: $$ HOSTNAME: $(hostname) USER: $(whoami) PWD: $(pwd)"
log "PATH: $PATH"

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
log "Step 1 done"

log "--- Step 2: Health check ---"
export PATH="/hermes-venv/bin:${PATH:-}"
python3 /app/health.py > "$LOG/health.log" 2>&1 &
HEALTH_PID=$!
log "Health PID: $HEALTH_PID"
sleep 3
if kill -0 $HEALTH_PID 2>/dev/null; then log "Health: ALIVE"; else log "Health: DEAD"; fi
log "Step 2 done"

log "--- Step 3: Config generation ---"
if python3 /app/generate_config.py 2>&1 | tee -a "$LOG/startup.log"; then
    log "Config: OK"
else
    log "Config generation FAILED (non-zero exit)"
fi
log "Step 3 done"

log "--- Step 4: Check hermes ---"
which hermes 2>/dev/null && log "hermes in PATH" || log "hermes NOT IN PATH"
ls -la /hermes-venv/bin/hermes 2>/dev/null && log "hermes binary found" || log "hermes binary NOT FOUND"
/hermes-venv/bin/hermes --version 2>&1 | head -3 && log "hermes version OK" || log "hermes --version FAILED"
log "Step 4 done"

log "--- Step 5: Tailscale SKIPPED ---"

log "--- Step 6: Gateway ---"
export PATH="/hermes-venv/bin:${PATH:-}"
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

log "--- Step 7: Dashboard ---"
hermes-web-ui start --port 8648 > "$LOG/dashboard.log" 2>&1 &
log "Dashboard PID: $!"
log "Step 7 done"

log "=== STARTUP COMPLETE ==="
wait ${GW_PID:-$HEALTH_PID}
log "=== EXIT (wait returned) ==="
