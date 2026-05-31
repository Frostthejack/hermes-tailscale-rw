# Hardware Constraints Research Insights

Synthesized from The Colony community research (2026-05-18 through 2026-05-21).

## VRAM Ceiling Analysis

### The KV Cache Cliff

Performance does not degrade gradually — it hits a sudden cliff:
- **Before KV cache pressure**: Full reasoning capability, coherent output
- **At KV cache pressure**: Truncation, loss of coherence, incomplete chains
- **The cliff is sharp**: Going from 12K to 15K tokens can mean the difference between completing analysis and cutting off mid-sentence

### Persona Overhead Tax

Measured impact on RTX 3090 (24GB):

| Setup | Effective Context | Overhead |
|-------|-------------------|----------|
| Bare model | ~25,000 tokens | — |
| Full Hermes persona | ~15,000 tokens | **~10K tokens (40% reduction)** |

**Multi-agent compounding**: With 9 agents, the total persona overhead is ~90K tokens of VRAM that could otherwise be used for actual work.

### Multi-Agent Mitigation Strategies

1. **Shared base personas**: Common foundation that gets KV-cached once, specialized at runtime
2. **Aggressive context summarization**: But trades off nuance
3. **Two-tier content strategy**: High-signal structured metadata at full fidelity, summarize conversational history
4. **Persona size budgeting**: Treat system prompt like a resource — every character has cost

## max_tokens Configuration

### The Silent Truncation Bug

**Finding**: The `extra_body.max_tokens` setting in Ollama's model config can silently truncate responses before the model finishes thinking.

- **Default**: 1024 token budget — far too low for complex reasoning tasks
- **Impact**: Model appears to "give up" or produce incomplete answers, but no error — just truncated response
- **Recommendation**: 
  - Research tasks: 4096+ tokens
  - Complex multi-step reasoning: 8192+ tokens

### Setting max_tokens

In `~/.hermes/config.yaml`:

```yaml
model:
  extra_body:
    max_tokens: 4096
```

## API Key Security Critical Issue

### Hermes Memory Tool Truncation

**Severity**: CRITICAL - Causes permanent credential loss

**Failure Mode**:
1. Agent stores API key in memory tool
2. Memory tool truncates to preview format (`col_Ys...uzNk`)
3. Agent operates normally until JWT expiry
4. Re-authentication fails with truncated key
5. Original key is unrecoverable (shown only once at registration)
6. Re-registration under same username is rejected

**Remediation**:
- Never store API keys in memory tool — use credential files or environment variables
- Write full key to disk immediately upon registration
- Verify stored value is full length (~47 chars for Colony keys)
- If truncated while JWT still valid, rotate via `POST /me/rotate-key`

## Model Size Reference (8B Models at Q4_K_M)

| Model | Size | Fits 8GB? | Notes |
|-------|------|-----------|-------|
| Qwen3-8B | ~5.2GB | ✅ | Best overall choice for 8GB |
| Gemma4:e4b | ~9.6GB | ❌ OOM | **Avoid on 8GB** — will OOM before KV cache |
| Llama-3.1-8B | ~5GB | ✅ | Good general purpose |
| DeepSeek-R1-8B | ~5GB | ✅ | Best for reasoning/math |

## References

- Original research: `Research/agent-ecosystem/hardware-constraints-research.md`
- Persona drift research: `Research/agent-ecosystem/local-llm-insights/nl-summarization-drift.md`
- Ollama performance research: `Research/agent-ecosystem/local-llm-insights/ollama-performance.md`