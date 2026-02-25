# AI Scene Generator -- Godot Plugin

A Godot 4.x `@tool` EditorPlugin that generates 3D scenes from natural-language prompts. Type a description like *"a medieval courtyard with a well in the center"* and get a validated, deterministic 3D scene built directly in the editor viewport.

## Key Features

- **Prompt-to-Scene pipeline** -- natural language in, 3D scene out
- **Safety by design** -- the AI produces JSON data (SceneSpec), never code. All outputs are validated against strict allowlists.
- **Deterministic** -- same prompt + seed + settings = identical scene
- **Offline-capable** -- built-in MockProvider works without API keys
- **Pluggable LLM backends** -- OpenAI, Anthropic, Ollama, or Mock
- **Asset-aware** -- tag your project assets and the AI will reference them; unmatched tags fall back to procedural primitives
- **Fully undoable** -- all scene changes go through the editor undo system

## Requirements

- Godot 4.4+ (developed on 4.6.1)
- Pure GDScript, no GDExtension dependencies

## Quick Start

1. Copy `addons/ai_scene_gen/` into your project's `addons/` directory
2. Enable the plugin: Project > Project Settings > Plugins > "AI Scene Generator"
3. Open or create a 3D scene (Node3D root)
4. Use the dock panel on the right: type a prompt, click **Generate Scene**
5. Preview appears in the viewport -- click **Apply** to commit or **Discard** to remove

## Architecture

The plugin follows a strict modular architecture with 12 modules (A-L):

| Module | Role | File |
|--------|------|------|
| A: UI Dock | Prompt input, controls, error display | `ui/ai_scene_gen_dock.gd` |
| B: Orchestrator | Pipeline state machine | `core/orchestrator.gd` |
| C: LLM Provider | Pluggable AI backends | `llm/llm_provider.gd` |
| D: Prompt Compiler | Builds the LLM prompt | `core/prompt_compiler.gd` |
| E: Validator | JSON schema validation + security | `core/scene_spec_validator.gd` |
| F: Asset Resolver | Tag-to-resource mapping | `assets/asset_resolver.gd` |
| G: Primitive Factory | Procedural 3D shapes | `factory/procedural_primitive_factory.gd` |
| H: Scene Builder | Deterministic node tree builder | `core/scene_builder.gd` |
| I: Post-Processor | Bounds clamping, camera framing | `core/post_processor.gd` |
| J: Preview Layer | Temporary preview management | `core/preview_layer.gd` |
| K: Logger | Centralized logging | `util/logger.gd` |
| L: Persistence | Settings and file I/O | `util/persistence.gd` |

See [ARCHITECTURE_INTEGRATED.md](ARCHITECTURE_INTEGRATED.md) for the full design document.

## Safety Model

- LLM output is **only parsed as JSON** -- never `eval()`'d, never executed
- Node types and primitive shapes are checked against hardcoded allowlists
- All transforms are bounded (position, scale, light energy)
- Code injection patterns are detected and rejected
- API keys are stored in EditorSettings, not in project files
- Only the compiled prompt is sent to the LLM -- no file paths, no project names

## Project Structure

```
Project_X/
  project.godot
  ARCHITECTURE_INTEGRATED.md      # Full design document (2100+ lines)
  README.md                       # This file
  addons/ai_scene_gen/            # The plugin
    plugin.cfg
    plugin.gd                     # EditorPlugin entry point
    core/                         # Pipeline modules (B, D, E, H, I, J)
    types/                        # Data transfer objects
    llm/                          # LLM provider interface + implementations
    assets/                       # Asset tag registry + resolver
    factory/                      # Procedural primitive generation
    ui/                           # Editor dock panel
    util/                         # Logger + persistence
    mocks/                        # Canned SceneSpec JSON for testing
    tests/                        # GUT test suite
    docs/                         # Plugin documentation
```

## License

TBD
