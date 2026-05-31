# Tauri Windows Development — Pitfalls and Patterns

## Critical: Windows GUI Subsystem Blocks Thread Spawning

Tauri apps on Windows use `windows_subsystem = "windows"` which means:
- `std::thread::spawn` **panics silently** — the thread never starts, no error shown
- `eprintln!` output goes **nowhere** (no console attached)
- File-based logging is the only way to debug thread issues

**Solution:** Use `std::process::Command` to spawn a separate binary for background services (like a webhook server), NOT threads.

## Spawning a Separate Binary from Tauri

When spawning a child process from a Tauri app on Windows:

```rust
// In lib.rs setup hook:
if let Ok(exe_dir) = std::env::current_exe() {
    if let Some(dir) = exe_dir.parent() {
        let webhook_exe = dir.join("webhook_server.exe");
        if webhook_exe.exists() {
            let _ = std::process::Command::new(webhook_exe)
                .env("PORT", "9191")
                .spawn();
        }
    }
}
```

**Caveat:** The child binary must be in the **same directory** as the main exe. When cross-compiling from WSL2, manually copy both binaries to Windows.

## Port Conflicts on Windows

Before binding to a port on Windows:
1. `netstat -ano | findstr <port>` — any existing connections
2. `netsh int ipv4 show excludedport range protocol=tcp` — excluded ranges
3. Test with `System.Net.Sockets.TcpListener` in PowerShell

**Common issue:** Port shows no owner in netstat but still can't bind. Try a different port.

## File Logging for Windows GUI Apps

Since `eprintln!` goes nowhere in Windows GUI apps:

```rust
let log_path = std::env::temp_dir().join("app-debug.log");
let _ = std::fs::write(&log_path, "message\n");
```

Write a marker file at thread start to confirm the thread launched. If the marker doesn't appear, the thread panicked.
