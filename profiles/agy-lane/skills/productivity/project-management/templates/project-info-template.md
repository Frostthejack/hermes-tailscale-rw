# <Project Name> — Hermes Infra

## Code
- **GitHub:** <user>/<repo>
- **Local:** `<full local path>`
- **Clone:** `gh repo clone <user>/<repo> <local path>`

## Vault
- **Path:** `/mnt/c/Users/luned/Vault/Encephalon-Mageia/Projects/Personal/<project>/`
- **project-state.md:** `<vault path>/project-state.md`

## Kanban
- **Board slug:** `<slug>`
- **DB:** `~/.hermes/kanban/boards/<slug>/kanban.db`
- **List:** `hermes kanban --board <slug> list`

## Symlinks (in code repo)
- `project-state.md` → vault project-state.md
- `docs/` → vault project directory

## Cron Jobs
| Job | Schedule | Purpose |
|-----|----------|---------|
| `<name>` | `<freq>` | `<what it does>` |

## Agent Lanes
- `claude-lane` — Complex coding tasks
- `agy-lane` — Quick fixes
- `reviewer` — Code review

## Notes
<Any Hermes-specific operational notes>
