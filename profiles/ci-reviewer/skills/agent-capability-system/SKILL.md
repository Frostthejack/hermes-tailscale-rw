---
name: agent-capability-system
description: Governs how the agent processes user requests, manages its limitations, and handles interactions with tools and external systems.
category: system
---
# Agent Capability & System Constraints

This skill governs how the agent processes user requests, manages its limitations, and handles interactions with tools and external systems.

## Core Directives

1.  **Prioritize Explicit Instructions:** User corrections regarding style, tone, format, or workflow are treated as **FIRST-CLASS SKILL SIGNALS**. These preferences must be embedded directly into the skill's instructions to govern future behavior.
2.  **Skill-First Tool Selection:** Before acting on any request, the agent MUST scan the available skills list and load any skill relevant to the task — even if a general-purpose tool (like `web_extract` or `terminal`) could handle it. If a purpose-built skill exists (e.g., `youtube-content` for YouTube links, `llm-wiki` for knowledge-base ingestion), it takes priority over generic tools. Check `skills_list` → `skill_view` → then act. **Never default to a general-purpose tool without first checking for a relevant skill.**
3.  **Tool Execution Protocol:** The agent must only execute actions using tools explicitly defined in its toolset. If a requested action requires external system interaction (like modifying an LLM provider or loading an internal profile), the agent must first check if a corresponding, authorized tool exists.
4.  **Limitation Handling:** When asked to perform an action outside of defined capabilities (e.g., modifying external configurations like Ollama settings), the agent must clearly state its limitation and offer the correct path forward (i.e., pointing out that it lacks the necessary execution tool).
5.  **Skill Update Protocol:** Any time a skill is consulted or loaded, the agent must check for new learning signals (style corrections, workflow fixes) and use `skill_manage` to update itself according to the established preference order (Update Loaded Skill > Update Umbrella > Add Support Files > Create New Umbrella).

## Memory Architecture (How Persistent State Works)

Understanding the memory system is critical for managing project information across sessions.

### The Three Tiers of System Prompt Injection

| Tier | Contents | When Updated | Token Cost |
|------|----------|--------------|------------|
| **Stable** | Identity (SOUL.md), tool guidance, skills prompt | Once per session | Prefix-cached |
| **Context** | AGENTS.md / CLAUDE.md / .cursorrules from `TERMINAL_CWD` | Once per session | Prefix-cached |
| **Volatile** | MEMORY.md, USER.md, hindsight recall block | Every turn (rebuilt) | **NOT cached** |

### Memory Stores

| Store | File(s) | Capacity | Auto-Injected | Write Tool |
|-------|---------|----------|---------------|------------|
| MEMORY.md | `~/.hermes/memories/MEMORY.md` | 2,200 chars | Yes (volatile tier) | `memory()` tool |
| USER.md | `~/.hermes/memories/USER.md` | 1,375 chars | Yes (volatile tier) | `memory()` tool |
| Hindsight | SQLite at `~/.hermes/hindsight/` | Unlimited | On recall only | `hindsight_retain()` |
| Context files | `AGENTS.md` under `TERMINAL_CWD` | 20,000 chars | Yes (context tier, cached) | `write_file()` |

### Critical Rules

- **MEMORY.md is at 2,200 char limit.** Project-specific details (repo paths, board slugs, tech stacks) must NOT be stored here — they consume space that behavioral rules need.
- **The `memory()` tool can ONLY write to MEMORY.md and USER.md** in `~/.hermes/memories/`. It cannot write to arbitrary paths. Use `write_file()` / `read_file()` for project info files.
- **Context files (AGENTS.md) are loaded from `TERMINAL_CWD`** (check `echo $TERMINAL_CWD`). For the gateway, this is typically `/home/frostthejack`. No context file currently exists there — if one is created, it loads once per session and is prefix-cached (unlike MEMORY.md which is volatile).
- **Hindsight retains every N turns** (configurable via `retain_every_n_turns` in `~/.hermes/hindsight/config.json`). It is the only store with semantic search and unlimited capacity.

### Project Info Pattern (Multi-Tier Durability)

To prevent project details from being lost to memory rewrites, use this redundancy pattern:

1. **Home AGENTS.md** (`/home/frostthejack/AGENTS.md`) — context tier, cached, survives memory rewrites
2. **`~/.hermes/projects/README.md`** — file-based backup, any agent can `read_file()` it
3. **`~/.hermes/projects/info/<project>.md`** — per-project operational details (board slugs, repo paths, cron jobs)
4. **MEMORY.md pointer** — single compact entry pointing to the above
5. **Hindsight retention** — semantic search backup of the pointer pattern
6. **Vault git** — versioned history if files are overwritten

**MEMORY.md should contain only pointers and behavioral rules, never project details.**

### What NOT to Store in MEMORY.md

- Repo paths, board slugs, tech stacks, API quirks for specific projects → use `~/.hermes/projects/info/<project>.md`
- Stale state (cron job statuses, paused/resumed state) → these change; use project files or vault project-state.md
- One-off task narratives or session outcomes → use session_search to recall

## Session-Specific Details

This section will be used to store specific context gathered during this session that impacts future interactions.
