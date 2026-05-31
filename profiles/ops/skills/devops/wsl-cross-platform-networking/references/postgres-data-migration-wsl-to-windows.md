# PostgreSQL Data Directory Migration: WSL → Windows

## Use Case

Move a PostgreSQL data directory from WSL (e.g., an embedded/pg0 instance) to a native Windows PostgreSQL install — without using `pg_dump`/`pg_restore`.

## When to Use

- Same major version on both sides (e.g., PG 18.x → PG 18.y)
- You want to migrate an entire instance including all databases, roles, and configs
- `pg_dump` is not available or practical

## When NOT to Use

- Different major versions — use `pg_dump`/`pg_restore` instead
- The WSL PG instance can be dumped normally — prefer `pg_dump -Fc` for reliability

## Step-by-Step

### 1. Locate the WSL Data Directory

```bash
cat ~/.pg0/instances/<name>/instance.json  # Shows port, data_dir, username, database
```

### 2. Copy to Windows

```bash
sudo cp -a ~/.pg0/instances/<name>/data /mnt/c/Users/<user>/Desktop/pg-data-export
```

### 3. Stop Windows PG and Back Up

```powershell
Stop-Service postgresql-x64-18
Rename-Item "C:\Program Files\PostgreSQL\18\data" "C:\Program Files\PostgreSQL\18\data-backup-$(Get-Date -Format 'yyyyMMdd')"
Copy-Item "C:\Users\<user>\Desktop\pg-data-export" "C:\Program Files\PostgreSQL\18\data" -Recurse
```

### 4. Fix Permissions

```powershell
$path = "C:\Program Files\PostgreSQL\18\data"
$acl = Get-Acl $path
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule("NETWORK_SERVICE", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$acl.SetAccessRule($rule)
Set-Acl $path $acl
```

### 5. Fix Linux-Specific postgresql.conf Settings

**CRITICAL**: The migrated config may contain Linux-specific values that crash Windows PG.

- `dynamic_shared_memory_type = posix` → `dynamic_shared_memory_type = windows`
- Comment out any `unix_socket_directories`, Linux SSL paths

```powershell
(Get-Content "C:\Program Files\PostgreSQL\18\data\postgresql.conf") -replace 'dynamic_shared_memory_type = posix', 'dynamic_shared_memory_type = windows' | Set-Content "C:\Program Files\PostgreSQL\18\data\postgresql.conf"
```

### 6. Remove Stale postmaster.pid and postmaster.opts

```powershell
Remove-Item "C:\Program Files\PostgreSQL\18\data\postmaster.pid" -ErrorAction SilentlyContinue
Remove-Item "C:\Program Files\PostgreSQL\18\data\postmaster.opts" -ErrorAction SilentlyContinue
```

### 7. Handle Port Conflicts

If WSL PG is still running on 5432 (or mirrored networking exposes it), change Windows PG port:

```powershell
(Get-Content "C:\Program Files\PostgreSQL\18\data\postgresql.conf") -replace '^#?port = 5432', 'port = 5433' | Set-Content "C:\Program Files\PostgreSQL\18\data\postgresql.conf"
```

### 8. Start Windows PG

```powershell
& "C:\Program Files\PostgreSQL\18\bin\pg_ctl" start -D "C:\Program Files\PostgreSQL\18\data" -l "C:\Program Files\PostgreSQL\18\data\start.log"
```

### 9. Verify and Fix User Passwords

```powershell
$env:PGPASSWORD = "<admin_password>"
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U <admin_user> -d <dbname> -h 127.0.0.1 -p <port> -c "\du"
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U <admin_user> -d <dbname> -h 127.0.0.1 -p <port> -c "ALTER USER <app_user> WITH PASSWORD '<new_password>';"
```

### 10. Install Required Extensions (e.g., pgvector)

Hindsight and other apps may need `pgvector` for vector columns. Download from pgvector GitHub releases, copy into PG's lib/share dirs, then:

```powershell
& "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d <dbname> -h 127.0.0.1 -p <port> -c "CREATE EXTENSION IF NOT EXISTS vector;"
```

## Installing pgvector on Windows PG

### The Problem

The EDB EnterpriseDB installer for Windows PostgreSQL does NOT include pgvector. The extension is registered in the migrated database (visible in `pg_extension`) and the SQL files can be copied from the Linux PG install, but the **shared library (`.dll`) must be built for Windows**.

### What Works

1. **Copy SQL extension files** from Linux PG install to Windows:
   ```bash
   # From WSL (requires sudo for Program Files write):
   sudo cp ~/.pg0/installation/18.1.0/share/extension/vector.control "/mnt/c/Program Files/PostgreSQL/18/share/extension/"
   sudo cp ~/.pg0/installation/18.1.0/share/extension/vector--*.sql "/mnt/c/Program Files/PostgreSQL/18/share/extension/"
   ```

2. **Obtain `vector.dll`** — one of:
   - **Pre-built binary**: Download from pgvector GitHub releases. Look for Windows `.zip` assets.
   - **Build from source on Windows**: Requires MSVC (Visual Studio Build Tools). Use `Makefile.win` from pgvector source. Set `PGROOT` to `C:\Program Files\PostgreSQL\18`.

3. **Copy `vector.dll`** to `C:\Program Files\PostgreSQL\18\lib\`

4. **Create the extension**:
   ```powershell
   & "C:\Program Files\PostgreSQL\18\bin\psql.exe" -U postgres -d <dbname> -h 127.0.0.1 -p <port> -c "CREATE EXTENSION IF NOT EXISTS vector;"
   ```

### What Does NOT Work

- **MinGW cross-compilation from WSL**: Linux PG headers reference `sys/socket.h` (via `storage/fd.h` → `port/pg_iovec.h`). MinGW doesn't have it. 15 of 19 source files compile; the 4 that need `sys/socket.h` fail.
- **Copying Linux `.so` file**: Windows needs `.dll`, not `.so`.
- **EDB StackBuilder**: Does not list pgvector.
- **winget/chocolatey**: No pgvector package.

## Common Failure Modes

| Symptom | Cause | Fix |
|---------|-------|-----|
| "Server closed the connection unexpectedly" | Stale `postmaster.pid` or `dynamic_shared_memory_type = posix` | Delete PID file, change to `windows` |
| Service won't start, no log entries | Permissions or Linux config values | Check Event Viewer, fix config |
| Port already in use | WSL PG holding 5432 | Change Windows PG to 5433 |
| Password auth failed | Password mismatch after migration | Reset via superuser |
| Two PG instances on different ports | Manual `pg_ctl start` + service both running | Kill all, start only one |
| `\\wsl$` UNC path not accessible | WSL network share unreliable from Windows | Use `/mnt/c/` from WSL, `C:\` from Windows |
| "could not access file 'vector'" | pgvector not installed | Install pgvector extension (see section above) |
| logical replication launcher crash (0xFFFFFFFF) | Linux-originated WAL settings | Usually non-fatal |

## Version Compatibility

- Forward-compatible within same major (18.1 → 18.4 = OK)
- NOT backward-compatible (18.4 → 18.1 = FAIL)
- NOT cross-major (16 → 18 = use pg_dump)

## PowerShell Tips

- Use `&` for exe paths with spaces: `& "C:\Program Files\...\pg_ctl" --version`
- Use `[Environment]::SetEnvironmentVariable('PGPASSWORD','value')` before psql
- For complex scripts, write `.ps1` file and use `-File` not `-Command`
- Copy scripts from WSL via `/mnt/c/Users/<user>/AppData/Local/Temp/`

## Session History

- **2026-05-15**: Hindsight migration WSL→Windows. Issues: stale PID file, posix shared memory type, port 5432 conflict, password mismatch, missing pgvector. All resolved except pgvector install (in progress). Banks verified: hermes (3896 entities, 182 docs, 877 chunks), mimir-well, claude_code.
