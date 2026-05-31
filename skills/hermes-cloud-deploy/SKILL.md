---
name: hermes-cloud-deploy
description: "Deploy Hermes Agent to cloud platforms (Railway, Render, Fly.io, etc.) — Dockerfile creation, service orchestration, Tailscale VPN, SSH access, remote Hindsight, cloud PostgreSQL, and Windows-to-cloud migration. Use when the user wants to run Hermes remotely/on a cloud host rather than locally, or migrate an existing Windows install to Railway."
---

# Hermes Cloud Deployment

Deploy Hermes Agent to a cloud container platform with full toolchain: TUI dashboard, gateway (messaging-ready), Tailscale VPN, SSH, Hindsight memory, and persistent customizations.

## Platforms Covered

- **Railway** (primary — managed Postgres, env vars, Dockerfile deploys)
- Render, Fly.io, etc. (same Dockerfile patterns apply)

## Support Files

| File | Purpose |
|------|---------|
| `templates/generate_config.py` | Python config generation (safe secret handling) |
| `templates/health.py` | Railway health check HTTP endpoint |
| `references/railway-gotchas.md` | Error reproductions, crash loops, CLI quirks |
| `references/railway-reference-may2026.md` | Condensed Railway platform knowledge |
| `references/windows-migration.md` | Windows → Railway migration guide |

## Architecture Pattern

```
Railway Project: hermes-agent
├── Hermes Agent Container (Docker — debian:bookworm-slim)
│   ├── Tailscale (userspace networking)
│   ├── SSHD (Tailnet SSH)
│   ├── Hermes Gateway (Discord + API server, port 8642)
│   ├── hermes-web-ui Dashboard (port 8648)
│   ├── Hindsight API (local_embedded, port 8888)
│   ├── Cron scheduler
│   ├── Custom skills + profiles + hooks
│   └── Health check endpoint (port 8080)
├── PostgreSQL (Railway managed plugin)
│   ├── Hindsight bank storage (pgvector for embeddings)
│   └── DATABASE_URL (injected env var)
└── Railway Volume (/hermes-data)
    ├── state.db (agent sessions, ~180MB)
    ├── kanban/ (kanban boards)
    ├── tailscale.state
    └── profiles/ (per-profile state)

NOTE: Hindsight runs in local_embedded mode inside the Hermes process.
There is NO separate Hindsight service — it uses Railway's managed PostgreSQL
via the DATABASE_URL reference variable.
```

## Step-by-Step: Railway + Tailscale + Hindsight

### 1. Dockerfile

Use `debian:bookworm-slim` (not `python:3.11-slim`) for full build control. Use `tini` as PID 1.

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

# Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Hermes Agent (clone from GitHub for latest)
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

# Volume directories (overridden by Railway Volume mount)
RUN mkdir -p /hermes-data/{logs,kanban,watcher-state,tailscale,profiles}

# Copy custom assets (skills, profiles, hooks, static files)
COPY skills/ /root/.hermes/skills/
COPY profiles/ /root/.hermes/profiles/
COPY hooks/ /root/.hermes/hooks/
COPY BOOT.md.railway /root/.hermes/BOOT.md
COPY HERMES.md.railway /root/.hermes/HERMES.md

# Copy start scripts
COPY docker/railway-start.sh /railway-start.sh
COPY docker/health.py /app/health.py
COPY docker/generate_config.py /app/generate_config.py
RUN chmod +x /railway-start.sh /app/health.py

EXPOSE 22 8642 8648 8888

ENTRYPOINT ["tini", "--"]
CMD ["/railway-start.sh"]
```

### 2. Start Script (`railway-start.sh`)

The start script MUST: (1) symlink ephemeral → persistent volume, (2) generate configs via Python, (3) start Tailscale + SSH, (4) start gateway + dashboard + health check.

Full template is in the conversation history. Key pattern: the `symlink_persist()` function migrates data to `/hermes-data/` on first run, then symlinks back. This MUST complete before `hermes gateway run`.

### 3. Health Check Endpoint (`health.py`)

Minimal HTTP server returning 200 on GET. Copy from `templates/health.py`.

### 4. Config Generation (`generate_config.py`)

Copy from `templates/generate_config.py`. **NEVER use shell heredocs** for files containing secrets — use Python `open().write()`.

### 5. Railway Environment Variables

Set in Railway dashboard (never in repo):

| Variable | Description |
|----------|-------------|
| `OPENROUTER_API_KEY` | OpenRouter API key |
| `HERMES_MODEL` | Model string (e.g. `@preset/hermes`) |
| `TS_AUTHKEY` | Tailscale **reusable** ephemeral auth key |
| `TS_HOSTNAME` | Hostname for this node |
| `DATABASE_URL` | PostgreSQL (Railway provides via reference) |
| `SSH_PUBLIC_KEY` | Your SSH public key |
| `COLONY_API_KEY` | The Colony API key (optional) |
| `GITHUB_TOKEN` | GitHub token for GitRadar (optional) |

### 6. Railway Volume

**Essential** — without it, all state is lost on restart.

- Mount path: `/hermes-data`
- Size: 5GB (Hobby) or 50GB (Pro) — ~260MB current usage
- Set `RAILWAY_RUN_UID=0` if non-root

Layout: `logs/`, `tailscale.state`, `state.db` (symlink), `kanban/`, `watcher-state/`, `response_store.db`, `profiles/`.

### 7. PostgreSQL

1. Railway dashboard → New → Database → PostgreSQL
2. `DATABASE_URL` as cross-service reference
3. Ensure `pgvector` extension for Hindsight
4. SQLite handles sessions/kanban — PG only for Hindsight banks

### 8. Healthchecks (May 2026)

- Hostname: `healthcheck.railway.app`
- Timeout: 300s default, override with `RAILWAY_HEALTHCHECK_TIMEOUT_SEC`
- Volume services get brief downtime on redeploy
- No continuous monitoring after deploy

### 9. Tailscale SSH

Must run `tailscale set --ssh` after `tailscale up`. Use reusable ephemeral auth keys.

```bash
ssh root@<tailscale-ip>
```

### 10. Hindsight Config (`local_embedded`)

```json
{
  "mode": "local_embedded",
  "bank_id": "hermes-railway",
  "auto_retain": true,
  "retain_every_n_turns": 5,
  "budget": "mid",
  "database_url": "<DATABASE_URL>"
}
```

## Retrieving Secrets from Bitwarden

1. Determine product: Secrets Manager (`bws`) vs Password Manager (`bw`)
2. `bw` requires `BW_SESSION` from `bw unlock`
3. On Windows: `bw` may not be installed — ask user to paste or `npm install -g @bitwarden/cli`
4. Railway env vars are the destination — never commit secrets

## Common Pitfalls

- **Shell heredoc crash loop (CRITICAL)**: `$` in API keys causes `bad substitution` → infinite restart. Always use Python for config files with secrets.
- **Ephemeral /root/.hermes/**: Wiped on every restart. Must auto-generate from env vars.
- **Gateway crashes**: Railway restarts on crash. Use `wait` pattern.
- **Tailscale SSH rejected**: Forgot `tailscale set --ssh` after `tailscale up`.
- **Tailscale one-time keys**: Railway restarts often. Use **reusable** ephemeral auth keys.
- **Local PG crash loop**: Don't run `initdb` in container. Use Railway managed PG.
- **Dashboard command**: `hermes-web-ui start --port 8648` NOT `hermes dashboard --tui`.
- **Hindsight plugin**: Requires `hindsight-client` as separate `RUN` step.
- **ENV line-continuation**: `\\` in Dockerfile can absorb next line. Always verify after patching.
- **Railway Agent**: Can auto-diagnose failures and open PRs. Useful during debugging.
- **Volume downtime**: Services with volumes get brief downtime on redeploy.
- **Healthcheck hostname**: `healthcheck.railway.app` must be in allowed hosts.
- **Node.js**: hermes-web-ui requires v23+. Use `setup_24.x`.
- **Railway CLI in MSYS**: `railway up` hangs. Use `railway service redeploy --yes`.

## Windows → Railway Migration

### Split-Brain Strategy
Run TWO instances. **Railway**: Colony, GitRadar, kanban watchers. **Windows**: trading, wiki/vault. Both deliver to Discord.

### What Migrates
- Skills → COPY into `skills/` dir in repo
- Profiles → COPY SOUL.md/AGENTS.md (NOT .env or state.db)
- Hooks → COPY into `hooks/`, rewrite BOOT.md for Linux
- Cron: 6 of 14 migrate (api-based), 8 stay (trading + wiki with Windows paths)
- Data: state.db + profile state.dbs → Railway Volume via symlinks
- Hindsight: export/import via API or start fresh

### Volume Symlink Pattern
`railway-start.sh` must symlink `/root/.hermes/state.db` → `/hermes-data/state.db` BEFORE gateway starts. On first run, migrate data to volume then symlink back.

See `references/windows-migration.md` for the complete migration guide including repo structure, cron routing, and 4-phase timeline.

## Verification Checklist

- [ ] `curl http://<railway-url>:8648` → Dashboard responds
- [ ] `ssh root@<tailscale-ip>` → SSH works (after `tailscale set --ssh`)
- [ ] `curl http://<railway-url>:8642/v1/models` → API server responds
- [ ] `curl http://localhost:8080/` (via Railway exec) → Health check "ok"
- [ ] `curl http://localhost:8888/health` (via Railway exec) → Hindsight healthy
- [ ] Send a message → Hindsight retain fires
- [ ] Volume persistence: restart → state.db intact
- [ ] Cron jobs fire correctly (`hermes cron run <job_id>`)