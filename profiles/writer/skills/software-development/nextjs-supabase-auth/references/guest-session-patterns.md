# Guest Session Auth — Patterns and Pitfalls

## The Cookie ↔ sessionStorage Disconnect

The most common bug in guest session apps: the server sets cookies (for middleware auth checks), but the client dashboard reads from `sessionStorage` (for UI state). These two storage mechanisms are completely disconnected.

**The fix is always the same**: after successful guest sign-in, write to `sessionStorage` before redirecting:

```tsx
await signInAsGuest(displayName);
sessionStorage.setItem("guestName", displayName); // Sync to client storage
router.push("/dashboard");
```

## Middleware vs Client Auth State

| Layer | Storage | Read by |
|-------|---------|---------|
| Middleware (server) | `rollsiege_session` cookie | `request.cookies.get()` |
| AuthContext (client) | API call to `/api/auth/session` or `/api/auth/guest` | `fetch()` |
| Dashboard UI (client) | `sessionStorage` | `sessionStorage.getItem()` |

These three layers can get out of sync. The middleware redirects unauthenticated users to `/`, but the client might still think it's authenticated (or vice versa).

## Conditional Rendering Trap

A common pattern that breaks guest users:

```tsx
// BAD — hides logout from guest users
{user && !user.isGuest && (
  <Button onClick={signOut}>Sign Out</Button>
)}

// GOOD — shows logout for all authenticated users
{user && (
  <Button onClick={signOut}>Sign Out</Button>
)}
```

**Rule**: Never gate core functionality (logout, settings, profile) behind `!user.isGuest`. Guest users need these too.

## Guest User ID Problem

APIs that require user identification (favorites, preferences, etc.) typically use an `x-user-id` header. But guest users don't have a Supabase `authId` — their `authId` is typically `""` or `null`.

**Options**:
1. **Use the guest's `id` from the session cookie** (e.g., `guest_123456`) — but this is a client-generated ID, not a DB user ID
2. **Store guest data in `localStorage` instead of the database** — works for device-local features, no auth needed
3. **Create a database record for guest users** — gives them a real `authId` that works with existing APIs

**Recommendation**: For features that should persist across devices, create a DB record. For device-local features, use `localStorage`.

**Pitfall**: If your API uses `x-user-id` header to look up the user in the DB, guest users will get 401 because their `authId` doesn't match any DB record. Either:
- Make the API handle guest users (look up by guest ID or skip auth for certain endpoints)
- Or store guest-specific data client-side in `localStorage`

**Example**: Favorites for guest users should use `localStorage` keyed by character ID, not the `/api/user/favorites` endpoint.

## Sign-Out for Guests

The sign-out flow must clear both server cookies and client storage:

```tsx
const signOut = useCallback(async () => {
  // Clear client-readable cookies
  document.cookie = "rollsiege_guest=;path=/;max-age=0;samesite=lax";
  document.cookie = "rollsiege_display_name=;path=/;max-age=0;samesite=lax";

  // Clear server session (httpOnly cookie — needs server call)
  await fetch("/api/auth/signout", { method: "POST" });

  // Clear client state
  setUser(null);
  window.location.href = "/";
}, []);
```

Note: `sessionStorage` is automatically cleared when the tab closes, so explicit cleanup isn't strictly necessary, but it's good practice.
