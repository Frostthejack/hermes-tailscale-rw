# Discord Slash Command Bug Patterns

## Common Pitfalls in discord.py Slash Commands

### 1. CLI Flag Argument Splitting

**Bug:** Passing list items as separate CLI arguments when the flag expects a single comma-separated string.

```python
# WRONG — produces: --platforms twitter github
platform_list = [p.strip() for p in platforms.split(",")]
cmd.extend(["--platforms"] + platform_list)

# CORRECT — produces: --platforms twitter,github
cmd.extend(["--platforms", ",".join(platform_list)])
```

**Affected tools:** `socialscan --platforms`, any CLI that takes comma-separated values.

### 2. Mutually Exclusive Flags

**Bug:** Adding both a default flag and a custom override, causing the tool to ignore one.

```python
# WRONG — both --top-ports and -p are added
cmd = ["nmap", "--top-ports", "100"]
if port_range.strip():
    cmd.extend(["-p", port_range.strip()])

# CORRECT — use one or the other
cmd = ["nmap"]
if port_range.strip():
    cmd.extend(["-p", port_range.strip()])
else:
    cmd.extend(["--top-ports", "100"])
```

**Affected tools:** `nmap`, any CLI with mutually exclusive options.

### 3. Go Binary Path Resolution

**Pattern:** Go binaries installed via `go install` go to `~/go/bin/`. Use the full path in subprocess commands.

```python
# CORRECT
cmd = ["/home/frostthejack/go/bin/dnsx", "-d", domain]
```

### 4. Defer + Edit Response Pattern

**Required pattern for all slash commands that take >3 seconds:**

```python
await interaction.response.defer(ephemeral=False)
# ... do work ...
await interaction.edit_original_response(content=output)
```

Never use `interaction.response.send_message()` for long-running commands — the 3-second interaction window will expire.

### 5. Output Truncation

Discord message limit is 2000 chars. Always truncate at 1900 to leave room for markdown headers:

```python
if len(output) > 1900:
    output = output[:1900] + "\n…(truncated)"
```

### 6. Error Handling Pattern

Always handle these three error types minimum:

```python
try:
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=N)
    output = (proc.stdout + proc.stderr).strip()
except subprocess.TimeoutExpired:
    output = f"⏱️ tool timed out after {N}s."
except FileNotFoundError:
    output = "❌ tool is not installed. Run: `install command`"
except Exception as e:
    output = f"❌ Error: {e}"
```

### 7. Symlink Source Files

When the project uses symlinks (e.g., `src/` → hermes-agent gateway), the actual file being edited is on the target side of the symlink. Changes made through the symlink path are real changes to the target file. Be careful not to commit symlink entries as real files in git — add them to `.gitignore`.

### 8. Worker Crash After Implementation (Phantom Blocked/Todo Tasks)

**Pattern:** Workers may implement code and commit it, but crash before calling `kanban_complete`. The task stays in `blocked` or `todo` state even though the work is done.

**Detection:** Check `git log` in the project directory. If the expected commits exist, the task is a phantom.

**Fix:** Mark the task as `done` directly via SQLite rather than re-dispatching.

```bash
# Check if the implementation was already committed
cd /mnt/c/Users/luned/Documents/Projects/<project-name>/
git log --oneline -10
grep -n "async def slash_<command>" src/discord.py
```

### 9. Board Slug ≠ Project Name

**Pattern:** The kanban board slug (e.g., `discord`) may differ from the actual project name (e.g., `discord-osint`). Always use the project name for the directory path, not the board slug.

**Example:**
- Board slug: `discord`
- Project name: `discord-osint`
- Canonical path: `/mnt/c/Users/luned/Documents/Projects/discord-osint/`
- Workspace for tasks: `dir @ /mnt/c/Users/luned/Documents/Projects/discord-osint/`

**Anti-pattern:** Don't point workspaces to the hermes-agent source tree just because the code being modified lives there. The project gets its own directory with symlinks.

### 10. Project Directory Must Exist Before Task Execution

**Pattern:** When creating a new project, the canonical directory (`PROJECTS_ROOT/<project-name>/`) must exist with proper symlinks BEFORE tasks are dispatched. Workers will crash if the workspace directory doesn't exist.

**Setup order:**
1. Create `PROJECTS_ROOT/<project-name>/`
2. Initialize git repo
3. Create symlinks: `src/` → code location, `docs/` → vault, `project-state.md` → vault
4. Create `.gitignore` for symlink entries
5. Create `project-state.md` in vault
6. THEN create kanban tasks with `workspace_kind=dir` pointing to this path
