# Tauri 2 Webhook Server Pattern (Axum In-Process)

> Reference for adding an in-process HTTP webhook server to a Tauri 2 app using axum.

## When to Use

Use this pattern when the Tauri app needs to receive external HTTP events (e.g., from Hermes Agent webhooks, CI/CD callbacks, or other services) without running a separate server process.

## Architecture

```
External Service → HTTP POST → axum server (port 32947) → Tauri event emit → Frontend Zustand store
```

The axum server runs inside the Tauri async runtime (`tauri::async_runtime::spawn`), sharing the app handle for emitting events to the frontend.

## Implementation

### 1. Add dependencies to `src-tauri/Cargo.toml`

```toml
[dependencies]
axum = "0.7"
tower-http = { version = "0.5", features = ["cors"] }
```

### 2. Add server code to `src-tauri/src/lib.rs`

```rust
use axum::{
    routing::post,
    Json, Router,
    extract::State,
    http::StatusCode,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::Mutex;

#[derive(Debug, Deserialize)]
struct WebhookEvent {
    event_type: String,
    profile_name: String,
    #[serde(default)]
    message: Option<String>,
}

#[derive(Debug, Serialize, Clone)]
struct PetStateEvent {
    event_type: String,
    profile_name: String,
    pet_state: String,
    message: Option<String>,
}

fn event_to_pet_state(event_type: &str) -> &'static str {
    match event_type {
        "agent_start" => "idle",
        "agent_thinking" => "thinking",
        "agent_working" => "working",
        "agent_done" => "done",
        "agent_error" => "error",
        "agent_notification" => "notification",
        "agent_sleep" => "sleeping",
        _ => "idle",
    }
}

async fn handle_webhook(
    State(app): State<Arc<Mutex<tauri::AppHandle>>>,
    Json(payload): Json<WebhookEvent>,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let pet_state = event_to_pet_state(&payload.event_type);
    let state_event = PetStateEvent {
        event_type: payload.event_type.clone(),
        profile_name: payload.profile_name.clone(),
        pet_state: pet_state.to_string(),
        message: payload.message.clone(),
    };

    let app = app.lock().await;
    if let Err(e) = app.emit("pet_state_event", &state_event) {
        eprintln!("[webhook] Failed to emit: {}", e);
        return Err(StatusCode::INTERNAL_SERVER_ERROR);
    }

    Ok(Json(serde_json::json!({"status": "ok"})))
}

async fn start_webhook_server(app_handle: tauri::AppHandle) {
    let app = Arc::new(Mutex::new(app_handle));
    let router = Router::new()
        .route("/api/webhook", post(handle_webhook))
        .with_state(app);

    let listener = tokio::net::TcpListener::bind("127.0.0.1:32947")
        .await
        .expect("Failed to bind webhook server");

    eprintln!("[webhook] Server listening on http://127.0.0.1:32947");
    axum::serve(listener, router).await.expect("Webhook server failed");
}
```

### 3. Spawn in Tauri setup

In `run()`, before `.run(tauri::generate_context!())`:

```rust
tauri::async_runtime::spawn(start_webhook_server(app.handle().clone()));
```

### 4. Frontend event listener

```typescript
import { listen } from "@tauri-apps/api/event";

useffect(() => {
  const unlisten = listen<PetStateEvent>("pet_state_event", (event) => {
    const { profile_name, pet_state } = event.payload;
    usePetSystemStore.getState().setPetState(profile_name, pet_state as PetState);
  });
  return () => { unlisten.then((f) => f()); };
}, []);
```

## Port Selection

Use high ports (30000+) to avoid conflicts. DaemonCore uses **32947**. Avoid 3000, 8080, 8188 (ComfyUI), 5173 (Vite dev server).

## Testing

```bash
curl -X POST http://127.0.0.1:32947/api/webhook \
  -H "Content-Type: application/json" \
  -d '{"event_type":"agent_thinking","profile_name":"test","message":"Analyzing..."}'
# Expected: {"status":"ok"}
```

## Gotchas

- **Don't block the Tauri main thread** — always use `tauri::async_runtime::spawn`
- **CORS** — add `tower-http` with `cors` feature if the sender is on a different origin
- **Port conflicts** — check the port isn't in use: `netstat -tlnp | grep 32947`
- **WSL→Windows** — the server binds to 127.0.0.1 on the WSL side. For Windows→WSL communication, use the WSL gateway IP or bind to `0.0.0.0`
