# Session Player Persistence Pattern

## Problem

When a user creates or joins a game session on the dashboard, then navigates to the session page (`/sessions/[code]`), the session page needs to identify which player they are. The `SessionContext` state is lost on page navigation.

## Solution

Persist `sessionPlayerId` to `localStorage` keyed by join code:

```ts
// In SessionContext — after createSession / joinSession succeeds
localStorage.setItem(`sessionPlayerId:${sessionData.joinCode}`, data.player.id);
```

On the session page, read it:

```ts
const currentPlayerId = localStorage.getItem(`sessionPlayerId:${joinCode}`);
```

## Auto-Navigation After Create/Join

The dashboard should auto-navigate to the session page after successful create or join:

```ts
// handleCreateSession
const result = await createSession(name);
window.location.href = `/sessions/${result.joinCode}`;

// handleJoinSession
const success = await joinSession(code, displayName);
if (success) {
  window.location.href = `/sessions/${code.toUpperCase()}`;
}
```

Do NOT require the user to manually click "Go to Session" — this was a UX bug where users had to click a button and still got a broken page because `sessionPlayerId` wasn't persisted.

## Two-Tier Character Model Pitfall

RollSiege has two character concepts:

1. **Roster Character** (`Character` table) — the template/blueprint (e.g., "Knight", "Wizard")
2. **Session Character** (`SessionCharacter` table) — a specific instance of a character assigned to a player within a session

**Critical:** The deploy/undeploy APIs (`/api/game/deploy`, `/api/game/undeploy`) expect a `sessionCharacter.id`, NOT a `Character.id`. If you pass a roster character ID, you get "Character not found for this session player".

**Fix pattern:**
```ts
// Step 1: Create session character (idempotent — 409 means already exists)
const createRes = await fetch(`/api/sessions/${joinCode}/characters`, {
  method: "POST",
  body: JSON.stringify({ sessionPlayerId, characterId: rosterChar.id }),
});

// Step 2: Deploy using the sessionCharacter ID
const sessionCharId = createRes.ok
  ? (await createRes.json()).sessionCharacter.id
  : existingDeployed.find(c => c.characterId === rosterChar.id)?.id;

await fetch("/api/game/deploy", {
  method: "POST",
  body: JSON.stringify({ sessionPlayerId, characterId: sessionCharId }),
});
```

**Debugging tip:** When you see "Character not found for this session player" or "Deployed character not found for this session player", check whether the ID being sent is a `Character.id` or a `SessionCharacter.id`. Read the API route to confirm which it expects.
