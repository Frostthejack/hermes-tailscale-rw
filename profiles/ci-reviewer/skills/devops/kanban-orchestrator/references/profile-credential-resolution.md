# Profile Credential Resolution for Kanban Workers

## How Workers Resolve API Keys

The kanban worker process resolves API keys through this chain:

1. **`~/.hermes/profiles/<name>/.env`** — loaded by `load_hermes_dotenv()` when `HERMES_HOME` points to the profile directory
2. **`os.environ`** — inherited from the parent gateway process
3. **`config.yaml` `providers.<name>.api_key`** — ONLY used when `init_agent()` receives explicit `api_key` and `base_url` parameters

**CRITICAL**: The `_try_openrouter()` function checks `os.getenv("OPENROUTER_API_KEY")` — it does NOT read `config.yaml` provider settings. If the env var is empty, worker fails immediately with "Provider resolver returned an empty API key."

## The `.env` File Requirement

Every worker profile that uses OpenRouter MUST have:
```
OPENROUTER_API_KEY=*** 73-character key>
```

**DO NOT use the `write_file` tool to create `.env` files with secrets** — it writes masked/redacted content (the `...` truncation in terminal output is literal). Use `terminal()` with `echo` or `cat >` instead.

## Verifying Worker Auth

If worker fails with "Provider resolver returned an empty API key":
1. Check `~/.hermes/profiles/<assignee>/.env` exists with full key (use `xxd` to verify bytes)
2. Check `~/.hermes/profiles/<assignee>/config.yaml` has `providers.openrouter.api_key`
3. If `.env` was created with `write_file`, re-create with terminal — the tool writes masked content

## Masked Key Symptom

If `.env` has `OPENROUTER_API_KEY=sk-or-v1...2138` (15 chars with literal `...`), the key is TRUNCATED. Full key is 73 chars: `sk-or-v1-<68 chars>`.

Verify with: `xxd ~/.hermes/profiles/<name>/.env`

## Rate Limiting Recovery

If API key gets rate-limited (HTTP 401 "Missing Authentication header"):
1. Wait for cooldown or generate new key at https://openrouter.ai/keys
2. Update ALL profile `.env` files AND config.yaml provider sections
3. Hard-kill gateway to clear cached keys: `pkill -f hermes_cli.main gateway && hermes gateway start`
4. Re-dispatch tasks
