# Updating ComfyUI (Git Pull / Version Upgrade)

## Check Current Version

```bash
cd /mnt/c/Users/luned/ComfyUI
git log --oneline -1
git describe --tags --always
# Example output: v0.21.1-16-g7c4d95d1
```

## Check Latest Release

Visit https://github.com/comfy-org/ComfyUI/releases or use `web_search` for "ComfyUI latest release".

## Update Procedure

### 1. Fetch latest

```bash
cd /mnt/c/Users/luned/ComfyUI
git fetch origin
```

### 2. Handle dirty working tree

If `git pull` fails with "Your local changes would be overwritten by merge", the
working tree is dirty with behind-merge artifacts (not custom changes). Fix:

```bash
# Reset to clean HEAD state (discards the dirty merge artifacts)
git reset --hard HEAD

# Option A: fast-forward to latest master
git pull

# Option B: force-sync master to origin (cleaner, avoids detached HEAD)
git checkout -B master origin/master
```

**When to use `git reset --hard`:** Only when `git status` shows the dirty files
are all upstream files (core Python, nodes, configs) and you have no intentional
local modifications. If you have custom nodes or modified workflows, use
`git stash` instead (but note: stash can be very slow on large repos — 30s+
timeout is normal for 700+ files on NTFS).

### 3. Switch to a specific release tag (optional)

```bash
git fetch --tags
git checkout v0.22.2
# Then re-attach master:
git checkout -B master origin/master
```

### 4. Update Python dependencies

After pulling, check if `requirements.txt` changed:

```bash
git diff HEAD@{1}..HEAD -- requirements.txt
```

If deps changed, install them in the Windows Python environment that runs ComfyUI.
Since ComfyUI runs on Windows (not WSL), use the Windows pip:

```bash
# From WSL, invoke Windows Python:
cmd.exe /c "cd /d C:\Users\luned\ComfyUI && python -m pip install --upgrade comfy-aimdo==0.4.3"
```

If `python` is not on PATH in Windows, use the full path to the embedded Python
or the venv's Python executable.

### 5. Restart ComfyUI

**Important:** `taskkill` is not available inside WSL. Use PowerShell to kill
the process. Always target the specific PID rather than killing all python.exe
processes (which may include other running scripts).

```bash
# Step 1: Find the ComfyUI PID
powershell.exe -Command "Get-Process python -ErrorAction SilentlyContinue | Select-Object Id, @{Name='CmdLine';Expression={(Get-CimInstance Win32_Process -Filter \"ProcessId=$($_.Id)\").CommandLine}}"
# Look for the PID running main.py / ComfyUI

# Step 2: Kill the specific PID
powershell.exe -Command "Stop-Process -Id <PID> -Force; Write-Output 'Killed'"

# Step 3: Start
cmd.exe /c "cd /d C:\\Users\\luned\\ComfyUI && start_comfyui.bat"

# Step 4: Verify
curl -s http://127.0.0.1:8188/system_stats
```

## Post-Update: Check Release Notes

After updating, review the changelog for:
- New nodes that may need custom node installs
- Deprecated nodes or API changes
- New model format requirements
- `requirements.txt` dependency bumps

## Pitfalls

1. **`git stash` timeout on NTFS** — Stashing 700+ files on a Windows-mounted
   filesystem (`/mnt/c/`) can exceed 30s. Use `git reset --hard HEAD` instead
   when you're sure there are no local customizations to preserve.

2. **Detached HEAD** — `git checkout v0.22.2` puts you in detached HEAD state.
   Always follow with `git checkout -B master origin/master` to re-attach.

3. **Forgetting to update deps** — `requirements.txt` changes are silent.
   Always diff it after pulling and install updates before restarting.

4. **`python` not found from WSL** — The Windows Python that runs ComfyUI may
   not be accessible as `python` from WSL. Use `cmd.exe /c "python ..."` or the
   full path to the Python executable.

5. **`taskkill` not available in WSL** — `taskkill` is a Windows CMD builtin,
   not accessible from WSL's bash. Use `powershell.exe -Command "Stop-Process -Id <PID> -Force"`
   instead. Always identify the specific PID first with `Get-Process python` +
   `Get-CimInstance Win32_Process` to find which one is ComfyUI's `main.py`.

6. **Model compatibility after upgrade** — ComfyUI updates may change valid
   `class_type` values or node input requirements. After upgrading, re-validate
   existing workflows. Common breakage:
   - CLIPLoader `type` field: `sdxl` was removed in v0.22; valid types are now
     `stable_diffusion`, `stable_cascade`, `sd3`, `wan`, `flux2`, etc.
   - SDXL models require SDXL CLIP encoders (`clip_l` + `clip_g`), not LLM-based
     CLIP models like Qwen. Mismatched CLIP + UNET causes
     `AttributeError: 'NoneType' object has no attribute 'shape'` in
     `model_base.py:encode_adm` because `clip_pooled` is None.

7. **Downloading large models from HuggingFace** — `Invoke-WebRequest` in
   PowerShell may timeout on large files (>2GB). Use `curl` from WSL writing
   directly to `/mnt/c/...` paths instead:
   ```bash
   curl -L -o /mnt/c/Users/luned/ComfyUI/models/text_encoders/clip_g.safetensors \
     "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/text_encoder_2/model.safetensors"
   ```
