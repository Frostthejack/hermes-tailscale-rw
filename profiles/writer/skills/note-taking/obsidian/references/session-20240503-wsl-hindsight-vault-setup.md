# Session Reference: WSL + Hindsight + Obsidian Vault Setup

**Date:** May 3, 2026  
**User:** Josh (frostthejack, lunedecente, luned)  
**Environment:** WSL (Windows Subsystem for Linux)  

## Actual Vault Configuration

### Primary Vault Path - PRODUCTION
```bash
/mnt/c/Users/luned/Vault/Hermes
```

**Critical:** This path must be used for all Obsidian skill operations. Set in `~/.hermes/.env`:
```bash
export OBSIDIAN_VAULT_PATH="/mnt/c/Users/luned/Vault/Hermes"
```

### Hindsight Memory Service Configuration

**Service Location:** Windows host at `192.168.0.40:8888`  
**API Base:** `http://192.168.0.40:8888/`

#### From WSL, use Windows host IP (NOT localhost)

**Common Mistake:** `localhost:8888` or `127.0.0.1:8888` in WSL points to Linux loopback, not Windows host.

**Correct approach:**
```bash
# Add to ~/.hermes/.env
export HINDSIGHT_HOST="192.168.0.40"
export HINDSIGHT_PORT="8888"
export HINDSIGHT_URL="http://${HINDSIGHT_HOST}:${HINDSIGHT_PORT}"
```

#### Find Your Windows Host IP

```bash
# Method 1: From WSL
ip route | grep default
# Output: default via 172.25.144.1 dev eth0
# Your Windows IP is typically: 192.168.0.x or 172.x.x.x

# Method 2: From Windows CMD
ipconfig | findstr IPv4
```

#### Test Hindsight Connectivity from WSL

```bash
curl -sk "${HINDSIGHT_URL}/health"
curl -sk "${HINDSIGHT_URL}/openapi.json"
```

#### Working with Hindsight Memory Banks

**Available Banks:**
- `hermes` - Primary Hermes agent memory
- `claude_code` - Claude Code operations
- `mimir-well` - Mimir assistant memory

**Recall memories:**
```bash
curl -sk "${HINDSIGHT_URL}/v1/default/banks/hermes/memories/recall" \
  -H "Content-Type: application/json" \
  -d '{"query": "search terms", "k": 10}'
```

**Store memory:**
```bash
curl -sk -X POST "${HINDSIGHT_URL}/v1/default/banks/hermes/memories" \
  -H "Content-Type: application/json" \
  -d '{"items": [{"content": "Memory content", "type": "world", "context": "Context description"}]}'
```

## User Identity (Stored in Hindsight)

**Canonical name:** Josh  
**Preferred alias:** frostthejack  
**Also responds to:** lunedecente, luned (short for lunedecente)

## Troubleshooting Checklist

### Symptom: "Connection refused" to :8888 in WSL

**Root cause:** Trying `localhost:8888` or `127.0.0.1:8888` from WSL

**Fix:** Use Windows host IP (`192.168.0.40`)
```bash
# Wrong
curl http://localhost:8888/health

# Right  
curl http://192.168.0.40:8888/health
```

### Symptom: "Connection timed out" to Windows IP

**Possible causes:**
1. Windows firewall blocking port 8888
2. Service not running on Windows
3. Wrong IP address

**Diagnosis:**
```bash
# Verify Windows host IP
ping -c 2 192.168.0.40

# Check port (may need nmap or similar)
# From Windows: ensure service is running
```

**Fix (Windows Firewall):**
1. Open Windows Defender Firewall
2. Allow app through firewall
3. Add inbound rule for port 8888 (TCP)

### Symptom: Path contains spaces, commands fail

**Root cause:** Unquoted path variables

**Fix:** Always quote paths in scripts
```bash
# In your scripts and .env files
VAULT="${OBSIDIAN_VAULT_PATH}"
cat "$VAULT/Note Name.md"
```

## Session-Specific Learnings

### Sherlock OSINT Tool Usage

**Installation:**
```bash
pip install sherlock-project --break-system-packages
```

**Run with NSFW results:**
```bash
sherlock frostthejack --nsfw --print-found --timeout 30 --no-color
```

**Results for frostthejack:** 42 profiles found across:
- GitHub, GitLab, Docker Hub, Hugging Face
- Bluesky, TikTok, YouTube, Telegram
- Steam, Xbox Gamertag, osu!
- NSFW: Pornhub, RedTube, ChaturBate, xHamster, YouPorn

### Memory Persistence Strategy

**Two layers:**
1. **Session memory** (`memory` tool): Active session only
2. **Hindsight** (`hermes` bank): Persistent across sessions, queryable

**Best practice:** Store user preferences in both, but critical long-term info in Hindsight.

## Quick Reference Commands

```bash
# Set up environment
export OBSIDIAN_VAULT_PATH="/mnt/c/Users/luned/Vault/Hermes"
export HINDSIGHT_HOST="192.168.0.40"
export HINDSIGHT_URL="http://${HINDSIGHT_HOST}:8888"

# Verify paths
ls -la "$OBSIDIAN_VAULT_PATH"
curl -sk "${HINDSIGHT_URL}/health"

# Search vault
find "$OBSIDIAN_VAULT_PATH" -name "*.md" -type f

# Search Hindsight memories
curl -sk "${HINDSIGHT_URL}/v1/default/banks/hermes/memories/recall" \
  -H "Content-Type: application/json" \
  -d '{"query": "search", "k": 10}'

# Sherlock username search
sherlock frostthejack --nsfw --print-found --timeout 30
```

## Files and Directories Created

```
/mnt/c/Users/luned/Vault/Hermes/
  ├── (contents to be populated)

/tmp/
  ├── sherlock_results.txt      # Sherlock results for frostthejack
  └── sherlock_verified.txt     # Verified results

~/.hermes/
  ├── .env                      # Environment variables
  └── skills/
      └── note-taking/obsidian/
          └── SKILL.md          # Updated with WSL+Hindsight guidance
```

## Key Takeaways

1. **WSL localhost ≠ Windows host**: Services on Windows use Windows IP
2. **Always quote paths**: Prevent space-related failures  
3. **Layered memory**: Session + Hindsight for persistence
4. **Diagnostic-first workflow**: Verify each step before proceeding
5. **Document actual configs**: Not defaults, but what actually works