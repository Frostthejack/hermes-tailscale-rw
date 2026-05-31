---
name: tauri-desktop-apps
description: Build, debug, and deploy Tauri 2 desktop applications — cross-compilation from WSL, window configuration, system tray menus, transparent windows, and common pitfalls. Load when working on any Tauri project.
---

# Tauri 2 Desktop App Development

## Build & Cross-Compilation

### Building from WSL for Windows
- Use `tauri build -v` (verbose) — the build takes 3+ minutes and produces zero output without `-v`, making it appear hung
- Cross-compilation target: `x86_64-pc-windows-gnu` (requires `mingw-w64` installed on WSL)
- The bundling step (WiX installer) will fail on WSL — this is expected. The `.exe` binary is still produced at `src-tauri/target/x86_64-pc-windows-gnu/release/`
- Install target: `rustup target add x86_64-pc-windows-gnu`
- Frontend builds via `pnpm build` or `npm run build` depending on what the project uses — check `tauri.conf.json` `beforeBuildCommand`

### Launching the Built Binary from WSL
- WSL can't directly `.exe` files with `&` backgrounding in foreground terminal mode
- Use `powershell.exe -Command "Start-Process 'C:\path\to\app.exe' -WindowStyle Normal"` to launch on Windows host
- Verify with `powershell.exe -Command "Get-Process <name> -ErrorAction SilentlyContinue"`

## Window Configuration

### Transparent Windows & Click-Through
- Tauri windows with `transparent: true` and CSS `background-color: transparent` pass all mouse events through to windows behind
- **Fix**: Use `background-color: rgba(0, 0, 0, 0.01)` on the container — nearly invisible but captures mouse events
- For selective click-through (e.g., only the pet character should be clickable), use `set_ignore_cursor_events` Rust command + frontend `mousemove` listener that checks `document.elementFromPoint()`
- The `pointer-events: auto` CSS property on interactive elements (buttons) ensures they remain clickable even on transparent backgrounds

### Full-Monitor Overlay
- In `lib.rs` setup: use `window.primary_monitor()` to get monitor size, then `window.set_size(*size)` and `window.set_position(PhysicalPosition::new(monitor.position().x, monitor.position().y))`
- Window config: `decorations: false`, `alwaysOnTop: true`, `resizable: false` for overlay-style apps

## System Tray Menus (Tauri v2)

### MenuBuilder API
- `MenuBuilder` has `.item()`, `.items()`, and `.separator()` — **NOT** `.append()`
- `.append()` exists on the built `Menu` and `Submenu` types, not on `MenuBuilder`
- Use `.separator()` directly on the builder: `MenuBuilder::new(app).item(&a).separator().item(&b).build()?`
- `CheckMenuItemBuilder` for toggle items: `.checked(true/false)`
- `MenuItemBuilder::with_id(id, text)` for regular items
- `PredefinedMenuItem::separator(app)?` creates a separator but can only be used with `.append()` on built menus, not on `MenuBuilder`

### Tray Icon
- Create from raw RGBA bytes: `Image::new(&rgba_bytes, width, height)`
- Build in `setup()` hook: `TrayIconBuilder::with_id("main").icon(icon).menu(&menu).on_menu_event(handler).build(app)?`
- Emit events from tray handler: `app.emit("tray_event", "action_id").unwrap_or_default()`
- Frontend listens: `listen<string>("tray_event", (event) => { ... })`

### Tray Menu Pattern for Settings Apps
- Group related items with separators
- Use checkable items for toggles (Show Pet, Sounds, Follow Mouse)
- Use checkable items with distinct IDs for radio-style selections (Theme: Midnight/Peach/Cloud/Moss, Size: Small/Medium/Large)
- Include a "Quit" item with accelerator `CmdOrCtrl+Q`

## Cross-Compilation from WSL to Windows

### Resource.lib Permission Error

**Symptom**: `tauri build` fails with `Permission denied (os error 13)` on `resource.lib`.

**Root Cause**: Tauri build script creates `resource.lib` on Windows filesystem (`/mnt/c/`) via 9p bridge. Linker can't read it.

**Fix**: Build on Linux filesystem, copy back:
```bash
cd src-tauri
CARGO_TARGET_DIR=/tmp/daemoncore-target cargo build --release --target x86_64-pc-windows-gnu
cp /tmp/.../daemoncore.exe /mnt/c/Users/.../target/.../release/
```

**Cleanup**: `rm -rf /mnt/c/.../target/.../build/daemoncore-*`

### Delegate Task Timeout

600s default is too short for Tauri builds (3-5+ min). Run build commands directly or use `background=true` + `notify_on_complete=true`.

### Window Maximizing

Use `window.maximize()`. Remove fixed `width`/`height` from `tauri.conf.json`.

## Common Pitfalls

### Tray Menu Handlers Must Call Backend Functions — No-Ops Cause Review Loops

**Pattern**: Tauri tray menu items with `// TODO` handlers that don't call the backend function. The frontend may create the window correctly, but the tray menu item does nothing when clicked.

**Example**: `src-tauri/src/tray.rs` line 87-89 — the `"settings"` match arm has only a TODO comment. The `settings::create_settings_window(app)` function exists and works, but is never called from the tray event handler. This causes reviewers to block repeatedly (65+ hours in one case) while the fix task enters a crash loop trying to fix a one-liner.

**Fix**: Always ensure tray menu handlers call the actual backend function. The pattern:
```rust
"settings" => {
    settings::create_settings_window(app);  // NOT just a TODO comment
}
```

**Kanban impact**: If a tray-related task gets blocked in review, the fix is usually a one-liner. Don't let it enter a crash loop — check if the worker is actually making changes or just re-reading code.

### Rust Compilation
- `MenuBuilder::append()` → use `.separator()` or `.item()` instead
- `macos-private-api` feature in `Cargo.toml` causes issues on Windows-only apps — remove if not needed
- `Cargo.toml` line endings: git may convert CRLF↔LF; use `git checkout -- Cargo.toml` to revert if it shows as modified with no real changes

### Frontend
- Remove unused imports — `tsc --noEmit` (used by `pnpm build`) fails on unused imports with `error TS6133`
- When removing React components, also remove their CSS classes from `App.css` to keep the bundle clean

### Webhook Server Integration
- Axum server runs in `tauri::async_runtime::spawn()` inside a `.setup()` hook
- Emit events from webhook handlers: `app.emit("event_name", payload)` — frontend listens with `listen()`
- Port should be a `const WEBHOOK_PORT: u16 = <port>;` in `lib.rs`, not hardcoded in multiple places

### Eye Tracking Through Click-Through

When `set_ignore_cursor_events(true)` blocks webview mouse events, track from Rust:
```rust
fn start_mouse_tracker(app_handle: tauri::AppHandle) {
    tauri::async_runtime::spawn(async move {
        loop {
            if let Ok(pos) = app_handle.cursor_position() {
                let _ = app_handle.emit("mouse_position", (client_x, client_y));
            }
            tokio::time::sleep(Duration::from_millis(16)).await;
        }
    });
}
```
Frontend: `listen<[number, number]>("mouse_position", callback)`

### Container Background

`rgba(0,0,0,0.01)` captures mouse events. `transparent` causes click-through on Windows.
