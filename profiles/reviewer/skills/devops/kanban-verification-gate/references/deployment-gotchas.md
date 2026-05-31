# Web App Deployment Gotchas — RollSiege Patterns

## Supabase Auth Email Redirects

**Problem:** Confirmation/reset emails contain `localhost:3000` links instead of the production URL.

**Root cause:** `NEXT_PUBLIC_APP_URL` not set in Vercel production env vars. The code fallback `request.nextUrl.origin` works in production BUT only if the env var is unset — if it's set to a stale/local value, that stale value wins.

**Fix pattern:**
```typescript
// Defensive: hardcode production URL for auth redirects
emailRedirectTo: `https://rollsiege.vercel.app/auth/confirm`
```
Also set `NEXT_PUBLIC_APP_URL=https://rollsiege.vercel.app` in Vercel env vars.

**Supabase dashboard config needed:**
- Authentication → URL Configuration → Site URL: `https://rollsiege.vercel.app`
- Authentication → URL Configuration → Redirect URLs: `https://rollsiege.vercel.app/auth/confirm`, `https://rollsiege.vercel.app/api/auth/callback`

## Supabase Email Templates

**Cannot be customized from client code.** The `signUp()` call triggers Supabase server-side email. To customize:
1. Supabase Dashboard → Authentication → Email Templates → edit HTML
2. Or set up custom SMTP (Resend, SendGrid) in Supabase Dashboard → Authentication → SMTP Settings

**Template variables available:** `{{ .ConfirmationURL }}`, `{{ .Email }}`, `{{ .Token }}`, `{{ .TokenHash }}`, `{{ .SiteURL }}`

## Vercel Duplicate Deployments

**Problem:** Multiple Vercel projects connected to the same GitHub repo (e.g., `rollsiege` and `rollsiege-fresh`). Each deploys on every push to main.

**Cause:** Kanban workers or users creating separate Vercel projects linked to the same repo.

**Fix:** Delete duplicate projects from Vercel dashboard. Only keep one production deployment per repo/branch.

## Environment Variable Gotchas

- `.env.example` often has `localhost:3000` defaults — these are for local dev only
- `NEXT_PUBLIC_*` vars are baked in at build time, not runtime — changing them requires a redeploy
- Always verify production env vars match what the code expects: `vercel env pull` or check Vercel dashboard
- Common failure: code works locally (correct `.env.local`) but production uses wrong values

## Dashboard/Auth Wall Pattern

**Problem:** If the landing page requires auth (OAuth) before users can access the dashboard, ALL dashboard features become untestable without credentials.

**Pattern:** Provide a guest/name-based entry flow alongside OAuth. The PRD requires "What is your name, Challenger?" — this should work without any OAuth. OAuth is for persistent accounts (favorites, team presets, session history).

**Deploy-from-roster outside sessions:** Users should be able to deploy characters to their field BEFORE joining a session (to prepare their roster). The field should work in "local mode" when not in a session.

## Vercel Deployment Stuck in UNKNOWN

**Problem:** Vercel deployment shows `UNKNOWN` status, `vercel inspect` shows `0ms` build time, `vercel logs` times out.

**Root causes and fixes:**

1. **Invalid git author email** — Vercel blocks deployments if the commit author email is not a valid/recognized email address.
   - Fix: `git config --global user.email "your-real-email@gmail.com"` then `git commit --amend --no-edit --reset-author` and force push.
   - Verify: `git log --format="%ae" -1` should show a real email.

2. **Linked to wrong Vercel project** — The git repo is connected to a different Vercel project than the one with the production alias.
   - Fix: `vercel link --project <correct-project-name> --yes` from the project directory.
   - Verify: `vercel inspect <deployment-url>` should show the correct project name.

3. **Build command or output directory misconfiguration** — Check Vercel dashboard → Project Settings → Build & Output Settings.
   - For Next.js: Framework preset should be `Next.js`, build command `next build`, output directory `.next`.

## Cookie `secure` Flag on Vercel

**Problem:** Auth cookies are silently rejected by the browser after OAuth redirect. User gets redirected back to landing page instead of staying logged in.

**Root cause:** Using `secure: process.env.NODE_ENV === "production"` for cookie configuration. On Vercel, `NODE_ENV` may NOT be `"production"` even in production deployments (it can be `"development"` or undefined during build).

**Fix:** Always use `secure: true` for cookies. Vercel serves all traffic over HTTPS at the edge, so `secure: true` is always correct.

```ts
// WRONG — breaks on Vercel
secure: process.env.NODE_ENV === "production",

// CORRECT — always HTTPS on Vercel
secure: true,
```

**Affected files:** Any file that sets auth cookies — `src/lib/auth.ts`, `src/app/api/auth/callback/route.ts`, `src/app/api/auth/handle-implicit/route.ts`, guest sign-in route.

## Google OAuth Redirect URI

**Problem:** Google OAuth fails with `redirect_uri_mismatch`.

**Root cause:** Google Cloud Console is configured with the app's callback URL instead of Supabase's callback URL.

**Fix:** In Google Cloud Console → Credentials → OAuth 2.0 Client → Authorized redirect URIs, set:
```
https://your-project-ref.supabase.co/auth/v1/callback
```
NOT `https://your-app.vercel.app/api/auth/callback`.

**Why:** The OAuth flow is two-hop: Google → Supabase → your app. Google talks to Supabase, not directly to your app. Supabase processes the OAuth response and then redirects to your app's callback URL.
