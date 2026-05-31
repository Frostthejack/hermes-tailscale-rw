# Tauri App — Build from WSL, Deploy to Windows

> **⚠️ DEPRECATED (2026-05-16)**: The Agent Persona project is being rewritten from Tauri+Svelte to pure Rust egui (eframe). This reference is kept for historical context but the Tauri approach is no longer the active architecture. See the egui rewrite plan in the project's kanban board `agent-persona-v2`.

## Pattern: Building a Tauri App on Windows from WSL

Tauri requires a Windows toolchain (MSVC/LLVM) and cannot build in WSL directly. The workflow is:

### 0. Copy Project to Windows-Native Path (CRITICAL)

**Why**: WiX `light.exe` and other Windows tools cannot handle WSL UNC paths (`\\\\wsl.localhost\\...`). Building from a UNC path causes `failed to run light.exe` errors during MSI bundling.

```bash
WIN_TEMP="/mnt/c/Users/$WINUSER/AppData/Local/Temp/my-app-build"
rm -rf "$WIN_TEMP"
mkdir -p "$WIN_TEMP"
rsync -a --exclude=node_modules --exclude=target --exclude=dist \
    /path/to/your/tauri-app/ "$WIN_TEMP/"
# Copy dist separately if already built
cp -r /path/to/your/tauri-app/dist "$WIN_TEMP/" 2>/dev/null
```

### 1. Handle `beforeBuildCommand`

If the frontend is already built (dist/ exists), clear `beforeBuildCommand` in `tauri.conf.json` to avoid npm UNC path issues:

```json
{
  "build": {
    "frontendDist": "../dist",
    "beforeDevCommand": "npm run dev",
    "beforeBuildCommand": ""
  }
}
```

Build the frontend separately from WSL first:
```bash
cd /path/to/your/tauri-app && npm run build
```

### 2. Build from Windows-Native Path

```bash
cd "$WIN_TEMP/src-tauri" && /mnt/c/Users/$WINUSER/.cargo/bin/cargo.exe tauri build --target x86_64-pc-windows-msvc
```

**Target**: Use `x86_64-pc-windows-msvc` (not `x86_64-pc-windows-gnu`). The MSVC target is the standard for Tauri.

### 3. Verify Build Artifacts

```bash
ls "$WIN_TEMP/src-tauri/target/x86_64-pc-windows-msvc/release/" | grep -E "\.exe|bundle"
ls "$WIN_TEMP/src-tauri/target/x86_64-pc-windows-msvc/release/bundle/msi/"
```

Both `app.exe` (Tauri webview app) and `webhook_server.exe` (if applicable) should be present.

### 4. MSI Install

MSI install requires admin rights. Error 1925 = insufficient privileges.

**Silent install (from WSL)**: Write a PowerShell script to avoid `$` variable stripping:

```powershell
# install.ps1
$msiPath = "C:\\Users\\luned\\Desktop\\MyApp_0.1.0_x64_en-US.msi"
$logPath = "C:\\Users\\luned\\AppData\\Local\\Temp\\install.log"
$process = Start-Process -FilePath "msiexec.exe" `
    -ArgumentList "/i", "`"$msiPath`"", "/qn", "/norestart", "/l*v", "`"$logPath`"" `
    -Verb RunAs -Wait -PassThru
Write-Host "Exit code: $($process.ExitCode)"
```

```bash
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\\Users\\luned\\AppData\\Local\\Temp\\install.ps1"
```

### 5. Verify Install and Launch

**Note**: The MSI may only bundle one binary (e.g., `webhook_server.exe` but not `app.exe`). If `app.exe` is missing, manually copy it from the build output to a user-writable directory:

```powershell
$dest = "$env:LOCALAPPDATA\\MyApp"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item "C:\\Users\\luned\\AppData\\Local\\Temp\\my-app-build\\src-tauri\\target\\x86_64-pc-windows-msvc\\release\\app.exe" "$dest\\app.exe"
```

Launch from the user directory (no admin needed):
```powershell
Start-Process -FilePath "$env:LOCALAPPDATA\\MyApp\\app.exe"
Start-Sleep -Seconds 5
Get-Process | Where-Object {$_.ProcessName -match 'myapp|webhook'}
```

### 6. JSON POST Testing

**Do NOT use PowerShell `Invoke-WebRequest` with inline JSON** — escaping is broken. Instead write JSON to temp files and use `curl.exe`:

```powershell
# Write JSON to temp file
'{"agent":"hermes","status":"working","task":"test","profile":"reviewer","timestamp":"2026-01-01T00:00:00"}' |
    Out-File "C:\\Users\\luned\\AppData\\Local\\Temp\\body.json" -Encoding utf8

# Use curl.exe with file reference
curl.exe -s -X POST http://127.0.0.1:9191/webhooks/status `
    -H "Content-Type: application/json" `
    -d "@C:\\Users\\luned\\AppData\\Local\\Temp\\body.json"
```

### Key Pitfalls Summary

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| UNC path in build | `failed to run light.exe` | Copy project to `C:\...` first |
| `beforeBuildCommand` runs npm in UNC context | `npm ERR! enoent: package.json` | Set `beforeBuildCommand: ""` |
| Wrong target | Build succeeds but MSI fails | Use `x86_64-pc-windows-msvc` |
| MSI needs admin | Error 1925 | Use `-Verb RunAs` |
| MSI missing app.exe | Only webhook_server.exe installed | Manually copy app.exe to user dir |
| PowerShell `$` stripping | Variables disappear in `-Command` | Write `.ps1` file, use `-File` |
| PowerShell JSON escaping | 422 Unprocessable Entity | Write JSON to file, use `curl.exe -d @file` |
| `cmd.exe` UNC rejection | `UNC paths are not supported` | Always `cd /d` as first .bat command |
| Port already in use | `only one usage of each socket address` | `taskkill /F /IM exe.exe` first |
| Invoke-WebRequest health check false 500 | Health endpoint works with curl but not IWR | Use `curl.exe` for all API testing |
| Svelte `<main>` tag typo | `element_invalid_closing_tag` build error | Ensure `<main>` not `main>` in template |
| Rust stale function ref | `not found in this scope` after removing import | Remove ALL call sites when removing a function |
| `tauri build` appears hung (background) | No output for 30+ seconds, process looks stuck | Normal — Rust cross-compilation is slow and stdout is buffered. Use `notify_on_complete=true` in background, or run in foreground with `timeout` to see output |
| `beforeBuildCommand` references `pnpm` but project uses `npm` | Build may fail or use wrong package manager | Check `package-lock.json` vs `pnpm-lock.yaml` to determine actual package manager; update `tauri.conf.json` `beforeBuildCommand` to match |
| No `tauri` script in `package.json` | `npm run tauri build` fails with "Missing script" | Use the global `tauri` binary directly (`tauri build`) or `npx tauri build` |
| `cargo check` passes but app never built | All kanban tasks "done" but no `.exe` exists | `cargo check` only verifies compilation; must run `tauri build` to produce a binary. Always verify the binary exists and launches. |

---

## Pattern: Verifying a Tauri App Actually Works

**Critical gap**: `cargo check` passing ≠ a working app. A Tauri app must be fully built and launched to verify it works. All kanban tasks can be "done" while no binary has ever existed.

### Verification Checklist

1. **Build the binary**: `tauri build` (see build pattern above)
2. **Verify binary exists**: Check for `.exe` in `src-tauri/target/release/` or `target/x86_64-pc-windows-msvc/release/`
3. **Launch the binary**: Run the `.exe` on Windows (not WSL)
4. **Verify the window appears**: Screenshot or check process list
5. **Verify frontend loads**: The React/Vite app should render inside the Tauri webview
6. **Verify Rust backend works**: Test any Rust features (webhook server, state management, etc.)
7. **Verify IPC works**: Frontend ↔ Rust communication via Tauri commands/events

### Common Gap: Code Exists But Never Built

If `target/release/` or `target/debug/` has no `.exe`, the app has never been compiled. This is common when:
- Development was done entirely in WSL without Windows toolchain
- `cargo check` was used as a substitute for actual builds
- The project was cloned but never built on the current machine

**Fix**: Run the full `tauri build` workflow (see build pattern above). Expect 5-15 minutes for the first build due to Rust dependency compilation.

---

## Pattern: DaemonCore-Specific Build Notes

**Problem with OS-level approach**: `set_ignore_cursor_events(true)` makes the ENTIRE window invisible to mouse — no toolbar, no settings, no quit. All-or-nothing.

**Solution**: Use CSS `pointer-events` instead.

### How It Works

```css
/* Main container: background passes all mouse events through */
main {
  pointer-events: none;
}

/* Interactive children re-enable mouse events */
:global(main > *) {
  pointer-events: auto;
}
```

The window stays interactive but the transparent background passes clicks through. Individual elements (toolbar, pets, settings, popups) remain fully clickable.

### Window Configuration (`window_manager.rs`)

```rust
pub fn configure_pet_window(window: &WebviewWindow) {
    let _ = window.set_always_on_top(true);
    let _ = window.set_decorations(false);
    let _ = window.set_skip_taskbar(true);
    // ... size/position setup ...
    // NO set_ignore_cursor_events call — CSS handles click-through
}
```

### Key Principles

1. **Never use `set_ignore_cursor_events`** — CSS `pointer-events` gives finer control
2. **Toolbar is always visible** — no show/hide on hover needed
3. **Background is always click-through** — empty space passes clicks to windows below
5. **Remove OS-level click-through commands entirely** — `toggle_click_through`, `get_click_through`, `CLICK_THROUGH` atomic, `toggle_click_through_window` function

### Tray Menu (Simplified)

With CSS click-through, the tray only needs:
- Show All Pets / Hide All Pets
- Follow Cursor (toggle)
- Settings...
- Quit

No click-through toggle needed — it's always "on" for the background.

---

## Pattern: Cursor Following for Desktop Pets

### PetWindow.svelte

```svelte
<script>
  export let followCursor = false;
  let cursorX = 0, cursorY = 0;
  let followOffset = { x: 40, y: 40 }; // pet trails below-right of cursor

  function onGlobalMouseMove(e) {
    cursorX = e.clientX;
    cursorY = e.clientY;
  }

  // In the animation tick function:
  // if (followCursor) → target = cursor + offset
  // else → target = wanderTarget
  // followSpeed = 0.04 (faster than wanderSpeed = 0.006)

  onMount(() => {
    window.addEventListener('mousemove', onGlobalMouseMove);
    startWandering();
  });
  onDestroy(() => {
    window.removeEventListener('mousemove', onGlobalMouseMove);
  });
</script>
```

### Toggle Methods

1. Toolbar button (🎯, highlighted when active)
2. Keyboard shortcut (`Ctrl+Shift+F`)
3. Tray menu ("Follow Cursor")
4. Settings panel checkbox

### Settings Store

```javascript
const defaultSettings = {
  followCursor: false,
  // ... other settings ...
};
```

---

## Pattern: Click-Through UX for Desktop Overlay Apps

**Problem**: Tauri apps with `set_ignore_cursor_events(true)` (click-through) make the entire window invisible to mouse interaction. If click-through is ON at launch, users can't interact with any UI — toolbar, settings, or quit button. The app becomes "stuck" with no way to close it.

**Solution**: Start with click-through OFF and provide multiple toggle mechanisms.

### Architecture

```
+---------------------------------------------+
|  Click-Through State (starts OFF)           |
|                                             |
|  Toggle methods:                            |
|  1. Toolbar button                          |
|  2. Keyboard shortcut (Ctrl+Shift+X)        |
|  3. Tray menu item                          |
|                                             |
|  Toolbar visibility:                        |
|  - Default: visible (opacity: 1)            |
|  - Click-through ON: hidden (opacity: 0)    |
|  - Hover when hidden: visible (opacity: 1)  |
+---------------------------------------------+
```

### Rust Backend (`lib.rs`)

Track click-through state with an atomic:

```rust
use std::sync::atomic::{AtomicBool, Ordering};
static CLICK_THROUGH: AtomicBool = AtomicBool::new(false);

#[tauri::command]
fn toggle_click_through(window: tauri::WebviewWindow, enabled: bool) {
    let _ = window.set_ignore_cursor_events(enabled);
    CLICK_THROUGH.store(enabled, Ordering::Relaxed);
}

#[tauri::command]
fn get_click_through() -> bool {
    CLICK_THROUGH.load(Ordering::Relaxed)
}

#[tauri::command]
fn quit_app(app: tauri::AppHandle) {
    app.exit(0);
}
```

### Window Configuration (`window_manager.rs`)

```rust
pub fn configure_pet_window(window: &WebviewWindow) {
    // ... other setup ...
    // Start with click-through OFF
    let _ = window.set_ignore_cursor_events(false);
}
```

### Tray Menu (`tray.rs`)

Add toggle and quit items:

```rust
let toggle_click = MenuItem::with_id(app, "tray_toggle_click", "Enable Click-Through", true, None::<&str>)?;
let quit = MenuItem::with_id(app, "tray_quit", "Quit", true, None::<&str>)?;
Menu::with_items(app, &[&show_all, &hide_all, &settings, &toggle_click, &quit])
```

Handle the toggle event by emitting to frontend:

```rust
"tray_toggle_click" => {
    let _ = app.emit("tray:toggle-click-through", ());
}
```

### Frontend (`App.svelte`)

```svelte
<script>
  let clickThrough = false;

  // Tray toggle
  listen('tray:toggle-click-through', async () => {
    const { invoke } = await import('@tauri-apps/api/core');
    const current = await invoke('get_click_through');
    const newState = !current;
    await invoke('toggle_click_through', { enabled: newState });
    clickThrough = newState;
  });

  // Keyboard shortcut
  window.addEventListener('keydown', async (e) => {
    if (e.ctrlKey && e.shiftKey && e.key === 'X') {
      e.preventDefault();
      const { invoke } = await import('@tauri-apps/api/core');
      const current = await invoke('get_click_through');
      const newState = !current;
      await invoke('toggle_click_through', { enabled: newState });
      clickThrough = newState;
    }
    if (e.ctrlKey && e.shiftKey && e.key === 'Q') {
      e.preventDefault();
      const { invoke } = await import('@tauri-apps/api/core');
      await invoke('quit_app');
    }
  });
</script>

<div class="toolbar" class:click-through={clickThrough}>
  <button on:click={() => settingsVisible = true}>Settings</button>
  <button on:click={async () => { /* toggle */ }}>Toggle Click-Through</button>
  <button on:click={async () => { /* quit */ }}>Quit</button>
</div>

<style>
  .toolbar { opacity: 1; }
  .toolbar.click-through { opacity: 0; pointer-events: none; }
  .toolbar:hover { opacity: 1 !important; }
</style>
```

### Key Principles

1. **Start with click-through OFF** — users must be able to interact with the app on first launch
2. **Provide at least 3 toggle methods** — toolbar button, keyboard shortcut, tray menu
3. **Always provide a quit method** — tray quit button + keyboard shortcut (Ctrl+Shift+Q)
4. **Toolbar auto-hides when click-through is on** — but reappears on hover so users can disable it
5. **Track state in both Rust and frontend** — Rust atomic for the actual window state, frontend reactive variable for UI
