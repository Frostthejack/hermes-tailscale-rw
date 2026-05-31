# Agent Persona — Decomposition Example & Bug Fix Log

20 tasks, 5 phases. Created 2026-05-13 for the Agent Persona screen pet project.
Bug fix cycle added 2026-05-15 (4 bugs, 5 new tasks).

## Phase Structure

| Phase | Tasks | Focus | Dependencies |
|-------|-------|-------|-------------|
| 1 — Foundation | T1–T5 | Toolchain, scaffolding, webhook server, window, store | None (starts immediately) |
| 2 — Core Features | T6–T9 | Animations, multi-pet, tray, approval popup | Phase 1 tasks |
| 3 — Hermes Integration | T10–T12 | WSL emitter scripts, poller, approval response | Phase 1 webhook server |
| 4 — Polish | T13–T16 | Settings, sounds, character art, interactions | Phase 2 tasks |
| 5 — Testing & Packaging | T17–T20 | E2E test, .msi package, docs, perf | Phases 2–4 |

## Key Patterns

**Verification on every task.** Each task body includes a `VERIFICATION:` section with numbered steps, exact commands to run, expected outputs, and error case handling. This is the standard for all future project boards.

**Rich task bodies.** Each task body includes:
- Numbered implementation steps with exact commands
- File paths and code structure
- `VERIFICATION:` section with specific test steps
- Error case handling

**Dependency gating.** Phase 1 tasks have no parents (start immediately). All subsequent tasks have parents that must complete first.

## Bug Fix Cycle (2026-05-15)

After the initial 20/20 tasks completed, the user reported 4 bugs. Investigation found:

### Bug 1: Hermes Not Connecting
- **Root cause:** Port mismatch — `agent-persona-emit.sh` defaults to 8080, `webhook_server.rs` binary defaults to 9191
- **Fix task:** t_bfc168a6 (ops) — Align ports, make configurable via settings UI, add connection status indicator

### Bug 2: Settings Tray Does Nothing
- **Root cause:** `tray.rs` emits `"tray:open-settings"` event (line 128) but `App.svelte` never listens for it. Settings panel visibility is only toggled by the toolbar button.
- **Fix task:** t_dcc52a83 (frontend-eng) — Add Tauri event listener in App.svelte for `tray:open-settings`, also wire up `tray:show-all` and `tray:hide-all`

### Bug 3: Stationary Pet
- **Root cause:** `PetWindow.svelte` only renders static emoji (🐾/🤔) with a simple pulse CSS animation. No walking, no state-based animations, no character art per agent.
- **Fix task:** t_e20d2fc5 (frontend-eng) — Add animated SVG/CSS characters per agent, state-based animations (idle float, working bounce, approval shake, error/success), autonomous wandering movement

### Bug 4: Windowed Display (Not Free-Floating)
- **Root cause:** `tauri.conf.json` defines a single 400x300px window. `configure_pet_window()` removes decorations but it's still a bounded window. Pet DOM elements are confined within it.
- **Fix task:** t_5ceac5f6 (backend-eng) — Rework to per-pet undecorated windows or full-screen transparent overlay with click-through

### E2E Verification
- **Fix task:** t_dfefeb13 (reviewer) — Depends on all 4 fixes above. Full Windows testing.

## Lessons Learned

1. **"Done" ≠ verified.** All 20 tasks were marked done but the app had 4 user-facing bugs. Always independently verify.
2. **Tauri Windows GUI subsystem kills threads.** Use separate processes, not threads.
3. **Port conflicts are real.** Always test port availability on the target OS before hardcoding.
4. **Separate binaries must be in the same directory** as the main exe when spawning from Tauri.
5. **Cross-compiled binaries end up in `target/<target-triple>/release/`**, not `target/release/`.
6. **Ports should be settings, not hardcoded.** User preference: any configurable value (especially ports) should be in the settings UI so users can change it without rebuilding. This is critical for sharing the app with others who may have different port conflicts.
7. **Windows Firewall can Block by exe, not just by port.** Even if your app listens correctly, a program-specific Block rule prevents all inbound access. Check with `netsh advfirewall firewall show rule name=all | findstr /i yourapp`.
8. **Stale binary trap.** The source code may be correct but the deployed binary could be from a previous build. Always rebuild and redeploy after source changes.
9. **Tauri tray events need frontend listeners.** The Rust tray can emit events via `app.emit()`, but the Svelte frontend must explicitly listen via `listen()` or `onMount`. Emitting without listening = silent failure. Always verify the full chain: tray menu → emit → frontend listener → UI update.
10. **Tauri window architecture matters for desktop widgets.** A single decorated/undecorated window is NOT the same as a free-floating desktop pet. For true overlay behavior: use multi-window API (one window per pet), or a full-screen transparent overlay with click-through. The `decorations: false` + `alwaysOn_top: true` approach still bounds content to a rectangular window.
11. **Static emoji ≠ animated pet.** Rendering emoji characters with CSS is not animation. Real pet behavior requires: state-based visual changes, autonomous movement, and drag interaction. Plan animation complexity accordingly when estimating tasks.
12. **Character quality bar is high.** The user explicitly rejected both plain emoji AND simple SVG shapes. Virtual pets must be detailed, recognizable creatures (owls with ear tufts and feather detail, foxes with bushy tails, pixies as glowing particle clusters) with personality animations (breathing, blinking, tail flicks, head tilts). When creating character art tasks, reference `references/creative-asset-quality.md` for the full quality specification.
