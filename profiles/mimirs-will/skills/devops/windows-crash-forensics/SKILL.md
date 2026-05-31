---
name: windows-crash-forensics
description: "Diagnose Windows crashes, unexpected shutdowns, BSODs, and hardware issues from WSL or remote access. Query Windows Event Logs, crash dumps, thermal data, and hardware error records using PowerShell from Linux."
version: 1.0.0
author: OWL
license: MIT
metadata:
  hermes:
    tags: [forensics, windows, wsl, crash, debugging, system-administration]
---

# Windows Crash Forensics

## Overview

Diagnose unexpected shutdowns, BSODs, thermal events, and application crashes on a Windows host — accessed from WSL or another Linux environment. Uses `powershell.exe` calls to query the Windows Event Log, WMI, and crash dump directories.

## When to Use

- User reports their computer "crashed", "froze", "restarted unexpectedly", or "blue-screened"
- Investigating system instability or hangs
- Checking for hardware issues (thermal throttling, memory errors, disk problems)
- Remote diagnostics when user can't access Windows UI (e.g., WSL-only session)

## Key Event IDs

| Event ID | Log | Meaning |
|----------|-----|---------|
| **41** | System | Rebooted without cleanly shutting down (unexpected shutdown/crash) |
| **6008** | System | Previous shutdown was unexpected (records the time) |
| **1074** | System | Clean shutdown/restart initiated by user or process |
| **1076** | System | User-initiated restart after crash |
| **37** | System | Processor speed limited by firmware (thermal/power throttling) |
| **1001** | System | BugCheck event (BSOD details) |
| **18-20** | System | WHEA hardware errors (CPU, memory, PCIe errors) |
| **1000** | Application | Application fault/crash |
| **1002** | Application | Application hang |

## Diagnostic Flow

### 1. Confirm the Crash (Event 41/6008)

```python
subprocess.run(['powershell.exe', '-Command',
    'Get-WinEvent -FilterHashtable @{LogName="System"; Id=41,6008; StartTime=(Get-Date).AddHours(-48)} -MaxEvents 20 | Sort-Object TimeCreated | Format-List TimeCreated, Id, Message'],
    capture_output=True, text=True, timeout=20)
```

- Event 6008 tells you the **exact time** of the unexpected shutdown
- Event 41 appears on the **next boot** after the crash

### 2. Check for BSOD (BugCheck)

```python
subprocess.run(['powershell.exe', '-Command',
    'Get-WinEvent -FilterHashtable @{LogName="System"; Id=1001; StartTime=(Get-Date).AddHours(-48)} -MaxEvents 10 | Format-List TimeCreated, Message'],
    capture_output=True, text=True, timeout=20)
```

If no BugCheck event, the crash was likely **not a BSOD** — could be power loss, thermal shutdown, or hard hang.

### 3. Thermal Throttling Detection (Event 37)

```python
subprocess.run(['powershell.exe', '-Command',
    'Get-WinEvent -FilterHashtable @{LogName="System"; Id=37,38,39,40; StartTime=(Get-Date).AddHours(-72)} -MaxEvents 30 | Sort-Object TimeCreated | Format-List TimeCreated, LevelDisplayName, Message'],
    capture_output=True, text=True, timeout=20)
```

**Key interpretation:**
- "being limited by system firmware" = thermal or power throttling
- "has been in this reduced performance state for **86399 seconds**" = throttling for **24 hours** — serious chronic cooling issue
- If throttling lasted >1 hour before a crash, thermal shutdown is the likely cause
- The `Microsoft-Windows-Kernel-Power/Thermal-Operational` log (if populated) has more detail; check with `Get-WinEvent -ListLog *Thermal*`

### 4. Hardware Errors (WHEA)

```python
subprocess.run(['powershell.exe', '-Command',
    'Get-WinEvent -FilterHashtable @{LogName="System"; Id=18,19,20,47; StartTime=(Get-Date).AddHours(-72)} -MaxEvents 20 | Format-List TimeCreated, Id, Message'],
    capture_output=True, text=True, timeout=20)
```

WHEA events indicate CPU machine-check exceptions, memory errors, or PCIe errors — hardware-level failures.

### 5. Check Crash Dumps

```bash
# List Windows crash dumps with timestamps
ls -la --time-style=full-iso /mnt/c/Users/$WINDOWS_USER/AppData/Local/CrashDumps/ 2>/dev/null
ls -la --time-style=full-iso /mnt/c/Windows/Minidump/ 2>/dev/null

# Check for full memory dump
ls -la /mnt/c/Windows/MEMORY.DMP 2>/dev/null
```

- If `MEMORY.DMP` exists → BSOD occurred. Analyze with WinDbg or `python-evtx`.
- If `Minidump/` has `.dmp` files → bugcheck dumps
- `CrashDumps/` contains **user-mode** application crash dumps (not system crashes)

### 6. Application Crashes Around Crash Time

```python
subprocess.run(['powershell.exe', '-Command',
    'Get-WinEvent -FilterHashtable @{LogName="Application"; Level=1,2; StartTime=(Get-Date).AddHours(-48)} -MaxEvents 30 | Sort-Object TimeCreated | Format-List TimeCreated, ProviderName, Message'],
    capture_output=True, text=True, timeout=20)
```

### 7. Reliability Monitor

```python
subprocess.run(['powershell.exe', '-Command',
    'Get-CimInstance -ClassName Win32_ReliabilityRecords | Where-Object { $_.TimeGenerated -gt (Get-Date).AddHours(-48) } | Sort-Object TimeGenerated | Select-Object -First 20 | Format-List TimeGenerated, SourceName, Message'],
    capture_output=True, text=True, timeout=20)
```

Provides a high-level view of software installs, failures, and Windows updates around the crash time.

## Common Crash Patterns

| Pattern | Likely Cause | Evidence |
|---------|-------------|----------|
| Event 41 + no BugCheck + no dump | Power loss or thermal shutdown | Clean crash, no BSOD data |
| Event 41 + BugCheck 1001 | BSOD | BugCheck event + MEMORY.DMP or minidump |
| Event 37 (prolonged throttling) → Event 41 | Thermal emergency shutdown | 37 warning for hours before crash |
| WHEA errors → Event 41 | Hardware failure | Event 18/19/20 before crash |
| Application crash → Event 41 | Driver or app causing BSOD | App crash logged just before Event 41 |
| Event 6008 time matches Event 37 spike | Confirmed thermal | Throttled CPU → firmware shutdown |

## Tips

- Windows Event Log timestamps are in **local time** for the Windows host. WSL may show different times if TZ differs.
- Event ID 37 duration is in **seconds**. 86,399 = 24h of throttling.
- If the `Kernel-Power/Thermal-Operational` log has 0 records, the thermal event was handled entirely by firmware (BIOS/EC), not Windows.
- `postmaster.pid` permission denied errors in Application log are **PostgreSQL related**, not crash-related — ignore for crash forensics.
- To find the Windows username for path resolution: `ls /mnt/c/Users/`
