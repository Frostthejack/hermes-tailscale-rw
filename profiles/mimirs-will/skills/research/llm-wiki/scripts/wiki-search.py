#!/usr/bin/env python3
"""
wiki-search: Semantic search over a markdown wiki using Hindsight API.

Uses Hindsight's built-in embeddings (no local model or markitdown needed).
Ingest wiki pages → Hindsight bank → semantic recall search.

Prerequisites:
  - Hindsight API running (default: http://127.0.0.1:8888)
  - Python packages: requests

Usage:
    python3 wiki-search.py ingest                    # Ingest all wiki files
    python3 wiki-search.py search "query"            # Semantic search
    python3 wiki-search.py search "query" --limit 10 # Top-10 results
    python3 wiki-search.py status                    # Check bank status
    python3 wiki-search.py reingest                  # Force re-ingest all files

Environment variables:
    HINDSIGHT_URL   - Hindsight API URL (default: http://127.0.0.1:8888)
    BANK_ID         - Hindsight bank ID (default: mimir-well)
    WIKI_PATH       - Path to wiki directory (default: C:/Users/luned/Vault/Encephalon-Mageia/wiki)
"""

import sys
import os
import json
import hashlib
import time
import argparse
import tempfile
from pathlib import Path

try:
    import requests
except ImportError:
    print("ERROR: 'requests' package not installed. Run: pip install requests")
    sys.exit(1)

# Configuration
HINDSIGHT_URL = os.environ.get("HINDSIGHT_URL", "http://127.0.0.1:8888")
BANK_ID = os.environ.get("BANK_ID", "mimir-well")

# Default wiki path: use WIKI_PATH env var, or fall back to wiki/ inside the Obsidian vault
_DEFAULT_WIKI = Path("C:/Users/luned/Vault/Encephalon-Mageia/wiki")
WIKI_PATH = Path(os.environ.get("WIKI_PATH", str(_DEFAULT_WIKI)))

# State file: stored next to the wiki for easy discovery
_STATE_DEFAULT = WIKI_PATH.parent / ".wiki-search-state.json"
STATE_FILE = Path(os.environ.get("WIKI_SEARCH_STATE", str(_STATE_DEFAULT)))

# Files/directories to skip
SKIP_FILES = {"SCHEMA.md", "index.md", "log.md"}
SKIP_DIRS = {"raw", "_archive", "_meta"}


def chunk_text(text: str, max_chars: int = 2000, overlap: int = 200) -> list:
    """Split text into overlapping chunks."""
    if len(text) <= max_chars:
        return [text]
    chunks = []
    start = 0
    while start < len(text):
        end = start + max_chars
        if end < len(text):
            para_break = text.rfind("\n\n", start, end)
            if para_break > start + max_chars // 2:
                end = para_break
            else:
                sent_break = text.rfind(". ", start, end)
                if sent_break > start + max_chars // 2:
                    end = sent_break + 1
        chunks.append(text[start:end].strip())
        start = end - overlap
    return [c for c in chunks if c]


def get_wiki_files() -> list:
    """Get all wiki markdown files (not in raw/, not index/log/schema)."""
    files = []
    for f in WIKI_PATH.rglob("*.md"):
        parts = f.relative_to(WIKI_PATH).parts
        if any(d in SKIP_DIRS for d in parts):
            continue
        if f.name in SKIP_FILES:
            continue
        files.append(f)
    return sorted(files)


def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {"files": {}}


def save_state(state: dict):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2))


def file_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_hindsight() -> bool:
    try:
        resp = requests.get(f"{HINDSIGHT_URL}/health", timeout=5)
        return resp.status_code == 200
    except requests.ConnectionError:
        return False


def ingest_file(filepath: Path, state: dict, force: bool = False) -> bool:
    """Ingest a single wiki file into Hindsight via the JSON memories/retain endpoint (async)."""
    rel_path = str(filepath.relative_to(WIKI_PATH)).replace("\\", "/")
    current_hash = file_hash(filepath)

    if not force and str(rel_path) in state["files"] and state["files"][str(rel_path)] == current_hash:
        print(f"  ⊙ Skip (unchanged): {rel_path}")
        return True

    content = filepath.read_text()

    # Build tags from directory structure
    tags = ["wiki"]
    parent = filepath.relative_to(WIKI_PATH).parent
    if str(parent) != ".":
        tags.append(str(parent).replace("\\", "/"))

    try:
        # Submit async — Hindsight processes in background
        resp = requests.post(
            f"{HINDSIGHT_URL}/v1/default/banks/{BANK_ID}/memories",
            json={
                "items": [{
                    "content": content,
                    "context": f"Wiki page: {filepath.stem}",
                    "tags": tags,
                    "metadata": {
                        "source": "wiki",
                        "path": rel_path,
                        "filename": filepath.name
                    },
                    "document_id": f"wiki/{rel_path}",
                    "timestamp": "unset"
                }],
                "async": True
            },
            timeout=30
        )

        if resp.status_code == 200:
            result = resp.json()
            op_id = result.get("operation_id", "")
            print(f"  ✓ Queued: {rel_path}" + (f" (op: {op_id[:8]}...)" if op_id else ""))
            state["files"][str(rel_path)] = current_hash
            return True
        else:
            print(f"  ✗ Failed ({resp.status_code}): {rel_path} — {resp.text[:200]}")
            return False
    except requests.RequestException as e:
        print(f"  ✗ Error: {rel_path} — {e}")
        return False


def ingest_all(force: bool = False):
    """Ingest all wiki files into Hindsight."""
    print(f"Wiki path: {WIKI_PATH}")
    print(f"Hindsight: {HINDSIGHT_URL}")
    print(f"Bank: {BANK_ID}")
    print()

    if not check_hindsight():
        print("✗ Cannot connect to Hindsight API. Is it running?")
        return

    files = get_wiki_files()
    print(f"Found {len(files)} wiki files")
    print()

    state = load_state()
    success = 0
    skipped = 0
    failed = 0

    for f in files:
        if ingest_file(f, state, force=force):
            if str(f.relative_to(WIKI_PATH)) in state.get("files", {}):
                skipped += 1
            else:
                success += 1
        else:
            failed += 1
        time.sleep(0.2)

    save_state(state)
    print()
    print(f"Done: {success} ingested, {skipped} skipped (unchanged), {failed} failed")

    resp = requests.get(f"{HINDSIGHT_URL}/v1/default/banks/{BANK_ID}/stats")
    if resp.status_code == 200:
        stats = resp.json()
        print(f"Bank '{BANK_ID}': {stats.get('fact_count', '?')} facts")


def search(query: str, limit: int = 5):
    """Search the wiki using Hindsight semantic recall."""
    if not check_hindsight():
        print("✗ Cannot connect to Hindsight API.")
        return

    resp = requests.post(
        f"{HINDSIGHT_URL}/v1/default/banks/{BANK_ID}/memories/recall",
        json={"query": query, "limit": limit},
        timeout=30
    )

    if resp.status_code != 200:
        print(f"Search failed ({resp.status_code}): {resp.text[:200]}")
        return

    data = resp.json()
    results = data.get("results", [])

    if not results:
        print(f"No results for: '{query}'")
        print("Tip: Run 'ingest' first if you haven't yet.")
        return

    print(f"Semantic search: '{query}'")
    print(f"{'─' * 60}")

    for i, r in enumerate(results, 1):
        text = r.get("text", "").strip()
        if len(text) > 300:
            text = text[:297] + "..."
        meta = r.get("metadata", {})
        path = meta.get("path", "")
        source = f" ← {path}" if path else ""
        print(f"\n{i}. {text}{source}")

    print(f"\n{'─' * 60}")
    print(f"{len(results)} results")


def show_status():
    """Show bank status and ingestion state."""
    try:
        resp = requests.get(f"{HINDSIGHT_URL}/health", timeout=5)
        print(f"Hindsight API: {'✓ healthy' if resp.status_code == 200 else '✗ unhealthy'}")
    except requests.ConnectionError:
        print("Hindsight API: ✗ not reachable")
        return

    resp = requests.get(f"{HINDSIGHT_URL}/v1/default/banks/{BANK_ID}/stats")
    if resp.status_code == 200:
        stats = resp.json()
        print(f"Bank '{BANK_ID}':")
        print(f"  Facts: {stats.get('fact_count', '?')}")
        print(f"  Last doc: {stats.get('last_document_at', 'never')}")

    state = load_state()
    wiki_files = get_wiki_files()
    print(f"\nIngested files: {len(state['files'])}")
    print(f"Wiki files: {len(wiki_files)}")
    if len(state['files']) < len(wiki_files):
        print(f"⚠ {len(wiki_files) - len(state['files'])} files not yet ingested")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Semantic wiki search via Hindsight")
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("ingest", help="Ingest all wiki files")
    subparsers.add_parser("reingest", help="Force re-ingest all files")

    search_parser = subparsers.add_parser("search", help="Semantic search")
    search_parser.add_argument("query", nargs="+", help="Search query")
    search_parser.add_argument("--limit", "-l", type=int, default=10, help="Max results")

    subparsers.add_parser("status", help="Show status")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    if args.command == "ingest":
        ingest_all(force=False)
    elif args.command == "reingest":
        ingest_all(force=True)
    elif args.command == "search":
        search(" ".join(args.query), limit=args.limit)
    elif args.command == "status":
        show_status()
