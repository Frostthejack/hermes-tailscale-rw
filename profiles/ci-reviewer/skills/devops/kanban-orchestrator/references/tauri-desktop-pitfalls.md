# Tauri Desktop App — Common Pitfalls & Patterns

## Window Architecture

### Single Window vs Free-Floating Widgets
- **Pitfall:** Using `decorations: false` + `always_on_top: true` in `tauri.conf.json` creates an undecorated window, but content is still **bounded to that window's rectangle**. Dragging DOM elements inside won't move the window itself.
- **For true desktop pet/overlay behavior**, you need one of:
  1. **Multi-window API:** Each pet gets its own `WebviewWindow` (undecorated, transparent, always-on-top). Windows can be positioned independently on the desktop.
  2. **Full-screen transparent overlay:** One window covering the entire screen with `transparent: true` and click-through. Pets are absolutely-positioned DOM elements.
- **Key config for overlay windows:**
  ```json
  {
    "decorations": false,
    "transparent": true,
    "alwaysOnTop": true,
    "skipTaskbar": true,
    "visibleOnAllWorkspaces": true
  }
  ```

### Threading on Windows
- **Pitfall:** `std::thread::spawn` in Tauri's Windows GUI subsystem can panic silently. The Windows GUI thread has restrictions.
- **Pattern:** Use `tauri::async_runtime::spawn` for async tasks, or spawn a **separate binary** via `std::process::Command` for long-running servers.
- **Separate binary spawning:** The spawned binary must be in the same directory as the main exe. Use `std::env::current_exe()` → `.parent()` → `.join("other_binary.exe")`.

## Tray ↔ Frontend Communication

### Event Wiring
- **Pitfall:** Rust tray code can emit events via `app.emit("event-name", payload)`, but if the frontend code never calls `listen("event-name", callback)`, the event is silently lost.
- **Pattern:** Always verify the full chain: tray menu click → Rust `app.emit()` → frontend `listen()` → UI update.
- **In React/Tauri:** Use `import { listen } from '@tauri-apps/api/event'` and set up listeners in `useEffect`.

### Tray Icon API (Tauri 2)
- **Pitfall:** `Image::from_bytes()` does NOT exist in Tauri 2. Use `Image::new(&rgba_bytes, width, height)` with raw RGBA pixel data instead.
- **Pattern for generating tray icon at runtime:**
  ```rust
  let size: u32 = 32;
  let mut rgba = Vec::new();
  for y in 0..size {
      for x in 0..size {
          if is_inside_circle { rgba.extend_from_slice(&[R, G, B, A]); }
          else { rgba.extend_from_slice(&[0, 0, 0, 0]); }
      }
  }
  let tray_icon = Image::new(&rgba, size, size);
  ```
- **Lifetime gotcha:** `rgba` must live long enough — don't create it inside a block that drops before `Image::new()` returns. Declare `rgba` and `tray_icon` at the same scope level. Creating `rgba` inside a `let tray_icon = { ... }` block and then using `tray_icon` after the block exits is a compile error (`rgba does not live long enough`).
- **Scope pattern that works:** Declare `rgba` and `size` at the `setup()` closure level, fill the pixel data, then call `Image::new(&rgba, size, size)` — all at the same scope. Don't wrap the pixel generation in a nested block.

## Tauri 2 Capability Permissions

### Permission Naming
- **Pitfall:** Permission names are prefixed with `core:` in Tauri 2. Using `tray:default` will fail — it must be `core:tray:default`.
- **Common permission names that differ from Tauri 1:**
  - `tray:default` → `core:tray:default`
  - `core:app:allow-app-handle` → does NOT exist; use `core:app:default` instead
  - `core:window:allow-set-ignore-cursor-events` — this one IS valid
- **Build-time validation:** Tauri validates ALL permissions at build time. Invalid names cause build failure with a list of valid permissions.

### Feature Flags
- **Pitfall:** `tauri::tray`, `TrayIconBuilder`, and tray-related APIs require the `tray-icon` feature flag.
- **Fix:** In `Cargo.toml`:
  ```toml
  tauri = { version = "2", features = ["tray-icon", "macos-private-api"] }
  ```

## Build & Deploy

### Cross-Compilation from WSL/Linux to Windows
- **Target:** Use `x86_64-pc-windows-gnu` (MinGW) for cross-compilation from WSL. Requires `mingw-w64` package.
- **Cargo config** (`.cargo/config.toml` in src-tauri):
  ```toml
  [target.x86_64-pc-windows-gnu]
  linker = "x86_64-w64-mingw32-gcc"
  ```
- **Install target:** `rustup target add x86_64-pc-windows-gnu`
- **Output location:** `target/x86_64-pc-windows-gnu/release/` (NOT `target/release/`)
- **NSIS installer:** `makensis` is NOT available on Linux. Cross-compilation produces the `.exe` but NOT the installer.

### Icon Files
- **Pitfall:** Tauri requires `icons/icon.ico` (Windows) and `icons/icon.icns` (macOS) for bundling. Missing files cause build failure.
- **ICO generation from Python:** When generating ICO files programmatically:
  - ICO directory entry width/height bytes: 0 means 256, otherwise the actual size
  - Each entry's width/height MUST match the actual PNG dimensions embedded in the ICO
  - Setting w=0, h=0 for a 16x16 image causes Tauri to misparse it
- **ICNS:** For cross-compilation to Windows, a placeholder ICNS is fine (Tauri only uses it for macOS builds).

### Stale Binary Trap
- After fixing source code, always **rebuild and redeploy**. The deployed binary may be from a previous build.
- Verify the deployed binary's timestamp matches your latest build.

## Animation in Tauri + React/Svelte

### Pet/Character Animation
- **Static emoji is not animation.** Rendering a static image with CSS is not enough.
- **For animated pets, you need:**
  1. State-based visual changes (different appearance per state: idle, busy, error, etc.)
  2. Autonomous movement (CSS keyframes or JS-driven position updates)
  3. Drag interaction (mousedown/mousemove/mouseup with position state)
  4. State-based CSS animations (float, bounce, shake, pulse, fade)
- **Approach options:**
  - CSS keyframe animations (simple, GPU-accelerated)
  - SVG with SMIL/CSS animations (scalable, crisp)
  - Sprite sheets with CSS `steps()` (for frame-by-frame)
  - JS-driven canvas (most flexible, most complex)

### Inline SVG vs External SVG Files
- **Pitfall:** Switching from inline SVG to external `<img>` SVG files breaks CSS transforms on internal SVG elements (e.g., eye tracking that moves `<g>` elements within the SVG).
- **Trade-off:**
  - **Inline SVG:** Can manipulate internal elements via CSS/JS (eye tracking, color changes). SVG code is embedded in JSX.
  - **External SVG (`<img>`):** Clean separation, easy to swap states. But internal SVG elements are NOT accessible to CSS/JS.
- **Hybrid approach:** Render the base body as `<img>` and overlay interactive elements (eyes, accessories) as separate HTML/SVG elements positioned absolutely on top.
- **Cleanup checklist after SVG externalization:**
  1. Remove any props passed for internal SVG manipulation (e.g., `eyeOffset`)
  2. Remove unused interfaces/types that referenced those props
  3. Remove any `useState`/`useRef` variables only used for SVG element manipulation
  4. Remove any `useEffect` hooks that targeted internal SVG elements
  5. Run `pnpm build` to check for TypeScript errors from stale references
