# Supabase Realtime — postgres_changes Subscription Pitfall

## The Error

```
Uncaught Error: cannot add postgres_changes callbacks for realtime:game:<sessionId>:db after subscribe()
```

## Root Cause

Supabase Realtime v2 requires ALL `postgres_changes` listeners to be registered **before** `subscribe()` is called. Once a channel is subscribed, adding new `.on("postgres_changes", ...)` handlers throws this error.

The core issue: `supabase.channel(name)` returns the **same internal channel object** for the same name. Even after `removeChannel()`, Supabase's internal registry may still reference the old channel. When the effect re-renders (React strict mode double-mount, rapid sessionId change, or multiple components mounting simultaneously), the second `supabase.channel(sameName)` returns an already-subscribed channel.

## Failed Fixes (don't waste time on these)

- **Unique channel name with `Date.now()` suffix** — Date.now() can collide if two effects run in the same millisecond
- **Async `await supabase.removeChannel()`** — doesn't guarantee the channel is fully torn down before the next effect run
- **Conditional `if (callbackRef.current)` guards** around `.on()` calls — these can cause subscribe to fire before all listeners are registered
- **Module-level channel cache (`Map<string, RealtimeChannel>`)** — `supabase.channel(name)` still returns the same internal object even before `removeChannel` completes. The cache check passes but the channel is already subscribed from a previous mount.

## Working Fix: Unique Channel Name Per Hook Instance

Use `crypto.randomUUID()` to generate a truly unique channel name for every hook instance/effect run:

```typescript
export function useGamePostgresChanges({ sessionId, ...callbacks }) {
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null);

  useEffect(() => {
    if (!sessionId) return;

    // CRITICAL: Each hook instance must use a UNIQUE channel name.
    // supabase.channel(name) returns the SAME internal channel for the same name.
    // If that channel is already subscribed, calling .on("postgres_changes") throws.
    const uniqueKey = `${gameChannelName(sessionId)}:db:${crypto.randomUUID()}`;
    const channel = supabase.channel(uniqueKey);

    // Register ALL postgres_changes listeners BEFORE subscribing
    channel.on("postgres_changes", { event: "*", schema: "public", table: "Session", filter: `id=eq.${sessionId}` }, handler1);
    channel.on("postgres_changes", { event: "*", schema: "public", table: "SessionPlayer", filter: `sessionId=eq.${sessionId}` }, handler2);
    // ... all listeners

    channel.subscribe((status) => {
      if (status === "SUBSCRIBED") { /* ... */ }
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
}
```

**Trade-off**: Each hook instance creates its own channel (not shared). This is slightly more resource usage but guarantees no collisions. For most apps with 2-3 concurrent components using this hook, the overhead is negligible.

**Key insight**: The problem isn't about sharing channels — it's about channel name collision in Supabase's internal registry. Unique names per instance completely avoid this.

## Files Where This Pattern Was Applied

- `src/hooks/useGamePostgresChanges.ts` — RollSiege project, fixed 2026-05-16 (v4)
