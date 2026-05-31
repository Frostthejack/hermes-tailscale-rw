# Hermes Skill Migration: WSL ↔ Windows

**Domain**: Copying Hermes skills, configs, and data between WSL and Windows Hermes instances.

---

## Accessing WSL Files from Windows

WSL2 distros are accessible from Windows via the `\\wsl$` UNC path:

```
\\wsl$\<distro-name>\home\<user>\.hermes\
```

From bash/MSYS (Git Bash) on Windows, use the `//wsl$/` mount:

```bash
# List WSL Hermes skills from Windows bash
ls //wsl$/Ubuntu-24.04/home/frostthejack/.hermes/skills/

# List Windows Hermes skills
ls ~/AppData/Local/hermes/skills/
```

**Note**: `\\wsl$` is accessible from Windows-native tools (Explorer, PowerShell) and from bash/MSYS via `//wsl$/`. It is NOT reliably accessible from Windows PowerShell in all configurations — test first.

---

## Skill Migration Pattern

Skills are self-contained directories with a `SKILL.md` file and optional `references/`, `templates/`, and `scripts/` subdirectories. They can be freely copied between Hermes instances.

### From WSL (run in WSL terminal)

```bash
# Copy all skills from WSL to Windows Hermes
cp -r ~/.hermes/skills/* /mnt/c/Users/<windows-user>/AppData/Local/hermes/skills/

# Copy a single skill
cp -r ~/.hermes/skills/my-skill /mnt/c/Users/<windows-user>/AppData/Local/hermes/skills/
```

### From Windows (run in Git Bash / MSYS)

```bash
# Copy all skills from WSL to Windows
cp -r //wsl$/Ubuntu-24.04/home/<wsl-user>/.hermes/skills/* ~/AppData/Local/hermes/skills/

# Copy a single skill
cp -r //wsl$/Ubuntu-24.04/home/<wsl-user>/.hermes/skills/my-skill ~/AppData/Local/hermes/skills/
```

### From Windows Explorer

1. Open `\\wsl$\Ubuntu-24.04\home\<user>\.hermes\skills\` in Explorer
2. Copy desired skill folders
3. Paste into `C:\Users\<user>\AppData\Local\hermes\skills\`

---

## What to Migrate

| Item | Path (WSL) | Path (Windows) | Notes |
|------|-----------|----------------|-------|
| Skills | `~/.hermes/skills/` | `~/AppData/Local/hermes/skills/` | Safe to copy; folder name = skill name |
| Config | `~/.hermes/config.yaml` | `~/AppData/Local/hermes/config.yaml` | Review before overwriting — provider/model settings may differ |
| Env/secrets | `~/.hermes/.env` | `~/AppData/Local/hermes/.env` | Contains API keys — copy with care |
| Profiles | `~/.hermes/profiles/` | `~/AppData/Local/hermes/profiles/` | Each profile has its own skills, config, sessions |
| Cron jobs | `~/.hermes/cron/` | `~/AppData/Local/hermes/cron/` | Stored in SQLite; not a simple file copy |
| Sessions | `~/.hermes/sessions/` | `~/AppData/Local/hermes/sessions/` | Usually not worth migrating |
| Memories | `~/.hermes/memories/` | `~/AppData/Local/hermes/memories/` | Platform-specific paths may differ |

---

## Safety Notes

- **Skills are safe to copy** — they're read-only at runtime and namespaced by folder name.
- **Don't blindly overwrite `config.yaml`** — WSL and Windows may use different providers, models, or paths. Compare first.
- **Don't copy `.env` without review** — API keys may be the same, but paths and platform-specific settings will differ.
- **Profiles are isolated** — copying a profile from WSL to Windows will bring its skills, config, and sessions, but paths inside configs (e.g., `C:\Users\...` vs `/home/...`) will need updating.
- **Skills with `required_commands` or `required_environment_variables`** may not work on the target platform if those dependencies aren't installed there.

---

## Verifying After Migration

```bash
# List all skills on Windows
ls ~/AppData/Local/hermes/skills/

# Check a specific skill loaded correctly
# (In Hermes chat)
# /skill <name>
```

Skills are loaded automatically at session start — no restart of a running session is needed if you start a new session (`/reset` or new `hermes` invocation).
