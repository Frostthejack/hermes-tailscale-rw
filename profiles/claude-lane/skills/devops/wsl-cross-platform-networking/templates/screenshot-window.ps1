# Capture a specific window by title (partial match)
# Usage: Edit $windowTitle below, then run from WSL:
#   cp templates/screenshot-window.ps1 /mnt/c/Users/<user>/AppData/Local/Temp/screenshot-window.ps1
#   powershell.exe -File "C:\Users\<user>\AppData\Local\Temp\screenshot-window.ps1"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$windowTitle = "Agent Persona"  # Change this to target window title (partial match)

# Find the window
$targetProcess = Get-Process | Where-Object { $_.MainWindowTitle -like "*$windowTitle*" } | Select-Object -First 1

if (-not $targetProcess) {
    Write-Host "Window with title containing '$windowTitle' not found"
    exit 1
}

$hwnd = $targetProcess.MainWindowHandle
Write-Host "Found window: $($targetProcess.MainWindowTitle) (handle: $hwnd)"

# P/Invoke to bring window to foreground
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32 {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

[Win32]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 500

$rect = New-Object Win32+RECT
[Win32]::GetWindowRect($hwnd, [ref]$rect)

$width = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top
Write-Host "Window rect: $($rect.Left),$($rect.Top) - $($rect.Right),$($rect.Bottom) (${width}x${height})"

if ($width -le 0 -or $height -le 0) {
    Write-Host "Invalid window dimensions"
    exit 1
}

$bitmap = New-Object System.Drawing.Bitmap($width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($rect.Left, $rect.Top, [System.Drawing.Point]::Empty, $bitmap.Size)

$outPath = "C:\Users\luned\Desktop\screenshot-window.png"
$bitmap.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
Write-Host "Window screenshot saved to $outPath"
