# IPAdapter Plus — Installation and Multi-Reference Patterns

## Installation

```bash
# Clone into custom_nodes (NOT pip install — it's not on PyPI)
cd /mnt/f/ComfyUI/custom_nodes
git clone https://github.com/cubiq/ComfyUI_IPAdapter_plus.git
```

**No extra pip dependencies** — no `requirements.txt`; depends on ComfyUI built-ins.

## Required Model Files (SDXL)

| File | Path | Size |
|------|------|------|
| `ip-adapter-plus_sdxl_vit-h.safetensors` | `F:\ComfyUI\models\ipadapter\` | ~3.7 GB |
| `CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors` | `F:\ComfyUI\models\clip_vision\` | ~2.4 GB |

**Note:** The `models/ipadapter/` and `models/clip_vision/` directories may not exist — create them.

```bash
mkdir -p /mnt/f/ComfyUI/models/ipadapter
mkdir -p /mnt/f/ComfyUI/models/clip_vision
curl -L -o /mnt/f/ComfyUI/models/ipadapter/ip-adapter-plus_sdxl_vit-h.safetensors \
  "https://huggingface.co/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors"
curl -L -o /mnt/f/ComfyUI/models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors \
  "https://huggingface.co/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors"
```

**Restart ComfyUI after installing** — new nodes and models are only detected at startup.

## Multi-Reference Composition Patterns

### Pattern A: Simultaneous (Equal Influence)

Chain `IPAdapterAdvanced` nodes, all with `start_at=0.0, end_at=1.0`, equal weight.
Best when all subjects should have **equal prominence**.

`CheckpointLoader → IPAdapterAdv(char1, w=0.6) → IPAdapterAdv(char2, w=0.6) → IPAdapterAdv(char3, w=0.6) → IPAdapterAdv(char4, w=0.6) → KSampler`

### Pattern B: Timed/Scheduled (Staggered)

Stagger `start_at`/`end_at` per character for **distinct individual representation**.

| Char | start_at | end_at | weight |
|------|----------|--------|--------|
| 1 | 0.0 | 0.8 | 0.7 |
| 2 | 0.1 | 0.85 | 0.65 |
| 3 | 0.15 | 0.9 | 0.65 |
| 4 | 0.2 | 1.0 | 0.6 |

### Pattern C: Regional (Spatial)

Uses `easy ipadapterApplyRegional` (comfyui-easy-use) with mask inputs per region.
**WARNING:** kjnodes has no simple SolidMask/ConstantMask. Complex to set up without additional mask utility nodes. Prefer Pattern A or B.

## IPAdapterAdvanced Key Parameters

| Field | Recommended | Notes |
|-------|-------------|-------|
| `weight` | 0.5–0.75 | Per character with 4 refs |
| `weight_type` | `linear` | Most predictable |
| `combine_embeds` | `concat` | **Required** for chaining — without this later nodes overwrite earlier ones |
| `embeds_scaling` | `V only` | Standard for SDXL |
| `start_at` | 0.0–0.2 | Earlier = stronger structural influence |
| `end_at` | 0.8–1.0 | Later = more detail influence |

## Critical Pitfalls

1. **Wrong directory** — IPAdapter models go in `models/ipadapter/`, CLIP vision in `models/clip_vision/`
2. **No restart** — new nodes/models only detected at ComfyUI startup
3. **Shared loaders** — all chain nodes must share the SAME `IPAdapterModelLoader` and `CLIPVisionLoader`
4. **`combine_embeds: concat`** — must be set on ALL chained nodes or later refs overwrite earlier ones
5. **Weight too high** — 4 chars at w=0.8 each over-constrains; use 0.5–0.6
6. **No pip package** — `comfyui-ipadapter-plus` does NOT exist on PyPI; must git clone

## Example Workflows

See `F:\ComfyUI\workflow_ipadapter_multi_ref.json` (Pattern A) and `F:\ComfyUI\workflow_ipadapter_timed.json` (Pattern B) for complete runnable examples.
