---
name: local-llm-setup
description: Evaluate, select, and integrate local LLM hosting platforms as Hermes providers. Use when the user wants to set up a local model for fallback, cost savings, or privacy. Covers platform comparison, model selection for specific hardware, quantization tradeoffs, and Hermes provider configuration.
version: 1.0.1
author: OWL
license: MIT
metadata:
  hermes:
    tags: [local-llm, ollama, lm-studio, llama-cpp, vllm, gpu, quantization, hermes-provider, fallback]
    related_skills: [llama-cpp, serving-llms-vllm, hermes-agent, gguf-quantization]
---

# Local LLM Setup for Hermes

Select and configure local LLM hosting platforms as Hermes providers. Covers platform evaluation, model selection for specific hardware, and integration.

## When to use

- User wants a local model as a fallback or primary provider
- User asks "what model can I run on my GPU?"
- User wants to compare Ollama vs LM Studio vs other options
- User needs to configure Hermes to use a local endpoint
- User asks about quantization (Q4, Q5, QGUF) tradeoffs

## Platform Comparison

### Quick Reference

| Platform | Ease | GPU | OpenAI API | Windows | Best For |
|----------|------|-----|------------|---------|----------|
| **Ollama** | ★★★★★ | CUDA/ROCm/Metal | ✅ | ✅ | Always-on local server |
| **LM Studio** | ★★★★★ | CUDA/Metal | ✅ | ✅ | GUI model exploration |
| **llama.cpp** | ★★★☆☆ | CUDA/Metal/Vulkan | ✅ | ✅ | Maximum control |
| **vLLM** | ★★☆☆☆ | CUDA (Linux) | ✅ | ❌ WSL only | Production throughput |
| **Jan** | ★★★★☆ | CUDA/Metal | ✅ | ✅ | ChatGPT replacement |
| **textgen** | ★★★☆☆ | CUDA/ExLlama | ✅ | ✅ | Feature-rich chat UI |
| **Open WebUI** | ★★★☆☆ | N/A (frontend) | N/A | Docker | Dashboard UI |
| **GPT4All** | ★★★★☆ | CPU-focused | ❌ | ✅ | Lightweight/CPU use |

### Ollama (Recommended Primary)

**Best for:** Always-on local LLM server with minimal setup.

```bash
# Windows install
winget install Ollama.Ollama

# Pull a model
ollama pull qwen3:8b

# Verify API (Windows)
curl http://127.0.0.1:11434/v1/models

# Verify API (WSL — auto-forwards, no portproxy needed)
curl http://127.0.0.1:11434/v1/models
```

**Pros:** One-command model management, auto GPU offload, 1000+ pre-quantized models, OpenAI API compatible, Windows native.
**Cons:** Less control over quantization details vs raw llama.cpp.

### LM Studio (Recommended Secondary)

**Best for:** GUI-based model browsing, testing, and exploration.

- OpenAI-compatible API at `http://127.0.0.1:1234/v1` (must be started manually)
- `llmster` daemon for headless server use
- Python/TypeScript SDKs available

**Pros:** Best GUI, easy model comparison, good for experimentation.
**Cons:** Proprietary, API server not auto-start, less scriptable.

### llama.cpp (Direct)

**Best for:** Maximum control over every parameter.

```bash
# Direct from HuggingFace Hub
llama-server -hf bartowski/Qwen3-8B-GGUF:Q4_K_M

# With explicit file
llama-server --hf-repo bartowski/Qwen3-8B-GGUF --hf-file Qwen3-8B-Q4_K_M.gguf -c 8192
```

**Pros:** Lowest overhead, full control, direct Hub loading.
**Cons:** Manual model management, manual GPU offload config.

### vLLM

**Best for:** Production multi-user serving (Linux only).
**Not recommended** for single-user local fallback — overkill and Linux-first.

## Model Selection by VRAM

### 8GB VRAM (e.g., RTX 4060)

**Sweet spot: 8B parameter models at Q4_K_M (~4.5-5GB)**

| Model | Size (Q4_K_M) | Fits 8GB? | Best For |
|-------|---------------|-----------|----------|
| **Qwen3-8B** | ~5.2GB | ✅ Yes | Best overall (coding, reasoning, general) |
| **Qwen2.5-Coder-7B** | ~5.5GB (Q5) | ✅ Yes | Best for code generation |
| **DeepSeek-R1-8B** | ~5GB | ✅ Yes | Best for reasoning/math |
| **Llama-3.1-8B** | ~5GB | ✅ Yes | Best general purpose |
| **Gemma-3-4B** | ~3GB | ✅ Yes | Best small model, leaves VRAM headroom |
| **Gemma4:e4b** | ~9.6GB | ❌ **OOM** | Avoid on 8GB — use smaller quant or switch model |

**Key rule:** Stick with 8B-class models for full GPU offload on 8GB. `gemma4:e4b` at Q4_K_M (~9.6GB) **exceeds 8GB VRAM** — will OOM before KV cache allocation. Use Qwen3-8B instead.

### Quantization Guide

| Use Case | Quant | Why |
|----------|-------|-----|
| General chat/assistant | Q4_K_M | Best speed/quality balance |
| Coding | Q5_K_M | Higher precision helps code accuracy |
| Reasoning/math | Q5_K_M | Precision matters for logic |
| Long context (64K+) | Q4_K_M | Smaller = more room for KV cache |
| Maximum quality | Q6_K / Q8_0 | If it fits in VRAM |

**Size reference for 8B models:**
- Q4_K_M: ~4.5-5GB
- Q5_K_M: ~5.5-6GB
- Q6_K: ~6.5-7GB
- Q8_0: ~8-9GB (tight for 8GB VRAM)

## Hermes Integration

### As a Custom Provider

Add to `~/.hermes/config.yaml`:

```yaml
model:
  provider: custom
  base_url: http://127.0.0.1:11434/v1
  api_key: ollama
  model: qwen3:8b
```

### Via Named Provider + Profile

Add to profile config (`~/.hermes/profiles/<name>/config.yaml`):

```yaml
model:
  base_url: http://127.0.0.1:11434/v1
  default: qwen3:8b
  provider: ollama
  api_mode: chat_completions
  fallback:
    base_url: https://openrouter.ai/api/v1
    default: "@preset/hermes"
    provider: openrouter
providers:
  ollama:
    base_url: http://127.0.0.1:11434/v1
    api_key: ollama
```

### Global Ollama Fallback

To make Ollama the system-wide fallback (in `~/.hermes/config.yaml`):

```yaml
fallback_providers:
  - base_url: http://127.0.0.1:11434/v1
    provider: ollama
    default: qwen3:8b
```

This sets Ollama as a fallback chain entry. If the primary provider fails, Hermes tries the next in order.

### WSL ↔ Windows Networking

When Hermes runs in WSL and Ollama runs on Windows:
- Use `http://127.0.0.1:11434` — WSL2 auto-forwards `127.0.0.1`
- Do NOT use `localhost` — can resolve differently in WSL2
- No `netsh portproxy` needed for same-machine access
- **Stale IP warning**: Profile configs may contain old Windows host IPs (e.g., `172.25.144.1`). Always verify connectivity with `curl -s --connect-timeout 5 http://127.0.0.1:11434/api/tags` and update if unreachable.

**Checking if Ollama is running**: `ps aux | grep ollama` in WSL only finds WSL processes — it will NOT show Windows services. Always test port connectivity from WSL (`curl http://127.0.0.1:11434/api/tags`) or check Windows directly. The Windows Ollama installer puts files in `AppData/Local/Ollama/` and can run as a system tray app.

## Workflow: Setting Up Local LLM for Hermes

1. **Identify hardware constraints** — GPU VRAM, system RAM, CPU
2. **Select platform** — Ollama for always-on, LM Studio for exploration
3. **Choose model** — Match parameter count and quant to VRAM. For 8GB cards, prefer Qwen3-8B Q4_K_M. **Do NOT use Gemma4:e4b at Q4_K_M on 8GB** (9.6GB = OOM).
4. **Install and pull** — `winget install Ollama.Ollama && ollama pull <model>`
5. **Verify API** — `curl http://127.0.0.1:11434/v1/models`
6. **Configure Hermes** — Add provider in config.yaml and/or profile
7. **Test** — Run a query through Hermes using the local model

## Pitfalls

- **Gemma4:e4b OOM on 8GB**: At Q4_K_M (~9.6GB), exceeds RTX 4060 8GB VRAM. Use Qwen3-8B or a smaller quant.
- **`fallback_providers` works globally**: It is NOT only for Gemini Cloud Code — it works as a general fallback chain for any provider including Ollama.
- **Qwen3 empty `content` field**: Qwen3 is a reasoning model. The `content` field may be empty with the actual response in `reasoning`. This is normal.
- **Don't hardcode model names in cron jobs** — use `@preset/hermes` unless user explicitly requests otherwise
- **Ollama must be running** before Hermes can use it — set up auto-start via Windows Startup folder
- **Windows services invisible from WSL `ps`** — `ps aux` in WSL only shows Linux processes. Windows-hosted Ollama won't appear in `ps aux`. Always test port connectivity (`curl http://127.0.0.1:11434/api/tags`) or check Windows paths (`/mnt/c/Users/<user>/AppData/Local/Ollama/`).
- **cmd.exe UNC path issues from WSL** — `cmd.exe /c` fails with UNC paths for registry/scheduled-task commands. Use `powershell.exe` instead.
- **PowerShell `$` variable stripping** — multi-line PowerShell with `$` vars gets mangled via `-Command`. Write `.ps1` files and use `-File`.
- **Context window vs VRAM tradeoff** — larger context = more VRAM for KV cache; reduce context if OOM
- **First model load is slow** — 30-60s to load into VRAM on first request after starting Ollama

### Multi-Agent VRAM Overhead

When running multiple agents, persona overhead compounds:
- **Full Hermes persona** (~10K tokens) reduces effective context window by ~40%
- **9 agents** = ~90K tokens of persona overhead across the system
- **Mitigation**: Use shared base personas with role-specific deltas, budget VRAM per agent, minimize system prompt length

### max_tokens Configuration

- Default 1024 token budget **silently truncates** complex reasoning outputs
- For research/analysis tasks, set `max_tokens` to **4096+**; for complex multi-step reasoning, **8192+**
- This is an Ollama-level setting that needs explicit configuration for sustained reasoning

### API Key Storage Warning

- Hermes memory tool **silently truncates long API keys** into previews (e.g., `col_Ys...uzNk`)
- Store API keys in credential files, NOT in memory tool entries
- Verify full key length (minimum ~47 chars for Colony keys)

## References

- `references/hardware-constraints-insights.md` — VRAM ceilings, KV cache cliffs, persona overhead taxes, max_tokens truncation, API key storage warning (synthesized from Colony community research)
- `references/ollama-integration-lessons.md` — Ollama integration details: config format, auto-start, WSL networking, stale IP fixes, Gemma4 OOM warning
- `references/platform-comparison-2026.md` — Detailed platform comparison matrix with features, pros/cons
- `references/model-recs-8gb-vram.md` — Model recommendations specifically for 8GB VRAM systems