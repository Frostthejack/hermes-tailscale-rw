# PowerShell Dollar-Sign ($) Stripping When Called from WSL

## Problem

When calling PowerShell from WSL via `powershell.exe -Command "..."`, the shell strips `$` variables before PowerShell sees them:

```bash
# BROKEN: $pid gets stripped by the shell
powershell.exe -Command "Get-Process | Where-Object {$_.ProcessName -match 'foo'}"
# Error: Cannot overwrite variable PID because it is read-only or constant
```

This affects ALL PowerShell calls from WSL, not just process enumeration.

## Root Cause

The WSL shell (bash/zsh) interprets `$` as shell variable expansion. Even with single quotes, the WSL→Windows boundary can mangle the string.

## Solution: Always Use Script Files

**Never pass complex PowerShell commands inline.** Write to a `.ps1` file and use `-File`:

```bash
# From WSL: write the script to a Windows path
cat > /mnt/c/Users/$WINUSER/AppData/Local/Temp/myscript.ps1 << 'PS1'
Get-Process | Where-Object {$_.ProcessName -match 'foo'} |
    Select-Object ProcessName, Id, MainWindowTitle |
    Format-Table -AutoSize
PS1

# Execute it
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Users\$WINUSER\AppData\Local\Temp\myscript.ps1"
```

## When You Must Use Inline Commands

For very simple commands, use single quotes and escape carefully:

```bash
# Simple commands work with single quotes
powershell.exe -NoProfile -Command 'Get-Date'
powershell.exe -NoProfile -Command 'Write-Host "hello"'
```

But as soon as you need `$` variables, loops, or complex expressions, switch to a script file.

## Common Patterns

### Process enumeration
```powershell
# myscript.ps1
Get-Process | Where-Object {$_.ProcessName -match 'webhook|app'} |
    Select-Object ProcessName, Id
```

### Window enumeration
```powershell
# windows.ps1
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class WinAPI {
    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
"@
$callback = [WinAPI+EnumWindowsProc]{
    $hWnd = $args[0]
    $sb = New-Object System.Text.StringBuilder 256
    [WinAPI]::GetWindowText($hWnd, $sb, 256) | Out-Null
    $title = $sb.ToString()
    $visible = [WinAPI]::IsWindowVisible($hWnd)
    if ($title -and $visible) { Write-Host $title }
    return $true
}
[WinAPI]::EnumWindows($callback, [IntPtr]::Zero) | Out-Null
```

### JSON API testing
```powershell
# api-test.ps1
$body = '{"agent":"hermes","status":"working","task":"test","profile":"reviewer","timestamp":"2026-01-01T00:00:00"}'
$body | Out-File "C:\Users\luned\AppData\Local\Temp\body.json" -Encoding utf8
curl.exe -s -X POST http://127.0.0.1:9191/webhooks/status -H "Content-Type: application/json" -d "@C:\Users\luned\AppData\Local\Temp\body.json"
```
