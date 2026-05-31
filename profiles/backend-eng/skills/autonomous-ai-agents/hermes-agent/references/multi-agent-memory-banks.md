# Multi-Agent Memory Bank Pattern

## Overview

Each Hermes agent profile gets its own isolated Hindsight memory bank for
role-specific knowledge, plus read access to a shared `hermes` bank for
cross-agent context.

## Architecture

```
Hindsight API (http://localhost:8888)
├── /v1/default/banks/hermes          ← Shared bank (all agents read)
├── /v1/default/banks/analyst         ← Analyst-only memories
├── /v1/default/banks/backend-eng     ← Backend eng memories
├── /v1/default/banks/frontend-eng    ← Frontend eng memories
├── /v1/default/banks/ops             ← Ops memories
├── /v1/default/banks/pm              ← PM memories
├── /v1/default/banks/researcher      ← Researcher memories
├── /v1/default/banks/reviewer        ← Reviewer memories
├── /v1/default/banks/writer          ← Writer memories
├── /v1/default/banks/claude_code     ← Claude Code (existing)
└── /v1/default/banks/mimir-well      ← Legacy (existing)
```

## Creating a New Bank

```bash
curl -s -X PUT http://localhost:8888/v1/default/banks/{bank_id} \
  -H "Content-Type: application/json" \
  -d '{
    "bank_id": "{bank_id}",
    "name": "{bank_id}",
    "mission": "Role-specific mission statement",
    "disposition": {
      "skepticism": 1-5,
      "literalism": 1-5,
      "empathy": 1-5
    }
  }'
```

**Important:** Always include the full payload (bank_id, name, mission,
disposition) in a single PUT. Partial updates may reset unspecified fields
to defaults.

## Disposition Guide

| Role | Skepticism | Literalism | Empathy | Rationale |
|------|-----------|------------|---------|-----------|
| analyst | 4 | 3 | 2 | Question data, verify claims |
| backend-eng | 3 | 4 | 2 | Precise, specification-driven |
| frontend-eng | 2 | 3 | 4 | User-centered, accessible |
| ops | 4 | 4 | 2 | Verify everything, exact procedures |
| pm | 2 | 3 | 4 | Stakeholder-focused, flexible |
| researcher | 5 | 4 | 2 | Demand evidence, precise |
| reviewer | 5 | 4 | 2 | Assume nothing, exact standards |
| writer | 2 | 2 | 5 | Creative, reader-focused |

## Cross-Bank Access

Agents READ from their own bank (automatic via hindsight tools) and the
shared `hermes` bank. To query another bank:

```bash
curl -s -X POST http://localhost:8888/v1/default/banks/{bank_id}/memories/recall \
  -H "Content-Type: application/json" \
  -d '{"query": "search terms", "budget": "low"}'
```

**Write rule:** Agents ONLY write to their own bank. For cross-agent knowledge,
retain to the shared `hermes` bank.

## Profile AGENTS.md Setup

Each profile gets an `AGENTS.md` in `~/.hermes/profiles/{name}/` containing:
- Bank ID and purpose
- Quick-reference table of all banks and when to query them
- Access rules (write own, read shared, read others via API)
- Role-specific disposition values
- **Auto-recall trigger** — mandatory `hindsight_recall` calls at session start
- **Memory retention rules** — when to retain to own bank vs shared bank

See `~/.hermes/memory-bank-registry.md` for the full registry.

## Files

- `~/.hermes/memory-bank-registry.md` — Full bank registry (all agents)
- `~/.hermes/profiles/{name}/AGENTS.md` — Per-profile bank config
- `~/.hermes/profiles/{name}/hindsight/config.json` — **Per-profile hindsight config (REQUIRED)**

## Per-Profile Hindsight Config (REQUIRED for bank isolation)

**This is the most commonly missed step.** Without a profile-scoped hindsight config, the profile defaults to the global `~/.hermes/hindsight/config.json` which points to the `hermes` shared bank — the profile will never read/write its own bank.

**However**, if all profiles share the same hindsight config (pointing to `bank_id: "hermes"`), they will ALL write to the shared bank. For per-profile bank isolation, each profile needs its own config.

Create `~/.hermes/profiles/{name}/hindsight/config.json` for each profile that needs its own bank:

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
  "bank_id": "{profile_name}",
  "recall_budget": "mid",
  "auto_retain": true,
  "retain_every_n_turns": 1,
  "auto_recall": true,
  "retain_async": true,
  "banks": {
    "{profile_name}": {
      "bankId": "{profile_name}",
      "budget": "mid",
      "enabled": true
    }
  }
}
```

**Config resolution order** (from the Hindsight plugin source `_load_config()`):
1. `$HERMES_HOME/hindsight/config.json` (profile-scoped — this is the one that matters)
2. `~/.hindsight/config.json` (legacy, shared)
3. Environment variables

Since `$HERMES_HOME` resolves to `~/.hermes/profiles/{name}/` when running under a profile, the profile-scoped config takes priority. If no profile-scoped config exists, the global `~/.hermes/hindsight/config.json` is used.

**Important:** The `bank_id` in the hindsight config determines which bank the profile writes to. If it's `"hermes"`, the profile writes to the shared bank. If it's the profile name, the profile writes to its own bank.

**Current state (May 2026):** Only the global `~/.hermes/hindsight/config.json` exists with `bank_id: "hermes"`. No per-profile hindsight configs exist. This means all profiles write to the shared `hermes` bank unless per-profile configs are created.

## Retaining Memories via REST API

The `hindsight_retain` tool is the normal path. For direct REST API access (e.g., seeding banks from a script):

```bash
# Retain one or more memories to a bank
curl -s -X POST http://localhost:8888/v1/default/banks/{bank_id}/memories \
  -H "Content-Type: application/json" \
  -d '{
    "items": [
      {"content": "Memory text here"},
      {"content": "Another memory"}
    ],
    "async": true
  }'
```

**Note:** The endpoint is `/memories` (not `/memories/retain`). The `async: true` flag processes in the background — check `/v1/default/banks/{bank_id}/operations` for status.

## Recall vs Reflect

- **`recall`** — Semantic/keyword search for specific memories. May return 0 results for newly retained memories until fully indexed/consolidated.
- **`reflect`** — Synthesizes a reasoned answer across all stored memories. Works even when `recall` returns 0.
- **The Hermes `hindsight_recall` tool** wraps the API and works correctly even when direct REST `recall` returns 0.

## Auto-Recall Behavior

The Hindsight plugin has `auto_recall=True` and `auto_retain=True` by default. The agent loop calls `prefetch_all()` before every turn, which triggers a recall from the active bank. However:

- **Auto-recall uses the user's message as the query** — if the query doesn't semantically match stored memories, they won't surface. Profile-specific bank memories (e.g., "I question data and verify claims") may not match typical user queries.
- **The shared `hermes` bank auto-recalls well** because its memories (user preferences, project context) match common queries.
- **Profile-specific banks need explicit recall** via AGENTS.md instructions to guarantee the agent loads its role-specific knowledge.
- **Auto-retain may not trigger for one-shot `chat -q` sessions** — multi-turn interactive sessions (gateway) go through the full `sync_all` cycle.

**Best practice:** Always include explicit `hindsight_recall` calls in AGENTS.md for profile-specific banks. Don't rely solely on auto-recall.

## Profile Gateway Status

Profiles show `gateway: stopped` in `hermes profile list` — this is **expected**. Profiles are on-demand agents, not persistent gateway services. They're spawned via `hermes -p {name} chat -q "..."` and load their hindsight bank at startup. The single `hermes-gateway.service` (systemd) handles all platform connections (Discord, Telegram, etc.) and routes messages to the correct profile agent.

## Seeding a New Profile Bank — Full Checklist

When setting up a new profile's memory bank from scratch:

1. **Create the bank** via PUT with FULL payload (bank_id, name, mission, disposition) — partial PUT resets fields to defaults
2. **Create per-profile hindsight config** at `~/.hermes/profiles/{name}/hindsight/config.json` — without this, the profile defaults to the shared `hermes` bank
3. **Seed initial memories** via `POST /v1/default/banks/{bank_id}/memories` with `{"items": [...], "async": true}`
4. **Update AGENTS.md** at `~/.hermes/profiles/{name}/AGENTS.md` with auto-recall trigger, retention rules, and bank registry
5. **Verify** by spawning the profile: `hermes -p {name} chat -q "Call hindsight_recall with query 'your role'"`

**Common failure mode:** Steps 1 and 2 are done but step 2's config points to the wrong bank_id, or step 4 is missing so the agent never explicitly recalls its bank.

## Bank Tuning: Missions and Dispositions (May 2026 Findings)

### The Gap

As of May 2026, all 10 Hindsight banks have:
- **Empty `mission` and `retain_mission`** fields — Hindsight extracts and reasons without role-specific framing
- **Default 3/3/3 dispositions** on every bank — despite the registry defining differentiated dispositions per role

This means Hindsight treats all banks identically, missing the opportunity to specialize extraction and reasoning per role.

### How to Fix

**Set bank missions via PUT (full payload required — partial PUT resets fields):**

```bash
curl -s -X PUT http://localhost:8888/v1/default/banks/{bank_id} \
  -H "Content-Type: application/json" \
  -d '{
    "bank_id": "{bank_id}",
    "name": "{bank_id}",
    "mission": "Role-specific identity and purpose",
    "retain_mission": "What to extract and retain from conversations",
    "disposition": {
      "skepticism": <1-5>,
      "literalism": <1-5>,
      "empathy": <1-5>
    }
  }'
```

### Recommended Missions and Dispositions

| Bank | Mission | Retain Mission | Skep | Lit | Emp |
|------|---------|---------------|------|-----|-----|
| **hermes** | Cross-agent shared memory for user preferences, project context, and lessons learned | Retain user preferences, project decisions, environment facts, and cross-cutting lessons | 3 | 3 | 3 |
| **analyst** | System evaluation and data analysis patterns | Retain analysis methodologies, data patterns, system metrics, and evaluation frameworks | 4 | 3 | 2 |
| **backend-eng** | Backend architecture, API design, and infrastructure decisions | Retain API schemas, DB designs, service patterns, and deployment architectures | 3 | 4 | 2 |
| **frontend-eng** | UI/UX patterns, component architecture, and accessibility | Retain component patterns, UX decisions, accessibility requirements, and design system choices | 2 | 3 | 4 |
| **ops** | Deployment procedures, monitoring, and incident response | Retain deployment configs, monitoring setups, incident postmortems, and runbooks | 4 | 4 | 2 |
| **pm** | Project management, stakeholder context, and prioritization | Retain project timelines, stakeholder preferences, prioritization rationale, and status updates | 2 | 3 | 4 |
| **researcher** | Deep research findings and investigation methodology | Retain research findings, paper summaries, investigation notes, and source evaluations | 5 | 4 | 2 |
| **reviewer** | Code review patterns, quality standards, and security | Retain review checklists, quality standards, security patterns, and common defect categories | 5 | 4 | 2 |
| **writer** | Documentation, content creation, and style guides | Retain documentation drafts, style guides, publishing notes, and content patterns | 2 | 2 | 5 |

### Verification

After setting missions/dispositions, verify:
```bash
curl -s http://localhost:8888/v1/default/banks/{bank_id} | python3 -m json.tool
```

Check that `mission`, `retain_mission`, and `disposition` fields are populated correctly.

### Why This Matters

- **`mission`** frames how Hindsight reasons about the bank's purpose during reflect operations
- **`retain_mission`** steers what gets extracted from conversations — without it, Hindsight uses generic extraction
- **Dispositions** control the reasoning personality: skepticism (question vs accept), literalism (exact vs interpretive), empathy (user-focused vs system-focused)
- Without these, all banks behave identically regardless of their intended role

## Auto-Consolidate Pattern (May 2026)

### The Problem

Hindsight's `hindsight_reflect` tool (LLM-powered cross-memory synthesis) is exposed as a tool the agent can call, but agents rarely think to call it. The result: raw conversation turns accumulate in banks but are never synthesized into higher-level observations.

### The Solution: Periodic /consolidate via Cron

The Hindsight server has a `POST /v1/default/banks/{bank_id}/consolidate` endpoint that runs memory consolidation server-side — creating/updating observations from recent memories. This is the reliable alternative to the `hindsight_reflect` LLM endpoint, which frequently times out (120s+) even on small banks.

**Key findings (May 2026):**
- `/consolidate` completes in < 1 second per bank
- `/reflect` times out consistently (tested with max_tokens=256 on 1-document bank — still times out at 120s)
- The `on_session_end` hook in `plugin.yaml` is registered but **not implemented** in the plugin code — there is no `on_session_end` method, only `on_session_switch` and `shutdown`
- Session-end flushes happen through `on_session_switch` (fires on `/new`, `/reset`, `/resume`, context compression) and `shutdown()`

**Anti-duplication strategy (3 layers):**
1. **Timestamp tracking** — `~/.hermes/hindsight/last_reflected.json` tracks per-bank last run; skips banks with no new documents since then
2. **Minimum interval** — 1 hour safety net prevents re-running the same bank
3. **Tag check** — Checks for existing `auto-reflect` tags from the last 6 hours

**Cron schedule:** Every 5 hours is a good balance — frequent enough to keep observations fresh, infrequent enough to avoid unnecessary API calls.

**Script location:** `~/.hermes/hindsight/auto_reflect.py` — run with `python3 ~/.hermes/hindsight/auto_reflect.py`

**Dry run:** `python3 ~/.hermes/hindsight/auto_reflect.py --dry-run`

**Single bank:** `python3 ~/.hermes/hindsight/auto_reflect.py --bank hermes`

### Consolidate vs Reflect

| | `/consolidate` | `/reflect` (LLM endpoint) |
|---|---|---|
| Speed | < 1 second | Frequently times out (120s+) |
| Output | Server-side observations | Human-readable synthesis text |
| Reliability | High | Low (requires working LLM backend) |
| Use case | Periodic background synthesis | On-demand human-readable summary |

**Recommendation:** Use `/consolidate` as the primary synthesis mechanism via cron. The `/reflect` endpoint can be used on-demand when a human-readable summary is needed, but don't rely on it for automated workflows.
