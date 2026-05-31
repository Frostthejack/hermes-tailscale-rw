# Tauri 2 Cross-Compilation from WSL2 → Windows

> Reference for building Tauri 2 apps from WSL2 Ubuntu to Windows targets.

## Prerequisites

```bash
# Install Rust (if not present)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
source "$HOME/.cargo/env"

# Add Windows GNU target (MinGW cross-compiler)
rustup target add x86_64-pc-windows-gnu

# Verify MinGW is installed (usually pre-installed on Ubuntu 24.04)
dpkg -l | grep mingw-w64
```

## Cargo Configuration

Create `src-tauri/.cargo/config.toml`:

```toml
[target.x86_64-pc-windows-gnu]
linker = "x86_64-w64-mingw32-gcc"

[build]
target = "x86_64-pc-windows-gnu"
```

## Cargo.toml — Required Features

```toml
[dependencies]
tauri = { version = "2", features = ["tray-icon"] }
tauri-plugin-opener = "2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

> **Critical:** The `tray-icon` feature is NOT enabled by default in Tauri 2. Without it, `tauri::tray`, `tauri::menu`, and `tauri::image` modules are unavailable at compile time.

## Capability Permissions

Tauri 2 validates permissions **at build time**. Invalid permission names cause build failures with a list of valid permissions.

### Common Pitfalls

| Wrong | Correct |
|-------|---------|
| `tray:default` | `core:tray:default` |
| `core:app:allow-app-handle` | `core:app:default` |
| `menu:default` | `core:menu:default` |

### Minimal Working Set for Tray + Window

```json
{
  "identifier": "default",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "core:window:default",
    "core:window:allow-set-size",
    "core:window:allow-set-position",
    "core:window:allow-set-ignore-cursor-events",
    "core:window:allow-inner-position",
    "core:window:allow-scale-factor",
    "core:window:allow-primary-monitor",
    "core:window:allow-available-monitors",
    "core:app:default",
    "core:event:default",
    "core:event:allow-emit",
    "core:tray:default",
    "core:tray:allow-new",
    "core:tray:allow-set-icon",
    "core:tray:allow-set-menu",
    "core:menu:default",
    "core:menu:allow-new",
    "core:menu:allow-append",
    "opener:default"
  ]
}
```

## Icons

Tauri requires `icons/icon.ico` (Windows) and `icons/icon.icns` (macOS). For cross-compilation from Linux, generate them with Python (see code in session transcript). Key points:

- ICO directory entry width/height must match actual PNG dimensions (0 = 256)
- `Image::from_bytes()` does NOT exist in Tauri 2 — use `Image::new(&rgba, w, h)` with raw RGBA bytes
- The `rgba` Vec must outlive the `Image::new()` call (declare outside block expressions)

## Build Commands

```bash
pnpm tauri build --target x86_64-pc-windows-gnu
```

## Known Limitations (Cross-Compilation)

| Feature | Status |
|---------|--------|
| `.exe` compilation | ✅ Works |
| NSIS installer | ❌ Requires `makensis` (Windows only) |
| MSI installer | ❌ Requires Windows host |
| Code signing | ❌ Requires Windows host |
