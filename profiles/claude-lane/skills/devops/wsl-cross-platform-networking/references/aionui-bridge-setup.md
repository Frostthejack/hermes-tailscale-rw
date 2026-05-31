# AionUI Bridge Setup - Reference Guide

## Problem Summary
AionUI (Windows Electron app) listening on `127.0.0.1:62936` (Windows loopback)   
WSL2 needs to connect to AionUI MCP tools   
Windows 10 lacks WSL2 localhost forwarding (no `localhost` alias)

## Quick Setup Commands

### Step 1: Configure AionUI (Windows)

```json
// %APPDATA%\AionUi\webui.config.json
{
  "server": {
    "host": "0.0.0.0",
    "port": 62936,
    "allowRemote": true
  },
  "mcp": {
    "port": 57978,
    "allowRemote": true
  },
  "webui": {
    "port": 25809
  }
}
```

Restart AionUI after saving config.

### Step 2: Windows Firewall Exception (Admin PowerShell)

```powershell
# Allow inbound on WSL vEthernet interface (Windows side)
New-NetFirewallRule `
  -DisplayName "AionUI WSL Bridge" `
  -Direction Inbound `
  -LocalAddress 172.25.144.1 `
  -LocalPort 62936 `
  -Protocol TCP `
  -Action Allow `
  -Enabled True

# (Optional) Allow MCP port too
New-NetFirewallRule `
  -DisplayName "AionUI MCP Bridge" `
  -Direction Inbound `
  -LocalAddress 172.25.144.1 `
  -LocalPort 57978 `
  -Protocol TCP `
  -Action Allow `
  -Enabled True
```

### Step 3: PortProxy Forwarding (Admin PowerShell)

**Option A: vEthernet-based forwarding** (WSL connects to 172.25.144.1)

```powershell
netsh interface portproxy delete v4tov4 listenport=62937
netsh interface portproxy add v4tov4 `
  listenaddress=172.25.144.1 `
  listenport=62936 `
  connectaddress=127.0.0.1 `
  connectport=62936
```

**Option B: Loopback forwarding** (for Windows-side access)

```powershell
netsh interface portproxy delete v4tov4 listenport=62937
netsh interface portproxy add v4tov4 `
  listenaddress=127.0.0.1 `
  listenport=62937 `
  connectaddress=172.25.150.25 `
  connectport=62936
```

### Step 4: Connect from WSL

```bash
# Test connectivity
curl http://172.25.144.1:62936

# Use with AionUI MCP tools
# Configure MCP endpoint to http://172.25.144.1:62936
```

## Alternative: SSH Tunnel (Recommended)

```powershell
# Windows (Admin PowerShell) - Enable SSH server
Add-WindowsCapability -Online -Name OpenSSH.Server
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
```

```bash
# WSL - Create persistent tunnel
ssh-keygen -t ed25519 -f ~/.ssh/aionui_id -N ""
# Copy public key to Windows: ~/.ssh/aionui_id.pub → Windows ~/.ssh/authorized_keys

# Connect tunnel
ssh -L 62936:127.0.0.1:62936 -o ServerAliveInterval=30 -N -f username@192.168.0.40

# Now use localhost:62936 from WSL
curl http://localhost:62936
```

## Troubleshooting

### Issue: Connection timeout from WSL

```bash
# Test 1: Can WSL reach Windows vEthernet?
ping -c 2 172.25.144.1

# Test 2: Is portproxy active?
powershell.exe -Command "netsh interface portproxy show v4tov4"

# Test 3: Is service listening?
powershell.exe -Command "Get-NetTCPConnection -State Listen | Where {\$_.LocalPort -eq 62936}"

# Test 4: Is firewall blocking?
powershell.exe -Command "Get-NetFirewallRule | Where {\$_.Enabled -eq 'True' -and \$_.Direction -eq 'Inbound'} | Format-Table Name, Enabled, Direction"
```

### Issue: Firewall exception disappears

Windows may auto-remove rules. Make persistent:

```powershell
# Check rule profile
Get-NetFirewallRule -DisplayName "*AionUI*" | Get-NetFirewallAddressFilter

# Ensure it applies to Domain/Private (not just Public)
Set-NetFirewallRule -DisplayName "AionUI WSL Bridge" -Profile Domain,Private
```

### Issue: WSL IP changes after restart

```bash
# Quick fix: Update portproxy dynamically
WSL_IP=$(hostname -I | awk '{print $1}')
powershell.exe -Command "netsh int portproxy delete v4tov4 listenport=62936" 2>/dev/null
powershell.exe -Command "netsh int portproxy add v4tov4 listenaddr=172.25.144.1 listenport=62936 connectaddr=127.0.0.1 connectport=62936"

# Better: Use SSH tunnel which doesn't depend on specific IPs
```

### Issue: "Access denied" on portproxy commands

```powershell
# Must run PowerShell as Administrator
# Right-click PowerShell → "Run as administrator"
```

## Path Translations

```bash
# AionUI config (WSL path)
/mnt/c/Users/luned/AppData/Roaming/AionUi/webui.config.json

# AionUI config (Windows path)
C:\Users\luned\AppData\Roaming\AionUi\webui.config.json

# AionUI process check (PowerShell)
Get-Process AionUi | Select-Object Id, Path
```

## Verification Checklist

- [x] AionUI running on Windows (`Get-Process AionUi`)
- [x] AionUI listening on `127.0.0.1:62936` (Windows)
- [x] Firewall exception for `172.25.144.1:62936` (Windows)
- [x] Portproxy rule active (`netsh interface portproxy show v4tov4`)
- [x] WSL can ping `172.25.144.1` (`ping -c 2 172.25.144.1`)
- [x] WSL can connect via TCP (`python3 -c "import socket; s=socket.socket(); s.connect(('172.25.144.1', 62936)); print('OK')"`)
- [x] MCP endpoint configured correctly

## Common Pitfalls

1. **AionUI binds to `127.0.0.1` only** → Add `webui.config.json` with `"host": "0.0.0.0"`
2. **Firewall blocking all non-localhost** → Add explicit firewall rule for vEthernet
3. **Portproxy uses `0.0.0.0`** → This exposes to all Windows interfaces; restrict to `172.25.144.1` for security
4. **WSL IP changes** → Script dynamic updates or use SSH tunnel
5. **Antivirus interference** → Temporarily disable to test
6. **Windows Defender Firewall profile = Public** → Private profile rules don't apply; switch network to Private

## Session History

- 2026-05-04: Initial portproxy setup (0.0.0.0:62937 → 172.25.150.25:62936)
- 2026-05-04: Firewall exceptions added for vEthernet interface
- 2026-05-04: AionUI configured for remote access via webui.config.json
- 2026-05-04: SSH tunnel pattern documented as recommended alternative
