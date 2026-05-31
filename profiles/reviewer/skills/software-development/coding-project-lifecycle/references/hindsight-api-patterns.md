# Hindsight API Patterns

## API Endpoints (hindsight-api 0.5.6)

The hindsight service runs on `http://localhost:8888`. It uses REST endpoints, NOT function calls.

### Health Check
```bash
curl -s http://localhost:8888/health
# Expected: {"status":"healthy","database":"connected"}
```

### Recall Memories
```bash
curl -s -X POST http://localhost:8888/v1/default/banks/{bank_id}/memories/recall \
  -H "Content-Type: application/json" \
  -d '{"query": "search terms", "budget": "high"}'
```
- `bank_id`: e.g., `hermes` (shared bank), or profile-specific bank ID
- `budget`: `"low"`, `"mid"`, or `"high"` (NOT `"medium"`)
- Returns: `{"results": [{"id", "text", "tags", ...}]}`

### Retain Memories
```bash
curl -s -X POST http://localhost:8888/v1/default/banks/{bank_id}/memories \
  -H "Content-Type: application/json" \
  -d '{
    "items": [{
      "content": "What you learned or did in this session",
      "tags": ["project-name", "profile", "work-type"],
      "type": "observation"
    }]
  }'
```
- **IMPORTANT:** The body uses `{"items": [{...}]}` array format, NOT a flat object.
- `type`: `"observation"` for session summaries
- Returns: `{"success": true, "bank_id": "...", "items_count": 1}`

### Reflect (Cross-Bank Patterns)
```bash
# NOT SUPPORTED on all API versions — returns 405 Method Not Allowed
# Use recall with a broader query instead
```

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Using `hindsight_retain(...)` function call | Use `POST /v1/default/banks/{bank_id}/memories` REST endpoint |
| `budget: "medium"` | Use `"mid"` or `"high"` |
| Flat body `{content, tags}` | Wrap in `{"items": [{content, tags}]}` |
| `/memories/retain` endpoint | Use `/memories` with POST |
| Timeout on large content | Keep content under ~2000 chars; split into multiple items if needed |

## Fallback When Hindsight Is Down

If the API times out or returns errors:
1. Write retention to `~/.hermes/pending-retention/<project>-<YYYY-MM-DD>.md`
2. Retain it in the next session before doing other work
3. Check service health: `curl -s http://localhost:8888/health`

## Retention Content Template

```
<Project> <date>: <phase> <status>. <N>/<M> tasks done. <running/blocked summary>. <key findings>. <next steps>.
```

Keep it concise — the value is in the key facts, not the narrative.
