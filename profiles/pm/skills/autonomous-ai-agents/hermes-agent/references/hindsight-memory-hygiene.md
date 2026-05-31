# Hindsight Memory Bank Hygiene

## Problem

The Hindsight bank (`hermes`) accumulates duplicate, stale, and overspecific entries that bloat context and degrade recall quality. As of May 2026, common symptoms:

- Same fact stored 3-10+ times (e.g., `HINDSIGHT_API_RECALL_CONNECTION_BUDGET is 4` appears 5 times)
- Bulk-ingested reference docs (50+ config var entries) fire on every Hindsight-related query
- Stale resolved-debugging memories (e.g., BookReader TTS from April 27-28) surface repeatedly
- Recall returns 67+ memories totaling 15,000-20,000+ chars on a `mid` budget

## Root Cause

- `hindsight_retain` with `document_id` upserts but does NOT delete old entries with different IDs
- No delete/update API exists in Hindsight for removing specific memories
- `mid` recall budget is too generous for a bank full of duplicates
- Reference documentation was ingested one-fact-per-entry instead of as single consolidated summaries

## Immediate Remediation

### 1. Consolidate Canonical Entries

For each topic cluster that has N duplicates, retain ONE clean entry. Key clusters:
- All `HINDSIGHT_API_*` config vars -> single consolidated entry
- All BookReader TTS debugging -> remove entirely (resolved)
- All subagent isolation facts -> single entry
- All WSL networking facts -> refer to wsl-cross-platform-networking skill

### 2. Tune Recall Budget

Lower from `mid` to `low` for everyday tasks. Use `mid` only for deep research.

### 3. Disable Include Chunks

Set `HINDSIGHT_API_RECALL_INCLUDE_CHUNKS=false` to skip raw chunk text and save ~1000 tokens per recall.

### 4. Stop Bulk Doc Ingestion

Store single concise summaries of reference docs, not fact-by-fact entries.

## Deduplication Attempt Log

- **2026-05-07**: 20x `hindsight_retain` with `document_id` failed to remove old duplicates. Only created new entries alongside old ones.
- **Conclusion**: True dedup awaits a delete API. Mitigate via canonical entries + low budget + no chunks.
