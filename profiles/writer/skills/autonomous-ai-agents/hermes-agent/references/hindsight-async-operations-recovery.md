# Hindsight Async Operations: Stuck Tasks and Recovery

## Problem

The `async_operations` table in Hindsight's PostgreSQL database can accumulate tasks stuck in `processing` or `pending` state indefinitely. This happens when:

1. The Hindsight API process crashes or is restarted while tasks are in-flight
2. A worker claims a task (setting status to `processing`) but never completes it
3. The API's in-process worker poller doesn't have a reaper/timeout mechanism for stale tasks

As of May 2026, there is **no automatic recovery** -- once a task is stuck in `processing`, it stays there forever unless manually reset.

## Symptoms

- Dashboard shows operations count with `processing` or `pending` that never decreases
- New operations complete fine but the stuck ones remain
- `pending_consolidation` stat (from `memory_units.consolidated_at IS NULL`) grows unbounded because consolidation tasks are stuck
- The stuck operations are often days or weeks old with `retry_count = 0`

## Diagnosis

### Connect to the Database

The Hindsight API's DB credentials are in the process environment (the `HINDSIGHT_API_DATABASE_URL` env var is masked with `***` in the process listing, so read it directly from `/proc`):

```bash
# Read DB URL from the running Hindsight API process
python3 << 'EOF'
from urllib.parse import urlparse

with open('/proc/<hindsight-pid>/environ', 'rb') as f:
    env_data = f.read()

env = {}
for entry in env_data.split(b'\x00'):
    if b'=' in entry:
        key, _, value = entry.partition(b'=')
        env[key.decode('utf-8', errors='replace')] = value.decode('utf-8', errors='replace')

db_url = env.get('HINDSIGHT_API_DATABASE_URL', '')
parsed = urlparse(db_url)
print(f"Host: {parsed.hostname}")
print(f"Port: {parsed.port}")
print(f"Database: {parsed.path[1:]}")
print(f"Username: {parsed.username}")
# Password: parsed.password
EOF
```

Find the Hindsight PID: `ps aux | grep hindsight-api`

### Query Stuck Operations

Use the Hindsight API's own Python environment to avoid dependency issues:

```bash
/home/frostthejack/.local/share/pipx/venvs/hindsight-api/bin/python3 << 'EOF'
import psycopg2
from urllib.parse import urlparse

# Read DB URL from process environment
with open('/proc/<hindsight-pid>/environ', 'rb') as f:
    env_data = f.read()
env = {}
for entry in env_data.split(b'\x00'):
    if b'=' in entry:
        key, _, value = entry.partition(b'=')
        env[key.decode('utf-8', errors='replace')] = value.decode('utf-8', errors='replace')

conn = psycopg2.connect(env['HINDSIGHT_API_DATABASE_URL'])
cur = conn.cursor()

# Summary by status
cur.execute("SELECT status, COUNT(*) FROM async_operations GROUP BY status")
print("Operations by status:")
for row in cur.fetchall():
    print(f"  {row[0]}: {row[1]}")

# Stuck operations
cur.execute("""
    SELECT operation_id, operation_type, status, bank_id,
           created_at, updated_at, retry_count,
           EXTRACT(EPOCH FROM (NOW() - updated_at))/3600 as hours_stale
    FROM async_operations
    WHERE status IN ('processing', 'pending')
    ORDER BY updated_at ASC
""")
print("\nStuck operations:")
for row in cur.fetchall():
    print(f"  {row[1]} / {row[2]} / {row[3]} -- {row[7]:.1f}h stale (id={row[0]})")

# Unconsolidated memory units (what dashboard calls "pending consolidations")
cur.execute("SELECT COUNT(*) FROM memory_units WHERE consolidated_at IS NULL")
print(f"\nUnconsolidated memory_units: {cur.fetchone()[0]}")

conn.close()
EOF
```

### What the Numbers Mean

- `async_operations` `processing`/`pending`: Tasks stuck in the operation queue
- `memory_units` where `consolidated_at IS NULL`: Individual facts waiting for consolidation dedup. This number (e.g., 4000+) is what the dashboard shows as "pending consolidations" -- it is NOT the same as pending `async_operations` consolidation tasks
- The consolidation `async_operations` tasks are the workers that process the unconsolidated memory_units. When those workers are stuck, the unconsolidated count grows

## Fix: Reset Stuck Operations

```python
import psycopg2

conn = psycopg2.connect(db_url)
cur = conn.cursor()

# Reset stuck 'processing' tasks back to 'pending' and increment retry
cur.execute("""
    UPDATE async_operations
    SET status = 'pending',
        retry_count = retry_count + 1,
        updated_at = NOW()
    WHERE status = 'processing'
""")
print(f"Reset {cur.rowcount} processing tasks to pending")

conn.commit()
conn.close()
```

After resetting, the Hindsight API's worker poller should pick up the `pending` tasks on its next poll cycle (typically within seconds).

## Key Pitfall: `hindsight-admin worker-status` Tries to Start Embedded PostgreSQL

The `hindsight-admin worker-status` command attempts to start an embedded PostgreSQL instance (pg0) and will hang/time out if PG is already running on the expected port. It does NOT show worker status for the running Hindsight API instance. To inspect operations, query the database directly as shown above.

## Prevention

- **Monitor**: Set up a periodic check (cron) for operations stuck in `processing` for more than 1 hour
- **Avoid mid-task restarts**: Don't restart the Hindsight API while operations are in-flight
- **Stagger large batches**: When ingesting large documents, use smaller batches to reduce the window for crashes

## Known Patterns (2026-05-15)

On the hermes bank, 8 operations were stuck since May 1-2:
- 4x `refresh_mental_model` (processing, hermes) -- mental model refresh interrupted by API restart
- 1x `consolidation` (processing, hermes) -- consolidation worker crashed
- 1x `consolidation` (pending, hermes) -- queued behind the stuck one
- 1x `batch_retain` (pending, claude_code) -- never picked up
- 1x `retain` (processing, claude_code) -- worker crashed

All had `retry_count = 0` and were ~324-330 hours stale.
