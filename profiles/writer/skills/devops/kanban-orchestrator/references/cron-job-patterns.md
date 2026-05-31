# Cron Job Patterns for Kanban Monitoring

## Board Monitor Cron

A lightweight cron that checks a kanban board and reports status changes back to the originating chat.

### Key Pattern
- Use `deliver: "origin"` — the agent's final text response is automatically delivered back to the chat that created the cron
- Do NOT use `send_message` — it's not needed and will fail if `messaging` isn't in `enabled_toolsets`
- Keep `enabled_toolsets: ["terminal"]` — only needs to run `hermes kanban list`
- Use the user's default model (`@preset/hermes`), never hardcode a model
- Schedule: `every 5m` is usually frequent enough without being noisy
- The prompt should tell the agent to stay silent if nothing changed

### Example Prompt
```
You are a kanban board monitor. Check the <project> board and report status.

Run: hermes kanban --board <slug> list

Output a concise status report:

<Project> Kanban
Done: X total
Running: [count]
- [task title] -> [assignee]
Blocked: [count]
- [task title] -> [assignee]

Only include sections with count > 0. Keep titles short.
Do NOT use send_message — just output the report as your final response.
```

### Common Mistakes

1. **Hardcoding a model** — always use `@preset/hermes` (the user's default)
2. **Adding web toolset unnecessarily** — board monitoring only needs terminal
3. **Calling send_message** — not needed with `deliver: "origin"`, will error without messaging toolset
4. **Too frequent** — every 1m wastes tokens; every 5m is the sweet spot
5. **Too verbose** — keep the report concise; the user is on mobile/Telegram

### Delivery Target Gotcha

`deliver: "origin"` resolves to the chat/thread where the cron job was **created**. If the cron was created from a Discord thread but the delivery doesn't land there, `origin` may resolve to a different channel.

**Symptom:** Cron job runs successfully (status: `ok`) but the update never appears in the expected thread.

**Fix:** Set `deliver` explicitly to the target thread:
```
deliver: "discord:<channel_id>:<thread_id>"
```

You can find the thread ID from the Discord channel context. Always verify delivery after changing the target — run the job manually and confirm the message lands in the right place.

**When to use explicit vs. origin:**
- `origin` — works when the cron is created and consumed in the same thread
- Explicit `discord:channel:thread` — needed when the cron is created from a different context than where updates should go, or when `origin` resolution is ambiguous (e.g., created from CLI but should deliver to a Discord thread)
