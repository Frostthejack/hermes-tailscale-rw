# Database Connectivity Debugging (Next.js / Prisma / Neon / Supabase)

## When to Use

Use this guide when debugging database connection failures in Next.js applications using Prisma ORM, especially when the stack involves Supabase, Neon, or local PostgreSQL.

## Quick Diagnostic Flow

### 1. Check the Health Endpoint

```bash
# Production
curl -s https://<app>.vercel.app/api/health | python3 -m json.tool

# Local
curl -s http://localhost:3000/api/health | python3 -m json.tool
```

**Key fields to read:**
- `database: "connected"` → DB is fine, problem is elsewhere
- `database: "error"` → Check `dbError` and `dbStack` for specifics
- `dbHost`, `dbPort`, `dbUser`, `dbName` → Shows which DB the app is actually connecting to
- `hasDbUrl: false` → DATABASE_URL env var is missing entirely

### 2. Identify the Error Pattern

| Error | Meaning | Typical Cause |
|-------|---------|---------------|
| `ENETUNREACH <IPv6>` | Can't route to IPv6 address | Supabase direct connection from WSL2 or Vercel serverless |
| `ECONNREFUSED` | Nothing listening on that host:port | Wrong host, wrong port, or service not running |
| `FATAL: password authentication failed` | Wrong password | Placeholder `***` in .env file, or wrong credentials |
| `FATAL: database "X" does not not exist` | DB name wrong | Typo in DB name, or different DB than expected |
| `P1010: User was denied access` | Auth method mismatch | Peer auth vs password vs md5 |
| `Can't reach database server` | Network-level failure | Firewall, wrong IP, service down |

### 3. Check Which Database Is Actually Configured

**Don't assume — verify.** The project may have been migrated between providers.

```bash
# Check local env
cat .env.local | grep DATABASE_URL

# Check production env file (local reference only)
cat .env.production | grep DATABASE_URL

# Check Vercel production env (the real production config)
vercel env pull .env.vercel.production --environment=production
cat .env.vercel.production | grep DATABASE_URL
```

**Common patterns:**
- `localhost:5432` → Local PostgreSQL
- `db.<project>.supabase.co:5432` → Supabase direct (IPv6, often broken from WSL2/Vercel)
- `aws-1-us-west-1.pooler.supabase.com:6543` → Supabase pooler (IPv4, pgbouncer)
- `*.neon.tech:5432` → Neon direct
- `*-pooler.neon.tech:5432` → Neon pooler

### 4. Test Each Connection Path

```bash
# Test local Postgres
pg_isready -h localhost -p 5432
psql -h localhost -U postgres -d <dbname> -c "SELECT 1;"

# Test Supabase pooler
PGPASSWORD="<password>" psql -h aws-1-us-west-1.pooler.supabase.com -p 6543 \
  -U postgres.<project-ref> -d postgres -c "SELECT 1;"

# Test Neon pooler
PGPASSWORD="<password>" psql -h <endpoint>-pooler.c-7.us-east-1.aws.neon.tech -p 5432 \
  -U neondb_owner -d neondb -c "SELECT 1;"
```

### 5. Check Prisma Configuration

**Prisma 7+ pattern** (datasource URL in `prisma.config.ts`, not `schema.prisma`):

```typescript
// prisma.config.ts
import { defineConfig } from "prisma/config";
export default defineConfig({
  datasource: {
    url: process.env.DATABASE_URL,
  },
});
```

```typescript
// schema.prisma — no datasource URL here in Prisma 7+
datasource db {
  provider = "postgresql"
}
```

**Prisma 7+ with pg adapter** (for pgbouncer/pooler compatibility):

```typescript
// src/lib/prisma.ts
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Pool } from "pg";

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const adapter = new PrismaPg(pool);
const client = new PrismaClient({ adapter });
```

**Key insight:** When using pgbouncer (Supabase pooler or Neon pooler), the `PrismaPg` adapter with `Pool` from `pg` is required. The default PrismaClient doesn't work well with transaction-mode pooling.

### 6. Fix Patterns by Scenario

#### Scenario A: Supabase Direct → Pooler Migration

**Symptom:** `ENETUNREACH` on IPv6 address in health endpoint.

**Fix:** Update DATABASE_URL to use pooler:
```
# Before (broken)
postgresql://postgres:<password>@db.<project>.supabase.co:5432/postgres

# After (Supabase pooler)
postgresql://postgres.<project>:<password>@aws-1-us-west-1.pooler.supabase.com:6543/postgres?sslmode=require&pgbouncer=true
```

#### Scenario B: Local Postgres Password Placeholder

**Symptom:** `FATAL: password authentication failed` or `***` in .env file.

**Fix:** Set the actual password:
```bash
# Option 1: Set password for postgres user
sudo -u postgres psql -c "ALTER USER postgres PASSWORD '<password>';"

# Option 2: Use socket auth (no password needed)
# In .env.local:
DATABASE_URL="postgresql:///rollsiege?host=/var/run/postgresql"
```

#### Scenario C: Vercel Production Uses Unpooled Neon

**Symptom:** Production health shows `database: error` but local works.

**Fix:** Check if production `DATABASE_URL` uses unpooled Neon. Switch to pooled:
```
# Before (unpooled, may fail in serverless)
postgresql://neondb_owner:<password>@<endpoint>.c-7.us-east-1.aws.neon.tech/neondb?sslmode=require

# After (pooled, works in serverless)
postgresql://neondb_owner:<password>@<endpoint>-pooler.c-7.us-east-1.aws.neon.tech/neondb?channel_binding=require&sslmode=require
```

Update via Vercel CLI:
```bash
vercel env rm DATABASE_URL --environment=production
echo "postgresql://..." | vercel env add DATABASE_URL production
```

## Common Pitfalls

1. **Editing `.env.production` doesn't change production.** That file is a local reference. Use `vercel env` commands for actual production changes.

2. **The `***` in `.env` files is a placeholder**, not a real password. It means "the real value is stored elsewhere (Vercel encrypted env vars)".

3. **WSL2 cannot route IPv6** to Supabase direct connections. Always use the pooler (port 6543) from WSL2.

4. **Prisma `db execute` requires `DATABASE_URL` as env var**, not from `.env` file. Use `export DATABASE_URL=...` before running Prisma CLI commands.

5. **Don't assume the DB provider from the project name.** A project named "RollSiege" configured with Supabase might have been migrated to Neon. Always check the actual connection string.

## Verification After Fix

```bash
# 1. Local health check
curl -s http://localhost:3000/api/health | python3 -m json.tool

# 2. Local API check
curl -s http://localhost:3000/api/characters | python3 -m json.tool

# 3. Production health check
curl -s https://<app>.vercel.app/api/health | python3 -m json.tool

# 4. Run tests
npx playwright test
```
