---
name: auto-wiki-briefing
description: "Configure automated wiki source harvesting (RSS, arXiv, GitHub) with periodic content ingestion and a daily briefing that mixes AI/agent research updates with serious world, national, and local news."
tags: [automation, wiki, briefing, rss, cron, news]
category: research
prerequisites:
  - "Hermes Agent with cron, terminal, file, and web toolsets"
  - "Hindsight API running (:8888) for wiki semantic search"
  - "watchers skill (watch_rss.py, watch_github.py, _watermark.py)"
  - "wiki-search.py at ~/.hermes/scripts/wiki-search.py"
  - "Obsidian vault with wiki/ directory and SCHEMA.md"
related_skills: [watchers, blogwatcher, obsidian, code-wiki]
---

# Auto Wiki Briefing

Poll configured sources on an interval, ingest new content into a wiki knowledge base, and deliver a daily synthesized briefing covering both domain-specific research and serious news.

## When to Use

- User wants automated wiki population from RSS feeds, arXiv, or GitHub
- User wants a daily briefing combining their research domain + news
- User says "keep my wiki updated automatically" or "send me a daily digest"
- The wiki domain is AI tooling, memory systems, agent infrastructure, or similar

## Architecture

```
sources.yaml (config)
    │
    ├── wiki-harvester.sh (cron: every 30m)
    │     ├── Runs watchers for domain sources (AI research, GitHub, etc.)
    │     ├── web_extract for new item content
    │     ├── Saves raw → wiki/raw/articles/<slug>.md
    │     ├── Synthesizes wiki entity/concept pages (per SCHEMA.md)
    │     ├── Updates wiki/index.md and wiki/log.md
    │     └── Runs wiki-search.py ingest (semantic index)
    │
    └── wiki-daily-briefing (cron: daily, user-configured time)
          ├── Fetches news RSS feeds (world / national / local)
          ├── web_search for overnight developments
          ├── Reads wiki/log.md since last briefing
          ├── Hindsight semantic search for new themes
          └── Synthesizes briefing → Discord/Telegram
```

## Source Configuration

Config lives at `wiki/sources.yaml`. Two categories:

### Category 1: Domain sources (synthesized into wiki)
These are the research/tooling sources that feed wiki pages:
- arXiv API searches
- GitHub repo releases/issues
- RSS feeds from company blogs
- HN front page for domain stories

### Category 2: News sources (briefing only, NOT wiki pages)
These feed the daily briefing's news section only:
- World: BBC World, NPR, Google News World
- National: NPR, Google News US
- State/Local: Google News proxy for state + city

## Reference Files

- **templates/sources.yaml**: Starter config with verified working source examples. Copy to your wiki dir and customize.
- **references/local-news-guide.md**: How to find news feeds for small towns using Google News proxy, with geography tips and filtering advice.
- **scripts/wiki-harvester.sh**: The fetch/ingest orchestrator. Runs watchers, collects new items, triggers reindex. Returns `__HARVEST_NEW__` markers for the agent to process into wiki pages.

## Procedure

### 1. Survey sources

For domain sources, identify:
- Which blogs/RSS feeds cover the wiki's domain
- Which GitHub repos to track
- Which arXiv categories are relevant
- HN keywords to filter for

For news sources:
- World: BBC World RSS, NPR, Google News World — always work
- National: NPR, Google News US — always work
- **Local (small towns)**: Direct RSS rarely exists. Use Google News search proxy (see `references/local-news-guide.md`)

### 2. Create sources.yaml

Use `templates/sources.yaml` as a starter. Verify every RSS URL works before adding (see watchers skill for verification pattern).

### 3. Configure the harvester

- Set wiki path, Hindsight URL, intervals
- Wire each source to a watcher script
- Test one source end-to-end before adding more

### 4. Configure the daily briefing

- Set delivery time
- Set delivery target (Discord channel, Telegram)
- Set local news geography (state + city for Google News queries)
- Define "serious news" filter in the briefing prompt

## Briefing Output Structure

```
📰 Daily Briefing — [date]

🌍 World News (2-3 top stories)
🇺🇸 National News (2-3 top stories)
🏠 [State/Local] News (1-2 stories)

🧠 [Domain] Intelligence
  — New wiki pages created
  — Key themes/patterns emerging
  — Notable claims or contradictions

📊 Wiki Stats

⚠️ Action Items
  — Pages needing review
  — Stale pages to update
```

## News Filter Rules

Include:
- Politics, policy, legislation, elections
- Economics, business, labor
- International relations, conflicts
- Science and technology breakthroughs
- Major weather/natural events
- Major infrastructure or development news

Exclude:
- Sports scores and game recaps
- Celebrity gossip, entertainment
- Product reviews, unboxings
- Opinion/editorial columns
- Local petty crime, routine accidents
- Clickbait, listicles, filler

For local news: focus on city/county government, state politics, major local employers, education policy, infrastructure, community development.

## Wiki Page Synthesis Rules

When synthesizing a new domain source into a wiki page:
- Follow the wiki SCHEMA.md conventions (frontmatter, wikilinks, confidence)
- Create entity pages for named tools/products
- Create concept pages for patterns/ideas
- Add minimum 2 outbound wikilinks
- Update index.md and log.md
- Don't create pages for passing mentions
- Mark confidence level (high/medium/low) and source count

## Pitfalls

1. **Broken RSS feeds**: Always verify before configuring. See `watchers` skill for common failures and the Google News proxy pattern for local news.
2. **Overloading the briefing**: Cap news at 2-3 stories per section. The briefing is a scannable summary, not a news dump.
3. **Wiki bloat**: Don't create a wiki page for every article. Aggregate related sources into existing pages when possible. Create new pages only for genuinely new entities or concepts.
4. **Stale local news in small towns**: Google News search for small towns returns low volume. Broaden to state-level or nearest mid-size city for meaningful coverage.
5. **First-run baseline**: Watchers record a baseline on first run and emit nothing. The first briefing after setup won't have news from watchers — only from direct RSS polling in the briefing job itself.
6. **Concurrent vault writes**: If multiple cron jobs write to the same wiki files (index.md, log.md), they can overwrite each other. The daily briefing should be the ONLY job that writes to news sections of wiki files. The harvester should be the ONLY job that writes wiki pages and index/log.
7. **Skipping the news filter**: Without explicit instructions, the model may include sports, entertainment, or low-quality news. The briefing prompt MUST include the serious-news filter rules.

## Verification

After setup:
1. Run `wiki-harvester.sh` manually, check that raw articles appear in `wiki/raw/articles/`
2. Check that wiki pages are synthesized with proper frontmatter
3. Run `wiki-search.py ingest` and verify Hindsight returns results
4. Run the briefing cron job manually, verify delivery format
5. Check that the briefing respects the news filter (no sports/celebrity)
