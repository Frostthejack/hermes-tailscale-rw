# Patch Tool + Pagination Pitfall

## The Bug

When editing a file with `patch(mode='replace')`, you need to provide `old_string` that uniquely matches the text to replace. If you read the file with `read_file(offset=N, limit=M)` (pagination), you may only see a **partial view** of the file. This causes two failure modes:

### Failure Mode 1: Duplicate declarations
You replace a block (e.g., a `const grouped = ...` loop) with a new version, but the **original block is outside your paginated view** and you don't realize it exists. The patch inserts the new block but the old one remains, causing a "Cannot redeclare block-scoped variable" build error.

### Failure Mode 2: Stale `old_string` match
The `old_string` you provide matches text that appears twice in the file (once in your view, once outside it). The patch replaces the wrong occurrence, or fails with "not unique."

## The Rule

**Before patching a file you read with pagination, verify there are no duplicate declarations or blocks outside your view.**

### Safe workflow:

1. **Search first**: Use `search_files(pattern="const grouped", path="src/")` to find ALL occurrences of the variable/block you're about to replace.
2. **Read the full file** (or at least the relevant sections around each match) to understand the complete picture.
3. **Include enough context** in `old_string` to make it unique — include surrounding comments, function signatures, or adjacent lines that distinguish it from any other block.
4. **After patching**, search again to verify only one instance remains.

### When you can't read the full file:

If the file is too large to read at once, use `search_files` with `output_mode="content"` and `context=5` to see all occurrences with surrounding lines. This gives you the full picture without reading the entire file.

## Real Example

Editing `RosterPanel.tsx` with `read_file(offset=720)`:
- Added a new `const grouped = ...` block at line 743 (using `displayCharacters` for favorites filtering)
- The old `const grouped = ...` block at line 710 (using `characters`) was **outside the paginated view**
- Patch inserted the new block but didn't remove the old one
- Build failed: `Cannot redeclare block-scoped variable 'grouped'`
- Fix: searched for all `const grouped` occurrences, found both, removed the old one

## Related

- `read_file` pagination: use `offset` and `limit` for large files, but be aware you're seeing a partial view
- `search_files` with `output_mode="content"` and `context=N` is your friend for finding all occurrences before patching
