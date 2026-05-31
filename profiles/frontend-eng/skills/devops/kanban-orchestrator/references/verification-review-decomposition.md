# Verification & Review Decomposition Pattern

How to decompose a "verify everything works" request into parallel review tracks with a PM triage fan-in.

## Pattern

When asked to verify/review a project comprehensively:

1. **Spawn parallel review tracks** — each covering a different dimension:
   - **UX/UI Review** (reviewer): Check live app against PRD requirements line-by-line
   - **E2E Verification** (backend-eng): Test all API endpoints, game flows, real-time sync, edge cases
   - **Code Review** (reviewer): Verify codebase matches project specs (schema, routes, logic, seed data, components)

2. **Create a PM triage task** blocked on all reviews completing:
   - Reads findings from all review tasks
   - Creates one fix task per FAIL/PARTIAL finding
   - Assigns to correct specialist (frontend-eng, backend-eng, ops)
   - Links each fix task as child of the relevant review task

3. **Create known-fix tasks immediately** for any obvious gaps already identified (don't wait for reviews to find what you already know is broken)

## Task body template for review tasks

```markdown
## Task: [Review Type] — [Project Name]

### What to Review
[Bulleted list of specific items to check, grouped by area]

### Output Format
For each item:
- ✅ PASS — works as specified
- ❌ FAIL — missing or broken (describe)
- ⚠️ PARTIAL — exists but doesn't match spec (describe gap)

### VERIFICATION:
1. [Specific step]
2. [Specific step]
3. Document results with evidence (curl output, screenshots)
4. For each FAIL/PARTIAL, create a fix task with details
```

## Dependency graph

```
T1 (reviewer): UX/UI Review ─────────┐
T2 (backend-eng): E2E Verification ──┤
T3 (reviewer): Code Review ──────────┤
                                      ▼
T4 (pm): Triage & Create Fix Tasks (parents: T1, T2, T3)
                                      │
                                      ▼
T5..N (various): Individual fix tasks (parents: T4)
```

## Key decisions from this session

- Three parallel review tracks was the right number for a full-stack web app
- PM triage task prevents review findings from sitting unactioned
- Known-fix tasks (like the missing dashboard Create/Join) should be spawned immediately, not gated behind reviews
- Each review task needs a VERIFICATION section with specific, executable test steps — not just "check that it works"
