# ComfyUI on Windows: WSL Integration Notes

## File Paths

| Purpose | Windows Path | WSL Path |
|---------|-------------|----------|
| ComfyUI root | `F:\ComfyUI` | `/mnt/f/ComfyUI` |
| Checkpoints | `F:\ComfyUI\models\checkpoints\` | `/mnt/f/ComfyUI/models/checkpoints/` |
| LoRAs | `F:\ComfyUI\models\loras\` | `/mnt/f/ComfyUI/models/loras/` |
| Upscale models | `F:\ComfyUI\models\upscale_models\` | `/mnt/f/ComfyUI/models/upscale_models/` |
| Custom nodes | `F:\ComfyUI\custom_nodes\` | `/mnt/f/ComfyUI/custom_nodes/` |
| Workflows | `F:\ComfyUI\workflows\` | `/mnt/f/ComfyUI/workflows/` |
| Output | `F:\ComfyUI\output\` | `/mnt/f/ComfyUI/output/` |
| User/Manager config | `F:\ComfyUI\user\__manager\config.ini` | `/mnt/f/ComfyUI/user/__manager/config.ini` |

> **Important**: The Manager config is in `user\__manager\config.ini`, NOT in the `ComfyUI-Manager-latest` custom_nodes directory.

## Launch Command

```cmd
cd /d F:\ComfyUI && C:\Users\luned\AppData\Local\Programs\Python\Python312\python.exe main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --lowvram [--enable-manager]
```

## Restarting from WSL

`start_comfyui.bat` does NOT pass through arguments. Invoke directly:

```bash
cmd.exe /c "cd /d F:\ComfyUI && C:\Users\luned\AppData\Local\Programs\Python\Python312\python.exe main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --lowvram --enable-manager"
```

## Checking if ComfyUI is Running (from WSL)

```bash
# WSL2 auto-forwards 127.0.0.1, so this just works:
curl -s --connect-timeout 5 http://127.0.0.1:8188/system_stats

# Or run the full health check:
cd ~/.hermes/profiles/pm/skills/creative/comfyui/scripts
python3 health_check.py --host http://127.0.0.1:8188
```

> **Note**: Do NOT use the Windows host IP (from `/etc/resolv.conf`) for ComfyUI — use `127.0.0.1` directly since WSL2 forwards it automatically.

## ComfyUI-Manager Configuration

### Config Location
`F:\ComfyUI\user\__manager\config.ini`

### Required Settings for Extension Installation

Manager v4.x requires two settings to install extensions:

```ini
[default]
channel_url = https://api.comfy.org/nodes
security_level = normal
network_mode = personal_cloud
```

**Details:**

| Setting | Correct Value | Wrong Value | Why |
|---------|--------------|-------------|-----|
| `channel_url` | `https://api.comfy.org/nodes` | `https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main` | Old URL is deprecated in Manager v4; causes `InvalidChannel` errors |
| `network_mode` | `personal_cloud` | `public` (default) | Extension installs from Manager UI require `personal_cloud` |
| `security_level` | `normal` or `weak` | `strong` / `above_normal` | Blocks manager operations if too restrictive |

### Known Non-Critical Errors

These appear in the ComfyUI console but don't block functionality:

1. **`InvalidChannel` for old GitHub URL** — Only matters if `channel_url` still points to the old URL. Fix: update `channel_url` as above.
2. **`ComfyRegistry cache update still in progress`** — Manager uses stale cache while refreshing. Self-resolves within seconds.
3. **`[DEPRECATION WARNING] Detected import of deprecated legacy API`** — Frontend JS deprecation warnings from ComfyUI v0.22.0. Cosmetic only.

## Health Check Script

A full health check script with ComfyUI-specific checks (checkpoints, workflow deps, smoke test) is at:

```
~/.hermes/profiles/pm/skills/creative/comfyui/scripts/health_check.py
```

Run from WSL:
```bash
python3 ~/.hermes/profiles/pm/skills/creative/comfyui/scripts/health_check.py --host http://127.0.0.1:8188
```

The shared library at `~/.hermes/profiles/pm/skills/creative/comfyui/scripts/_common.py` provides HTTP transport, cloud detection, and model listing used by all ComfyUI skill scripts.

## Installing pip packages (e.g. comfyui-manager)

```bash
cmd.exe /c "C:\Users\luned\AppData\Local\Programs\Python\Python312\python.exe -m pip install -U --pre comfyui-manager"
```

## LoRA Compatibility

### Format detection

Two formats exist. ComfyUI expects **kohya format**:
- **kohya/A1111**: keys like `lora_unet_*`, `lora_te_*`, `lora_up.weight`
- **diffusers**: keys like `unet.*.lora.up.weight`

Diffusers-format LoRAs silently fail in ComfyUI. Inspect with:
```python
import struct, json
with open('lora.safetensors', 'rb') as f:
    data = f.read()
hlen = struct.unpack('<Q', data[:8])[0]
keys = [k for k in json.loads(data[8:8+hlen]) if not k.startswith('_')]
print(keys[0])  # lora_unet_* = kohya, unet.*.lora = diffusers
```

### SD version mismatch

LoRAs must match the checkpoint's SD version. SDXL LoRAs have 1280-dim weights vs SD 1.5's 768-dim. Mislabeled LoRAs on CivitAI are common — verify by checking tensor shapes in the header. Shape mismatch errors = wrong SD version.

### "lora key not loaded" warnings

Harmless. Some LoRA keys don't match the model's UNet architecture. Only matching keys are applied.

## Known Fixes

**`OSError: [Errno 22]` tqdm crash on Windows:**
Edit `F:\ComfyUI\app\logger.py`, `LogInterceptor.flush()`:
```python
def flush(self):
    try:
        super().flush()
    except (OSError, ValueError):
        pass
    # ... callbacks unchanged
```

## Workflow JSON Format

```json
{
  "<node_id>": {
    "class_type": "<NodeType>",
    "inputs": {
      "<name>": ["<source_node_id>", <output_index>],
      "<name>": <literal>
    }
  }
}
```

Node IDs are strings. Source references use `[string_id, number_index]`.

### Format detection

Two formats exist. ComfyUI expects **kohya format**:
- **kohya/A1111**: keys like `lora_unet_*`, `lora_te_*`, `lora_up.weight`
- **diffusers**: keys like `unet.*.lora.up.weight`

Diffusers-format LoRAs silently fail in ComfyUI. Inspect with:
```python
import struct, json
with open('lora.safetensors', 'rb') as f:
    data = f.read()
hlen = struct.unpack('<Q', data[:8])[0]
keys = [k for k in json.loads(data[8:8+hlen]) if not k.startswith('_')]
print(keys[0])  # lora_unet_* = kohya, unet.*.lora = diffusers
```

### SD version mismatch

LoRAs must match the checkpoint's SD version. SDXL LoRAs have 1280-dim weights vs SD 1.5's 768-dim. Mislabeled LoRAs on CivitAI are common — verify by checking tensor shapes in the header. Shape mismatch errors = wrong SD version.

### "lora key not loaded" warnings

Harmless. Some LoRA keys don't match the model's UNet architecture. Only matching keys are applied.

## Known Fixes

**`OSError: [Errno 22]` tqdm crash on Windows:**
Edit `F:\ComfyUI\app\logger.py`, `LogInterceptor.flush()`:
```python
def flush(self):
    try:
        super().flush()
    except (OSError, ValueError):
        pass
    # ... callbacks unchanged
```

## Workflow JSON Format

```json
{
  "<node_id>": {
    "class_type": "<NodeType>",
    "inputs": {
      "<name>": ["<source_node_id>", <output_index>],
      "<name>": <literal>
    }
  }
}
```

Node IDs are strings. Source references use `[string_id, number_index]`.
