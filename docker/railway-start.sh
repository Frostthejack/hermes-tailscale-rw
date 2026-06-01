#!/usr/bin/env bash
# Minimal debug startup — maximum logging, never crash
LOG="/hermes-data/logs"
mkdir -p "$LOG"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG/startup.log"; }

log "=== STARTUP ==="
log "PID: $$ HOSTNAME: $(hostname) USER: $(whoami)"

log "PATH: $PATH"
log "PYTHON: $(python3 --version 2>&1)"

log "Checking hermes..."
which hermes 2>/dev/null || log "hermes NOT IN PATH"
/hermes-venv/bin/hermes --version 2>&1 || log "hermes version FAILED"

log "Starting health check..."
python3 /app/health.py > "$LOG/health.log" 2>&1 &
HEALTH_PID=$!
log "Health PID: $HEALTH_PID"
sleep 3
kill -0 $HEALTH_PID 2>/dev/null && log "Health: alive" || log "Health: DEAD"

log "Generating config..."
python3 /app/generate_config.py 2>&1 || log "Config generation FAILED"

log "Starting gateway..."
export PATH="/hermes-venv/bin:${PATH:-}"
hermes gateway run > "$LOG/gateway.log" 2>&1 &
GW_PID=$!
log "Gateway PID: $GW_PID"

for i in $(seq 1 20); do
    sleep 3
    if ! kill -0 $GW_PID 2>/dev/null; then
        log "Gateway died at check $i"
        cat "$LOG/gateway.log" 2>/dev/null | while read line; do log "GW: $line"; done
        GW_PID=""
        break
    fi
    log "Gateway alive at check $i"
done

[ -z "$GW_PID" ] || log "Gateway still running after 60s"

log "Starting dashboard..."
hermes-web-ui start --port 8648 > "$LOG/dashboard.log" 2>&1 &
DASH_PID=$!
log "Dashboard PID: $DASH_PID"

log "=== LIVE ==="
wait ${GW_PID:-$HEALTH_PID}
log "=== EXIT ==="
