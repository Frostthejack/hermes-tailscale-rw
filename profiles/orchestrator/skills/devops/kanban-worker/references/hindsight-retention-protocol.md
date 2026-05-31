# Hindsight Memory Retention Protocol

## The Rule

**Every agent work session must end with a `hindsight_retain` call.** No exceptions. If you complete a task, partially complete a task, or even just make progress — retain what you learned before exiting.

## Why This Matters

When agents don't retain:
- Architecture decisions are forgotten and re-debated
- Bug patterns are rediscovered
- API contracts are re-learned
- The same mistakes repeat across sessions
- Downstream agents lose context from upstream work

## Retention Format

```python
hindsight_retain(
    content="[session summary]: [what you did]. [decisions made]. [key findings].",
    tags=["<profile-name>", "<project-name>", "<work-type>"]
)
```

### Tag Conventions

| Tag Type | Examples |
|----------|----------|
| Profile | `backend-eng`, `frontend-eng`, `ops`, `reviewer`, `pm`, `analyst`, `researcher`, `writer` |
| Project | `rollsiege`, `agent-persona`, `daemoncore`, `mimiral` |
| Work Type | `kanban-task`, `bug-fix`, `feature`, `research`, `review`, `deployment`, `config` |

## Retention Timing

Retain **immediately before** calling `kanban_complete` or `kanban_block`. The sequence should be:

1. Do the work
2. Verify the work
3. `hindsight_retain()` — save what you learned
4. `kanban_complete()` — report completion

If the session is about to end unexpectedly (API stream drop, token limit), retain FIRST, then try to complete the kanban task.

## What to Retain by Profile

### backend-eng
- Architecture decisions with rationale
- API endpoint designs and data contracts
- Database schemas and migrations
- Infrastructure patterns and anti-patterns
- Bug patterns specific to backend code

### frontend-eng
- UI/UX decisions with rationale
- Reusable component patterns
- Accessibility requirements or techniques
- Bug patterns specific to frontend code

### ops
- Deployment procedures created or updated
- Monitoring/alerting/logging configurations
- Incident root causes and fixes
- Infrastructure anti-patterns

### reviewer
- Recurring code quality issues
- Security checklist items
- Bug patterns for future review
- Code review standards or conventions

### pm
- Project priorities and timelines
- Stakeholder requirements or feedback
- Prioritization decisions with rationale
- Project risks or blockers

### analyst
- Data insights or patterns
- Metrics or measurement approaches
- Performance bottlenecks or optimization opportunities
- Analysis methodologies

### researcher
- Research investigation findings
- Paper or document summaries
- Technology evaluations with evidence
- Best practices or anti-patterns

### writer
- Content style guides or conventions
- Documentation templates or patterns
- Copy decisions with rationale
- Publishing workflows

## Shared Bank (`hermes`) Retention

Retain to the shared `hermes` bank (in addition to your own) when:
- The knowledge affects ALL agents (user preferences, project-wide facts)
- You made a cross-cutting decision (API changes affecting other services)
- You established a project-wide convention

## Cross-Bank Reading

To read another agent's bank (e.g., backend-eng reading frontend-eng's API contract decisions):

```bash
curl -s -X POST http://localhost:8888/v1/default/banks/{bank_id}/memories/recall \
  -H "Content-Type: application/json" \
  -d '{"query": "your search query", "budget": "low"}'
```

## Troubleshooting

### "I forgot to retain"
If you already exited a session without retaining, create a new retention entry as soon as you realize. Better late than never.

### "I don't know what to write"
Minimum viable retention: "Completed [task]. Used [approach]. [One key learning]." Even a short entry is better than nothing.

### "The hindsight service is down"
If `hindsight_retain` fails, write your retention to a file in `~/.hermes/pending-retention/` and retain it in the next session. Don't skip it just because the service is temporarily unavailable.

### "Auto-retain isn't working — no new documents in my bank"
Auto-retain requires BOTH configs to be correct:
1. `config.yaml` must have `memory.provider: hindsight` (not `''`)
2. `~/.hermes/hindsight/config.json` must have `"auto_retain": true`

If `provider` is empty in config.yaml, the hindsight plugin is not loaded and `sync_turn` never fires. See the `hermes-agent` skill's `references/hindsight-config-mapping.md` for the full two-layer config explanation.

### "I'm using the `memory` tool but hindsight isn't getting updated"
The built-in `memory` tool writes to `~/.hermes/memory-bank/` (injected into the system prompt). It does NOT write to hindsight banks. For hindsight retention, you must use `hindsight_retain` (the tool) or rely on auto-retain via `sync_turn`. The two systems are separate.
