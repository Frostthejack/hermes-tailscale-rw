# WSL + Hindsight + Obsidian Vault Patterns

## Session Learning: May 3, 2026

**Environment:** WSL (Ubuntu) accessing Windows host services  
**User:** Josh (frostthejack, lunedecente, luned)  
**Primary Vault:** `/mnt/c/Users/luned/Vault/Hermes`  
**Hindsight Host:** `192.168.0.40:8888` (Windows host IP, not localhost)

## Key Pattern: WSL Network Isolation

**Problem:** `localhost:8888` or `127.0.0.1:8888` in WSL points to the Linux loopback, not the Windows host where services like Hindsight run.

**Solution:** Use the Windows host IP address:
```bash
# Find your Windows IP from WSL:
ip route | grep default
# Typical output: default via 172.25.144.1 dev eth0
# OR: default via 192.168.0.x dev eth0

# Or from Windows CMD:
ipconfig | findstr IPv4
# Look for your active adapter's IPv4 address

# Set in your .env:
export HINDSIGHT_HOST="192.168.0.40"  # Your actual Windows IP
export HINDSIGHT_PORT="8888"
export HINDSIGHT_URL="http://${HINDSIGHT_HOST}:${HINDSIGHT_PORT}"

# Test:
curl -sk "${HINDSIGHT_URL}/health"
```

**Error Signatures:**
- `curl: (7) Failed to connect to 127.0.0.1 port 8888: Connection refused` → Wrong host
- `curl: (28) Connection timed out after X ms` → Firewall or wrong IP

## Pattern: Windows Service Accessibility

**For any Windows-hosted service accessed from WSL:**

1. **Service must bind to `0.0.0.0` not `127.0.0.1`**
   - Windows services often default to `127.0.0.1` (localhost only)
   - Configure to bind to `0.0.0.0` (all interfaces) or specific Windows IP

2. **Windows Firewall must allow the port**
   ```powershell
   # In Windows PowerShell (Admin):
   New-NetFirewallRule -DisplayName "Hindsight Port 8888" -Direction Inbound -Protocol TCP -LocalPort 8888 -Action Allow
   ```

3. **WSL uses Windows network stack differently**
   - WSL2 has its own virtual network
   - Windows host is the default gateway
   - Services on Windows host = accessible via Windows IP

## Pattern: Path Translation

**Windows → WSL:**
```
C:\Users\luned\Vault\Hermes
↓
/mnt/c/Users/luned/Vault/Hermes
```

**WSL → Windows (for Windows tools):**
```
/mnt/c/Users/luned/Vault/Hermes
↓
C:\Users\luned\Vault\Hermes
```

**Best Practice for WSL-Primary Workflow:**
```bash
# Store vault in Windows-accessible location but work from WSL
export OBSIDIAN_VAULT_PATH="/mnt/c/Users/luned/Vault/Hermes"

# Quoting is CRITICAL (paths often contain spaces)
cat "$OBSIDIAN_VAULT_PATH/Note Name.md"
```

## Pattern: Memory Persistence Across Sessions

**Two-tier approach for robust memory:**

1. **Session Memory (fast, volatile)**
   ```bash
   memory add target=user content="Prefers exhaustive troubleshooting" action=add
   ```
   - Cleared when terminal session ends
   - Use for: Current project state, temporary preferences

2. **Hindsight Memory (persistent, queryable)**
   ```bash
   curl -sk -X POST "${HINDSIGHT_URL}/v1/default/banks/hermes/memories" \
     -H "Content-Type: application/json" \
     -d '{"items": [{"content": "...", "type": "world", "context": "..."}]}'
   ```
   - Survives reboots and new sessions
   - Semantic search across all memories
   - Use for: User identity, project history, learned patterns

**Retrieval:**
```bash
# Search all memories
curl -sk "${HINDSIGHT_URL}/v1/default/banks/hermes/memories/recall" \
  -H "Content-Type: application/json" \
  -d '{"query": "search terms", "k": 10}'

# By bank (hermes, claude_code, etc.)
curl -sk "${HINDSIGHT_URL}/v1/default/banks/hermes/stats"
```

## Pattern: User Identity Aliases

**Store multiple identifiers for flexible recall:**
```bash
curl -sk -X POST "${HINDSIGHT_URL}/v1/default/banks/hermes/memories" \
  -H "Content-Type: application/json" \
  -d '{"items": [{
    "content": "User: Josh (canonical), frostthejack (preferred alias), lunedecente, luned",
    "type": "world",
    "context": "User identity and name resolution"
  }]}'
```

**Query works with any alias:**
```bash
# These all find the same memories:
curl ... -d '{"query": "Josh", ...}'
curl ... -d '{"query": "frostthejack", ...}'
curl ... -d '{"query": "luned", ...}'
```

## Pattern: Diagnostic Workflow

**When WSL ↔ Windows communication fails:**

```bash
# 1. Verify Windows host is reachable
ping -c 2 192.168.0.40

# 2. Verify port is open
curl -sk -o /dev/null -w "%{http_code}" http://192.168.0.40:8888/health
# 200 = OK, 000 = connection failed

# 3. Check Windows firewall (from Windows)
#    Windows Defender Firewall → Advanced Settings → Inbound Rules

# 4. Check service binding (from Windows)
#    netstat -ano | findstr :8888

# 5. Test from WSL with verbose output
curl -svk http://192.168.0.40:8888/health 2>&1 | head -20
```

**When file paths fail:**

```bash
# Check path exists
ls -la "$OBSIDIAN_VAULT_PATH" || echo "PATH DOES NOT EXIST"

# Check permissions
ls -ld "$OBSIDIAN_VAULT_PATH"

# Check for spaces (common issue)
echo "$OBSIDIAN_VAULT_PATH" | grep ' ' && echo "WARNING: Path contains spaces - always quote!"

# Mount check (WSL)
mount | grep '/mnt/c'
df -h /mnt/c
```

## Pattern: Service Configuration on Windows

**For developer services (Hindsight, etc.):**

1. **Configuration file location:**
   ```
   %APPDATA%\Hindsight\config.yaml
   # or
   C:\Users\<user>\AppData\Roaming\Hindsight\config.yaml
   ```

2. **Ensure binds to 0.0.0.0:**
   ```yaml
   # In config
   host: "0.0.0.0"  # Not "127.0.0.1"
   port: 8888
   ```

3. **Run as service (optional):**
   ```powershell
   # Use NSSM or Windows Service Wrapper
   # Or enable systemd in WSL for Linux services
   ```

## Pattern: Environment Variable Management

**In `~/.hermes/.env`:**
```bash
# User identity (used by various tools)
USER_NAME="Josh"
USER_ALIAS="frostthejack"
USER_ALIASES="frostthejack,lunedecente,luned"

# Vault configuration
OBSIDIAN_VAULT_PATH="/mnt/c/Users/luned/Vault/Hermes"

# WSL network (critical!)
export WSL_HOST_IP="192.168.0.40"  # Your Windows IP

# Hindsight memory service (runs on Windows)
export HINDSIGHT_HOST="${WSL_HOST_IP}"
export HINDSIGHT_PORT="8888"
export HINDSIGHT_URL="http://${HINDSIGHT_HOST}:${HINDSIGHT_PORT}"

# Alternative: Use Windows DNS name
# export HINDSIGHT_URL="http://host.docker.internal:8888"
```

**Load in shell:**
```bash
# In ~/.bashrc or ~/.zshrc
[ -f ~/.hermes/.env ] && source ~/.hermes/.env
```

## Pattern: Troubleshooting Checklist

**Service unreachable from WSL:**
- [ ] Windows service is running
- [ ] Service bound to `0.0.0.0` not `127.0.0.1`
- [ ] Windows Firewall allows the port (inbound rule)
- [ ] Using Windows IP, not `localhost`, in WSL
- [ ] WSL can ping Windows host (`ping -c 2 <Windows_IP>`)
- [ ] No VPN blocking local network traffic

**File path issues:**
- [ ] Path contains spaces → **always quote** `"$PATH"`
- [ ] WSL can access `/mnt/c/...` (not all Windows folders are mounted)
- [ ] Permissions allow read/write
- [ ] Path exists (WSL won't auto-create parents)

**Memory not persisting:**
- [ ] Hindsight service running
- [ ] Using correct bank ID (`hermes` vs `claude_code`)
- [ ] POST requests include proper JSON format
- [ ] Check response for errors

## Pattern: Common Commands (Quick Reference)

```bash
# --- WSL + Windows ---
# Find Windows IP
ip route | grep default | awk '{print $3}'

# Test Windows service
curl -sk http://$(ip route | grep default | awk '{print $3}'):8888/health

# Mount Windows path
ls /mnt/c/Users/$(whoami)/Documents/

# --- Hindsight ---
# Health check
curl -sk "${HINDSIGHT_URL}/health"

# List banks
curl -sk "${HINDSIGHT_URL}/v1/default/banks"

# Search memories
curl -sk "${HINDSIGHT_URL}/v1/default/banks/hermes/memories/recall" \
  -H "Content-Type: application/json" \
  -d '{"query": "topic", "k": 10}'

# Store memory
curl -sk -X POST "${HINDSIGHT_URL}/v1/default/banks/hermes/memories" \
  -H "Content-Type: application/json" \
  -d '{"items": [{"content": "info", "type": "world", "context": "..."}]}'

# Stats
curl -sk "${HINDSIGHT_URL}/v1/default/banks/hermes/stats"

# --- Obsidian ---
# Count notes
find "$OBSIDIAN_VAULT_PATH" -name "*.md" -type f | wc -l

# Search content
grep -rni "keyword" "$OBSIDIAN_VAULT_PATH" --include="*.md"

# Recent notes
find "$OBSIDIAN_VAULT_PATH" -name "*.md" -type f -mtime -7 | head -10

# --- Diagnostics ---
# Run full check
source scripts/diagnose-wsl-hindsight.sh
```

## Pattern: Security Considerations

**WSL ↔ Windows traffic:**
- All WSL-to-Windows traffic goes through virtual network
- By default, NOT exposed to external network
- Windows Firewall protects from outside access
- Services bound to `0.0.0.0` on Windows are accessible from WSL

**For sensitive services:**
- Use firewall rules to restrict by IP/port
- Consider VPN or SSH tunnel for remote access
- Use HTTPS where possible (localhost certs)
- Don't expose admin interfaces broadly

## Pattern: Performance Optimization

**WSL file I/O:**
- Windows-mounted drives (`/mnt/c/...`) are slower than native Linux FS
- For best performance: work in WSL-native directories (`~/`)
- Or use WSL2 with 9P filesystem optimizations

**Memory operations:**
- Cache Hindsight results locally for frequent queries
- Batch database operations
- Use connection pooling for HTTP services

## Session-Specific Observations

**May 3, 2026 Session:**
- Hindsight at `192.168.0.40:8888` confirmed working
- `/mnt/c/Users/luned/Vault/Hermes` set as primary vault
- Sherlock OSINT: 42 profiles found for `frostthejack`
- NSFW results included as requested
- All aliases (Josh/frostthejack/lunedecente/luned) documented in Hindsight

**Common Gotchas:**
1. Typing `localhost:8888` in WSL → points to Linux, not Windows
2. Unquoted paths with spaces → silent failures
3. Windows services default to `127.0.0.1` → inaccessible from WSL
4. Firewall blocking after Windows updates → rule gets removed
5. WSL shutdown → all running Linux processes terminated

## Tools and Scripts

**Diagnostic script:** `scripts/diagnose-wsl-hindsight.sh`
- Run: `source scripts/diagnose-wsl-hindsight.sh`
- Checks: WSL env, Windows IP, Hindsight connectivity, vault access

**Reference guide:** `references/session-20240503-wsl-hindsight-vault-setup.md`
- Session-specific setup details
- Actual configuration values
- Troubleshooting steps taken

## Further Reading

- WSL Network: https://docs.microsoft.com/en-us/windows/wsl/networking
- WSL Mount: https://docs.microsoft.com/en-us/windows/wsl/filesystems
- Windows Firewall: https://docs.microsoft.com/en-us/windows/security/threat-protection/windows-firewall
- Hindsight Docs: (see service README)
- Obsidian: https://help.obsidian.md/

---

*Generated from session work on May 3, 2026*  
*User: Josh (frostthejack)*  
*Location: WSL → Windows host services*