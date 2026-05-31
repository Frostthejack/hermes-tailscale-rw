# Hermes Visualizer Plugin — Mood/Activity Mapping Reference

> Source: https://github.com/rwcrosk-arch/hermes-visualizer-plugin
> Captured: 2026-05-18

## Mood-to-Tool Mapping

The visualizer plugin maps Hermes tool names to 8 distinct moods. This is a useful reference for any project that needs activity-to-state mapping.

| Mood | Activity | Example Tools |
|------|----------|---------------|
| curious | Search / browse / read | web_search, read_file |
| working | Terminal / patch / git | terminal, patch |
| thinking | Code / reason / analyze | execute_code, delegate_task |
| happy | Write / save / send | write_file, send_message |
| excited | Image / audio generate | image_generate, text_to_speech |
| surprised | Question / clarify | clarify |
| sad | Errors / failures | Auto-detected from result text |
| sleeping | Session end | on_session_end hook |

## Architecture Pattern

- **Event Source:** Hermes plugin hooks (post_tool_call, on_session_start, on_session_end)
- **IPC:** Named pipe (FIFO) - plugin writes JSON, daemon reads
- **Rendering:** chafa terminal image renderer with ANSI ASCII fallback
- **Animation:** 3 GIF variants per mood, random cycling
- **Mood Detection:** Tool name to mood mapping (not event-type-based)

## Key Design Decisions

1. **Tool-level granularity** - Maps individual tool names, not broad event types. This gives more nuanced reactions than mapping agent_working to a single state.
2. **Multiple variants per mood** - 3 GIFs per mood prevents repetition. Applicable to any animation system.
3. **Graceful fallback** - ANSI ASCII when chafa unavailable. Always have a degraded-mode fallback.
4. **Zero core modifications** - Pure plugin, no agent patches. Keep integrations non-invasive.

## When to Reference This

- Designing state/activity mapping for agent-driven UIs
- Adding granular sub-states to a state machine
- Implementing animation variety (multiple variants per state)
- Building terminal-based visualizations of agent activity
