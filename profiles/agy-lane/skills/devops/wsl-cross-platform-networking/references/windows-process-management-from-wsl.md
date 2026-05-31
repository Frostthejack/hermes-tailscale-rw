# Windows Process Management from WSL

## Problem

WSL `ps`, `top`, `htop` only show Linux processes. Windows-hosted processes (python.exe running ComfyUI, node.exe, etc.) are invisible. Similarly, `tasklist` and `taskkill` are Windows commands not available in WSL.

## Solution: PowerShell from WSL

### Discover Processes

```bash
# List all python.exe processes on Windows
powershell.exe -Command "Get-Process python -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, @{Name='CmdLine';Expression={(Get-CimInstance Win32_Process -Filter \"ProcessId=$($_.Id)\").CommandLine}}"
```

This returns PID, process name, and full command line — enough to identify which process is which.

### Check if a Port is in Use

```bash
# Quick HTTP health check (works from WSL to Windows localhost)
curl -s -o /dev/null -w "%{http_code}" http://localhost:8188/
# 200 = something is serving on that port (process is alive)
# 000/connection refused = nothing listening
```

**Important:** A port responding on localhost from WSL means the service is running on **Windows** (via WSL2 mirrored networking or portproxy). Do NOT assume it's a WSL service.

### Kill a Process

```bash
# Kill by PID
powershell.exe -Command "Stop-Process -Id <PID> -Force; Write-Output 'Killed'"

# Kill by name (all matching processes)
powershell.exe -Command "Stop-Process -Name python -Force; Write-Output 'Killed all python'"
```

### Check Windows Service Status

```bash
# Check if a Windows service is running
powershell.exe -Command "Get-Service -Name <ServiceName> | Select-Object Status, StartType"

# Start/Stop a Windows service
powershell.exe -Command "Start-Service -Name <ServiceName>"
powershell.exe -Command "Stop-Service -Name <ServiceName> -Force"
```

## Common Patterns

### "Is ComfyUI running?"

```bash
# Check port
curl -s -o /dev/null -w "%{http_code}" http://localhost:8188/
# 200 = yes, running

# Find the process
powershell.exe -Command "Get-Process python -ErrorAction SilentlyContinue | Select-Object Id, @{Name='CmdLine';Expression={(Get-CimInstance Win32_Process -Filter \"ProcessId=$($_.Id)\").CommandLine}}" | grep main.py
```

### "Kill and restart ComfyUI"

```bash
# 1. Find PID
powershell.exe -Command "Get-Process python -ErrorAction SilentlyContinue | Select-Object Id, @{Name='CmdLine';Expression={(Get-CimInstance Win32_Process -Filter \"ProcessId=$($_.Id)\').CommandLine}}"

# 2. Kill it
powershell.exe -Command "Stop-Process -Id <PID> -Force"

# 3. Verify port is free
curl -s -o /dev/null -w "%{http_code}" http://localhost:8188/
# Should return 000 or connection refused

# 4. Restart (user runs start_comfyui.bat on Windows)
```

## Pitfalls

- **`$` variable stripping**: When passing PowerShell commands inline via `powershell.exe -Command "..."`, the WSL shell may strip `$` variables. If a command fails with "not recognized", write a `.ps1` file to `/mnt/c/Users/<user>/AppData/Local/Temp/` and run with `powershell.exe -ExecutionPolicy Bypass -File "C:\\Users\\<user>\\AppData\\Local\\Temp\\script.ps1"`.
- **Multiple python.exe processes**: There may be more than one (e.g., ComfyUI + something else). Always check the command line to identify the right PID before killing.
- **`taskkill` not in WSL**: `taskkill` is a Windows CMD command, not available in WSL bash. Use `powershell.exe -Command "Stop-Process"` instead.
- **`tasklist` not in WSL**: Same issue. Use `powershell.exe -Command "Get-Process"` instead.
