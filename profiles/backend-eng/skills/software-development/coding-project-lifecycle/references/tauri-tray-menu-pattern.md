# Tauri 2 — System Tray Menu Pattern

> Reference for building a system tray menu as the **primary control surface** for a Tauri 2 desktop app (replacing in-window buttons/panels).

## When to Use

Use this pattern when the app is a desktop overlay/widget (always-on-top, transparent, borderless). The window itself should be minimal — just the visual content. All settings, toggles, and management go in the system tray menu.

## Architecture

```
Desktop (transparent window)
  └── Pet/Widget rendering only (no buttons, no panels)
      └── Clicks pass through to windows behind

System Tray Icon (purple circle, 32x32 RGBA)
  └── Right-click → Menu
      ├── Show Pet (checkable toggle)
      ├── Sounds (checkable toggle)
      ├── Follow Mouse (checkable toggle)
      ├── ── separator ──
      ├── Theme: Midnight (checkable, default)
      ├── Theme: Peach (checkable)
      ├── Theme: Cloud (checkable)
      ├── Theme: Moss (checkable)
      ├── ── separator ──
      ├── Size: Small (checkable)
      ├── Size: Medium (checkable, default)
      ├── Size: Large (checkable)
      ├── ── separator ──
      ├── Active Sessions... (clickable → opens session panel)
      ├── ── separator ──
      └── Quit (with CmdOrCtrl+Q accelerator)
```

## Rust Implementation (lib.rs)

### Cargo.toml features

```toml
[dependencies]
tauri = { version = "2", features = ["tray-icon"] }
```

> **Critical:** `tray-icon` feature is NOT enabled by default. Without it, `tauri::tray`, `tauri::menu`, and `tauri::image` modules won't compile.

### Building the tray icon

Generate a simple icon from raw RGBA bytes (no external icon files needed):

```rust
let size: u32 = 32;
let mut rgba = Vec::new();
for y in 0..size {
    for x in 0..size {
        let cx = size as f64 / 2.0;
        let cy = size as f64 / 2.0;
        let r = (size as f64 / 2.0) - 2.0;
        let dx = x as f64 - cx;
        let dy = y as f64 - cy;
        if dx * dx + dy * dy <= r * r {
            rgba.extend_from_slice(&[124, 109, 240, 255]); // purple
        } else {
            rgba.extend_from_slice(&[0, 0, 0, 0]); // transparent
        }
    }
}
let tray_icon = Image::new(&rgba, size, size);
```

### Building the menu (flat layout with separators)

Use `MenuBuilder` with `CheckMenuItemBuilder` for toggles. Use `PredefinedMenuItem::separator()` for dividers.

```rust
fn build_tray_menu(app: &tauri::AppHandle) -> Result<tauri::menu::Menu<tauri::Wry>, tauri::Error> {
    let show_pet = CheckMenuItemBuilder::new("Show Pet").id("show_pet").checked(true).build(app)?;
    let sounds = CheckMenuItemBuilder::new("Sounds").id("sounds").checked(true).build(app)?;
    let follow_mouse = CheckMenuItemBuilder::new("Follow Mouse").id("follow_mouse").checked(true).build(app)?;

    let sep1 = tauri::menu::PredefinedMenuItem::separator(app)?;

    let theme_midnight = CheckMenuItemBuilder::new("Theme: Midnight").id("theme_midnight").checked(true).build(app)?;
    let theme_peach = CheckMenuItemBuilder::new("Theme: Peach").id("theme_peach").checked(false).build(app)?;
    let theme_cloud = CheckMenuItemBuilder::new("Theme: Cloud").id("theme_cloud").checked(false).build(app)?;
    let theme_moss = CheckMenuItemBuilder::new("Theme: Moss").id("theme_moss").checked(false).build(app)?;

    let sep2 = tauri::menu::PredefinedMenuItem::separator(app)?;

    let size_small = CheckMenuItemBuilder::new("Size: Small").id("size_small").checked(false).build(app)?;
    let size_medium = CheckMenuItemBuilder::new("Size: Medium").id("size_medium").checked(true).build(app)?;
    let size_large = CheckMenuItemBuilder::new("Size: Large").id("size_large").checked(false).build(app)?;

    let sep3 = tauri::menu::PredefinedMenuItem::separator(app)?;
    let sessions = MenuItemBuilder::with_id("sessions", "Active Sessions...").enabled(true).build(app)?;
    let sep4 = tauri::menu::PredefinedMenuItem::separator(app)?;
    let quit = MenuItemBuilder::with_id("quit", "Quit").accelerator("CmdOrCtrl+Q").build(app)?;

    let menu = MenuBuilder::new(app)
        .item(&show_pet).item(&sounds).item(&follow_mouse)
        .append(&sep1)?
        .item(&theme_midnight).item(&theme_peach).item(&theme_cloud).item(&theme_moss)
        .append(&sep2)?
        .item(&size_small).item(&size_medium).item(&size_large)
        .append(&sep3)?
        .item(&sessions).append(&sep4)?.item(&quit)
        .build()?;
    Ok(menu)
}
```

### Handling menu events

```rust
.on_menu_event(move |app, event| {
    let payload = match event.id.as_ref() {
        "show_pet"       => "show_pet",
        "sounds"         => "sounds",
        "follow_mouse"   => "follow_mouse",
        "theme_midnight" => "theme:midnight",
        "theme_peach"    => "theme:peach",
        "theme_cloud"    => "theme:cloud",
        "theme_moss"     => "theme:moss",
        "size_small"     => "size:small",
        "size_medium"    => "size:medium",
        "size_large"     => "size:large",
        "sessions"       => "sessions",
        "quit"           => { app.exit(0); return; },
        _                => return,
    };
    app.emit("tray_event", payload).unwrap_or_default();
})
```

> **Note:** Checkable menu items auto-toggle their checked state in Tauri 2 — you do NOT need to manually update checked state.

### Frontend event handling (React + Zustand)

```typescript
useEffect(() => {
    const unlisten = listen<string>("tray_event", (event) => {
        const id = event.payload;
        if (id === "show_pet") setShowPet(!showPet);
        if (id === "sounds") setSoundsEnabled(!isSoundsEnabled);
        if (id === "follow_mouse") setFollowMouse(!followMouse);
        if (id.startsWith("theme:")) setTheme(id.split(":")[1]);
        if (id.startsWith("size:")) setSize(id.split(":")[1]);
    });
    return () => { unlisten.then(f => f()); };
}, [showPet, isSoundsEnabled, followMouse, setTheme, setSize]);
```

## Click-Through Fix (CSS)

For transparent overlay windows, the container background **cannot** be fully `transparent` or mouse events pass through everything. Use a nearly-invisible background:

```css
.container {
    background-color: rgba(0, 0, 0, 0.01); /* captures mouse events */
}
```

Then use `pointer-events: auto` on specific interactive elements.

## Validation Checklist

- [ ] Tray icon appears in Windows system tray
- [ ] Right-click opens the menu with all items
- [ ] Checkable items show correct checked state
- [ ] Toggling updates the UI (theme, size, follow, show, sounds)
- [ ] Quit exits cleanly
- [ ] Window background is visually transparent despite rgba(0,0,0,0.01)
