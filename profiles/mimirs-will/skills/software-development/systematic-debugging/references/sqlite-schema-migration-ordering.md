# SQLite Schema Migration Ordering

## Pattern: CREATE INDEX on a column that doesn't exist yet

### Symptoms

```
sqlite3.OperationalError: no such column: <column_name>
Traceback:
  File "...", line N, in connect
    conn.executescript(SCHEMA_SQL)
```

The traceback points to `executescript(SCHEMA_SQL)`, but the actual failure is **not** in the `CREATE TABLE` statement — it's in a `CREATE INDEX` that references a column that doesn't exist in the existing table.

### Root Cause

When a SQLite schema uses `CREATE TABLE IF NOT EXISTS` (idempotent) followed by additive migrations (`ALTER TABLE ADD COLUMN`), and the table already exists from an older version:

1. `CREATE TABLE IF NOT EXISTS` → **no-op** (table already exists with old columns)
2. `CREATE INDEX IF NOT EXISTS idx ON table(new_column)` → **FAILS** because `new_column` doesn't exist
3. `_migrate_add_optional_columns(conn)` (which would `ALTER TABLE ADD COLUMN`) → **never reached**

The error message blames the index creation, but the real issue is the **ordering dependency**: the index depends on a column that a later migration step would add.

### Diagnosis

1. Check the existing table schema: `sqlite3 db_path "PRAGMA table_info(table_name);"`
2. Check which columns are missing vs. what `SCHEMA_SQL` expects
3. Confirm the error is in `CREATE INDEX`, not `CREATE TABLE`

### Fix

Manually run the missing `ALTER TABLE` statements before the index creation:

```python
import sqlite3
conn = sqlite3.connect(db_path)
cols = {row[1] for row in conn.execute("PRAGMA table_info(tasks)").fetchall()}
for col, col_type in [("session_id", "TEXT"), ("model_override", "TEXT")]:
    if col not in cols:
        conn.execute(f"ALTER TABLE tasks ADD COLUMN {col} {col_type}")
conn.close()
```

### Prevention

When designing schema migrations that use `executescript()`:

- **Option A**: Put `ALTER TABLE ADD COLUMN` statements inside the same `SCHEMA_SQL` string, *before* any `CREATE INDEX` that references the new column.
- **Option B**: Make `CREATE INDEX` conditional on column existence (SQLite doesn't support `IF NOT EXISTS` for indexes on non-existent columns — so this doesn't work; use Option A).
- **Option C**: Run additive migrations *before* `executescript()`, not after.

### Real Example

Hermes kanban_db.py: `SCHEMA_SQL` contained `CREATE TABLE IF NOT EXISTS tasks (... session_id TEXT)` followed by `CREATE INDEX IF NOT EXISTS idx_tasks_session_id ON tasks(session_id)`. On databases created before `session_id` was added, the CREATE TABLE was a no-op (table existed without `session_id`), and the CREATE INDEX failed. The `_migrate_add_optional_columns()` function that adds `session_id` via `ALTER TABLE` runs *after* `executescript(SCHEMA_SQL)`, so it never executed.

Fix: manually ran `ALTER TABLE tasks ADD COLUMN session_id TEXT` (and other missing columns) on all board databases, then restarted the gateway.
