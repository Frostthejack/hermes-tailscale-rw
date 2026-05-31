# Vercel Build Debugging Reference

## Common Build Failures and Fixes

### Missing Component Files

**Symptom:** `Module not found: Can't resolve './GameSettingsModal'` or similar import error in Vercel build logs.

**Cause:** A worker added an `import` statement for a component that doesn't exist on disk. This happens when workers add imports for components they plan to create but never actually create.

**Fix:**
1. Find the missing import: `grep -r "GameSettingsModal" src/` (or whatever the missing component is)
2. Check if the file exists: `ls src/components/session/GameSettingsModal.tsx`
3. If missing, create the component (even a minimal stub) and commit/push
4. Verify with `npx tsc --noEmit` before pushing

**Prevention:** After every worker commit, run `npx tsc --noEmit` to verify all imports resolve.

### Node Version Mismatch

**Symptom:** Build fails with syntax errors on modern JS features, or `engines` field warnings.

**Fix:** Add to `package.json`:
```json
{
  "engines": {
    "node": "20.x"
  }
}
```

### Prisma Generate Not Running

**Symptom:** `PrismaClientInitializationError` or `Unknown prisma model` errors.

**Fix:** Ensure `prisma generate` runs before build:
```json
{
  "scripts": {
    "dev": "prisma generate && next dev",
    "build": "prisma generate && next build"
  }
}
```

### Environment Variables Missing on Vercel

**Symptom:** `TypeError: Cannot read property 'SUPABASE_URL' of undefined` at runtime.

**Fix:** Add env vars to Vercel project settings (not just `.env.local`):
```bash
vercel env add NEXT_PUBLIC_SUPABASE_URL
vercel env add SUPABASE_SERVICE_ROLE_KEY
# etc.
```

### Duplicate/Stale Vercel Projects

**Symptom:** Deployments going to wrong project, or `vercel link` pointing to a stale project.

**Fix:**
```bash
# List all projects
vercel project ls

# Remove duplicates
vercel project rm <stale-project-id>

# Link to correct project
vercel link --project <correct-project-name>
```

## Build Verification Checklist

After any code change that affects the build:

1. `npx tsc --noEmit` — all imports resolve, no type errors
2. `npm run build` — production build succeeds
3. `git log --oneline -3` — changes are actually committed
4. `git push origin main` — changes are on remote
5. Check Vercel dashboard — new deployment triggered and green

## Reading Vercel Build Logs

```bash
# Latest deployment status
vercel ls

# Build logs for latest deployment
vercel logs <deployment-url>

# If deployment status is UNKNOWN
vercel logs --follow  # watch in real time
```

> **Tip:** If Vercel shows `UNKNOWN` status, it usually means the build hasn't started. Trigger with `git push origin main` or `vercel --force`.
