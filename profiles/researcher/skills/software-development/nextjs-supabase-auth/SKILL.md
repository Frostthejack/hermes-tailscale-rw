---
name: nextjs-supabase-auth
description: Next.js + Supabase authentication patterns — OAuth (Google/Discord), PKCE flow, redirect URI configuration, session management with cookies, and common pitfalls. Load when building or debugging auth in a Next.js app using Supabase.
---

# Next.js + Supabase Auth

## Architecture Overview

The recommended pattern for Next.js + Supabase auth:

1. **Frontend** calls a backend API route (`POST /api/auth/signin`) with `{ provider: "google" | "discord" }`
2. **Backend** calls `supabase.auth.signInWithOAuth()` and returns the OAuth URL
3. **Frontend** does `window.location.href = data.url` — full page redirect to provider
4. **Provider** redirects back to `/api/auth/callback` with auth code (PKCE) or token (implicit)
5. **Callback route** exchanges code for session, sets cookie, redirects to app

## Critical: Force PKCE Flow

Supabase server-side `signInWithOAuth` can default to **implicit flow** (token in URL hash `#access_token=...`). Hash fragments never reach the server, so your callback route can't process them.

**Always explicitly set `flowType: 'pkce'`:**

```ts
const { data, error } = await supabase.auth.signInWithOAuth({
  provider: "google",
  options: {
    redirectTo: `${baseUrl}/api/auth/callback?redirect=${encodeURIComponent("/dashboard")}`,
    flowType: "pkce", // ← REQUIRED
  },
});
```

## Safety Net: Client-Side Hash Handler

Even with PKCE forced, some configurations may still produce implicit flow redirects. Add a client-side handler in your auth context/provider:

```tsx
useEffect(() => {
  const hash = window.location.hash;
  if (hash && hash.includes("access_token")) {
    const params = new URLSearchParams(hash.replace(/^#/, ""));
    const accessToken = params.get("access_token");
    const refreshToken = params.get("refresh_token") || "";

    if (accessToken) {
      // Clear hash immediately (token is sensitive)
      window.history.replaceState(null, "", window.location.pathname + window.location.search);

      fetch("/api/auth/handle-implicit", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ accessToken, refreshToken }),
      })
        .then((res) => res.json())
        .then((data) => {
          if (data.redirectTo) window.location.href = data.redirectTo;
        });
      return;
    }
  }
  // ... normal session check
}, []);
```

## Redirect URI Configuration (3 Places)

OAuth redirect URIs must match in **all three** places:

### 1. Supabase Dashboard
- **Authentication → URL Configuration → Site URL**: `https://your-app.vercel.app`
- **Redirect URLs**: `https://your-app.vercel.app/api/auth/callback`

### 2. OAuth Provider (e.g., Google Cloud Console)
- **Credentials → OAuth 2.0 Client → Authorized redirect URIs**: `https://your-project-ref.supabase.co/auth/v1/callback`
- This is Supabase's OAuth callback endpoint — Google redirects to Supabase, then Supabase processes the response and redirects to your app's callback URL
- Do NOT put your app's callback URL here — Google talks to Supabase, not directly to your app

### 3. Vercel Environment Variables
- `NEXT_PUBLIC_APP_URL=https://your-app.vercel.app`
- `NEXT_PUBLIC_SUPABASE_URL=https://your-project-ref.supabase.co`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key`

## Building the Callback URL

Use a fallback chain so it works in all environments:

```ts
const baseUrl =
  process.env.NEXT_PUBLIC_APP_URL ??
  (process.env.VERCEL_URL ? `https://${process.env.VERCEL_URL}` : null) ??
  request.nextUrl.origin;
const callbackUrl = `${baseUrl}/api/auth/callback`;
```

## Guest Session Pattern

For apps supporting both OAuth and guest (name-entry) auth, use a unified cookie-based approach:

### Cookie Setup (Guest Sign-In)

```ts
// POST /api/auth/guest
const response = NextResponse.json({ user: guestUser });

// Session cookie (httpOnly — read by middleware for auth checks)
response.cookies.set("rollsiege_session",
  JSON.stringify({ guest: true, displayName, id: guestId }),
  { httpOnly: true, secure: true, sameSite: "lax", path: "/", maxAge: 60 * 60 * 24 * 30 }
);

// Display name cookie (client-readable — fallback for guest detection)
response.cookies.set("rollsiege_display_name", displayName,
  { httpOnly: false, secure: true, sameSite: "lax", path: "/", maxAge: 60 * 60 * 24 * 30 }
);

// Guest data cookie (client-readable)
response.cookies.set("rollsiege_guest", JSON.stringify({ id, displayName }),
  { httpOnly: false, secure: true, sameSite: "lax", path: "/", maxAge: 60 * 60 * 24 * 30 }
);

return response;
```

### Middleware Auth Check

Check for session cookie OR display name cookie (guest fallback):

```ts
function isAuthenticated(request: NextRequest): boolean {
  const sessionCookie = request.cookies.get("rollsiege_session")?.value;
  if (sessionCookie) return true;

  const displayNameCookie = request.cookies.get("rollsiest_display_name")?.value;
  if (displayNameCookie && decodeURIComponent(displayNameCookie).trim().length > 0) {
    return true;
  }

  return false;
}
```

### Client-Side State Sync (Critical)

**Pitfall**: The server sets cookies, but the client dashboard reads from `sessionStorage`. These are disconnected — the dashboard won't know the guest name unless you explicitly sync.

**Fix**: After successful guest sign-in, store the name in `sessionStorage` before redirecting:

```tsx
// Landing page — after signInAsGuest succeeds
await signInAsGuest(trimmed);
sessionStorage.setItem("guestName", trimmed); // ← Required for dashboard pre-fill
router.push("/dashboard");
```

Then on the dashboard, read from `sessionStorage` on mount:

```tsx
useEffect(() => {
  const stored = sessionStorage.getItem("guestName");
  if (stored) {
    setGuestName(stored);
    setNameInput(stored);
  }
}, []);
```

### Guest User ID for API Calls

Guest users don't have a Supabase `authId`. For APIs that need user identification (e.g., favorites), you have two options:

1. **Use a guest-specific identifier** (e.g., `guest_` prefix from the session cookie)
2. **Make the API work without auth for guest users** (store favorites in localStorage instead)

If using the `x-user-id` header pattern, extract it from the auth context:

```tsx
// In the component
const { user } = useAuth();
// user.authId is "" for guests — handle this case
const authId = user?.authId || user?.id || null;
```

## Common Pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| Redirects to `localhost:3000` on production | `NEXT_PUBLIC_APP_URL` not set or still `localhost` | Set env var on Vercel |
| `#access_token` in URL but no session | Implicit flow, hash never reaches server | Force `flowType: 'pkce'` + add client hash handler |
| `redirect_uri_mismatch` from Google | URI not registered in Google Cloud Console | Add exact callback URI to authorized redirects |
| Session cookie not set | Callback route doesn't set cookie before redirect | Set `httpOnly` cookie in callback response |
| Infinite redirect loop | Cookie not being read / session not persisting | Check cookie `path`, `sameSite`, `secure` settings |
| Guest name lost on page refresh | Dashboard reads from sessionStorage but landing page never writes to it | Write to sessionStorage after signInAsGuest |
| Guest users can't access features gated by `!user.isGuest` | Conditional rendering excludes guests | Show UI for all authenticated users; vary text/behavior by `user.isGuest` |
| Favorites API returns 401 for guests | API requires `x-user-id` header but guests have no authId | Use guest ID or fall back to localStorage for guests |
| Session cookie silently rejected by Browser | `secure: process.env.NODE_ENV === "production"` — NODE_ENV not "production" on Vercel | Always use `secure: true` |
| Google OAuth redirects to landing page | Google redirect URI set to app URL instead of Supabase callback | Set Google redirect URI to `https://project-ref.supabase.co/auth/v1/callback` |
| Vercel deployment stuck in UNKNOWN | Git author email is invalid (not a real email) | Set `git config --global user.email` to a valid email matching GitHub account |
| Vercel build fails with `Module not found` for a component | Worker committed code that imports a component file that was never created | After worker commits, run `npx tsc --noEmit` to check all imports resolve; also `git diff --name-only` + `ls` to verify created files exist |
| `flowType` TypeScript error in signin route | `@supabase/supabase-js` v2.105.4 and earlier don't include `flowType` in the `SignInWithOAuthOptions` type | **Do NOT add `flowType: "pkce"`** — Supabase v2 defaults to PKCE anyway. If a previous fix added it, simply remove it. The redirect will still use PKCE by default. Only add it back if you've verified the installed version supports it (check `npm ls @supabase/supabase-js`) |
| Duplicate Vercel projects | Multiple projects created for same repo | Delete unused projects in Vercel dashboard; keep only the one with the production alias |
| "Character not found for this session player" on deploy | Sending roster `Character.id` instead of `SessionCharacter.id` to deploy API | Create session character first via `POST /api/sessions/[code]/characters`, then deploy using the returned `sessionCharacter.id` |
| Session page shows "can't load" after join | `sessionPlayerId` not persisted to localStorage before navigation | Store `localStorage.setItem('sessionPlayerId:' + joinCode, player.id)` in SessionContext after create/join |
| User must manually click "Go to Session" | Dashboard doesn't auto-navigate after create/join | Use `window.location.href = '/sessions/' + joinCode` after successful create/join |
| Realtime "cannot add postgres_changes callbacks after subscribe()" | Conditional `channel.on()` guards or race condition on re-subscription | See `references/supabase-realtime-patterns.md` |

## Session Cookie Pattern

Store tokens in an `httpOnly` cookie as JSON:

```ts
response.cookies.set(
  "rollsiege_session",
  JSON.stringify({ accessToken, refreshToken }),
  {
    httpOnly: true,
    secure: true, // Always true — app is always HTTPS on Vercel
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24 * 30, // 30 days
  }
);
```

**IMPORTANT:** Do NOT use `secure: process.env.NODE_ENV === "production"`. On Vercel, `NODE_ENV` may not be `"production"` even in production deployments. The app is always served over HTTPS on Vercel, so `secure: true` is always correct. Using the `NODE_ENV` check causes the browser to silently reject the cookie, resulting in the user being redirected back to the landing page after OAuth.

Then read it in server-side auth utilities via `cookies().get("rollsiege_session")`.

## See Also

- `references/supabase-redirect-checklist.md` — deployment checklist for redirect URI configuration
- `references/guest-session-patterns.md` — guest session auth patterns, cookie/sessionStorage sync, and common pitfalls
- `references/session-player-persistence.md` — session player ID persistence across page navigations, auto-navigation after create/join, and the two-tier character model pitfall (roster Character vs SessionCharacter)
- `references/supabase-realtime-patterns.md` — Supabase Realtime `postgres_changes` subscription errors (including "cannot add callbacks after subscribe()"), the correct channel setup pattern, and the duplicate variable declaration pitfall after patching
