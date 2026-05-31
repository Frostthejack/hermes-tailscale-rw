# Windows Port Ghost Block — No Owner in netstat but Bind Fails

## Symptom
A TCP port shows no owner in `netstat -ano` but attempting to bind to it fails with:
```
An attempt was made to access a socket in a way forbidden by its access rights
```
or
```
Only one usage of each socket address (protocol/network address/port) is normally permitted
```

## Verified Instance (2026-05-15)
- **Port**: 9191
- **Environment**: Windows 11, WSL2 (Ubuntu-24.04)
- **Symptoms**: `netstat -ano | findstr 9191` returns nothing. No process owns it. But `TcpListener` bind fails.
- **Fix**: Changed to port 19191, which worked immediately.

## Diagnosis Commands (Windows PowerShell)
```powershell
# Check if port is in an excluded range
netsh int ipv4 show excludedportrange protocol=tcp

# Check HTTP.sys URL reservations
netsh http show urlacl | findstr "<port>"

# Check for stealth reservations
Get-NetTCPConnection -State Listen | Where-Object { $_.LocalPort -eq <port> }
```

## Common Causes
1. **HTTP.sys port reservation**: A service registered the URL prefix with HTTP.sys but isn't actively listening
2. **Windows NAT driver (winnat)**: Can hold ports after WSL restarts
3. **Hyper-V / WSL virtual switch**: May reserve port ranges
4. **Windows Update or system service**: Temporary reservation that wasn't released

## Fix Options
1. **Change the application port** (simplest) — pick a port outside common reserved ranges
2. **Release the reservation** (if HTTP.sys):
   ```powershell
   netsh http delete urlacl url=http://+:<port>/
   ```
3. **Restart winnat** (use with caution — affects all NAT):
   ```powershell
   net stop winnat
   net start winnat
   ```

## Recommended Alternative Ports
| Original | Alternative |
|----------|-------------|
| 9191 | 19191 |
| 3000 | 3001 |
| 5000 | 5001 |
| 8080 | 8081 |

---

# Windows Firewall — EXE-Level Block Rules

## Symptom
Your app is listening on a port (confirmed via `netstat`), and localhost connections work fine, but remote connections (e.g., from WSL, another machine, or another network segment) are blocked. The port shows as LISTENING but external connections time out.

## Verified Instance: Agent Persona (2026-05-15)
- **App**: `agent-persona.exe` listening on port 8080
- **netstat**: `TCP 0.0.0.0:8080 LISTENING` — confirmed
- **localhost curl**: `{"status":"ok"}` — works
- **WSL curl to 192.168.0.40:8080**: Connection timed out
- **Root cause**: Windows Firewall had **Block** rules for the exe itself:
  ```
  Rule Name: agent-persona.exe
  Direction: In
  Protocol: TCP
  Action: Block
  Program: C:\users\luned\desktop\agent-persona.exe
  ```
- **Fix**: Changed to Allow (requires admin):
  ```cmd
  netsh advfirewall firewall set rule name="agent-persona.exe" new action=allow
  ```

## Diagnosis Commands

```cmd
:: Check for rules targeting your exe
netsh advfirewall firewall show rule name=all | findstr /i "yourapp"

:: Get full details
netsh advfirewall firewall show rule name="yourapp.exe" verbose
```

Look for `Action: Block` — that's your problem.

## Why This Happens

Windows Firewall can have **program-specific** rules that override port-level rules. If a Block rule exists for your exe, it doesn't matter what port your app listens on — all inbound traffic to that exe is blocked. These rules can be created by:
- Windows Defender SmartScreen
- Previous app installations
- Corporate/group policy
- Manual user action
- The app's own installer (some installers add Block rules for updater exes)

## Fix (Requires Admin)

```cmd
:: Change existing Block rule to Allow
netsh advfirewall firewall set rule name="yourapp.exe" new action=allow

:: Or delete the Block rule entirely
netsh advfirewall firewall delete rule name="yourapp.exe"

:: Or add a port-level Allow rule (also requires admin)
netsh advfirewall firewall add rule name="MyApp Webhook" dir=in action=allow protocol=tcp localport=8080
```

## Key Insight

**Port-level listening ≠ inbound access.** Always check BOTH:
1. Is the app listening? (`netstat -an | findstr PORT`)
2. Is the firewall allowing it? (`netsh advfirewall firewall show rule name=all | findstr /i app`)

A common debugging trap: testing from localhost works fine (localhost bypasses firewall rules for most configs), but remote connections fail. Always test from the actual remote source, not just localhost.

---

# Tauri App Port Mismatch Pattern

## Symptom
A Tauri app's frontend (Svelte/JS) hardcodes a port for API calls that doesn't match the Rust backend's actual listening port. The app appears to run but API calls silently fail.

## Verified Instance: Agent Persona (2026-05-15)
- **Frontend** (`src/App.svelte`): Used `$settings?.webhookPort ?? 8080` — correct
- **Backend** (`src-tauri/src/lib.rs`): `start_webhook_server(app.handle().clone(), 8080)` — correct
- **But**: Old built binary had port 9191 hardcoded from a previous version
- **Result**: Source was correct but binary was stale. Rebuild was needed.

## Fix Pattern
1. **Make the port dynamic** — read from settings/store, not hardcoded:
   ```svelte
   const webhookPort = $settings?.webhookPort ?? 8080;
   const res = await fetch(`http://127.0.0.1:${webhookPort}/webhooks/respond-approval`, {...});
   ```
2. **Add port to default settings**:
   ```js
   webhookPort: 8080,  // Must match backend default
   ```
3. **Add port to settings UI** so user can change it if needed
4. **Ensure backend and frontend defaults match**
5. **Rebuild both frontend and backend** when changing ports

## Key Insight
In Tauri apps, the Rust backend and Svelte frontend are built separately. The frontend's compiled JS is bundled into the Tauri binary. If you change the backend port, you **must** also update the frontend and rebuild both. A mismatch won't cause a crash — it silently fails in fetch `catch` blocks, making it hard to debug.

## Diagnostic Approach
1. Search frontend source for hardcoded port numbers: `grep -rn "127.0.0.1:" src/`
2. Search backend source for the actual port: `grep -rn "start_webhook_server\|listen\|bind" src-tauri/src/`
3. Compare the two — they must match
4. Check if the port is also ghost-blocked on Windows
5. **Check if the binary matches the source** — a stale binary is a common cause of "correct source, broken app"
