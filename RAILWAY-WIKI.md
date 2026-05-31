# Hermes on Railway — Complete Deployment & Migration Guide

> **Status**: Research Complete — May 31, 2026
> **Author**: OWL (frostthejack's AI assistant)
> **Target**: Deploy full Hermes Agent stack on Railway with Tailscale, PostgreSQL, Hindsight, and persistent customizations

---

## 1. Architecture Overview

```
Railway Project: hermes-agent
├── Hermes Agent Container (Docker — debian:bookworm-slim)
│   ├── Tailscale (userspace networking, sidecar)
│   ├── SSH server (Tailnet SSH via tailscale set --ssh)
│   ├── Hermes Gateway (Discord/API server)
│   ├── hermes-web-ui Dashboard (port 8648)
│   ├── Hindsight API (local_embedded, port 8888)
│   ├── Cron scheduler (cron jobs)
│   ├── Custom skills (38+ skill directories)
│   ├── Custom profiles (13 profile dirs)
│   └── Hooks (boot-md, end-logger)
├── PostgreSQL (Railway managed plugin)
│   ├── Hindsight bank storage (primary)
│   └── Vector embeddings (pgvector extension)
└── Volume Mount (/hermes-data)
    ├── state.db (agent sessions, ~180MB)
    ├── kanban/ (kanban boards)
    ├── tailscale.state (Tailscale identity)
    ├── logs/ (rotated logs)
    └── profiles/ (per-profile state)
```

---

## 2. Critical Railway Platform Knowledge (Updated May 2026)

### 2.1 Healthchecks

- Railway healthchecks poll your `/health` endpoint until HTTP 200.
- **Default timeout**: 300 seconds (5 minutes). Configurable via `RAILWAY_HEALTHCHECK_TIMEOUT_SEC`.
- Railway injects a `PORT` env var — your app MUST listen on this port for healthchecks to work.
- After healthcheck passes, Railway does **NOT** continuously monitor (use Uptime Kuma for that).
- **Volume caveat**: Services with attached volumes get brief downtime on redeploy (no zero-downtime with volumes).

### 2.2 Volumes

| Plan | Size | Max Volumes |
|------|------|-------------|
| Free/Trial | 0.5–3GB | 1–3 |
| Hobby | 5GB | 10 |
| Pro | 50GB | 20+ |

- **One volume per service** (cannot mount multiple volumes to same service).
- No replicas with volumes.
- Live resize supported (Pro). Offline resize for data integrity.
- Docker images running as non-root need `RAILWAY_RUN_UID=0` for volume access.
- Our estimated need: ~260MB total → **Hobby 5GB is sufficient**.

### 2.3 PostgreSQL

- Railway provides PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE, and DATABASE_URL automatically.
- Connect via TCP Proxy for external access (billed for egress).
- Extensions: Use `ALTER SYSTEM` for config changes. pgvector is available via template templates.
- Official PG docs for `ALTER SYSTEM` tuning: shared_buffers, work_mem, etc.

### 2.4 Railway Agent (AI Assistant)

- Built into Railway dashboard. Can create services, set variables, diagnose failed deployments.
- Can auto-open PRs against your repo with fixes.
- **Pricing**: billed at Anthropic's per-token rates, no markup.
- Useful for: "Hey Railway, why did my deployment fail?"

### 2.5 File Management

- `railway volume browse` and `railway volume files` let you manage volume contents from CLI.
- Volume data persists across deploys but is NOT backed up automatically (enable Railway backups).

---

## 3. Docker & Dockerfile Design

### 3.1 Base Dockerfile (Current — Working)

The existing Dockerfile at `hermes-tailscale-rw/` is solid:

```dockerfile
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg git openssh-server sudo \
    build-essential libssl-dev libffi-dev python3-dev \
    python3-pip python3-venv net-tools iproute2 jq procps tini \
    postgresql-client sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# Node.js 24+ (hermes-web-ui requires Node 23+)
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g hermes-web-ui@latest \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://tailscale.com/install.sh | sh

# Hermes Agent from GitHub
RUN git clone --depth 1 https://github.com/NousResearch/hermes-agent.git /hermes-agent \
    && python3 -m venv /hermes-venv \
    && /hermes-venv/bin/pip install --no-cache-dir --upgrade pip \
    && /hermes-venv/bin/pip install --no-cache-dir -e /hermes-agent \
    && /hermes-venv/bin/pip install --no-cache-dir hindsight-client>=0.4.22
ENV PATH="/hermes-venv/bin:${PATH}"

# SSH
RUN mkdir -p /run/sshd \
    && sed -i 's/#PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config \
    && sed -i 's/#PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config

# Volume directories
RUN mkdir -p /hermes-data/{logs,kanban,watcher-state,tailscale,profiles}

# Asset COPY directives (new — for migration)
COPY skills/ /root/.hermes/skills/
COPY profiles/ /root/.hermes/profiles/
COPY hooks/ /root/.hermes/hooks/
COPY BOOT.md.railway /root/.hermes/BOOT.md
COPY HERMES.md.railway /root/.hermes/HERMES.md

COPY docker/start-all.sh /start-all.sh
COPY docker/railway-start.sh /railway-start.sh
COPY docker/health.py /app/health.py
RUN chmod +x /start-all.sh /railway-start.sh /app/health.py

EXPOSE 22 8642 8648 8888

ENTRYPOINT ["tini", "--"]
CMD ["/railway-start.sh"]
```

### 3.2 Railway Configuration (railway.json)

```json
{
  "$schema": "https://railway.com/railway.schema.json",
  "build": {
    "builder": "dockerfile"
  },
  "deploy": {
    "startCommand": "/railway-start.sh",
    "healthcheckPath": "/",
    "healthcheckTimeout": 120,
    "restartPolicyType": "on_failure",
    "restartPolicyMaxRetries": 10
  }
}
```

### 3.3 Volume Configuration

In Railway dashboard → Service → Settings → Volume:
- **Mount path**: `/hermes-data`
- **Size**: 5GB (Hobby) or 50GB (Pro)

---

## 4. Start Script (railway-start.sh) — Key Component

This is the most critical file. It must:

1. **Create symlinks** from ephemeral `/root/.hermes/` → persistent `/hermes-data/` before Hermes starts
2. **Generate config.yaml and .env** from Railway-injected environment variables
3. **Start Tailscale** (userspace networking), enable Tailnet SSH
4. **Start SSHD**, Hermes Gateway, Dashboard, Health check

```bash
#!/usr/bin/env bash
set -euo pipefail
LOG="/hermes-data/logs"
mkdir -p "$LOG"
log() { echo "[$(date -u +%H:%M:%S)] $*"; }

# ── 1. Symlink persistent data ────────────────────────────
# Migrate existing data to volume on first run, then symlink back
symlink_persist() {
    local src="/hermes-data/$1" dst="/root/.hermes/$1"
    if [ -e "$src" ] && [ ! -L "$dst" ]; then
        [ -e "$dst" ] && cp -a "$dst" "$src" 2>/dev/null && rm -rf "$dst"
        ln -sf "$src" "$dst"
        log "Symlinked $dst → $src"
    elif [ ! -e "$dst" ] && [ ! -L "$dst" ]; then
        ln -sf "$src" "$dst"
        log "Symlinked $dst → $src (new)"
    fi
}

symlink_persist "state.db"
symlink_persist "response_store.db"

# Profile state.dbs
for prof in /root/.hermes/profiles/*/; do
    pname=$(basename "$prof")
    [ -f "$prof/state.db" ] || continue
    mkdir -p "/hermes-data/profiles/$pname"
    vol="/hermes-data/profiles/$pname/state.db"
    if [ ! -e "$vol" ]; then
        mv "$prof/state.db" "$vol"
        log "Migrated $pname state.db"
    elif [ ! -L "$prof/state.db" ]; then
        rm -f "$prof/state.db" "$prof/state.db-shm" "$prof/state.db-wal" 2>/dev/null
    fi
    ln -sf "$vol" "$prof/state.db"
done

# Logs symlink
ln -sf /hermes-data/logs /root/.hermes/logs 2>/dev/null || true

# ── 2. Config generation (Python — NO shell heredocs) ─────
python3 /app/generate_config.py

# ── 3. Tailscale ──────────────────────────────────────────
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

# ── 4. SSHD ───────────────────────────────────────────────
mkdir -p /root/.ssh && chmod 700 /root/.ssh
[ -n "${SSH_PUBLIC_KEY:-}" ] && echo "$SSH_PUBLIC_KEY" > /root/.ssh/authorized_keys
/usr/sbin/sshd -D &

# ── 5. Hermes Gateway ────────────────────────────────────
log "Starting Hermes Gateway..."
export PATH="/hermes-venv/bin:$PATH"
hermes gateway run > "$LOG/gateway.log" 2>&1 &
GW_PID=$!
# Wait for gateway to be ready
for i in $(seq 1 60); do
    sleep 2
    kill -0 $GW_PID 2>/dev/null || { log "Gateway died"; exit 1; }
done
log "Gateway: running"

# ── 6. Dashboard ──────────────────────────────────────────
hermes-web-ui start --port 8648 > "$LOG/dashboard.log" 2>&1 &
sleep 3
log "Dashboard: port 8648"

# ── 7. Health check endpoint (Railway requirement) ───────
python3 /app/health.py &
log "Health check: port 8080"

log "LIVE — Tailscale: $TS_IP | Dashboard:8648 | API:8642"
wait $GW_PID
```

### 4.1 Why Python for Config Generation?

**CRITICAL RAILWAY GOTCHA**: Shell heredocs (`cat <<EOF`) silently corrupt API keys containing `$`, `{`, `}` characters:
```
# WRONG — causes 'bad substitution' crash loop
cat > /root/.hermes/.env << EOF
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}   # $ chars get eaten by shell
EOF
```

Always use Python `open().write()` for config files with secrets.

---

## 5. Railway Environment Variables

Set these in Railway dashboard (Variables tab), NEVER in repo:

| Variable | Description | Source |
|----------|-------------|--------|
| `OPENROUTER_API_KEY` | OpenRouter API key | Bitwarden |
| `HERMES_MODEL` | Model string (e.g. `@preset/hermes`) | Optional |
| `TS_AUTHKEY` | Tailscale **reusable** ephemeral auth key | Bitwarden |
| `TS_HOSTNAME` | Hostname for this node | Optional |
| `DATABASE_URL` | PostgreSQL connection string | Railway Postgres reference |
| `SSH_PUBLIC_KEY` | Your SSH public key for SSHD access | Your key |
| `COLONY_API_KEY` | The Colony API key | Bitwarden |
| `GITHUB_TOKEN` | GitHub token for GitRadar | Bitwarden |
| `API_SERVER_KEY` | API server authentication key | Optional |
| `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` | Healthcheck timeout (default 300) | Optional, set to 120 |

---

## 6. Hindsight Migration

### 6.1 Current State (Windows)

- **Mode**: `local_external` — connects to Hindsight API at `http://localhost:8888`
- **12 banks**: hermes, backend-eng, frontend-eng, ops, reviewer, researcher, writer, analyst, pm, claude_code, ci-reviewer, mimir-well
- **Data**: ~3,896 entities, ~182 documents, ~877 chunks in PostgreSQL (Hindsight API's internal PG)
- **API process**: Running as a Windows executable at port 8888

### 6.2 Target State (Railway)

- **Mode**: `local_embedded` — Hindsight runs inside the Hermes process
- **Storage**: Railway managed PostgreSQL via `DATABASE_URL`
- **Banks**: Same 12 banks + `hermes-railway` for the Railway instance

### 6.3 Migration Procedure

Since Hindsight on Windows uses an embedded PostgreSQL (not a standard PG service), migration requires exporting data through the Hindsight API:

```bash
# Step 1: List all banks and their document counts
curl -s http://localhost:8888/banks | python3 -m json.tool

# Step 2: Export each bank's data
curl -s http://localhost:8888/banks/hermes/export > hermes_bank_export.json

# Step 3: On Railway, after deploy, import via Hindsight API
curl -X POST http://localhost:8888/banks/hermes-railway/import \
  -H "Content-Type: application/json" \
  -d @hermes_bank_export.json
```

**Important caveats**:
- Hindsight API is currently `local_external` on Windows and will become `local_embedded` on Railway
- The `hindsight-client` package is needed for `local_embedded` mode
- Railway's PG needs the `pgvector` extension (available via pgvector template or `CREATE EXTENSION pgvector;`)
- If hindsight-client version mismatch occurs, may need to rebuild Railway container

### 6.4 Alternative: Start Fresh on Railway

Since the Hindsight data is ~260MB and consists of embeddings that can be regenerated:
- **Simpler approach**: Let Railway Hindsight rebuild banks from conversation history
- Set `auto_retain: true` and let it accumulate over time
- Historical session transcripts in SQLite state.db can be re-processed

---

## 7. Migration Plan: Windows → Railway

### 7.1 Split-Brain Architecture

**Not everything should migrate.** The recommended approach is a split:

| Location | What Runs There |
|----------|----------------|
| **Railway** | Colony monitor, GitRadar, kanban watchers, general agent, dashboard |
| **Windows** | Trading system, wiki/vault management, Windows-specific tools |

Both deliver to Discord, so users interact seamlessly.

### 7.2 What Migrates

#### Skills (COPY into repo)
Copy into `hermes-tailscale-rw/skills/`:
- `the-colony/`, `hermes-cloud-deploy/`, `devops/*`, `one-three-one-rule/`
- Exclude: `windows-crash-forensics/`, `windows-discord-media/`, `windows-hermes-workarounds/`

#### Profiles (COPY into repo)
Copy into `hermes-tailscale-rw/profiles/`:
- All profiles EXCEPT `trading/` (depends on Windows-specific trading code)
- Copy: SOUL.md, AGENTS.md, profile.yaml from each profile directory
- Do NOT copy: `.env` files (use Railway env vars), `state.db` (use volume symlinks)

#### Hooks
- COPY `boot-md/` and `end-logger/` into `hermes-tailscale-rw/hooks/`
- Rewrite BOOT.md content for Linux (replace PowerShell with bash, Windows paths with Linux)

#### Cron Jobs (6 migrate)
| Job | Linux Path/Env Needed |
|-----|-----------------------|
| colony-notifications-monitor | `COLONY_API_KEY` env var |
| GitRadar Pipeline + Recommendations | `GITHUB_TOKEN`, gitradar repo |
| hermes-relay Kanban Watcher + Board Watcher | Kanban DB on volume |

#### Cron Jobs (8 stay on Windows)
All trading jobs (6), wiki daily briefing, wiki harvester — all depend on Windows paths.

### 7.3 Repo Structure for Migration

```
hermes-tailscale-rw/
├── skills/                    # Custom Linux-compatible skills
│   ├── the-colony/
│   ├── hermes-cloud-deploy/
│   └── devops/
├── profiles/                  # Custom profile configs
│   ├── agy-lane/
│   │   ├── SOUL.md
│   │   ├── AGENTS.md
│   │   └── profile.yaml
│   ├── mimirs-will/
│   └── ... (12 profiles, no trading)
├── hooks/
│   ├── boot-md/
│   └── end-logger/
├── BOOT.md.railway            # Linux-rewrite of BOOT.md
├── HERMES.md.railway          # Linux-rewrite of HERMES.md
├── Dockerfile                 # Enhanced with COPY directives
├── railway.json               # Railway deploy config
└── docker/
    ├── start-all.sh           # Original (backup)
    ├── railway-start.sh       # Enhanced startup with volume symlinks
    ├── generate_config.py     # Config gen (already exists)
    └── health.py              # Health check server
```

### 7.4 Migration Phases

**Phase 1: Foundation (Week 1)**
1. Add `skills/`, `profiles/`, `hooks/` directories to git repo
2. Copy custom skills, profiles, hooks into repo
3. Create `BOOT.md.railway`, `HERMES.md.railway` (Linux rewrites)
4. Add `sqlite3` to Dockerfile apt packages
5. Create `railway-start.sh` with volume symlink logic
6. Update `railway.json` with healthcheck config
7. Deploy to Railway, verify gateway + dashboard start

**Phase 2: Cron Migration (Week 2)**
1. Add Railway env vars: `COLONY_API_KEY`, `GITHUB_TOKEN`
2. Create new Linux-path cron jobs for the 6 migratable jobs
3. Disable the 6 migrated cron jobs on Windows
4. Test each Railway cron job manually
5. Monitor for 48h

**Phase 3: Hindsight Migration (Week 3)**
1. Configure `DATABASE_URL` reference to Railway Postgres
2. Ensure pgvector extension is enabled
3. Either export/import existing Hindsight data OR start fresh
4. Verify Hindsight banks are created and accumulating

**Phase 4: Validation**
1. Full verification checklist:
   - [ ] Dashboard accessible at Railway URL
   - [ ] SSH via Tailscale works
   - [ ] API server responds on 8642
   - [ ] Hindsight healthy on 8888
   - [ ] Cron jobs fire correctly
   - [ ] Volume persistence works (restart container, data intact)

---

## 8. Common Pitfalls & Gotchas

### 8.1 Shell Heredoc Crash Loop (CRITICAL)
Using `cat <<EOF` with `$` characters in values → `bad substitution` → container crash loop. Always use Python for config files with secrets.

### 8.2 Ephemeral /root/.hermes/
Config files in `/root/.hermes/` do NOT survive restarts. Must auto-generate from env vars on every boot via `railway-start.sh`.

### 8.3 Volume Downtime
Services with volumes get brief downtime on redeploy (Railway can't do zero-downtime with volumes). Keep deploys minimal during market hours.

### 8.4 Tailscale Auth Key Reuse
Railway restarts containers frequently. Use Tailscale's **reusable** ephemeral auth keys, not one-time keys. Clean up stale nodes in Tailscale admin.

### 8.5 ENV Line-Continuation Gotcha
When patching Dockerfile, ensure `\\` continuation doesn't absorb the next line (e.g., `ENV` getting concatenated onto a `RUN`). Always `cat Dockerfile` after patching.

### 8.6 Non-Root UID Volume Access
Docker images running as non-root get volume permissions errors. Set `RAILWAY_RUN_UID=0` if needed.

### 8.7 Healthcheck Port Mismatch
Railway uses the `PORT` env var for healthchecks. If your healthcheck.py listens on 8080 but PORT=8648, healthchecks fail. Either listen on `$PORT` or set `RAILWAY_HEALTHCHECK_TIMEOUT_SEC` explicitly.

---

## 9. Access & Post-Deploy

| Service | Access Method |
|---------|--------------|
| Dashboard | `https://<railway-url>:8648` (or Railway domain) |
| SSH (Tailnet) | `ssh root@<tailscale-ip>` after `tailscale set --ssh` |
| API Server | `https://<railway-url>:8642/v1/models` |
| Health check | `https://<railway-url>:8080/` |
| Hindsight | Internal only (localhost:8888, via Railway exec) |

---

## 10. Troubleshooting

```bash
# Build logs (latest attempt):
railway service logs --service <name> --build --latest

# Runtime logs:
railway service logs --service <name> --latest

# Check if deploy failed (new build vs active):
railway service list --json
# Compare deploymentId vs latestDeployment.id

# Connect to running container:
railway run /bin/bash

# Check volume contents:
railway volume browse
```

---

*This document should be maintained alongside the hermes-cloud-deploy skill and the hermes-tailscale-rw repository.*
*Last updated: 2026-05-31 by OWL*
