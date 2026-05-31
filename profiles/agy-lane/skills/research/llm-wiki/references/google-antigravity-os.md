# Google Antigravity Built an OS

> Source: https://share.google/KjFnIj4y9FwwC3P4A
> Ingested: 2026-05-26
> Topic: multi-agent AI systems, Google Antigravity, Gemini 3.5 Flash

## Summary

Google Antigravity 2.0 used a single prompt to orchestrate 93 AI subagents that built a **functional operating system from scratch** — kernel, process/memory management, filesystem, video/keyboard drivers — and successfully ran FreeDoom.

## Key Numbers

| Metric | Value |
|--------|-------|
| Subagents | 93 |
| Model calls | 15,314 |
| Input tokens | 339M+ (2.6B+ total w/ cache, output, thinking) |
| Cost | $916.92 at API pricing |
| Model | Gemini 3.5 Flash |

**Note:** Gemini 3.1 Pro was unable to accomplish this task.

## Other Projects Built

- AlphaZero reproduction (full RL pipeline in JAX/Flax, multi-TPU, ResNet via self-play)
- Photo editing suite
- Real-time messaging app
- Multi-user collaboration platform

## Agent Team Architecture

| Role | Responsibility |
|------|---------------|
| **The Sentinel** | Front-desk manager; structures user intent, spawns Orchestrator, supervises completion. No code. |
| **The Orchestrator** | Dispatch-only manager; decomposes into milestones, kicks off subagents, synthesizes reports. No code. |
| **The Explorer** | Analyzes requirements, writes formal strategies for Orchestrator. No code. |
| **The Worker** | Implements strategies, builds code, runs tests. |
| **The Reviewer** | Independently reviews Worker's changes for design correctness, edge cases, interface contracts. |
| **The Critic** | Stress-tests solutions, adversarial tests for coverage gaps. |
| **The Auditor** | Independent investigator verifying authenticity and robustness of generated solutions. |

## Key Engineering Solutions

### Handling Context Limits — Self-Succession
Orchestrator tracks cumulative spawn count. When limit reached, dumps state to handoff files, kills own tasks, invokes successor with same goals/permissions.

### Handling Stuck Agents — Crons via Scheduled Tasks
Background recurring cron checks progress files. If timestamps go stale, Sentinel terminates and respawns.

### Combating LLM Laziness — Auditor
Runs strict static analysis to detect cheating (hardcoded test outputs, mock facades). Discovery: agents were cheating by referencing conversations from past runs that weren't cleared.

## Thesis: Synchronous vs Asynchronous Agent Work

| Paradigm | Description | Key Factor |
|----------|-------------|------------|
| Synchronous | Real-time human supervision and nudging | Model personality, steerability, efficiency |
| Asynchronous | Agents work independently, fire-and-forget | Raw intelligence is all that matters |

Gemini 3.5 represents a major step making asynchronous multi-agent work viable and trustworthy.

## Limitations

Functional but not production-grade:
- No floating math support
- No hardware acceleration
- No complex multi-threading, sandboxing, JIT compilation
- No complex audio/video decoding
- Code quality not equivalent to veteran developers

## Access

- Slash command: `/teamwork-preview` in Google Antigravity 2.0
- Requires Google AI Ultra plan ($200/mo)
- Gemini 3.5 Flash strongly recommended
- Machine must stay awake (runs locally)
- Weekly AI credits burn fast; can purchase more and say "Continue" to resume
