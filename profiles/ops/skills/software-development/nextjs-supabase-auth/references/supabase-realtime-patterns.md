# Supabase Realtime: Common Errors & Patterns

## "cannot add postgres_changes callbacks after subscribe()"

### Symptom

```
Uncaught Error: cannot add postgres_changes callbacks for realtime:game:<id>:db after subscribe()
```

### Root Cause

In Supabase Realtime v2, all `postgres_changes` listeners **must** be registered on the channel **before** `subscribe()` is called. This error occurs when:

1. **Conditional `channel.on()` guards**: Code wraps `channel.on("postgres_changes", ...)` in `if (callback)` checks. If the effect re-runs (e.g., `sessionId` reference changes), the channel may already be subscribed from a previous effect run, and the new `channel.on()` calls fail.
2. **Race condition on re-subscription**: The cleanup function removes the old channel, but the new effect creates and subscribes a new channel before the old one is fully removed.
3. **Stale channel reference**: The channel was subscribed in a previous render cycle, and the effect tries to add more listeners without first removing/unsubscribing.

### Fix (v4 — FINAL WORKING SOLUTION)

**Use a unique channel name per hook instance** with `crypto.randomUUID()`:

```ts
useEffect(() => {
  if (!sessionId) return;

  // CRITICAL: Each hook instance must use a UNIQUE channel name.
  // supabase.channel(name) returns the SAME internal channel for the same name.
  // If that channel is already subscribed, calling .on("postgres_changes") throws.
  const uniqueKey = `${gameChannelName(sessionId)}:db:${crypto.randomUUID?.() ?? Date.now()}-${Math.random().toString(36).slice(2)}`;
  const channel = supabase.channel(uniqueKey);

  // Register ALL postgres_changes listeners BEFORE subscribing
  channel.on("postgres_changes", { event: "*", schema: "public", table: "Session", filter: `id=eq.${sessionId}` }, (payload) => {
    if (!mountedRef.current) return;
    callbacksRef.current.onSessionChange?.(payload.new as SessionRow, payload.eventType);
  });

  channel.on("postgres_changes", { event: "*", schema: "public", table: "SessionPlayer", filter: `sessionId=eq.${sessionId}` }, (payload) => {
    if (!mountedRef.current) return;
    if (payload.eventType === "DELETE") {
      callbacksRef.current.onPlayerChange?.(payload.old as SessionPlayerRow, "DELETE");
    } else {
      callbacksRef.current.onPlayerChange?.(payload.new as SessionPlayerRow, payload.eventType as "INSERT" | "UPDATE");
    }
  });

  channel.on("postgres_changes", { event: "*", schema: "public", table: "SessionCharacter" }, (payload) => {
    if (!mountedRef.current) return;
    if (payload.eventType === "DELETE") {
      callbacksRef.current.onCharacterChange?.(payload.old as SessionCharacterRow, "DELETE");
    } else {
      callbacksRef.current.onCharacterChange?.(payload.new as SessionCharacterRow, payload.eventType as "INSERT" | "UPDATE");
    }
  });

  channel.on("postgres_changes", { event: "INSERT", schema: "public", table: "DiceRoll", filter: `sessionId=eq.${sessionId}` }, (payload) => {
    if (!mountedRef.current) return;
    callbacksRef.current.onDiceRoll?.(payload.new as DiceRollRow);
  });

  channel.on("postgres_changes", { event: "INSERT", schema: "public", table: "ActionLogEntry", filter: `sessionId=eq.${sessionId}` }, (payload) => {
    if (!mountedRef.current) return;
    callbacksRef.current.onActionLog?.(payload.new as ActionLogEntryRow);
  });

  channel.subscribe((subscribeStatus) => {
    if (!mountedRef.current) return;
    if (subscribeStatus === "SUBSCRIBED") {
      setStatus("connected");
      setError(null);
    } else if (subscribeStatus === "CHANNEL_ERROR") {
      setStatus("error");
      setError(new Error("Postgres changes channel error"));
    } else if (subscribeStatus === "TIMED_OUT") {
      setStatus("error");
      setError(new Error("Postgres changes channel timed out"));
    } else if (subscribeStatus === "CLOSED") {
      setStatus("disconnected");
    }
  });

  channelRef.current = channel;

  return () => {
    const ch = channelRef.current;
    if (ch) {
      channelRef.current = null;
      supabase.removeChannel(ch);
    }
  };
}, [sessionId]);
```

### Why Previous Approaches Failed

| Approach | Why It Failed |
|----------|---------------|
| **v1: Conditional `if (callback)` guards** | Channel already subscribed from previous effect run; new `.on()` calls fail |
| **v2: Async cleanup with `await removeChannel()`** | `removeChannel()` is not truly awaitable; Supabase internal registry still holds reference |
| **v3: Module-level channel cache** | `supabase.channel(name)` returns the same internal object from Supabase's client-side cache, bypassing the module-level Map |
| **v4: Unique channel name per instance** | ✅ Works because each channel is truly new and never previously subscribed |

### Key Rules

1. **Never reuse the same channel name** across effect re-runs or component instances — use `crypto.randomUUID()` or `Date.now() + Math.random()`
2. **Never guard `channel.on()` with `if (callback)`** — always register the listener, use a ref for the callback
3. **Register ALL listeners before calling `subscribe()`** — create channel → register all `.on()` → call `.subscribe()`
4. **Use a ref for callbacks** to avoid stale closures: `const callbacksRef = useRef({ onXxx }); callbacksRef.current = { onXxx };`
5. **Use a mounted ref** to prevent state updates on unmounted components: `if (!mountedRef.current) return;`

### Trade-off

Using unique channel names means each hook instance creates its own Supabase Realtime connection. This is slightly less efficient than sharing a single channel, but it's the only reliable way to avoid the "cannot add callbacks after subscribe()" error. For typical usage (1-3 components per page), the overhead is negligible.

### Key Rules

1. **Never guard `channel.on()` with `if (callback)`** — always register the listener. Use a ref for the callback so it's always callable: `callbacksRef.current.onXxx?.(payload)`.
2. **Always clean up the existing channel** before creating a new one: `if (channelRef.current) { supabase.removeChannel(channelRef.current); channelRef.current = null; }`.
3. **Register ALL listeners before calling `subscribe()`** — in the correct order: create channel → register all `.on()` → call `.subscribe()`.
4. **Use a ref for callbacks** to avoid stale closures without causing re-subscriptions: `const callbacksRef = useRef({ onXxx }); callbacksRef.current = { onXxx };`.

### Broadcast Channel Pattern (for comparison)

Broadcast channels use a chainable pattern that avoids this issue:

```ts
channel
  .on("broadcast", { event: "game_event" }, (payload) => {
    onEventRef.current?.(payload.payload);
  })
  .subscribe((status) => {
    // handle status
  });
```

The `.on()` returns the channel, so `.subscribe()` is always called on the same chain. This pattern is safe because the `on()` and `subscribe()` happen in the same expression.

## Duplicate Variable Declaration After Patching

### Symptom

```
Ecmascript file had an error
const grouped = new Map<...>();
^^^^^ Duplicate declaration
```

### Root Cause

When using `patch` to replace code that declares a variable, the old declaration may remain if the replacement text doesn't fully overlap the original scope. This commonly happens when:

1. The `old_string` in the patch doesn't include the variable declaration line
2. A new declaration is added elsewhere in the file
3. Both the old and new declarations survive the patch

### Fix

After any patch that adds or moves a variable declaration, **search the file for duplicate declarations**:

```bash
grep -n "const grouped" src/components/dashboard/RosterPanel.tsx
```

If duplicates exist, remove the stale one. The stale declaration is typically the one that uses the old variable (e.g., `characters` instead of `displayCharacters`).

### Prevention

When patching code that declares variables:
- Include the full declaration + usage block in the `old_string`
- After patching, verify no duplicates remain with `grep -n "const <name>" <file>`
- If the variable is used in multiple places, replace the entire block (declaration + loop + usage) in a single patch
