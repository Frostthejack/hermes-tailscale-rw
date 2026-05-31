# YAML-Driven Multi-Source Harvester Pattern

## Overview

For projects that poll many sources (wiki auto-fetch, news aggregation, etc.), the pattern is:

1. **`sources.yaml`** — single config file listing all sources with metadata
2. **`harvester.sh`** — orchestration script that parses YAML, runs watchers, triggers downstream actions
3. **Cron job** — runs the harvester on interval

This scales better than one-cron-job-per-source when you have 5+ sources.

## sources.yaml Structure

Use two sections — one for content that gets synthesized (wiki), one for content consumed directly (news):

```yaml
wiki_sources:
  - name: unique-watcher-name    # Used as --name for watch_*.py (watermark key)
    type: rss | github | http_json | google_news
    url: https://...             # For RSS/http sources
    repo: owner/repo             # For GitHub sources
    scope: releases | issues     # For GitHub sources
    description: "Human-readable purpose"
    cadence: 60                  # Polling interval in minutes (informational)
    max_items: 5                 # Max new items per tick
    tags: [ai-tool, agent]       # For wiki synthesis routing

news_sources:
  - name: unique-name
    type: rss | google_news
    url: https://...
    scope: local | state | national | world   # For briefing section routing
    description: "Human-readable purpose"
    max_stories: 3               # Max stories to include in briefing
```

## Delimiter Choice for Shell Parsing

When outputting YAML-parsed data from Python to shell `read`:

- **Tab (`\t`) fails** when fields are empty (consecutive tabs collapse in shell `IFS`)
- **Pipe (`|`)** fails when descriptions contain pipe characters
- **Use `§` (section sign)** — extremely unlikely to appear in URLs or descriptions

```python
# Python side
print(f'{name}§{url}§{type}§{repo}§{scope}§{desc}')
```

```bash
# Shell side
while IFS='§' read -r name url type repo scope desc; do
  [ "$url" = "-" ] && url=""   # Convert placeholder back to empty
  ...
done < <(python3 parse_yaml.py)
```

## Harvester Script Structure

```
harvester.sh
├── Parse sources.yaml (Python one-liner, awk is brittle for YAML)
├── For each source:
│   ├── Check type -> dispatch to watch_rss.py or watch_github.py
│   ├── Collect output -> STATE_DIR/<name>-pending.md
│   └── Log new item count
├── If any new items:
│   └── Run downstream action (wiki ingest, re-index, etc.)
└── Append summary to log.md
```

Key flags to support:
- `--dry-run` — print what would fetch, don't fetch
- `--full` — clear all watermarks, treat as first run

## State Management

- Watermark files: `$STATE_DIR/<name>.json` (managed by `_watermark.py`)
- Pending items: `$STATE_DIR/<name>-pending.md` (for downstream synthesis)
- Daily briefing cache: `$STATE_DIR/briefing-<name>-<date>.cache` (avoid re-fetching same day)
- Clean pending files older than 7 days: `find $STATE_DIR -name "*-pending.md" -mtime +7 -delete`

## Google News RSS as Local News Proxy

Small towns rarely have direct RSS feeds. Use Google News search RSS:

```
https://news.google.com/rss/search?q=City+State+OR+County+County&hl=en-US&gl=US&ceid=US:en
```

Verified fetchable outlets (as of 2026-05):
| Source | URL Pattern | Status |
|---|---|---|
| Google News (any) | `news.google.com/rss/search?q=...` | OK - 100 items, 140KB+ |
| NPR | `feeds.npr.org/1001/rss.xml` | OK |
| BBC World | `feeds.bbci.co.uk/news/world/rss.xml` | OK |
| Al Jazeera | `aljazeera.com/xml/rss/all.xml` | OK |
| ABC17 (Columbia MO) | `abc17news.com/feed/` | OK |
| Missouri Independent | `missouriindependent.com/feed/` | OK |

Known broken (avoid):
| Source | Issue |
|---|---|
| Reuters direct | 401 (paywalled) |
| AP | 401 |
| Most local TV stations | 404 on published RSS URLs |
| Kansas City Star | Timeout |

## Real-World Example

See the working implementation at:
- `~/.hermes/scripts/wiki-harvester.sh`
- `~/.hermes/scripts/wiki-daily-briefing.sh`
- `/mnt/c/Users/luned/Vault/Encephalon-Mageia/wiki/sources.yaml`

As of 2026-05-28: 10 wiki sources, 9 news sources, all verified fetchable.
