# Multi-Image Reference Composition in ComfyUI

## Use Case
User wants to use multiple reference images (e.g., character portraits) and a text prompt to generate a single composite scene.

## Decision Tree

### Best: IPAdapter Plus
**Install first if not present.** This is the gold standard for multi-character reference composition.

```
comfy node install ComfyUI_IPAdapter_plus
```

Also requires:
- IPAdapter model files in `models/ipadapter/` (e.g., `ip-adapter-plus_sdxl_vit-h.safetensors`)
- CLIP vision model in `models/clip_vision/` (e.g., `CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors`)

**Workflow pattern:**
1. `LoadImage` × N (one per reference)
2. `IPAdapterModelLoader` → loads IPAdapter weights
3. `CLIPVisionLoader` → loads CLIP vision encoder
4. `IPAdapterAdvanced` per image, each with its own `weight` and `start_at`/`end_at`
5. Feed all IPAdapter outputs into KSampler
6. Use a detailed text prompt describing the desired scene/composition

**Key parameters:**
- `weight`: 0.6–0.8 per reference (lower = less influence)
- `start_at`/`end_at`: Stagger these (e.g., 0.0–0.5, 0.2–0.7, 0.4–0.9, 0.6–1.0)
- `noise`: 0.3–0.5 for each reference adds variation

### Alternative: Regional Prompting (comfyui-easy-use)
If IPAdapter is not available, use comfyui-easy-use's regional prompting nodes.

**Pros:** No extra downloads
**Cons:** Characters won't match references precisely; works better for style/pose than likeness

### Avoid: img2img Collage Approach
**Do NOT** concatenate reference images into a collage and use as single img2img input. This blends/morphs characters together. The model treats the collage as one image to remix, not as separate character references.

## Common Pitfalls
- **IPAdapter models not in correct folder**: Must be in `models/ipadapter/`, not `models/`
- **Wrong CLIP vision model**: SDXL needs ViT-H (laion2B), SD 1.5 needs ViT-H (laion2B) — check IPAdapter model requirements
- **Too many references at full weight**: With 4+ references, keep individual weights at 0.5–0.7 to avoid over-constraining
- **Forgetting IPAdapterModelLoader**: Must be in workflow, not just the Apply node
