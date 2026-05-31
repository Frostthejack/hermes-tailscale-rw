# Reference: Railway Deployment Gotchas

## How to Create a Railway Service via CLI (Non-Interactive)

The `railway add --repo` flag triggers an interactive prompt that fails in MSYS/bash terminals.
Workaround — use dashboard for repo linking:

```bash
# Step 1: Create empty service (non-interactive)
railway add --service hermes-agent --json

# Step 2: Set env vars via CLI
railway variable set OPENROUTER_API_KEY=sk-or-... --skip-deploys --json
railway variable set TS_AUTHKEY=tskey-auth-... --skip-deploys --json

# Step 3: Link GitHub repo via Railway dashboard
# Dashboard → Service → Settings → Source → GitHub Repo
```

## Cross-Service Variable References

Railway supports `${{Service.VAR}}` syntax but the shell eats `${{}}` in CLI commands.
Set `DATABASE_URL` from Postgres service manually in the Dashboard:
- Go to the Hermes service → Variables → New Variable
- Select the "Reference" tab → choose Postgres → DATABASE_URL

Or manually construct it from the Postgres service's Variables tab:
```
postgresql://postgres:PASSWORD@postgres.railway.internal:5432/railway
```

## Bitwarden Secrets Manager CLI Quirks

```bash
# Correct: positional project ID
bws secret list <project-uuid>

# Wrong: flag-based project ID (not supported)
bws secret list --project-id <project-uuid>   # fails!

# List all projects first
bws project list

# Then list secrets per project
bws secret list bc31c79e-da7e-46b8-9f1a-b4570162d3fc
```

Secrets are organized as: **Organization → Projects → Secrets**.
A "key called X" might be a Secret inside a Project, not a Project itself.

## Tailscale on Railway

- Tailscale containers restart frequently on Railway. Use **reusable ephemeral auth keys**.
- Clean up stale nodes in Tailscale admin console (Machines → expired).
- The Railway container gets a `100.x.y.z` Tailscale IP automatically after `tailscale up`.
- SSH access: `ssh root@<tailscale-ip>` (not through Railway's public domain).
- **CRITICAL**: Run `tailscale set --ssh` AFTER `tailscale up`. Without this command, Tailnet SSH is disabled and all SSH connections are rejected. The node appears online in the tailnet but refuses SSH.

## Config Generation Crash Loop (Gotcha)

When writing `.env` or `config.yaml` files that contain API keys:

```bash
# WRONG — causes 'bad substitution' crash loop
cat > /root/.hermes/.env << EOF
OPENROUTER_API_KEY=${OPENROUTER_API_KEY}
EOF
```

Shell interpolation eats `$`, `{`, `}` in the key value. The container crashes on every start. **Always use a Python script** (see `templates/generate_config.py`) to write config files with secrets.

## Local PostgreSQL Crash Loop (Gotcha)

Running `initdb` inside a Debian Railway container fails with `initdb: command not found` because the binary is at `/usr/lib/postgresql/15/bin/initdb`, not in PATH. The container crash-loops.

**Do not run local PostgreSQL in the container.** Use Railway's managed Postgres plugin and reference it via `DATABASE_URL`. Hindsight in `local_embedded` mode reads `DATABASE_URL` directly.

## hermes-web_ui Dashboard

- Install: `npm install -g hermes-web-ui@latest` (requires Node.js v23+)
- Start: `hermes-web-ui start --port 8648`
- NOT `hermes dashboard --tui` — that command doesn't exist
- Requires Node.js v24: `curl -fsSL https://deb.nodesource.com/setup_24.x | bash -`

## Hindsight Plugin Installation

Hindsight is a built-in Hermes plugin (`plugins/memory/hindsight/`) but requires the
`hindsight-client` pip package. Install as a **separate `RUN` step** (not `&&`-chained
onto a line that continues with `\`):

```dockerfile
RUN /hermes-venv/bin/pip install --no-cache-dir hindsight-client>=0.4.22
```

Config goes in `/root/.hermes/hindsight/config.json` (generate at boot — the directory
is ephemeral):

```json
{
    "mode": "local_embedded",
    "bank_id": "hermes-railway",
    "auto_retain": true,
    "retain_every_n_turns": 5,
    "budget": "mid",
    "database_url": "<DATABASE_URL from environment>"
}
```

Enable in `~/.hermes/config.yaml`:
```yaml
memory:
  provider: hindsight
plugins:
  enabled:
    - hindsight
```

## Ephemeral /root/.hermes/ — Config Must Be Generated at Boot

`/root/.hermes/` is **ephemeral** — wiped on every container restart. Config files written
manually via SSH do NOT survive restarts.

**Solution**: Auto-generate `config.yaml` and `.env` from Railway-injected env vars on
every boot, BEFORE starting the Hermes Gateway. Use a Python script (not shell heredoc).
See `templates/generate_config.py`.

## Debugging Railway Deploy Failures

```bash
# Build logs from latest attempt:
railway service logs --service <name> --build --latest --lines 100

# Runtime logs from latest (even failed) deployment:
railway service logs --service <name> --latest --lines 100
```

If `railway service list --json` shows `deploymentId` != `latestDeployment.id`, the new
build failed and Railway kept the old deployment active.

## Dockerfile ENV Line-Continuation Gotcha

When using `patch` to add a `pip install` line before `ENV` in a Dockerfile, the
replacement text can get concatenated with the `ENV` line if the `\` continuation
isn't properly terminated:

```
# BROKEN — ENV became part of the RUN:
RUN ... && pip install foo \
ENV PATH="/bar"

# FIXED:
RUN ... && pip install foo
ENV PATH="/bar"
```

**Always `cat` the Dockerfile after patching** to confirm `ENV` is on its own line.
