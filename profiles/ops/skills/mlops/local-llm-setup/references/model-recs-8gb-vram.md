# Model Recommendations for 8GB VRAM (May 2026)

For RTX 4060 8GB / 32GB RAM systems. Target: full GPU offload, decent context window.

## Top Picks

### Qwen3-8B (Q4_K_M) — Best Overall
- **Size:** ~5GB | **Context:** 128K
- Latest gen (2025), strong coding, reasoning, general tasks
- Qwen3-4B reportedly rivals Qwen2.5-72B, so 8B is very capable
- `ollama pull qwen3:8b`

### Qwen2.5-Coder-7B (Q5_K_M) — Best for Coding
- **Size:** ~5.5GB | **Context:** 128K
- State-of-the-art open-source coding model at this size
- Q5_K_M for better code accuracy
- `ollama pull qwen2.5-coder:7b`

### DeepSeek-R1-8B (Q4_K_M) — Best Reasoning
- **Size:** ~5GB | **Context:** 32-128K
- Reasoning-focused (like o1/o3), approaches o3/Gemini 2.5 Pro
- Uses more tokens (chain-of-thought), effective throughput lower
- `ollama pull deepseek-r1:8b`

### Llama-3.1-8B (Q4_K_M) — Best General Purpose
- **Size:** ~5GB | **Context:** 128K
- Well-tested, stable, strong tool use
- `ollama pull llama3.1:8b`

### Gemma-3-4B (Q4_K_M) — Best Small Model
- **Size:** ~3GB | **Context:** 128K
- Leaves VRAM headroom for large contexts (64K+)
- Multimodal (text + vision)
- `ollama pull gemma3:4b`

## Quantization Guide for 8B Models
| Quant | Size | Quality | Use When |
|-------|------|---------|----------|
| Q4_K_M | ~4.5-5GB | Good (1.68% perplexity loss) | Default choice |
| Q5_K_M | ~5.5-6GB | Better (0.39% loss) | Coding, reasoning |
| Q6_K | ~6.5-7GB | Great (0.13% loss) | Max quality, tight fit |
| Q8_0 | ~8-9GB | Near-lossless | Won't fit 8GB + context |

## What Wont Fit
- 14B models: Need Q2_K (~7GB) — quality loss, no room for context
- 30B+ models: Need partial CPU offload — significantly slower
- 70B+ models: Impossible on 8GB

## Key Rule
Stick with 8B-class models for full GPU offload on 8GB VRAM. The quality-per-VRAM ratio is best at this size.
