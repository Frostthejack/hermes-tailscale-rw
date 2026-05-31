# CI Pipeline Debugging — Multi-Instance & Schema Desync Patterns

## Multi-Instance Git Desync

**Symptom:** CI fails with errors that don't match local code (e.g., "Argument 'session' is missing" in a Prisma create call, but the local file looks correct).

**Root cause:** Another Hermes instance pushed commits that modified the schema or API routes. Your local repo is behind `origin/main`.

**Diagnostic steps:**
```bash
# Check if local is behind remote
git fetch origin
git log HEAD..origin/main --oneline

# If behind, pull and re-examine the failing file
git pull origin main
```

**Fix:** Always `git pull` before debugging CI failures when multiple Hermes instances share the project.

## Prisma Schema/Route Desync

**Symptom:** Prisma validation error about missing required argument in a `create` or `update` call.

**Root cause:** `prisma/schema.prisma` was modified (by another instance or manually) to add a new required relation field, but the API route's `create`/`update` call wasn't updated to include it.

**Diagnostic steps:**
1. Read `prisma/schema.prisma` — find the model and check for new required fields
2. Read the failing API route — check if the `create` call includes all required relations
3. The fix is usually adding `relationField: { connect: { id: entity.id } }` to the create payload

**Example:**
```typescript
// Schema added: SessionCharacter.session Session @relation(...)
// Route was missing: session: { connect: { id: session.id } }
prisma.sessionCharacter.create({
  data: {
    // ... other fields
    session: { connect: { id: session.id } },  // ← added this
  },
})
```

## Prisma Relation/Scalar Conflict

**Symptom:** `PrismaClientValidationError` pointing at a scalar field (e.g., `sessionPlayerId`) with underline markers, even though the scalar value is provided.

**Root cause:** When a Prisma model has both a relation field (e.g., `sessionPlayer`) and its corresponding scalar foreign key (e.g., `sessionPlayerId`), you CANNOT include both in the same `create()` call. Prisma rejects the scalar as redundant/conflicting when the relation connect is present.

**Diagnostic steps:**
1. Check the error location — if it points at a scalar FK field (e.g., `sessionPlayerId`, `sessionId`)
2. Check if the same `data` block also has the relation connect (e.g., `sessionPlayer: { connect: { id } }`)
3. Remove the scalar FK field — Prisma auto-populates it from the relation

**Example — WRONG:**
```typescript
prisma.sessionCharacter.create({
  data: {
    session: { connect: { id: session.id } },
    sessionPlayer: { connect: { id: sessionPlayerId } },
    sessionPlayerId,  // ← REMOVE THIS — conflicts with sessionPlayer relation
    characterId,
  },
})
```

**Example — CORRECT:**
```typescript
prisma.sessionCharacter.create({
  data: {
    session: { connect: { id: session.id } },
    sessionPlayer: { connect: { id: sessionPlayerId } },
    // sessionPlayerId is auto-set by Prisma from the sessionPlayer relation
    characterId,
  },
})
```

**Same pattern applies to any model with both `relation` and `relationId` fields.**

## E2E Test Stale State Pattern

**Symptom:** E2E test fails after many successful rounds/iterations, typically with "not found", "defeated", or "not your turn" errors from the API. The test helper objects (e.g., character arrays) were populated once at setup and never refreshed.

**Root cause:** The test holds references to server response objects (e.g., deployed characters) in local variables/arrays. These objects have fields like `currentHealth` that change on the server during gameplay. The test reads stale values and makes decisions based on outdated state (e.g., picking a character that's actually defeated).

**Diagnostic steps:**
1. Check if the test uses `.find()` or `.filter()` on locally-held arrays to select entities
2. Check if the selection criteria depends on server-mutated fields (HP, status, turn index)
3. Check if the arrays are refreshed from the server after state-changing operations

**Fix:** After each state-changing operation (end turn, attack, etc.), refresh the local arrays from the server's session state:

```typescript
// WRONG — stale arrays never updated
const hostDeployed = [...];  // set once at deployment
// ... 20 rounds later ...
const activeChar = hostDeployed.find(c => c.currentHealth > 0);  // stale HP!

// RIGHT — refresh from server state after each turn
state = await getSessionState(page, sessionId);
const hostPlayerState = state.players.find(p => p.id === hostPlayerId);
hostDeployed.length = 0;
if (hostPlayerState) hostDeployed.push(...hostPlayerState.characters);
```

**Key indicator:** Test logs show characters with their initial HP values even after combat damage has been dealt.

## CI Log Investigation Pattern

```bash
# 1. List recent workflow runs
gh run list --repo owner/repo --limit 5

# 2. View failed run details
gh run view <run_id> --repo owner/repo

# 3. Get ONLY the failed test output
gh run view <run_id> --repo owner/repo --log-failed

# 4. If the error is a build failure (not test), get the full log
gh run view <run_id> --repo owner/repo --log
```

**Key flags:**
- `--log-failed` — only shows output from failed steps (much shorter, focused)
- `--log` — full log (use when `--log-failed` doesn't show the error)
- `--job <job_id>` — focus on a specific job

## E2E Test Failures — Common Patterns

1. **All tests fail at the same point** → Usually a setup/seeding issue or a shared dependency (DB, auth)
2. **Tests fail with "element not found"** → UI changed but tests weren't updated, or the app crashed during test setup
3. **Tests fail with timeout** → Service didn't start, or a request is hanging (check DB connection, external API)
4. **Intermittent failures** → Race conditions, shared state between tests, or rate limiting
5. **Test fails after many successful rounds** → Stale local state (see E2E Test Stale State Pattern above)
6. **Test safety limit too tight** → maxRounds/maxIterations exits before completion (see `references/e2e-test-safety-limits.md`)

## Verification After Fix

After pushing a CI fix:
```bash
# Watch the new run
gh run watch <run_id> --repo owner/repo

# Or poll manually
gh run view <run_id> --repo owner/repo --json status,conclusion
```
