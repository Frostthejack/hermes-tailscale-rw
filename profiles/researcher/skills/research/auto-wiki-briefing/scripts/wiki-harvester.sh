#!/usr/bin/env bash
# wiki-harvester.sh — Fetch new content from configured sources,
# synthesize wiki pages, and reindex.
#
# Usage:
#   wiki-harvester.sh [--source <name>] [--dry-run]
#
# Without --source, runs all domain-type sources from sources.yaml.
# With --source, runs only that specific source.
#
# Dependencies:
#   - watch_*.py scripts (watchers skill)
#   - wiki-search.py (at $WIKI_SEARCH_SCRIPT)
#   - sources.yaml at $WIKI_SOURCES
#   - Hermes web_extract tool (called by the agent, not directly)
#
# This script is the FETCH layer. Page synthesis and reindex are
# handled by the agent (Hermes) interpreting the output.
# The agent should:
#   1. Run this script
#   2. For each new raw article, synthesize a wiki page
#   3. Update index.md and log.md
#   4. Run wiki-search.py ingest

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
WIKI_PATH="${WIKI_PATH:-/mnt/c/Users/luned/Vault/Encephalon-Mageia/wiki}"
WIKI_RAW="$WIKI_PATH/raw/articles"
WIKI_SOURCES="${WIKI_SOURCES:-$WIKI_PATH/sources.yaml}"
WIKI_SEARCH_SCRIPT="${WIKI_SEARCH_SCRIPT:-$HERMES_HOME/scripts/wiki-search.py}"
WATCHER_SCRIPTS="${WATCHER_SCRIPTS:-$HERMES_HOME/skills/devops/watchers/scripts}"
STATE_DIR="${HERMES_HOME}/watcher-state"
DRY_RUN=false
SOURCE_FILTER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE_FILTER="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

mkdir -p "$WIKI_RAW" "$STATE_DIR"

echo "=== Wiki Harvester ==="
echo "Wiki:    $WIKI_PATH"
echo "Sources: $WIKI_SOURCES"
echo "Dry run: $DRY_RUN"
echo ""

# ── Run RSS watchers ──────────────────────────────────────────────
run_rss_watcher() {
  local name="$1" url="$2"
  echo "→ $name"
  if $DRY_RUN; then
    echo "  [dry-run] Would run: watch_rss.py --name $name --url $url"
    return
  fi
  output=$(python3 "$WATCHER_SCRIPTS/watch_rss.py" \
    --name "$name" \
    --url "$url" \
    --max 5 \
    2>/dev/null) || true
  if [[ -n "$output" ]]; then
    echo "$output"
    echo "__HARVEST_NEW__:$name"
  else
    echo "  (no new items)"
  fi
}

# ── Run GitHub watcher ─────────────────────────────────────────────
run_github_watcher() {
  local name="$1" repo="$2"
  echo "→ GitHub: $name ($repo)"
  if $DRY_RUN; then
    echo "  [dry-run] Would run: watch_github.py --name $name --repo $repo"
    return
  fi
  output=$(python3 "$WATCHER_SCRIPTS/watch_github.py" \
    --name "$name" \
    --repo "$repo" \
    2>/dev/null) || true
  if [[ -n "$output" ]]; then
    echo "$output"
    echo "__HARVEST_NEW__:$name"
  else
    echo "  (no new items)"
  fi
}

# ── Parse sources.yaml and run watchers ────────────────────────────
# Simple YAML parsing: extract source blocks and their fields
parse_sources() {
  python3 -c "
import yaml, sys
with open('$WIKI_SOURCES') as f:
    data = yaml.safe_load(f)
sources = data.get('sources', [])
for s in sources:
    if s.get('scope') != 'domain':
        continue
    if '$SOURCE_FILTER' and s['name'] != '$SOURCE_FILTER':
        continue
    print(f\"{s['name']}|{s['type']}|{s.get('url', '')}|{s.get('repo', '')}|{s.get('query', '')}\")
" 2>/dev/null || echo ""
}

echo "--- Running domain watchers ---"
NEW_SOURCES=""

# Check if PyYAML is available; if not, use manual approach
if python3 -c "import yaml" 2>/dev/null; then
  while IFS='|' read -r name type url repo query; do
    [[ -z "$name" ]] && continue
    case "$type" in
      rss)
        result=$(run_rss_watcher "$name" "$url" 2>&1)
        echo "$result"
        if echo "$result" | grep -q "__HARVEST_NEW__"; then
          NEW_SOURCES="$NEW_SOURCES $name"
        fi
        ;;
      github)
        result=$(run_github_watcher "$name" "$repo" 2>&1)
        echo "$result"
        if echo "$result" | grep -q "__HARVEST_NEW__"; then
          NEW_SOURCES="$NEW_SOURCES $name"
        fi
        ;;
      arxiv|http_json)
        echo "→ $name ($type) — requires agent-side processing (web_search + web_extract)"
        echo "__HARVEST_AGENT__:$name"
        NEW_SOURCES="$NEW_SOURCES $name"
        ;;
    esac
  done < <(parse_sources)
else
  echo "PyYAML not installed. Install with: pip install pyyaml"
  echo "Falling back to manual source list..."
  # Hardcoded fallback for known sources
  run_rss_watcher "anthropic-engineering" "https://www.anthropic.com/engineering/building-effective-agents" 2>&1
  run_rss_watcher "google-ai-blog" "https://blog.google/technology/ai/rss/" 2>&1
  run_github_watcher "hermes-agent-releases" "NousResearch/hermes-agent" 2>&1
  run_github_watcher "hindsight-releases" "NousResearch/hindsight" 2>&1
fi

echo ""
echo "--- Reindex ---"
if $DRY_RUN; then
  echo "[dry-run] Would run: python3 $WIKI_SEARCH_SCRIPT ingest"
else
  python3 "$WIKI_SEARCH_SCRIPT" ingest 2>&1 | tail -5
fi

echo ""
echo "=== Done ==="
echo "New sources: ${NEW_SOURCES:-none}"

# Write marker for the agent to know what needs synthesis
if [[ -n "$NEW_SOURCES" ]]; then
  echo ""
  echo "__HARVEST_COMPLETE__"
  echo "NEXT: For each new source above, call web_extract on the emitted URLs,"
  echo "synthesize wiki pages, update index.md + log.md, then reindex."
fi
