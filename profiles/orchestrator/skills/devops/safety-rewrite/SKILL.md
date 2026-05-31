---
name: safety-rewrite
description: Safety-first command rewriting for agent-generated commands. Before executing any command, apply defensive patterns to reduce risk of blindly running harmful operations. Not a safety bypass — defensive coding habits.
---

# Safety-First Command Rewriting

## When to Apply

Apply these rewrites to **every command an agent generates** before execution. This is a standing behavioral rule, not optional.

## Rule 1: Never Pipe Remote Content to an Interpreter

**Pattern flagged:** `curl ... | python3`, `curl ... | bash`, `wget ... | sh`, etc.

**Rewrite to:**
```bash
# Step 1: Download to temp file
curl -s <url> -o /tmp/_fetch_$(date +%s).<ext>

# Step 2: Review content
cat /tmp/_fetch_*.<ext>

# Step 3: Execute only after review
python3 /tmp/_fetch_*.<ext>
```

**Rationale:** Piping fetched content directly to an interpreter means executing untrusted code without inspection. Even if the source is trusted today, a compromised server or wrong URL becomes a remote code execution vulnerability.

**Exception:** `python3 -m json.tool` and other pure-formatting modules are safe, but still prefer the two-step pattern for consistency.

## Rule 2: Destructive Operations — List Before Acting

**Pattern flagged:** `rm -rf`, `dd`, `mkfs`, `truncate`, mass `mv`/`cp` overwrites.

**Rewrite to:**
```bash
# Step 1: Show what would be affected
ls -la /target/path/
# or
find /target/path -type f | head -20

# Step 2: Execute only after confirming scope
rm -rf /target/path/*
```

**Rationale:** Agents can misjudge paths. Listing first catches mistakes like wrong variable expansion or relative path confusion.

## Rule 3: Remote Code Execution — Always Split

**Pattern flagged:** Any command that downloads and executes code in one step.

**Rewrite to:**
```bash
# Download
curl -s <url> -o /tmp/review.sh

# Inspect
cat /tmp/review.sh

# Execute with explicit approval
bash /tmp/review.sh
```

## Rule 4: Network Requests to Unknown Hosts

Before executing commands that contact external servers:
1. Verify the hostname/IP is expected
2. Prefer HTTPS over HTTP
3. Don't silently follow redirects (`curl -L` can redirect to unexpected hosts)

## Rule 5: Sudo / Privileged Operations

Any command requiring `sudo` or root:
1. Explain why elevated privileges are needed
2. Prefer targeted privilege escalation (`sudo <specific command>`) over `sudo su` or `sudo bash`
3. Never pipe remote content through sudo

## Implementation Notes

- These rules apply to **agent-generated commands**, not user-provided commands (users can run what they want)
- If a user explicitly requests a one-liner pipe pattern, warn them but respect their choice
- For kanban workers: include these rules in the task prompt so subagents follow them too
- Temp files should be cleaned up after use: `rm -f /tmp/_fetch_*`

## Examples

### Before (risky):
```bash
curl -s https://example.com/install.sh | sudo bash
```

### After (safe):
```bash
curl -s https://example.com/install.sh -o /tmp/install.sh
cat /tmp/install.sh
# Review output, then:
sudo bash /tmp/install.sh
rm -f /tmp/install.sh
```

### Before (risky):
```bash
curl -s http://api.example.com/data | python3 -c "import sys,json; d=json.load(sys.stdin); ..."
```

### After (safe):
```bash
curl -s http://api.example.com/data -o /tmp/api_data.json
python3 -m json.tool /tmp/api_data.json | head -50
# Then process with confidence
```
