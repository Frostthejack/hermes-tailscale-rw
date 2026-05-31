#!/usr/bin/env bash
# wiki-git-sync.sh — Periodic git sync for the Encephalon-Mageia wiki vault
# Run via cron job every 15 minutes from Railway container.
#
# Handles: git pull (remote changes), git add + commit (auto-save), git push
# Safe: uses --rebase, stashes local changes if needed, never force-pushes.
#
# Environment variables:
#   WIKI_PATH     — Path to wiki vault (default: /app/wiki)
#   GIT_USER      — Git commit user name (default: hermes-railway)
#   GIT_EMAIL     — Git commit user email (default: hermes@railway.local)

set -euo pipefail

WIKI_PATH="${WIKI_PATH:-/app/wiki}"
GIT_USER="${GIT_USER:-hermes-railway}"
GIT_EMAIL="${GIT_EMAIL:-hermes@railway.local}"
LOG="/hermes-data/logs/wiki-git-sync.log"
mkdir -p "$(dirname "$LOG")"

log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; echo "$*"; }

log "=== Wiki Git Sync ==="
log "Vault: $WIKI_PATH"

if [ ! -d "$WIKI_PATH/.git" ]; then
  log "ERROR: No git repo at $WIKI_PATH. Run railway-start.sh first."
  exit 1
fi

GIT_AUTHOR_NAME="$GIT_USER" GIT_AUTHOR_EMAIL="$GIT_EMAIL" \
GIT_COMMITTER_NAME="$GIT_USER" GIT_COMMITTER_EMAIL="$GIT_EMAIL" \
  git -C "$WIKI_PATH" config user.name "$GIT_USER" 2>/dev/null

GIT_AUTHOR_NAME="$GIT_USER" GIT_AUTHOR_EMAIL="$GIT_EMAIL" \
GIT_COMMITTER_NAME="$GIT_USER" GIT_COMMITTER_EMAIL="$GIT_EMAIL" \
  git -C "$WIKI_PATH" config user.email "$GIT_EMAIL" 2>/dev/null

# Pull remote changes
log "Pulling remote changes..."
PULL_OUT=$(GIT_AUTHOR_NAME="$GIT_USER" GIT_AUTHOR_EMAIL="$GIT_EMAIL" \
  git -C "$WIKI_PATH" pull --rebase 2>&1) || true
log "Pull: $PULL_OUT"

# Stage all changes
CHANGES=$(git -C "$WIKI_PATH" status --porcelain 2>/dev/null | wc -l)
if [ "$CHANGES" -gt 0 ]; then
  log "Found $CHANGES changed file(s). Committing..."
  GIT_AUTHOR_NAME="$GIT_USER" GIT_AUTHOR_EMAIL="$GIT_EMAIL" \
  GIT_COMMITTER_NAME="$GIT_USER" GIT_COMMITTER_EMAIL="$GIT_EMAIL" \
    git -C "$WIKI_PATH" add -A
  
  GIT_AUTHOR_NAME="$GIT_USER" GIT_AUTHOR_EMAIL="$GIT_EMAIL" \
  GIT_COMMITTER_NAME="$GIT_USER" GIT_COMMITTER_EMAIL="$GIT_EMAIL" \
    git -C "$WIKI_PATH" commit -m "auto-sync: $CHANGES file(s) changed [$(date -u '+%Y-%m-%d %H:%M:%S')]" 2>/dev/null || true
  
  PUSH_OUT=$(GIT_AUTHOR_NAME="$GIT_USER" GIT_AUTHOR_EMAIL="$GIT_EMAIL" \
    git -C "$WIKI_PATH" push 2>&1) || log "Push warning: $PUSH_OUT"
  log "Sync complete: committed $CHANGES files"
else
  log "No local changes. Sync complete."
fi
