# Game Asset Tile Generation with ComfyUI

## Isometric Tile Workflow (v5 — Current Best)

A single-pass workflow for generating game tiles at 512×512:

1. **Generate at 512×512, batch of 4** — Pick the best tile from 4 variations
2. **No hires fix** — Saves VRAM on 8GB cards; upscale externally if needed
3. **CFG 9.0-10.0** — High CFG critical for enforcing "single tile" constraint
4. **DPM++ 2M Karras** — Better convergence than euler/normal for this use case
5. **Single LoRA (Hades Isometric Grid) at 0.7** — Confirmed working SD 1.5 kohya format

### Key Insight: SD Models Generate Scenes, Not Tiles

Default SD models (even fine-tuned ones) will produce full scenes with
perspective, multiple objects, and landscape elements unless explicitly
constrained. The solution is **aggressive prompt engineering**:

**Positive prompt structure:**
```
flat isometric [TYPE] tile, viewed from above at 45-degree angle,
[SURFACE DETAIL], single square tile filling entire frame,
RPG maker game asset, no perspective depth, no vanishing point,
centered, seamless edges, top-down 2d sprite style, game art,
clean sharp edges, vibrant saturated colors, no background,
no scenery, no sky, no horizon line, no other objects
```

**Negative prompt — must explicitly exclude scene keywords:**
```
blurry, low quality, text, watermark, deformed, ugly, cropped,
worst quality, jpeg artifacts, multiple tiles, scene, landscape,
panorama, wide shot, horizon, sky, clouds, mountains, ocean,
buildings, towers, trees, plants, flowers, characters, people,
animals, creatures, perspective lines, vanishing point, depth
effect, realistic photograph, out of frame, empty border, vignette
```

### Tile Type Examples (replace [TYPE] and [SURFACE DETAIL])

| Tile | Prompt Fragment |
|------|----------------|
| Dirt Path | `dungeon floor tile, dirt stone path, mossy edges` |
| Grass | `grass terrain, lush green, small flowers, clover` |
| Stone | `stone brick, worn cobblestone, dungeon floor` |
| Water | `water surface, translucent blue, small ripples` |
| Lava | `lava floor, glowing orange red, cracked earth` |
| Sand | `sand desert, dry cracked earth, scattered bones` |
| Wood | `wooden planks, bridge deck, weathered wood` |
| Ice | `ice tile, frozen surface, snow covered` |
| Swamp | `swamp mud, bubbling green sludge` |
| Marble | `marble floor, white veined, polished stone` |

## Model Recommendations (SD 1.5 based, ~2GB each)

All models below are CivitAI downloads. URLs use format:
`https://civitai.com/api/download/models/{ID}?type=Model&format=SafeTensor&size=pruned&fp=fp16`

| Model | CivitAI ID | Style | Best For |
|-------|-----------|-------|----------|
| **ToonYou Beta 6** | 125771 | Cartoon/toon, clean lines | **Best for game tiles** — stylized, game-like |
| **DreamShaper v8** | 128713 | Versatile artistic | Good prompt adherence, stylized |
| **AziibPixelMix v10** | 220049 | Pixel art, retro | Pixel art game tiles |
| **Lyriel v15** | HF mirror | Illustrated/fantasy | Fantasy game assets |
| **Realistic Vision v6** | 501240 | Photorealistic | NOT recommended for tiles |

Place downloaded `.safetensors` files in `F:\ComfyUI\models\checkpoints\`.

### Download Method

Use WSL's native `curl` (most reliable):
```bash
curl -L -s -A "Mozilla/5.0" -e "https://civitai.com/" \
  -o /mnt/f/ComfyUI/models/checkpoints/model_name.safetensors \
  "https://civitai.com/api/download/models/{ID}?type=Model&format=SafeTensor&size=pruned&fp=fp16"
```

Run multiple in parallel via `terminal(background=true)`.

### CivitAI Rate Limiting

After downloading several models in quick succession, CivitAI returns
"File not found" (14-byte HTML) instead of the safetensor. This affects
LoRAs more than checkpoints. Workarounds:
- Wait a few minutes between download batches
- Use HuggingFace mirrors where available
- Download via browser manually

**LoRA downloads blocked:** The isometric LoRAs (`isometric_game_assets`
CivitAI ID 367782, `hades_isometric_grid` CivitAI ID 1183026) were
consistently blocked. If you can download them manually from CivitAI
browser, place in `F:\ComfyUI\models\loras\`.

**Lyriel HF mirror:**
```bash
curl -L -s -o /mnt/f/ComfyUI/models/checkpoints/lyriel_v15.safetensors \
  "https://huggingface.co/danbrown/Lyriel-v1-5/resolve/main/lyriel-v1-5.safetensors"
```

## VRAM Considerations (RTX 4060, 8GB)

With `--lowvram` flag:
- SD 1.5 at 512×512, batch 4: ~5-6GB VRAM — works
- SD 1.5 with 4× upscale + hires fix to 2048×2048: ~7-8GB — tight, may OOM
- **Recommendation:** Skip hires fix, generate at 512px, upscale externally

## Workflow Files

| `F:\ComfyUI\workflows\isometric_tile_generator_v5.json` | **Recommended** — Single Hades LoRA (0.7), batch 4, CFG 9, no hires fix. Confirmed working. |
| `F:\ComfyUI\workflows\isometric_tile_generator_v4.json` | Two LoRA stack (broken — isometric_game_assets is SDXL, will cause shape mismatch) |
| `F:\ComfyUI\workflows\isometric_tile_generator_v3.json` | Prompt-engineered single pass, batch 4, CFG 10, no hires fix. Use if no LoRAs available. |
| `F:\ComfyUI\workflows\isometric_tile_generator_v2_hades.json` | Variant with only Hades LoRA at 0.9 strength |
| `F:\ComfyUI\isotropic_tile_generator.json` | Original v1 (outdated, do not use) |

To use: drag JSON into ComfyUI, edit the CLIPTextEncode prompt, run.

## LoRA Compatibility — CRITICAL

### LoRA Format Compatibility

ComfyUI's `LoraLoader` expects **kohya/A1111 format** LoRAS with key naming like:
`lora_unet_down_blocks_0_attentions_0_transformer_blocks_0_attn1_to_k.lora_down.weight`

**Diffusers-format LoRAS** (key naming like:
`unet.down_blocks.0.attentions.0.transformer_blocks.0.attn1.to_k.lora.down.weight`)
will NOT load in ComfyUI. Check format before downloading:
```python
import json, struct
with open('lora.safetensors', 'rb') as f:
    data = f.read()
header_len = struct.unpack('<Q', data[:8])[0]
header = json.loads(data[8:8+header_len])
keys = [k for k in header if not k.startswith('_')]
is_kohya = any('lora_down' in k or 'lora_up' for k in keys)
is_diffusers = any('lora.down.weight' in k for k in keys)
```

### Known Isometric/Tile LoRAS

| LoRA | Source | Format | Compatible? | Notes |
|------|--------|--------|-------------|-------|
| **hades_isometric_grid** | CivitAI ID 1183026 (~24MB) | Kohya SD 1.5 | ✅ Yes | Isometric grid map tiles. Works with ToonYou. |
| **isometric_game_assets** | CivitAI ID 367782 (~50MB) | SDXL (mislabeled as SD 1.5) | ❌ No | Claims SD 1.5 in metadata but weights are SDXL-sized (10240×1280). Causes shape mismatch errors. Do not use with SD 1.5 checkpoints. |
| **SedatAl/pixel-art-LoRa** | HuggingFace (~3MB) | Diffusers | ❌ No | Diffusers key format. ComfyUI cannot load it. |

### SDXL LoRAs Mislabeled as SD 1.5

Some CivitAI LoRAs claim `ss_base_model_version: sd_v1` in metadata but have
SDXL-sized tensor weights. Detect by inspecting tensor shapes:
- SD 1.5 attention weights: 768×768 or 768×3072
- SDXL attention weights: 1280×1280 or 1280×5120

If you see shape errors like `'[10240, 1280]' is invalid for input of size 3276800`,
the LoRA is SDXL and won't work with SD 1.5 checkpoints.

### `file` Command Misidentification

The `file` command may report a valid safetensors file as "zlib compressed data".
This is a false positive — the safetensors format uses a header that `file`
mistakenly identifies as zlib. Always validate with struct header parsing, not
the `file` command.

### "lora key not loaded" Warnings Are Harmless

When loading a LoRA, you may see many warnings like:
```
lora key not loaded: lora_unet_output_blocks_0_1_transformer_blocks_1_ff_net_2.lora_up.weight
```
These are **warnings, not errors**. The LoRA contains keys for layers that don't exist in the current model's UNet. ComfyUI skips them and loads the matching ones. This is normal when a LoRA was trained on a slightly different architecture (e.g., SDXL-derived model used with SD 1.5). The LoRA still works — ignore these warnings.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Still getting scenes | Raise CFG to 11-12; add more negative keywords (scene, landscape, panorama, horizon, sky, perspective) |
| Tiles too plain | Add surface detail words; lower CFG to 8-9 |
| Want pixel art look | Use aziibpixelmix_v10 model; add "pixel art" to prompt |
| LoRA file missing/broken | Set strength_model and strength_clip to 0 in LoraLoader node |
| OOM on hires fix | Remove hires fix pass; use 512px output only |
