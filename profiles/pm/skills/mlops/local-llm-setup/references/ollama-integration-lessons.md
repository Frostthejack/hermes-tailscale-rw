# Ollama Integration — Lessons Learned

## Config: `providers` Dict AND `fallback_providers`

The correct way to add Ollama as a named provider:

```yaml
# In config.yaml
providers:
  ollama:
    base_url: http://127.0.0.1:11434/v1
    api_key: ollama  # Ollama accepts any non-empty key
```

Then reference it as `ollama/qwen3:8b` in model config.

**`fallback_providers` also works** for global fallback chains:

```yaml
fallback_providers:
  - base_url: http://127.0.0.1:11434/v1
    provider: ollama
    default: qwen3:8b
```

This sets Ollama as a system-wide fallback when the primary provider fails.

## Stale IP / Profile Fix: WSL → Windows

If you updated Windows and the host IP changed, update the profile config:

```yaml
model:
  base_url: http://127.0.0.1:11434/v1  # WSL2 auto-forwards 127.0.0.1
  default: qwen3:8b
```

Verify with `curl -s --connect-timeout 5 http://127.0.0.1:11434/api/tags`. If that times out, Ollama isn't running. If it returns tags, fix the IP in config.yaml and the profile.

If a stale IP (`172.25.144.1`) appears in the profile config, update it.

## Model Selection by VRAM

| Model | Quant | VRAM Use | Notes |
|-------|-------|----------|-------|
| Qwen3-8B | Q4_K_M | ~5.2GB | Best all-around, coding, reasoning |
| Gemma4:e4b | Q4_K_M | ~9.6GB | **OOM on 8GB** — use `q3_k_m` or switch to `qwen3:8b` |

**Critical:** Avoid `gemma4:e4b` with Q4_K_M on 8GB cards. Either use `qwen3:8b` (fits), or pick a smaller quant for Gemma.
