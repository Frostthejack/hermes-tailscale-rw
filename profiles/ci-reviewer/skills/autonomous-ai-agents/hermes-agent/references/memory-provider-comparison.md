# Memory Provider Comparison: Hindsight vs Honcho

## Honcho Overview

**Honcho** (by Plastic Labs, https://honcho.dev) is a reasoning-first memory infrastructure for
building stateful agents. It models users, agents, groups, and projects as "peers" that
change over time, using formal logic to extract deductive conclusions.

**GitHub:** https://github.com/plastic-labs/honcho (3.6k stars, v3.0.6)

### Architecture

```
Hermes Agent ──► Honcho API (api.honcho.dev or self-hosted)
                      │
                      ├── Sessions (messages grouped by directory/repo/global)
                      ├── Peers (user peer + one AI peer per Hermes profile)
                      ├── Representations (per-peer conclusions from reasoning)
                      └── Deriver workers (background Neuromancer reasoning)
```

**Two-layer context injection:**
- **Base layer** (refreshed on `contextCadence`): session summary + representation + peer card
- **Dialectic supplement** (refreshed on `dialecticCadence`): multi-pass LLM reasoning with self-audit

**Three independent cost/latency knobs:** contextCadence, dialecticCadence, dialecticDepth (1-3)

### Tools (5 total)

| Tool | Purpose |
|------|---------|
| `honcho_profile` | Read/update peer card |
| `honcho_search` | Semantic search |
| `honcho_context` | Session context (summary, representation, card, messages) |
| `honcho_reasoning` | LLM-synthesized reasoning |
| `honcho_conclude` | Create/delete conclusions |

### Neuromancer Model

Neuromancer XR — 8B model fine-tuned from Qwen3-8B on ~10,000 social reasoning traces.
Benchmark: **86.9% on LoCoMo** memory benchmark vs 69.6% for base Qwen3-8B, 80.0% for Claude 4 Sonnet.

### Multi-Peer Setup

- **Workspace** = shared environment (all Hermes profiles share one)
- **User peer** = the human (shared across profiles)
- **AI peer** = one per Hermes profile
- Each AI peer builds an independent representation from its own observations

### Pricing

- **Managed cloud:** $100 free credits on signup, then pay-as-you-go (~$0.04 per quickstart)
- **Self-hosted:** Free (uses your own API keys + Docker + PostgreSQL + Redis)

## Hindsight Overview

**Hindsight** is a knowledge graph-based memory system with multi-strategy retrieval
(semantic + entity graph + BM25). Currently deployed locally for Hermes.

### Architecture

```
Hermes Agent ──► localhost:8888 (self-hosted Hindsight)
                      │
                      ├── PostgreSQL + pgvector (local)
                      ├── Entity graph with relationships
                      ├── Per-profile memory banks (10 banks configured)
                      └── Reflect workers (background LLM synthesis)
```

**Three tools:** `hindsight_retain`, `hindsight_recall`, `hindsight_reflect`

### Unique Capability: Reflect

`hindsight_reflect` performs cross-memory synthesis — LLM-powered reasoning across all
stored memories. Honcho's dialectic is the closest equivalent but works differently
(multi-pass self-audit on a single peer's representation).

### Current Deployment (frostthejack, May 2026)

- **Mode:** local_external at `http://localhost:8888` (forwarded from Windows host `192.168.0.40:8888`)
- **Banks:** hermes (shared), analyst, backend-eng, frontend-eng, ops, pm, researcher, reviewer, writer, claude_code, mimir-well (legacy)
- **Cost:** $0 (fully self-hosted)
- **Known gaps:** All bank dispositions are 3/3/3 (default) despite registry defining differentiated values. All bank missions are empty strings.

## Head-to-Head Comparison

| Capability | Hindsight | Honcho |
|---|---|---|
| Knowledge graph | Entity extraction + relationships | Peer representations |
| Reasoning depth | Reflect (single-pass LLM synthesis) | Dialectic (multi-pass + self-audit) |
| Auto-retain | Every conversation turn | Async background processing |
| Cross-agent memory | Cross-bank read + shared hermes bank | Shared workspace + per-peer models |
| Data sovereignty | Fully local | Cloud by default, self-hostable |
| Cost | Free | $100 free credits, then pay-per-use |
| Context injection | Auto-recall before each turn | Base layer + dialectic supplement |
| Dedicated reasoning model | Uses configured LLM | Neuromancer (specialized 8B) |
| Multi-agent isolation | Per-profile banks with dispositions | Per-peer within workspace |
| Reflect / synthesis | hindsight_reflect | No direct equivalent |
| Observation toggles | N/A | Per-peer directional/unified |

## How They Complement Each Other

| Problem | Best Fit |
|---|---|
| What did we discuss last time? | Both |
| What are the facts about this project? | Hindsight (knowledge graph) |
| What does the user really want? | Honcho (dialectic user modeling) |
| What patterns emerge across all our work? | Hindsight (reflect across banks) |
| How has this user changed over time? | Honcho (evolving peer representations) |
| API schemas and DB designs? | Hindsight (structured knowledge) |

## Recommendation

**Don't switch. Layer.**

1. Hindsight is already running, fully local, 10 banks, $0 cost. Fix the known gaps first.
2. Honcho adds the most value for user-facing products needing deep user modeling.
3. Honcho self-hosting is possible for $0 cloud cost (Docker + own API keys).

**Prerequisite: Fix Hindsight first:**
- Set bank_mission and bank_retain_mission on each bank (currently all empty)
- Apply differentiated dispositions per the registry (currently all 3/3/3)
- Use hindsight_reflect more aggressively for cross-memory synthesis
- Add explicit retention quality checks in profile AGENTS.md files

**Then evaluate Honcho** for agents that need deep user modeling (tutor, assistant, support).

## Honcho Self-Hosting Quick Reference

```bash
# Clone + start
git clone https://github.com/elkimek/honcho-self-hosted.git ~/honcho-self-hosted
git clone --depth 1 https://github.com/plastic-labs/honcho.git ~/honcho
cp ~/honcho-self-hosted/docker-compose.yml ~/honcho/
cp ~/honcho-self-hosted/config.toml ~/honcho/
cp ~/honcho-self-hosted/env.example ~/honcho/.env
# Edit .env with API keys, then:
cd ~/honcho && docker compose up -d
# API at http://localhost:8000
```

Configure Hermes (~/.hermes/honcho.json):
```json
{
  "baseUrl": "http://localhost:8000",
  "hosts": {
    "hermes": {
      "enabled": true,
      "aiPeer": "hermes",
      "peerName": "frostthejack",
      "workspace": "hermes"
    }
  }
}
```
