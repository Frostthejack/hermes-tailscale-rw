# Supabase OAuth Redirect Checklist

Use this when setting up or debugging OAuth (Google/Discord) in a Next.js + Supabase app.

## Pre-Flight

- [ ] `NEXT_PUBLIC_APP_URL` set in Vercel env vars (production URL, NOT localhost)
- [ ] `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` set
- [ ] `SUPABASE_SERVICE_ROLE_KEY` set (for server-side admin operations)

## Supabase Dashboard → Authentication → URL Configuration

- [ ] **Site URL** = `https://your-app.vercel.app` (not localhost)
- [ ] **Redirect URLs** includes `https://your-app.vercel.app/api/auth/callback`
- [ ] Remove any stale localhost redirect URLs (or keep only for local dev project)

## Google Cloud Console → Credentials → OAuth 2.0 Client

- [ ] **Authorized redirect URIs** includes `https://YOUR-PROJECT-REF.supabase.co/auth/v1/callback`
  - **IMPORTANT**: This is Supabase's OWN callback endpoint, NOT your app's callback URL
  - Google → Supabase → your app (two-step redirect chain)
  - The flow: Google redirects to Supabase → Supabase processes OAuth → Supabase redirects to your `redirectTo` URL
- [ ] Do NOT put your app's callback URL (`https://your-app.vercel.app/api/auth/callback`) here — that goes in Supabase's redirect URL whitelist instead

## The Two-Step Redirect Chain (Critical to Understand)

```
Your App → Google Consent → Google redirects to Supabase → Supabase redirects to Your App
```

1. Your app calls `supabase.auth.signInWithOAuth({ options: { redirectTo: "https://your-app.vercel.app/api/auth/callback" } })`
2. User completes Google consent
3. Google redirects to: `https://YOUR-PROJECT-REF.supabase.co/auth/v1/callback` (registered in Google Cloud Console)
4. Supabase processes the OAuth response
5. Supabase redirects to: `https://your-app.vercel.app/api/auth/callback?code=...` (the `redirectTo` from step 1, must be in Supabase's redirect URL whitelist)
6. Your callback route exchanges `code` for session

**Common confusion**: The `redirectTo` in your code is NOT what you register in Google Cloud Console. Google talks to Supabase; Supabase talks to your app.

## Code Checklist

- [ ] `flowType: "pkce"` set in `signInWithOAuth` options
- [ ] Client-side hash fragment handler added to auth context (safety net)
- [ ] Callback route uses `exchangeCodeForSession(code)` for PKCE
- [ ] Session cookie is `httpOnly`, `secure` in production, `sameSite: "lax"`
- [ ] Cookie `path: "/"` so it's sent with all requests

## Verification

1. Open browser dev tools → Network tab
2. Click "Sign in with Google"
3. Observe the redirect chain:
   - Your app → Google consent → back to your callback URL
   - **PKCE**: callback URL has `?code=...` (query param)
   - **Implicit (wrong)**: callback URL has `#access_token=...` (hash fragment)
4. After callback, check Application → Cookies for your session cookie
5. Verify no `localhost` URLs appear in the redirect chain on production
