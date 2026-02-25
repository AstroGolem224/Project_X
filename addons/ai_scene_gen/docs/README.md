# AI Scene Generator - Godot Plugin

## What It Does

This EditorPlugin lets you type a natural-language prompt and generates a 3D scene directly in the Godot editor. It uses a validated JSON pipeline (SceneSpec) to ensure safety—the AI never executes code, only produces data.

## Requirements

- Godot 4.4+ (tested on 4.6.1)
- Pure GDScript, no GDExtension needed
- Optional: API key for OpenAI/Anthropic (MockProvider works offline)

## Installation

1. Copy the `addons/ai_scene_gen/` folder into your project's `addons/` directory
2. Open Project > Project Settings > Plugins
3. Enable "AI Scene Generator"
4. The dock panel appears in the right dock area

## Quick Start (5-Minute Walkthrough)

1. Open or create a 3D scene (e.g. Node3D as root)
2. Find the "AI Scene Generator" panel in the right dock
3. Type a scene description, e.g.: "a medieval courtyard with a well in the center"
4. Provider: MockProvider (default, works offline)
5. Style: blockout (grey-box prototyping)
6. Click "Generate Scene"
7. Preview appears in the viewport with temporary nodes
8. Click "Apply" to commit to the scene, or "Discard" to remove

## Plugin Architecture

Brief overview with the module list:

- **A: UI Dock** – prompt input and controls
- **B: Orchestrator** – pipeline state machine
- **C: LLM Provider** – pluggable AI backends (Mock, OpenAI, Anthropic, Ollama)
- **D: Prompt Compiler** – builds the LLM prompt from user inputs
- **E: SceneSpec Validator** – validates the JSON schema with security checks
- **F: Asset Registry + Resolver** – maps tags to project assets
- **G: Primitive Factory** – generates basic 3D shapes as fallbacks
- **H: Scene Builder** – deterministic node tree construction
- **I: Post-Processor** – bounds clamping, camera framing, collision checks
- **J: Preview Layer** – temporary preview management
- **K: Logger** – centralized logging
- **L: Persistence** – settings and file I/O

## Safety Model

- The LLM never executes code. It only produces JSON data.
- All node types are checked against an allowlist
- All positions are bounded. All scales are limited.
- Code injection patterns are detected and rejected
- API keys are stored in EditorSettings, not in project files

## Style Presets

- **blockout**: Simple shapes, muted colors, grey-box prototyping
- **stylized**: Rounded shapes, vibrant colors, stylized look
- **realistic-lite**: Realistic proportions, neutral palette

## SceneSpec

The plugin uses a JSON format called SceneSpec (v1.0.0) as the bridge between AI and engine. You can export/import these files for reproducibility.

## Configuration

- **Seed**: Integer for deterministic generation. Same seed = same scene.
- **Bounds**: Scene bounding box in meters (X, Y, Z)
- **Max nodes**: Configurable limit (default 256, max 1024)

## Asset Tags

Register your project assets with tags so the AI can reference them. Unmatched tags fall back to procedural primitives.

## Testing

The plugin includes a GUT test suite under `tests/`. Install the GUT addon and run the tests from the GUT panel.

## License

TBD

## Links

- Architecture document: see `ARCHITECTURE_INTEGRATED.md` in the project root
