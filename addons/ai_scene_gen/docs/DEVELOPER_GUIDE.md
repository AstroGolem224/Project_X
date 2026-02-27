# AI Scene Generator — Developer Guide

This guide is for developers contributing to the AI Scene Generator plugin (Godot 4.6.1, pure GDScript).

---

## Architecture Overview

The plugin uses 12 modules (A–L), all **composition-based** (RefCounted), connected via signals in `plugin.gd`:

| Module | class_name | File | extends | Role |
|--------|-----------|------|---------|------|
| A: UI Dock | AiSceneGenDock | ui/ai_scene_gen_dock.gd | Control | Prompt input, settings, state management |
| B: Orchestrator | AiSceneGenOrchestrator | core/orchestrator.gd | RefCounted | Pipeline state machine |
| C: LLM Provider | LLMProvider | llm/llm_provider.gd | RefCounted | Abstract base for AI backends |
| C1: Mock | MockProvider | llm/mock_provider.gd | LLMProvider | Canned responses (offline) |
| C2: Ollama | OllamaProvider | llm/ollama_provider.gd | LLMProvider | Local LLM via HTTP |
| C3: OpenAI | OpenAIProvider | llm/openai_provider.gd | LLMProvider | Chat Completions API |
| C4: Anthropic | AnthropicProvider | llm/anthropic_provider.gd | LLMProvider | Messages API |
| D: Prompt Compiler | PromptCompiler | core/prompt_compiler.gd | RefCounted | Builds LLM prompts |
| E: Validator | SceneSpecValidator | core/scene_spec_validator.gd | RefCounted | JSON schema validation |
| F: Asset Registry | AssetTagRegistry | assets/asset_tag_registry.gd | Resource | Tag storage |
| F: Asset Resolver | AssetResolver | assets/asset_resolver.gd | RefCounted | Tag → asset resolution |
| G: Primitive Factory | ProceduralPrimitiveFactory | factory/procedural_primitive_factory.gd | RefCounted | 5 primitive shapes |
| H: Scene Builder | SceneBuilder | core/scene_builder.gd | RefCounted | Deterministic node tree |
| I: Post-Processor | PostProcessor | core/post_processor.gd | RefCounted | 5 passes |
| J: Preview Layer | PreviewLayer | core/preview_layer.gd | RefCounted | Temp preview + undo |
| K: Logger | AiSceneGenLogger | util/logger.gd | RefCounted | 4 log levels + metrics |
| L: Persistence | AiSceneGenPersistence | util/persistence.gd | RefCounted | Settings, SceneSpec I/O, cache |

---

## Signal Wiring (plugin.gd)

```
Dock.generate_requested           → plugin._on_generate_requested           → await orchestrator.start_generation()
Dock.apply_requested              → plugin._on_apply_requested              → orchestrator.apply_preview(undo_redo, root)
Dock.discard_requested            → plugin._on_discard_requested           → orchestrator.discard_preview()
Dock.provider_changed             → plugin._on_provider_changed              → orchestrator.set_llm_provider() + await fetch_models
Dock.import_requested              → plugin._on_import_requested            → EditorFileDialog → persistence.import_spec → orchestrator.rebuild_from_spec
Dock.export_requested             → plugin._on_export_requested             → EditorFileDialog → persistence.export_spec
Dock.connection_test_requested    → plugin._on_connection_test_requested    → await fetch_available_models → dock.show_connection_result

orchestrator.pipeline_state_changed → dock.set_state()
orchestrator.pipeline_progress      → dock.show_progress()
orchestrator.pipeline_completed     → dock.show_progress(1.0)
orchestrator.pipeline_failed        → dock.show_errors()
```

---

## Pipeline Flow

### Single-Stage (default)

1. `PromptCompiler.compile_single_stage(request)` → compiled_prompt
2. `await LLMProvider.send_request(prompt, model, 0.0, seed)` → LLMResponse  
   (up to 2 retries on failure, `correlation_id` guard after each `await`)
2b. `_strip_markdown_fences(raw_json)` — remove \`\`\`json fences  
2c. `_patch_spec_fields(raw_json, request)` — inject system-managed fields  
   (prompt_hash, seed, variation_mode, fingerprint, timestamps, sky_type default;
   remove misplaced top-level fields like `generator`)
3. `SceneSpecValidator.validate_json_string(raw_json)` → ValidationResult  
   **Schema-Retry** (up to `MAX_SCHEMA_RETRIES=2`):
   - a. `PromptCompiler.compile_retry_stage(request, raw_json, errors)`
   - b. `await LLMProvider.send_request(retry_prompt, ...)` → LLMResponse
   - c. `_patch_spec_fields(new_raw_json, request)` — patch retry output too
   - d. Validate again
4. `AssetResolver.resolve_nodes(spec, registry)` → ResolvedSpec
5. `SceneBuilder.build(resolved_spec, preview_root)` → BuildResult
6. `PostProcessor.execute_all(root, spec)` → warnings
7. `PreviewLayer.show_preview(root, scene_root)`

### Two-Stage (>30 words or checkbox)

Same as above, but steps 1–2 become:

1a. `compile_plan_stage` → plan_prompt  
1b. `await send_request` → plan_text  
1c. `compile_spec_stage(request, plan_text)` → spec_prompt  
1d. `await send_request` → raw_json (with retries)

---

## Adding a New LLM Provider

1. Create `addons/ai_scene_gen/llm/my_provider.gd`:

```gdscript
@tool
class_name MyProvider
extends LLMProvider

func get_provider_name() -> String:
    return "MyProvider"

func get_available_models() -> Array[String]:
    var result: Array[String] = ["model-a", "model-b"]
    return result

func is_configured() -> bool:
    return _http_node != null and not _api_key.is_empty()

func needs_api_key() -> bool:
    return true  # or false

func needs_base_url() -> bool:
    return false  # or true

func send_request(compiled_prompt: String, model: String, temperature: float, seed: int) -> LLMResponse:
    # Implement HTTP call using _http_node
    # Return LLMResponse.create_success(text, elapsed_ms, token_usage)
    # Or LLMResponse.create_failure(error_code, message, elapsed_ms)
    return LLMResponse.create_failure("LLM_ERR_NOT_CONFIGURED", "Not implemented", 0)

func fetch_available_models() -> Array[String]:
    # Async model fetching via _http_node
    return get_available_models()
```

2. Register in `plugin.gd` `_register_providers()`:

```gdscript
var my: MyProvider = MyProvider.new(_logger)
my.set_http_node(_http_request)
_providers["MyProvider"] = my
```

3. Add tests in `tests/test_my_provider.gd`.

---

## Adding a Post-Processing Pass

1. Add an inner class in `core/post_processor.gd`:

```gdscript
class MyCustomPass extends PostProcessorPass:
    func get_pass_name() -> String:
        return "MyCustomPass"

    func execute(root: Node3D, spec: Dictionary) -> Array[Dictionary]:
        var warnings: Array[Dictionary] = []
        # Process nodes under root
        # Use _make_warning(code, message, fix_hint, node_path) for warnings
        return warnings
```

2. Add it to the `_passes` array in `PostProcessor._init()`:

```gdscript
_passes = [
    BoundsClampPass.new(logger),
    SnapToGroundPass.new(logger),
    CameraFramingPass.new(logger),
    CollisionCheckPass.new(logger),
    NamingPass.new(logger),
    MyCustomPass.new(logger),  # ← add here
]
```

**Current 5 passes** (executed in order):

1. **BoundsClamp**: clamps node positions to scene bounds
2. **SnapToGround**: warns about floating nodes (if snap_to_ground rule set)
3. **CameraFraming**: repositions camera to frame the scene AABB
4. **CollisionCheck**: detects significant AABB overlaps between meshes
5. **NamingPass**: deduplicates node names with `_N` suffixes

---

## Registering Asset Packs

Asset tags map string identifiers to project resources. The `AssetTagRegistry` (extends Resource) stores entries.

```gdscript
var registry: AssetTagRegistry = orchestrator.get_asset_registry()
registry.register_tag("medieval_well", "res://assets/medieval/well.tscn")
registry.register_tag("oak_tree", "res://assets/nature/oak.tscn")
```

Optional metadata (e.g. `resource_type`, `thumbnail_path`, `fallback`) can be passed as a third argument:

```gdscript
registry.register_tag("test_tree", "res://assets/trees/oak.tscn", {
    "resource_type": "PackedScene",
    "thumbnail_path": "res://thumbnails/oak.png"
})
```

When the LLM outputs `"asset_tag": "medieval_well"`, the `AssetResolver` loads that resource instead of creating a procedural primitive. Unmatched tags fall back to primitives.

---

## GDScript Conventions (STRICTLY enforced)

- `@tool` on all scripts that run in the editor
- Explicit types on **every** variable, parameter, and return value. No type inference.
- Typed collections: `Array[String]`, `Array[Dictionary]`, etc.
- **Important**: When passing arrays to typed parameters, declare as typed variable first:  
  `var x: Array[String] = ["a"]` then pass `x`. Untyped literals can crash on dynamic dispatch.
- `snake_case` for functions/variables, `PascalCase` for classes, `UPPER_SNAKE_CASE` for constants
- `_` prefix for private members
- Signals with typed signatures; connect via `.connect()`
- `await` instead of `yield`
- `##` Doxygen-style docs on public functions
- No comments that just narrate code
- File order: class_name/extends → signals → enums/constants → @export → @onready → private vars → _ready → public methods → private methods
- Composition over inheritance, signals over direct references
- RefCounted for all non-UI modules

---

## Test Conventions

- **Test framework**: GUT 9.6.0 (in `addons/gut/`)
- **Test files** in `addons/ai_scene_gen/tests/` (has `.gdignore` so Godot doesn't scan)
- ~161 tests across 10 test files, all PASS
- **Naming**: `test_{module}.gd`; test functions: `test_{description}()`
- Each test file: `extends GutTest`
- Use `assert_eq`, `assert_true`, `assert_false`, `assert_not_null`, `assert_null`
- Tests run headless: `godot --headless -s addons/gut/gut_cmdln.gd -gexit`

### Running Tests Locally

1. Install GUT:

```bash
git clone --depth 1 https://github.com/bitwes/Gut.git /tmp/gut
cp -r /tmp/gut/addons/gut addons/gut
```

2. Import project:

```bash
godot --headless --import
```

3. Run tests:

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gexit
```

### Test Files

| File | Tests | Coverage |
|------|-------|----------|
| test_validator.gd | 19 | Schema validation (T01-T13, T38, T39) |
| test_primitive_factory.gd | 16 | Primitive shapes (T24, T25) |
| test_prompt_compiler.gd | 20 | Prompt compilation (T14-T16 + variation + retry) |
| test_scene_builder.gd | 7 | Scene building (T26, T27) |
| test_asset_resolver.gd | 11 | Asset resolution (T21-T23) |
| test_ollama_provider.gd | 14 | Ollama config, errors, cancel |
| test_openai_provider.gd | 19 | OpenAI config, errors, cancel, models |
| test_anthropic_provider.gd | 19 | Anthropic config, errors, cancel, models |
| test_orchestrator.gd | 15 | Pipeline, cancel, two-stage, correlation, schema-retry |
| test_dock.gd | 14 | Request shape, flags, tags, states |

### CI (GitHub Actions)

- **Workflow**: `.github/workflows/test.yml`
- Runs on every push/PR to `main`
- Godot 4.6.1 headless + GUT
- All tests must pass

---

## File Structure

```
addons/ai_scene_gen/
  plugin.cfg
  plugin.gd
  core/
    orchestrator.gd
    prompt_compiler.gd
    scene_spec_validator.gd
    scene_builder.gd
    post_processor.gd
    preview_layer.gd
  types/
    llm_response.gd
    validation_result.gd
    build_result.gd
    resolved_spec.gd
  llm/
    llm_provider.gd
    mock_provider.gd
    ollama_provider.gd
    openai_provider.gd
    anthropic_provider.gd
  assets/
    asset_tag_registry.gd
    asset_resolver.gd
  factory/
    procedural_primitive_factory.gd
  ui/
    ai_scene_gen_dock.gd
  util/
    logger.gd
    persistence.gd
  mocks/
    outdoor_clearing.scenespec.json
    interior_room.scenespec.json
  cache/
    models_*.json           # Provider model caches
  tests/
    test_validator.gd
    test_primitive_factory.gd
    test_prompt_compiler.gd
    test_scene_builder.gd
    test_asset_resolver.gd
    test_ollama_provider.gd
    test_openai_provider.gd
    test_anthropic_provider.gd
    test_orchestrator.gd
    test_dock.gd
  docs/
    README.md
    USER_GUIDE.md
    OPERATOR_GUIDE.md
    DEVELOPER_GUIDE.md
    TROUBLESHOOTING.md
    FAQ.md
```

---

## Key Types Reference

| Type | File | Purpose |
|------|------|---------|
| LLMResponse | types/llm_response.gd | `create_success(text, elapsed_ms, token_usage)` / `create_failure(code, message, elapsed_ms)` |
| ValidationResult | types/validation_result.gd | `valid`, `raw_json`, `errors` |
| BuildResult | types/build_result.gd | `root`, `warnings` |
| ResolvedSpec | types/resolved_spec.gd | Resolved nodes with asset paths |

---

## Further Reading

- [USER_GUIDE.md](USER_GUIDE.md) — End-user workflow
- [OPERATOR_GUIDE.md](OPERATOR_GUIDE.md) — Configuration and asset packs
