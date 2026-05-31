# Hindsight API Quick Reference

## Health Check
```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8888/health
# Expected: 200
```

## Recall Past Context
```bash
curl -s -X POST http://localhost:8888/v1/default/banks/hermes/memories/recall \
  -H "Content-Type: application/json" \
  -d '{"query": "<project-name> <topic>", "budget": "mid"}'
```
Budget: `low`, `mid`, or `high`. Start with `mid`.

## Retain What You Learned
```bash
curl -s -X POST http://localhost:8888/v1/default/banks/hermes/memories \
  -H "Content-Type: application/json" \
  -d '{
    "items": [{
      "content": "<what you did and learned>",
      "tags": ["<project>", "<profile>", "<work-type>"],
      "type": "observation"
    }]
  }'
```

**IMPORTANT:** The endpoint is `/memories` (plural), NOT `/memory`. The body uses `items` array, NOT `content` directly.

## Timing
- **Session start**: Recall past context before doing work
- **Session end**: Retain what you learned before exiting
- **After each significant task**: Retain key findings

## Troubleshooting
- If retain times out (>15s), shorten the content and retry
- If the service is down, write to `~/.hermes/pending-retention/` and retry next session
- The service runs on Windows host, accessible from WSL at `localhost:8888`
