# Tauri 2 Desktop App — Verification & Launch Patterns

> Reference for verifying Tauri 2 desktop apps built from WSL2 and launched on Windows.

## Build Verification Sequence

After every code change, run this exact sequence before declaring a phase complete:

```bash
# 1. Frontend build (from project root)
npm run build
# Expect: "✓ built in XXXms", 0 errors

# 2. Rust build (from src-tauri — NOT project root)
cd src-tauri && cargo build --target x86_64-pc-windows-gnu --release
# Expect: "Finished `release` profile", 0 errors

# 3. Verify EXE exists
ls -lh target/x86_64-pc-windows-gnu/release/<app>.exe

# 4. Copy to accessible location on Windows
cp target/x86_64-pc-windows-gnu/release/<app>.exe ../<app>.exe

# 5. Launch on Windows
powershell.exe -Command "Start-Process 'C:\\Users\\luned\\Documents\\<project>\\<app>.exe' -PassThru"

# 6. Wait, then verify process is still running
sleep 3
powershell.exe -Command "Get-Process <app> -ErrorAction SilentlyContinue | Format-List Id,ProcessName,WorkingSet64"
# Expect: Process exists, memory ~40-60MB

# 7. Verify window created (use .ps1 file to avoid $ escaping — see below)

# 8. Clean shutdown
powershell.exe -Command "Stop-Process -Id <PID> -Force"
```

## PowerShell Escaping Rules

**Never** pass complex PowerShell with `$()` interpolation directly via `powershell.exe -Command "..."` — the shell strips `$` signs. Instead:
1. Write a `.ps1` file to `/tmp/`
2. Run with `powershell.exe -ExecutionPolicy Bypass -file /tmp/<script>.ps1`

## Process Health Check Template

Save as `/tmp/check_<app>.ps1`:
```powershell
$proc = Get-Process <app> -ErrorAction SilentlyContinue
if ($proc) {
    Write-Host "PID: $($proc.Id)"
    Write-Host "Memory: $([math]::Round($proc.WorkingSet64/1MB,1)) MB"
    Write-Host "Threads: $($proc.Threads.Count)"
    Write-Host "Has window: $($proc.MainWindowHandle -ne 0)"
    Write-Host "Window title: $($proc.MainWindowTitle)"
} else { Write-Host "NOT RUNNING" }
```

## Tauri-Specific Build Gotchas

| Symptom | Cause | Fix |
|---------|-------|-----|
| `could not find Cargo.toml` | Running `cargo build` from project root | `cd src-tauri && cargo build ...` |
| `tray-icon` compile error | Missing feature flag | Add `features = ["tray-icon"]` to tauri dep |
| `Image::from_bytes` not found | Tauri 2 API change | Use `Image::new(&rgba, w, h)` with raw RGBA |
| Permission denied at runtime | Missing capability prefix | Add `core:` prefix to all permissions |
| Window not transparent | Missing CSS | `background-color: transparent` everywhere |
| `maximize()` breaks transparency | DWM treats maximized transparent windows as opaque | Use manual `set_size()` + `set_position()` instead |

## Transparent Window Click-Through — CORRECT Pattern

**Problem:** A Tauri window with `transparent: true` needs clicks to pass through empty space but be captured on interactive elements (pets, buttons).

**Root cause of click-through failure:** Any non-zero alpha background on container elements (e.g., `rgba(0, 0, 0, 0.01)`) causes the webview to register as an OS-level hit target on Windows, preventing `set_ignore_cursor_events(true)` from working. Even `0.01` alpha is enough to break it.

**Correct fix:**
```css
.container {
    /* Fully transparent — no alpha hit target */
    background-color: transparent;
}
```

**Dynamic click-through toggle:** Use `set_ignore_cursor_events(true)` as the default state (click-through ON). Then use a polling loop that checks cursor position against pet bounding boxes. When cursor is over a pet, call `set_ignore_cursor_events(false)` to capture clicks. When cursor moves away, re-enable click-through.

**Bounding-box fallback:** `document.elementFromPoint()` returns `null` when click-through is active (browser engine can't see through its own click-through surface). Use the OS-level mouse position from Tauri's `cursor_position()` API combined with pet positions from the Zustand store to do a bounding-box check instead.

**What NOT to do:**
- Do NOT use `rgba(0, 0, 0, 0.01)` as a "nearly transparent" workaround — it breaks click-through
- Do NOT rely solely on `elementFromPoint` for hit testing — it fails through click-through windows
- Do NOT call `window.maximize()` on transparent windows — it breaks DWM transparency on Windows

## Memory Targets

| Component | Target | Notes |
|-----------|--------|-------|
| Base app (idle) | < 50MB | Tauri webview + React runtime |
| Per additional pet | +3-8MB | Same process, extra React components |
