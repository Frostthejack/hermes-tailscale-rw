# Agent Lane — Operational Lessons

> Sessions: 2026-05-23, 2026-05-24, 2026-05-27

## OpenRouter Key Revocation (2026-05-27)

After 2754+ failed auth attempts in a worker retry loop, OpenRouter **revoked the key mid-session**. Key was valid earlier (curl worked), then ALL requests returned 401. Always test key validity fresh with:
```bash
curl -s "https://openrouter.ai/api/v1/auth/key" -H "Bearer <full-key>"
```

## request_dump Key Masking

The Authorization header in request_dump files is ALWAYS masked to ~15 chars due to `redact_secrets: true`. This does NOT mean the wrong key was sent. To debug, add temporary print statements in `_try_openrouter()` or `create_openai_client()`.

## default_headers Do NOT Cause 401

Tested and confirmed: `build_or_headers()` adds HTTP-Referer, X-Title, X-OpenRouter-* headers. These do NOT interfere with the Authorization header.

## Model Names

**INVALID** (cause 401 "Missing Authentication header"):
- `@preset/logos-coder` — does not exist in OpenRouter
- `@preset/coder` — does not exist in OpenRouter

**VALID**:
- `openrouter/owl-alpha` — the default model from the main config
- Any model listed in `~/.hermes/config.yaml` under `model.default`

## OpenRouter API Key

- Stored in protected credential file at Hermes home directory
- Agent CANNOT modify this file — sandbox blocks all writes
- When workers get 401 "Missing Authentication" or 403 "budget limit exceeded":
  1. User must manually edit the credential file
  2. Hard-kill the gateway process to clear cached key
  3. Verify key with `xxd` not `grep` (display truncates long values)
- **CRITICAL**: 401 on claude-lane is NOT a key truncation issue — it's a per-profile credential resolution bug. The full key is present in config.yaml but the gateway resolves it differently for claude-lane vs agy-lane. Workaround: use agy-lane.

## agy -p Critical Flags

- `--add-dir "$WORKTREE"` is **REQUIRED** — without it, `agy` creates its own scratch project under `~/.gemini/antigravity-cli/scratch/` and ignores the working directory
- `--print-timeout 5m0s` to bound execution time
- `--dangerously-skip-permissions` to avoid interactive prompts

## Worker Behavior

**Finding:** Kanban workers code directly using Hermes file/terminal tools instead of spawning `claude -p` / `agy -p` as instructed in AGENTS.md.

**Cause:** Workers have full file write tool access. The AGENTS.md text says "you MUST spawn agent CLIs" but there's no enforcement mechanism. Workers take the path of least resistance.

**Attempted fix (did NOT work):** Adding `disabled_toolsets: [file, web, ...]` to the lane profile config. The kanban dispatcher overrides profile toolset settings.

## Debugging Auth Errors

1. Check actual file bytes: `xxd /home/frostthejack/.hermes/.env | grep -A3 OPENROUTER`
2. Check worker logs: `hermes kanban log <task_id>`
3. 401 = key is empty or malformed (check file bytes)
4. 403 = key is valid but budget exhausted
5. After key change: hard-kill gateway process, not just restart
