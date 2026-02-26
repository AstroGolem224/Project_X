# Agent Handoff: AI Scene Generator Plugin

> Dieses Dokument ist der vollstaendige Kontext fuer den naechsten Agenten.
> Lies zuerst dieses File, dann ARCHITECTURE_INTEGRATED.md fuer Details.

## Projekt-Ueberblick

**Repo:** [https://github.com/AstroGolem224/Project_X.git](https://github.com/AstroGolem224/Project_X.git)
**Branch:** main
**Workspace:** `c:\Users\matth\OneDrive\Dokumente\GitHub\Project_X`
**Engine:** Godot 4.6.1 stable, pure GDScript, kein GDExtension
**Godot Pfad:** `J:\Godot\Godot_v4.6.1-stable_win64.exe`
**Typ:** `@tool` EditorPlugin unter `addons/ai_scene_gen/`

Ein Godot-Plugin das aus natuerlichsprachigen Prompts 3D-Szenen generiert.
Der LLM gibt JSON (SceneSpec) zurueck, das validiert und deterministisch
in einen Godot Node-Tree gebaut wird. Kein eval(), kein Code-Execution.

## Aktueller Stand: MVP + ASYNC + UNDO + IMPORT/EXPORT + TWO-STAGE + VARIATION/TAGS + CI/CD + PROVIDERS (Phase 1-6 + Prio 1-7)

Alle 12 Module (A-L) sind implementiert, verdrahtet, und **fehlerfrei getestet**.
Plugin laedt und entlaedt in Godot 4.6.1 headless ohne Fehler/Warnings.
Generate-Pipeline laeuft komplett durch (mit MockProvider).
Two-Stage Generation Mode ist implementiert und getestet.
Variation Mode und Asset Tag Browser sind implementiert und getestet.
OpenAI + Anthropic Provider sind implementiert, integriert, und getestet.
147 GUT Tests (10 Test-Files) laufen headless, GitHub Actions CI aktiv.

### Was bisher implementiert wurde

**Phase 1-6 (MVP):**

- Alle 12 Module (A-L) implementiert und verdrahtet
- Plugin laedt/entlaedt fehlerfrei in Godot 4.6.1
- 7 Bugs gefixt (@tool auf Type-Scripts, typed Array Safety, null Guards, lokale Transforms)

**Prio 1: Async Pipeline + LLM Provider (✅ ERLEDIGT)**

- `LLMProvider` Basisklasse: `_http_node` Injection (RefCounted kann keine Nodes ownen),
`_api_key` Management, `cancel()`, `fetch_available_models()` (async-faehig)
- `OllamaProvider`: async `send_request()` via `await _http_node.request_completed`
gegen `localhost:11434/api/generate`, Model-Liste via `/api/tags`,
volles Error-Mapping (LLM_ERR_NETWORK/TIMEOUT/AUTH/RATE_LIMIT/SERVER/NON_JSON),
konfigurierbare Base-URL via `set_base_url()` (fuer Remote-Instanzen)
- `Orchestrator.start_generation()` ist async mit `await` auf LLM-Call,
Cancellation-Guard via `_correlation_id` nach jedem await
- `plugin.gd`: HTTPRequest-Node Lifecycle, Provider-Registry (MockProvider + Ollama),
dynamisches Provider-Switching mit async Model-Fetch, API-Key Persistence via EditorSettings
- Dock: `provider_changed` Signal, API-Key Feld (secret, toggle per Provider),
Host-URL Feld (sichtbar wenn Provider `needs_base_url()` meldet),
Provider-Dropdown Verdrahtung
- Persistence: `get_provider_url()` / `set_provider_url()` fuer Host-URLs in EditorSettings
- MockProvider: unveraendert synchron, `await` auf non-Coroutine returned sofort

**Prio 2: EditorUndoRedoManager (✅ ERLEDIGT)**

- `PreviewLayer.apply_to_scene(undo_redo: EditorUndoRedoManager, scene_root: Node3D)`
- `_do_apply()` / `_undo_apply()` private Methoden mit `_applied_children: Array[Node]` Tracking
- `create_action("AI Scene Gen: Apply Preview")` + `add_do_method` / `add_undo_method`
- `add_do_reference` / `add_undo_reference` auf alle Nodes fuer GC-Safety
- Null-Guard: `undo_redo == null` -> direktes Apply ohne Undo (Test-Kompatibilitaet)
- Plugin uebergibt `get_undo_redo()` bei Apply

**Prio 3: Import/Export UI (✅ ERLEDIGT)**

- Import/Export Buttons im Dock ("Import Spec" / "Export Spec") mit State-Management
- `EditorFileDialog` (ACCESS_RESOURCES, `*.scenespec.json` Filter)
- Import-Flow: Dialog -> `persistence.import_spec(path)` -> `orchestrator.rebuild_from_spec(spec, root)`
- Export-Flow: Spec-Check -> Dialog -> `persistence.export_spec(last_spec, path)`
- Fehlerhandling fuer leere Specs, fehlgeschlagene Imports, Write-Fehler

**Prio 4: Two-Stage Mode + Code-Fixes (✅ ERLEDIGT)**

- Two-Stage Generation Mode im Orchestrator:
  - Heuristik: `request["two_stage"] == true` ODER >30 Woerter im Prompt -> Two-Stage
  - Stage 1: `compile_plan_stage(request)` -> `await send_request()` -> plan_text
  - Stage 2: `compile_spec_stage(request, plan_text)` -> `await send_request()` -> raw_json
  - Cancellation-Guard nach jedem `await` (correlation_id check)
  - Pipeline-Progress: 0.0/0.05/0.15/0.20/0.30 fuer Two-Stage, 0.0/0.10 fuer Single-Stage
  - Single-Stage Pfad bleibt als Default unveraendert
- Dock: "Two-Stage (detailed planning)" CheckBox im Settings-Bereich
- Error-Code Prefixes gefixt: `UI_ERR_EMPTY_PROMPT`, `UI_ERR_INVALID_BOUNDS`, `UI_ERR_INVALID_SEED`
- `get_editor_interface()` deprecated -> `EditorInterface` Singleton (4 Stellen in plugin.gd)
- `cancel_generation()` emittiert jetzt `ORCH_ERR_CANCELLED` via `pipeline_failed`
- Typo-Fix: `ORCH_ERR_ST_type_FAILED` -> `ORCH_ERR_STAGE_FAILED`

### File-Inventar (30 .gd + 3 .json + 2 .md + 1 .yml + plugin.cfg + project.godot)

```
addons/ai_scene_gen/
  plugin.cfg                           # Plugin-Metadaten
  plugin.gd                            # EditorPlugin Entry — verdrahtet alle Module
  core/
    orchestrator.gd                    # B: Async Pipeline State Machine
    prompt_compiler.gd                 # D: Prompt-Zusammenbau (single + two-stage)
    scene_spec_validator.gd            # E: Schema-Validierung (1269 Zeilen)
    scene_builder.gd                   # H: Deterministischer Builder
    post_processor.gd                  # I: 5 Post-Processing Passes
    preview_layer.gd                   # J: Preview + UndoRedo
  types/
    llm_response.gd                    # @tool, LLMResponse mit static factory methods
    validation_result.gd               # @tool, ValidationResult
    build_result.gd                    # @tool, BuildResult
    resolved_spec.gd                   # @tool, ResolvedSpec
  llm/
    llm_provider.gd                    # C: Abstrakte Basisklasse + HTTP/API-Key/Base-URL Infrastruktur
    mock_provider.gd                   # C: Canned-Response Provider (synchron)
    ollama_provider.gd                 # C: Async Ollama Provider (localhost:11434)
    openai_provider.gd                 # C: Async OpenAI Provider (Chat Completions, JSON mode)
    anthropic_provider.gd              # C: Async Anthropic Provider (Messages API)
  assets/
    asset_tag_registry.gd              # F: Tag-Registry (extends Resource, @export)
    asset_resolver.gd                  # F: Tag-Aufloesung mit Fallback
  factory/
    procedural_primitive_factory.gd    # G: 5 Primitives (box/sphere/cylinder/capsule/plane)
  ui/
    ai_scene_gen_dock.gd               # A: Komplettes Dock UI (rein programmatisch)
  util/
    logger.gd                          # @tool, AiSceneGenLogger mit 4 Log-Levels + Metrics
    persistence.gd                     # L: Settings/SceneSpec I/O + API-Key/Host-URL via EditorSettings
  mocks/
    outdoor_clearing.scenespec.json    # Example 1 (Outdoor Clearing mit Baum, Fels, Pfad)
    interior_room.scenespec.json       # Example 2 (Raum mit Waenden und Tisch)
  tests/                               # .gdignore vorhanden (Godot scannt nicht)
    test_validator.gd                  # 19 Tests (T01-T13, T38, T39 + extras)
    test_primitive_factory.gd          # 16 Tests (T24, T25 + extras)
    test_prompt_compiler.gd            # 16 Tests (T14-T16 + variation + extras)
    test_scene_builder.gd              # 7 Tests (T26, T27 + extras)
    test_asset_resolver.gd             # 11 Tests (T21-T23 + extras)
    test_ollama_provider.gd            # 14 Tests (Provider config, error guards, cancel)
    test_openai_provider.gd            # 19 Tests (Config, error guards, cancel, models, token extraction)
    test_anthropic_provider.gd         # 19 Tests (Config, error guards, cancel, models, token extraction)
    test_orchestrator.gd               # 12 Tests (Pipeline, cancel, two-stage, correlation)
    test_dock.gd                       # 14 Tests (Request shape, flags, tags, states)
  docs/
    README.md                          # Plugin-Quickstart + CI Badge

.gutconfig.json                        # GUT Test-Framework Konfiguration
.github/workflows/test.yml            # GitHub Actions CI (Godot 4.6.1 headless + GUT)
```

### class_name Mapping


| class_name                 | File                                    | extends      |
| -------------------------- | --------------------------------------- | ------------ |
| AiSceneGenPlugin           | plugin.gd                               | EditorPlugin |
| AiSceneGenDock             | ui/ai_scene_gen_dock.gd                 | Control      |
| AiSceneGenOrchestrator     | core/orchestrator.gd                    | RefCounted   |
| AiSceneGenLogger           | util/logger.gd                          | RefCounted   |
| AiSceneGenPersistence      | util/persistence.gd                     | RefCounted   |
| PromptCompiler             | core/prompt_compiler.gd                 | RefCounted   |
| SceneSpecValidator         | core/scene_spec_validator.gd            | RefCounted   |
| SceneBuilder               | core/scene_builder.gd                   | RefCounted   |
| PostProcessor              | core/post_processor.gd                  | RefCounted   |
| PreviewLayer               | core/preview_layer.gd                   | RefCounted   |
| LLMProvider                | llm/llm_provider.gd                     | RefCounted   |
| MockProvider               | llm/mock_provider.gd                    | LLMProvider  |
| OllamaProvider             | llm/ollama_provider.gd                  | LLMProvider  |
| OpenAIProvider             | llm/openai_provider.gd                  | LLMProvider  |
| AnthropicProvider          | llm/anthropic_provider.gd               | LLMProvider  |
| AssetTagRegistry           | assets/asset_tag_registry.gd            | Resource     |
| AssetResolver              | assets/asset_resolver.gd                | RefCounted   |
| ProceduralPrimitiveFactory | factory/procedural_primitive_factory.gd | RefCounted   |
| LLMResponse                | types/llm_response.gd                   | RefCounted   |
| ValidationResult           | types/validation_result.gd              | RefCounted   |
| BuildResult                | types/build_result.gd                   | RefCounted   |
| ResolvedSpec               | types/resolved_spec.gd                  | RefCounted   |


### Signal-Verdrahtung (plugin.gd)

```
AiSceneGenDock.generate_requested  -> plugin._on_generate_requested  -> await orchestrator.start_generation()
AiSceneGenDock.apply_requested     -> plugin._on_apply_requested     -> orchestrator.apply_preview(get_undo_redo(), root)
AiSceneGenDock.discard_requested   -> plugin._on_discard_requested   -> orchestrator.discard_preview()
AiSceneGenDock.provider_changed    -> plugin._on_provider_changed    -> orchestrator.set_llm_provider() + await fetch_models
AiSceneGenDock.import_requested    -> plugin._on_import_requested    -> EditorFileDialog -> persistence.import_spec -> orchestrator.rebuild_from_spec
AiSceneGenDock.export_requested    -> plugin._on_export_requested    -> EditorFileDialog -> persistence.export_spec
orchestrator.pipeline_state_changed -> plugin._on_pipeline_state_changed -> dock.set_state()
orchestrator.pipeline_progress      -> plugin._on_pipeline_progress      -> dock.show_progress()
orchestrator.pipeline_completed     -> plugin._on_pipeline_completed     -> dock.show_progress(1.0)
orchestrator.pipeline_failed        -> plugin._on_pipeline_failed        -> dock.show_errors()
```

### Pipeline-Flow (orchestrator.start_generation — async)

```
Single-Stage (default):
  1. PromptCompiler.compile_single_stage(request) -> compiled_prompt
  2. await LLMProvider.send_request(prompt, model, 0.0, seed) -> LLMResponse
     (bis zu 2 Retries bei Fehler, Cancellation-Guard via correlation_id)

Two-Stage (>30 Woerter oder CheckBox):
  1a. PromptCompiler.compile_plan_stage(request) -> plan_prompt
  1b. await LLMProvider.send_request(plan_prompt, ...) -> plan_text
  1c. PromptCompiler.compile_spec_stage(request, plan_text) -> spec_prompt
  1d. await LLMProvider.send_request(spec_prompt, ...) -> LLMResponse (mit Retries)

Shared (ab Validation):
  3. SceneSpecValidator.validate_json_string(raw_json) -> ValidationResult
  4. AssetResolver.resolve_nodes(spec, registry) -> ResolvedSpec
  5. SceneBuilder.build(resolved_spec, preview_root) -> BuildResult
  6. PostProcessor.execute_all(root, spec) -> warnings
  7. PreviewLayer.show_preview(root, scene_root)
```

## Bekannte Limitierungen (keine Bugs, Design-Grenzen)

1. **Post-Processor nutzt lokale Transforms** — Korrekt fuer flache
   Hierarchien (1 Ebene Kinder von preview_root). Bei tief verschachtelten
   Nodes waere `global_transform` genauer, geht aber erst nach Tree-Insert.
2. **Undo revertiert nur Tree-Operationen** — Orchestrator/Dock State
   (IDLE/PREVIEW_READY) wird beim Undo nicht automatisch zurueckgesetzt.
   Nodes werden korrekt revertiert, aber UI zeigt weiter IDLE.
3. **Shared HTTPRequest** — Ein HTTPRequest-Node fuer alle Provider.
   Bei Cancel bleibt der alte Coroutine suspended (Correlation-ID Guard
   verhindert Seiteneffekte). Akzeptabler Tradeoff fuer MVP.
4. ~~**Nur Single-Stage Mode**~~ ✅ GEFIXT — Two-Stage Mode implementiert
   im Orchestrator mit Heuristik (>30 Woerter oder CheckBox).
5. **Schema-Retry nicht implementiert** — `MAX_SCHEMA_RETRIES = 1` ist definiert
   aber nicht verwendet. Nur JSON-Parse-Retries (max 2) sind aktiv. Die Architektur
   beschreibt einen Schema-Retry-Pfad (Error-Details an Prompt anhaengen), der
   noch implementiert werden muss.
6. ~~**Error-Code Prefixes inkonsistent**~~ ✅ GEFIXT — Dock nutzt jetzt
   `UI_ERR_EMPTY_PROMPT`, `UI_ERR_INVALID_BOUNDS`, `UI_ERR_INVALID_SEED`.
7. ~~**`get_editor_interface()` deprecated**~~ ✅ GEFIXT — plugin.gd nutzt
   jetzt `EditorInterface` Singleton (4 Stellen ersetzt).
8. ~~**Nur MockProvider + OllamaProvider**~~ ✅ GEFIXT — OpenAIProvider und
   AnthropicProvider sind implementiert und in die Provider-Registry integriert.

## Fehlende Features (nach Architektur-Doc, priorisiert)

### ~~Prio 1: Async Pipeline + LLM Provider~~ ✅ ERLEDIGT

### ~~Prio 2: EditorUndoRedoManager~~ ✅ ERLEDIGT

### ~~Prio 3: Import/Export UI~~ ✅ ERLEDIGT

### ~~Prio 4: Two-Stage Mode~~ ✅ ERLEDIGT

### Prio 5: Variation Mode + Asset Tag Browser (✅ ERLEDIGT)

- FR-14: Variation CheckBox im Dock, Random Suffix an Prompt via PromptCompiler
  `[variation_seed={randi()}]` wird an user_prompt angehängt bevor kompiliert wird
- FR-13: Aufklappbarer "Available Asset Tags" Browser im Dock
  - Liest Tags aus AssetTagRegistry (via Orchestrator -> plugin.gd -> dock)
  - Selektierte Tags werden in `get_generation_request()["available_asset_tags"]` aufgenommen
  - Zeigt "No asset tags registered" wenn Registry leer
- plugin.gd: `_sync_asset_tags_to_dock()` leitet Registry-Tags an Dock weiter

### Prio 6: CI/CD mit GUT + GitHub Actions (✅ ERLEDIGT)

- GUT 9.6.0 als Test-Framework (addons/gut/ via git clone, in .gitignore)
- `.gutconfig.json` im Projekt-Root: Test-Dirs, Prefix, Suffix, should_exit
- 3 neue Test-Files:
  - `test_ollama_provider.gd` (14 Tests): Provider-Config, Error Guards, Cancel, Default Models
  - `test_orchestrator.gd` (12 Tests): State Management, Pipeline mit MockProvider, Cancel, Two-Stage, Correlation ID
  - `test_dock.gd` (14 Tests): Request Shape, Variation/Two-Stage Flags, Asset Tags, State Transitions
- 3 Variation-Tests zu `test_prompt_compiler.gd` hinzugefuegt
- 5 bestehende Tests gefixt (GUT Error-Tracking: `assert_push_error`, `assert_engine_error_count`)
- `.github/workflows/test.yml`: push + PR auf main, Godot 4.6.1 headless, GUT runner
- CI Badge in README.md
- **109 Tests, 322 Asserts, 0.6s Runtime, alle PASS**

### Prio 7: Weitere LLM Provider (✅ ERLEDIGT)

- OpenAIProvider: GPT-4o/GPT-4o-mini, Chat Completions API, JSON mode,
  Bearer Auth, Token Usage Extraction, Model-Fetch via /v1/models
- AnthropicProvider: Claude (claude-sonnet-4-20250514), Messages API,
  x-api-key + anthropic-version Header, Content Block Extraction
- Plugin-Integration: Provider-Registry (4 Provider: Mock, Ollama, OpenAI, Anthropic),
  API-Key Persistence via EditorSettings, Host-URL nur fuer Ollama
- 19 Tests pro Provider (Config, Error Guards, Cancel, Models, Token Extraction)
- **147 Tests, 373 Asserts, 0.62s Runtime, alle PASS**

## GDScript Konventionen (STRIKT EINHALTEN)

- @tool auf allen Scripts die im Editor laufen
- Explizite Typen auf JEDER Variable, Parameter, Return. Keine Inferenz.
- Typed collections: Array[String], Array[Dictionary], etc.
- **WICHTIG:** Beim Uebergeben von Arrays an typed Parameter IMMER erst
als typed Variable deklarieren (z.B. `var x: Array[String] = ["a"]`),
dann uebergeben. Untyped Literale `["a"]` crashen bei Dynamic Dispatch.
- snake_case fuer Funktionen/Variablen, PascalCase fuer Klassen, UPPER_SNAKE_CASE fuer Konstanten
- _ Prefix fuer private Member
- Signals mit typed Signature, connect via .connect()
- await statt yield
- ## Doxygen-Style Docs auf public Funktionen
- Keine Kommentare die nur Code nacherzaehlen
- Datei-Reihenfolge: class_name/extends -> signals -> enums/constants -> @export -> @onready -> private vars -> _ready -> public methods -> private methods
- Composition over Inheritance, Signals statt direkte Referenzen
- RefCounted fuer alle nicht-UI Module

## Sicherheits-Invarianten (NIEMALS BRECHEN)

1. Kein eval(), Expression, load(), preload() auf LLM-Output
2. Allowlists sind const — NICHT aus Dateien laden
3. Alle File-Paths muessen mit res:// beginnen
4. API Keys in EditorSettings, NICHT in Projekt-Dateien
5. additionalProperties: false im Schema — keine unbekannten Felder
6. LLM-Output wird NUR als JSON geparst (JSON.parse_string())

## Architektur-Referenz

Vollstaendiges Designdokument: `ARCHITECTURE_INTEGRATED.md` (2117 Zeilen)

- Abschnitt 4: Alle 12 Module mit Interfaces, Error Codes, Test Plans
- Abschnitt 5: SceneSpec JSON Schema v1.0.0 + Beispiele
- Abschnitt 6: LLM System Instruction Template + Two-Stage Design
- Abschnitt 7: 40 Test Cases (T01-T40) + CI Plan
- Abschnitt 9: Mermaid-Diagramme (Component, Sequence, State, Data Flow)
- Abschnitt 10: Security & Safety Model
- Abschnitt 11: Acceptance Checklist

## Empfohlene naechste Schritte

1. ~~Godot oeffnen, Plugin testen, Bugs fixen~~ ✅ ERLEDIGT
2. ~~Async Pipeline + Ollama Provider~~ ✅ ERLEDIGT
3. ~~EditorUndoRedoManager in Preview Layer~~ ✅ ERLEDIGT
4. ~~Import/Export Buttons im Dock~~ ✅ ERLEDIGT
5. ~~Two-Stage Mode im Orchestrator~~ ✅ ERLEDIGT
6. ~~Variation Mode + Asset Tag Browser~~ ✅ ERLEDIGT
7. ~~CI/CD (GUT + GitHub Actions)~~ ✅ ERLEDIGT
8. ~~Weitere LLM Provider (OpenAI, Anthropic)~~ ✅ ERLEDIGT
9. **Schema-Retry** (MAX_SCHEMA_RETRIES nutzen, Error-Details an Prompt anhaengen)

---

## Agenten-Prompt: Prio 8 — Schema-Retry

> Copy-paste diesen Block als Prompt fuer den naechsten AI-Agenten.

```
Benutze Agenten. Lies HANDOFF.md im Projekt-Root fuer den vollstaendigen Kontext.
Danach ARCHITECTURE_INTEGRATED.md Abschnitt 4 (Module B + E) fuer Orchestrator + Validator Specs.

Prio 1-7 sind erledigt (Async, Undo, Import/Export, Two-Stage, Variation/Tags, CI/CD, Provider).
147 GUT Tests laufen alle PASS. GitHub Actions CI ist aktiv.
Naechster Schritt: Prio 8 — Schema-Retry implementieren.

SCHRITT 1: Schema-Retry im Orchestrator

- `MAX_SCHEMA_RETRIES = 2` (bereits als Konstante definiert aber nicht genutzt)
- Nach fehlgeschlagener Validation: Error-Details an Prompt anhaengen
- PromptCompiler: neue Methode `compile_retry_stage(request, raw_json, errors)`
- Retry-Prompt: "The previous JSON was invalid: {errors}. Fix these issues."
- Pipeline-Progress Steps fuer Retry anpassen
- Cancellation-Guard nach jedem Retry-Await

SCHRITT 2: Tests

- Orchestrator: Schema-Retry Test (MockProvider mit absichtlich invalidem JSON beim 1. Call)
- Lokal testen: Alle 147+ Tests muessen PASS sein
- HANDOFF.md updaten, committen und pushen
```

