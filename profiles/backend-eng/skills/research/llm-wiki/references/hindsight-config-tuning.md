# Hindsight Config Tuning Quick Reference

## Optimal Config for Reducing Context Bloat

File: `~/.hermes/hindsight/config.json`

```json
{
  "recall_types": ["observation"],
  "recall_max_tokens": 2048,
  "recall_budget": "low",
  "retain_every_n_turns": 5
}
```

## What Each Setting Does

| Setting | Default | Recommended | Effect |
|---------|---------|-------------|--------|
| `recall_types` | `null` (all) | `["observation"]` | Only Observation layer recalled; eliminates Experience/World duplicates |
| `recall_max_tokens` | 4096 | 2048 | Half the injected context per turn |
| `recall_budget` | `mid` | `low` | Fewer memories retrieved per query |
| `retain_every_n_turns` | 1 | 5 | Retain only every 5th turn; 5x slower bank growth |

## Apply in One Command

```bash
python3 -c "
import json, os, pathlib
base = pathlib.Path(os.environ.get('HERMES_HOME', pathlib.Path.home() / '.hermes'))
path = base / 'hindsight' / 'config.json'
cfg = json.loads(path.read_text())
cfg['recall_types'] = ['observation']
cfg['recall_max_tokens'] = 2048
cfg['recall_budget'] = 'low'
cfg['retain_every_n_turns'] = 5
path.write_text(json.dumps(cfg, indent=2) + '\n')
print('Done.')
"
```

## Key Facts

- `recall_types` affects **recall only**, not retention. All 4 types still stored.
- Retention is **asynchronous** — new memories available on next turn.
- Wiping the DB does NOT fix bloat — symptoms return once experience entries re-accumulate.
- Disable built-in `memory` tool during debugging: `hermes tools disable memory`
- Check `memory_mode` — must be `hybrid` or `context` for auto-recall.

## Related

- GitHub: [hermes-agent#21698](https://github.com/NousResearch/hermes-agent/issues/21698)
- Paper: [arXiv 2512.12818](https://arxiv.org/abs/2512.12818) — Hindsight architecture (4 logical networks)
