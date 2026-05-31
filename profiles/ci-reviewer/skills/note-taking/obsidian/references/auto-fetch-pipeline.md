# Wiki Auto-Fetch Infrastructure

## What It Is

A pipeline that automatically polls external sources, fetches new content, synthesizes wiki pages, and re-indexes the knowledge base. Runs alongside the Obsidian vault to keep it continuously updated.

## Components

| Component | Location | Purpose |
|---|---|---|
| `sources.yaml` | `wiki/sources.yaml` | Feed configuration (wiki_sources + news_sources) |
| `wiki-harvester.sh` | `~/.hermes/scripts/wiki-harvester.sh` | Poll wiki_sources, fetch, ingest, re-index |
| `wiki-daily-briefing.sh` | `~/.hermes/scripts/wiki-daily-briefing.sh` | Collect news + wiki stats for daily briefing |
| Cron: Wiki Harvester | Every 30 min | Runs harvester |
| Cron: Daily Briefing | Daily 1 PM CST | Synthesizes + delivers briefing (Discord + Telegram) |

## sources.yaml Sections

**wiki_sources** → fetched content gets synthesized into wiki pages via agent, then indexed into Hindsight `mimir-well` bank:
- HN AI stories, arXiv papers, GitHub releases (hermes, hindsight, obsidian, MCP, antigravity), Google/OpenAI/Anthropic blogs

**news_sources** → included in daily briefing only (NOT wiki pages):
- Local (Marshall/mid-MO): ABC17, Google News Columbia/Marshall/Saline County
- State (Missouri): Missouri Independent, Google News Missouri
- National: NPR, Google News US
- World: BBC, Google News World, Al Jazeera

## Watermark & State

- `~/.hermes/watcher-state/<name>.json` — per-source watermark (dedup)
- `~/.hermes/watcher-state/<name>-pending.md` — new items waiting for synthesis
- `~/.hermes/watcher-state/briefing-<name>-<date>.cache` — daily news cache
- Clean pending files: `find ~/.hermes/watcher-state -name "*-pending.md" -mtime +7 -delete`

## Adding a New Wiki Source

1. Add entry to `wiki_sources` in `sources.yaml`
2. Verify the feed works: `python3 ~/.hermes/skills/devops/watchers/scripts/watch_rss.py --name <name> --url <url> --max 3`
3. Create a cron job that runs the harvester (or wait for next 30-min tick)
4. The harvester's cron prompt should instruct the agent to synthesize new items into wiki pages

## Adding a New News Source

1. Add entry to `news_sources` in `wiki/sources.yaml`
2. Verify the feed works (many published RSS URLs are broken — test first)
3. The daily briefing cron will pick it up automatically on next run
