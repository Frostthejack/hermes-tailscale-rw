# Railway Migration Plan V2 — Complete Deployment Guide

> **Status**: Active — June 1, 2026
> **Author**: OWL (frostthejack's AI assistant)
> **Goal**: Move ALL Hermes workloads to Railway so Windows can be shut down
> **Based on**: MIGRATION-PLAN.md (May 31) + ALL-IN-ONE-MIGRATION.md (May 31) + hermes-relay app work (Jun 1)

---

## Current State (June 1, 2026)

### What's Running on Windows
| Service | Port | Status |
|---------|------|--------|
| Hermes Gateway (Discord + API) | 8642 | ✅ Running (PID 70068) |
| Hermes-Relay WSS Server | 8767 | ✅ Running (PID 68616) |
| Hindsight API | 8888 | ✅ Running |
| Dashboard (hermes-web-ui) | 8648 | ✅ Running |
| Tailscale | — | ✅ Connected (100.72.73.74) |
| Trading DB | — | ✅ SQLite WAL mode |
| Wiki Vault | — | ✅ Git repo (~5.6MB markdown) |

### What's on Railway
| Service | Status |
|---------|--------|
| Railway Project `hermes-agent` | ✅ Created (Hobby plan) |
| PostgreSQL | ✅ Running (managed plugin) |
| GitHub Repo `Frostthejack/hermes-tailscale-rw` | ✅ Pushed (all Docker assets) |
| Volume `/hermes-data` | ✅ Configured |
| Tailscale | ✅ Connected (reusable auth key, `tailscale set --ssh` done) |
| Hermes Gateway | ⚠️ Deployed but needs config finalization |
| API Server Key | ✅ Set in Railway env vars |
| OpenRouter API Key | ✅ Set in Railway env vars |

### What Was Done Today (June 1) — hermes-relay App
1. Fixed `SensitiveAppDetector.kt` (missing import + type annotation)
2. Built APK, installed on Pixel 6, established `adb reverse` for ports 8642 + 8767
3. Diagnosed Tailscale ACL blocking LAN IP — switched QR to use `127.0.0.1` via `adb reverse`
4. Found API key was missing from QR (not in config files, only in gateway env) — extracted from running process
5. Generated multi-endpoint QR (LAN + Tailscale) with API key using `--mode auto`
6. Successfully paired the app (v3 payload, `hermes:3`, endpoints array)
7. Fixed stale session token conflict (cleared app data)
8. Fixed relay WSS auth failure (`First message must be system/auth`)
9. Updated `hermes-relay-pair` skill for Windows compatibility

---

## Architecture: Target State (Everything on Railway)

```
Railway Project: hermes-agent (Hobby Plan)
│
├── hermes-agent Container (Docker — debian:bookworm-slim + tini)
│   ├── Hermes Gateway (Discord + API server, port 8642)
│   ├── Dashboard (hermes-web-ui, port 8648)
│   ├── Hermes-Relay WSS Server (port 8767) ← NEW: relay server for Android app
│   ├── Tailscale (userspace networking, SSH via `tailscale set --ssh`)
│   ├── Hindsight (local_embedded, port 8888, PG-backed)
│   ├── Cron scheduler (ALL 14+ jobs)
│   │   ├── Colony monitor (every 12h)
│   │   ├── GitRadar pipeline (daily 15:00 UTC)
│   │   ├── GitRadar recommendations (daily 16:00 UTC)
│   │   ├── hermes-relay Kanban Watcher (every 5 min)
│   │   ├── hermes-relay Active Board Watcher (every 5h)
│   │   ├── Trading Premarket Scan (7 AM ET weekdays)
│   │   ├── Trading Intraday Scan (every 30 min, market hours)
│   │   ├── Trading Daily Recap (4:05 PM ET weekdays)
│   │   ├── Trading Weekly Review (Sat 10 AM)
│   │   ├── Trading Monitor (every 30 min, market hours)
│   │   ├── Trading Monthly Review (1st of month)
│   │   ├── Wiki Daily Briefing (2×/day)
│   │   ├── Wiki Harvester (every 30 min)
│   │   └── Wiki Git Sync (every 15 min) ← NEW
│   ├── Custom skills (30+ directories)
│   │   ├── the-colony/
│   │   ├── hermes-cloud-deploy/
│   │   ├── hermes-relay-pair/ ← NEW (for Android app pairing)
│   │   ├── devops/kanban-orchestrator/
│   │   ├── devops/kanban-worker/
│   │   ├── devops/kanban-verification-gate/
│   │   ├── devops/watchers/
│   │   ├── devops/safety-rewrite/
│   │   └── devops/webhook-subscriptions/
│   ├── Custom profiles (13 directories)
│   │   ├── agy-lane/ analyst/ backend-eng/ claude-lane/ frontend-eng/
│   │   ├── mimirs-will/ ops/ orchestrator/ pm/ researcher/
│   │   ├── reviewer/ writer/
│   │   └── trading/ ← includes trading DB symlink
│   ├── Hooks (2)
│   │   ├── boot-md/ (Linux-rewritten BOOT.md)
│   │   └── end-logger/
│   ├── /app/Hermes-Trading/ (cloned from GitHub)
│   │   ├── trading/ (data.py, signals.py, execution.py)
│   │   ├── scripts/ (scan, review, watchdog)
│   │   └── → trading.db symlinked to /hermes-data/trading.db
│   ├── /app/wiki/ (Encephalon-Mageia vault — git clone)
│   │   ├── wiki/ (5.6MB markdown)
│   │   └── .git/ (synced via GITHUB_TOKEN)
│   └── /app/hermes-relay/ ← NEW: relay Android app source
│       └── (reference copy for pairing/QR generation scripts)
│
├── PostgreSQL (Railway managed plugin)
│   ├── Hindsight bank storage (pgvector)
│   └── Hermes agent sessions
│
└── Railway Volume (/hermes-data) — 5GB Hobby
    ├── state.db (agent sessions, ~180MB)
    ├── trading.db (trading data, ~50MB)
    ├── kanban/ (board databases)
    ├── response_store.db (~20KB)
    ├── tailscale.state
    ├── logs/
    ├── profiles/ (per-profile state.dbs)
    └── wiki-state/ (harvester state, dedup cache)
```

---

## What's New in V2 (Changes from V1)

### 1. Hermes-Relay WSS Server on Railway
The relay Android app needs the WSS relay server (port 8767) to be accessible from the phone. Options:

**Option A: Tailscale Serve (Recommended)**
- The phone connects via Tailscale MagicDNS hostname
- `tailscale serve --bg https+insecure://localhost:8767` makes it available on the tailnet
- QR code uses `wss://grayfox-1.tailf479f7.ts.net:443` or similar Tailscale Serve URL
- No public internet exposure — locked to tailnet by ACL
- Requires: `tailscale cert grayfox-1.tailf479f7.ts.net` for HTTPS

**Option B: Tailscale Funnel (Public)**
- `tailscale funnel --bg https+insecure://localhost:8767`
- Available on the public internet via `<hostname>.ts.net`
- Only needed if phone isn't on tailnet

**Option C: Direct Port (Internal Only)**
- `tailscale ip`: use direct 100.x Tailscale IP
- `wss://100.x.x.x:8767/ws` — works only on tailnet

**Current recommendation**: Option A (Tailscale Serve). The phone app already supports multi-endpoint QRs, so we can include both Tailscale and public endpoints.

### 2. API Server Key Must Be in Config
The API key (`API_SERVER_KEY`) is injected from Bitwarden at gateway startup on Windows. On Railway, this must be:
1. Set as a Railway environment variable: `API_SERVER_KEY=<value>`
2. The `generate_config.py` / `railway-start.sh` must write it to the gateway's config so the API server enforces auth
3. The `plugin.pair` QR generator must read this key (currently it reads from `~/.hermes/.env` or `config.yaml`)

### 3. Trading System is Pure Python
Confirmed: `yfinance`, `requests`, `pandas`, `numpy` — all Linux-compatible. Alpaca SDK is pure Python. SQLite WAL works identically on Linux. Zero Windows dependencies beyond file paths.

### 4. Wiki Vault is a Git Repo
`Encephalon-Mageia` is already on GitHub. Clone into container, add git-sync cron job. No Obsidian needed in the cloud.

### 5. Config Generation Must Include `API_SERVER_KEY`
The `generate_config.py` (or equivalent in `railway-start.sh`) currently writes `API_SERVER_ENABLED=true` and `API_SERVER_PORT=8642` but does NOT write `API_SERVER_KEY`. This must be added so the gateway's API server enforces authentication.

---

## Migration Phases V2

### Phase 0: Immediate Fixes (Do Now)
These are blockers for the Railway deployment to work correctly.

1. **Add `API_SERVER_KEY` to `generate_config.py`**
   ```python
   if os.environ.get('API_SERVER_KEY'):
       config['platforms']['api_server']['api_key'] = os.environ['API_SERVER_KEY']
   ```

2. **Add `API_SERVER_KEY` to `railway-start.sh` config generation**
   ```bash
   [ -n "${API_SERVER_KEY:-}" ] && echo "API_SERVER_KEY=${API_SERVER_KEY}" >> /root/.hermes/.env
   ```

3. **Add Hermes-Relay Dockerfile stage**
   The relay WSS server needs to run alongside the gateway. Add to Dockerfile:
   ```dockerfile
   # Hermes-Relay server
   COPY relay_server/ /app/relay_server/
   RUN /hermes-venv/bin/pip install --no-cache-dir -r /app/relay_server/requirements.txt
   ```

4. **Add relay server startup to `railway-start.sh`**
   ```bash
   # Start relay server in background
   python3 -m relay_server --no-ssl --port 8767 > "$LOG/relay.log" 2>&1 &
   RELAY_PID=$!
   log "Relay server: running (PID $RELAY_PID)"
   ```

5. **Push to GitHub and trigger Railway deploy**

### Phase 1: Repo Preparation (1-2 days)

**Skills to COPY into `hermes-tailscale-rw/skills/`:**
- `the-colony/` (complete directory)
- `hermes-cloud-deploy/` (with V2 updates)
- `hermes-relay-pair/` (Windows-fixed version)
- `devops/kanban-orchestrator/`
- `devops/kanban-worker/`
- `devops/kanban-verification-gate/`
- `devops/watchers/`
- `devops/safety-rewrite/`
- `devops/webhook-subscriptions/`

**Profiles to COPY into `hermes-tailscale-rw/profiles/`:**
- All EXCEPT `trading` (trading stays on Windows initially, or migrates in Phase 3)
- Each profile: `AGENTS.md` + `SOUL.md` + `profile.yaml`

**Hooks to COPY:**
- `boot-md/` (with Linux-rewritten `BOOT.md`)
- `end-logger/`

**Static files:**
- `BOOT.md.railway` (Linux version)
- `HERMES.md.railway` (Linux version with Railway-specific project info)

**Scripts to rewrite for Linux:**
- `wiki-harvester.sh` → remove MSYS `cygpath`, use `/app/wiki/` paths
- `wiki-daily-briefing.sh` → same
- `wiki-search.py` → update `WIKI_PATH = Path("/app/wiki/wiki")`
- Create `wiki-git-sync.sh`:
  ```bash
  #!/bin/bash
  cd /app/wiki
  git pull --rebase 2>/dev/null
  git add -A
  git diff --cached --quiet || git commit -m "auto-sync: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  git push 2>/dev/null
  ```

**Dockerfile additions:**
```dockerfile
# Trading system
RUN git clone --depth 1 https://x-access-token:${GITHUB_TOKEN}@github.com/frostthejack/Hermes-Trading.git /app/Hermes-Trading \
    && /hermes-venv/bin/pip install --no-cache-dir -r /app/Hermes-Trading/requirements.txt

ENV TRADING_DB_PATH="/hermes-data/trading.db"
ENV TRADING_KILL_SWITCH="/hermes-data/KILL_SWITCH"

# Wiki vault
ENV WIKI_PATH="/app/wiki"
ENV WIKI_VAULT_REPO="https://x-access-token:${GITHUB_TOKEN}@github.com/frostthejack/Encephalon-Mageia"
```

**Railway Environment Variables (complete list):**
| Variable | Description |
|----------|-------------|
| `OPENROUTER_API_KEY` | OpenRouter API key (already set) |
| `API_SERVER_KEY` | API server auth key (already set) |
| `TS_AUTHKEY` | Tailscale reusable auth key (already set) |
| `TS_HOSTNAME` | Tailscale hostname (e.g. `railway-hermes`) |
| `DATABASE_URL` | PostgreSQL URL (auto-set by Railway) |
| `SSH_PUBLIC_KEY` | Your SSH public key |
| `COLONY_API_KEY` | The Colony API key |
| `GITHUB_TOKEN` | GitHub token (for vault push + GitRadar) |
| `ALPACA_API_KEY` | Alpaca paper trading API key |
| `ALPACA_SECRET_KEY` | Alpaca paper trading secret key |

### Phase 2: Data Migration (1 day)

**Export from Windows → Import to Railway:**

1. **state.db** (agent sessions):
   ```bash
   # On Windows
   cp /c/Users/luned/AppData/Local/hermes/hermes-agent/state.db /hermes-data/state.db
   # Upload to Railway volume via Railway CLI or dashboard
   ```

2. **trading.db**:
   ```bash
   # On Windows
   cp /c/Users/luned/.hermes/profiles/trading/data/trading.db /hermes-data/trading.db
   # Upload to Railway volume
   ```

3. **Kanban databases**:
   ```bash
   cp /c/Users/luned/AppData/Local/hermes/hermes-agent/kanban.db /hermes-data/kanban.db
   ```

4. **Profile state.dbs**:
   ```bash
   for prof in /c/Users/luned/AppData/Local/hermes/hermes-agent/profiles/*/; do
       pname=$(basename "$prof")
       [ -f "$prof/state.db" ] && cp "$prof/state.db" "/hermes-data/profiles/$pname/state.db"
   done
   ```

5. **Tailscale state**: Generate fresh on Railway (don't copy — will get new node identity)

### Phase 3: Cron Job Migration (1-2 days)

**All 14 cron jobs rewritten for Linux:**

| Job | Old Path (Windows) | New Path (Railway) |
|-----|-------------------|-------------------|
| Premarket Scan | `C:\...\Hermes-Trading\scripts\market_scan.py` | `/app/Hermes-Trading/scripts/market_scan.py` |
| Intraday Scan | `C:\...\Hermes-Trading\scripts\intraday_scan.py` | `/app/Hermes-Trading/scripts/intraday_scan.py` |
| Daily Recap | `cd C:\...\Hermes-Trading` | `cd /app/Hermes-Trading` |
| Weekly Review | `C:\...\weekly_report.py` | `/app/Hermes-Trading/scripts/weekly_report.py` |
| Monitor Check | `C:\...\market_watchdog.py` | `/app/Hermes-Trading/scripts/market_watchdog.py` |
| Monthly Review | `C:\...\monthly_review.py` | `/app/Hermes-Trading/scripts/monthly_review.py` |
| Wiki Harvester | `bash /c/Users/.../wiki-harvester.sh` | `bash /app/wiki-harvester.sh` |
| Wiki Briefing | `bash /c/Users/.../wiki-daily-briefing.sh` | `bash /app/wiki-daily-briefing.sh` |
| Wiki Git Sync | ← NEW | `bash /app/wiki-git-sync.sh` (every 15 min) |

**Process:**
1. Delete all 14 Windows cron jobs (`hermes cron rm <id>`)
2. Create 14+ new Railway cron jobs with Linux paths
3. Test each manually: `hermes cron run <job_id>`
4. Monitor Discord delivery for 48-72h

### Phase 4: Validation (3-5 days)

**Verification Checklist:**
- [ ] `curl https://<railway-url>:8648` → Dashboard responds
- [ ] `curl https://<railway-url>:8642/v1/models` → API responds (with key auth)
- [ ] `curl http://localhost:8080/` (via Railway exec) → Health check OK
- [ ] `curl http://localhost:8767/health` (via Railway exec) → Relay server OK
- [ ] `curl http://localhost:8888/health` (via Railway exec) → Hindsight OK
- [ ] `ssh root@<tailscale-ip>` → SSH access works
- [ ] Send message via Discord → Gateway responds
- [ ] Android app pairs via QR → Relay WSS connects
- [ ] Trading scan cron fires → Paper trade executes
- [ ] Wiki git sync fires → Vault commits pushed
- [ ] Volume persistence: restart container → all databases intact
- [ ] Hindsight retain/recall works → Banks functional
- [ ] Railway uptime: 72h without restart

**Extended monitoring (1 week):**
- All cron jobs fire on schedule
- Discord delivery: no lost messages
- Trading system: daily recap fires correctly
- Wiki vault: git sync keeps up with changes
- Memory usage: stays within Hobby limits
- Volume growth: < 1GB/week

### Phase 5: Windows Shutdown 🎉

Once validation passes for 1 week:
1. Verify all Railway services stable
2. Back up Windows one final time
3. ✅ **Shut down Windows** — everything runs on Railway

---

## Hermes-Relay App Specifics for Railway

### QR Code Generation on Railway
The `hermes-relay-pair` skill runs `python -m plugin.pair` on the host. On Railway, this means:
1. SSH into the Railway container: `railway ssh`
2. Navigate to the hermes-relay directory
3. Run: `cd /app/hermes-relay && python3 -m plugin.pair --mode auto --host <tailscale-hostname>`
4. The QR will include the Tailscale hostname as the primary endpoint
5. Scan with Android app

### Multi-Endpoint QR for Phone
The phone app supports v3 QRs with `endpoints` array. Generate with:
- **Tailscale** (priority 0): `wss://<railway-ts-hostname>:443` via Tailscale Serve
- **LAN** (priority 1): Only if phone is on same LAN as a future home relay
- **Public** (priority 2): Only if Tailscale Funnel is enabled

### Pairing Code Flow
1. Operator runs `python3 -m plugin.pair --mode auto --png --host <ts-hostname>` in Railway container
2. QR code generated with Tailscale endpoint + pairing code
3. Phone scans QR → connects to relay WSS via Tailscale
4. Pairing code is pre-registered with the loopback `/pairing/register` endpoint
5. Phone authenticates with relay, gets session token
6. Phone connects to API server using `API_SERVER_KEY` from QR
7. ✅ Full connectivity: chat (8642) + terminal/bridge (8767)

---

## Volume Size Estimate (V2 — All-in-One)

| Component | Size | Notes |
|-----------|------|-------|
| state.db | ~180MB | Agent sessions |
| trading.db | ~50MB | Grows with trades |
| kanban/ | ~200KB | Board databases |
| wiki vault (git) | ~10MB | 5.6MB markdown + history |
| wiki-state/ | ~200KB | Harvester dedup |
| relay pairing codes | ~1KB | Ephemeral |
| tailscale.state | ~1KB | Node identity |
| logs/ | ~50MB | Rotated |
| profiles/ | ~30MB | Per-profile state |
| **Total** | **~320MB** | Within 5GB Hobby ✅ |

---

## Risk Assessment (Updated)

| Risk | Severity | Mitigation |
|------|----------|------------|
| API_SERVER_KEY not written to gateway config on Railway | **HIGH** | Phase 0 fix — add to generate_config.py |
| Relay server port conflict with gateway | Medium | Different ports: gateway 8642, relay 8767 |
| Trading scripts fail on Linux | Low | All pure Python; test in Railway exec first |
| Git auth for vault fails | Medium | Use `GITHUB_TOKEN` in clone URL |
| Cron jobs double-fire during migration | Medium | Disable Windows jobs BEFORE enabling Railway jobs |
| Tailscale Serve cert issues | Medium | Use `tailscale cert` for TLS; `+insecure` fallback |
| Two Hermes instances conflict on Discord | Low | Different bot tokens OR stagger migration |
| Volume data loss | Low | Railway volumes are durable; backup before migration |

---

## Open Questions

1. **Tailscale Serve vs Funnel**: Does the phone connect via tailnet or public internet? Serve (tailnet-only) is more secure.
2. **Trading Alpaca keys**: Need to confirm paper trading keys work from Railway IP (Alpaca may have IP restrictions).
3. **GitHub token scope**: Needs `repo` scope for vault push. Already have this?
4. **Android app flavor**: `googlePlay` or `sideload`? Sideload has full bridge/terminal. GooglePlay lacks Device Control.
5. **Hermes-Relay server**: Should it run as a separate Railway service or in the same container? Same container avoids cross-service networking.

---

## File Checklist for `hermes-tailscale-rw/` Repo

```
hermes-tailscale-rw/
├── Dockerfile                          ← Updated: add trading + wiki + relay clones
├── railway.json                        ← Current: healthcheck + restart policy
├── railway-start.sh                    ← UPDATED: add relay server, API_SERVER_KEY
├── generate_config.py                  ← UPDATED: write API_SERVER_KEY to config
├── health.py                           ← Current: health check endpoint
├── docker/
│   └── (any additional Docker helpers)
├── skills/
│   ├── the-colony/
│   ├── hermes-cloud-deploy/
│   ├── hermes-relay-pair/              ← NEW: Windows-fixed
│   └── devops/
│       ├── kanban-orchestrator/
│       ├── kanban-worker/
│       ├── kanban-verification-gate/
│       ├── watchers/
│       ├── safety-rewrite/
│       └── webhook-subscriptions/
├── profiles/
│   ├── agy-lane/ AGENTS.md SOUL.md
│   ├── analyst/ AGENTS.md SOUL.md
│   ├── backend-eng/ AGENTS.md SOUL.md
│   ├── claude-lane/ AGENTS.md SOUL.md
│   ├── frontend-eng/ AGENTS.md SOUL.md
│   ├── mimirs-will/ AGENTS.md SOUL.md
│   ├── ops/ AGENTS.md SOUL.md
│   ├── orchestrator/ AGENTS.md SOUL.md
│   ├── pm/ AGENTS.md SOUL.md
│   ├── researcher/ AGENTS.md SOUL.md
│   ├── reviewer/ AGENTS.md SOUL.md
│   └── writer/ AGENTS.md SOUL.md
├── hooks/
│   ├── boot-md/ HOOK.yaml handler.py BOOT.md
│   └── end-logger/ HOOK.yaml handler.py
├── BOOT.md.railway                     ← Linux-rewritten
├── HERMES.md.railway                   ← Linux-rewritten
├── scripts/
│   ├── wiki-harvester.sh               ← Linux-rewritten
│   ├── wiki-daily-briefing.sh          ← Linux-rewritten
│   ├── wiki-git-sync.sh                ← NEW
│   └── wiki-search.py                  ← Path updated
└── docs/
    ├── RAILWAY-WIKI.md                 ← Current deployment guide
    ├── MIGRATION-PLAN.md               ← V1 migration plan
    ├── ALL-IN-ONE-MIGRATION.md         ← V1 all-in-one plan
    └── RAILWAY-MIGRATION-PLAN-V2.md    ← THIS FILE
```

---

*Josh, the path is clear. Phase 0 (adding API_SERVER_KEY to config) is the immediate blocker. Once that's done and the relay server is in the Dockerfile, we can do a test deploy and iterate. The hermes-relay Android app is working with the Windows relay — the next step is getting the same relay server running on Railway and accessible via Tailscale.*
