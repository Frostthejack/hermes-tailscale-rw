---
name: wsl-cross-platform-networking
title: WSL Cross-Platform Networking & Bridge Patterns
category: devops
description: Solutions for WSL2 ↔ Windows service interoperability — port forwarding, bridging, firewall configuration, and path handling for AionUI, MCP servers, and cross-platform development workflows.
priority: high
tags: [wsl2, windows, networking, portproxy, firewall, bridge, aionui, mcp, cross-platform]
---

# WSL Cross-Platform Networking & Bridge Patterns

**Domain**: WSL2/Windows network interoperability, port forwarding, service bridging, cross-platform path handling

**Scope**: Solutions for accessing Windows services from WSL2 and vice versa, including AionUI, MCP servers, HTTP APIs, and Hermes Agent's optional **API Server** (`/v1/models` endpoints). The API Server runs inside WSL on port **8642** (default) but requires explicit activation — it is **disabled by default** and must be configured via `API_SERVER_ENABLED=true` in `~/.hermes/.env`.

**Key Insight**: Hermes Gateway (messaging platforms) and Hermes API Server (OpenAI-compatible HTTP endpoints) are **separate components**. The Gateway runs as a systemd service; the API Server only starts when `API_SERVER_ENABLED=true` plus `API_SERVER_KEY=<secret>` are set. Without these, `GET /v1/models` returns connection refused even though the Gateway service appears running.

---

## Quick Decision Matrix

| Scenario | Target | Source | Solution |
|----------|--------|--------|----------|
| WSL → Windows service | Windows `127.0.0.1:PORT` | WSL | PortProxy to vEthernet IP (`172.25.144.1`) + firewall exception |
| Windows → WSL service | WSL `127.0.0.1:PORT` | Windows | PortProxy from Windows `127.0.0.1:N` → WSL IP `M:PORT` |
| WSL API Server → Windows | Windows `127.0.0.1:PORT` | WSL | PortProxy or SSH tunnel |
| Windows PowerShell → WSL API Server | WSL `127.0.0.1:8642` | Windows | Use Windows IP `192.168.0.x` (Windows Firewall exception) OR PortProxy to bridge |
| Persistent bidirectional | Both sides | Both | SSH tunnel (recommended for production) |

---

## API Server Specifics (Hermes)

### Enable API Server in WSL

```bash
# ~/.hermes/.env
API_SERVER_ENABLED=true
API_SERVER_KEY=hermes-secret-key
API_SERVER_PORT=8642              # Optional, defaults to 8642
API_SERVER_HOST=127.0.0.1         # Optional, defaults to 127.0.0.1
```

Then restart:
```bash
hermes gateway restart
```

### Access from WSL (after enabling)
```bash
curl http://127.0.0.1:8642/v1/models
curl -H "Authorization: Bearer hermes-secret-key" http://127.0.0.1:8642/v1/models
```

### Access from Windows PowerShell (WSL API Server)

Since WSL runs in a NAT network, Windows cannot reach `127.0.0.1:8642` directly. Options:

#### Option A: Windows uses WSL IP directly (requires firewall exception)
```powershell
# Find the WSL-connected interface on Windows
# Typically 172.25.144.1 (vEthernet) or 192.168.0.x (host network)
curl http://172.25.144.1:8642/v1/models
```
*Problem*: Windows Firewall blocks inbound 8642 by default.

#### Option B: PortProxy bridge (Windows vEthernet → Windows loopback)
```powershell
# Windows PowerShell (Admin)
netsh interface portproxy add v4tov4 `
    listenaddress=172.25.144.1 `
    listenport=62936 `
    connectaddress=127.0.0.1 `
    connectport=8642

# Allow inbound on vEthernet (not Public!)
New-NetFirewallRule `
    -DisplayName "WSL API Bridge" `
    -Direction Inbound `
    -LocalAddress 172.25.144.1 `
    -LocalPort 62936 `
    -Protocol TCP `
    -Action Allow
```
Now from Windows PowerShell: `curl http://172.25.144.1:62936/v1/models`

#### Option C: SSH tunnel (recommended)
```powershell
# Enable Windows OpenSSH server
Add-WindowsCapability -Online -Name OpenSSH.Server
Start-Service sshd
```

```bash
# From WSL
autossh -M 0 -o "ServerAliveInterval 30" -L 62936:127.0.0.1:8642 -N -f user@192.168.0.40
```
Now from Windows: `curl http://127.0.0.1:62936/v1/models`

---

## Architecture Overview

### Network Topology
- **WSL2**: NAT-based virtual network (typically `172.25.144.0/20`), guest VM with its own `localhost`
- **Windows Host**: Physical network interface (e.g., `192.168.0.x`) + Hyper-V vEthernet adapter (`172.25.144.1`)
- **Isolation**: WSL2 `localhost` ≠ Windows `localhost` (separate namespaces)
- **Routing**: Windows can initiate to WSL IPs; WSL cannot route to Windows `127.0.0.1`; direct Windows IP access from WSL often blocked by Windows Firewall

### Key Constraints
1. Windows 10 lacks built-in WSL2 localhost forwarding (added in Windows 11 build 22621+)
2. Windows Firewall blocks inbound connections to most application ports from non-localhost sources
3. WSL2 uses virtual NIC with NAT — no direct route to Windows physical network
4. `host.docker.internal` resolves to Windows host but still subject to Windows Firewall policies

---

## Bridge Patterns

### Pattern 1: Windows PortProxy with Firewall Exception (Outbound-Bridge)

**Use Case**: WSL needs to connect to Windows service running on `127.0.0.1:PORT` (e.g., AionUI, database, dev server)

**Mechanism**:
- Windows `netsh portproxy` forwards Windows interface IP → Windows `127.0.0.1:PORT`
- Windows Firewall rule allows inbound on that interface
- WSL connects to Windows vEthernet/gateway IP

**Configuration**:

```powershell
# Windows PowerShell (Admin)
# Find WSL vEthernet gateway IP (typically 172.25.144.1)
Get-NetIPAddress | Where-Object {$_.InterfaceAlias -like "*vEthernet (WSL)*"}

# Add portproxy: Windows vEthernet IP:PORT -> Windows loopback:PORT
netsh interface portproxy add v4tov4 `
    listenaddress=172.25.144.1 `
    listenport=62936 `
    connectaddress=127.0.0.1 `
    connectport=62936

# Allow inbound on vEthernet interface only (not public!)
New-NetFirewallRule `
    -DisplayName "WSL Bridge - AionUI" `
    -Direction Inbound `
    -LocalAddress 172.25.144.1 `
    -LocalPort 62936 `
    -Protocol TCP `
    -Action Allow `
    -Enabled True
```

**WSL Usage**:
```bash
# Connect to Windows service via vEthernet gateway
curl http://172.25.144.1:62936
# Or use from WSL app: localhost won't work — must use 172.25.144.1
```

**Limitations**:
- Windows Firewall exceptions required per port/interface
- vEthernet IP may change after WSL restart (check each time)
- Windows 10 Home lacks advanced firewall rule UIs — use PowerShell

**Status**: Works reliably on Windows 10/11 when configured correctly

---

### Pattern 2: Reverse PortProxy (Inbound-Bridge)

**Use Case**: Windows service needs to connect to WSL service (e.g., WSL HTTP API, database)

**Mechanism**:
- Windows portproxy forwards Windows loopback → WSL IP
- WSL binds service to `0.0.0.0` (not `127.0.0.1`)

**Configuration**:

```powershell
# Windows PowerShell (Admin)
netsh interface portproxy add v4tov4 `
    listenaddress=127.0.0.1 `
    listenport=62937 `
    connectaddress=172.25.150.25 `
    connectport=62936
```

**WSL Setup**:
```bash
# Bind to 0.0.0.0, NOT 127.0.0.1
python -m http.server 62936 --bind 0.0.0.0
```

**Windows Usage**:
```powershell
# Windows connects to its own loopback, forwarded to WSL
curl http://127.0.0.1:62937
```

**Limitations**:
- WSL IP changes on restart (use DHCP reservation or script to update)
- Windows Firewall may block inbound — add exception if needed
- Service must bind to `0.0.0.0` not `127.0.0.1`

**Status**: Works reliably for WSL → Windows direction

---

### Pattern 3: socat TCP Bridge (Dual-Direction)

**Use Case**: Full bidirectional bridge, complex forwarding, or when portproxy is insufficient

**Mechanism**:
- Run `socat` on Windows (or WSL) to forward between endpoints
- Can chain multiple ports, handle protocol translation

**Windows socat (as service)**:
```powershell
socat TCP-LISTEN:62937,fork,reuseaddr TCP:172.25.150.25:62936
```

**WSL Python Bridge**:
```python
import socket, threading

def forward(src, dst):
    while True:
        data = src.recv(4096)
        if not data: break
        dst.sendall(data)
    src.close(); dst.close()

def bridge(listen_port, dest_host, dest_port, label):
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('0.0.0.0', listen_port))
    server.listen(5)
    while True:
        client, addr = server.accept()
        remote = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        remote.connect((dest_host, dest_port))
        threading.Thread(target=forward, args=(client, remote), daemon=True).start()
        threading.Thread(target=forward, args=(remote, client), daemon=True).start()

# Start bridge
bridge(62936, '192.168.0.40', 62936, "WebUI")
```

**Limitations**:
- Requires socat installation or custom bridge code
- No automatic restart on failure (unless run as service)
- Must maintain process lifecycle

**Status**: Most flexible; works when other patterns fail

---

### Pattern 4: SSH Tunnel (Recommended for Production)

**Use Case**: Secure, reliable cross-platform access; production deployments

**Mechanism**:
- Windows OpenSSH server enabled
- WSL creates local port forward through SSH

**Setup**:

```powershell
# Windows PowerShell (Admin)
Add-WindowsCapability -Online -Name OpenSSH.Server
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

**WSL Client**:
```bash
# One-time tunnel
ssh -L 62936:127.0.0.1:62936 -N -f -l username 192.168.0.40

# Auto-reconnect with autossh
autossh -M 0 -o "ServerAliveInterval 30" -L 62936:127.0.0.1:62936 -N -f user@192.168.0.40
```

**Advantages**:
- Encrypted channel
- Built-in keepalive/retry
- No firewall exceptions needed (uses SSH port 22)
- Works reliably across Windows/WSL restarts

**Status**: **Recommended** for production and persistent setups

---

### Pattern 5: Named Pipes / stdio Transport (AionUI-Specific)

**Use Case**: MCP servers communicating with AionUI without TCP

**Mechanism**:
- Use stdio transport instead of TCP for MCP communication
- AionUI launches MCP server as child process
- No network boundary crossed

**Example**:
```json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["/path/to/mcp-server.js"],
      "transport": "stdio"
    }
  }
}
```

**Limitations**:
- Only works for child-process-launched MCP servers
- Cannot connect to already-running Windows services

**Status**: Limited applicability; use only for integrated MCP servers

---

### Pattern 6: Windows UI Screenshot from WSL

**Use Case**: Capture screenshots of Windows applications (e.g., Tauri apps, desktop widgets) from WSL for verification, debugging, or sending to the user via Telegram.

**Mechanism**: Write a PowerShell script to a Windows temp path, then invoke it from WSL via `powershell.exe -ExecutionPolicy Bypass`. Uses `System.Windows.Forms.Screen` for full desktop or P/Invoke to `FindWindow`/`GetWindowRect` for a specific window, then `Graphics.CopyFromScreen` to capture.

**Step-by-step**:

1. Write the PowerShell script from WSL to a Windows-accessible path:
   ```bash
   cp /tmp/screenshot.ps1 /mnt/c/Users/$WINUSER/AppData/Local/Temp/screenshot.ps1
   ```

2. Execute it from WSL:
   ```bash
   powershell.exe -ExecutionPolicy -File "C:\\Users\\$WINUSER\\AppData\\Local\\Temp\\screenshot.ps1"
   ```

3. Copy the resulting PNG back to WSL for sending:
   ```bash
   cp /mnt/c/Users/$WINUSER/Desktop/screenshot.png /tmp/screenshot.png
   ```

**Full Desktop Capture** (`templates/screenshot-desktop.ps1`):
```powershell
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$bounds = $screen.Bounds
$bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bitmap.Save("C:\\Users\\luned\\Desktop\\screenshot.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
Write-Host "Screenshot saved"
```

**Single Window Capture** (`templates/screenshot-window.ps1`):
Uses P/Invoke to find window by title, bring to foreground, then capture just that region. See `templates/screenshot-window.ps1` for the full ready-to-use script. Usage:
```bash
# From WSL: copy script to Windows, edit WINDOW_TITLE, run it
cp templates/screenshot-window.ps1 /mnt/c/Users/$WINUSER/AppData/Local/Temp/screenshot-window.ps1
# Edit WINDOW_TITLE in the script first, then:
powershell.exe -ExecutionPolicy Bypass -File "C:\\Users\\$WINUSER\\AppData\\Local\\Temp\\screenshot-window.ps1"
```

**Key Pitfalls**:
- **Dollar sign stripping**: When passing PowerShell commands inline via `powershell.exe -Command "..."`, the shell strips `$` variables. Always write to a `.ps1` file and use `-File` instead.
- **`\\wsl$` network share is unreliable**: The `\\wsl$\Ubuntu\...` or `\\wsl$\Ubuntu-24.04\...` UNC path is often not accessible from Windows PowerShell, even when WSL is running. Do NOT rely on it. Always write files to Windows via `/mnt/c/` (e.g., `/mnt/c/Users/<user>/AppData/Local/Temp/`) and reference them from Windows as `C:\\Users\<user>\\AppData\\Local\\Temp/`.
- **Window not found by exact title**: Use the fallback loop via `Get-Process` with `MainWindowHandle` — some apps (e.g., Tauri) may have slightly different titles.
- **SetForegroundWindow may fail**: Returns `False` if the calling process doesn't have foreground priority. Add a `Start-Sleep -Milliseconds 500` after to let the window settle before capturing.
- **Multiple monitors**: `PrimaryScreen` only captures the main monitor. For multi-monitor setups, enumerate `System.Windows.Forms.Screen.AllScreens`.

**Verified**: Works for capturing Agent Persona (Tauri app) window at 416×309 from WSL. Process: `agent-persona.exe`, found via `Get-Process` fallback, captured to `C:\\Users\\luned\\Desktop\\agent-persona-window.png`.

---

### Pattern 7: Migrating PostgreSQL Data Directory from WSL to Windows

**Use Case**: Move a PG data directory (e.g., from an embedded/pg0 instance in WSL) to a native Windows PostgreSQL install via raw file copy.

**Key Steps**:
1. `sudo cp -a ~/.pg0/instances/<name>/data /mnt/c/Users/<user>/Desktop/pg-data-export`
2. Stop Windows PG service
3. Back up Windows `data` dir, replace with exported data
4. Fix NTFS permissions (grant `NETWORK_SERVICE` Full Control)
5. **Delete stale `postmaster.pid`** — this is the #1 cause of startup failure after migration
6. Start Windows PG service

**Version Compatibility**: Forward-compatible within same major (18.1 → 18.4 is fine). NOT backward-compatible. NOT cross-major.

**Common Failure**: "Server closed the connection unexpectedly" on first connection attempt = almost always a stale `postmaster.pid` or permissions issue. Delete the PID file and check NTFS permissions.

**Better Alternative**: If the WSL PG can be started at all, prefer `pg_dump -Fc` → `pg_restore` over raw file copy. More reliable, handles version differences, avoids permission/PID issues.

Full step-by-step guide with PowerShell commands: `references/postgres-data-migration-wsl-to-windows.md`

Building pgvector from source on Windows (MSVC): `references/pgvector-build-windows.md`

---

### Pattern 8: Windows App → WSL PostgreSQL (Common Case)

**Use Case**: A Windows application (e.g., hindsight-api, DBeaver, psql.exe) needs to connect to PostgreSQL running inside WSL.

**Problem**: Windows `127.0.0.1` ≠ WSL `127.0.0.1`. The Windows app connects to Windows localhost, but PG is in WSL.

#### Solution 0 — WSL2 Mirrored Networking (BEST, if available)

**Requirement**: WSL2 kernel ≥ 5.15.167.1 (WSL app version ≥ 2.0.0, check with `wsl --version` from Windows).

Add to `C:\\Users\<user>\\.wslconfig`:
```ini
[wsl2]
networkingMode=mirrored
```

**CRITICAL**: After editing `.wslconfig`, you MUST restart WSL for the change to take effect:
```powershell
wsl --shutdown
# WSL will auto-restart on next command or terminal open
```

**Verify mirrored mode is active**:
```bash
# In WSL:
hostname -I
# Should show ONLY the shared host IP (e.g., 192.168.0.40)
# If you see a second IP like 100.x.x.x or 172.x.x.x, mirrored mode is NOT active
```

**How it works**: With mirrored mode, WSL shares the same network stack as Windows. `127.0.0.1` on Windows reaches WSL services directly. No portproxy, no firewall rules, no IP lookup needed.

**Connection string** (same as if PG were on Windows):
```
postgresql://user:password@127.0.0.1:5432/dbname
```

**Verified (2026-05-15)**: User had `networkingMode=mirrored` in `.wslconfig` but WSL hadn't been restarted. WSL showed two IPs (`100.72.73.74` and `192.168.0.40`), confirming mirrored mode was NOT active. After `wsl --shutdown` + restart, only the shared IP should remain.

**Pitfall**: `netsh interface portproxy` does NOT work for routing from Windows to WSL's internal Hyper-V NAT IP (e.g., `100.72.73.74`). The portproxy creates the rule but TCP connections time out because the Windows network stack can't route to the WSL2 NAT network. Mirrored networking eliminates this problem entirely.

#### Solution A — Use Windows Host IP (When mirrored mode unavailable)

1. Find the Windows host IP from WSL:
   ```bash
   # From WSL:
   cat /etc/resolv.conf | grep nameserver | awk '{print $2}'
   # Or:
   hostname -I | awk '{print $2}'  # Usually 192.168.0.x
   ```

2. Update PostgreSQL to listen on all interfaces:
   ```bash
   # In WSL:
   sudo nano /etc/postgresql/*/main/postgresql.conf
   # Change: listen_addresses = '*'
   sudo service postgresql restart
   ```

3. Update pg_hba.conf to allow connections from Windows:
   ```bash
   sudo nano /etc/postgresql/*/main/pg_hba.conf
   # Add: host  all  all  0.0.0.0/0  md5
   sudo service postgresql restart
   ```

4. Use the Windows host IP in the connection string:
   ```
   postgresql://user:password@192.168.0.40:5432/dbname
   ```

**Caveat**: `192.168.0.40` from Windows is Windows itself, not WSL. This only works if the Windows Firewall allows the connection AND the routing reaches WSL. In practice, this often fails with timeouts due to Hyper-V NAT isolation. Prefer Solution 0 (mirrored) or Solution B (portproxy).

#### Solution B — PortProxy (Fallback when mirrored mode unavailable)

```powershell
# Windows PowerShell (Admin)
# Forward Windows 127.0.0.1:5432 → WSL IP:5432
netsh interface portproxy add v4tov4 `
    listenaddress=127.0.0.1 `
    listenport=5432 `
    connectaddress=100.72.73.74 `  # WSL IP from hostname -I (first IP)
    connectport=5432
```

Then the Windows app uses `127.0.0.1:5432` as if PG were local.

**WARNING**: This often DOES NOT WORK for WSL2 → Windows direction because `netsh portproxy` cannot route through the Hyper-V NAT layer. Connections will time out silently. If this happens, use Solution 0 (mirrored networking) or Pattern 4 (SSH tunnel).

**Diagnostic Commands**:
```bash
# WSL: Check PG is running and listening
sudo service postgresql status
sudo ss -tlnp | grep 5432

# WSL: Check listen_addresses
sudo -u postgres psql -c "SHOW listen_addresses;"

# WSL: Check pg_hba.conf allows remote
sudo -u postgres psql -c "SHOW hba_file;"
```

```powershell
# Windows: Test connection
psql -U username -h 192.168.0.40 -p 5432 -d dbname
```

**Note**: WSL IP (`hostname -I`) may change on WSL restart. For persistent setups, use an SSH tunnel (Pattern 4).

---

### Pattern: Auditing WSL vs Windows Hermes — The "Single Install" Gotcha

**Use Case**: User thinks they have two separate Hermes installs (WSL + Windows) and wants to migrate or compare them.

**Critical Insight**: With WSL2 `networkingMode=mirrored` (set in `~/.wslconfig`), WSL's home directory resolves to the **same** Windows user profile. WSL `~/.hermes/` and Windows `~/AppData/Local/hermes/` are the **same filesystem**. There is only ONE Hermes install — Windows. WSL was just another terminal into it.

**How to confirm**:
```bash
# In WSL: check where ~ resolves to
echo $HOME
# If it shows C:/Users/<user> (not /home/<user>), WSL is using Windows home

# Check if the hermes data is the same
ls $HOME/AppData/Local/hermes/
# If this works from WSL, it's the Windows install
```

**What this means for migration**: There is no second install to migrate from. The profiles, kanban.db, hindsight config, and skills all live on the Windows side and are accessible via both Windows-native paths (`C:\Users\...\AppData\Local\hermes\`) and WSL paths (`/mnt/c/Users/.../AppData/Local/hermes/`).

**When this applies**: Only when `networkingMode=mirrored` is active in `~/.wslconfig`. Without mirrored mode, WSL has a separate Linux home and a separate Hermes install may exist there. Always check `.wslconfig` first.

### Pattern: Migrating Hermes Skills Between WSL and Windows

**Use Case**: Copy skills, configs, cron jobs, or other Hermes data between a WSL and Windows Hermes instance (or between two WSL distros).

**IMPORTANT**: Before migrating, verify whether WSL and Windows share the same Hermes install (see "Single Install" gotcha above). If `networkingMode=mirrored` is active, there's nothing to migrate — it's already the same instance.

**Key Insight**: Skills are self-contained directories under `~/.hermes/skills/` and can be freely copied between Hermes instances. The `\\wsl$` UNC path (or `//wsl$/` from bash/MSYS) provides direct filesystem access from Windows to WSL.

**Quick Reference**:
```bash
# From WSL → Windows:
cp -r ~/.hermes/skills/* /mnt/c/Users/<win-user>/AppData/Local/hermes/skills/

# From Windows (bash/MSYS) → WSL:
cp -r //wsl$/Ubuntu-24.04/home/<wsl-user>/.hermes/skills/* ~/AppData/Local/hermes/skills/
```

**What's safe**: Skills (read-only at runtime).  
**What needs review**: `config.yaml` (providers/paths differ), `.env` (secrets + platform-specific vars), profiles (embedded paths).  
**What doesn't transfer cleanly**: Cron jobs (SQLite-backed), sessions (platform-specific).

Full guide: `references/hermes-skill-migration-wsl-to-windows.md`

---

### Pattern 9: Hindsight API Server (Windows)

**Use Case**: The Hindsight memory API runs as a Windows process (`hindsight-api`) connecting to Windows PostgreSQL. It can crash or be killed, while PG stays up.

**Quick Diagnosis**:
```bash
# From WSL: check API health
curl -s --connect-timeout 5 http://192.168.0.40:8888/health
# If timeout → API process is dead (PG may still be fine)

# Check PG separately:
pg_isready -h localhost -p 5433  # from WSL via mirrored networking
```

**Restart Procedure**: See `references/hindsight-wsl-postgresql.md` for the exact env vars and command. The 4 required env vars are `HINDSIGHT_API_LLM_PROVIDER`, `HINDSIGHT_API_DATABASE_URL`, `HINDSIGHT_API_LLM_API_KEY`, `HINDSIGHT_API_LLM_MODEL`.

**Key Insight**: PG (port 5433) and Hindsight API (port 8888) are independent processes. PG surviving does NOT mean the API is running. Always check both.

**Verified (2026-05-15)**: API crashed while PG stayed healthy. Recovery: restart `hindsight-api` with the 4 env vars. Full details, env var values, and troubleshooting: `references/hindsight-wsl-postgresql.md`

---

## Troubleshooting

### Symptom: "Connection refused" from WSL to Windows

**Quick Test**:
```bash
# From WSL: test raw TCP to Windows vEthernet
python3 -c "import socket; s=socket.socket(); s.settimeout(2); s.connect(('172.25.144.1', 62936)); print('OK'); s.close()"
```

**Diagnosis Flow**:
1. Does Windows service bind to `0.0.0.0` or `127.0.0.1`?
   - `127.0.0.1` only → Need portproxy or reconfigure
2. Windows Firewall blocking?
   - `Get-NetFirewallRule | Where {$_.Enabled -eq "True"}`
3. Portproxy active?
   - `netsh interface portproxy show v4tov4`

**Fix**:
```powershell
# Add firewall exception (vEthernet only, not public!)
New-NetFirewallRule -DisplayName "WSL Bridge" -Direction Inbound `
    -LocalAddress 172.25.144.1 -LocalPort 62936 `
    -Protocol TCP -Action Allow -Enabled True
```

### Symptom: Portproxy created but connections timeout

**Likely Causes**:
- Windows Firewall blocking inbound on that interface
- Service not actually listening on target address/port
- Antivirus/security software intercepting

**Fix**:
```powershell
# Verify service listening
Get-NetTCPConnection -State Listen | Where {$_.LocalPort -eq 62936}

# Check Windows Firewall rule scope
Get-NetFirewallRule -DisplayName "*WSL*" | Get-NetFirewallAddressFilter
```

### Symptom: Port appears free (no process in netstat) but bind fails

**Likely Cause**: Windows HTTP.sys has reserved the port range, or a service bound it with exclusive access.

**Diagnosis**:
```powershell
# Check HTTP.sys reserved URLs
netsh http show urlacl | findstr "9191"

# Check for port reservations
netsh int ipv4 show excludedportrange protocol=tcp
```

**Fix**: Change the application port to one outside reserved ranges. Common working alternatives: 19191, 3000, 5000, 8080, 8888.

**Session Note (2026)**: Port 9191 showed no owner in netstat but `TcpListener` bind failed with "only one usage of each socket address." Port 19191 worked immediately. This is a common Windows issue with no visible process owner. See `references/windows-port-ghost-block.md` for diagnosis commands and fix options.

### Symptom: App listens on port, localhost works, but remote connections time out

**Likely Cause**: Windows Firewall has a **program-specific Block rule** for your exe. This is different from a port-level block — it blocks ALL inbound connections to that exe regardless of port.

**Diagnosis**:
```cmd
:: Check for rules targeting your exe
netsh advfirewall firewall show rule name=all | findstr /i "yourapp"

:: Get full details — look for Action: Block
netsh advfirewall firewall show rule name="yourapp.exe" verbose
```

**Fix** (requires admin):
```cmd
:: Change existing Block rule to Allow
netsh advfirewall firewall set rule name="yourapp.exe" new action=allow
```

**Verified Instance (2026-05-15)**: Agent Persona's `agent-persona.exe` was listening on port 8080, localhost curl returned `{"status":"ok"}`, but WSL connections timed out. Windows Firewall had `Action: Block` rules for the exe (both TCP and UDP). Changing to `Allow` fixed it.

**Key Insight**: Always check BOTH port-level AND program-specific firewall rules. `netstat` showing LISTENING + localhost working does NOT mean remote access works. See `references/windows-port-ghost-block.md` for full details.

### Symptom: Works after restart then stops

**Likely Cause**: WSL IP changed on restart (DHCP)

**Solutions**:
1. Update portproxy dynamically:
```bash
WSL_IP=$(hostname -I | awk '{print $1}')
powershell.exe -Command "netsh int portproxy set v4tov4 listenport=62937 connectaddress=$WSL_IP"
```

2. Use SSH tunnel (recommended — doesn't depend on IP)

### Symptom: PowerShell `--version` flag parsed as expression

**Cause**: PowerShell treats `--` as the stop-parsing operator, not a flag prefix.

**Fix**: Use `&` to invoke the command:
```powershell
& "C:\\Program Files\\PostgreSQL\\18\\bin\\pg_ctl" --version
```

---

## Tauri App Development (Windows target, WSL dev)

### Building Tauri Apps from WSL

Tauri requires a Windows toolchain and cannot build in WSL directly. See `references/tauri-build-from-wsl.md` for the full build/deploy pattern including:
- Copying project to Windows-native paths (avoids UNC path issues with WiX)
- Clearing `beforeBuildCommand` when building from copied paths
- Using `x86_64-pc-windows-msvc` target
- MSI install with admin elevation
- JSON POST testing via `curl.exe -d @file`

**Key points**:
- Write a `.bat` build script to Windows temp, execute via `cmd.exe /c`
- Always use `cd /d` as the first command (UNC path rejection from WSL)
- Kill running exe before deploying (`taskkill /F /IM app.exe`)
- `cargo tauri build` handles cross-compilation automatically

### Key Insights from Session (2026-05-16)

**Agent Persona Tauri App Development**:
- CSS `pointer-events` is superior to OS-level `set_ignore_cursor_events` for desktop overlays
 → Container: `pointer-events: none`, Children: `pointer-events: auto`
 → Background click-through but UI remains fully interactive
- Cursor following: smooth interpolation at 0.04 speed (faster than wandering 0.006)
- MSI bundling may only include one binary - verify both `app.exe` and `webhook_server.exe`
- Always build from Windows-native paths to avoid UNC issues with WiX `light.exe`
- `beforeBuildCommand` must be empty when building from copied paths (npm UNC issues)

### Tauri Desktop Overlay Patterns

For desktop overlay apps (pets, widgets, etc.), use CSS-level click-through instead of OS-level `set_ignore_cursor_events`. See `references/tauri-desktop-overlay-patterns.md` for the full pattern including cursor following.

**Key principle**: `pointer-events: none` on container + `pointer-events: auto` on children = background is click-through but UI elements remain interactive.

> **Note (2026-05-16)**: The Agent Persona project is moving from Tauri+Svelte to pure Rust egui (eframe) to eliminate the browser entirely. The Tauri patterns above are kept for reference but the active architecture is egui. See `references/agent-persona-v2-egui-plan.md` for the rewrite plan.

---

## Configuration File Handling

### Paths

| File | Windows Path | WSL Path |
|------|-------------|----------|
| AionUI Config | `%APPDATA%\\AionUi\\webui.config.json` | `/mnt/c/Users/<user>/AppData/Roaming/AionUi/webui.config.json` |
| AionUI Preferences | `%APPDATA%\\AionUi\\Preferences` | `/mnt/c/Users/<user>/AppData/Roaming/AionUi/Preferences` |
| AionUI Local | `%LOCALAPPDATA%\\AionUi\\` | `/mnt/c/Users/<user>/AppData/Local/AionUi/` |

### WSL Path Translation

```bash
# Windows → WSL: C:\\Users\\name\\file → /mnt/c/Users/name/file
# WSL → Windows: /mnt/c/Users/name/file → C:\\Users\\name\\file

# Python example
def wsl_to_win(path):
    return path.replace('/mnt/c/', 'C:/').replace('/', '\\')
def win_to_wsl(path):
    return path.replace('C:\\', '/mnt/c/').replace('\\', '/')
```

---

## Supabase + Vercel + Prisma Connectivity

When a Next.js app on Vercel can't connect to Supabase PostgreSQL (IPv6 routing issues from WSL2 or Vercel serverless), the fix is to use the Supabase pooler — not to migrate to a different database provider. See `references/supabase-vercel-prisma-connectivity.md` for the full guide.

**TL;DR**: Use `aws-1-us-west-1.pooler.supabase.com:6543` with `pgbouncer=true`, `PrismaPg` adapter, and sequential ops instead of `$transaction`. Stay on Supabase; don't split across Neon + Supabase.

---

## Quick Reference: AionUI Setup

> **AionUI internal architecture** (config format, pet system, agent registry, ACP protocol, database): See `references/aionui-internal-architecture.md`. Key insight: the main config is stored as base64→URL-encoded JSON in `config/aionui-config.txt`, NOT plain JSON.

### Scenario: AionUI on Windows, MCP tools in WSL

> **Agent Persona v2 egui rewrite**: See `references/agent-persona-v2-egui-plan.md` for the full rewrite plan from Tauri+Svelte to pure Rust egui. The egui approach uses per-pet OS windows with WS_EX_TRANSPARENT instead of CSS pointer-events.

```powershell
# Windows (Admin PowerShell)
# 1. Find WSL gateway IP
Get-NetIPAddress | Where {$_.InterfaceAlias -like "*vEthernet (WSL)*"}

# 2. Add portproxy (e.g., gateway is 172.25.144.1)
netsh int portproxy add v4tov4 listenaddr=172.25.144.1 listenport=62936 connectaddr=127.0.0.1 connectport=62936

# 3. Add firewall exception
New-NetFirewallRule -DisplayName "AionUI Bridge" -Direction Inbound -LocalAddress 172.25.144.1 -LocalPort 62936 -Protocol TCP -Action Allow

# 4. Restart AionUI (it should bind to 127.0.0.1:62936)
```

```bash
# WSL: Configure MCP server to use Windows endpoint
# In AionUI MCP config or ~/.hermes/etc/mcp.json
{
  "mcpServers": {
    "my-tool": {
      "command": "python3",
      "args": ["mcp_server.py", "--endpoint", "http://172.25.144.1:62936"]
    }
  }
}
```

### Persistent SSH Tunnel (Recommended)

```bash
# WSL ~/.config/systemd/user/aionui-ssh-tunnel.service
[Unit]
Description=AionUI SSH Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/ssh -L 62936:127.0.0.1:62936 -o ServerAliveInterval=30 -N user@192.168.0.40
Restart=always
RestartSec=10

[Install]
WantedBy=default.target

# Enable and start
systemctl --user enable aionui-ssh-tunnel
systemctl --user start aionui-ssh-tunnel
```

---

## DaemonCore-Specific Build Notes

For DaemonCore-specific Tauri build issues and patterns, see:
[`references/daemoncore-tauri-build-notes.md`](references/daemoncore-tauri-build-notes.md)
For general Tauri cross-compilation from WSL, see the `tauri-desktop-apps` skill.



Key issues encountered:
- **Resource.lib permission error**: Build on Linux fs (`CARGO_TARGET_DIR=/tmp/...`) to avoid 9p issues
- **MenuBuilder API**: No `.append()` — use `.separator()` and `.item()`
- **Tray icon**: Load from .ico file, not raw RGBA bytes
- **Eye tracking through click-through**: Use Rust-side `cursor_position()` + Tauri events
- **Container background**: `rgba(0,0,0,0.01)` captures mouse events; `transparent` does not
- **Window maximizing**: Use `window.maximize()`, remove fixed dimensions from config
- **Delegate task timeout**: 600s default is too short for Tauri builds (3-5+ min)



- [ ] Windows service listening on correct address/port (`Get-NetTCPConnection -State Listen`)
- [ ] Portproxy rule active and correct (`netsh interface portproxy show v4tov4`)
- [ ] Windows Firewall rule exists for port/interface
- [ ] **Windows Firewall does NOT have a Block rule for the exe itself**
- [ ] No conflicting public-profile firewall rules
- [ ] WSL can ping Windows vEthernet IP
- [ ] Raw TCP test from WSL succeeds (`python3 -c "import socket; ..."`)
- [ ] WSL IP hasn't changed (if using IP-based forwarding)
- [ ] AionUI configured to bind to `127.0.0.1` (default) or `0.0.0.0` (for remote)

---

## Best Practices

1. **Prefer SSH tunnels** for production — reliable, encrypted, auto-reconnect
2. **Limit firewall exceptions** to specific interfaces (vEthernet, not Public)
3. **Use `0.0.0.0` for services** that need cross-boundary access
4. **Document IP dependencies** — WSL IPs change, Windows IPs may change
5. **Test raw TCP** before debugging application layers
6. **Monitor with `netstat`** on both sides (`Get-NetTCPConnection` on Windows)
7. **Avoid localhost assumptions** in cross-platform configs
8. **Use webui.config.json** for AionUI remote access (not command-line args for persistence)
9. **Never hardcode ports in Tauri apps** — use configurable settings with sensible defaults
10. **Check both port-level AND program-specific firewall rules** when debugging connectivity
11. **Delete stale `postmaster.pid`** when migrating PG data directories between systems
12. **Use `&` to invoke exe paths in PowerShell** — `--` is parsed as stop-parsing operator, not a flag
13. **Fix `dynamic_shared_memory_type`** when migrating PG data from Linux to Windows: change `posix` to `windows` in `postgresql.conf`
14. **Handle port conflicts** when both WSL and Windows PG instances exist — change one to a different port (e.g., 5433)
15. **Reset user passwords after migration** — passwords may not match your connection strings even though roles carry over
16. **Install `pgvector` on Windows PG if the migrated database uses vector columns (e.g., Hindsight's memory_units table).
17. **Avoid running two PG instances simultaneously**
18. **`\\wsl$` UNC paths are unreliable from Windows PowerShell** — always use `/mnt/c/` from WSL and `C:\` from Windows to transfer files between the two environments.
19. **WSL9P directory metadata corruption** — see `references/wsl9p-directory-corruption-fix.md`
19. **Hindsight API and PG are independent processes** — always check both when diagnosing memory tool failures. API on 8888, PG on 5433.
20. **PowerShell `$` variable stripping** — when calling `powershell.exe -Command "..."` from WSL, the shell strips `$` variables. Always write `.ps1` files to a Windows path and use `-File` instead. See `references/powershell-dollar-stripping.md`.
22. **Tauri/cross-compiled builds must run from Windows-native paths** — WiX `light.exe`, `msiexec`, and other Windows tools reject UNC paths. See `references/tauri-build-from-wsl.md`.
23. **MSI bundling may not include all binaries** — verify MSI contents after build.
25. **`tauri build` appears silent/hung in background** — Rust cross-compilation takes 5-15 min with buffered stdout. Use `notify_on_complete=true` or run in foreground with `timeout`.
26. **Windows services invisible from WSL `ps`** — `ps aux` in WSL only shows Linux processes. See `references/windows-process-management-from-wsl.md`.
27. **Reading Windows files with spaces from WSL** — Use `cat` via `terminal()` with double-quoted paths instead of `read_file`.
28. **ComfyUI file layout** — See the `comfyui` skill for full path tables.
25. **`cargo check` passing ≠ working binary** — Always verify the `.exe` exists and launches.

---

## Session Notes: AionUI Bridge (2026)

**Problem**: `netsh portproxy` forwarding Windows 0.0.0.0:62937 → WSL 172.25.150.25:62936 was created but **Windows Firewall blocked inbound connections** to port 62937 from the vEthernet interface, causing timeouts.

**Root Cause**: Portproxy uses Windows interfaces, but Windows Firewall by default blocks all inbound connections except established/related traffic on non-loopback interfaces. The vEthernet (172.25.144.1) is treated as a separate network segment.

**Fix Applied**:
1. Added firewall exception for vEthernet interface specifically (not Public!):
   ```powershell
   New-NetFirewallRule -DisplayName "AionUI Bridge" -Direction Inbound -LocalAddress 172.25.144.1 -LocalPort 62936 -Protocol TCP -Action Allow
   ```
2. Changed portproxy to use 127.0.0.1 instead of 0.0.0.0:
   ```powershell
   netsh interface portproxy delete v4tov4 listenport=62937
   netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=62937 connectaddress=172.25.150.25 connectport=62936
   ```
3. Verified WSL can reach Windows vEthernet IP (172.25.144.1) but couldn't reach AionUI port due to Windows Firewall → added exception

**Current State**: AionUI running on Windows 127.0.0.1:62936, portproxy forwarding Windows 127.0.0.1:62937 → WSL 172.25.150.25:62936, firewall exceptions in place. SSH tunnel (Pattern 4) is recommended alternative for reliability.
