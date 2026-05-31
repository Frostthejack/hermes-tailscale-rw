# Kanban Profile Setup with Hindsight Banks

## Full Profile Creation + Bank Assignment Workflow

This reference covers creating kanban specialist profiles AND configuring them with isolated hindsight memory banks. Run this once when standing up a new kanban board.

### Step 1: Create Profiles

Clone from default to inherit model config, API keys, credential pool, and skills:

```bash
for name in orchestrator researcher analyst writer reviewer backend-eng frontend-eng ops pm claude-lane agy-lane ci-reviewer; do
  hermes profile create "$name" --clone-from default
done
```

Each profile gets:
- Wrapper script at `~/.local/bin/<name>`
- Config at `~/.hermes/profiles/<name>/config.yaml`
- SOUL.md, AGENTS.md, workspace, sessions, skills dirs

### Step 2: Configure Hindsight Bank Isolation

This is the **critical step** most setups miss. Each profile needs TWO config layers:

#### Layer 1: config.yaml — activates hindsight plugin
Each profile's `config.yaml` must have:
```yaml
memory:
  memory_enabled: true
  provider: hindsight    # NOT empty string
  auto_retain: true
  auto_recall: true
  retain_every_n_turns: 1
```
This is inherited from default if default already has it. Verify with:
```bash
hermes -p <name> config show | grep -A3 "memory:"
```

#### Layer 2: hindsight/config.json — controls which bank
Each profile needs `~/.hermes/profiles/<name>/hindsight/config.json`:

```json
{
  "mode": "local_external",
  "apiKey": "",
  "timeout": 120,
  "idle_timeout": 300,
  "retain_tags": "",
  "retain_source": "",
  "retain_user_prefix": "User",
  "retain_assistant_prefix": "Assistant",
  "api_url": "http://localhost:8888",
  "bank_id": "<profile-name>",
  "recall_budget": "mid",
  "auto_retain": true,
  "retain_every_n_turns": 1,
  "auto_recall": true,
  "retain_async": true,
  "recall_types": ["observation", "world", "experience"],
  "recall_max_tokens": 2048,
  "banks": {
    "<profile-name>": {
      "bankId": "<profile-name>",
      "budget": "mid",
      "enabled": true
    }
  }
}
```

**CRITICAL:** `bank_id` must match the hindsight bank name, NOT necessarily the profile name.

### Standard Bank-to-Profile Mapping

| Profile | Hindsight Bank ID | Notes |
|---------|------------------|-------|
| `orchestrator` | `orchestrator` | Auto-created on first retain |
| `researcher` | `researcher` | Pre-existing bank |
| `analyst` | `analyst` | Pre-existing bank |
| `writer` | `writer` | Pre-existing bank |
| `reviewer` | `reviewer` | Pre-existing bank |
| `backend-eng` | `backend-eng` | Pre-existing bank, usually most facts |
| `frontend-eng` | `frontend-eng` | Pre-existing bank |
| `ops` | `ops` | Pre-existing bank |
| `pm` | `pm` | Pre-existing bank |
| `claude-lane` | `claude_code` | **NOT `claude-lane`** — maps to existing claude_code bank |
| `agy-lane` | `agy-lane` | Auto-created on first retain |
| `ci-reviewer` | `ci-reviewer` | Pre-existing bank |

**Pitfall:** `claude-lane` profile name ≠ `claude_code` bank name. Using `claude-lane` as bank_id creates a separate bank that won't share existing Claude Code memories.

### Step 3: Verify Bank Existence

List all banks via API:
```bash
curl -s http://localhost:8888/v1/default/banks
```

Banks auto-create on first `hindsight_retain` call. You do NOT need to create them manually.

### Step 4: Configure Kanban Dispatcher

Set in the **default** profile's `config.yaml`:
```yaml
kanban:
  orchestrator_profile: orchestrator
  max_spawn: 2           # 1-2 recommended for rate-limited providers
  dispatch_in_gateway: true
  dispatch_interval_seconds: 60
```

### Step 5: Verify Profiles Are Recognized

```bash
hermes kanban assignees
```

Should list all profiles with `(idle)` status.

### Step 6: Gateway Restart Required

After creating new profiles, restart the gateway so the dispatcher picks them up:
```bash
hermes gateway restart
```

On Windows this may require manual confirmation. Profiles won't be available for dispatch until the gateway reloads the profile roster.

### Step 7: Smoke Test

```bash
hermes kanban create "test: verify <profile> dispatch" \
  --assignee <profile> \
  --body "Report that you're alive and confirm your hindsight bank ID."
```

Wait up to 60 seconds. Check with `hermes kanban show <task_id>`. Should show `status: done`.

### Pitfall: Hindsight Bank Priority / Config Resolution

The hindsight config resolves in this order:
1. `$HERMES_HOME/hindsight/config.json` — profile-scoped (preferred)
2. `~/.hindsight/config.json` — legacy shared path
3. Environment variables

If `~/.hermes/hindsight/config.json` (default profile) has `bank_id: "hermes"`, the default profile writes to the shared `hermes` bank. Each specialist profile writes to its own bank via its profile-scoped config.

### Pitfall: Profile Can't Write to Wrong Bank

If a worker's hindsight retains aren't showing up in the expected bank:
1. Check the profile's `hindsight/config.json` bank_id
2. Check that `memory.provider: hindsight` in the profile's `config.yaml`
3. Check hindsight service health: `curl -s http://localhost:8888/health`
4. Verify the bank exists: `curl -s http://localhost:8888/v1/default/banks/<bank_id>`

### Pitfall: Cross-Bank Reading

Workers can read OTHER profiles' banks via the recall API:
```bash
curl -s -X POST http://localhost:8888/v1/default/banks/backend-eng/memories/recall \
  -H "Content-Type: application/json" \
  -d '{"query": "architecture decisions", "budget": "low"}'
```

This is how an `analyst` can read `researcher` findings from the researcher's isolated bank.
