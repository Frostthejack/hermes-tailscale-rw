# E2E Test Safety Limits vs. Data Values

## Pattern

**Symptom:** E2E test fails at an assertion after many successful iterations/rounds. The test has a safety limit (maxRounds, maxIterations, maxTime) that exits the loop before the actual completion condition is met. The assertion after the loop then fails because the completion flag was never set.

**Real example:** A full-game E2E test for a turn-based combat game:
- Test has `maxRounds = 20` to prevent infinite loops
- Each player has 3 characters with 75 HP total
- Damage is capped at 3 per turn
- 75 HP / 3 damage = 25 turns per player = 25 rounds total
- Loop exits at round 20, `gameOver` is still `false`
- Test fails at `expect(gameOver).toBe(true)` — 10+ consecutive CI failures

**Why it's hard to diagnose:**
- The test "almost works" — 22 of 23 tests pass
- The failure looks like a backend logic bug (gameOver detection)
- Multiple fix attempts targeting the backend (allDefeated logic, session re-fetching, channel naming) all fail because the backend is correct
- The real issue is a test-side configuration value that's too tight for the current data

## Diagnostic Steps

1. **Check the test's safety limits** — Look for `maxRounds`, `maxIterations`, `maxTime`, `while (!condition && count < N)` patterns
2. **Calculate the actual required iterations** — Total HP / max damage per turn, or similar domain-specific math
3. **Compare limit vs. required** — If the safety limit is close to or less than the required iterations, that's the bug
4. **Check if data values changed** — HP values, damage caps, or other game balance changes may have been updated without adjusting the test limits

## Common Safety Limit Patterns

| Pattern | Typical Value | What to Check |
|---------|--------------|---------------|
| `maxRounds` | 10-20 | Total HP / min damage per round |
| `maxIterations` | 100-1000 | Domain-specific calculation |
| `maxTime` (ms) | 30000-60000 | Network latency × expected calls |
| `retries` | 2-3 | Transient failure rate |

## Fix

Increase the safety limit to comfortably exceed the expected maximum:

```typescript
// Before
let maxRounds = 20;

// After — add 50% headroom above expected maximum
let maxRounds = 30;
```

Or make the limit data-driven:

```typescript
// Calculate from actual game state
const totalHP = players.reduce((sum, p) => sum + p.characters.reduce((s, c) => s + c.maxHealth, 0), 0);
const maxRounds = Math.ceil(totalHP / minDamagePerTurn) + 5; // headroom
```

## Key Insight

**When 3+ backend fix attempts fail for an E2E test, check the test itself.** The test's safety limits, assertions, or data assumptions may be the root cause. This is especially likely when:
- The test passes most assertions but fails at the final one
- The failure is consistent across many commits
- Backend logging shows correct behavior
- The test "almost completes" but exits early
