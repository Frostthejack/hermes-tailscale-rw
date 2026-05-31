# wiki-search.py — Windows Port Notes

## What Changed from WSL

| Item | WSL | Windows |
|------|-----|---------|
| Script path | `~/.hermes/scripts/wiki-search.py` | `%APPDATA%\Local\hermes\skills\research\llm-wiki\scripts\wiki-search.py` |
| `ws` CLI symlink | `~/.local/bin/ws` → symlinked | Not symlinked; invoke `python3` directly |
| Default `WIKI_PATH` | `~/wiki` | `C:\Users\luned\Vault\Encephalon-Mageia\wiki` |
| Default `HINDSIGHT_URL` | `http://0.0.0.0:8888` | `http://127.0.0.1:8888` |
| Temp files | Hardcoded `/tmp/wiki_ingest_*.md` | `tempfile.mkstemp()` (cross-platform) |
| Ingest endpoint | `files/retain` (requires markitdown) | `memories` JSON endpoint (no parser needed) |
| State file | `~/.wiki-search-state.json` | `Encephalon-Mageia/.wiki-search-state.json` (next to vault) |
| Ingest mode | Synchronous | Async (`"async": True`) — queues all files without blocking |

## CLI Usage on Windows

```bash
# Ingest all wiki pages
python3 "%APPDATA%\Local\hermes\skills\research\llm-wiki\scripts\wiki-search.py" ingest

# Force re-ingest
python3 "%APPDATA%\Local\hermes\skills\research\llm-wiki\scripts\wiki-search.py" reingest

# Semantic search
python3 "%APPDATA%\Local\hermes\skills\research\llm-wiki\scripts\wiki-search.py" search "agent memory" --limit 5

# Check status
python3 "%APPDATA%\Local\hermes\skills\research\llm-wiki\scripts\wiki-search.py" status
```

## Environment Variables

- `WIKI_PATH` — overrides default wiki path
- `BANK_ID` — Hindsight bank ID (default: `mimir-well`)
- `HINDSIGHT_URL` — Hindsight API URL (default: `http://127.0.0.1:8888`)
- `WIKI_SEARCH_STATE` — state file path (default: `<vault>/.wiki-search-state.json`)

## Hindsight API Differences

The `memories` JSON endpoint (`POST /v1/default/banks/{bank_id}/memories`) accepts `MemoryItem` objects:

```json
{
  "items": [{
    "content": "full markdown text of wiki page",
    "context": "Wiki page: page-slug",
    "tags": ["wiki", "concepts"],
    "metadata": {
      "source": "wiki",
      "path": "concepts/page-slug.md",
      "filename": "page-slug.md"
    },
    "timestamp": "unset"
  }],
  "async": true
}
```

Key fields:
- `content` (required): the full text
- `tags`: first tag is always `"wiki"`, second is the subdirectory (e.g. `"concepts"`, `"entities"`)
- `timestamp: "unset"`: marks as timeless reference material (not time-bound)
- `async: true`: queues in background, returns immediately with `operation_id`

## Troubleshooting

- **`400 Parser(s) not available: ['markitdown']`**: You're hitting `files/retain` instead of the JSON `memories` endpoint. The wiki-search.py script uses the correct endpoint — if you wrote a custom script, switch to the JSON endpoint.
- **Hindsight not reachable**: Check `curl http://127.0.0.1:8888/health`. Expected: `{"status":"healthy","database":"connected"}`.
- **`requests` import error**: Run `pip install requests` in the Python env that runs the script.
- **Timeout on ingest large batch**: The script uses async mode by default, so it shouldn't time out. If you modified it to synchronous, switch `async: true` back.
