# Discord Gateway Configuration Reference

## channel_prompts

`channel_prompts` is a dictionary mapping Discord channel IDs (as numeric strings) to custom system prompt strings. When the agent responds in a matched channel, the custom prompt is injected into the system prompt for that turn.

### Config Format

```yaml
discord:
  channel_prompts:
    "<channel_id>": "<custom prompt string>"
    "1505062204171489340": "You are a coding assistant. Be concise and technical."
    "987654321098765432": "You are a creative writer. Be imaginative and descriptive."
```

### Key Details

- **Channel IDs must be quoted strings** — Discord IDs are large integers; quoting prevents YAML from interpreting them as numbers.
- **Injection is per-turn** — the system prompt is rebuilt each conversation turn, so the channel-specific prompt is injected on every message in that channel.
- **Merge semantics** — the channel prompt replaces/augments the base system prompt for that channel. It does NOT stack with personality settings.
- **Empty dict `{}`** — means no channel-specific prompts are configured (default).
- **Getting a channel ID** — In Discord, enable Developer Mode (Settings → Advanced → Developer Mode), then right-click a channel → "Copy Channel ID".

### Example: Coding Channel

```yaml
discord:
  channel_prompts:
    "1505062204171489340": "You are a coding assistant. Be concise. Focus on code, not explanations. Use code blocks liberally."
```

### Example: Multiple Channels

```yaml
discord:
  channel_prompts:
    "1505062204171489340": "You are a coding assistant. Be concise and technical."
    "987654321098765432": "You are a creative writer. Be imaginative and descriptive."
    "111222333444555666": "You are a helpful assistant. Be friendly and approachful."
```

### Troubleshooting

- **Prompt not taking effect:** Ensure the channel ID is correct and quoted as a string. Restart the gateway after config changes.
- **All channels getting the same prompt:** Each channel needs its own entry. There is no wildcard or "default" channel prompt — use `allowed_channels` to restrict which channels the bot responds in.
