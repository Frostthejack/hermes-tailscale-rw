# Code Review Checklist for Web Game Projects

Use this checklist when performing pre-decomposition code review (Step 2.3.5) on web game projects.

## Common Bug Patterns in Next.js + Supabase Games

### API Route Issues
- [ ] **Validation rejects valid empty inputs** — Check if validators (e.g., `validateTurnOrder`) reject empty arrays/strings that are valid for partial updates
- [ ] **Wrong ID types in filters** — Verify filter uses the correct field (e.g., `characterId` vs `id` vs `sessionCharacterId`)
- [ ] **Missing session filters on realtime listeners** — Supabase `postgres_changes` listeners should filter by session ID to avoid cross-session data leaks
- [ ] **Enum mismatches** — Code-level status enums must match Prisma schema enums exactly
- [ ] **Missing exports** — Functions used by other modules must be exported (e.g., `validatePositiveInt`)
- [ ] **Context values not exposed** — If a consumer calls `useGameState()` and destructures `setGameState`, verify the context provider actually exposes it (check the context value object and the interface)

### Frontend State Issues
- [ ] **Spectator/role checks** — Ready checks, start conditions, and action permissions must account for spectators
- [ ] **Wrong API URLs** — Verify fetch calls match actual route definitions (join code vs session ID)
- [ ] **Missing prop passing** — Components receiving callbacks from parent must have those props actually passed
- [ ] **No-op callbacks** — Empty `() => {}` handlers that should wire up modals or API calls
- [ ] **ID space confusion** — Roster character IDs, session character IDs, and deployed character IDs are different; use the right one for each operation
- [ ] **Fields from wrong type** — If a worker adds `initialSession.someField`, verify `someField` actually exists on the session type (Prisma model). Workers often add UI state fields (e.g., `useDigitalBoard`) to the wrong type instead of using local `useState`

### Missing Component Files After Worker Commits
- [ ] **Import without file** — After any worker commit, verify every `import` in the diff resolves to an actual file on disk. Run `npx tsc --noEmit` — `Module not found` errors mean a worker imported a component they never created
- [ ] **Checklist for each new import in diff:**
  1. `git diff --name-only HEAD~1` — list changed files
  2. For each new `import { X } from "@/components/..."`, verify the target file exists
  3. If the file is missing, create it BEFORE pushing to main (broken builds block all other work)
- [ ] **Common culprits:** Modal components, context provider exports, hook functions referenced but not defined

### Data Flow Issues
- [ ] **Multi-step operations incomplete** — Deploy may require: create session character → deploy. Verify all steps are present.
- [ ] **Stale data after mutations** — After create/update/delete, local state should refresh from API or be optimistically updated
- [ ] **Missing error handling** — 409 (conflict) responses should be handled gracefully (e.g., "already exists" → continue)

### Real-time Issues
- [ ] **Channel name collisions** — Supabase channels must have unique names per instance (use `crypto.randomUUID()`)
- [ ] **Missing unsubscribe** — Channels must be cleaned up on unmount to prevent memory leaks
- [ ] **Over-broad listeners** — Listeners without session filters receive all changes from all sessions

## Verification Commands

```bash
# Check for TypeScript errors (catches missing files, type mismatches, missing exports)
npx tsc --noEmit

# Check for missing exports
grep -rn "import.*from.*validation" src/app/api/ | grep -v node_modules

# Check for wrong API URLs
grep -rn "fetch.*api/sessions" src/ | grep -v node_modules

# Check for empty callbacks
grep -rn "() => {}" src/components/

# Check for ID field mismatches
grep -rn "\.id !== .*characterId" src/
grep -rn "characterId !== .*id" src/

# After worker commits: verify all imports resolve
npx tsc --noEmit 2>&1 | grep "Cannot find module\|Module not found"
```
