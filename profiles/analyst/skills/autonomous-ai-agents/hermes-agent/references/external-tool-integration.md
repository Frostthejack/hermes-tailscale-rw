# External Tool Integration Patterns

How to build tools and apps that communicate with Hermes Agent from the outside.

## Architecture Overview

```
External Tool ←──→ Hermes Gateway ←──→ Agent Loop
   (your app)       (port 8642)          (LLM + tools)
                      │
                      ├── API Server (port 62936) ← HTTP/REST
                      ├── Webhook Server (port 8644) ← Inbound POSTs
                      ├── Session Files (*.jsonl) ← File-based
                      ├── Kanban DB (kanban.db) ← SQLite
                      └── Shell Hooks ← Pre/post exec hooks
```

## Pattern 1: Inbound Webhooks (External → Hermes)

**Use when:** You want Hermes to react to events from GitHub, CI/CD, monitoring, IoT, etc.

**Setup:** `hermes webhook subscribe <name> --prompt "..." --events "..." --deliver telegram`

**Docs:** See the `webhook-subscriptions` skill for full details.

**Key point:** This is a pull model from Hermes' perspective — the external service pushes events in.

## Pattern 2: Outbound Status Push (Hermes → External Tool)

**Use when:** You want an external app to know what Hermes agents are doing (e.g., screen pet, dashboard, notification system).

### Option A: Agent Reports Self via Webhook (Recommended)

Create a local HTTP server in your external tool, then have Hermes agents POST to it:

```bash
# In your external tool: start a local server on port 9191
# In Hermes: agent sends status via curl

curl -s -X POST http://127.0.0.1:9191/webhooks/status \
  -H "Content-Type: application/json" \
  -d '{
    "agent": "hermes",
    "profile": "default",
    "status": "busy",
    "task": "Building auth service",
    "timestamp": 1715632000
  }'
```

**Event types to report:**
- `busy` — agent started processing a task
- `idle` — agent finished, back to idle
- `waiting` — agent waiting for tool response
- `approval_needed` — agent requests user approval
- `error` — agent encountered an error
- `complete` — task completed successfully

**How to trigger these from Hermes:**
- Shell hooks (`~/.hermes/shell-hooks-allowlist.json`) — fire a script before/after tool execution
- Custom Hermes plugin — Python hook in `~/.hermes/plugins/`
- Cron job — periodic status report from a no-agent cron

### Option B: External Tool Polls Hermes

Your external tool periodically queries Hermes session status:

```bash
# List recent sessions
hermes sessions list

# List sessions in JSON (for parsing)
hermes sessions export /tmp/sessions.jsonl

# Query kanban for multi-agent status
# Read ~/.hermes/kanban.db directly (SQLite)
sqlite3 ~/.hermes/kanban.db "SELECT * FROM tasks WHERE status='in_progress';"
```

**Polling interval:** 30s is reasonable. Use a cron job:
```bash
hermes cron add "every 30s" "echo $(hermes sessions list --json) > ~/.hermes/screen-pet-status.json" --no-agent
```

### Option C: Tail Session Files (Lowest Latency)

Hermes writes session transcripts to `~/.hermes/sessions/*.jsonl` in real time. Your external tool can tail the most recent file:

```bash
# Find the most recent session file
ls -t ~/.hermes/sessions/*.jsonl | head -1

# Tail it for new events
tail -f ~/.hermes/sessions/latest.jsonl | jq 'select(.role=="assistant")'
```

**Note:** This gives you the raw conversation stream, not structured status events. You'll need to parse tool calls and responses to determine what the agent is doing.

### Option D: Custom Hermes Plugin (Most Integrated)

Create a Python plugin that hooks into Hermes' internal events:

```python
# ~/.hermes/plugins/screen_pet/hook.py
import requests
import json
import time

SCREEN_PET_URL = "http://127.0.0.1:9191/webhooks/status"

def notify_status(agent, status, task=""):
    try:
        requests.post(SCREEN_PET_URL, json={
            "agent": agent,
            "status": status,
            "task": task[:100],
            "timestamp": time.time()
        }, timeout=2)
    except:
        pass  # Don't let notification failures break the agent
```

**Plugin location:** `~/.hermes/plugins/<name>/` with a `plugin.json` manifest.

## Pattern 3: Hermes API Server (OpenAI-Compatible)

**Endpoint:** `http://127.0.0.1:62936/v1/` (configurable via `API_SERVER_PORT`)

**Enable in `~/.hermes/.env`:**
```bash
API_SERVER_ENABLED=true
API_SERVER_PORT=62936
# API_SERVER_KEY=optional  # omit for local dev (no auth)
```

**Endpoints:**
- `GET /v1/models` — list available models
- `POST /v1/chat/completions` — send messages, get completions (streaming supported)

**Use for:** External programs that want to send prompts to Hermes and get responses.

**Example:**
```bash
curl http://127.0.0.1:62936/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "hermes-agent",
    "messages": [{"role": "user", "content": "What is the status?"}],
    "stream": true
  }'
```

**Limitation:** Request-response only. No native push notifications.

## Pattern 4: Approval Flow (Bidirectional)

**Use when:** An external tool needs to approve/deny something an agent wants to do.

### Outgoing (Agent needs approval):

1. Agent sends approval request to external tool via webhook:
```json
{
  "agent": "hermes",
  "type": "approval_request",
  "command": "rm -rf /tmp/build-cache",
  "context": "Cleaning up build artifacts",
  "approval_id": "abc-123"
}
```

2. External tool shows popup to user
3. User clicks Approve or Deny
4. External tool sends response back via Hermes API:

```bash
# Option A: POST to Hermes webhook (if configured)
curl -X POST http://127.0.0.1:8644/webhooks/approval-response \
  -d '{"approval_id": "abc-123", "decision": "approve"}'

# Option B: Shell out to CLI
hermes gateway approve abc-123

# Option C: Write to a file that Hermes polls
echo '{"id":"abc-123","decision":"approve"}' > ~/.hermes/approvals.jsonl
```

### Hermes' Built-in Approval System:

- `approvals.mode` in config.yaml: `manual` (default), `smart`, or `off`
- In manual mode, Hermes prompts via Telegram/Discord/Slack before destructive commands
- An external screen pet can intercept these and show a native Windows popup instead

## Pattern 5: Kanban DB (Multi-Agent Status)

**Location:** `~/.hermes/kanban.db` (SQLite)

**Schema (key tables):**
```sql
-- Tasks
SELECT id, title, status, assigned_to, created_at, updated_at
FROM tasks
WHERE status IN ('todo', 'in_progress', 'review', 'done', 'blocked');

-- Agent heartbeats (last activity)
SELECT agent_name, last_heartbeat FROM agents;
```

**Use for:** Building dashboards that show all active agents and their current tasks.

**Read access:** The DB is a regular SQLite file — any language can read it.
**Write access:** Use Hermes CLI tools (`hermes kanban`) or the kanban toolset to update tasks.

## Networking: WSL2 ↔ Windows

| Direction | Use Address | Notes |
|-----------|-------------|-------|
| WSL → Windows service | `127.0.0.1` | Auto-forwarded in WSL2 |
| Windows → WSL service | `127.0.0.1` | Auto-forwarded in WSL2 |
| Windows → WSL (fallback) | `localhost` | Sometimes fails; prefer `127.0.0.1` |
| External device → WSL | Windows host IP | Requires portproxy + firewall rule |

**For the screen pet:** Since Hermes runs in WSL and the pet runs on Windows:
- Pet's webhook server listens on `0.0.0.0:9191` (Windows)
- Hermes agents POST to `http://127.0.0.1:9191` (WSL sees this as Windows host)
- No portproxy needed — WSL2 auto-forwards `127.0.0.1`

## Security Considerations

- **API server:** No auth by default (`API_SERVER_KEY` not set). Only enable on local machine or trusted network.
- **Webhook server:** HMAC-SHA256 signature validation. Always set a secret.
- **Session files:** Contain full conversation history including tool output. Don't expose to untrusted processes.
- **Kanban DB:** Read-only from external tools. Write only through Hermes CLI to avoid corruption.

## Real-World Example: Screen Pet Integration

```python
# screen_pet_server.py — runs on Windows
from flask import Flask, request, jsonify
import json

app = Flask(__name__)
agents = {}

@app.route('/webhooks/status', methods=['POST'])
def on_status():
    data = request.json
    agents[data['agent']] = {
        'status': data['status'],
        'task': data.get('task', ''),
        'timestamp': data.get('timestamp')
    }
    # Update pet window...
    return jsonify({'ok': True})

@app.route('/webhooks/approval', methods=['POST'])
def on_approval():
    data = request.json
    # Show popup, wait for user response...
    return jsonify({'ok': True, 'approval_id': data['approval_id']})

@app.route('/api/agents', methods=['GET'])
def list_agents():
    return jsonify(agents)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9191)
```

```bash
# In Hermes (WSL) — called by shell hook or plugin
curl -s -X POST http://127.0.0.1:9191/webhooks/status \
  -H "Content-Type: application/json" \
  -d '{"agent":"hermes","status":"busy","task":"Researching screen pets"}'
```
