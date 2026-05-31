# Hindsight Config Mapping — Where Settings Actually Live

## The Two Config Systems

Hermes has **two separate config layers** for memory. Understanding which is which prevents the common failure mode where hindsight appears configured but auto-retain silently does nothing.

### Layer 1: Hermes `config.yaml` — activates the plugin

`~/.hermes/config.yaml` (main) and `~/.hermes/profiles/<name>/config.yaml` (per-profile):

```yaml
memory:
  memory_enabled: true
  provider: hindsight          # ← MUST be "hindsight" (not "" or "honcho")
  auto_retain: true            # ← explicit is safer than relying on defaults
  retain_every_n_turns: 1      # ← 1 = every turn; higher = batch N turns
  auto_recall: true            # ← auto-inject context before each turn
```

**What this does:** Tells Hermes to load the Hindsight memory provider plugin. Without `provider: hindsight`, the plugin is not loaded and no hindsight tools (retain/recall/reflect) are available.

**Common failure:** `provider: ''` (empty string) means "no external memory provider" — the built-in `memory` tool is used instead. No auto-retain happens.

### Layer 2: Hindsight `config.json` — controls the plugin behavior

The Hindsight plugin reads its own config from a **separate JSON file**, not from `config.yaml`:

**Resolution order:**
1. `$HERMES_HOME/hindsight/config.json` — profile-scoped (preferred)
2. `~/.hindsight/config.json` — legacy shared path
3. Environment variables

For profiles, `$HERMES_HOME` = `~/.hermes/profiles/<name>/`, so the profile-scoped path is:
```
~/.hermes/profiles/<name>/hindsight/config.json
```

For the main profile:
```
~/.hermes/hindsight/config.json
```

**Typical content:**
```json
{
  "mode": "local_external",
  "api_url": "http://localhost:8888",
  "apiKey": "",
  "timeout": 120,
  "idle_timeout": 300,
  "bank_id": "hermes",
  "recall_budget": "mid",
  "auto_retain": true,
  "retain_every_n_turns": 1,
  "auto_recall": true,
  "retain_async": true
}
```

**Key fields:**
| Field | Default | Effect |
|-------|---------|--------|
| `mode` | `"cloud"` | `"local_external"` = connect to running server |
| `api_url` | cloud URL | For local: `http://localhost:8888` |
| `bank_id` | `"hermes"` | Which bank this profile writes to. Should match profile name for per-profile banks. |
| `auto_retain` | `true` | Enable `sync_turn` auto-retention after every turn |
| `retain_every_n_turns` | `1` | Flush every N turns. 1 = every turn. |
| `auto_recall` | `true` | Auto-recall relevant memories before each turn |
| `retain_async` | `true` | Process retains asynchronously on the server |

## Per-Profile Bank Isolation

For profiles to write to their **own** bank (not the shared `hermes` bank), two things must be true:

1. **The profile's `config.yaml`** must have `memory.provider: hindsight`
2. **The hindsight config** must have `bank_id: "<profile-name>"` (not `"hermes"`)

**Best practice:** Create per-profile hindsight configs at `~/.hermes/profiles/<name>/hindsight/config.json` with `bank_id` set to the profile name.

## Auto-Retain: How It Actually Works

The `sync_turn()` method fires after every conversation turn:

1. Buffers the turn in `_session_turns`
2. Increments `_turn_counter`
3. When `_turn_counter % _retain_every_n_turns == 0`, flushes via `aretain_batch()`
4. The flush runs on a **background writer thread** (non-blocking, ~1 second)

**Important:** The retain is **async**. If the process exits immediately after a turn (e.g., `hermes chat -q`), buffered retains may be lost. The `shutdown()` method drains the queue with a 10-second timeout.

**Session switches** (`/new`, `/reset`, context compression) trigger a flush of buffered turns under the old session's document ID before rotating.

## Diagnostic Checklist: "Why Isn't Auto-Retain Working?"

1. **Is the hindsight plugin loaded?**
   - `grep provider ~/.hermes/config.yaml` → must be `hindsight`, not `''`

2. **Is the hindsight service running?**
   - `curl -s http://localhost:8888/health` → `{"status":"healthy"}`

3. **Is auto_retain enabled?**
   - `cat ~/.hermes/hindsight/config.json` → `"auto_retain": true`

4. **Is the bank_id correct?**
   - Main profile: `bank_id: "hermes"` → shared bank
   - Agent profiles: `bank_id: "<profile-name>"` → own bank

5. **Check recent documents:**
   ```python
   import urllib.request, json
   url = 'http://localhost:8888/v1/default/banks/<bank_id>/documents?limit=5'
   req = urllib.request.Request(url)
   with urllib.request.urlopen(req, timeout=10) as resp:
       data = json.loads(resp.read().decode())
       for item in data.get('items', data.get('documents', [])):
           print(f"{item.get('created_at')} | tags={item.get('tags',[])} | len={item.get('text_length',0)}")
   ```

## Config Change Propagation

- **Changes to `config.yaml`** → take effect on next session start (`/reset`)
- **Changes to `hindsight/config.json`** → take effect on next session start
- **Changes to bank missions/dispositions** → take effect immediately (server-side)
- **Gateway restart** NOT required — only a new session (`/reset`)
