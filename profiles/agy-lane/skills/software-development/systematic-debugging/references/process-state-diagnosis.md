# Process State Diagnosis — Determining Frozen vs. Completed Installations

**Reference for Phase 1: Root Cause Investigation**

## Quick Diagnostic Workflow

When attempting to determine whether an installation/process is frozen, completed, or failed in another terminal/session:

### 1. Check Active Process Tree

```bash
# Look for installation-related processes
ps aux | grep -iE '(pip|npm|yarn|cargo|go|dotnet|make|cmake|configure|setup|build)' | grep -v grep

# Check for specific package manager
ps aux | grep -iE '(apt|dpkg|pacman|zypper)' | grep -v grep

# Show full process tree to see parent-child relationships
ps aux --forest
```

**What to look for:**
- The process itself (pip, npm, cargo, etc.)
- Parent processes (shell, terminal emulator)
- Child processes (compilers, downloaders, build tools)

### 2. Check for Download/Network Activity

```bash
# Processes using network
ps aux | grep -iE '(curl|wget|git|rsync)' | grep -v grep

# Active TCP connections
ss -tlnp 2>/dev/null | grep -iE '(npm|pip|registry|package)'

# DNS lookups or network activity indicators
lsof -i 2>/dev/null | grep -iE '(npm|pip|http|registry)'
```

**What to look for:**
- Download tools (`curl`, `wget`) fetching packages
- Git operations cloning repositories
- Connections to package registries (npmjs.org, pypi.org, github.com)

### 3. Check for Build/Compilation Activity

```bash
# Compilation processes
ps aux | grep -iE '(gcc|g\+\+|clang|rustc|cargo|go|javac)' | grep -v grep

# Build system tools
ps aux | grep -iE '(make|cmake|ninja|bazel|meson)' | grep -v grep

# Package-specific build tools
ps aux | grep -iE '(node-gyp|node-pre-gyp|prebuild)' | grep -v grep
```

**What to look for:**
- Compilers running
- Build system orchestrators
- High CPU usage by build tools (check with `top` or `htop`)

### 4. Check Package Manager Locks

```bash
# NPM lock
ls -la /path/to/project/node_modules/.package-lock.json 2>/dev/null
lsof /path/to/project/package-lock.json 2>/dev/null

# Python lock
ls -la /path/to/project/pip.lock 2>/dev/null
lsof /path/to/project/pip*.log 2>/dev/null

# General lock files
find /path/to/project -name '*.lock' -newer /tmp/checkpoint 2>/dev/null
```

**What to look for:**
- Lock file modification times
- Processes holding file locks
- Recent activity on lock files

### 5. Check Cache/Log Activity

```bash
# Recent log files
find /tmp -name '*.log' -newer /tmp/checkpoint -mmin -5 2>/dev/null

# Package manager cache locks
ls -la /tmp/uv-*.lock 2>/dev/null
ls -la /tmp/npm-* 2>/dev/null
ls -la /tmp/pip-* 2>/dev/null

# Check if cache is being written
lsof /tmp/*cache* 2>/dev/null
```

**What to look for:**
- Recent log file modifications
- Cache locks held by processes
- Temporary files being created/modified

### 6. Check Terminal/PTY State

```bash
# Active terminals and their processes
ps aux --forest | grep -E '(-bash|-zsh|-fish|bash|zsh|fish)'

# TTY allocation
ps aux | grep -iE '(tmux|screen|pty|terminal)' | grep -v grep
```

**What to look for:**
- Shell processes associated with terminals
- Terminal multiplexers (tmux, screen) running sessions
- PTY allocation for interactive sessions

### 7. Check for Background/Daemon Processes

```bash
# Daemon processes related to the package
pgrep -fa '(pip|npm|yarn|cargo|python|node)' | grep -v grep

# Nocturn processes
ps aux | grep -iE '(pip|npm)' | grep -v grep
```

**What to look for:**
- Background workers still running
- Subprocesses spawned by main installer
- Service daemons that were started

### 8. Check Exit Codes and Status

```bash
# Check /proc for process details
for pid in $(pgrep -f 'pip|npm|yarn'); do
    echo "PID: $pid"
    cat /proc/$pid/status 2>/dev/null | grep -E '(State|Exit)'
    cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' '
    echo ""
done
```

**What to look for:**
- Process state (Running, Sleeping, Zombie)
- Exit codes if already terminated
- Command line arguments (which package, which version)

### 9. Check for Zombie/Defunct Processes

```bash
ps aux | grep 'Z\|<defunct>' | grep -v grep
```

**What to look for:**
- Zombie processes (state 'Z')
- Indicates child process died but parent hasn't reaped it
- Often means parent process is stuck

### 10. Check File System Activity

```bash
# Files being modified in project
find /path/to/project -newer /tmp/checkpoint -mmin -2 -type f 2>/dev/null

# Disk I/O by process
iotop -b -n 1 2>/dev/null | grep -iE '(pip|npm|yarn|cargo)'

# Inotify watches
lsof +D /path/to/project 2>/dev/null | grep -iE '(pip|npm|node_modules)'
```

**What to look for:**
- Files being written to node_modules/ or site-packages/
- High disk I/O
- Open file handles to project directories

## Interpreting Results

### Scenario A: Installation Completed Successfully
**Indicators:**
- No installation-related processes found
- Lock files present but not held by any process
- Package directory (node_modules/, site-packages/) populated
- Recent log entries show completion message
- Exit code 0 visible or implied

### Scenario B: Installation Frozen/Stuck
**Indicators:**
- Process found but no network activity (for download installs)
- No recent file system activity in package directories
- No CPU usage by installation process
- Parent process waiting indefinitely
- No recent log entries (stalled)

### Scenario C: Installation Failed with Error
**Indicators:**
- Process terminated (not running)
- Non-zero exit code
- Error log files present
- Incomplete package directory
- Lock file may or may not be present

### Scenario D: Installation Active but Slow
**Indicators:**
- Process found and running
- Network activity present (for download installs)
- Compilation/build processes active
- CPU or I/O usage visible
- Recent file system modifications

## Quick One-Command Checks

```bash
# Check if package installation is active
check_install() {
    local pkg_type=$1
    echo "=== Checking $pkg_type installation status ==="
    echo "Processes:"
    ps aux | grep -iE "$pkg_type" | grep -v grep || echo "None found"
    echo ""
    echo "Recent activity (last 5 min):"
    find /tmp -name "*${pkg_type}*" -newer /tmp/checkpoint -mmin -5 2>/dev/null || echo "None"
    echo ""
    echo "Lock files:"
    find /tmp -name "*${pkg_type}*.lock" -mmin -5 2>/dev/null || echo "None"
}

# Usage
check_install "pip"
check_install "npm"
check_install "cargo"
```

## Decision Tree

```
Are installation processes running?
├── Yes → Check activity level (network, CPU, I/O)
│   ├── Active → Installation is in progress (wait)
│   └── Inactive → Likely frozen (kill and retry)
└── No → Check completion indicators
    ├── Package files present + exit code 0 → Success
    ├── Error logs present → Failed (review logs)
    └── Incomplete files, no logs → Unknown state (retry)
```

## Common False Positives

1. **"pip is running" from system Python**
   - Check the full command line to verify it's the right pip
   - `ps aux | grep pip` may show unrelated system processes

2. **npm/yarn post-install scripts**
   - Can appear stuck while running build scripts
   - Check if `node` processes are actively compiling
   - May legitimately take several minutes

3. **Cargo compilation**
   - Can appear frozen while downloading crates
   - Check network activity
   - Large dependency trees take time

## When to Intervene

- ✅ Safe: Check logs, verify state, look for error messages
- ⚠️ Caution: Kill process only if definitely frozen (> 10 min no activity)
- ❌ Avoid: Force kill if compilation/build processes are active

## Reference Commands

```bash
# Monitor in real-time
watch -n 5 'ps aux | grep -E "(pip|npm|yarn|cargo|python|node)" | grep -v grep'

# Check specific PID
ls -la /proc/PID/fd/ 2>/dev/null    # What files it has open
cat /proc/PID/status 2>/dev/null    # Process state
cat /proc/PID/cmdline 2>/dev/null | tr '\0' ' '  # Full command

# Check parent process
ps -o ppid= -p PID       # Parent PID
ps aux | grep PARENT_PID # What's the parent
```

## Memory Aid

**PCRD** — Process, Cache, Recent, Disk
1. **P**rocess: Is the installation process running?
2. **C**ache: Are cache/lock files being used?
3. **R**ecent: Any recent log or file activity?
4. **D**isk: Is disk I/O happening in package directories?

Answer these four questions to determine state.

