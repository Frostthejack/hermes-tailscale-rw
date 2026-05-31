# Windows + WSL Setup for ComfyUI

## Architecture

ComfyUI runs on **Windows** (directly, not in WSL). WSL accesses it via `http://127.0.0.1:8188` because Windows forwards localhost ports to WSL2.

**Why not run in WSL?** PyTorch CUDA support in WSL2 is possible but requires installing NVIDIA drivers inside WSL, matching CUDA toolkit versions, and using a specific Python build. Running ComfyUI directly on the Windows host avoids all of this.

## Launch Commands

```bash
# From WSL:
cmd.exe /c "cd /d F:\\ComfyUI && start_comfyui.bat"

# Manual launch (if bat file doesn't exist):
cmd.exe /c "cd /d F:\\ComfyUI && python main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --lowvram --enable-manager --windows-standalone-build"
```

Flags:
- `--listen 0.0.0.0` — makes the server reachable from both Windows and WSL
- `--port 8188` — default ComfyUI port
- `--disable-auto-launch` — prevents ComfyUI from opening a browser window
- `--lowvram` — required for RTX 4060 (8GB); optimizes VRAM usage
- `--enable-manager` — **required** for ComfyUI-Manager frontend panel to load. Without this flag, Manager won't appear in the UI even though the custom node is installed.
- `--windows-standalone-build` — required for ComfyUI-Manager UI rendering on Windows v0.22+. Without it, Manager's JS panel won't render.

## Stopping / Restarting ComfyUI

```bash
# Step 1: Find the ComfyUI python process (brute-force list without /FI filter):
cmd.exe /c "tasklist /FO CSV /NH"

# Step 2: Identify the ComfyUI PID by its command line using PowerShell:
cmd.exe /c "powershell -Command \"Get-Process python -ErrorAction SilentlyContinue | ForEach-Object { $cmdLine = (Get-CimInstance Win32_Process -Filter \\\"ProcessId=$($_.Id)\\\").CommandLine; Write-Output \\\"PID: $($_.Id) | CMD: $cmdLine\\\" }\""

# Step 3: Kill ONLY the ComfyUI process (not all Python processes):
cmd.exe /c "taskkill /PID <PID> /F"

# Step 4: Restart:
cmd.exe /c "cd /d F:\\ComfyUI && start_comfyui.bat"

# Step 5: Wait for startup (30-40s) and verify:
sleep 30 && curl -s http://127.0.0.1:8188/system_stats
```

**IMPORTANT:** Do NOT use `taskkill /IM python.exe /F` — this kills ALL Python processes on the machine, including hindsight-api, ollama, and any other running services. Always target by PID.

**IMPORTANT:** `tasklist /FI "IMAGENAME eq python.exe"` does NOT work through WSL's `cmd.exe` — it returns `ERROR: Invalid argument/option - 'eq'`. Use `tasklist /FO CSV /NH` without filters instead.

### When a Job is Stuck on GPU (CUDA hang)

If a job is stuck (e.g., Qwen-Image or other model hanging on the GPU):

1. `curl -X POST http://127.0.0.1:8188/interrupt` — will NOT work for CUDA-level hangs
2. `curl -X POST http://127.0.0.1:8188/queue -d '{"clear": true}'` — only clears pending queue, not running job
3. **Must kill the Python process by PID** (see above) and restart
4. After restart, verify queue is empty: `curl -s http://127.0.0.1:8188/queue` should show 0 running, 0 pending

## Common Issues

### OSError [Errno 22] Invalid argument (tqdm flush crash)

**Symptoms:** KSampler crashes mid-generation with `OSError: [Errno 22] Invalid argument` at `tqdm/std.py:448` → `sys.stderr.flush()`.

**Cause:** ComfyUI's `app/logger.py` replaces `sys.stderr` with a custom `LogInterceptor` that wraps a buffer. On Windows, calling `.flush()` on this wrapper raises `OSError` when tqdm tries to update its progress bar.

**Fix:** Edit `F:\ComfyUI\app\logger.py`, find the `flush` method in `LogInterceptor`, and wrap `super().flush()`:

```python
# Before (broken):
def flush(self):
    super().flush()
    for cb in self._flush_callbacks:
        cb(self._logs_since_flush)
        self._logs_since_flush = []

# After (fixed):
def flush(self):
    try:
        super().flush()
    except (OSError, ValueError):
        pass
    for cb in self._flush_callbacks:
        cb(self._logs_since_flush)
        self._logs_since_flush = []
```

Restart ComfyUI after editing. This is **not** a GPU/VRAM issue.

### cmd.exe UNC Path Errors

WSL mounts the Linux filesystem at a UNC path (`\\wsl.localhost\...`). When `cmd.exe` starts, it inherits this as the working directory and rejects it:

```
CMD.EXE was started with the above path as the current directory.
UNC paths are not supported. Defaulting to Windows directory.
```

**Fix:** Always use `cd /d` to a Windows drive before running commands:

```bash
# Good:
cmd.exe /c "cd /d F:\ComfyUI && python main.py"

# Bad (inherits WSL cwd, triggers UNC error):
cmd.exe /c "python F:\ComfyUI\main.py"
```

The `cd /d` command switches both drive and directory, and importantly overrides the UNC working directory.

### ComfyUI-Manager

To enable ComfyUI-Manager, the launch command requires `--windows-standalone-build`:

```bash
cmd.exe /c "cd /d F:\\ComfyUI && python main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --lowvram --windows-standalone-build"
```

**Important:** `--enable-manager` alone does NOT work. The `--windows-standalone-build` flag is what actually enables the Manager UI. The manager may report as started in logs (`[START] ComfyUI-Manager`) even without this flag, but the UI button won't appear.

After restarting with the flag, hard refresh the browser (Ctrl+Shift+R) to see the Manager button in the sidebar.

Install manager requirements first:
```bash
cmd.exe /c "C:\\Users\\luned\\AppData\\Local\\Programs\\Python\\Python312\\python.exe -m pip install -r F:\\ComfyUI\\manager_requirements.txt"
```

`ps aux | grep python` inside WSL won't show Windows processes. Use:

```bash
# List all Windows python processes:
cmd.exe /c "tasklist /FO CSV /NH" | grep python

# Get command line for a specific PID (to identify ComfyUI vs other python):
cmd.exe /c "powershell -Command \"Get-Process python -ErrorAction SilentlyContinue | ForEach-Object { $cmdLine = (Get-CimInstance Win32_Process -Filter \\\"ProcessId=$($_.Id)\\\").CommandLine; Write-Output \\\"PID: $($_.Id) | CMD: $cmdLine\\\" }\""
```

### Checking Server Health

```bash
curl -s http://127.0.0.1:8188/system_stats
# Returns JSON with OS, RAM, PyTorch version, device info
```

### File Paths

| Context | ComfyUI Root | Output Dir |
|---------|-------------|------------|
| Windows | `F:\ComfyUI` | `F:\ComfyUI\output\` |
| WSL | `/mnt/f/ComfyUI` | `/mnt/f/ComfyUI/output/` |

When reading workflow JSON from WSL, use Windows paths for `cmd.exe` commands and `/mnt/f/` paths for WSL-native file operations.

### Model Locations

ComfyUI scans all subdirectories under `models/`:

```
F:\ComfyUI\models\checkpoints\     # Main model files (.safetensors)
F:\ComfyUI\models\upscale_models\  # Upscale models (4x-UltraSharp.pth, etc.)
F:\ComfyUI\models\loras\           # LoRA models
F:\ComfyUI\models\clip\            # CLIP/text encoder models
F:\ComfyUI\models\vae\             # VAE models
F:\ComfyUI\models\diffusion_models\ # UNET/diffusion model files
```

### Downloading Models from CivitAI (WSL → Windows)

The most reliable method for downloading CivitAI models is WSL's native `curl`:

```bash
curl -L -s -A "Mozilla/5.0" -e "https://civitai.com/" \
  -o /mnt/f/ComfyUI/models/checkpoints/model_name.safetensors \
  "https://civitai.com/api/download/models/{MODEL_ID}?type=Model&format=SafeTensor&size=pruned&fp=fp16"
```

Run multiple in parallel via `terminal(background=true)` or shell `&` + `wait`.

**Query params are required:** `?type=Model&format=SafeTensor&size=pruned&fp=fp16`. Without them, CivitAI returns HTML instead of the model file.

**Why not alternatives:**
- `urllib.request` (Python) — fails silently on CivitAI CDN redirects, produces 0-byte files
- `cmd.exe /c curl` — UNC path errors corrupt output
- PowerShell `Invoke-WebRequest` — UNC path issues from WSL cwd, jobs produce 0-byte files

### CivitAI Rate Limiting

After downloading several models in quick succession (3-5 models), CivitAI starts
returning "File not found" (14-byte HTML error page) instead of the actual
safetensor file. This is a rate limit on the CDN, not a model-specific issue.

**Symptoms:** Downloaded file is ~14-80KB and `file` reports it as "HTML document"
or "ASCII text" instead of "data" (safetensor binary).

**Workarounds:**
1. Wait 2-3 minutes between download batches
2. Use HuggingFace mirrors where available (e.g., Lyriel: `huggingface.co/danbrown/Lyriel-v1-5`)
3. Download manually via browser from civitai.com
4. Use `comfy model download --set-civitai-api-token <token>` with a CivitAI account

**Known affected models (as of session):**
- Lyriel v16 (CivitAI ID 72396) — use HF mirror `danbrown/Lyriel-v1-5` instead
- isometric_game_assets LoRA (CivitAI ID 367782) — blocked after checkpoint downloads
- hades_isometric_grid LoRA (CivitAI ID 1183026) — blocked after checkpoint downloads

**Successfully downloaded via WSL curl:**
- DreamShaper v8 (ID 128713) — 2,034 MB ✓
- ToonYou Beta 6 (ID 125771) — 2,193 MB ✓
- Realistic Vision v6 (ID 501240) — 1,986 MB ✓
- AziibPixelMix v10 (ID 220049) — 2,034 MB ✓

### VRAM Guide for RTX 4060 (8GB)

| Workflow | Approx VRAM | Notes |
|----------|-------------|-------|
| SD 1.5 txt2img (512×512) | ~4GB | Works fine |
| SD 1.5 batch of 4 (512×512) | ~5-6GB | Works |
| SD 1.5 with upscale (2048×2048) | ~7-8GB | Tight but works with --lowvram |
| SDXL txt2img (1024×1024) | ~7-8GB | Needs --lowvram |
| SDXL hires fix (2048×2048) | ~8GB+ | May OOM; use caution |
| Flux Dev | ~12GB+ | Won't fit; use SD 1.5 or SDXL instead |
