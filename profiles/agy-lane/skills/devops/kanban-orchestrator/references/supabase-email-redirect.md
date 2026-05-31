# Supabase Email Confirmation Redirect Issue

## Problem
When users sign up with email, Supabase sends a confirmation email. The link in that email points to the `emailRedirectTo` URL configured in the `signUp` call.

If `NEXT_PUBLIC_APP_URL` is not set correctly in the production environment, the fallback (`request.nextUrl.origin` or `localhost:3000`) causes the confirmation link to point to the wrong URL.

## Root Cause
In `src/app/api/auth/email-signup/route.ts`:
```typescript
emailRedirectTo: `${process.env.NEXT_PUBLIC_APP_URL ?? request.nextUrl.origin}/auth/confirm`
```

If `NEXT_PUBLIC_APP_URL` is `http://localhost:3000` (from `.env.example`) or unset, Supabase uses that as the base URL for redirect links.

## Fix
1. Set `NEXT_PUBLIC_APP_URL=https://rollsiege.vercel.app` in Vercel production env vars
2. Also set it in Supabase Dashboard → Authentication → URL Configuration → Site URL
3. Hardcode the URL in code as defensive fix:
   ```typescript
   emailRedirectTo: 'https://rollsiege.vercel.app/auth/confirm'
   ```
4. Update all auth routes that use `process.env.NEXT_PUBLIC_APP_URL` to use the production URL

## Verification
- Sign up with email → check email → confirmation link should point to production URL
- Click link → should confirm and redirect to dashboard
- CI tests must pass before marking task done
