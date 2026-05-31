# Agent Persona v2 — egui Rewrite Plan

> **Created**: 2026-05-16
> **Status**: Planned, kanban board `agent-persona-v2` created with 13 tasks
> **Board**: `~/.hermes/kanban/boards/agent-persona-v2/`

## Why Rewrite?

The Tauri+Svelte architecture (v1) has fundamental limitations:

1. **Browser dependency** — WebKit runtime adds ~10MB, startup latency, and rendering overhead
2. **OS-level click-through is all-or-nothing** — `set_ignore_cursor_events` makes the entire window invisible to mouse. CSS `pointer-events` was a workaround but still requires the browser.
3. **Single-window model** — All pets are DOM elements inside one Tauri window. Can't have per-pet OS-level click-through or per-pet window management.
4. **Separate webhook binary** — `webhook_server.exe` is a separate process spawned by Tauri. Adds complexity and MSI bundling issues.

## New Architecture: Pure Rust egui

| Aspect | v1 (Tauri+Svelte) | v2 (egui) |
|--------|-------------------|-----------|
| Framework | Tauri 2.x + Svelte 5 + WebKit | eframe 0.28+ (egui) |
| Rendering | DOM/CSS via browser | egui Painter API (immediate-mode) |
| Windowing | Single webview window | Per-pet OS windows |
| Click-through | CSS pointer-events (workaround) | WS_EX_TRANSPARENT per-window (native) |
| Webhook server | Separate webhook_server.exe | In-process (same tokio runtime) |
| Binary size | ~15MB + runtime | ~5MB single exe |
| Animations | CSS keyframes | Frame-by-frame egui painting |

## Key Technical Decisions

### Per-Pet OS Windows
Each pet is a separate OS window via eframe, not DOM elements:
- Window style: WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW
- No decorations, borderless, transparent background
- Pet drawn with egui Painter (shapes, text, paths)
- Transparent areas pass mouse events through natively
- Pet body captures mouse for dragging

### Click-Through (Native)
No set_ignore_cursor_events needed — WS_EX_TRANSPARENT makes empty window areas pass mouse events at the OS level. The pet graphic (drawn region) captures clicks via egui's hit testing.

### Cursor Following
- GetCursorPos() each frame via windows-rs
- Lerp pet position toward (cursor + offset)
- follow_speed = 0.04, follow_offset = (40, 40) — pet trails below-right of cursor
- Toggle: tray menu, settings, keyboard (Ctrl+Shift+F), toolbar button

### Webhook Server (In-Process)
- Same Axum routes as v1 (backward compatible with WSL scripts)
- Runs on tokio runtime alongside egui
- Communicates via mpsc channels instead of SSE
- Port: 9191 (default), configurable

### System Tray
- tray-icon crate (Rust native, no browser needed)
- Menu: Show All / Hide All / Follow Cursor / Settings / Quit

## Task Breakdown (agent-persona-v2 board)

### Phase 1: Foundation
- Scaffold egui app with multi-window support
- Adapt webhook server for egui app
- Implement system tray icon and menu

### Phase 2: Pet Rendering & Behavior
- Render pet characters with egui painting API
- Implement cursor-following mode
- Implement autonomous pet wandering

### Phase 3: UI
- Build egui settings panel
- Implement approval popup overlay
- Build toolbar overlay for pet interaction

### Phase 4: Polish & Packaging
- Implement multi-agent pet management
- Implement config file persistence
- Package as Windows single exe installer
- E2E verification

## Dependencies
- eframe 0.28+ — egui application framework
- egui 0.28+ — immediate-mode GUI
- windows-rs — WinAPI for window styles
- tray-icon 0.17+ — system tray
- tokio + axum — webhook server (reuse from v1)
- serde_json — config persistence

## Build Command
cargo build --release --target x86_64-pc-windows-msvc

Same cross-compilation approach as v1 — build from Windows-native path.

## User Requests Addressed
1. Ditch the browser — pure Rust, no WebKit
2. True per-pet click-through — WS_EX_TRANSPARENT per window
3. Cursor following — smooth lerp with configurable offset
4. Single exe — no separate webhook_server.exe
5. Gentle following — 0.04 lerp speed, 40px offset
