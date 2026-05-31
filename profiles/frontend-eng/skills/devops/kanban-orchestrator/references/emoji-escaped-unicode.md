# Emoji Rendering as Escaped Unicode Strings

## Problem
Emoji characters on the landing page render as literal Unicode escape strings (e.g., `\uD83C\uDFB2`) instead of actual emoji (🎲).

## Root Cause
The emoji characters are being JSON-escaped somewhere in the data pipeline and then rendered as text instead of being decoded back to Unicode before rendering to HTML.

## How to Diagnose
1. View page source — if you see `\uXXXX` strings instead of actual emoji characters, the data is being double-escaped
2. Check if emoji are stored in a config/data file as JSON escape sequences
3. Check if any API response is double-encoding the characters

## Fix
- Replace `\uXXXX` strings in source data with actual emoji characters
- Ensure the data pipeline doesn't JSON-encode already-encoded strings
- If using a data file, make sure it's UTF-8 encoded and contains actual emoji

## Affected Components
- Landing page feature cards (Roll to Act, Tactical Combat, Real-Time Multiplayer)
