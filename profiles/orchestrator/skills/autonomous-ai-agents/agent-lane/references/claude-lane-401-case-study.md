# Claude-Lane 401 Troubleshooting — Detailed Case Study

**Date**: 2026-05-23
**Project**: ScreenFox (settings wiring task)
**Symptom**: claude-lane workers fail immediately with HTTP 401 "Missing Authentication header"
**Root cause**: Per-profile credential resolution bug in the Hermes gateway. NOT a key truncation issue.

## Key Findings

- Both claude-lane and agy-lane have identical config structure (model dict, same api_key, same provider settings)
- Both have the full 73-char key `sk-or-...2138` — verified via `xxd` (NOT truncated, NOT masked)
- Gateway restart does NOT fix the issue
- agy-lane workers succeed with the exact same key
- Only major config difference: `disabled_toolsets` (claude-lane has 46, agy-lane has 0) — this should not affect auth
- Model format was tested both as string and dict — 401 occurs in both cases

## What Was Tried

### 1. Checked config.yaml for masked key
The `config.yaml` had `api_key: sk-or-...2138` which looked masked. But `xxd` showed the full 73-char key was actually there — the `...` was terminal display masking, not literal dots.

**Lesson**: Always verify keys with `xxd` or Python raw bytes, never trust `cat`/`grep` output which may be masked by the terminal.

### 2. Tested the key directly with curl
The key works fine via direct HTTP request. The issue is specific to the worker process.

### 3. Compared agy-lane vs claude-lane configs
- Both have the same API key
- Both use dict-format model
- Changed claude-lane from string to dict model format — still 401
- Gateway restarted after config change — still 401

### 4. Restarted the gateway
Gateway restarted with new PID. Workers still get 401.

### 5. Key insight
The same key works from direct Python urllib and agy-lane workers, but NOT from claude-lane workers. This points to a per-profile credential resolution bug in the Hermes gateway that is NOT related to key format, model format, or config structure.

## Workaround
Use agy-lane instead of claude-lane for all tasks when claude-lane exhibits 401s. The two lanes are interchangeable for delegation purposes.

## Open Questions
- Why does the same API key work for agy-lane but not claude-lane with identical config?
- Is there a per-profile credential cache in the gateway that persists across restarts?
- Could recreating the claude-lane profile from scratch (new profile name) fix this?
- Could the 46 disabled toolsets in claude-lane somehow affect credential resolution?
- Does this affect other profiles too, or just claude-lane?
