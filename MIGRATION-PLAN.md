# Windows Hermes → Railway Migration Plan

## Executive Summary

This document categorizes every Windows Hermes customization, determines what can migrate to Railway, and provides a prioritized plan with Dockerfile modifications, volume strategy, and cron job routing.

**Core constraint**: Railway containers are ephemeral — `/root/.hermes/` and `/hermes-data/` (unless on a volume) are wiped on every restart. The current Dockerfile builds hermes-agent from GitHub source and starts via `start-all.sh`.

---

## 1. Categorization: What CAN and CANNOT Migrate

### 1A. Skills (34 directories, ~13MB, 931 files)

| Category | Migrate? | Notes |
|----------|----------|-------|
| **Bundled skills** (airtable, apple-notes, arxiv, github, etc.) | ✅ Auto-installed | Come with `hermes-agent` pip package. No action needed. |
| **Custom/broad skills** (the-colony, hermes-cloud-deploy, devops/*) | ✅ COPY into Dockerfile | Pure Python/skill files. Linux-compatible. |
| **Windows-specific skills** (windows-crash-forensics, windows-discord-media, windows-hermes-workarounds) | ❌ Keep on Windows only | Windows-path dependent, PowerShell, .exe calls. |
| **Semi-portable skills** (devops/watchers, devops/kanban-orchestrator, devops/kanban-worker) | ⚠️ Needs path rewrites | Contain Windows-style paths in scripts but logic is portable. |

**Recommendation**: COPY the entire `skills/` tree into the container via `git` (recommended: add as git submodule or COPY from repo). The 13MB size is trivial. Exclude Windows-only skills.

### 1B. Profiles (14 profiles → 13 profile dirs + default)

| Profile | Migrate? | Notes |
|---------|----------|-------|
| **agy-lane** | ✅ Easy | SOUL.md + AGENTS.md + config.yaml. Pure text. |
| **analyst** | ✅ Easy | same |
| **backend-eng** | ✅ Easy | same |
| **ci-reviewer** | ✅ Easy | same |
| **claude-lane** | ✅ Easy | same |
| **frontend-eng** | ✅ Easy | same |
| **mimirs-will** | ✅ Easy | same. SOUL.md references `C:\Users\...` paths in AGENTS.md (vault git push) — these are only used by the cron job's prompt, not the SOUL.md itself. |
| **ops** | ✅ Easy | same |
| **orchestrator** | ✅ Easy | same |
| **pm** | ✅ Easy | same |
| **researcher** | ✅ Easy | same |
| **reviewer** | ✅ Easy | same |
| **trading** | ❌ Keep on Windows | Depends on `C:\Users\...\Documents\Projects\Hermes-Trading\` code, local ONNX runtime, Windows Python. |
| **writer** | ✅ Easy | same as others |

**Recommendation**: COPY all profiles' SOUL.md and AGENTS.md into the container. The `.env` files should NOT be copied — use Railway environment variables instead. Profile `state.db` files should live on a Railway Volume.

### 1C. Hooks (2 hooks)

| Hook | Migrate? | Notes |
|------|----------|-------|
| **boot-md** | ✅ Mostly | Python handler uses `from gateway.run import ...` and `from run_agent import AIAgent`. These are hermes-agent internals. HOOK.yaml references `gateway:startup` event — compatible with Linux Hermes. The BOOT.md file contains Windows-specific commands (`powershell Get-PSDrive C`) and Windows paths. Needs content rewrite for Linux. |
| **end-logger** | ✅ Easy | Pure Python, uses `pathlib.Path.home() / ".hermes" / "logs"`. Fully Linux-compatible. Writes JSONL session events. |

**Recommendation**: COPY both hook directories into `/root/.hermes/hooks/`. Rewrite BOOT.md for Linux (`df -h` instead of PowerShell, remove Windows-specific path checks).

### 1D. Cron Jobs (14 active)

| # | Job | Schedule | Migrate to Railway? | Notes |
|---|-----|----------|---------------------|-------|
| 1 | **Wiki Daily Briefing** | `0 18,2 * * *` (2×/day) | ❌ **Keep on Windows** | Prompt hardcodes `C:\Users\luned\AppData\Local\hermes\scripts\wiki-daily-briefing.sh` and `C:\Users\luned\Vault\...`. Depends on local Obsidian vault. |
| 2 | **Wiki Harvester** | every 30 min | ❌ **Keep on Windows** | Same Windows path dependencies. RSS/GitHub polling scripts are Windows-path-dependent. |
| 3 | **colony-notifications-monitor** | every 12 hrs | ✅ **Migrate** | Pure API calls to thecolony.cc. Only dependency is `COLONY_API_KEY` (env var). Profile `mimirs-will` is portable. |
| 4 | **GitRadar Pipeline** | daily 15:00 | ✅ **Migrate** | Runs `python3 scripts/gitradar-discover.py && python3 scripts/gitradar-score.py` in `C:\Users\...\gitradar`. Need to COPY gitradar project into container or clone from GitHub. Depends on `GITHUB_TOKEN`. |
| 5 | **GitRadar Recommendations** | daily 16:00 | ✅ **Migrate** | Reads `recommendations.json` from gitradar project. Same migration path as #4. |
| 6 | **hermes-relay Kanban Watcher** | every 5 min | ✅ **Migrate** | Runs `hermes kanban --board hermes-relay list`. Works if kanban DB is on a Railway Volume. Discord delivery target is a channel ID — works from anywhere. |
| 7 | **hermes-relay Active Board Watcher** | every 5 hrs | ✅ **Migrate** | Same as #6, plus git health checks. Needs `git` installed (already in Dockerfile). |
| 8 | **Trading Premarket Scan** | `0 7 * * 1-5` | ❌ **Keep on Windows** | Depends on `C:\Users\...\Hermes-Trading\scripts\market_scan.py`, local Python, Alpaca API keys accessible from Windows host. |
| 9 | **Trading Intraday Scan** | `*/30 9-15 * * 1-5` | ❌ **Keep on Windows** | Same as #8. Market hours only — Windows is always on. |
| 10 | **Trading Daily Recap** | `5 16 * * 1-5` | ❌ **Keep on Windows** | Reads trading.db from Windows path. |
| 11 | **Trading Weekly Review** | `0 10 * * 6` | ❌ **Keep on Windows** | Same as #8. |
| 12 | **Trading Active Board Watcher** | every 5 hrs | ❌ **Keep on Windows** | Trading-specific kanban board on Windows. |
| 13 | **Trading Monitor Check** | `*/30 9-16 * * 1-5` | ❌ **Keep on Windows** | Runs `market_watchdog.py` which references `C:\Users\...\Hermes-Trading\`. |
| 14 | **Trading Monthly Review** | `0 10 1 * *` | ❌ **Keep on Windows** | Same as #8. |

**Summary**: 6 of 14 cron jobs can migrate to Railway (colony monitor, GitRadar ×2, kanban watchers ×2, weekly review). 8 must stay on Windows (all wiki + trading jobs).

### 1E. Scripts (8 files)

| Script | Migrate? | Notes |
|--------|----------|-------|
| `wiki-harvester.sh` | ❌ | Windows paths (`/c/Users/...`), `cygpath`, Windows Python. |
| `wiki-daily-briefing.sh` | ❌ | Same Windows dependencies + Obsidian vault. |
| `wiki-search.py` | ❌ | Depends on vault paths. |
| `market_watchdog.py` | ❌ | `sys.path.insert(0, r"C:\Users\...\Hermes-Trading")`, Windows DB paths. |
| `update_workspaces.py` | ❌ | Uses `%USERPROFILE%`, Windows kanban DB path. |
| `comfyui.sh` | ❌ | GPU/ComfyUI — irrelevant on Railway. |
| `screenshot.ps1` | ❌ | PowerShell. |
| `ws` | ⚠️ Check | Tiny script — need to inspect. |

### 1F. Data Stores (Critical for Volume Strategy)

| Data | Size | Migrate? | Volume Strategy |
|------|------|----------|-----------------|
| **state.db** | ~180MB | ✅ Must persist | Railway Volume `/hermes-data/state/` — Core agent state, sessions, checkpoints. |
| **kanban.db** | ~104KB | ✅ Must persist | Same volume `/hermes-data/kanban/` — Kanban board state for watcher cron jobs. |
| **response_store.db** | ~20KB | ✅ Must persist | Same volume `/hermes-data/response-store/`. |
| **watcher-state/** | ~200KB | ❌ Keep on Windows | Wiki harvester polling state — only needed by Windows wiki cron jobs. |
| **kanban-watcher/** | ~1KB | ✅ Must persist | Kanban watcher state JSON. Small enough to include with kanban volume. |
| **hindsight/** | Config only | ✅ Recreated at boot | `config.json` is regenerated from env vars. Hindsight banks use remote Postgres. |
| **BOOT.md** | ~500B | ✅ COPY into image | Simple text file, add to Dockerfile or git repo. |
| **HERMES.md** | ~4KB | ✅ COPY + rewrite | Contains Windows paths and project info. Need Linux-rewrite for Railway context. |
| **SOUL.md** | ~500B | ✅ COPY into image | Currently empty/template. Keep as-is. |
| **.env** | ~24KB | ❌ DO NOT COPY | Secrets → Railway environment variables. |
| **auth.json** | ~2.4KB | ❌ DO NOT COPY | Discord/Telegram auth → Railway env vars. |
| **config.yaml** | ~17KB | ✅ Template | Generate at boot from env vars (already done in start-all.sh). |
| **profile.yaml × 14** | Small | ✅ COPY | Per-profile metadata. Already part of profile dirs. |
| **Profile hindsight dirs** | Varies | ✅ Recreated | Per-profile hindsight configs — regenerated from main config. |
| **models_dev_cache.json** | ~2MB each | ❌ Skip | Runtime cache — rebuilt on demand. Not worth persisting. |
| **skills/.usage.json** | ~8KB | ❌ Skip | Runtime usage stats. |
| **skills/.hub/** | Varies | ❌ Skip | Skill hub cache. |

---

## 2. Dockerfile Modifications

### Current Dockerfile (Base)
```dockerfile
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git openssh-server sudo \
    build-essential libssl-dev libffi-dev python3-dev \
    python3-pip python3-venv net-tools iproute2 jq procps tini \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*
# ... Node, Tailscale, hermes-agent install ...
```

### Recommended Modifications

```dockerfile
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git openssh-server sudo \
    build-essential libssl-dev libffi-dev python3-dev \
    python3-pip python3-venv net-tools iproute2 jq procps tini \
    postgresql-client sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Node.js 24+ (dashboard requirement)
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g hermes-web-ui@latest \
    && rm -rf /var/lib/apt/lists/*

# Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Hermes Agent from GitHub
RUN git clone --depth 1 https://github.com/NousResearch/hermes-agent.git /hermes-agent \
    && python3 -m venv /hermes-venv \
    && /hermes-venv/bin/pip install --no-cache-dir --upgrade pip \
    && /hermes-venv/bin/pip install --no-cache-dir -e /hermes-agent \
    && /hermes-venv/bin/pip install --no-cache-dir hindsight-client>=0.4.22
ENV PATH="/hermes-venv/bin:${PATH}"

# ═══════════════════════════════════════════════════
# CUSTOM WINDOWS HERMES MIGRATION — ADDITIONS BELOW
# ═══════════════════════════════════════════════════

# --- 1. Custom Skills ---
# Option A: COPY from local build context (recommended for initial testing)
COPY skills/ /root/.hermes/skills/

# Option B (future): Clone from private repo
# RUN git clone https://x-access-token:${GH_TOKEN}@github.com/hermes-skills.git /tmp/skills \
#     && cp -r /tmp/skills/* /root/.hermes/skills/ \
#     && rm -rf /tmp/skills

# --- 2. Profiles ---
COPY profiles/ /root/.hermes/profiles/

# --- 3. Hooks ---
COPY hooks/ /root/.hermes/hooks/

# --- 4. Static instruction files ---
COPY BOOT.md.railway /root/.hermes/BOOT.md
COPY HERMES.md.railway /root/.hermes/HERMES.md

# --- 5. Writable directories (ephemeral, recreated each boot) ---
# Persisted data lives on Railway Volume at /hermes-data
RUN mkdir -p /hermes-data/{logs,tailscale,state,kanban,watcher-state} \
    && mkdir -p /hermes-data/profiles

# --- 6. SSH setup ---
RUN mkdir -p /run/sshd \
    && sed -i 's/#PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config

# ═══════════════════════════════════════════════════

COPY docker/start-all.sh /start-all.sh
COPY docker/railway-start.sh /railway-start.sh
COPY docker/health.py /app/health.py
RUN chmod +x /start-all.sh /railway-start.sh /app/health.py

EXPOSE 22 8642 8648 8888

ENTRYPOINT ["tini", "--"]
CMD ["/railway-start.sh"]
```

### Skills Directory Structure for Repo

Create a `skills/` directory in the git repo with custom skills only:

```
hermes-tailscale-rw/
├── skills/
│   ├── the-colony/
│   │   ├── SKILL.md
│   │   ├── scripts/
│   │   │   ├── colony_schemas.py
│   │   │   └── colony-auth.sh
│   │   ├── references/
│   │   └── templates/
│   ├── hermes-cloud-deploy/
│   │   ├── SKILL.md
│   │   ├── references/
│   │   └── templates/
│   └── devops/
│       ├── kanban-orchestrator/
│       ├── kanban-worker/
│       ├── kanban-verification-gate/
│       ├── watchers/
│       │   ├── SKILL.md
│       │   └── scripts/
│       │       ├── watch_rss.py
│       │       ├── watch_github.py
│       │       ├── watch_http_json.py
│       │       └── _watermark.py
│       ├── safety-rewrite/
│       └── webhook-subscriptions/
├── profiles/
│   ├── agy-lane/
│   │   ├── AGENTS.md
│   │   ├── SOUL.md
│   │   └── profile.yaml
│   ├── mimirs-will/
│   │   ├── AGENTS.md
│   │   ├── SOUL.md
│   │   └── profile.yaml
│   └── ... (all except trading)
├── hooks/
│   ├── boot-md/
│   │   ├── HOOK.yaml
│   │   └── handler.py
│   └── end-logger/
│       ├── HOOK.yaml
│       └── handler.py
├── BOOT.md.railway          # Linux-rewrite of BOOT.md
├── HERMES.md.railway        # Linux-rewrite of HERMES.md
└── docker/
    ├── start-all.sh
    └── railway-start.sh     # Enhanced startup with volume symlinks
```

### Critical: Symlink Strategy for Persistent Data

The `railway-start.sh` must create symlinks from ephemeral `/root/.hermes/` to persisted `/hermes-data/` BEFORE the gateway starts:

```bash
#!/usr/bin/env bash
# railway-start.sh — enhanced startup with volume persistence
set -euo pipefail

LOG="/hermes-data/logs"
mkdir -p "$LOG"
log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# ── Symlink persistent data to Railway Volume ────────────
# These files MUST survive container restarts

VOLUME_DIRS=("state.db" "kanban" "watcher-state" "response_store.db")
for d in "${VOLUME_DIRS[@]}"; do
    src="/hermes-data/$d"
    dst="/root/.hermes/$d"
    if [ -e "$src" ] && [ ! -L "$dst" ]; then
        # Migrate existing data to volume on first run
        if [ -e "$dst" ]; then
            log "Migrating $dst → $src"
            cp -a "$dst" "$src" 2>/dev/null || true
            rm -rf "$dst"
        fi
        ln -sf "$src" "$dst"
        log "Symlinked $dst → $src"
    elif [ ! -e "$dst" ]; then
        ln -sf "$src" "$dst"
        log "Symlinked $dst → $src (new)"
    fi
done

# Profile state.dbs
for prof in /root/.hermes/profiles/*/; do
    pname=$(basename "$prof")
    if [ -f "$prof/state.db" ]; then
        vol_path="/hermes-data/profiles/$pname/state.db"
        mkdir -p "$(dirname "$vol_path")"
        if [ ! -e "$vol_path" ]; then
            mv "$prof/state.db" "$vol_path" 2>/dev/null || true
            ln -sf "$vol_path" "$prof/state.db"
            log "Migrated $pname state.db to volume"
        elif [ ! -L "$prof/state.db" ]; then
            # Volume already has data, replace ephemeral
            rm -f "$prof/state.db" "$prof/state.db-shm" "$prof/state.db-wal" 2>/dev/null || true
            ln -sf "$vol_path" "$prof/state.db"
            log "Re-linked $pname state.db to volume"
        fi
    fi
done

# Ensure logs directory
ln -sf /hermes-data/logs /root/.hermes/logs 2>/dev/null || true

# ── Config generation (from env vars) ────────────────────
# [Same as current start-all.sh config generation]
if [ ! -f /root/.hermes/.env ]; then
    log "Creating .env..."
    : > /root/.hermes/.env
    [ -n "${OPENROUTER_API_KEY:-}" ] && echo "OPENROUTER_API_KEY=${OPENROUTER_API_KEY}" >> /root/.hermes/.env
    [ -n "${DATABASE_URL:-}" ] && echo "DATABASE_URL=${DATABASE_URL}" >> /root/.hermes/.env
    [ -n "${COLONY_API_KEY:-}" ] && echo "COLONY_API_KEY=${COLONY_API_KEY}" >> /root/.hermes/.env
    [ -n "${GITHUB_TOKEN:-}" ] && echo "GITHUB_TOKEN=${GITHUB_TOKEN}" >> /root/.hermes/.env
    echo "API_SERVER_ENABLED=true" >> /root/.hermes/.env
    echo "API_SERVER_PORT=8642" >> /root/.hermes/.env
    echo "HINDSIGHT_MODE=local_embedded" >> /root/.hermes/.env
    echo "HINDSIGHT_BANK_ID=${HINDSIGHT_BANK_ID:-hermes-railway}" >> /root/.hermes/.env
    log "Created .env ($(wc -l < /root/.hermes/.env) lines)"
fi

if [ ! -f /root/.hermes/config.yaml ]; then
    log "Creating config.yaml..."
    # [Same config.yaml template as current start-all.sh]
    # ...
fi

# ── Tailscale ────────────────────────────────────────────
# [Same as current start-all.sh]
tailscaled --tun=userspace-networking --state=/hermes-data/tailscale.state &
# ... rest of Tailscale setup ...

# ── SSHD ─────────────────────────────────────────────────
# [Same as current start-all.sh]

# ── Hermes Gateway ───────────────────────────────────────
log "Starting Hermes Gateway..."
export PATH="/hermes-venv/bin:$PATH"
hermes gateway run > "$LOG/gateway.log" 2>&1 &
GW_PID=$!
# ...

wait $GW_PID
```

---

## 3. Railway Volume Strategy

### Volume Configuration

In `railway.json`, configure a persistent volume:

```json
{
  "$schema": "https://railway.com/railway.schema.json",
  "build": {
    "builder": "dockerfile"
  },
  "deploy": {
    "startCommand": "/railway-start.sh",
    "restartPolicyType": "on_failure",
    "restartPolicyMaxRetries": 10,
    "healthcheckPath": "/",
    "healthcheckTimeout": 30
  }
}
```

In Railway dashboard → Volume:
- **Mount path**: `/hermes-data`
- **Size**: 5GB (Hobby) or 50GB (Pro)

### Volume Directory Layout

```
/hermes-data/
├── logs/                    # Gateway, dashboard, health logs
│   ├── gateway.log
│   ├── dashboard.log
│   └── health.log
├── tailscale/               # Tailscale state (survives restarts)
│   └── tailscale.state
├── state/                   # Ephemeral caches (repopulated)
│   └── ...
├── state.db → symlink       # Main agent state (180MB) — CRITICAL
├── kanban/                  # Kanban board databases
│   └── boards/
│       └── hermes-relay/
│           └── kanban.db
├── watcher-state/           # Kanban watcher state
│   └── hermes-relay-state.json
├── response_store.db        # Response store (20KB)
└── profiles/                # Per-profile persisted data
    ├── mimirs-will/
    │   └── state.db
    ├── backend-eng/
    │   └── state.db
    └── ... (other active profiles)
```

### Volume Size Estimates (Hobby 5GB)

| Component | Size |
|-----------|------|
| state.db | ~180MB |
| Profile state.dbs (×8 active) | ~30MB total |
| kanban.db | ~104KB |
| response_store.db | ~20KB |
| Tailscale state | ~1KB |
| Logs (rotated) | ~50MB |
| watcher-state JSONs | ~200KB |
| **Total** | **~260MB** |
| **Headroom** | **~4.7GB** |

Well within Hobby limits.

---

## 4. Cron Job Routing Recommendation

### Jobs that SHOULD run on Railway (6 jobs)

| Job | Railway Schedule | Env Vars Needed |
|-----|-----------------|-----------------|
| **colony-notifications-monitor** | every 12h (unchanged) | `COLONY_API_KEY` |
| **GitRadar Pipeline** | daily at 15:00 UTC | `GITHUB_TOKEN` |
| **GitRadar Recommendations** | daily at 16:00 UTC | (reads file from Pipeline) |
| **hermes-relay Kanban Watcher** | every 5 min (unchanged) | (uses hermes CLI) |
| **hermes-relay Active Board Watcher** | every 5h (unchanged) | (uses hermes CLI + git) |
| **Trading Weekly Review** | Saturday 10:00 (if trading DB accessible) | `ALPACA_*_KEY` — only if trading system also migrates |

**Setup**: These cron jobs reference `C:\Users\...` paths in their prompts. You must:

1. Create **new** cron job prompts that use Linux paths (or no paths at all — just `hermes kanban --board X list`)
2. Strip all Windows path references
3. For GitRadar, either clone the gitradar repo into the container or COPY it into the image
4. Set the required env vars in Railway dashboard

### Jobs that MUST stay on Windows (8 jobs)

| Job | Reason |
|-----|--------|
| **Wiki Daily Briefing** | Depends on `C:\Users\luned\Vault\Encephalon-Mageia\wiki\` (Obsidian vault) |
| **Wiki Harvester** | Same vault dependency + Windows-path scripts |
| **Trading Premarket Scan** | Depends on Windows-hosted trading system + market data APIs |
| **Trading Intraday Scan** | Same + market hours only |
| **Trading Daily Recap** | Same + reads trading.db from Windows path |
| **Trading Weekly Review** | Same |
| **Trading Active Board Watcher** | Depends on Windows kanban board |
| **Trading Monitor Check** | Runs `market_watchdog.py` with Windows paths |

### Recommended Approach: Split-Brain

Rather than trying to make everything work in one place, run **two Hermes instances**:

1. **Railway**: Colony monitoring, GitRadar, kanban watchers, general-purpose agent, dashboard
2. **Windows**: Trading system, wiki/vault management, Windows-specific tools

Communication between them happens naturally through Discord (both deliver to Discord channels).

---

## 5. Prioritized Migration Order

### Phase 1: Foundation (Do First)
1. ✅ Modify `hermes-tailscale-rw/` repo structure to include skills/, profiles/, hooks/ directories
2. ✅ Copy custom skills into repo (`the-colony`, `hermes-cloud-deploy`, `devops/*`, `one-three-one-rule`, etc.)
3. ✅ Copy profile AGENTS.md + SOUL.md + profile.yaml for all non-trading profiles
4. ✅ Copy hooks/ into repo
5. ✅ Create `BOOT.md.railway` (Linux version of BOOT.md)
6. ✅ Create `HERMES.md.railway` (Linux-rewrite)
7. ✅ Add `sqlite3` package to Dockerfile
8. ✅ Create `railway-start.sh` with symlink persistence logic
9. ✅ Update `railway.json` healthcheck
10. Deploy and verify gateway + dashboard come up

### Phase 2: Cron Migration (Do Second)
1. Add `COLONY_API_KEY` to Railway env vars
2. Create new Linux-path cron jobs for the 6 migratable jobs
3. Disable the 6 migrated cron jobs on Windows
4. Test each Railway cron job manually via `hermes cron run`
5. Monitor for 48h

### Phase 3: Cleanup (Do Third)
1. Archive Windows-path references from `cron/jobs.json` (reduce prompt noise)
2. Set up log rotation in `railway-start.sh`
3. Document which jobs run where
4. Optionally: set up Railway Pro (50GB) if state.db grows

### Phase 4: Enhancement (Future)
1. Move skills/ to a private GitHub repo and clone at build time
2. Add gitradar project to container (COPY or clone)
3. Add Telegram/Discord bot tokens to Railway env vars for full messaging
4. Configure Hindsight with Railway Postgres plugin

---

## 6. Portability Audit: Files That Need Path Rewrites

### Files with `C:\Users\luned` or `/c/Users/luned` References

| File | Line Count | Action Required |
|------|-----------|-----------------|
| `jobs.json` (cron prompts) | ~50+ references | Create Linux-equivalent prompts for migrated jobs |
| `HERMES.md` | ~5 references | Rewrite for Linux paths |
| `BOOT.md` | ~2 references | Already have Linux `df -h` |
| `profiles/mimirs-will/AGENTS.md` | ~4 references | Vault git push path (won't be used on Railway) |
| `skills/devops/watchers/scripts/*.py` | Some | Check for Windows-specific imports |
| `skills/the-colony/scripts/colony-auth.sh` | 0 | Already POSIX-compatible |

### Files Already Linux-Compatible

| File | Status |
|------|--------|
| `hooks/boot-md/handler.py` | Uses `pathlib.Path.home()` — portable |
| `hooks/end-logger/handler.py` | Uses `pathlib.Path.home()` — portable |
| `skills/the-colony/SKILL.md` | API reference — no paths |
| `skills/hermes-cloud-deploy/SKILL.md` | Already Railway-focused |
| `skills/the-colony/references/engagement-pitfalls.md` | Text only |
| All profile SOUL.md files | Plain text instructions, no paths |

---

## 7. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| State.db too large for volume | Low | Currently 180MB, Hobby = 5GB |
| Symlink strategy breaks on restart | Medium | Test with `railway redeploy` before going live |
| Cron job prompts still reference Windows paths in jobs.json | Medium | Hermes reads jobs.json at runtime on Railway — the 8 Windows jobs' prompts will error. Disable them after creating new Linux-path versions. |
| Skills containing Windows-only code | Low | Already identified. Exclude windows-* skill dirs. |
| BOOT.md references PowerShell | Low | Rewrite for Linux (df -h) |
| Auth tokens in Railway env vars | Medium | Set all in Railway dashboard, never in repo |
| Two Hermes instances competing for Discord message | Low | Different bot tokens or different delivery channels |
| GitRadar project not in container | Medium | COPY into image or clone from GitHub at build time |

---

## 8. Summary

| Category | Total | Migrate | Stay on Windows |
|----------|-------|---------|-----------------|
| Skills | 34 dirs | 30 (excl. windows-*) | 4 windows-specific |
| Profiles | 14 | 13 (excl. trading) | trading |
| Hooks | 2 | 2 | 0 |
| Cron Jobs | 14 | 6 | 8 (wiki + trading) |
| Scripts | 8 | 0 | 8 (all Windows-path) |
| Data Stores | 6 critical | 4 (state.db, kanban.db, etc.) | 2 (watcher-state, models cache) |

**Bottom line**: The Railway container can become the primary agent host for Colony, GitRadan, kanban watching, and general-purpose tasks. Windows remains the host for trading and wiki/vault operations. This split-brain approach is clean, low-risk, and leverages each platform's strengths.
