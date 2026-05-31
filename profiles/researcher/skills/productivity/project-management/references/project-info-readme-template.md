# Project Info Index — Durable Backup

This document is the durable backup for the project info pointer pattern.
Store it at `~/.hermes/projects/README.md` on disk.

Even if MEMORY.md is rewritten, this file persists and any agent can `read_file()` it.

## How to Use

**To find project info:**
1. List files: `ls ~/.hermes/projects/info/`
2. Read the file matching your project

**To update:** Edit the relevant file, then commit the vault.
**To add a project:** Create a new `<project-name>.md` file here.

## Memory Architecture Summary

| Store | Location | Capacity | Auto-Injected | Write Tool |
|-------|----------|----------|---------------|------------|
| MEMORY.md | `~/.hermes/memories/MEMORY.md` | 2,200 chars | Yes (volatile, every turn) | `memory()` |
| USER.md | `~/.hermes/memories/USER.md` | 1,375 chars | Yes (volatile, every turn) | `memory()` |
| Hindsight | `~/.hermes/hindsight/` | Unlimited | On recall | `hindsight_retain()` |
| **HERMES.md** | `~/.hermes/HERMES.md` | 20,000 chars | **Yes (context tier, cached)** | `write_file()` |
| Context files | `AGENTS.md`/`CLAUDE.md` under `TERMINAL_CWD` | 20,000 chars | Yes (cached) | `write_file()` |
| Project info | `~/.hermes/projects/info/<project>.md` | Unlimited | No (read on demand) | `write_file()` |
| Project state | Vault `Projects/Personal/<project>/project-state.md` | Unlimited | No (read on demand) | `write_file()` |

### How HERMES.md Loading Works

- HERMES.md is loaded by `build_context_files_prompt()` from `TERMINAL_CWD`
- Priority: `.hermes.md`/`HERMES.md` > `AGENTS.md` > `CLAUDE.md` > `.cursorrules`
- **Config requirement:** `terminal.cwd` in `~/.hermes/config.yaml` must be set to the directory containing HERMES.md
- Current setting: `terminal.cwd: /home/frostthejack/.hermes`
- HERMES.md is in the **context tier** — cached within a session, rebuilt on compression (not every turn like MEMORY.md)
- Edits to HERMES.md take effect on the next new session or after context compression
- Both CLI and gateway load HERMES.md when `terminal.cwd` points to `~/.hermes/`

### 5-Layer Durability Model

To ensure project info survives any single point of failure:

1. **HERMES.md** — auto-loaded context file (survives memory rewrites)
2. **`~/.hermes/projects/info/<project>.md`** — on disk, read on demand
3. **`~/.hermes/projects/README.md`** — index file, durable backup of the pattern
4. **MEMORY.md pointer** — compact entry pointing to all of the above
5. **Hindsight retention** — semantic search backup of the architecture pattern
6. **Vault git** — versioned history of all vault files

## Key Rules

- **NEVER store project details in MEMORY.md** — use project info files or vault
- **The `memory()` tool can ONLY write to MEMORY.md/USER.md** — not arbitrary paths
- **HERMES.md is the preferred global instructions file** — it loads automatically when `terminal.cwd` is configured
- **Context files are cached** — unlike MEMORY.md which is volatile (rebuilt every turn)
- **Hindsight is the only unlimited store** — retain important patterns there
- **Use multi-tier redundancy** — don't rely on any single file
