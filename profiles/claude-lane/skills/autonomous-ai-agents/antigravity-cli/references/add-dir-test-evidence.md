# Antigravity CLI — Test Evidence (2026-05-22)

## `--add-dir` Requirement — Live Test Results

### Test Setup
- Created test git repo at `/tmp/test-agent-lane` with `src/main.py` containing a `hello()` function
- Created isolated git worktree at `/tmp/test-agy-worktree`
- Used Hermes `terminal()` tool to spawn `agy -p` with `workdir=WORKTREE`

### Test 1: Without `--add-dir` (FAILED)
```
Command: agy -p "Add multiply function to src/main.py" --dangerously-skip-permissions
Workdir: /tmp/test-agy-worktree
```
**Result:** `agy` created its own scratch project at `~/.gemini/antigravity-cli/scratch/math_project/`
and modified files there. The worktree was NOT touched.
```bash
$ cat /tmp/test-agy-worktree/src/main.py
def hello():
    return 'world'    # UNCHANGED
```

### Test 2: With `--add-dir` (PASSED)
```
Command: agy -p "Add multiply function to src/main.py" --add-dir /tmp/test-agy-worktree --dangerously-skip-permissions
Workdir: /tmp/test-agy-worktree
```
**Result:** `agy` correctly modified the file in the worktree.
```bash
$ cat /tmp/test-agy-worktree/src/main.py
def hello():
    return 'world'

def multiply(a, b):
    return a * b
```
```bash
$ git diff --stat
 src/main.py | 7 ++++++-
 1 file changed, 6 insertions(+), 1 deletion(-)
```

### Test 3: Reproducibility (PASSED)
Repeated with fresh worktree `/tmp/test-agy-worktree2`, task: add `divide()` function.
Same `--add-dir` pattern worked correctly. `git diff --stat` confirmed only `src/main.py` changed.

### Comparison: `claude -p` vs `agy -p`
| Behavior | `claude -p` | `agy -p` |
|----------|-------------|----------|
| Respects `workdir` | ✅ Yes | ❌ No |
| Needs `--add-dir` | ❌ No | ✅ **REQUIRED** |
| Creates scratch project | ❌ No | ⚠️ Yes, without `--add-dir` |
| Structured JSON output | ✅ `--output-format json` | ✅ `--output-format json` |
| Cost tracking | ✅ `total_cost_usd` in JSON | ❌ No cost data |

### Cleanup
After testing: `git worktree remove` + `rm -rf /tmp/test-agent-lane`
Scratch project cleanup: `rm -rf ~/.gemini/antigravity-cli/scratch/math_project`
