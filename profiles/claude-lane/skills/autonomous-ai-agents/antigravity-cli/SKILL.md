---
name: antigravity-cli
description: >
  Use when the task requires delegating coding work to Google Antigravity CLI (the
  agy binary), either in print mode (agy -p) or interactive TUI mode via tmux.
  Handles installation, auth, subagents, hooks, plugins, AGENTS.md context
  injection, and Hermes-orchestrated delegation patterns including kanban lanes.
version: 1.2.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [coding-agent, google, gemini, antigravity, terminal, TUI, automation, agent-lane]
    related_skills: [claude-code, kanban-codex-lane, agent-lane]
---

# Antigravity CLI — Hermes Orchestration Guide

Delegate coding tasks to [Google Antigravity CLI](https://antigravity.google/) (`agy`) — Google's Go-based terminal agent that replaces Gemini CLI (**sunset June 18, 2026**). Antigravity shares its agent engine with the Antigravity 2.0 desktop app and runs on **Gemini 3.5 Flash**.

## Prerequisites

- **Install:** `curl -fsSL https://antigravity.google/cli/install.sh | bash`
- **Verify:** `agy --version` (v1.0.1+)
- **Binary location:** `~/.local/bin/agy` (Unix) or `%LOCALAPPDATA%\Antigravity\` (Windows)
- **Auth:** First run opens browser for Google Sign-In, or set `ANTIGRAVITY_API_KEY` for CI
- **Migrate from Gemini CLI:** `agy plugin import gemini`

### Product Family

All Antigravity surfaces share the same core agent engine and settings:

| Surface | Description |
|---------|-------------|
| **Antigravity CLI** (`agy`) | Terminal-first, lightweight TUI — fast, keyboard-centric |
| **Antigravity 2.0** | Desktop app — visual orchestration, project management |
| **Antigravity SDK** | Python framework for custom agent builds |
| **Antigravity IDE** | Full AI-powered development environment |

**Integration:** Conversations can be exported from CLI to Antigravity 2.0 via `/export`. Settings changes sync bidirectionally.

## Auth Modes
| Mode | How |
|------|-----|
| **Desktop** | Google Sign-In OAuth → system keyring |
| **SSH/Remote** | CLI prints URL + code → open on local machine |
| **CI/Scripting** | `export ANTIGRAVITY_API_KEY=<key>` |
| **Enterprise** | Connect GCP project |

## Two Orchestration Modes

### Mode 1: Print Mode (`-p`) — Non-Interactive (PREFERRED for most tasks)

One-shot task execution. No PTY needed. No interactive prompts. Best for automation and kanban lanes.

```python
terminal(
    command='agy -p "Add error handling to all API calls in src/" '
            '--dangerously-skip-permissions '
            '--print-timeout 5m0s',
    workdir="/path/to/project",
    timeout=300
)
```

**When to use print mode:**
- One-shot coding tasks (fix bug, add feature, refactor)
- CI/CD automation and scripting
- Piped input processing (`cat file | agy -p "analyze this"`)
- Kanban lane delegation (bounded implementation tasks)
- Any task where you don't need multi-turn conversation

**Key print mode flags:**
| Flag | Effect |
|------|--------|
| `-p`, `--print` | Non-interactive, exits when done |
| `--prompt` | Alias for `--print` |
| `--print-timeout <duration>` | Timeout (default 5m0s) |
| `--output-format json` | Structured output |
| `--add-dir <path>` | **REQUIRED** to make `agy` modify files in the target directory. Without this, `agy` creates its own scratch project under `~/.gemini/antigravity-cli/scratch/` |
| `--dangerously-skip-permissions` | Auto-approve all tool permission requests |
| `--sandbox` | Run in OS-level terminal sandbox (nsjail on Linux) |

### Mode 2: Interactive TUI via tmux — Multi-Turn Sessions

Full conversational REPL with slash commands, subagent management, and plugins. **Requires tmux orchestration.**

```python
# Start a tmux session
terminal(command="tmux new-session -d -s agy-work -x 140 -y 40")

# Launch Antigravity CLI inside it
terminal(command="tmux send-keys -t agy-work 'cd /path/to/project && agy' Enter")

# Handle trust dialog (first visit to directory)
terminal(command="sleep 4 && tmux send-keys -t agy-work Enter")

# Send task
terminal(command="sleep 1 && tmux send-keys -t agy-work 'Refactor the auth module' Enter")

# Monitor progress
terminal(command="sleep 15 && tmux capture-pane -t agy-work -p -S -60")

# Exit when done
terminal(command="tmux send-keys -t agy-work '/exit' Enter")
```

**When to use interactive mode:**
- Multi-turn iterative work
- Tasks requiring human-in-the-loop decisions
- Exploratory coding sessions
- When you need slash commands (`/agents`, `/mcp`, `/skills`, `/schedule`)

## Print Mode Details

### Structured JSON Output
```python
terminal(
    command='agy -p "Analyze auth.py for security issues" '
            '--output-format json '
            '--dangerously-skip-permissions '
            '--print-timeout 3m0s',
    workdir="/path/to/project",
    timeout=180
)
```

### Session Continuation
```bash
# Continue the most recent session in this directory
agy -p "Continue working" --continue

# Resume specific session by ID
agy -p "Continue working" --conversation <id>
```

## Complete CLI Flags Reference

| Flag | Effect |
|------|--------|
| `-p`, `--print` | Non-interactive one-shot mode |
| `--prompt` | Alias for `--print` |
| `--print-timeout <d>` | Timeout (default 5m0s) |
| `-c`, `--continue` | Resume most recent conversation |
| `--conversation <id>` | Resume specific conversation |
| `-i`, `--prompt-interactive` | Run initial prompt then stay interactive |
| `--add-dir <paths>` | Grant access to additional directories (repeatable) |
| `--dangerously-skip-permissions` | Auto-approve everything |
| `--sandbox` | OS-level terminal sandbox (nsjail on Linux) |
| `--log-file <path>` | Override log file path |

## Slash Commands (Interactive Mode)

### Core Commands
| Command | Purpose |
|---------|---------|
| `/help` | List all commands and keybindings |
| `/context` | Show token usage, checkpoints |
| `/usage` | Quota and rate-limit status |
| `/resume` (`/switch`) | Resume/switch sessions |
| `/rewind` (`/undo`) | Roll back to checkpoint |
| `/rename <name>` | Rename thread |
| `/permissions` | Set agent autonomy level |
| `/model` | Switch model mid-session |
| `/export` | Push session to Antigravity 2.0 GUI |
| `/logout` | Sign out |

### Tools & Monitoring
| Command | Purpose |
|---------|---------|
| `/config` or `/settings` | Full settings overlay |
| `/statusline` | Customize status bar |
| `/tasks` | List/monitor/kill background tasks |
| `/skills` | Browse loaded agent workflows |
| `/mcp` | Manage MCP servers |
| `/agents` | Manage subagents |
| `/keybindings` | Edit keyboard shortcuts |

### Slash Commands (Advanced)
| Command | Purpose |
|---------|---------|
| `/goal` | Agent runs until task complete |
| `/grill-me` | Agent asks clarifying questions first |
| `/fork` | Spin up a separate workspace and branch the conversation from an earlier point |
| `/schedule` | One-time future event or recurring schedule |
| `/browser` | Trigger browser subagent |

## AGENTS.md — Project Context

Place at project root. Content prepended to every prompt:

```markdown
# Project: My API

## Architecture
- FastAPI + SQLAlchemy, PostgreSQL, Redis
- pytest with 90% coverage target

## Key Commands
- `make test` — full test suite
- `make lint` — ruff + mypy

## Code Standards
- Type hints on all public functions
- Google-style docstrings
- No wildcard imports
```

**Inspect what's loaded:** `agy inspect` — prints configs, skills, plugins, hooks, MCP servers.

## Subagents

Three types:
1. **Built-in roles** (e.g., browser subagent)
2. **Generic clones** (same capabilities as main agent)
3. **Dynamically registered** on-the-fly

### Spawning Subagents (Interactive)
```
/agent refactor "Convert all callback-based handlers in @internal/api to use context.Context"
```

### Managing Subagents
- `/agents` panel: list active/completed subagents with status
- Select for full detail view (conversation, steps, tool logs)
- `ctrl+k` to approve pending permission without leaving main conversation
- `ctrl+j` to teleport to next subagent awaiting approval

### Programmatic Subagent Tools
- `invoke_subagent`: Spawn specialized sub-agents
- `define_subagent`: Create custom sub-agent (name, description, system_prompt, tool flags)
- `manage_subagents`: List or terminate active sub-agents

## Hooks

**Location:** `.agents/hooks.json` (workspace) or `~/.gemini/config/hooks.json` (global)

### Hook Events
| Event | When It Fires |
|-------|---------------|
| `PreToolUse` | Before a tool executes |
| `PostToolUse` | After a tool completes |
| `PreInvocation` | Before model call |
| `PostInvocation` | After tool calls finish |
| `Stop` | Execution loop terminates |

### Example hooks.json
```json
{
  "auto-linter": {
    "PostToolUse": [{
      "matcher": "run_command",
      "hooks": [{"type": "command", "command": "ruff check --fix", "timeout": 10}]
    }]
  },
  "safety-gate": {
    "enabled": false,
    "PreToolUse": [{
      "matcher": "run_command",
      "hooks": [{"command": "./scripts/check-safety.sh"}]
    }]
  }
}
```

### Tool Matchers
- `"run_command"` — Exact match
- `"run_command|view_file"` — Multiple tools
- `"browser_.*"` — Regex pattern
- `""` or `"*"` — All tools

## Plugins

**Install path:** `~/.gemini/antigravity-cli/plugins/<plugin_name>/`

### Plugin Structure
```
~/.gemini/antigravity-cli/plugins/<name>/
├── plugin.json         # Required marker
├── mcp_config.json     # Optional MCP servers
├── hooks.json          # Optional hooks
├── skills/             # Optional skills
├── agents/             # Optional subagents
└── rules/              # Optional rules
```

**Commands:**
```bash
agy plugin import gemini     # Migrate from Gemini CLI
agy plugin list              # List installed plugins
agy plugin enable <name>     # Enable a plugin
agy plugin disable <name>    # Disable a plugin
agy plugin install <name>    # Install a plugin
agy plugin uninstall <name>  # Remove a plugin
```

## MCP Support

```bash
# Via /mcp in interactive mode, or via mcp_config.json in plugins
```

Use `agy inspect` to verify loaded MCP servers.

## Terminal Sandbox

| OS | Mechanism |
|----|-----------|
| Linux | `nsjail` |
| macOS | `sandbox-exec` |
| Windows | `AppContainer` |

**Config:** `"enableTerminalSandbox": true` in `~/.gemini/antigravity-cli/settings.json` (default: false)

## Settings & Configuration

**Location:** `~/.gemini/antigravity-cli/settings.json`

### Permission Levels
| Level | Behavior |
|-------|----------|
| `request-review` | Ask before each action |
| `always-proceed` | Auto-approve most actions |
| `strict` | Maximum safety gate |

### Fine-Grained Permissions
```json
{
  "permissions": {
    "allow": ["command(git)", "command(npm test)"],
    "deny": ["command(rm -rf)"]
  }
}
```

### CLI flags override settings
- `--sandbox` forces sandbox on even if disabled in settings.json
- `--dangerously-skip-permissions` forces bypass even if permissions are strict

## Keyboard Shortcuts (Interactive)

| Key | Action |
|-----|--------|
| `ctrl+c`, `esc` | Stop stream, close menus |
| `ctrl+d` | Exit CLI |
| `ctrl+l` | Clear terminal |
| `ctrl+z` | Suspend CLI to background |
| `ctrl+v` | Paste |
| `ctrl+g` | Open prompt in external editor |
| `ctrl+k` | Approve pending subagent permission |
| `ctrl+j` | Teleport to subagent awaiting approval |
| `alt+enter`, `ctrl+j`, `shift+enter` | Newline |
| `y` / `n` | Confirm / deny command execution |
| `e` | Edit proposed command |

### Input Prefixes
| Prefix | Action |
|--------|--------|
| `!` | Execute bash directly (bypass AI) |
| `@` | File/directory reference with autocomplete |
| `/` | Slash commands |

## Kanban Lane Integration

For delegation through Hermes Kanban, use the **agent-lane** skill pattern. Key points:

### One-Shot Lane (Print Mode)
1. Create isolated git worktree
2. Construct prompt from kanban task body
3. Run `agy -p` with `--dangerously-skip-permissions` and `--print-timeout`
4. Review diff, run tests
5. Cherry-pick commits back
6. `kanban_complete` with metadata

### Interactive Lane (tmux)
1. Set up tmux session
2. Launch `agy` interactively
3. Handle trust dialog (Enter)
4. Send task prompt via `tmux send-keys`
5. Monitor via `tmux capture-pane`
6. Reconcile and verify
7. `kanban_complete` with metadata

**Hermes always owns the Kanban lifecycle.** `agy` never calls `kanban_complete` or `kanban_block`.

## Cost & Performance Tips

1. **Use `--print-timeout`** to prevent runaway execution
2. **Use `--dangerously-skip-permissions`** to avoid interactive dialogs in print mode
3. **Keep AGENTS.md specific** — saves tokens and correction cycles
4. **Use subagents for parallel work** — doesn't block main conversation
5. **Monitor `/usage`** for quota tracking
6. **Use the sandbox** (`--sandbox`) for untrusted operations
7. **Use `agy inspect`** as first debugging step when behavior is unexpected

## Pitfalls & Gotchas

1. **Gemini CLI sunset: June 18, 2026** — Gemini CLI stops serving free/Pro/Ultra users. Migrate now with `agy plugin import gemini`.
2. **Interactive mode REQUIRES tmux** — `agy` is a full TUI app like `claude`
3. **`--add-dir` is REQUIRED for file modification** — Without `--add-dir <path>`, `agy -p` will NOT modify files in the current directory. It creates its own scratch project under `~/.gemini/antigravity-cli/scratch/` and works there instead. Always pass `--add-dir "$WORKTREE"` when delegating to a worktree.
4. **No ACP support** — Antigravity CLI cannot be used as a stdio-based agent server (unlike old Gemini CLI `--acp`)
5. **Settings path is `~/.gemini/`** — legacy from Gemini CLI, not renamed to `~/.antigravity/`
6. **No `--max-turns` equivalent** — only `--print-timeout` (time-based, not turn-based)
7. **No `--allowedTools` whitelist** — tool permissions only via settings.json
8. **No `total_cost_usd` in output** — no cost tracking in print mode JSON
9. **Trust dialog only appears once per directory** — then cached permanently
10. **`/export` requires Antigravity 2.0 desktop app** — not useful in headless environments
11. **Scheduled tasks only in 2.0 desktop app** — `/schedule` in CLI is one-time timers only
12. **Google Sign-In required** — no Anthropic-style console login; use API key for headless
13. **Background tmux sessions persist** — clean up with `tmux kill-session -t <name>`
14. **Scratch directory pollution** — `agy` may create projects under `~/.gemini/antigravity-cli/scratch/`. Clean up periodically.
15. **`/fork` requires Antigravity 2.0 desktop app** — Conversation forking is only supported via `/export` to the desktop app; the CLI `/fork` command branches the conversation within the TUI only.

## References

- **`references/add-dir-test-evidence.md`** — Live test results (2026-05-22) proving `--add-dir` is required. Includes side-by-side comparison of `claude -p` vs `agy -p` working directory behavior, reproducibility tests, and cleanup steps.

1. **Prefer print mode (`-p`) for single tasks** — cleaner, no dialog handling
2. **Use tmux for multi-turn work** — only reliable TUI orchestration method
3. **Always set `workdir`** — keep agy focused on the right project
4. **Set `--print-timeout`** — prevents infinite hangs
5. **Monitor tmux sessions** — `tmux capture-pane -t <session> -p -S -50`
6. **Clean up tmux sessions** — kill when done
7. **Report results to user** — summarize what agy did and what changed
8. **Don't kill slow sessions** — check progress before assuming failure
