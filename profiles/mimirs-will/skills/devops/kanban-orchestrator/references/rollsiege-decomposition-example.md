# RollSiege Kanban Decomposition — Example

How a large project build plan gets decomposed into phased kanban tasks with parent dependencies.

## Pattern

1. Read the project's PRD, build plan, and all supporting documents
2. Group tasks into phases (Foundation → Core → Polish → Post-MVP)
3. Each phase's tasks depend on prior phase's tasks completing
4. Within a phase, tasks can be parallel or sequential depending on dependencies
5. Create Phase 1 tasks first (no parents), let dispatcher pick them up
6. Subsequent phases auto-promote to ready when parents complete

## Key decisions from this session

- Use `--board <slug>` flag before subcommand (not after)
- `boards switch` sets active board; `boards current` confirms
- 54 tasks across 6 phases was the right granularity
- All assigned to `backend-eng` since one person builds full-stack
- Parent dependencies auto-gate phase progression

## RollSiege phases created

Phase 1 (8 tasks): Foundation — project setup, Supabase, Prisma schema, seed data, landing page, dashboard shell, GitHub/Vercel, env vars
Phase 2 (8 tasks): Character System — API routes, roster, cards, banners, field, deploy logic, images
Phase 3 (8 tasks): Session Management — create/join APIs, QR modal, lobby, host controls, presence, routing, reconnect
Phase 4 (14 tasks): Core Gameplay — GameBoard, DiceRoller, HealthEditor, EnergyDisplay, AbilityButton, ActionPanel, 3 game APIs, Realtime, turn order, win check, logs
Phase 5 (7 tasks): Polish & Deploy — responsive, errors, validation, edge cases, polish, E2E, deploy
Phase 6 (9 tasks): Post-MVP — auth, accounts, ability automation, AoE UI, save/resume, digital board, replay, spectator, admin
