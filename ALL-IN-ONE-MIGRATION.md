# ALL-IN-ONE RAILWAY MIGRATION —Shut Down Windows Forever
> **Goal**: Move EVERYTHING to Railway so Josh can shut down his Windows machine
> **Date**: May 31, 2026 | **Status**: Research Complete → Ready to Plan

---

## What Was Blocking Full Migration (And How to Fix It)

My initial research recommended "split-brain" because I assumed the trading system and wiki were deeply Windows-dependent. Deeper analysis shows **everything is actually portable** — the blockers are fixable:

### Blockers & Solutions

| Component | Blocker | Solution |
|-----------|---------|----------|
| **Trading scripts** | `sys.path.insert(0, r"C:\Users\...\Hermes-Trading")` | Clone the trading repo into the container. Pure Python + SQLite. |
| **Trading DB** | DB at `C:\Users\luned/.../trading.db` | WAL-mode SQLite → Railway Volume. Portable binary format. |
| **Alpaca API** | None. Alpaca SDK is pure Python, cross-platform | Just work from anywhere with API keys. |
| **Wiki vault** | `/c/Users/luned/Vault/Encephalon-Mageia/wiki/` | The vault is a **regular git repo**. Clone it into container. |
| **Obsidian** | `.obsidian/` config dir | Don't need Obsidian in the container. The wiki is plain Markdown files — just `git pull/push`. |
| **Wiki scripts** | MSYS `cygpath` calls, Windows Python paths | Rewrite for Linux bash + Python3. Core logic is portable. |
| **Wiki search** | References `/mnt/c/...` (WSL paths) | Already has Linux path support! (`Path("/mnt/c/Users/...")`). |
| **Cron prompts** | Windows paths in cron job text | Rewrite prompts with Linux paths. |

---

## Architecture: Everything on Railway

```
Railway Project: hermes-agent
│
├── hermes-agent Container (Docker)
│   ├── Hermes Gateway (Discord + API)
│   ├── Dashboard (hermes-web-ui, port 8648)
│   ├── Tailscale (userspace, SSH)
│   ├── Hindsight API (local_embedded, port 8888)
│   ├── Cron scheduler (ALL 14 jobs)
│   │   ├── Colony monitor (every 12h)
│   │   ├── GitRadar pipeline (daily)
│   │   ├── GitRadar recommendations (daily)
│   │   ├── Kanban watchers (5 min / 5h)
│   │   ├── Trading premarket scan (7 AM ET weekdays)
│   │   ├── Trading intraday scan (every 30 min, market hours)
│   │   ├── Trading daily recop (4:05 PM ET weekdays)
│   │   ├── Trading weekly review (Sat 10 AM)
│   │   ├── Trading monitor (every 30 min, market hours)
│   │   ├── Trading monthly review (1st of month)
│   │   ├── Wiki daily briefing (2×/day)
│   │   └── Wiki harvester (every 30 min)
│   ├── Custom skills + profiles + hooks
│   ├── /app/Hermes-Trading/ (cloned repo — pure Python)
│   │   ├── trading/ (package: data.py, signals.py, etc.)
│   │   ├── scripts/ (scan, review, watchdog)
│   │   └── trading.db (SQLite — symlinked to volume)
│   └── /app/wiki/ (Encephalon-Mageia vault — git clone)
│       ├── wiki/ (5.6MB markdown files)
│       └── .git/ (synced via git mail)
│
├── PostgreSQL (Railway managed plugin)
│   └── Hindsight bank storage (pgvector)
│
└── Railway Volume (/hermes-data)
    ├── state.db (agent sessions)
    ├── trading.db (trading data)
    ├── kanban/ (boards)
    ├── watcher-state/ (harvester state, dedup, etc.)
    ├── tailscale.state
    ├── logs/
    └── profiles/
```

---

## Trading System on Railway — Details

### Why It Works
- **Dependencies**: `yfinance`, `requests`, `pandas`, `numpy` — all pure Python, available on Linux
- **Alpaca SDK**: Pure Python, rate-limited to 0.3s between requests
- **Database**: SQLite (WAL mode) — same binary format on Linux/Windows
- **No ONNX/ML**: It's rule-based signal detection (yinance + pandas), no Windows ML libraries
- **Kill switch**: Just a file touch → works on any OS

### What Needs to Happen
1. Clone `Hermes-Trading` repo into the container: `git clone ... /app/Hermes-Trading`
2. Install dependencies: `pip install -r requirements.txt`
3. Symlink `trading.db` to `/hermes-data/trading.db`
4. Rewrite cron prompts:
   - `sys.path.insert(0, "/app/Hermes-Trading")` instead of Windows path
   - DB path: `/hermes-data/trading.db` instead of `C:\Users\...`
   - Kill switch: `/hermes-data/KILL_SWITCH` instead of `C:\Users\...`
5. Set Railway env vars: `ALPACA_API_KEY`, `ALPACA_SECRET_KEY`

### No Code Changes Needed
The actual Python scripts are OS-agnostic. The only Windows-specific stuff is:
- `sys.path.insert` line → fix path
- `DB_PATH = r"C:\Users\..."` → change to env var or Linux path
- `KILL_SWITCH` file path → change to Linux path

---

## Wiki System on Railway — Details

### Why It Works
- **Vault is a git repo**: `https://github.com/Frostthejack/Encephalon-Mageia`
- **Content**: 5.6MB of plain Markdown + YAML sources
- **Git push/pull**: Works from anywhere — no Obsidian needed in container
- **Wiki search script**: Already has Linux path handling (`Path("/mnt/c/Users/...")`)
- **Sources file**: `sources.yaml` — portable YAML, no OS dependencies

### What Needs to Happen
1. Clone the vault: `git clone https://github.com/Frostthejack/Encephalon-Mageia /app/wiki`
2. Rewrite wiki-harvester.sh: Remove MSYS `cygpath` calls, use Linux paths
3. Rewrite wiki-daily-briefing.sh: Same — Linux bash + Python3
4. Update wiki-search.py config: `WIKI_PATH = Path("/app/wiki/wiki")`
5. Set Railway env vars: `GITHUB_TOKEN` (for vault git push/pull)
6. Add a git-sync cron job: `cd /app/wiki && git pull && git push` every 15 min

---

## Unified Dockerfile

```dockerfile
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1

# ── System deps ──
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git openssh-server sudo \
    build-essential libssl-dev libffi-dev python3-dev \
    python3-pip python3-venv net-tools iproute2 jq procps tini \
    postgresql-client sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# ── Node.js 24+ ──
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g hermes-web-ui@latest \
    && rm -rf /var/lib/apt/lists/*

# ── Tailscale ──
RUN curl -fsSL https://tailscale.com/install.sh | sh

# ── Hermes Agent ──
RUN git clone --depth 1 https://github.com/NousResearch/hermes-agent.git /hermes-agent \
    && python3 -m venv /hermes-venv \
    && /hermes-venv/bin/pip install --no-cache-dir --upgrade pip \
    && /hermes-venv/bin/pip install --no-cache-dir -e /hermes-agent \
    && /hermes-venv/bin/pip install --no-cache-dir hindsight-client>=0.4.22
ENV PATH="/hermes-venv/bin:${PATH}"

# ── Trading System ──
RUN git clone --depth 1 https://github.com/frostthejack/Hermes-Trading.git /app/Hermes-Trading \
    && /hermes-venv/bin/pip install --no-cache-dir -r /app/Hermes-Trading/requirements.txt
ENV TRADING_DB_PATH="/hermes-data/trading.db"
ENV TRADING_KILL_SWITCH="/hermes-data/KILL_SWITCH"

# ── Wiki Vault ──
# Vault cloned at boot if not on volume (first run) or pulled if on volume
ENV WIKI_PATH="/app/wiki"
ENV WIKI_VAULT_REPO="https://github.com/Frostthejack/Encephalon-Mageia"

# ── SSH ──
RUN mkdir -p /run/sshd \
    && sed -i 's/#PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config

# ── Volume dirs ──
RUN mkdir -p /hermes-data/{logs,kanban,watcher-state,tailscale,profiles,wiki-state}

# ── Custom assets ──
COPY skills/ /root/.hermes/skills/
COPY profiles/ /root/.hermes/profiles/
COPY hooks/ /root/.hermes/hooks/
COPY BOOT.md.railway /root/.hermes/BOOT.md
COPY HERMES.md.railway /root/.hermes/HERMES.md

# ── Start scripts ──
COPY docker/railway-start.sh /railway-start.sh
COPY docker/health.py /app/health.py
COPY docker/generate_config.py /app/generate_config.py
COPY docker/wiki-harvester.sh /app/wiki-harvester.sh
COPY docker/wiki-daily-briefing.sh /app/wiki-daily-briefing.sh
COPY docker/wiki-git-sync.sh /app/wiki-git-sync.sh
COPY docker/wiki-search.py /app/scripts/wiki-search.py
RUN chmod +x /railway-start.sh /app/health.py /app/wiki-harvester.sh \
    /app/wiki-daily-briefing.sh /app/wiki-git-sync.sh

EXPOSE 22 8642 8648 8888

ENTRYPOINT ["tini", "--"]
CMD ["/railway-start.sh"]
```

---

## Railway Environment Variables (Expanded)

| Variable | Description | Required For |
|----------|-------------|--------------|
| `OPENROUTER_API_KEY` | OpenRouter API key | Core |
| `TS_AUTHKEY` | Tailscale reusable auth key | SSH/VPN |
| `TS_HOSTNAME` | Hostname (e.g. `railway-hermes`) | Tailscale |
| `DATABASE_URL` | PostgreSQL connection string | Hindsight |
| `SSH_PUBLIC_KEY` | Your SSH public key | SSHD |
| `COLONY_API_KEY` | The Colony API key | Colony monitor |
| `GITHUB_TOKEN` | GitHub token | GitRadar + wiki git push |
| `ALPACA_API_KEY` | Alpaca paper trading API key | Trading |
| `ALPACA_SECRET_KEY` | Alpaca paper trading secret key | Trading |

---

## Railway Start Script (Full Version)

```bash
#!/usr/bin/env bash
set -euo pipefail
LOG="/hermes-data/logs"
mkdir -p "$LOG"
log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# ── 1. Symlink persistent data ──────────────────────────────
symlink_persist() {
    local src="/hermes-data/$1" dst="/root/.hermes/$1"
    if [ -e "$src" ] && [ ! -L "$dst" ]; then
        [ -e "$dst" ] && cp -a "$dst" "$src" 2>/dev/null && rm -rf "$dst"
        ln -sf "$src" "$dst"
    elif [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
        ln -sf "$src" "$dst"
    fi
}
symlink_persist "state.db"
symlink_persist "response_store.db"

# Trading DB
if [ -f "/hermes-data/trading.db" ] && [ ! -L "/app/Hermes-Trading/trading.db" ]; then
    [ -f "/app/Hermes-Trading/trading.db" ] && mv /app/Hermes-Trading/trading.db /hermes-data/trading.db
    ln -sf /hermes-data/trading.db /app/Hermes-Trading/trading.db
fi
if [ ! -L "/app/Hermes-Trading/trading.db" ]; then
    ln -sf /hermes-data/trading.db /app/Hermes-Trading/trading.db
fi

# Profile state.dbs
for prof in /root/.hermes/profiles/*/; do
    pname=$(basename "$prof")
    [ -f "$prof/state.db" ] || continue
    mkdir -p "/hermes-data/profiles/$pname"
    vol="/hermes-data/profiles/$pname/state.db"
    if [ ! -e "$vol" ]; then
        mv "$prof/state.db" "$vol" 2>/dev/null || true
    elif [ ! -L "$prof/state.db" ]; then
        rm -f "$prof/state.db" "$prof/state.db-shm" "$prof/state.db-wal" 2>/dev/null || true
    fi
    ln -sf "$vol" "$prof/state.db"
done

# Wiki state
mkdir -p /hermes-data/wiki-state
ln -sf /hermes-data/wiki-state /root/.hermes/wiki-state 2>/dev/null || true

# Logs
ln -sf /hermes-data/logs /root/.hermes/logs 2>/dev/null || true

# ── 2. Clone/pull wiki vault ────────────────────────────────
if [ ! -d "$WIKI_PATH/.git" ]; then
    log "Cloning wiki vault..."
    git clone "$WIKI_VAULT_REPO" "$WIKI_PATH" 2>&1 | tail -3
    log "Wiki vault cloned"
else
    log "Pulling wiki vault updates..."
    git -C "$WIKI_PATH" pull --rebase 2>&1 | tail -3 || true
fi
# Update wiki-search.py vault path
sed -i "s|WIKI_PATH = Path.*|WIKI_PATH = Path(\"$WIKI_PATH/wiki\")|" /app/scripts/wiki-search.py 2>/dev/null || true

# ── 3. Config generation ────────────────────────────────────
python3 /app/generate_config.py

# ── 4. Tailscale ────────────────────────────────────────────
log "Starting Tailscale..."
tailscaled --tun=userspace-networking --state=/hermes-data/tailscale.state &
for i in $(seq 1 20); do
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 1
done
[ -S /var/run/tailscale/tailscaled.sock ] || { log "FATAL: tailscaled failed"; exit 1; }

TS_HOST="${TS_HOSTNAME:-hermes-$(openssl rand -hex 4)}"
tailscale up --authkey="$TS_AUTHKEY" --hostname="$TS_HOST" --accept-routes 2>&1 | tail -3
sleep 3
tailscale set --ssh 2>&1 | tail -3
sleep 2
TS_IP=$(tailscale ip -4 2>/dev/null || echo "pending")
log "Tailscale: $TS_IP"

# ── 5. SSHD ─────────────────────────────────────────────────
mkdir -p /root/.ssh && chmod 700 /root/.ssh
[ -n "${SSH_PUBLIC_KEY:-}" ] && echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
/usr/sbin/sshd &

# ── 6. Hermes Gateway ──────────────────────────────────────
log "Starting Hermes Gateway..."
export PATH="/hermes-venv/bin:$PATH"
hermes gateway run > "$LOG/gateway.log" 2>&1 &
GW_PID=$!
for i in seq 1 60; do sleep 2; kill -0 $GW_PID 2>/dev/null || { log "Gateway died"; exit 1; }; done
log "Gateway: running"

# ── 7. Dashboard + Health ───────────────────────────────────
hermes-web-ui start --port 8648 > "$LOG/dashboard.log" 2>&1 &
python3 /app/health.py &
log "LIVE — Tailscale: $TS_IP | Dashboard:8648 | API:8642 | All systems go"
wait $GW_PID
```

---

## Cron Job Rewrite Map

| Job | Windows Prompt Path | Railway Prompt Path |
|-----|--------------------|--------------------|
| Premarket Scan | `C:\Users\...\Hermes-Trading\scripts\market_scan.py` | `python3 /app/Hermes-Trading/scripts/market_scan.py` |
| Intraday Scan | `C:\Users\...\Hermes-Trading\scripts\intraday_scan.py` | `python3 /app/Hermes-Trading/scripts/intraday_scan.py` |
| Daily Recap | `cd C:\Users\...\Hermes-Trading` | `cd /app/Hermes-Trading` |
| Weekly Review | `C:\Users\...\Hermes-Trading\scripts\weekly_report.py` | `python3 /app/Hermes-Trading/scripts/weekly_report.py` |
| Monitor Check | `C:\Users\...\market_watchdog.py` | `python3 /app/Hermes-Trading/scripts/watcher_health_check.py` (adapted) |
| Monthly Review | `C:\Users\...\Hermes-Trading\scripts\monthly_review.py` | `python3 /app/Hermes-Trading/scripts/monthly_review.py` |
| Wiki Harvester | `bash /c/Users/.../wiki-harvester.sh` | `bash /app/wiki-harvester.sh` (Linux rewrite) |
| Wiki Briefing | `bash /c/Users/.../wiki-daily-briefing.sh` | `bash /app/wiki-daily-briefing.sh` (Linux rewrite) |

---

## Migration Phases (All-in-One)

### Phase 1: Repo Preparation (1-2 days)
1. Create `Hermes-Trading` GitHub repo (if not already) with scripts + trading package
2. Ensure `Encephalon-Mageia` vault repo is up to date on GitHub
3. Copy custom skills into `hermes-tailscale-rw/skills/`
4. Copy custom profiles into `hermes-tailscale-rw/profiles/` (all except trading)
5. Rewrite `wiki-harvester.sh` and `wiki-daily-briefing.sh` for Linux
6. Create `.railway/BOOT.md` and `HERMES.md` (Linux rewrites)
7. Add `ALPACA_API_KEY` + `ALPACA_SECRET_KEY` to Railway env vars
8. Add `GITHUB_TOKEN` to Railway env vars (for vault push + GitRadar)

### Phase 2: Dockerfile + Start Script (1 day)
1. Update Dockerfile with trading/wiki clones
2. Create new `railway-start.sh` with all symlinks
3. Create `wiki-git-sync.sh` for periodic vault sync
4. Push to GitHub, trigger Railway deploy
5. Debug and fix any startup issues

### Phase 3: Cron Migration (1-2 days)
1. Delete all 14 Windows cron jobs
2. Create 14 new Railway cron jobs with Linux paths
3. Test each one manually via `hermes cron run`
4. Monitor for 48-72h

### Phase 4: Hindsight Migration (1 day)
1. Export Hindsight banks from Windows
2. Import into Railway PG
3. Verify banks are functional
4. Set `auto_retain: true` for continuous accumulation

### Phase 5: Validation (Ongoing)
1. Run full verification checklist (extended)
2. Monitor cron job delivery to Discord for 1 week
3. Verify trading paper trades execute correctly
4. Verify wiki vault git sync works (push/pull)
5. ✅ **Windows machine: SHUTDOWN** 🖥️➡️😴

---

## Volume Size Estimate (All-in-One)

| Component | Size |
|-----------|------|
| state.db | ~180MB |
| trading.db | ~50MB (grows over time) |
| kanban DBs | ~200KB |
| wiki vault (git) | ~10MB (5.6MB markdown + git history) |
| watcher-state | ~200KB |
| logs | ~50MB |
| profile states | ~30MB |
| **Total** | **~320MB** |
| **Hobby Plan Headroom** | **~4.7GB** ✅ |

---

## Risk Assessment

| Risk | Mitigation |
|------|------------|
| Trading scripts fail on Linux | Test in Railway container via `railway run sh`, pure Python deps |
| Git auth for vault fails | Use `GITHUB_TOKEN` in git URL: `https://x-access-token:${GH_TOKEN}@github.com/...` |
| Cron jobs time-shift | Ensure Railway container timezone matches ET (or use UTC in scripts) |
| Alpaca API keys exposed | Railway env vars only, never in code |
| Windows data left behind | Migration copies data to volume; old Windows data becomes backup |

---

*Josh, this is absolutely achievable. The trading system is pure Python with zero Windows dependencies beyond file paths. The wiki is a git repo that can be cloned anywhere. Nothing in your setup requires Windows to be running 24/7.*
