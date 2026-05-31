# ComfyUI-Manager Installation, Security & LoRA Compatibility

## Manager Installation

ComfyUI-Manager must be installed as a **custom node**, not just via pip.

### Correct procedure

1. Clone into custom_nodes:
   ```
   cmd.exe /c "cd /d F:\ComfyUI\custom_nodes & git clone https://github.com/ltdrdata/ComfyUI-Manager.git"
   ```

2. Install Python dependencies:
   ```
   cmd.exe /c "C:\Users\luned\AppData\Local\Programs\Python\Python312\python.exe -m pip install -r F:\ComfyUI\manager_requirements.txt"
   ```

3. Restart ComfyUI with the correct flags:
   ```
   cmd.exe /c "cd /d F:\ComfyUI && C:\Users\luned\AppData\Local\Programs\Python\Python312\python.exe main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --lowvram --windows-standalone-build"
   ```

**CRITICAL**: Both `--enable-manager` AND `--windows-standalone-build` are REQUIRED for the Manager UI to load and render properly on Windows v0.22+. Without `--enable-manager`, the Manager frontend panel won't load at all. Without `--windows-standalone-build`, the Manager JS panel won't render.

### Channel URL Fix (Manager v4.x)

Manager v4.x switched from the old ltdrdata GitHub URL to the official ComfyRegistry API. If you see repeated `InvalidChannel` errors:

```
[ComfyUI-Manager] An invalid channel was used: https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main
```

Edit `F:\ComfyUI\user\__manager\config.ini` and change:
```ini
channel_url = https://api.comfy.org/nodes
```

The old URL (`https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main`) is deprecated. The new API source (`https://api.comfy.org/nodes`) is the correct channel for v4.x.

### Manager UI not visible?
- Hard refresh browser (Ctrl+Shift+R)
- Look for Manager button in bottom-left sidebar or as a cog/gear icon
- The `/manager` API endpoint may return empty — this is normal
- The Manager's JS files are in `custom_nodes/ComfyUI-Manager/js/` — if missing, the clone was incomplete

## Manager Security Policy & Configuration

### Config file location

**IMPORTANT**: The config file is NOT at `custom_nodes/ComfyUI-Manager/config.ini`.
The actual location is:

```
F:\ComfyUI\user\__manager\config.ini
```

This is because ComfyUI-Manager was extracted as `ComfyUI-Manager-latest` and the
config lives in the `__manager` user directory.

### Security Level Error

When installing extensions or performing certain Manager actions, you may see:

```
ERROR: To use this action, security_level must be `normal or below`,
and network_mode must be `personal_cloud`. Please contact the administrator.
```

**Root cause**: ComfyUI-Manager v3.40+ enforces a security policy that restricts
actions based on two config settings:
- `security_level` — must be `normal` or `weak` (not `strong`/`above_normal`)
- `network_mode` — must be `personal_cloud` for extension installs

**Fix**: Edit `F:\ComfyUI\user\__manager\config.ini`:

```ini
[default]
security_level = normal          ; or weak if normal still blocked
network_mode = personal_cloud    ; was `public`, change to `personal_cloud`
```

**After saving**: The config is read at operation time — no ComfyUI restart needed.
Try the install again. If it still fails, drop `security_level` to `weak`.

### Other common config values in `config.ini`

```ini
[default]
git_exe =
use_uv = False
channel_url = https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main
share_option = all
bypass_ssl = False
file_logging = True
update_policy = stable-comfyui
windows_selector_event_loop_policy = False
model_download_by_agent = False
downgrade_blacklist =
security_level = normal
always_lazy_install = False
network_mode = personal_cloud
db_mode = cache
verbose = False
```

## LoRA Compatibility

### CivitAI LoRAs can be mislabeled
- Some LoRAs claim SD 1.5 but have SDXL-sized tensor weights (10240×1280)
- SD 1.5 attention weights: 768×768; SDXL: 1280×1280+
- Shape mismatch errors = wrong base model
- Verify by checking tensor dimensions, not just metadata

### Diffusers-format LoRAs won't load in ComfyUI
- Diffusers keys: `unet.down_blocks...attn1.to_k.lora.down.weight`
- Kohya/ComfyUI keys: `lora_unet_down_blocks...attn1_to_k.lora_down.weight`
- Diffusers-format LoRAs silently fail in ComfyUI

### Safetensors validation
- `file` command is unreliable — may report "zlib compressed" for valid files
- Validate: parse header, check `file_size == 8 + header_len + sum(tensor_data_offsets)`
- If file is smaller than expected = truncated, re-download

### Double-stacking LoRAs
- Same LoRA applied twice at different strengths (e.g., 0.6 + 0.4) compounds
- Effective strength ≈ 0.76-0.8 for 0.6+0.4

### "lora key not loaded" warnings are harmless
- Informational only — keys for non-existent layers are skipped
- LoRA still works with the keys that do match

## Process Management

### Kill by PID, not by name
- `taskkill /IM python.exe /F` kills ALL Python processes
- Find ComfyUI PID via PowerShell, then `taskkill /PID <PID> /F`

### CUDA hangs
- API interrupt doesn't work for CUDA-level hangs
- Only fix: kill process by PID and restart
