---
author: Josh (frostthejack)
title: Memory Diagnostics Runbook
date: 2026-05-22
tags: [hindsight, memory, troubleshooting, hermes-agent]
---

# Hindsight Memory Diagnostics Runbook

## Context

From-session field notes from debugging Hindsight memory issues across multiple sessions. This file is a reference for the `llm-wiki` skill's troubleshooting section and for any session that needs to diagnose memory problems.

---

## The Problem

- **Symptom:** Hindsight recall returns heavy duplication — the same facts repeated 5-10 times in injected context
- **Impact:** Context window fills with noise; model output degrades; token usage inflates
- **Platform:** WSL2 Ubuntu, Hermes gateway, hindsight 0.6.0 local_embedded

## Root Cause Chain

1. **Default `recall_types=None`** → recalls all types (world + experience + observation)
2. **Experience layer accumulates** — per-turn observations overlap semantically
3. **No MMR/dedup in recall** — upstream Hindsight rejected this feature (#1309)
4. **Retain feedback loop** — recalled memories get re-retained every turn (mitigated on Hermes side but not eliminated)

## The Four Memory Networks (from arXiv 2512.12818)

Hindsight organizes memory into four logical networks:

| Network | Code | Type | Example |
|---------|------|------|---------|
| **World** | W | Objective fact | "Alice works at Google" |
| **Experience** | B | First-person | "I recommended using pandas" |
| **Opinion** | O | Subjective judgment | "Python is better for data science" |
| **Observation** | S | Neutral summary | "Alice is a software engineer at Google" |

The **Experience layer (B)** is the primary bloat source — it captures per-turn agent actions that overlap semantically.

## The Fix

Set `recall_types: ["observation"]` in `~/.hermes/hindsight/config.json`:

```json
{
  "recall_types": ["observation"]
}
```

### What This Changes

- ✅ **Recall (injection):** Only Observation-type memories are retrieved and injected into context
- ✅ **Retention (storage):** All four types are still stored — nothing is lost
- ✅ **Query fallback:** User can query Hindsight directly for World/Experience if needed
- ✅ **Async timing:** Fix takes effect on the next turn (retention is asynchronous)

### Trade-off

Loses synthesized Experience and World memories from automatic context injection. Only raw observations are recalled. Acceptable for most users.

## Verification Steps

1. Check current config:
   ```bash
   python -c "
   import json, os, pathlib
   base = pathlib.Path(os.environ.get('HERMES_HOME', pathlib.Path.home() / '.hermes'))
   path = base / 'hindsight' / 'config.json'
   cfg = json.loads(path.read_text())
   print('recall_types:', cfg.get('recall_types', 'NOT SET (defaults to None = all types)'))
   "
   ```

2. Apply fix:
   ```bash
   python -c "
   import json, os, pathlib
   base = pathlib.Path(os.environ.get('HERMES_HOME', pathlib.Path.home() / '.hermes'))
   path = base / 'hindsight' / 'config.json'
   cfg = json.loads(path.read_text())
   cfg['recall_types'] = ['observation']
   path.write_text(json.dumps(cfg, indent=2) + '\n')
   print('Done. recall_types set to [observation]')
   "
   ```

3. Restart Hermes and test with a controlled retain → next-turn recall

## Related GitHub Issues

- [hermes-agent#21698](https://github.com/NousResearch/hermes-agent/issues/21698) — Surface recall_types workaround
- [hindsight#1284](https://github.com/vectorize-io/hindsight/issues/1284) — Experience-layer semantic dedup (OPEN)
- [hindsight#1309](https://github.com/vectorize-io/hindsight/issues/1309) — No MMR/dedup (CLOSED NOT_PLANNED)
- [hindsight#826](https://github.com/vectorize-io/hindsight/issues/826) — Retain-time dedup (CLOSED NOT_PLANNED)
- [hindsight#360](https://github.com/vectorize-io/hindsight/issues/360) — Retain feedback loop (CLOSED)

## Notes

- Wiping the DB does NOT fix this — symptoms return once experience entries re-accumulate
- The built-in Hermes `memory` tool can also cause confusion — disable during debugging: `hermes tools disable memory`
- `memory_mode: tools` disables auto-recall entirely — make sure you're in `hybrid` or `context` mode
- Fix applied 2026-05-22 by user request
