# AI Scene Generator - Godot Plugin

[![Tests](https://github.com/AstroGolem224/Project_X/actions/workflows/test.yml/badge.svg)](https://github.com/AstroGolem224/Project_X/actions/workflows/test.yml)

## What It Does

This EditorPlugin lets you type a natural-language prompt and generates a 3D scene directly in the Godot editor. It uses a validated JSON pipeline (SceneSpec) to ensure safety—the AI never executes code, only produces data.

## Requirements

- Godot 4.4+ (tested on 4.6.1)
- Pure GDScript, no GDExtension needed
- Optional: [Ollama](https://ollama.com) for local LLM inference (MockProvider works offline)

## Installation

1. Copy the `addons/ai_scene_gen/` folder into your project's `addons/` directory
2. Open Project > Project Settings > Plugins
3. Enable "AI Scene Generator"
4. The dock panel appears in the right dock area

## Quick Start (5-Minute Walkthrough)

1. Open or create a 3D scene (e.g. Node3D as root)
2. Find the "AI Scene Generator" panel in the right dock
3. Type a scene description, e.g.: "a medieval courtyard with a well in the center"
4. Provider: MockProvider (default, works offline) or Ollama (local LLM)
5. Style: blockout (grey-box prototyping)
6. Click "Generate Scene"
7. Preview appears in the viewport with temporary nodes
8. Click "Apply" to commit to the scene, or "Discard" to remove
9. Ctrl+Z undoes an applied preview (full undo/redo support)

## Providers

| Provider | Setup | API Key | Host URL |
|----------|-------|---------|----------|
| **MockProvider** | None (offline, ships with plugin) | No | — |
| **Ollama** | Install [Ollama](https://ollama.com), run a model | No | Configurable |
| **OpenAI** | [API key](https://platform.openai.com/api-keys) | Yes | — |
| **Anthropic** | [API key](https://console.anthropic.com) | Yes | — |

Select the provider from the dropdown. Models are fetched automatically.
Use "Test Connection" to verify connectivity and refresh the model list.
To use a model not in the dropdown, type its name in the **Custom** field (e.g. `qwen3.5:27b`).

### Remote Ollama (e.g. another machine on your LAN)

By default Ollama connects to `http://localhost:11434`. To use a remote
instance:

1. On the remote machine, start Ollama bound to all interfaces:
   ```bash
   OLLAMA_HOST=0.0.0.0 ollama serve
   ```
2. Find the remote machine's LAN IP (e.g. `192.168.1.42`)
3. In the plugin dock, select Ollama as provider
4. Enter `http://192.168.1.42:11434` in the **Host** field
5. The URL is persisted in Godot's EditorSettings — no need to re-enter

## Import / Export

- **Export Spec**: Save the last generated SceneSpec as `.scenespec.json`
- **Import Spec**: Load a SceneSpec and rebuild the scene (skips LLM call)

## Plugin Architecture

Brief overview with the module list:

- **A: UI Dock** – prompt input and controls
- **B: Orchestrator** – pipeline state machine
- **C: LLM Provider** – pluggable AI backends (Mock, Ollama, OpenAI, Anthropic)
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

- **Host URL**: Base URL for providers that support it (e.g. Ollama). Stored per-provider in EditorSettings.
- **API Key**: For providers that require authentication. Stored securely in EditorSettings.
- **Seed**: Integer for deterministic generation. Same seed = same scene.
- **Bounds**: Scene bounding box in meters (X, Y, Z)
- **Max nodes**: Configurable limit (default 256, max 1024)

## Asset Tags

Register your project assets with tags so the AI can reference them. Unmatched tags fall back to procedural primitives.

## Testing

The plugin includes 161 GUT tests across 10 test files under `tests/`.

**Local setup:**

1. Install [GUT](https://github.com/bitwes/Gut) (v9.x) into `addons/gut/`:
   ```bash
   git clone --depth 1 https://github.com/bitwes/Gut.git /tmp/gut
   cp -r /tmp/gut/addons/gut addons/gut
   ```
2. Import the project: `godot --headless --import`
3. Run tests headless:
   ```bash
   godot --headless -s addons/gut/gut_cmdln.gd -gexit
   ```

Tests also run automatically via GitHub Actions on every push/PR to `main`.

## License

TBD

## Documentation

- [User Guide](USER_GUIDE.md) — full UI walkthrough, prompt tips, features
- [Operator Guide](OPERATOR_GUIDE.md) — provider setup, API keys, security, tuning
- [Developer Guide](DEVELOPER_GUIDE.md) — architecture, adding providers/passes, testing
- [Troubleshooting](TROUBLESHOOTING.md) — error code table, common problems
- [FAQ](FAQ.md) — frequently asked questions
- Architecture document: see `ARCHITECTURE_INTEGRATED.md` in the project root
