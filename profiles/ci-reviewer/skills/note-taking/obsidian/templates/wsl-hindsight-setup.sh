#!/bin/bash
# WSL + Hindsight Setup Template
# Usage: Copy and modify for new user setups
# This creates the standard configuration for WSL↔Windows service integration

# ========================================
# 1. Environment Variables
# ========================================

# Add to ~/.hermes/.env or ~/.bashrc

# User Identity (for Hindsight memory)
export USER_NAME="{{USER_NAME}}"
export USER_ALIAS="{{USER_ALIAS}}"
export USER_FULL_NAME="{{USER_FULL_NAME}}"

# Obsidian Vault Path
# Default: ~/Documents/Obsidian Vault
# WSL: /mnt/c/Users/<username>/Documents/Obsidian Vault
export OBSIDIAN_VAULT_PATH="{{OBSIDIAN_VAULT_PATH}}"

# WSL Network (CRITICAL: Replace with your Windows IP)
# Find with: ip route | grep default
# Windows ipconfig: Look for "IPv4 Address"
export WSL_HOST_IP="{{WSL_HOST_IP}}"  # e.g., 192.168.0.40

# Hindsight Service (running on Windows)
export HINDSIGHT_HOST="${WSL_HOST_IP}"
export HINDSIGHT_PORT="8888"
export HINDSIGHT_URL="http://${HINDSIGHT_HOST}:${HINDSIGHT_PORT}"

# Optional: Alternative Hindsight access
# export HINDSIGHT_URL="http://host.docker.internal:8888"

# ========================================
# 2. Path Verification
# ========================================

# Create vault if it doesn't exist
mkdir -p "$OBSIDIAN_VAULT_PATH"

# Test access
if [ -d "$OBSIDIAN_VAULT_PATH" ]; then
    echo "✓ Vault path: $OBSIDIAN_VAULT_PATH"
    echo "  Files: $(find "$OBSIDIAN_VAULT_PATH" -name '*.md' -type f 2>/dev/null | wc -l) markdown files"
else
    echo "✗ Cannot access vault: $OBSIDIAN_VAULT_PATH"
    echo "  Check: Is path correct? Does it exist?"
fi

# Test Hindsight connectivity
if curl -sk --max-time 5 "${HINDSIGHT_URL}/health" &>/dev/null; then
    echo "✓ Hindsight: ${HINDSIGHT_URL}"
else
    echo "✗ Hindsight unreachable: ${HINDSIGHT_URL}"
    echo "  Troubleshooting:"
    echo "    1. Is service running on Windows?"
    echo "    2. Is firewall allowing port ${HINDSIGHT_PORT}?"
    echo "    3. Is WSL_HOST_IP correct? (current: ${WSL_HOST_IP})"
    echo "    4. Try: curl -sk http://${WSL_HOST_IP}:${HINDSIGHT_PORT}/health"
fi

# ========================================
# 3. Hindsight Bank Initialization
# ========================================

# Create/verify hermes bank
curl -sk -X POST "${HINDSIGHT_URL}/v1/default/banks" \
  -H "Content-Type: application/json" \
  -d '{"bank_id": "hermes", "name": "hermes"}' 2>/dev/null || true

# Store user identity
curl -sk -X POST "${HINDSIGHT_URL}/v1/default/banks/hermes/memories" \
  -H "Content-Type: application/json" \
  -d "{
    \"items\": [{
      \"content\": \"User: ${USER_NAME} (${USER_ALIAS})\",
      \"type\": \"world\",
      \"context\": \"User identity for ${USER_NAME}\"
    }]
  }" 2>/dev/null || true

echo "✓ User identity stored in Hindsight"

# ========================================
# 4. Obsidian Setup
# ========================================

# Create standard directory structure
mkdir -p "$OBSIDIAN_VAULT_PATH"/{Daily\ Notes,Templates,Projects,Research,Archive".attachments"}
mkdir -p "$OBSIDIAN_VAULT_PATH/.obsidian"

# Create welcome note
cat > "$OBSIDIAN_VAULT_PATH/Welcome.md" << EOF
# Welcome, ${USER_NAME}

Date: \$(date '+%Y-%m-%d')

## Setup
- **Vault Path**: ${OBSIDIAN_VAULT_PATH}
- **Hindsight**: ${HINDSIGHT_URL}
- **Environment**: WSL ↔ Windows

## Structure
- **Daily Notes/**: Daily journaling
- **Templates/**: Note templates
- **Projects/**: Active projects
- **Research/**: Research notes
- **Archive/**: Archived content

## Quick Links
- [Daily Note](Daily\ Notes/\$(date '+%Y-%m-%d').md)
- [Templates](Templates/)
- [Projects](Projects/)

## Getting Started
1. Open this vault in Obsidian
2. Install recommended plugins
3. Set up daily notes
4. Start exploring!

---
*Generated: \$(date)*
EOF

echo "✓ Welcome note created"

# ========================================
# 5. Test Commands
# ========================================

cat << 'EOF'

# Quick Test Commands
# -------------------

# Check vault
ls -la "${OBSIDIAN_VAULT_PATH}"

# Search notes
find "${OBSIDIAN_VAULT_PATH}" -name "*.md" -type f

# Test Hindsight
curl -sk "${HINDSIGHT_URL}/health"
curl -sk "${HINDSIGHT_URL}/v1/default/banks/hermes/stats"

# Search memories
curl -sk "${HINDSIGHT_URL}/v1/default/banks/hermes/memories/recall" \
  -H "Content-Type: application/json" \
  -d '{"query": "user", "k": 5}' | python3 -c "import sys,json; [print(r['content']) for r in json.load(sys.stdin).get('results',[])]"

# Sherlock username check (if installed)
# sherlock {{USER_ALIAS}} --nsfw --print-found --timeout 30

EOF

echo ""
echo "=========================================="
echo "  Setup Complete!"
echo "=========================================="
echo "User: ${USER_NAME} (${USER_ALIAS})"
echo "Vault: ${OBSIDIAN_VAULT_PATH}"
echo "Hindsight: ${HINDSIGHT_URL}"
echo "=========================================="
