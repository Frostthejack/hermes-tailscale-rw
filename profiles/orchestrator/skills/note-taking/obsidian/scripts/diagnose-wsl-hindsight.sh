#!/bin/bash
# Diagnostic script for WSL + Hindsight + Obsidian Vault connectivity
# Usage: source this file or run directly
# Dependencies: curl, bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Default configuration (override with env vars)
HINDSIGHT_HOST="${HINDSIGHT_HOST:-192.168.0.40}"
HINDSIGHT_PORT="${HINDSIGHT_PORT:-8888}"
HINDSIGHT_URL="${HINDSIGHT_URL:-http://${HINDSIGHT_HOST}:${HINDSIGHT_PORT}}"
OBSIDIAN_VAULT_PATH="${OBSIDIAN_VAULT_PATH:-$HOME/Documents/Obsidian Vault}"

echo "==============================================="
echo "  WSL + Hindsight + Obsidian Diagnostics"
echo "==============================================="
echo ""

# --- Check 1: WSL Environment ---
log_info "Check 1: WSL Environment"
if grep -qi microsoft /proc/version 2>/dev/null; then
    log_ok "Running in WSL"
    echo "  Kernel: $(uname -r)"
else
    log_warn "Not running in WSL (may be native Linux)"
fi
echo ""

# --- Check 2: Windows Host IP ---
log_info "Check 2: Windows Host IP"
if command -v ip &>/dev/null; then
    WIN_IP=$(ip route | grep default | awk '{print $3}' || echo "unknown")
    echo "  Default gateway (Windows host): $WIN_IP"
    if [ "$WIN_IP" != "unknown" ]; then
        log_ok "Detected Windows host at $WIN_IP"
    fi
else
    log_warn "Cannot determine Windows IP"
fi
echo ""

# --- Check 3: Hindsight Host Configuration ---
log_info "Check 3: Hindsight Host Configuration"
echo "  HINDSIGHT_HOST: $HINDSIGHT_HOST"
echo "  HINDSIGHT_PORT: $HINDSIGHT_PORT"
echo "  HINDSIGHT_URL:  $HINDSIGHT_URL"

if [ "$HINDSIGHT_HOST" = "127.0.0.1" ] || [ "$HINDSIGHT_HOST" = "localhost" ]; then
    log_warn "HINDSIGHT_HOST is localhost - this may not work from WSL!"
    log_warn "Use Windows host IP instead (e.g., 192.168.0.40)"
else
    log_ok "Using non-localhost host: $HINDSIGHT_HOST"
fi
echo ""

# --- Check 4: Hindsight Connectivity ---
log_info "Check 4: Hindsight Connectivity Test"
if curl -sk --max-time 5 "${HINDSIGHT_URL}/health" &>/dev/null; then
    log_ok "Hindsight is reachable at ${HINDSIGHT_URL}"
    HEALTH=$(curl -sk "${HINDSIGHT_URL}/health" 2>/dev/null || echo "{error}")
    echo "  Health: $HEALTH"
else
    log_error "Cannot reach Hindsight at ${HINDSIGHT_URL}"
    log_info "Troubleshooting:"
    echo "  1. Is Hindsight running on Windows?"
    echo "  2. Is Windows firewall allowing port $HINDSIGHT_PORT?"
    echo "  3. Try: curl -sk http://${HINDSIGHT_HOST}:${HINDSIGHT_PORT}/health"
    echo "  4. From WSL, ping Windows host: ping -c 2 ${HINDSIGHT_HOST}"
fi
echo ""

# --- Check 5: Hindsight API ---
log_info "Check 5: Hindsight API Test"
if curl -sk --max-time 5 "${HINDSIGHT_URL}/openapi.json" &>/dev/null; then
    log_ok "Hindsight API is responding"
    BANKS=$(curl -sk "${HINDSIGHT_URL}/v1/default/banks" 2>/dev/null | grep -o '"bank_id":"[^"]*"' | cut -d'"' -f4 | tr '\n' ', ' || echo "none")
    echo "  Available banks: ${BANKS%, }"
else
    log_warn "Hindsight API not responding"
fi
echo ""

# --- Check 6: Obsidian Vault Path ---
log_info "Check 6: Obsidian Vault Path"
echo "  OBSIDIAN_VAULT_PATH: $OBSIDIAN_VAULT_PATH"
if [ -d "$OBSIDIAN_VAULT_PATH" ]; then
    log_ok "Vault directory exists"
    FILE_COUNT=$(find "$OBSIDIAN_VAULT_PATH" -name "*.md" -type f 2>/dev/null | wc -l)
    echo "  Markdown files: $FILE_COUNT"
else
    log_warn "Vault directory does not exist"
    echo "  Creating: $OBSIDIAN_VAULT_PATH"
    mkdir -p "$OBSIDIAN_VAULT_PATH" || log_error "Failed to create vault directory"
fi
echo ""

# --- Check 7: Network Path Test (if using Windows path) ---
log_info "Check 7: Windows Path Access"
if echo "$OBSIDIAN_VAULT_PATH" | grep -q "^/mnt/"; then
    WIN_PATH=$(echo "$OBSIDIAN_VAULT_PATH" | sed 's|^/mnt/\([a-z]\)/|\U\1:\\|; s|/|\\\\|g')
    echo "  Windows equivalent: $WIN_PATH"
    if [ -d "$OBSIDIAN_VAULT_PATH" ]; then
        log_ok "Windows path is accessible from WSL"
    else
        log_error "Windows path is NOT accessible from WSL"
        log_info "Check: Is the Windows directory valid?"
        log_info "Try: ls \"$OBSIDIAN_VAULT_PATH\""
    fi
else
    log_info "Not a Windows-mounted path (local Linux path)"
fi
echo ""

# --- Summary ---
echo "==============================================="
echo "  Summary"
echo "==============================================="
echo ""
echo "Hindsight:  ${HINDSIGHT_URL}"
echo "Vault:      $OBSIDIAN_VAULT_PATH"
echo ""
echo "For issues:"
echo "  - Hindsight unreachable: Check Windows firewall & service"
echo "  - Path inaccessible: Check WSL/Windows path mapping"
echo "  - Spaces in path: Always quote path variables"
echo ""

# Quick test commands
echo "Quick test commands:"
echo "  curl -sk ${HINDSIGHT_URL}/health"
echo "  ls \"${OBSIDIAN_VAULT_PATH}\""
echo "  find \"${OBSIDIAN_VAULT_PATH}\" -name \"*.md\" | head -5"
echo ""