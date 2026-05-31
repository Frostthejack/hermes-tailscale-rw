# Local LLM Hosting Platform Comparison (2026)

## Ollama — Best Overall
- **License:** MIT | **Platform:** Windows, macOS, Linux
- One-command model pull, OpenAI API at port 11434
- Auto CUDA GPU offload, 1000+ pre-quantized models
- `winget install Ollama.Ollama`

## LM Studio — Best GUI
- **License:** Proprietary (free personal) | **Platform:** All
- Visual model browser, OpenAI API at port 1234
- Python/TypeScript SDKs, `lms` CLI for headless
- API server must be manually started

## llama.cpp — Maximum Control
- **License:** MIT | **Platform:** All
- `llama-server -hf bartowski/Qwen3-8B-GGUF:Q4_K_M`
- Full control over GPU layers, context, samplers
- Manual model management, no registry

## vLLM — Production (Linux only)
- PagedAttention, continuous batching, highest throughput
- Overkill for single-user local fallback

## Others (Brief)
- **Jan:** ChatGPT alternative, AGPL-3.0, OpenAI API
- **textgen:** Feature-rich web UI, AGPL-3.0, multiple backends
- **Open WebUI:** Dashboard layer (needs Ollama), MIT
- **GPT4All:** Lightweight CPU, MIT, no OpenAI API

## Summary Matrix
| Platform | Ease | GPU | OpenAI API | Windows | Best For |
|----------|------|-----|------------|---------|----------|
| Ollama | ★★★★★ | CUDA/ROCm/Metal | ✅ | ✅ | Always-on local server |
| LM Studio | ★★★★★ | CUDA/Metal | ✅ | ✅ | GUI model exploration |
| llama.cpp | ★★★☆☆ | CUDA/Metal/Vulkan | ✅ | ✅ | Maximum control |
| vLLM | ★★☆☆☆ | CUDA (Linux) | ✅ | ❌ | Production throughput |
