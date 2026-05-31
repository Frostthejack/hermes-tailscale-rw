# Kanban Worker Concurrency Limits

## How to Limit Active Workers

The kanban dispatcher spawns workers on each tick. Two parameters control concurrency:

### `max_spawn` (config.yaml key — persistent)

- **Where**: `~/.hermes/config.yaml` → `kanban.max_spawn`
- **Default**: None (unlimited — dispatcher default is 8 per tick)
- **Effect**: Live concurrency cap — counts tasks already in `status='running'` plus this tick's spawns. `max_spawn=1` means at most 1 worker running at any time across the whole board.
- **Gateway support**: The gateway-embedded dispatcher reads this key at startup (see `gateway/run.py` ~line 5015). No patching required.
- **Usage**:
  ```yaml
  kanban:
    max_spawn: 1
  ```
  Then restart the gateway: `hermes gateway restart`

### `max_in_progress` (config.yaml key — persistent)

- **Where**: `~/.hermes/config.yaml` → `kanban.max_in_progress`
- **Default**: None (unlimited)
- **Effect**: If set, dispatcher skips spawning entirely when running tasks ≥ this value. More aggressive than `max_spawn`.
- **Gateway support**: Also read from config at startup (see `gateway/run.py` ~line 5023).

### Per-dispatch override (API)

You can also pass `max_n` to the dispatch endpoint:
```
curl -s http://127.0.0.1:9119/api/dispatch?max=1
```
This only affects that single tick — use `config.yaml` for persistent limits.

### When to Limit

- **Rate-limited providers** (OpenRouter free tier): limit to 1-2 workers to avoid 429 cascades
- **Resource-constrained hosts** (single GPU, limited RAM): limit to 1 worker
- **Debugging**: limit to 1 worker to isolate issues

### Verification

After restarting the gateway, verify the limit is active:
```bash
# Check gateway logs for the max_spawn line
journalctl --user -u hermes-gateway --no-pager -n 20 | grep -i "max_spawn\|kanban"
# Or check the gateway log file
tail -30 ~/.hermes/logs/gateway.log | grep -i "max_spawn\|kanban"
```

Expected output:
```
kanban dispatcher: max_spawn=1
```

### Session History

- **2026-05-21**: Added `max_spawn: 1` to `~/.hermes/config.yaml`. Gateway picked it up on restart — confirmed via `gateway.log` showing `kanban dispatcher: max_spawn=1`. The gateway already reads this key natively (no patching needed).
