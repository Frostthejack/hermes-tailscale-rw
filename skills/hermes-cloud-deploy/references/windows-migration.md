# Windows → Railway Migration Guide

## Split-Brain Architecture (Recommended)

Run TWO Hermes instances. Not everything should migrate to Railway:

| Location | What Runs There | Why |
|----------|----------------|-----|
| **Railway** | Colony monitor, GitRadar, kanban watchers, general agent | API-based, no local file deps |
| **Windows** | Trading system, wiki/vault, Windows-specific tools | Depends on local Windows paths/code |

Communication between both: Discord delivery targets (both deliver to same channels).

## What Migrates

### Skills → COPY into repo as `skills/` directory
- All skills EXCEPT: `windows-crash-forensics/`, `windows-discord-media/`, `windows-hermes-workarounds/`
- ~13MB total, all pure Python/markdown
- In Dockerfile: `COPY skills/ /root/.hermes/skills/`

### Profiles → COPY into repo as `profiles/` directory
- All profiles EXCEPT `trading/` (depends on Windows trading code)
- Copy: `SOUL.md`, `AGENTS.md`, `profile.yaml` from each profile dir
- Do NOT copy: `.env` files → use Railway env vars
- Do NOT copy: `state.db` files → use volume symlinks

### Hooks → COPY into repo as `hooks/` directory
- COPY `boot-md/` and `end-logger/`
- Rewrite `BOOT.md` for Linux (replace PowerShell with bash, Windows paths with Linux)

### Cron Jobs

**Migrate (6 jobs)**: colony-notifications-monitor, GitRadar Pipeline, GitRadar Recommendations, hermes-relay Kanban Watcher, hermes-relay Active Board Watcher, (optional: Trading Weekly Review if trading DB accessible)

**Keep on Windows (8 jobs)**: All 6 trading jobs (depend on `C:\Users\...\Hermes-Trading\`), Wiki Daily Briefing, Wiki Harvester (depend on `C:\Users\...\Vault\Encephalon-Mageia\`)

## Volume Strategy

Current estimated usage: ~260MB total (well within Hobby 5GB).

| Component | Size | Notes |
|-----------|------|-------|
| state.db | ~180MB | Main agent state — CRITICAL |
| Profile state.dbs | ~30MB | 8 active profiles |
| kanban.db | ~104KB | Small |
| response_store.db | ~20KB | Small |
| Tailscale state | ~1KB | Identity persistence |
| Logs | ~50MB | Rotated |

## Volume Symlink Pattern

The `railway-start.sh` MUST establish these symlinks BEFORE Hermes starts:

```
/root/.hermes/state.db → /hermes-data/state.db
/root/.hermes/response_store.db → /hermes-data/response_store.db
/root/.hermes/profiles/<name>/state.db → /hermes-data/profiles/<name>/state.db
/root/.hermes/logs → /hermes-data/logs
```

On first run: data in ephemeral `/root/.hermes/` is migrated TO `/hermes-data/`, then symlinked back.
On subsequent runs: `/hermes-data/` already has data, symlinks re-established.

## Repo Structure Expected by Dockerfile

```
hermes-tailscale-rw/
├── skills/              # Custom Linux skills only
├── profiles/            # SOUL.md + AGENTS.md + profile.yaml per profile
├── hooks/               # Hook directories
├── BOOT.md.railway      # Linux BOOT.md
├── HERMES.md.railway    # Linux HERMES.md
├── Dockerfile
├── railway.json
└── docker/
    ├── railway-start.sh
    ├── health.py
    └── generate_config.py
```

## Hindsight Migration

- **Source**: `local_external` mode, Hindsight API at `localhost:8888`, 12 banks
- **Target**: `local_embedded` mode, Railway managed PostgreSQL via `DATABASE_URL`

Two approaches:
1. **Export/import**: Use Hindsight API to export banks as JSON, import via POST on new instance
2. **Start fresh**: Let Hindsight rebuild banks from conversation history (simpler, loses historical embeddings)

pgvector extension is required for Hindsight embeddings — available on Railway's PG.

## 4-Phase Migration

1. **Foundation**: Add skills/profiles/hooks to repo, update Dockerfile/railway-start.sh, deploy
2. **Cron Migration**: Create Linux-path cron jobs on Railway, disable migrated ones on Windows
3. **Hindsight Migration**: Configure DATABASE_URL, migrate or rebuild banks
4. **Validation**: Full checklist — dashboard, SSH, API, health, Hindsight, volume persistence, cron firing
