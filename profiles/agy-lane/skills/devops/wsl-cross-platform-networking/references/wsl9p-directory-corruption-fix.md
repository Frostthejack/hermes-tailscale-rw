# WSL9P Directory Metadata Corruption — Fix Guide

## Symptom

A directory on the Windows filesystem (accessed from WSL under `/mnt/c/...`) shows `d?????????` in `ls -la` output:

```
d????????? ? ? ? ? ? DaemonCore
```

All WSL tools fail on the path:
- `cd /mnt/c/Users/.../DaemonCore` → "No such file or directory"
- `git -C /mnt/c/.../DaemonCore status` → "failed to stat"
- `rmdir` → "Directory not empty" (hits the real NTFS dir)
- `Remove-Item` in PowerShell → NullReferenceException

But the directory is **perfectly fine** on the Windows side — all files intact, accessible via PowerShell.

## Root Cause

WSL2 uses the 9P protocol to access Windows filesystems. Directory metadata (permissions, timestamps) is cached by the 9P driver. If a `mv` operation was previously performed across the WSL/Windows boundary (e.g., `mv /mnt/c/.../dir /mnt/c/.../otherdir`), the 9P metadata can become permanently corrupted while the underlying NTFS directory entry remains valid.

## Fix Procedure (No WSL Shutdown Needed)

The key insight: WSL caches directory metadata by path. Renaming the directory from Windows forces a fresh lookup.

### Step 1: User renames the directory in Windows

Have the user run this in **Windows PowerShell** (not WSL):

```powershell
Rename-Item -Path 'C:\Users\luned\Documents\Projects\DaemonCore' -NewName 'DaemonCore_tmp'
```

Or simply rename it in File Explorer.

### Step 2: Access the renamed directory from WSL

```bash
ls -la "/mnt/c/Users/luned/Documents/Projects/DaemonCore_tmp"
```

This should work immediately — fresh 9P lookup, no cached corruption.

### Step 3: Rename back to the original name

Have the user rename it back:

```powershell
Rename-Item -Path 'C:\Users\luned\Documents\Projects\DaemonCore_tmp' -NewName 'DaemonCore'
```

Or via File Explorer.

### Step 4: Verify from WSL

```bash
ls -la "/mnt/c/Users/luned/Documents/Projects/DaemonCore"
cd "/mnt/c/Users/luned/Documents/Projects/DaemonCore"
git status
```

All WSL tools should now work normally.

## What NOT To Do

- **Do NOT use `Remove-Item`** in PowerShell — it throws `NullReferenceException` on the corrupt entry.
- **Do NOT use `rmdir`** in WSL — it either fails or tries to delete the real directory.
- **Do NOT use `[System.IO.Directory]::Delete()`** — same problem, hits the real directory.
- **Do NOT use `cmd.exe /c rmdir`** — UNC path rejection from WSL working directory.
- **Do NOT `wsl --shutdown`** — not necessary, the rename cycle fixes it without a restart.

## Prevention

- **Never use `mv` across WSL/Windows boundaries** (`/mnt/c/...`). Use `cp -a` then `rm -rf`, or use Windows `Move-Item` via PowerShell.
- If you must move/rename Windows directories, do it from the Windows side (PowerShell or File Explorer), not from WSL.

## Session History

- **2026-05-17**: DaemonCore directory corrupted. All WSL tools failed. Fixed via Windows rename cycle (DaemonCore → DaemonCore_tmp → DaemonCore). Verified git, ls, cd all working after.
