# ComfyUI Integration for Creative Asset Generation

> Reference for using ComfyUI (Stable Diffusion) to generate character art and creative assets for desktop apps.

## When to Use

- Generating unique character sprites/variants for pet/companion apps
- Creating state-specific artwork (happy, sad, working, error states)
- Producing background elements, particle effects, or ambient visuals
- Rapid prototyping of visual styles before committing to hand-crafted SVGs

## Setup Requirements

- ComfyUI running on Windows host (accessible from WSL at `http://127.0.0.1:8188`)
- SD 1.5 model minimum (SDXL for higher quality)
- `--lowvram` flag for 8GB VRAM GPUs (RTX 4060)

## API Usage from WSL

```bash
# Check status
curl http://127.0.0.1:8188/system_stats

# Generate image via workflow
curl -X POST http://127.0.0.1:8188/api/prompt \
  -H "Content-Type: application/json" \
  -d @workflow.json
```

## Helper Scripts

- `~/.hermes/scripts/comfyui.sh status|start|stop|generate` — manage ComfyUI from WSL
- `~/.hermes/skills/creative/comfyui/scripts/run_workflow.py` — run workflow JSON files

## Model Management

```bash
# Download models via comfy-cli
comfy --workspace C:\Users\luned\ComfyUI model download \
  --url <huggingface_url> \
  --relative-path models/checkpoints
```

## Integration Pattern for DaemonCore

1. User selects "Generate new look" in character selector
2. Frontend sends request to Rust backend via Tauri command
3. Rust backend calls ComfyUI API with character-specific prompt
4. Generated image saved to `public/characters/<char-id>/generated/`
5. Frontend loads generated image as alternative to SVG

## Prompt Tips for Character Art

- Use consistent seed for reproducible results
- Include style keywords: "cartoon", "flat design", "minimal", "cute"
- Specify view: "front view", "icon", "sprite"
- Use negative prompts: "text", "watermark", "blurry"
- 512x512 for icons/sprites, 1024x1024 for detailed characters

## Performance

- SD 1.5 on RTX 4060: ~15-30s per 512x512 image with --lowvram
- Batch generation: queue multiple prompts, process sequentially
- Cache generated images to avoid regeneration
