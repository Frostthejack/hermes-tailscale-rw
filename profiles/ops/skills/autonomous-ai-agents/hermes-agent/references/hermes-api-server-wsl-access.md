# Hermes API Server — WSL2 Windows Access Guide

## Problem Statement

When Hermes runs inside WSL2 and the API server is enabled, accessing it from **Windows PowerShell** (or any Windows application) requires understanding the WSL2 networking model.

## Network Topology

```
Windows Host (192.168.0.40)
  |
  +-- WSL2 VM (172.25.144.x, NAT'd)
       |
       +-- Hermes Gateway (systemd user service)
            |
            +-- API Server (127.0.0.1:62936 or 8642)
```

## Access Patterns

### 1. From Windows PowerShell → WSL API Server

**What works:**
```powershell
# Use 127.0.0.1 (not localhost)
curl http://127.0.0.1:62936/v1/models
```

**Why:** WSL2 sets up a portproxy that forwards `127.0.0.1` on Windows to the WSL2 VM's `127.0.0.1`.

**What doesn't work:**
- Using the WSL2 IP directly (e.g., `172.25.144.1:62936`) without Windows Firewall exceptions
- Using `localhost` (sometimes resolves differently on Windows)

### 2. From WSL → Hermes API Server

**Always works:**
```bash
curl http://127.0.0.1:62936/v1/models
# or
curl http://localhost:62936/v1/models
```

### 3. From Windows Browser → Hermes API Server

```
http://127.0.0.1:62936/docs  # If API server serves docs
```

## Configuration Checklist

### In WSL (Hermes `.env`):
```bash
API_SERVER_ENABLED=true
API_SERVER_PORT=62936
API_SERVER_HOST=127.0.0.1  # Or 0.0.0.0 to bind to all interfaces
```

### If Binding to `0.0.0.0` (All Interfaces):

**Note:** Binding to `0.0.0.0` makes the API server accessible from:
- WSL localhost (`127.0.0.1`)
- Windows host (via portproxy)
- Other machines on your LAN (if firewall allows)

```bash
API_SERVER_HOST=0.0.0.0
```

**Security:** Only do this if you have firewall rules restricting access to the port.

## Portproxy Bridge (Alternative Method)

If `127.0.0.1` forwarding isn't working (common after WSL updates):

### Setup Portproxy
```powershell
# Run as Administrator
netsh interface portproxy add v4tov4 listenport=62936 listenaddress=0.0.0.0 connectport=62936 connectaddress=127.0.0.1
```

### Verify
```powershell
netsh interface portproxy show all
```

### Remove
```powershell
netsh interface portproxy delete v4tov4 listenport=62936 listenaddress=0.0.0.0
```

## Troubleshooting

### Issue: "Connection Refused" from Windows

**Check 1:** Is the API server running in WSL?
```bash
hermes status
# or
grep "API server listening" ~/.hermes/logs/gateway.log
```

**Check 2:** Is it bound to the right address?
```bash
ss -tlnp | grep 62936
# Should show: LISTEN on 127.0.0.1:62936 or 0.0.0.0:62936
```

**Check 3:** Can WSL reach it?
```bash
curl http://127.0.0.1:62936/v1/models
```

**Check 4:** Is Windows Firewall blocking?
```powershell
# Check vEthernet (WSL) firewall rules
Get-NetFirewallRule | Where-Object {$_.DisplayName -like "*WSL*" -or $_.DisplayName -like "*vEthernet*"}
```

### Issue: Works in WSL but Not Windows

**Likely cause:** Windows Firewall blocking the `vEthernet (WSL)` interface.

**Fix:**
```powershell
# Add firewall rule (Run as Administrator)
New-NetFirewallRule -DisplayName "WSL Hermes API" `
  -Direction Inbound `
  -LocalPort 62936 `
  -Protocol TCP `
  -Action Allow `
  -Profile Private
```

### Issue: Port Already in Use

**Find the process:**
```powershell
# Windows
Get-Process -Id (Get-NetTCPConnection -LocalPort 62936).OwningProcess

# WSL
lsof -i :62936
```

### Issue: Intermittent Connection

WSL2 VM may have been stopped. Check:
```powershell
wsl --status
wsl -l -v
```

Restart WSL:
```powershell
wsl --shutdown
wsl -d Ubuntu  # or your distro
```

## Hindsight Service Note

In this environment, Hindsight runs on Windows at `192.168.0.40:8888`.

**From WSL cannot use `localhost:8888`** — must use the Windows host IP:

```bash
curl http://192.168.0.40:8888/v1/default/banks/hermes/memories/
```

**Why:** `localhost` in WSL refers to the WSL2 VM, not the Windows host.

## Summary

| Access Path | Address to Use | Notes |
|-------------|----------------|-------|
| Windows → WSL API | `127.0.0.1:62936` | Works via portproxy |
| WSL → WSL API | `127.0.0.1:62936` | Always works |
| Windows → Hindsight | `192.168.0.40:8888` | Use Windows host IP from WSL |
| Network → WSL API | `172.25.144.x:62936` | Needs firewall rules + `API_SERVER_HOST=0.0.0.0` |
