---
name: llm-wiki
description: "Karpathy's LLM Wiki: build/query interlinked markdown KB."
version: 2.5.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [wiki, knowledge-base, research, notes, markdown, rag-alternative]
    category: research
    related_skills: [obsidian, arxiv]
---

# Karpathy's LLM Wiki

Build and maintain a persistent, compounding knowledge base as interlinked markdown files.
Based on [Andrej Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

Unlike traditional RAG (which rediscovers knowledge from scratch per query), the wiki
compiles knowledge once and keeps it current. Cross-references are already there.
Contradictions have already been flagged. Synthesis reflects everything ingested.

**Division of labor:** The human curates sources and directs analysis. The agent
summarizes, cross-references, files, and maintains consistency.

## When This Skill Activates

Use this skill when the user:
- Asks to create, build, or start a wiki or knowledge base
- Asks to ingest, add, or process a source into their wiki
- Provides a URL, file, or paste and asks to "ingest this" — **even if they don't explicitly mention the wiki**. If a wiki exists (check `$WIKI_PATH` or default `~/wiki` for `SCHEMA.md`), the ingest skill governs, not bare `web_extract`.
- Asks a question and an existing wiki is present at the configured path
- Asks to lint, audit, or health-check their wiki
- References their wiki, knowledge base, or "notes" in a research context
- Asks for highlights/summary of a source when a wiki exists — ingest first, then summarize from the wiki pages

## Wiki Location

**Location:** Set via `WIKI_PATH` environment variable (e.g. in `~/.hermes/.env`).

Default (Windows): `C:\Users\luned\Vault\Encephalon-Mageia\wiki\`
Default (WSL): `/mnt/c/Users/luned/Vault/Encephalon-Mageia/wiki/`

```bash
WIKI="${WIKI_PATH:-$HOME/wiki}"
```

The wiki is just a directory of markdown files — open it in Obsidian, VS Code, or any editor.

## Architecture: Three Layers

```
wiki/
├── SCHEMA.md           # Conventions, structure rules, domain config
├── index.md            # Sectioned content catalog with one-line summaries
├── log.md              # Chronological action log (append-only, rotated yearly)
├── raw/                # Layer 1: Immutable source material
│   ├── articles/       # Web articles, clippings
│   ├── papers/         # PDFs, arxiv papers
│   ├── transcripts/    # Meeting notes, interviews
│   └── assets/         # Images, diagrams referenced by sources
├── entities/           # Layer 2: Entity pages (people, orgs, products, models)
├── concepts/           # Layer 2: Concept/topic pages
├── comparisons/        # Layer 2: Side-by-side analyses
└── queries/            # Layer 2: Filed query results worth keeping
```

**Layer 1 — Raw Sources:** Immutable. The agent reads but never modifies these.
**Layer 2 — The Wiki:** Agent-owned markdown files. Created, updated, and
cross-referenced by the agent.
**Layer 3 — The Schema:** `SCHEMA.md` defines structure, conventions, and tag taxonomy.

## Resuming an Existing Wiki (CRITICAL — do this every session)

When the user has an existing wiki, **always orient yourself before doing anything**:

① **Run `hindsight_recall`** on the topic at hand — this surfaces prior context from Hindsight's semantic memory, including related entities, past ingests, and decisions. Do this *before* reading wiki files.
② **Read `SCHEMA.md`** — understand the domain, conventions, and tag taxonomy.
③ **Read `index.md`** — learn what pages exist and their summaries.
④ **Scan recent `log.md`** — read the last 20-30 entries to understand recent activity.

```bash
WIKI="${WIKI_PATH:-$HOME/wiki}"
# Orientation reads at session start
read_file "$WIKI/SCHEMA.md"
read_file "$WIKI/index.md"
read_file "$WIKI/log.md" offset=<last 30 lines>
# Re-index for semantic search (also do this after any ingestion)
ws ingest
```

Only after orientation should you ingest, query, or lint. This prevents:
- Creating duplicate pages for entities that already exist
- Missing cross-references to existing content
- Contradicting the schema's conventions
- Repeating work already logged

For large wikis (100+ pages), also run a quick `search_files` for the topic
at hand before creating anything new.

## Initializing a New Wiki

When the user asks to create or start a wiki:

1. Determine the wiki path (from `$WIKI_PATH` env var, or ask the user; default `~/wiki`)
2. Create the directory structure above
3. Ask the user what domain the wiki covers — be specific
4. Write `SCHEMA.md` customized to the domain (see template below)
5. Write initial `index.md` with sectioned header
6. Write initial `log.md` with creation entry
7. Confirm the wiki is ready and suggest first sources to ingest

### SCHEMA.md Template

Adapt to the user's domain. The schema constrains agent behavior and ensures consistency:

```markdown
# Wiki Schema

## Domain
[What this wiki covers — e.g., "AI/ML research", "personal health", "startup intelligence"]

## Conventions
- File names: lowercase, hyphens, no spaces (e.g., `transformer-architecture.md`)
- Every wiki page starts with YAML frontmatter (see below)
- Use `[[wikilinks]]` to link between pages (minimum 2 outbound links per page)
- When updating a page, always bump the `updated` date
- Every new page must be added to `index.md` under the correct section
- Every action must be appended to `log.md`
- **Provenance markers:** On pages that synthesize 3+ sources, append `^[raw/articles/source-file.md]`
  at the end of paragraphs whose claims come from a specific source. This lets a reader trace each
  claim back without re-reading the whole raw file. Optional on single-source pages where the
  `sources:` frontmatter is enough.

## Frontmatter
  ```yaml
  ---
  title: Page Title
  created: YYYY-MM-DD
  updated: YYYY-MM-DD
  type: entity | concept | comparison | query | summary
  tags: [from taxonomy below]
  sources: [raw/articles/source-name.md]
  # Optional quality signals:
  confidence: high | medium | low        # how well-supported the claims are
  contested: true                        # set when the page has unresolved contradictions
  contradictions: [other-page-slug]      # pages this one conflicts with
  ---
  ```

`confidence` and `contested` are optional but recommended for opinion-heavy or fast-moving
topics. Lint surfaces `contested: true` and `confidence: low` pages for review so weak claims
don't silently harden into accepted wiki fact.

### raw/ Frontmatter

Raw sources ALSO get a small frontmatter block so re-ingests can detect drift:

```yaml
---
source_url: https://example.com/article   # original URL, if applicable
ingested: YYYY-MM-DD
sha256: <hex digest of the raw content below the frontmatter>
---
```

The `sha256:` lets a future re-ingest of the same URL skip processing when content is unchanged,
and flag drift when it has changed. Compute over the body only (everything after the closing
`---`), not the frontmatter itself.

## Tag Taxonomy
[Define 10-20 top-level tags for the domain. Add new tags here BEFORE using them.]

Example for AI/ML:
- Models: model, architecture, benchmark, training
- People/Orgs: person, company, lab, open-source
- Techniques: optimization, fine-tuning, inference, alignment, data
- Meta: comparison, timeline, controversy, prediction

Rule: every tag on a page must appear in the taxonomy. If a new tag is needed,
add it here first, then use it. This prevents tag sprawl.

## Page Thresholds
- **Create a page** when an entity/concept appears in 2+ sources OR is central to one source
- **Add to existing page** when a source mentions something already covered
- **DON'T create a page** for passing mentions, minor details, or things outside the domain
- **Split a page** when it exceeds ~200 lines — break into sub-topics with cross-links
- **Archive a page** when its content is fully superseded — move to `_archive/`, remove from index

## Entity Pages
One page per notable entity. Include:
- Overview / what it is
- Key facts and dates
- Relationships to other entities ([[wikilinks]])
- Source references

## Concept Pages
One page per concept or topic. Include:
- Definition / explanation
- Current state of knowledge
- Open questions or debates
- Related concepts ([[wikilinks]])

## Comparison Pages
Side-by-side analyses. Include:
- What is being compared and why
- Dimensions of comparison (table format preferred)
- Verdict or synthesis
- Sources

## Update Policy
When new information conflicts with existing content:
1. Check the dates — newer sources generally supersede older ones
2. If genuinely contradictory, note both positions with dates and sources
3. Mark the contradiction in frontmatter: `contradictions: [page-name]`
4. Flag for user review in the lint report
```

### index.md Template

The index is sectioned by type. Each entry is one line: wikilink + summary.

```markdown
# Wiki Index

> Content catalog. Every wiki page listed under its type with a one-line summary.
> Read this first to find relevant pages for any query.
> Last updated: YYYY-MM-DD | Total pages: N

## Entities
<!-- Alphabetical within section -->

## Concepts

## Comparisons

## Queries
```

**Scaling rule:** When any section exceeds 50 entries, split it into sub-sections
by first letter or sub-domain. When the index exceeds 200 entries total, create
a `_meta/topic-map.md` that groups pages by theme for faster navigation.

### log.md Template

```markdown
# Wiki Log

> Chronological record of all wiki actions. Append-only.
> Format: `## [YYYY-MM-DD] action | subject`
> Actions: ingest, update, query, lint, create, archive, delete
> When this file exceeds 500 entries, rotate: rename to log-YYYY.md, start fresh.

## [YYYY-MM-DD] create | Wiki initialized
- Domain: [domain]
- Structure created with SCHEMA.md, index.md, log.md
```

## Core Operations

### 1. Ingest

When the user provides a source (URL, file, paste), integrate it into the wiki:

① **Capture the raw source:**
   - **Check for existing raw file first** — Before extracting, list the relevant `raw/` subdirectory and check if a file for this URL or title already exists. If it does, read it: if the `ingested` date is today and the content is non-empty, skip re-extraction and reuse the existing file. If the source may have been updated (different `sha256`), re-extract and overwrite. This avoids duplicate work when the same URL is sent multiple times or when batch-ingesting URLs that overlap with prior sessions.
   - URL → use `web_extract` to get markdown, save to `raw/articles/`
   - PDF → use `web_extract` (handles PDFs), save to `raw/papers/`
   - Pasted text → save to appropriate `raw/` subdirectory
   - **Validation:** After extracting, check that the content is actual article prose (not a modal, ad wall, login page, or share.google redirect). See the "web_extract non-article fallback" and "share.google.com shortlinks" pitfalls for detection and fallback steps.
   - Name the file descriptively: `raw/articles/karpathy-llm-wiki-2026.md`\n   - URL → use `web_extract` to get markdown, save to `raw/articles/`\n   - PDF → use `web_extract` (handles PDFs), save to `raw/papers/`\n   - Pasted text → save to appropriate `raw/` subdirectory\n   - **Validation:** After extracting, check that the content is actual article prose (not a modal, ad wall, login page, or ... share.google redirect). See "web_extract non-article fallback" in Pitfalls for detection and fallback steps.\n   - Name the file descriptively: `raw/articles/karpathy-llm-wiki-2026.md`
   - **Add raw frontmatter** (`source_url`, `ingested`, `sha256` of the body).
     On re-ingest of the same URL: recompute the sha256, compare to the stored value —
     skip if identical, flag drift and update if different. This is cheap enough to
     do on every re-ingest and catches silent source changes.
   - **Compute sha256 correctly** — use a Python one-liner to hash the body (everything
     after the closing `---` of the frontmatter), NOT the whole file including frontmatter:
     ```bash
     python3 -c "
     import hashlib
     with open('raw/articles/filename.md') as f:
         content = f.read()
     parts = content.split('---', 2)
     body = parts[2] if len(parts) >= 3 else content
     print(hashlib.sha256(body.encode()).hexdigest())
     "
     ```
     Write the real hash directly — never use a `PLACEHOLDER` string. If computing after
     writing, patch the file immediately.

② **Discuss takeaways** with the user — what's interesting, what matters for
   the domain. (Skip this in automated/cron contexts — proceed directly.)

③ **Check what already exists** — search index.md and use `search_files` to find
   existing pages for mentioned entities/concepts. This is the difference between
   a growing wiki and a pile of duplicates.

④ **Write or update wiki pages:**
   - **New entities/concepts:** Create pages only if they meet the Page Thresholds
     in SCHEMA.md (2+ source mentions, or central to one source)
   - **Existing pages:** Add new information, update facts, bump `updated` date.
     When new info contradicts existing content, follow the Update Policy.
   - **Cross-reference:** Every new or updated page must link to at least 2 other
     pages via `[[wikilinks]]`. Check that existing pages link back.
   - **Tags:** Only use tags from the taxonomy in SCHEMA.md
   - **Provenance:** On pages synthesizing 3+ sources, append `^[raw/articles/source.md]`
     markers to paragraphs whose claims trace to a specific source.
   - **Confidence:** For opinion-heavy, fast-moving, or single-source claims, set
     `confidence: medium` or `low` in frontmatter. Don't mark `high` unless the
     claim is well-supported across multiple sources.

⑤ **Update navigation:**
   - Add new pages to `index.md` under the correct section, alphabetically
   - Update the "Total pages" count and "Last updated" date in index header
   - Append to `log.md`: `## [YYYY-MM-DD] ingest | Source Title`
   - List every file created or updated in the log entry

⑥ **Report what changed** — list every file created or updated to the user.

### 7. Re-index for semantic search

After every ingestion (single or batch), re-index the wiki for semantic search:

```bash
# Windows (direct python invocation)
python3 "%APPDATA%\Local\hermes\skills\research\llm-wiki\scripts\wiki-search.py" ingest

# WSL (symlinked ws CLI)
ws ingest
```

This updates the Hindsight mimir-well bank so new/updated pages are semantically searchable. Check the output for any failures. **Do not skip this step** — without it, new wiki pages won't appear in semantic search results.

### 8. Commit the vault

```bash
# Windows
cd "C:\Users\luned\Vault\Encephalon-Mageia"
git add wiki/
git commit -m "ingest: [source title]"

# WSL
cd /mnt/c/Users/luned/Vault/Encephalon-Mageia
git add wiki/
git commit -m "ingest: [source title]"
```

A single source can trigger updates across 5-15 wiki pages. This is normal
and desired — it's the compounding effect.

### 2. Query

When the user asks a question about the wiki's domain:

① **Prefer semantic search via `ws`** — The wiki-search script is at:
   - Windows: `python3 "%APPDATA%\Local\hermes\skills\research\llm-wiki\scripts\wiki-search.py"`
   - WSL: `ws` CLI (symlinked from `~/.hermes/scripts/wiki-search.py`)
   ```bash
   ws search "query" -n 5
   ws ingest              # Re-index after any wiki changes
   ws status              # Check bank health + ingestion state
   ```
   This uses Hindsight's built-in embeddings (mimir-well bank) for semantic recall — finds conceptually related content even without exact keyword matches.

② **Fall back to `search_files`** — For exact keyword lookups, file name searches, or when Hindsight is not running:
   ```bash
   search_files "keyword" path="$WIKI" file_glob="*.md"
   ```

③ **Read `index.md`** to identify relevant pages for the topic.

④ **Read the relevant pages** using `read_file`.

⑤ **Synthesize an answer** from the compiled knowledge. Cite the wiki pages
   you drew from: "Based on [[page-a]] and [[page-b]]..."

⑥ **File valuable answers back** — if the answer is a substantial comparison,
   deep dive, or novel synthesis, create a page in `queries/` or `comparisons/`.
   Don't file trivial lookups — only answers that would be painful to re-derive.

⑦ **Update log.md** with the query and whether it was filed.

### 3. Lint

When the user asks to lint, health-check, or audit the wiki:

① **Orphan pages:** Find pages with no inbound `[[wikilinks]]` from other pages.
② **Broken wikilinks:** Find `[[links]]` that point to pages that don't exist.
③ **Index completeness:** Every wiki page should appear in `index.md`.
④ **Frontmatter validation:** Every wiki page must have all required fields.
⑤ **Stale content:** Pages whose `updated` date is >90 days older than the most recent source.
⑥ **Contradictions:** Pages on the same topic with conflicting claims.
⑦ **Quality signals:** Pages with `confidence: low` or single-source claims without confidence field.
⑧ **Source drift:** Recompute sha256 for raw files and flag mismatches.
⑨ **Page size:** Flag pages over 200 lines.
⑩ **Tag audit:** List all tags in use, flag any not in the SCHEMA.md taxonomy.
⑪ **Log rotation:** If log.md exceeds 500 entries, rotate it.
⑫ **Report findings** with specific file paths, grouped by severity.
⑬ **Append to log.md:** `## [YYYY-MM-DD] lint | N issues found`

## Working with the Wiki

### Searching

```bash
# Semantic search (preferred for conceptual queries)
ws search "query" -n 5

# Keyword search (for exact lookups)
search_files "transformer" path="$WIKI" file_glob="*.md"
search_files "*.md" target="files" path="$WIKI"

# Read wiki log
read_file "$WIKI/log.md" offset=<last 20 lines>
```

### Bulk Ingest

When ingesting multiple sources at once, batch the updates:
1. Read all sources first
2. Identify all entities and concepts across all sources
3. Check existing pages for all of them (one search pass, not N)
4. Create/update pages in one pass
5. Update index.md once at the end
6. Write a single log entry covering the batch

### Archiving

When content is fully superseded:
1. Create `_archive/` directory if it doesn't exist
2. Move the page to `_archive/` with its original path
3. Remove from `index.md`
4. Update any pages that linked to it
5. Log the archive action

### Obsidian Integration

The wiki directory works as an Obsidian vault out of the box:
- `[[wikilinks]]` render as clickable links
- Graph View visualizes the knowledge network
- YAML frontmatter powers Dataview queries

### Semantic Search via Hindsight

If Hindsight API is running locally (default: `http://127.0.0.1:8888`), it can serve as a semantic search backend for the wiki — no separate embedding model needed. Hindsight's recall endpoint handles embedding and vector search internally.

**Setup:**
1. Create a dedicated bank: use an existing empty bank (e.g., `mimir-well`) or create a new one
2. Ingest wiki pages via the `memories` JSON endpoint (see pitfall below about `files/retain`)
3. Search via the recall endpoint

**Reference implementation:** `wiki-search.py` script:
- Windows: `python3 "%APPDATA%\Local\hermes\skills\research\llm-wiki\scripts\wiki-search.py"`
- WSL: `ws` CLI (symlinked from `~/.hermes/scripts/wiki-search.py`)
- `ws ingest` — reads all wiki `.md` files, submits to Hindsight via JSON memories endpoint, tracks file hashes for incremental updates
- `ws search "query"` — semantic search returning ranked results with source file paths
- `ws status` — shows ingestion state and bank stats

**Advantages over keyword search (`search_files` / ripgrep):**
- Finds conceptually related content even without exact keyword matches
- Returns ranked results by semantic relevance
- No local embedding model or API costs required (uses Hindsight's built-in embeddings)

**Limitations:**
- Requires Hindsight API to be running
- Index is not real-time; re-ingest after wiki updates
- Recall quality depends on Hindsight's embedding model

## Pitfalls

- **Never modify files in `raw/`** — sources are immutable. Corrections go in wiki pages.
- **Always orient first** — read SCHEMA + index + recent log before any operation in a new session.
  Skipping this causes duplicates and missed cross-references.
- **Always update index.md and log.md** — skipping this makes the wiki degrade.
- **Don't create pages for passing mentions** — follow the Page Thresholds in SCHEMA.md.
- **Don't create pages without cross-references** — every page must link to at least 2 other pages.
- **Frontmatter is required** — it enables search, filtering, and staleness detection.
- **Tags must come from the taxonomy** — add new tags to SCHEMA.md first, then use them.
- **Keep pages scannable** — split pages over 200 lines.
- **Ask before mass-updating** — if an ingest would touch 10+ existing pages, confirm scope first.
- **Rotate the log** — when log.md exceeds 500 entries, rename it `log-YYYY.md` and start fresh.
- **Handle contradictions explicitly** — note both claims with dates, mark in frontmatter.
- **Always use `.md` extension for wiki files** — Obsidian only recognizes `.md` files as notes.
  When renaming, use `mv old new.md` — don't rewrite content.
- **Verify vault path before writing** — don't assume the wiki location. Check the actual path
  against any env var or user instruction. If `$WIKI_PATH` is unset and `~/wiki` doesn't exist,
  ask the user where the wiki should be, or offer to create it. Don't silently fail or fall back
  to `web_extract`-only summarization when a wiki ingest was requested.
- **WSL path translation** — In WSL environments, the wiki is often inside the Obsidian vault
  which lives on the Windows filesystem. The path from memory (e.g., `~/Documents/Obsidian/...`)
  may be wrong — the actual path is typically `/mnt/c/Users/<user>/Vault/<VaultName>/wiki/`.
  Always verify by listing the path before reading/writing. If the expected path doesn't exist,
  search `/mnt/` drives or check the `obsidian` skill's vault reference for the confirmed location.
- **Raw source markdown escaping** — When saving raw article content that contains code blocks
  with `***`, `|`, or table-like patterns, these can corrupt surrounding markdown tables or
  frontmatter delimiters. For short code snippets (auth headers, single-line values), use
  inline code (`` `backticks` ``) instead of fenced code blocks. For longer blocks, ensure
  the closing ``` is on its own line with no trailing content, and verify the file renders
  correctly after writing by re-reading it immediately.
- **Don't create `CLAUDE.md` or other skill artifacts in the wiki tree** — skill loading can
  auto-generate files in the current directory. Delete them immediately.
- **Hindsight `recall_types` filters recall, not retention** — setting `recall_types:
  ["observation"]` in `~/.hermes/hindsight/config.json` only filters what gets injected
  into context. All four memory types (world/experience/opinion/observation) are still stored.
  This is a safe first fix for memory bloat — data isn't lost, just filtered at recall time.
  See `references/hindsight-memory-bloat.md` for the full diagnostics runbook.

- **Check for relevant skills before using generic tools** — When the user provides a URL or asks to ingest content, always scan available skills first (via skills_list or skill_view) to check for a skill that handles that content type (e.g., youtube-content for YouTube URLs). Using generic tools like web_extract directly when a specialized skill exists means missing steps like transcript fetching, proper formatting, or structured output. The skill may encode the user's preferred approach, conventions, and quality standards — load it even for tasks you think you can handle with basic tools.

- **web_extract truncation fallback** — `web_extract` caps pages at ~5000 chars and silently truncates with `... summary truncated for context management ...`. When this happens, do NOT proceed with truncated content. Fallback: `browser_navigate(url)` → `browser_console(expression="document.querySelector('main')?.innerText || document.querySelector('article')?.innerText || 'not found'")` to get the full text. This is faster and cheaper than retrying web_extract. Verify completeness by checking the article's headings are all present.

- **web_extract non-article fallback** — `web_extract` can return non-article content: modal pages, ad walls, reCAPTCHA challenges, login prompts, or paywalled stubs (especially with share.google.com shortlinks that redirect). Detect this by checking if the extracted content contains article body text vs. modal/ad chrome (look for "reCAPTCHA", "Sign In", "Subscribe", video player chrome, or absence of actual article prose). When detected, **fastest fix:** use `web_search` with the article title (or `site:domain.com "article title"`) to find the canonical URL, then `web_extract` the canonical URL directly. This avoids `browser_navigate` overhead and works for most paywalled or redirect-heavy sources. Only fall back to `browser_navigate` → `browser_console` if `web_search` can't locate the canonical URL (e.g., very new or niche content). Verify the extracted text includes the article's expected headings before saving to raw/.

- **share.google.com shortlinks** — `web_extract` on `share.google.com/<id>` URLs redirects to a different domain based on the source (Yahoo Tech, Android Police, MakeUseOf, etc.). These redirects often land on JS-heavy or video-first pages that `web_extract` can't parse. **Always `web_search` the article title** to get the canonical source URL before attempting extraction.

- **Re-ingest duplicate detection** — Before extracting a URL, always check if a raw file for it already exists in `raw/articles/` (or `raw/papers/`, `raw/transcripts/`). List the directory first. If a file exists with today's `ingested` date and non-empty body, skip re-extraction entirely — reuse the existing file. This is critical for batch ingests where the same URL may appear multiple times across sessions, or when the user resends links that were already processed. Re-extracting wastes time and can create duplicate raw files with different hashes for identical content.

- **index.md multi-patch corruption** — When adding multiple new entries to `index.md` (e.g., entity + concept from one ingest), do NOT chain multiple `patch()` calls with `old_string` targets that are close together. Later patches can corrupt earlier ones if line shifts change the match. Instead: read the current `index.md` state first, compose the full new content, and `write_file` the entire file at once. If you must chain patches, re-read `index.md` between each one.

- **log.md partial-read overwrite** — When you need to append to `log.md`, read the FULL file first (no offset/limit). If you only read the tail (e.g., `offset=100`) and then `write_file` the entire file, you will silently truncate all earlier entries. If the file is too large to read in one call, use `patch` to append rather than `write_file` to overwrite. Never `write_file` a file you haven't read in full.

- **log.md repeated-line patching** — Many log entries share the same closing line (e.g., `- Index updated with N pages total`). When using `patch()` to append to the end of log.md, this line will match MULTIPLE times and fail with "Found N matches." Fix: include more surrounding context in `old_string` to make it unique (include the preceding entry title/date line as well), or match the very last entry full closing block with 3-4 lines of context. The safest approach: always include enough surrounding lines so the match is unique.

- **Concurrent subagent wiki corruption** — When multiple subagents (or the main agent + a sibling) write to the same wiki files (`index.md`, `log.md`) in the same turn, they overwrite each other's changes. Symptoms: duplicate entries in index.md, mismatched 'Total pages' count, missing log entries, or `patch()` failures with 'file was modified by sibling subagent' warnings. Prevention: if using `delegate_task` for wiki work, have the child return the page content and let the main agent do ALL index.md/log.md updates sequentially. Never let siblings write directly to shared navigation files. If you see the 'modified by sibling' warning, re-read the file before patching. External edit signal: if the 'Total pages' count or section entry index.md differs from what you read at session start, another process wrote to it - re-read the full index.md before patching.

- **Hindsight `files/retain` requires `markitdown`** — The `files/retain` endpoint needs the `markitdown` Python package installed on the Hindsight server. On Windows installations this is often missing. **Use the `memories` JSON endpoint instead** (`POST /v1/default/banks/{bank_id}/memories`) — it accepts `MemoryItem` objects with raw text `content` and doesn't need any file parser. The wiki-search.py script already uses this endpoint. If you get `400 Parser(s) not available: ['markitdown']`, switch to the JSON memories endpoint.

## Related Tools

- `references/wiki-search-windows.md` — Windows port notes for wiki-search.py: path differences, CLI usage, Hindsight API details, troubleshooting.
- `references/google-antigravity-os.md` — Google Antigravity 2.0 multi-agent OS build: architecture, agent roles, engineering solutions, and the sync vs async agent thesis.
- `references/workos-auth-md-protocol.md` — WorkOS auth.md: open agent registration protocol built on OAuth standards (ID-JAG + OTP flows, two-hop discovery, credential types).
- `references/hindsight-memory-bloat.md` — Diagnostics runbook for Hindsight duplicate memory injection (GitHub issue #21698). Includes root cause chain, the `recall_types: ["observation"]` workaround, full config tuning (recall_max_tokens, recall_budget, retain_every_n_turns), and verification steps.
- `references/hindsight-config-tuning.md` — Quick reference for the optimal Hindsight config to reduce context bloat. One-command apply snippet. Consult when tuning any Hermes+Hindsight setup.

[llm-wiki-compiler](https://github.com/atomicmemory/llm-wiki-compiler) is a Node.js CLI that
compiles sources into a concept wiki with the same Karpathy inspiration. It's Obsidian-compatible,
so users who want a scheduled/CLI-driven compile pipeline can point it at the same vault this
skill maintains. Trade-offs: it owns page generation (replaces the agent's judgment on page
creation) and is tuned for small corpora. Use this skill when you want agent-in-the-loop curation;
use llmwiki when you want batch compile of a source directory.
