---
name: secret-management
description: Store, retrieve, and manage secrets (API keys, passwords, tokens, credentials) using Bitwarden. Covers both Bitwarden Secrets Manager (bws — machine-account API keys synced to env vars) and Bitwarden Password Manager (bw — personal vault for logins, notes, SSH keys, TOTP). Use when the user asks to store, access, rotate, or migrate secrets, or when configuring Hermes to pull API keys from Bitwarden.
---

# Secret Management

Two Bitwarden products serve different purposes. Know which one you're using.

| Tool | Product | Use For |
|------|---------|---------|
| `bws` | Secrets Manager | API keys, tokens, env vars, machine-readable secrets — synced into Hermes automatically at startup |
| `bw` | Password Manager | Personal vault — logins, passwords, secure notes, SSH keys, TOTP, credit cards |

Secrets Manager (`bws`) is **separate** from your personal vault (`bw`). Secrets live in Bitwarden Secrets Manager projects, not in your password vault.

---

## Bitwarden Secrets Manager (`bws`)

### Setup

Hermes has built-in integration. Run:
```bash
hermes secrets bitwarden setup
```
This wizard downloads `bws` into `~/.hermes/bin/bws`, prompts for the access token, picks a project, and enables sync.

Non-interactive:
```bash
hermes secrets bitwarden setup \
  --access-token "0.xxx" \
  --server-url https://vault.bitwarden.com \
  --project-id <project-uuid>
```

In the web app (one-time setup before the wizard):
1. Switch to **Secrets Manager** in Bitwarden web UI (product switcher top-left)
2. Create a **Project** (e.g. "dev keys")
3. Add secrets — **Name** = env var name, **Value** = actual key
4. Create a **Machine account** → grant **Read** access to the project
5. Generate an **Access token** (starts with `0.`) — **save it, Bitwarden can't show it again**

### Commands

| Command | What it does |
|---------|-------------|
| `hermes secrets bitwarden status` | Check config + binary + token presence |
| `hermes secrets bitwarden sync` | Dry-run: show which env vars would be set |
| `hermes secrets bitwarden sync --apply` | Pull secrets into current shell's environment |
| `hermes secrets bitwarden disable` | Flip `enabled: false` |
| `hermes secrets bitwarden install` | Just download bws binary |

### Machine account permissions

- **Read-only** (default/setup): Hermes can pull secrets but cannot create, edit, or delete them. User manages secrets via web UI.
- **Read/Write**: If machine account is granted write access, `bws` can create/update/delete secrets via CLI.
- The access token is stored in `~/.hermes/.env` as `BWS_ACCESS_TOKEN`. Treat it like a master key.

### Adding secrets via CLI (requires write access)

```bash
~/.hermes/bin/bws secret create \
  --project-id <project-uuid> \
  --key "OPENROUTER_API_KEY" \
  --value "sk-or-v1-xxx" \
  --note "OpenRouter API key"
```

Secrets auto-sync into Hermes sessions at startup (5-min cache). No more plaintext API keys in `.env`.

---

## Bitwarden Password Manager (`bw`)

### Install
```bash
npm install -g @bitwarden/cli
```

### Login
```bash
bw login                    # interactive: email + password (+ 2FA if set)
bw unlock                   # generates session key
# Run the printed: export BW_SESSION="..."
```

### Core commands

| Command | What it does |
|---------|-------------|
| `bw list items` | List all vault items |
| `bw list items --search github` | Search by name |
| `bw get password Github` | Get password for item |
| `bw get item Github` | Get full JSON for item |
| `bw get notes "My Note"` | Get secure note contents |
| `bw lock` | Lock vault (keep logged in) |
| `bw logout` | Full logout |

### Creating items

**Login:**
```bash
bw get template item | jq '.name="GitHub" | .login = (.username="user" | .password="pass")' | bw encode | bw create item
```

**Secure note (type 2):**
```bash
bw get template item | jq '.type=2 | .secureNote.type=0 | .name="Note Name" | .notes="content"' | bw encode | bw create item
```

**SSH key (type 5):**
```bash
bw get template item | jq '.type=5 | .name="Server SSH" | .sshKey.privateKey="-----BEGIN..." | .sshKey.publicKey="ssh-ed25519..."' | bw encode | bw create item
```

### Item types

| Type | Value |
|------|-------|
| Login | 1 |
| Secure Note | 2 |
| Card | 3 |
| Identity | 4 |
| SSH Key | 5 |

---

## Pitfalls

- `bw` commands fail without `BW_SESSION` set. Always run `bw unlock` after login and export the session key.
- The bws access token **starts with `0.`** — if you have a `bw` session key, that's a different thing.
- `bws` binary lives at `~/.hermes/bin/bws` (not on PATH by default). Use full path or `hermes secrets bitwarden` commands.
- Secrets Manager secrets are **not** the same as Password Manager items. Don't confuse the two.
- Hermes auto-pulls secrets at startup when `secrets.bitwarden.enabled: true` in config. No manual intervention needed after initial setup.
