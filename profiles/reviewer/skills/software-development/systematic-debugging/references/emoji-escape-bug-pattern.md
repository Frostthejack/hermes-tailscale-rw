# Emoji Escape Bug Pattern — Next.js/React

## Symptom
Emoji characters render as literal Unicode escape strings in the browser:
- `\uD83C\uDFB2` instead of 🎲
- `\u2694\uFE0F` instead of ⚔️
- `\uD83C\uDF10` instead of 🌐

## Root Cause
The emoji got JSON-escaped (`\uXXXX`) somewhere in the data pipeline and is being rendered as a literal string instead of being decoded back to UTF-8 before rendering to HTML.

## Common Causes
1. **Data file serialization** — Emoji stored in a JSON/TS config file got escaped during write, and the file is served as raw text rather than being parsed as UTF-8
2. **API double-encoding** — An API response JSON-encodes emoji in a string field, and the frontend renders the escaped string without decoding
3. **Database encoding mismatch** — Data was inserted with escape sequences instead of actual UTF-8 bytes
4. **Build-time transformation** — A build step (Babel plugin, webpack loader, etc.) converts emoji to escape sequences

## Diagnosis
1. View page source (Ctrl+U) — if you see `\uD83C\uDFB2` in the HTML, the data itself contains the escape string
2. Check the API response — if the API returns `"\\uD83C\\uDFB2"` (double-escaped), the backend is the source
3. Check the data file — open the source file and look for `\uXXXX` instead of the actual emoji character

## Fix
Replace the `\uXXXX` strings in the source with the actual emoji characters. In most cases this means:
- Open the component or data file
- Replace `\uD83C\uDFB2` with 🎲 (paste the actual emoji)
- Ensure the file is saved as UTF-8

## Real-World Example
**Project:** RollSiege (Next.js 15 + Vercel)
**File:** Landing page component (`src/app/page.tsx` or similar)
**Bug:** Three feature cards had emoji stored as `\uXXXX` escape strings
**Fix:** Replaced escape strings with actual emoji characters in the component source
