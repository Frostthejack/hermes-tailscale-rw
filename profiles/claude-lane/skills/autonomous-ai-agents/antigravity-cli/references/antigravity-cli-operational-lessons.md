# Antigravity CLI — Operational Lessons

> Session: 2026-05-23 (ScreenFox project)

## --add-dir is REQUIRED

Without `--add-dir <path>`, `agy -p` does NOT modify files in the current directory or worktree. It creates its own scratch project under `~/.gemini/antigravity-cli/scratch/` and works there instead.

**Always use:** `agy -p "<prompt>" --add-dir "$WORKTREE" --dangerously-skip-permissions --print-timeout 5m0s`

## Settings Location

- Settings: `~/.gemini/antigravity-cli/settings.json` (legacy path from Gemini CLI)
- Scratch projects: `~/.gemini/antigravity-cli/scratch/`
- Keybindings: `~/.gemini/antigravity-cli/keybindings.json`

## Model Names

- Use valid OpenRouter model names like `openrouter/owl-alpha`
- `@preset/logos-coder` and `@preset/coder` are NOT valid model names
- Model can be changed mid-session with `/model` in interactive mode

## Quirks

- No `--max-turns` equivalent — use `--print-timeout` (time-based, default 5m0s)
- No `--allowedTools` whitelist — tool permissions via settings.json
- No ACP support — cannot be used as stdio agent server
- SSH-aware auth works without browser (prints URL + code)
- Settings path is `~/.gemini/` not `~/.antigravity/`
