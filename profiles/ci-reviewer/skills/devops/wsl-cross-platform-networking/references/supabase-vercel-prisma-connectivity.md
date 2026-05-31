# Supabase + Vercel + Prisma Connectivity

**Context**: Next.js app on Vercel with Supabase PostgreSQL, Prisma ORM, and local dev from WSL2.

## The IPv6 Problem

Supabase's direct database connection (`db.<ref>.supabase.co:5432`) resolves to **IPv6 only**. This breaks:
- **WSL2**: Cannot route IPv6 to external hosts
- **Vercel serverless functions**: Intermittent IPv6 connectivity issues

### Symptoms
- `GET /api/health` returns 503/500
- `connect ENETUNREACH 2600:1f1c:c19:4900:e7df:35e1:b21d:b138:5432`
- Prisma: `P1001: Can't reach database server`

## Solution: Supabase Pooler (Recommended)

Use Supabase's connection pooler, which resolves over IPv4:

```
postgresql://postgres.<ref>:<password>@aws-1-us-west-1.pooler.supabase.com:6543/postgres?sslmode=no-verify&pgbouncer=true
```

- Host: `aws-1-us-west-1.pooler.supabase.com` (resolves to 54.241.91.151)
- Port: `6543` (pgbouncer)
- Username: `postgres.<project_ref>` (note the project ref in the username)
- Requires `pgbouncer=true` parameter
- **Use `sslmode=no-verify`** — the `PrismaPg` adapter's `pg` Pool rejects the pooler's self-signed cert chain with `sslmode=require`. `no-verify` is required for the adapter to connect.

### Prisma Compatibility

The pooler uses pgbouncer in transaction mode. Prisma requires the `pg` adapter:

```typescript
// src/lib/prisma.ts
import { PrismaClient } from "@prisma/client";
import { PrismaPg } from "@prisma/adapter-pg";
import { Pool } from "pg";

const pool = new Pool({ connectionString: process.env.DATABASE_URL });
const adapter = new PrismaPg(pool);
const prisma = new PrismaClient({ adapter });
```

**Critical**: Prisma `$transaction` uses prepared statements which fail with pgbouncer (error P2028: "Transaction not found"). Replace all `$transaction` calls with sequential `prisma` operations.

### Prisma Config (Prisma 7+)

```typescript
// prisma.config.ts
import { defineConfig } from "prisma/config";
export default defineConfig({
  datasource: { url: process.env.DATABASE_URL },
});
```

```prisma
// schema.prisma
generator client {
  provider = "prisma-client-js"
  engineType = "client"
}
datasource db {
  provider = "postgresql"
}
```

## Schema Migration from WSL2 (Supabase Pooler DDL Workaround)

`prisma db push --force-reset` **times out** on Supabase's pgbouncer (DDL statements are long-running and pgbouncer drops them). The direct Supabase connection is IPv6-only (unreachable from WSL2). **Workaround**:

```bash
# Step 1: Drop old tables manually via raw SQL through the pooler
PGPASSWORD="<password>" psql -h aws-1-us-west-1.pooler.supabase.com -p 6543 \
  -U postgres.<ref> -d postgres -c "
DO \$\$
DECLARE r RECORD;
BEGIN
  FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
    EXECUTE 'DROP TABLE IF EXISTS \"' || r.tablename || '\" CASCADE';
  END LOOP;
END \$\$;
"

# Step 2: Generate SQL from Prisma schema
DATABASE_URL="postgresql://postgres.<ref>:<password>@aws-1-us-west-1.pooler.supabase.com:6543/postgres?sslmode=no-verify&pgbouncer=true" \
  npx prisma migrate diff --from-empty --to-schema prisma/schema.prisma --script > /tmp/schema.sql

# Step 3: Run the generated SQL directly via psql (bypasses Prisma's DDL timeout)
PGPASSWORD="<password>" psql -h aws-1-us-west-1.pooler.supabase.com -p 6543 \
  -U postgres.<ref> -d postgres -f /tmp/schema.sql
```

**Note**: "type already exists" errors from the previous partial schema are harmless — the new tables will still be created correctly.

## Seeding from WSL2

The seed script uses `PrismaPg` adapter which also needs `sslmode=no-verify`:

```bash
DATABASE_URL="postgresql://postgres.<ref>:<password>@aws-1-us-west-1.pooler.supabase.com:6543/postgres?sslmode=no-verify&pgbouncer=true" \
  npx tsx prisma/seed.ts
```

## Decision: Single Provider > Split

When a Supabase connectivity issue arises, the fix should stay within Supabase (pooler, Accelerate) rather than introducing a second database provider. Splitting across Neon + Supabase means:
- Two connection strings, two billing dashboards, two sets of env vars
- Data migration between providers
- Supabase Realtime Postgres Changes won't work on Neon tables
- Supabase Auth still needs Supabase anyway

**Rule**: Fix the connectivity, don't replace the provider.

## Verification

```bash
# Test pooler connectivity
PGPASSWORD="<password>" psql -h aws-1-us-west-1.pooler.supabase.com -p 6543 -U postgres.<ref> -d postgres -c "SELECT 1;"

# Test from app (local)
curl http://localhost:3000/api/health
# Expected: {"database": "connected", ...}

# Test from production
curl https://<your-app>.vercel.app/api/health
# Expected: {"database": "connected", "dbHost": "aws-1-us-west-1.pooler.supabase.com", ...}
```

## Common Pitfalls

1. **Wrong username format**: Pooler needs `postgres.<ref>`, not just `postgres`
2. **Missing pgbouncer=true**: Without it, pgbouncer rejects connections
3. **Using $transaction**: Prepared transactions fail in pgbouncer transaction mode
4. **Forgetting the adapter**: Prisma 7+ with `engineType=client` requires explicit `PrismaPg` adapter for pgbouncer
5. **sslmode=require with PrismaPg**: The `pg` Pool rejects the pooler's self-signed cert. Use `sslmode=no-verify`
6. **prisma db push --force-reset times out**: pgbouncer drops long-running DDL. Use the raw SQL workaround above
7. **Direct Supabase connection from WSL2**: IPv6-only, unreachable. Always use the pooler from WSL2
