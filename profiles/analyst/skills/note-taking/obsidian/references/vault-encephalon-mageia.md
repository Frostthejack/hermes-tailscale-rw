# Encephalon-Mageia Vault Reference

## Location

```
/mnt/c/Users/luned/Vault/Encephalon-Mageia
```

This is the **primary and only** vault. The former Hermes vault was merged into this vault on 2026-05-15 and deleted.

## Git Remote

- **URL:** `https://github.com/Frostthejack/Encephalon-Mageia`
- **Branch:** `Main` (tracks `origin/Main`)
- **Local git identity:** `frostthejack` / `frostthejack@users.noreply.github.com`

## Structure

| Folder | Purpose |
|--------|---------|
| **Daily Notes/** | `YYYY/MM/YYYY-MM-DD.md` — daily journal with tasks, habits, highlights |
| **Notes/** | Zettelkasten — Inbox, Ideas, Important, Thoughts, Unimportant, Cooking, Journal, Misc |
| **Projects/** | Personal/ (OSINT, RollSiege, Modular Box, Mimiral, Agent-Screen-Pet, Agent-Persona), Work/, Writing/ |
| **People/** | Family/, Friends/, Work/ — contact notes with template frontmatter |
| **Research/** | To Research/ (active), Archive/ (done), Languages/, Learning/, local-llm-research/, agent-ecosystem/ |
| **Media/** | Books, Shows, Backlog — tracked with `.base` Dataview databases |
| **Tasks/** | Dataview dashboards — Missed, Recurring, Upcoming |
| **Templates/** | Daily, Books, Shows, Movies, Games, People, Projects, PRD, Concept Brief, Ideas, Folder Table, D&D Character |
| **Work/** | Meetings/, Notes/, Parts/ |
| **Misc/** | DashBoard.canvas, Tracker Dashboard |
| **reports/** | hermes-memory-options/ (memory system comparison reports), colony-exploration-report.md, colony-targeted-intelligence.md |

## agent-ecosystem/ Research Folder

Created 2026-05-18. Houses research about AI agent platforms, tools, and ecosystems.

```
agent-ecosystem/
├── README.md                          # Index + key findings overview
├── platforms/
│   └── the-colony.md                  # The Colony platform deep-dive (API, colonies, agents)
├── local-llm-insights/                # Insights from other local LLM operators
│   ├── ollama-performance.md          # GGUF bug, CUDA SM builds, TTFT optimization
│   ├── vram-management.md             # Memory cliff, KV cache math, mitigation strategies
│   ├── multi-agent-coordination.md    # State fragmentation, CRDTs, our kanban approach
│   ├── nl-summarization-drift.md      # NL summarization causes persona drift
│   └── kanban-feedback.md             # Community feedback on our kanban approach
├── agent-tools/                       # Useful tools discovered
│   ├── mycrab-space.md                # Self-hosting platform for agents
│   └── cursor-composer-25.md          # Cursor 2.5 sustained agent work
└── rate-limits/                       # Platform rate limit intelligence
    └── colonist-one-36-platforms.md   # Rate limits across 36 platforms
```

## Conventions

- **Tags:** `#idea`, `#research`, `#project`, `#note`, `#daily-notes`, `#person`
- **People:** Relation, phone, birthday, social media, aliases
- **Projects:** Concept Brief or PRD template
- **Research:** `To Research/` → `Archive/` when done
- **Daily notes:** Includes task queries, habit tracker, highlights, activity log
- **Inbox:** `Notes/Inbox/` is capture zone — refine and move to Ideas/Thoughts/Important

## Notable Details

- Obsidian Git plugin configured (auto-commit on change, auto-pull on boot, manual push)
- 24+ community plugins active (Dataview, Templater, Tasks, Git, Calendar, etc.)
- Canvas files for DashBoard, OSINT learning, writing project planning
- `.base` files for Dataview databases (Media, Projects, Research, Daily Notes)
- RollSiege project has files both from original vault and migrated Hermes vault (supplements)

## Git Workflow

### The Divergence Problem

The Obsidian Git plugin auto-commits from the user's local Windows machine. When working from WSL, the local git state often falls behind the remote. This causes `git push` to reject with "fetch first."

### Correct Push Sequence from WSL

```bash
cd "/mnt/c/Users/luned/Vault/Encephalon-Mageia"

# 1. Check status
git status

# 2. Stage your changes
git add <files>

# 3. Commit
git commit -m "descriptive message"

# 4. Stash any unstashed working changes
git stash

# 5. Rebase onto remote (pulls plugin's auto-commits)
git pull --rebase origin Main

# 6. Restore stashed changes
git stash pop

# 7. Handle any conflicts from stash pop:
#    git add -A
#    git commit -m "sync local changes"
#    git rebase --continue

# 8. Push
git push origin Main
```

### Setting Up Git Identity

Always set per-repo before first commit:
```bash
git config user.name "frostthejack"
git config user.email "frostthejack@users.noreply.github.com"
```

### Vault Migration Pattern (2026-05-15)

When merging one Obsidian vault into another:

```bash
# Copy project directories (use cp -r, not mv, to keep source intact until verified)
cp -r /source/Projects/ProjectName /dest/Projects/Personal/

# Watch for nested directory issues
# Fix: mv dest/Folder/Folder/* dest/Folder/ && rmdir dest/Folder/Folder

# Then delete source vault only after verifying everything is in place and pushed
rm -rf /source/VaultName
```

### .gitignore

The vault root has a `.gitignore` excluding:
- `.obsidian/workspace.json`, `workspace-mobile.json` (per-device state)
- `.obsidian/cache/`, plugin data
- `__marimo__/`, `.trash/`, `.space/`
- `*.base` (Dataview databases)
- OS files (.DS_Thumbs.db)

## User Interaction Preferences

- **Q&A vs Execution separation:** When the user asks a question, answer it directly. Do NOT start executing commands unless explicitly asked.
- **Vault is the canonical workspace:** All notes, projects, and documentation live in the vault.
- **Prioritize local over remote:** When there are conflicts between local vault files and GitHub, the local files win.
