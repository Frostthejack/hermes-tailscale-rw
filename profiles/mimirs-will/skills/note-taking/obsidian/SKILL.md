---
name: obsidian
description: Read, search, create, and manage notes in the Obsidian vault. Handles cross-platform paths (WSL/Windows/macOS), multi-vault setups, vault migration/consolidation, and git-backed vault workflows.
tags: [obsidian, note-taking, vault-management, cross-platform]
category: note-taking
prerequisites:
  - "Basic shell proficiency (cd, ls, cat, find)"
  - "Obsidian application installed (optional but recommended)"
  - "curl for Hindsight integration"
related_skills: [hermes-agent]
---

# Obsidian Vault Management

The Obsidian vault is your personal knowledge base. This skill handles reading, searching, creating, and managing notes across different environments (WSL, Windows, macOS, Linux) and multi-vault setups.

**Special Focus:** WSL + Windows integration with Hindsight memory service.

## Quick Reference

| Task | Command |
|------|---------|
| **Set vault path** | `export OBSIDIAN_VAULT_PATH="/path/to/vault"` |
| **Read note** | Use `obsidian read <note>` via skill |
| **Search notes** | Use `obsidian search <query>` via skill |
| **Create note** | Use `obsidian create <note>` via skill |
| **List notes** | `find "$VAULT" -name "*.md" -type f` |
| **Diagnose WSL** | `source scripts/diagnose-wsl-hindsight.sh` |

## References

- **Encephalon-Mageia Vault:** [references/vault-encephalon-mageia.md](references/vault-encephalon-mageia.md) — primary vault location, structure, git workflow, migration pattern, user preferences
- **The Colony API:** [references/the-colony-api.md](references/the-colony-api.md) — thecolony.cc API reference, quirks, our account details, cron monitoring
- **Session Setup Guide:** [WSL + Hindsight + Vault](references/session-20240503-wsl-hindsight-vault-setup.md)
- **Diagnostic Script:** [diagnose-wsl-hindsight.sh](scripts/diagnose-wsl-hindsight.sh)

## Environment Setup

### Path Configuration

The vault path is controlled by the `OBSIDIAN_VAULT_PATH` environment variable. Configure it in `~/.hermes/.env`:

```bash
# Primary vault — Windows native (confirmed location)
OBSIDIAN_VAULT_PATH="C:\Users\luned\Vault\Encephalon-Mageia"

# WSL accessing the same vault (if running from Linux)
# OBSIDIAN_VAULT_PATH="/mnt/c/Users/luned/Vault/Encephalon-Mageia"
```

**Important:** Always quote paths containing spaces. When running on Windows, use native `C:\` paths — not `/mnt/c/` mounts. When running on WSL, use `/mnt/c/` paths.

**Confirmed vault locations:**
- **Windows Hermes (this host):** `C:\Users\luned\Vault\Encephalon-Mageia\`
- **WSL Hermes (if applicable):** `/mnt/c/Users/luned/Vault/Encephalon-Mageia/`
- Wiki subdirectory: `wiki/` inside whichever vault path is active

All project files, notes, and research live here.

### Cross-Platform Considerations

**WSL (Windows Subsystem for Linux):**
- Windows paths mount under `/mnt/c/`, `/mnt/d/`, etc.
- Windows services (like Hindsight) run on host IP, not localhost
- Use Windows host IP for services: `http://<windows-host-ip>:port`
- Enable WSL systemd for reliable service management: add `systemd=true` to `/etc/wsl.conf`

**Windows ↔ WSL File Sharing:**
- Windows → WSL: `/mnt/c/Users/<user>/...`
- WSL → Windows: `\\\\wsl$\\<distro>\\home\\<user>\\...`

## Core Operations

### Setting Up a New Vault

```bash
# 1. Set the path (add to ~/.hermes/.env)
export OBSIDIAN_VAULT_PATH="$HOME/Documents/My Obsidian Vault"

# 2. Create the directory
mkdir -p "$OBSIDIAN_VAULT_PATH"

# 3. Create initial marker file
cat > "$OBSIDIAN_VAULT_PATH/Welcome.md" << 'EOF'
# Welcome to My Vault

This is my personal knowledge base.
EOF

# 4. Verify
ls -la "$OBSIDIAN_VAULT_PATH"
```

### Reading a Note

```bash
# Windows native path
VAULT="C:\Users\luned\Vault\Encephalon-Mageia"
# WSL path (if running from Linux)
# VAULT="/mnt/c/Users/luned/Vault/Encephalon-Mageia"
read_file "$VAULT/Note Name.md"
```

### Searching

```bash
VAULT="C:\Users\luned\Vault\Encephalon-Mageia"

# Search by filename
find "$VAULT" -name "*.md" -iname "*keyword*" -type f

# Search by content (case-insensitive)
grep -rli "keyword" "$VAULT" --include="*.md"

# Search with context
grep -rni "keyword" "$VAULT" --include="*.md" -A 2 -B 2
```

### Creating and Managing Notes

```bash
VAULT="C:\Users\luned\Vault\Encephalon-Mageia"

# Create new note
cat > "$VAULT/New Note.md" << 'EOF'
# New Note

Date: $(date)

## Links
- [[Related Note]]

## Tags
#todo
EOF

# Create note in subdirectory (e.g., reports)
mkdir -p "$VAULT/reports"
cat > "$VAULT/reports/report-name.md" << 'EOF'
# Report Title

Date: $(date)
EOF
```

### Using Wikilinks

Obsidian uses `[[Note Name]]` syntax for bidirectional links:

```markdown
# Project Alpha

This project relates to [[Project Beta]] and uses concepts from [[Research/Methodology]].

See also: [[Meeting Notes/2024-01-15]]
```

## Advanced Features

### Multi-Vault Setup

For managing multiple vaults:

```bash
# Switch vaults by changing the env var (Windows)
export OBSIDIAN_VAULT_PATH="C:\Users\luned\Vault\Encephalon-Mageia"
```

### Community Plugins

Common plugins enhance functionality:
- **Dataview**: Query notes as databases
- **Templater**: Custom note templates
- **Periodic Notes**: Auto-create daily/weekly/monthly notes
- **Obsidian Git**: Version control with Git
- **Tasks**: Task management across vault
- **Calendar**: Calendar-based note creation

### Templates

Create a Templates folder:

```bash
VAULT="C:\Users\luned\Vault\Encephalon-Mageia"
mkdir -p "$VAULT/Templates"
```

## Wiki Schema (Encephalon-Mageia)

When creating or editing wiki pages in the Encephalon-Mageia vault:

- **Filenames:** lowercase, hyphens, no spaces
- **Every page needs YAML frontmatter** with: title, created, updated, type, tags, sources, confidence
- **Minimum 2 outbound [[wikilinks]]** per page
- **Bump `updated` date** on every edit
- **Add every new page to `index.md`** under the correct section (entities, concepts, comparisons, queries)
- **Append every action to `log.md`** (format: `## [YYYY-MM-DD] action | subject`)
- **Don't create pages** for passing mentions, minor details, or things outside the domain
- **Split pages** at ~200 lines
- **Tag taxonomy:** ai-tool, memory-system, mcp, agent, cli, desktop-app, concept-name, person, company, open-source, integration, architecture, automation, comparison, how-to, overview, pitfall

## Git Operations on the Vault

When managing an Obsidian vault via git (especially from WSL), use the CLI rather than relying on the Obsidian Git plugin — it gives you full control over commits, pushes, and conflict resolution.

### Initial Git Setup (per-repo)

```bash
cd "C:\Users\luned\Vault\Encephalon-Mageia"
git config user.name "frostthejack"
git config user.email "frostthejack@users.noreply.github.com"
```

**Always set user identity locally** before committing.

### Standard Workflow

```bash
cd "C:\Users\luned\Vault\Encephalon-Mageia"

# Check status first
git status

# Stage all changes
git add -A

# Commit
git commit -m "descriptive message"

# Push (branch is Main, not master)
git push origin Main
```

### Handling Divergent Branches

The Obsidian Git plugin auto-commits from the local Windows machine, so the git state can fall behind. When `git push` rejects:

```bash
cd "C:\Users\luned\Vault\Encephalon-Mageia"

# 1. Stash any unstaged local changes
git stash

# 2. Rebase onto remote
git pull --rebase origin Main

# 3. Restore stashed changes
git stash pop

# 4. If stash pop creates conflicts:
git add -A
git commit -m "sync local changes"
git rebase --continue

# 5. Push
git push origin Main
```

**User preference:** When there are conflicts between local and remote, prioritize the local files (the vault on the machine) over what's on GitHub. Use `git push origin Main` with force only if necessary after rebase.

### Recommended .gitignore for Obsidian Vaults

```
# Obsidian workspace state (per-device)
.obsidian/workspace.json
.obsidian/workspace-mobile.json

# Obsidian cache
.obsidian/cache/

# Plugin data that changes frequently
.obsidian/plugins/obsidian-git/data.json

# Marimo notebooks
__marimo__/

# Obsidian trash
.trash/

# Unknown tool artifacts
.space/

# Obsidian Dataview database files (regenerated)
*.base

# OS files
.DS_Store
Thumbs.db
```

## Troubleshooting Workflow (User Preference)

When complex multi-stage setup fails, follow this diagnostic sequence:

1. **Verify each step independently** — Don't assume previous steps succeeded
2. **Confirm environment variables** — `echo "OBSIDIAN_VAULT_PATH=$OBSIDIAN_VAULT_PATH"`
3. **Test connectivity separately** — For network services: `curl -sk http://host:port/health`
4. **Examine error messages carefully** — Permission denied, No such file, Connection refused, Connection timeout
5. **Verify assumptions** — Is the service actually running? Is the path correct?
6. **Document the failure point** — Note exactly which command and error

## Best Practices

1. **Consistent Structure**: Use a logical folder hierarchy
2. **Daily Notes**: Enable periodic notes for daily journaling
3. **Backups**: Use Obsidian Git or external backup
4. **Templates**: Create templates for common note types
5. **Tags**: Use consistent tag naming (#todo, #project, #reference)
6. **Links**: Link related notes with wikilinks [[Note Name]]
7. **Version Control**: Enable Git for change tracking — set user identity per-repo
8. **Path Safety**: Always quote paths with spaces
9. **Clean Repos**: Use `.gitignore` to exclude workspace state, caches, and generated files
10. **Vault is canonical**: All notes, projects, and documentation live in the vault. On Windows: `C:\Users\luned\Vault\Encephalon-Mageia\`. On WSL: `/mnt/c/Users/luned/Vault/Encephalon-Mageia/`. When asked to create a file "in the vault" or "in a project folder," it MUST go under the correct vault root for the current host.

## Common Pitfalls

- **Unquoted paths**: Causes failures with spaces in paths
- **WSL localhost confusion**: Services on Windows host aren't at localhost:port in WSL
- **Permission issues**: WSL/Windows file permission mismatches
- **Path case sensitivity**: Linux is case-sensitive, Windows is not
- **Files placed outside the vault**: When the user asks to create a file "in [project]" or "in the research folder," it MUST go in the Obsidian vault (`C:\Users\luned\Vault\Encephalon-Mageia\Projects\<Category>\<Project>\` on Windows, or `/mnt/c/Users/luned/Vault/Encephalon-Mageia/Projects/<Category>/<Project>/` on WSL). The vault is the single source of truth for all project files, notes, and research. Always verify the path starts with the vault root before writing.
- **Wrong git branch**: The vault repo uses `Main` (not `master`) as the default branch
- **API key truncation**: When registering on external platforms (e.g., The Colony), the API key may be truncated in tool output. Write the full key to a file IMMEDIATELY upon registration.

- **Concurrent subagent vault writes**: When multiple subagents write to the same vault files (`index.md`, `log.md`, wiki pages) in the same turn, they overwrite each other. The main agent should do ALL shared-file updates sequentially. If a sibling's write triggers a "file modified by sibling subagent" warning, re-read the file before patching. For wiki index/log updates specifically: have children return content to the parent and let the parent write navigation files.

## Integration with Hermes Agent

This skill works with Hermes Agent for:
- Automated note creation and updates
- Knowledge base queries
- Vault analysis and reporting
- Cross-vault linking and organization
- Template-based note generation
