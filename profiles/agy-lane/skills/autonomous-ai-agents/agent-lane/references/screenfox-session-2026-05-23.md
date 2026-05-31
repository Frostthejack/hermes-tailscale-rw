# Agent Lane — ScreenFox Session Learnings (2026-05-23)

## Infinite Loop Case Study: Task 1.1 (Tauri Deps Setup)

Task t_ff93ee0e got stuck in a 159+ cycle infinite loop. Workers either crashed immediately or exited cleanly without calling kanban_complete.

Event pattern: claim → spawn → crashed/protocol_violation → gave_up → promoted → claim → ...

Root cause: environment-dependent task (Rust/cross-comp deps), workers couldn't complete it. Dispatcher has no circuit breaker.

Fix: kill worker PID, reset task in SQLite, change approach or do directly.

Lesson: If a task fails 3+ times with same error, CHANGE THE APPROACH. Don't let dispatcher retry indefinitely.

## Claude-Lane 401: Truncated API Key

claude-lane workers fail with HTTP 401. Authorization header contains truncated key: "Bearer sk-or-v1...2138" (literal dots, 15 chars).

Root cause: credential resolution chain masks/truncates the API key before sending.

Fix: hermes gateway restart, or dispatch to agy-lane as workaround.

## Phase 1 Success Pattern

Tasks 1.2-1.7 completed via agent lanes (agy-lane and claude-lane). Key success factors: well-scoped tasks, clear acceptance criteria, print mode (-p) for bounded tasks, clear verification commands.

## Orchestrator Violations

Initial scaffold and Tauri deps setup done by Hermes directly. Rule: when a kanban board exists, ALL coding must go through agent lanes.
