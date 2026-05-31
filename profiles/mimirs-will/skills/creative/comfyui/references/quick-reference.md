# ComfyUI Quick Reference (Condensed)

> Extracted from the full ComfyUI-Reference.md in the vault. Keep this file concise — for full detail, load the vault doc.

## Model Compatibility Matrix

| Architecture | UNet Loader | CLIP Loader | VAE | Notes |
|-------------|-------------|-------------|-----|-------|
| **SD 1.5** | `CheckpointLoader` or `UNETLoader` | `CLIPLoader` type: `stable_diffusion` | SD 1.5 VAE | All-in-one checkpoint common |
| **SDXL** | `UNETLoader` | `DualCLIPLoader` type: `sdxl` (clip_l + clip_g) | SDXL VAE | Must use dual CLIP; single `CLIPLoader` lost `sdxl` type in v0.22 |
| **Flux** | `UNETLoader` | `DualCLIPLoader` type: `flux` (clip_l + t5xxl) | Flux VAE | T5XXL text encoder required |
| **SD 3 / 3.5** | `UNETLoader` | `DualCLIPLoader` type: `sd3` | SD3 VAE | Triple CLIP possible |
| **Wan 2.1** | `UNETLoader` | `DualCLIPLoader` type: `wan` | Wan VAE | Video generation |
| **HunyuanVideo** | `UNETLoader` | `DualCLIPLoader` type: `hunyuan_video` | Hunyuan VAE | Video generation |

## Critical Rule

**Mismatched CLIP + UNet = `NoneType.shape` crash.** SDXL UNet + non-SDXL CLIP (e.g., Qwen LLM) → KSampler crashes at `model_base.py:encode_adm`. Always match architecture.

## DualCLIPLoader Types (v0.22)

```
sdxl, sd3, flux, hunyuan_video, hidream, hunyuan_image,
hunyuan_video_15, kandinsky5, kandinsky5_image, ltxv, newbie, ace
```

## KSampler Quick Reference

| Param | Typical Range | Notes |
|-------|--------------|-------|
| `steps` | 20-30 | More = slower, diminishing returns after 30 |
| `cfg` | 5-8 | Higher = more literal, lower = more creative |
| `sampler_name` | `euler`, `euler_ancestral`, `dpmpp_2m` | Euler is fastest, DPM++ is highest quality |
| `scheduler` | `normal`, `karras` | Karras better at low step counts |
| `denoise` | 0.3-1.0 | 1.0 = full generation, 0.4 = light refinement (hires fix) |

## VRAM Tips (RTX 4060 8GB)

- Always use `--lowvram`
- Tiled VAE decode is automatic fallback when full-frame OOMs
- SDXL at 768x768: ~5.7 GB model load, tiled VAE for decode
- Batch size 1 recommended
- `--preview-method none` saves ~200 MB VRAM

## API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/system_stats` | GET | Server status, GPU info |
| `/api/prompt` | POST | Submit workflow |
| `/api/queue` | GET | Queue status |
| `/api/history` | GET | Execution history |
| `/api/view` | GET | Retrieve image |
| `/api/upload/image` | POST | Upload image |
| `/api/interrupt` | POST | Cancel running |
| `/api/free` | POST | Free GPU memory |
| `/api/object_info` | GET | Node schema |
| `/ws` | WebSocket | Real-time events |

## Model Download (curl from WSL)

```bash
# SDXL CLIP-L
curl -L -o /mnt/c/Users/luned/ComfyUI/models/text_encoders/clip_l.safetensors \
  "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors"

# SDXL CLIP-G
curl -L -o /mnt/c/Users/luned/ComfyUI/models/text_encoders/clip_g.safetensors \
  "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/text_encoder_2/model.safetensors"

# SDXL VAE
curl -L -o /mnt/c/Users/luned/ComfyUI/models/vae/sdxl_vae.safetensors \
  "https://huggingface.co/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors"
```

**Note:** Use `resolve/main/` URLs directly (not `/blob/`). `Invoke-WebRequest` in PowerShell often times out on large files.

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `NoneType.shape` | CLIP/UNet mismatch | Use matching architecture CLIP |
| `type: 'sdxl' not in list` | v0.22 removed from `CLIPLoader` | Use `DualCLIPLoader` |
| `Ran out of memory...tiled VAE` | Insufficient VRAM for VAE decode | Automatic fallback; reduce resolution |
| `Unsupported Pytorch` | PyTorch < 2.8 | `pip install --upgrade torch` |
| `unknown parameter 'prompt'` | `--args` only overrides `$`-refs | Edit workflow to use `$param` references |
| `InvalidChannel` spam in logs | Manager uses deprecated ltdrdata URL | Update `channel_url` in `user/__manager/config.ini` to `https://api.comfy.org/nodes` |
| `security_level must be normal or below` | Manager security policy blocks installs | Set `network_mode = personal_cloud` and `security_level = normal` in `user/__manager/config.ini` |
| `GPU/Accelerator not supported` warning | Extension dependency on deprecated `pynvml` | Cosmetic warning only; install works despite warning |

## IPAdapter Plus

For multi-image reference composition (e.g., combining multiple character portraits into one scene):

1. **Install:** `git clone` into `custom_nodes/ComfyUI_IPAdapter_plus/` (NOT pip)
2. **Models:** `ip-adapter-plus_sdxl_vit-h.safetensors` in `models/ipadapter/`, `CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors` in `models/clip_vision/`
3. **Chain `IPAdapterAdvanced` nodes** with `combine_embeds: concat`, weight 0.6–0.7 per reference
4. **Stagger `start_at`/`end_at`** for better individual character representation
5. **See full reference:** `references/ipadapter-plus.md`

## More Info

- **Full reference:** `ComfyUI-Reference.md` in vault
- **Workflow docs:** `comfyui.md` in vault
- **Project info:** `~/.hermes/projects/info/comfyui.md`
- **Official docs:** https://docs.comfy.org/
- **Wiki:** https://comfyui-wiki.com/en
