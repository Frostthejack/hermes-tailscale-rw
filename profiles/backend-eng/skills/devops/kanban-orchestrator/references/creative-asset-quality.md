# Creative Asset Generation — Quality Guidance

## User Design Preferences (Virtual Pet Characters)

**Source:** Direct user feedback, 2026-05-16. The user explicitly rejected the previous emoji + CSS pulse approach as insufficient.

### Core Principles

1. **"I want it to function but I also want it to look good. I don't want to settle for what we had before."**
   — Functionality is necessary but not sufficient. Visual quality is equally important.

2. **"I dont want overly simple characters because then they just seem like stationary objects jiggeling without any personality."**
   — Emoji, plain shapes, and simple CSS animations are NOT acceptable for virtual pets. Characters must feel alive.

3. **Characters must be recognizable creatures**, not abstract shapes:
   - **Owls**: Big round eyes, feather textures, ear tufts, proper anatomy
   - **Foxes**: Bushy tails, pointed snouts, recognizable silhouette
   - **Pixies**: NOT humanoid — clusters of various-sized glowing circles creating a sparkle/fairy dust effect, like a living constellation of light

4. **Personality through animation** — not just one pulse/bounce, but:
   - Idle: breathing/bobbing, occasional blinking, tail/ear twitches
   - Busy: faster movement, typing/bouncing energy, focused eyes
   - Thinking: head tilting, slow circling, puzzled expression
   - Approval needed: waving/shaking, urgent but cute, wide eyes
   - Error: drooped ears/tail, sad eyes, wobble
   - Success: happy bounce, sparkles, perked up
   - Offline: sleeping pose, slow breathing, "Zzz" particles

5. **Art style preference**: Cute/stylized but NOT blocky. Detailed enough to be recognizable as the creature type. Think "virtual pet" quality (Tamagotchi, Nintendogs) not "emoji with CSS."

### Rendering Approach

- **Owls and Foxes**: Hand-crafted SVG with individually animated parts (eyes, ears, tail, wings) + JS-driven state animations
- **Pixies**: Canvas 2D particle system with layered radial-gradient circles and opacity animations for glow/sparkle effect
- **NOT acceptable**: Plain emoji, CSS-only animations, simple geometric shapes, single-state sprites

## Lesson: SVG Asset Creation Needs Detailed Specs

When creating kanban tasks for creative asset generation (SVGs, images, icons), the task body MUST include:

1. **Detailed visual description**: Don't just say "create an SVG of X." Describe the art style, level of detail, specific elements required (gradients, shadows, facial features, etc.)
2. **Reference examples**: Link to or describe existing assets that match the desired quality level
3. **Technical requirements**: ViewBox size, color palette, animation requirements, file size constraints
4. **Quality checklist**: Specific things to verify (e.g., "eyes should have pupils AND highlights," "use radial gradients for depth")

## What Went Wrong (Round 1)

The SVG asset task said "Create SVG assets for pet states" with basic descriptions. The worker produced plain colored circles with minimal detail. The user rejected them: "looks like they are just colored circles that are plain."

## What Went Wrong (Round 2)

The app rendered pets as plain emoji (🐾, 🤔) at 48px font-size with a basic CSS pulse animation. The user rejected this: "stationary objects jiggling without any personality." Even though the app functioned correctly (webhook, tray, multi-window, approvals all worked), the character quality was fundamentally insufficient.

## Better Approach

For pet character tasks, the body should specify:
- **Anatomy**: "Create detailed cartoon owl with proper anatomy: round body, large eyes with pupils AND highlights, ear tufts, small beak, wing stubs, talons"
- **Art style**: "Cute/stylized proportions (slightly big head), warm color palette, soft edges with subtle gradients for depth"
- **Animation requirements**: "Each body part must be individually animatable: eyes blink independently, ears twitch, tail sways, wings flutter"
- **State variations**: "6 visual states (idle, busy, thinking, approval_needed, error, success) with distinct expressions and body language"
- **Pixie variant**: "For pixie-type characters: use Canvas 2D particle system with 15-25 circles of varying sizes (3-15px), warm golden/blue/silver glow, radial gradients with animated opacity for sparkle effect"
- **Quality bar**: "Should look like a professional virtual pet (Tamagotchi/Nintendogs quality), not a geometric shape or emoji"

## When to Search First

Before delegating creative asset creation, SEARCH for existing high-quality assets:
- OpenClipart.org (CC0 public domain SVGs)
- Wikimedia Commons (search for "cartoon X svg")
- SVGRepo.com

If suitable base assets exist, the task becomes "adapt existing SVG" which is higher quality than "create from scratch."

## Verification Step

When a creative asset task completes, the orchestrator should:
1. Visually inspect the output (render in browser or use vision tool)
2. Compare against the quality bar described in the task
3. Check that animations actually work (not just static images)
4. Verify all 6+ states have distinct visual differences
5. If quality is insufficient, block the task with specific feedback rather than accepting it
