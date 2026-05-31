# Updating Git-Based Projects on Windows Filesystem from WSL

## Problem

Projects cloned to `/mnt/c/...` (Windows filesystem, accessed via WSL) can accumulate dirty state that blocks `git pull`. This happens when the working tree has local modifications that conflict with incoming changes.

## Pre-Update Safety Check

Before resetting, check if there are any real local customizations vs just merge artifacts:

```bash
# See what's changed
git diff --stat HEAD

# If ALL changes are upstream files (no custom files), safe to reset
# If YOUR custom files appear in the diff, stash them first:
git stash -m "custom-changes"
git pull
git stash pop
```

For ComfyUI specifically: the 795-file "dirty" state was entirely caused by the working tree being behind the remote after a partial fetch. No local customizations existed. `git reset --hard HEAD` was safe.

## Update Procedure

```bash
cd /mnt/c/Users/<user>/<project>

# 1. Check current version
git log --oneline -1
git describe --tags --always

# 2. Fetch latest
git fetch origin

# 3. Check if update is available
git log HEAD..origin/master --oneline | head -5

# 4. Clean dirty state (only if no local customizations!)
git reset --hard HEAD

# 5. Checkout desired version
git checkout v0.22.2        # specific tag
# OR
git checkout -B master origin/master  # latest master

# 6. Check dependency changes
git diff HEAD@{1}..HEAD -- requirements.txt  # Python projects
git diff HEAD@{1}..HEAD -- package.json      # Node projects

# 7. Install dependency updates
# Python (run in the project's Python environment):
/mnt/c/Users/<user>/AppData/Local/Programs/Python/Python312/python.exe -m pip install --upgrade <package>==<version>
# Node:
npm install  # or pnpm install
```

## ComfyUI-Specific Notes

- **Python**: `C:\Users\luned\AppData\Local\Programs\Python\Python312\python.exe`
- **Launcher**: `start_comfyui.bat` runs `python.exe main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --lowvram`
- **After updating**: kill the running process first (see `references/windows-process-management-from-wsl.md`), then restart via `start_comfyui.bat`
- **Port**: Check if still running with `curl -s -o /dev/null -w "%{http_code}" http://localhost:8188/`
