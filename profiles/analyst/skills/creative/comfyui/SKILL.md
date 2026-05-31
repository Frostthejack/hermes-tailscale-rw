---
name: comfyui
description: "Generate images, video, and audio with ComfyUI — install, launch, manage nodes/models, run workflows with parameter injection. Uses the official comfy-cli for lifecycle and direct REST/WebSocket API for workflow execution."
version: 5.4.0
author: [kshitijk4poor, alt-glitch, purzbeats]
license: MIT
platforms: [macos, linux, windows]
compatibility: "Requires ComfyUI (local, ComfyUI Desktop, or Comfy Cloud) and comfy-cli (auto-installed via pipx/uvx by the setup script)."
prerequisites:
  commands: ["python3"]
setup:
  help: "Run scripts/hardware_check.py FIRST to decide local vs Comfy Cloud; then scripts/comfyui_setup.sh auto-installs locally (or use Cloud API key for platform.comfy.org)."
metadata:
  hermes:
    tags:
      - comfyui
      - image-generation
      - stable-diffusion
      - flux
      - sd3
      - wan-video
      - hunyuan-video
      - creative
      - generative-ai
      - video-generation
    related_skills: [stable-diffusion-image-generation, image_gen]
    category: creative
---

# ComfyUI

Generate images, video, audio, and 3D content through ComfyUI using the
official `comfy-cli` for setup/lifecycle and direct REST/WebSocket API
for workflow execution.

## What's in this skill

**Reference docs (`references/`):**

- `official-cli.md` — every `comfy ...` command, with flags
- `rest-api.md` — REST + WebSocket endpoints (local + cloud), payload schemas
- `workflow-format.md` — API-format JSON, common node types, param mapping
- `template-integrity.md` — converting `comfyui-workflow-templates` from
  editor format to API format: Reroute bypass, dotted dynamic-input keys
  (`values.a`, `resize_type.width`), Cloud quirks (302 redirect, 1 concurrent
  free-tier job, 1080p VRAM ceiling), Discord-compatible ffmpeg stitch.
  Authored by [@purzbeats](https://github.com/purzbeats). Load this whenever
  you're starting from an official template.
- `windows-wsl-setup.md` — WSL2 + Windows GPU setup: why ComfyUI must run on
  Windows directly, launch commands, fixing CPU-only PyTorch, file path rules,
  known issues (OSError [Errno 22] logger crash, cmd.exe UNC paths), and VRAM
  guide for RTX 4060 (8GB). Load this when the agent is on WSL but the GPU is on Windows.
- `update-comfyui.md` — git pull / version upgrade procedure: handling dirty
  working trees, `git reset --hard` vs stash, detached HEAD, updating Python
  deps after pull, and restart. Load this when the user asks to update ComfyUI.
- `quick-reference.md` — condensed cheat sheet: model compatibility matrix,
  KSampler params, VRAM tips, API endpoints, model download commands, common
  errors. Load this for a quick lookup without loading the full vault doc.
- `game-asset-tiles.md` — isometric game tile generation: prompt engineering,
  two-pass workflow (512→2048), model recommendations with CivitAI IDs,
  VRAM considerations for RTX 4060. Load this when generating game tiles or
  isometric art assets.
- `comfyui-manager-and-lora-compatibility.md` — ComfyUI-Manager installation,
  security policy, config file location, compatibility matrix, LoRA format issues
  (SDXL vs SD 1.5, diffusers vs kohya), troubleshooting. Load this when installing
  the manager, debugging LoRA errors, or fixing security/extension install errors.
- `ipadapter-plus.md` — IPAdapter Plus installation (git clone, not pip), model
  file locations, multi-reference composition patterns (simultaneous, timed,
  regional), node parameters, critical pitfalls. Load this for any multi-image
  reference workflow.

**Scripts (`scripts/`):**

| Script | Purpose |
|--------|---------|
| `_common.py` | Shared HTTP, cloud routing, node catalogs (don't run directly) |
| `hardware_check.py` | Probe GPU/VRAM/disk → recommend local vs Comfy Cloud |
| `comfyui_setup.sh` | Hardware check + comfy-cli + ComfyUI install + launch + verify |
| `extract_schema.py` | Read a workflow → list controllable params + model deps |
| `check_deps.py` | Check workflow against running server → list missing nodes/models |
| `auto_fix_deps.py` | Run check_deps then `comfy node install` / `comfy model download` |
| `run_workflow.py` | Inject params, submit, monitor, download outputs (HTTP or WS) |
| `run_batch.py` | Submit a workflow N times with sweeps, parallel up to your tier |
| `ws_monitor.py` | Real-time WebSocket viewer for executing jobs (live progress) |
| `health_check.py` | Verification checklist runner — comfy-cli + server + models + smoke test |
| `fetch_logs.py` | Pull traceback / status messages for a given prompt_id |

**Example workflows (`workflows/`):** SD 1.5, SDXL, Flux Dev, SDXL img2img,
SDXL inpaint, ESRGAN upscale, AnimateDiff video, Wan T2V. See
`workflows/README.md`.

**Templates (`templates/`):**

| Template | Purpose |
|----------|---------|
| `sdxl_dual_clip_workflow.json` | Minimal SDXL txt2img with DualCLIPLoader (v0.22 compatible). Copy and modify. |

## When to Use

- User asks to generate images with Stable Diffusion, SDXL, Flux, SD3, etc.
- User wants to run a specific ComfyUI workflow file
- User wants to chain generative steps (txt2img → upscale → face restore)
- User needs ControlNet, inpainting, img2img, or other advanced pipelines
- User asks to manage ComfyUI queue, check models, or install custom nodes
- User wants video/audio/3D generation via AnimateDiff, Hunyuan, Wan, AudioCraft, etc.
- User asks to update/upgrade ComfyUI to the latest version
- User wants multi-image reference composition (e.g., combine character portraits into a group scene)

## Architecture: Two Layers

```
┌─────────────────────────────────────────────────────┐
│ Layer 1: comfy-cli (official lifecycle tool)        │
│   Setup, server lifecycle, custom nodes, models     │
│   → comfy install / launch / stop / node / model    │
└─────────────────────────┬───────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────┐
│ Layer 2: REST/WebSocket API + skill scripts         │
│   Workflow execution, param injection, monitoring   │
│   POST /api/prompt, GET /api/view, WS /ws           │
│   → run_workflow.py, run_batch.py, ws_monitor.py    │
└─────────────────────────────────────────────────────┘
```

**Why two layers?** The official CLI is excellent for installation and server
management but has minimal workflow execution support. The REST/WS API fills
that gap — the scripts handle param injection, execution monitoring, and
output download that the CLI doesn't do.

## Quick Start

### ⚡ This Machine's Setup (WSL → Windows)

ComfyUI is installed on **Windows** at `F:\\ComfyUI` and accessed from
WSL via `http://127.0.0.1:8188`. The `comfy-cli` is **not** used for
lifecycle — launch is done directly via `cmd.exe`.

| Action | Command (run from WSL) |
|--------|------------------------|
| **Start** | `cmd.exe /c "cd /d F:\\ComfyUI && python main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --lowvram --windows-standalone-build"` |
| **Stop** | Find PID first (see pitfall #10), then `taskkill /PID <PID> /F` |
| **Web UI** | Open **http://localhost:8188** in your browser |
| **Health check** | `curl -s http://127.0.0.1:8188/system_stats` |

The full flag set for this machine:
```
python main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --lowvram --windows-standalone-build
```
- `--lowvram` is required for the RTX 4060 (8GB)
- `--listen 0.0.0.0` makes it reachable from both Windows and WSL
- `--windows-standalone-build` enables ComfyUI-Manager frontend (v0.22 compat)

**Models:** Checkpoints at `F:\\ComfyUI\\models\\checkpoints\\`, LoRas at `F:\\ComfyUI\\models\\loras\\`, upscale models at `F:\\ComfyUI\\models\\upscale_models\\`. ComfyUI scans all subfolders under `models/`.

**Outputs:** Generated images land in `F:\\ComfyUI\\output\\` (accessible from WSL at `/mnt/f/ComfyUI/output/`).

### Detect environment

```bash
# What's available?
command -v comfy >/dev/null 2>&1 && echo "comfy-cli: installed"
curl -s http://127.0.0.1:8188/system_stats 2>/dev/null && echo "server: running"

# Can this machine run ComfyUI locally? (GPU/VRAM/disk check)
python3 scripts/hardware_check.py
```

## Core Workflow

### Step 1: Get a workflow JSON in API format

Workflows must be in API format (each node has `class_type`). They come from:

- ComfyUI web UI → **Workflow → Export (API)** (newer UI) or
  the legacy "Save (API Format)" button (older UI)
- This skill's `workflows/` directory (ready-to-run examples)
- Community downloads (Civitai, Reddit, Discord) — usually editor format,
  must be loaded into ComfyUI then re-exported

Editor format (top-level `nodes` and `links` arrays) is **not directly
executable**. The scripts detect this and tell you to re-export.

### Step 2: See what's controllable

```bash
python3 scripts/extract_schema.py workflow_api.json --summary-only
python3 scripts/extract_schema.py workflow_api.json  # full schema
```

### Step 3: Run with parameters

```bash
python3 scripts/run_workflow.py \
  --workflow workflow_api.json \
  --args '{"prompt": "a beautiful sunset", "seed": -1, "steps": 30}' \
  --output-dir ./outputs
```

### Step 4: Present results

```json
{
  "status": "success",
  "prompt_id": "abc-123",
  "outputs": [{"file": "./outputs/iso_tile_00001_.png", "type": "image"}]
}
```

## Decision Tree

| User says | Tool | Command |
|-----------|------|---------|
| "start ComfyUI (this machine)" | cmd.exe | `cmd.exe /c "cd /d F:\\ComfyUI && python main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch --lowvram --windows-standalone-build"` |
| "stop ComfyUI safely" | taskkill by PID | See pitfall #10 |
| "is everything ready?" | script | `health_check.py` |
| "generate an image" | workflow | `run_workflow.py --workflow W --args '{...}'` |
| "check queue" | REST | `curl http://127.0.0.1:8188/queue` |
| "cancel running job" | REST | `curl -X POST http://127.0.0.1:8188/interrupt` |
| "multi-image reference composition" | IPAdapter workflow | See `references/ipadapter-plus.md` |

## Pitfalls

See `references/comfyui-manager-and-lora-compatibility.md` for the full compatibility and troubleshooting guide. Key highlights:

1. **API format required** — workflows must be in API format, not editor format.
2. **Server must be running** — verify with `curl http://127.0.0.1:8188/system_stats`.
3. **Model names are exact** — case-sensitive, includes extension.
4. **`OSError: [Errno 22]` logger crash on Windows** — patch `app/logger.py` `flush()` with try/except.
5. **CivitAI LoRAs can be mislabeled** — check tensor dimensions, not just metadata.
6. **Diffusers-format LoRAs won't load in ComfyUI** — keys must use kohya naming.
7. **Use WSL curl for CivitAI downloads** — not PowerShell or urllib.
8. **ComfyUI-Manager needs `custom_nodes/` + `js/` directory** — pip install alone is insufficient.
9. **`--windows-standalone-build` required for manager UI** on Windows v0.22.
10. **Find PID before killing** — never use `taskkill /IM python.exe /F`.
11. **Wait 30-40s after startup** before submitting jobs — API responds before nodes finish loading.
12. **"lora key not loaded" warnings are harmless** — ComfyUI skips incompatible keys.
13. **ComfyUI-Manager security policy blocks extension installs** — When installing extensions triggers `ERROR: security_level must be normal or below, network_mode must be personal_cloud`, edit `F:\\ComfyUI\\user\\__manager\\config.ini` (NOT `custom_nodes/ComfyUI-Manager/config.ini`): set `network_mode = personal_cloud` and `security_level = normal` (or `weak`). Config is read at operation time — no restart needed.
14. **ComfyUI-Manager `InvalidChannel` errors** — Update `channel_url` in `user/__manager/config.ini` from old `https://raw.githubusercontent.com/ltdrdata/ComfyUI-Manager/main` to `https://api.comfy.org/nodes`.
15. **IPAdapter Plus is NOT on PyPI** — must `git clone` into `custom_nodes/`. See `references/ipadapter-plus.md`.

See `references/game-asset-tiles.md` for isometric tile generation prompt engineering.
See `references/ipadapter-plus.md` for multi-image reference composition with IPAdapter.
