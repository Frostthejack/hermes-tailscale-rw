# Tauri App — Persistent Settings Pattern

## Pattern: Configurable Settings via config.json + Tauri Commands

For Tauri apps that need user-configurable values (ports, themes, behavior), use this pattern:

### 1. Define a Settings Struct (Rust Backend)

```rust
#[derive(Debug, serde::Serialize, serde::Deserialize, Clone)]
pub struct AppSettings {
    pub webhook_port: u16,
    // Add other settings here
}

impl Default for AppSettings {
    fn default() -> Self {
        Self { webhook_port: 8080 }
    }
}
```

### 2. Load/Save from App Data Directory

```rust
fn load_settings(app: &tauri::AppHandle) -> AppSettings {
    let config_path = app.path().app_data_dir()
        .ok()
        .map(|dir| dir.join("config.json"));
    if let Some(path) = config_path {
        if let Ok(contents) = std::fs::read_to_string(&path) {
            if let Ok(settings) = serde_json::from_str::<AppSettings>(&contents) {
                return settings;
            }
        }
    }
    AppSettings::default()
}

fn save_settings(app: &tauri::AppHandle, settings: &AppSettings) {
    if let Ok(dir) = app.path().app_data_dir() {
        let _ = std::fs::create_dir_all(&dir);
        let path = dir.join("config.json");
        if let Ok(json) = serde_json::to_string_pretty(settings) {
            let _ = std::fs::write(&path, json);
        }
    }
}
```

### 3. Expose Tauri Commands

```rust
pub struct SettingsState {
    pub settings: Mutex<AppSettings>,
}

#[tauri::command]
fn get_webhook_port(state: tauri::State<'_, SettingsState>) -> u16 {
    state.settings.lock().unwrap().webhook_port
}

#[tauri::command]
fn set_webhook_port(
    app: tauri::AppHandle,
    state: tauri::State<'_, SettingsState>,
    port: u16,
) -> Result<(), String> {
    if port == 0 {
        return Err("Port must be >= 1".to_string());
    }
    let mut settings = state.settings.lock().unwrap();
    settings.webhook_port = port;
    save_settings(&app, &settings);
    Ok(())
}
```

### 4. Register in invoke_handler

```rust
.invoke_handler(tauri::generate_handler![
    // ... other commands
    get_webhook_port,
    set_webhook_port,
])
```

### 5. Frontend: Call from Svelte

```svelte
<script>
  import { onMount } from 'svelte';
  let tauriInvoke = null;
  let portInputValue = '8080';

  onMount(() => {
    tauriInvoke = window.__TAURI__?.core.invoke ?? null;
  });

  async function save() {
    const port = parseInt(portInputValue, 10);
    if (tauriInvoke) {
      await tauriInvoke('set_webhook_port', { port });
    }
    // Also update localStorage for immediate frontend use
    const stored = JSON.parse(localStorage.getItem('settings') || '{}');
    stored.webhookPort = port;
    localStorage.setItem('settings', JSON.stringify(stored));
  }
</script>

<input type="number" bind:value={portInputValue} min="1" max="65535" />
<button on:click={save}>Save</button>
```

### 6. Use Dynamic Port in API Calls

```svelte
<script>
  import { settings } from './stores/settingsStore.js';
</script>

{#if settings}
  {@const webhookPort = $settings?.webhookPort ?? 8080}
  {await fetch(`http://127.0.0.1:${webhookPort}/webhooks/status`, {...})}
{/if}
```

### Key Principles

1. **Never hardcode ports or other user-configurable values.** Always use settings with sensible defaults.
2. **Default must match across frontend and backend.** If backend defaults to 8080, frontend must also default to 8080.
3. **Persist in two places:** Rust `config.json` (for backend on restart) and `localStorage` (for frontend immediate use).
4. **Validate on save.** Port 0 is invalid for `u16`. Range-check user input.
5. **Settings changes take effect on restart** for the backend (the server is already running on the old port). The frontend picks up changes immediately from localStorage.
