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

## Aktueller Stand: MVP + ASYNC + UNDO + IMPORT/EXPORT + TWO-STAGE + VARIATION/TAGS + CI/CD + PROVIDERS + SCHEMA-RETRY + HEALTH-CHECK + MODEL-CACHE + DOCUMENTATION + GOLDEN-TESTS + BENCHMARKS + INTEGRATION-TESTS (Phase 1-6 + Prio 1-13)

Alle 12 Module (A-L) sind implementiert, verdrahtet, und **fehlerfrei getestet**.
Plugin laedt und entlaedt in Godot 4.6.1 headless ohne Fehler/Warnings.
Generate-Pipeline laeuft komplett durch (mit MockProvider).
Two-Stage Generation Mode ist implementiert und getestet.
Variation Mode und Asset Tag Browser sind implementiert und getestet.
OpenAI + Anthropic Provider sind implementiert, integriert, und getestet.
Schema-Retry mit Error-Feedback an LLM ist implementiert und getestet.
Health-Check UI + Model Cache Persistence sind implementiert und getestet.
Documentation (USER_GUIDE, OPERATOR_GUIDE, DEVELOPER_GUIDE, TROUBLESHOOTING, FAQ) ist komplett.
Golden/Snapshot Tests verifizieren Determinismus via frozen SceneSpec JSON.
Performance Benchmarks verifizieren lineare Build-Time-Skalierung und Cleanup.
Real LLM Integration Tests mit Skip-Guard fuer optionale Ollama/OpenAI E2E.
194 GUT Tests (13 Test-Files) laufen headless, GitHub Actions CI aktiv.

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

**Prio 9: Health-Check UI + Model Cache Persistence (✅ ERLEDIGT)**

- Dock: "Test Connection" Button rechts neben Provider-Dropdown
- Dock: Ergebnis-Label darunter ("Connected — X models" / "Failed: ...")
- Button + Label nur sichtbar wenn Provider != MockProvider
- Neues Signal: `connection_test_requested(provider_name: String)`
- Button disabled waehrend Test laeuft, re-enabled nach Callback
- `show_connection_result(success: bool, model_count: int)` public Method
- plugin.gd: Handler nutzt `_provider_switch_id` Pattern gegen Race Conditions
- plugin.gd: `_on_provider_changed()` laedt Model-Cache VOR async fetch (TTL 1h)
- plugin.gd: speichert Model-Cache NACH erfolgreichem fetch
- plugin.gd: Connection-Test aktualisiert Cache bei Erfolg
- 7 neue Tests in test_dock.gd (Signal, Label, Visibility, Disabled-State)

**Prio 11: Golden/Snapshot Tests (✅ ERLEDIGT)**

- Golden Test Infrastructure (`test_golden.gd`):
  - Laedt frozen `.scenespec.json` Dateien, baut Szene via AssetResolver + SceneBuilder
  - Vergleicht Node-Count, Node-Namen, Positionen (approx), Typen, Materialien
  - 2 Golden Specs: `outdoor_clearing` (9 Nodes, 1176 Tris) + `interior_room` (8 Nodes, 48 Tris)
- Snapshot-Vergleich:
  - `build(spec, root)` zweimal mit gleichem Seed → identischer Hash
  - Node-Count, Triangle-Count, Build-Hash alle identisch
  - Verschiedene Specs erzeugen verschiedene Hashes
  - Voller Tree-Structure-Vergleich (normalisierte Auto-Namen)
- 10 neue Tests (6 Golden + 4 Snapshot)

**Prio 12: Performance Profiling (✅ ERLEDIGT)**

- Benchmark Infrastructure (`test_benchmark.gd`):
  - Programmatischer SceneSpec-Generator fuer beliebige Node-Counts (flat + nested)
  - Microsecond-genaue Zeitmessung mit Median ueber 3 Iterationen
  - 3 Tier-Thresholds: Small (10 nodes < 50ms), Medium (100 nodes < 500ms), Large (500 nodes < 2500ms)
  - Linearity-Verifikation: 200/10 Ratio muss unter 3x linearer Erwartung bleiben
  - Nested-Spec Performance (10 branches x depth 4)
  - BuildResult.duration_ms Konsistenz-Check
- Memory Profiling:
  - Node-Count Verifikation: BuildResult.get_node_count() == Spec-Node-Count
  - Large Spec (500 nodes) Node-Count Verifikation
  - Cleanup nach PreviewLayer.discard() (preview inactive, count = 0)
  - Cleanup nach PreviewLayer.apply_to_scene() (nodes reparented, preview inactive)
  - Repeated Build/Discard Leak-Check (5 Iterationen, State bleibt clean)
  - Triangle-Count positiv fuer Primitive-Nodes
  - Hash-Determinismus ueber identische Specs
- Gemessene Performance (Godot 4.6.1, Windows):
  - 10 nodes: ~0.8ms, 100 nodes: ~8.2ms, 500 nodes: ~40.6ms
  - Build-Time skaliert linear mit Node-Count
- 13 neue Tests (6 Benchmark + 7 Memory)

**Prio 13: Real LLM Integration Tests (✅ ERLEDIGT)**

- Integration Test Infrastructure (`test_integration.gd`):
  - Optionale Tests mit async Skip-Guard: ueberspringen wenn kein Endpunkt erreichbar
  - Ollama-Guard: HTTP GET auf localhost:11434/api/tags, cached nach erstem Check
  - OpenAI-Guard: OPENAI_API_KEY env var + /v1/models Endpoint-Pruefung, cached
  - Erster verfuegbarer Ollama-Model wird automatisch erkannt und verwendet
- Ollama Connectivity Tests (3):
  - Reachability + Model-Erkennung
  - fetch_available_models() gegen echte Ollama-Instanz
  - send_request() Roundtrip mit einfachem JSON-Prompt
- OpenAI Connectivity Tests (3):
  - Reachability via API Key + Endpoint
  - fetch_available_models() gegen echte OpenAI API (GPT-Modelle)
  - send_request() Roundtrip mit gpt-4o-mini
- E2E Pipeline Tests (4):
  - Voller Pipeline-Durchlauf mit echtem Ollama (Orchestrator → Validator → Builder)
  - Voller Pipeline-Durchlauf mit echtem OpenAI (Orchestrator → Validator → Builder)
  - Separate Validation Chain: LLM-Output → SceneSpecValidator → AssetResolver → SceneBuilder
  - Two-Stage Pipeline mit echtem LLM (Plan → Spec → Validate → Build)
- Alle Tests skippen sauber in CI (kein Ollama, kein API Key) als Pending
- 10 neue Tests (3 Ollama + 3 OpenAI + 4 E2E)

### File-Inventar (33 .gd + 3 .json + 2 .md + 1 .yml + plugin.cfg + project.godot)

```
addons/ai_scene_gen/
  plugin.cfg                           # Plugin-Metadaten
  plugin.gd                            # EditorPlugin Entry — verdrahtet alle Module
  core/
    orchestrator.gd                    # B: Async Pipeline State Machine
    prompt_compiler.gd                 # D: Prompt-Zusammenbau (single + two-stage + retry-stage)
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
    test_prompt_compiler.gd            # 20 Tests (T14-T16 + variation + retry-stage + extras)
    test_scene_builder.gd              # 7 Tests (T26, T27 + extras)
    test_asset_resolver.gd             # 11 Tests (T21-T23 + extras)
    test_ollama_provider.gd            # 14 Tests (Provider config, error guards, cancel)
    test_openai_provider.gd            # 19 Tests (Config, error guards, cancel, models, token extraction)
    test_anthropic_provider.gd         # 19 Tests (Config, error guards, cancel, models, token extraction)
    test_orchestrator.gd               # 15 Tests (Pipeline, cancel, two-stage, correlation, schema-retry)
    test_golden.gd                     # 10 Tests (Golden structure/position/material + Snapshot determinism)
    test_benchmark.gd                  # 13 Tests (Build-time benchmarks, linearity, memory profiling, cleanup)
    test_dock.gd                       # 21 Tests (Request shape, flags, tags, states)
    test_integration.gd                # 10 Tests (Real LLM connectivity, E2E pipeline, validation chain)
  docs/
    README.md                          # Plugin-Quickstart + CI Badge
    USER_GUIDE.md                      # Full UI walkthrough, prompt tips, features
    OPERATOR_GUIDE.md                  # Provider setup, API keys, security, tuning
    DEVELOPER_GUIDE.md                 # Architecture, adding providers/passes, testing
    TROUBLESHOOTING.md                 # Error code table, common problems, debug logging
    FAQ.md                             # Frequently asked questions

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
AiSceneGenDock.connection_test_requested -> plugin._on_connection_test_requested -> await fetch_available_models -> dock.show_connection_result
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
     Schema-Retry (bis zu MAX_SCHEMA_RETRIES=2 bei Validation-Fehler):
       3a. PromptCompiler.compile_retry_stage(request, raw_json, errors) -> retry_prompt
       3b. await LLMProvider.send_request(retry_prompt, ...) -> LLMResponse
       3c. SceneSpecValidator.validate_json_string(new_raw_json) -> ValidationResult
       (Cancellation-Guard nach jedem await)
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
4. ~~**Model-Cache nicht genutzt**~~ ✅ BEHOBEN (Prio 9) — Cache wird bei
   Provider-Switch geladen (TTL 1h) und nach fetch gespeichert.
5. ~~**Kein Health-Check im UI**~~ ✅ BEHOBEN (Prio 9) — "Test Connection"
   Button im Dock, zeigt Ergebnis ("Connected — X models" / "Failed").

Bereits gefixt: Two-Stage Mode (Prio 4), Schema-Retry (Prio 8),
Error-Code Prefixes (Prio 4), `get_editor_interface()` deprecated (Prio 4),
4 Provider statt 2 (Prio 7).

## Erledigte Features (Prio 1-9, alle ✅)

| Prio | Feature | Tests hinzugefuegt |
|------|---------|-------------------|
| 1 | Async Pipeline + LLM Provider (Ollama, MockProvider) | 14 (Ollama) |
| 2 | EditorUndoRedoManager | — (in Orchestrator-Tests) |
| 3 | Import/Export UI (EditorFileDialog, SceneSpec I/O) | — (in Dock-Tests) |
| 4 | Two-Stage Mode + Code-Fixes | 12 (Orchestrator) |
| 5 | Variation Mode + Asset Tag Browser | 14 (Dock) + 3 (Compiler) |
| 6 | CI/CD (GUT 9.6.0 + GitHub Actions) | 5 Fixes |
| 7 | OpenAI + Anthropic Provider | 19+19 (Provider) |
| 8 | Schema-Retry mit Error-Feedback | 3 (Orchestrator) + 4 (Compiler) |
| 9 | Health-Check UI + Model Cache Persistence | 7 (Dock) |
| 10 | Documentation (USER_GUIDE, OPERATOR_GUIDE, DEVELOPER_GUIDE, TROUBLESHOOTING, FAQ) | — (no code changes) |
| 11 | Golden/Snapshot Tests (determinism verification via frozen SceneSpec) | 10 (Golden + Snapshot) |
| 12 | Performance Profiling (build-time benchmarks, memory tracking, cleanup) | 13 (Benchmark + Memory) |
| 13 | Real LLM Integration Tests (Ollama + OpenAI E2E, skip-guard) | 10 (Integration, pending in CI) |

**Aktuell: 194 Tests, 553 Asserts, 13 Test-Files, 6.1s, 184 PASS + 10 Pending (Integration skip).**

Details zu jedem Prio-Schritt: siehe git log (`feat:` Commits).

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
9. ~~Schema-Retry~~ ✅ ERLEDIGT
10. ~~Health-Check UI~~ ✅ ERLEDIGT
11. ~~Model-Cache Persistence~~ ✅ ERLEDIGT
12. ~~Documentation~~ ✅ ERLEDIGT (USER_GUIDE, OPERATOR_GUIDE, DEVELOPER_GUIDE, TROUBLESHOOTING, FAQ)
13. ~~Golden/Snapshot Tests~~ ✅ ERLEDIGT (determinism verification via frozen SceneSpec JSON)
14. ~~Performance Profiling~~ ✅ ERLEDIGT (build-time benchmarks, memory tracking, cleanup verification)
15. ~~Real LLM Integration Tests~~ ✅ ERLEDIGT (E2E mit echtem Ollama/OpenAI, skip-guard fuer CI)
16. **UI Polish + UX Improvements** (Progress animations, better error display, keyboard shortcuts)

---

## Agenten-Prompt: Prio 14 — UI Polish + UX Improvements

> Copy-paste diesen Block als Prompt fuer den naechsten AI-Agenten.

```
Benutze Agenten. Lies HANDOFF.md im Projekt-Root fuer den vollstaendigen Kontext.

Prio 1-13 sind erledigt (Async, Undo, Import/Export, Two-Stage, Variation/Tags,
CI/CD, OpenAI+Anthropic Provider, Schema-Retry, Health-Check + Model-Cache,
Documentation, Golden/Snapshot Tests, Performance Profiling, Integration Tests).
194 GUT Tests (13 Test-Files) laufen headless, GitHub Actions CI aktiv.
Naechster Schritt: Prio 14 — UI Polish + UX Improvements.

ZIEL: Dock UI aufpolieren und UX verbessern.

SCHRITT 1: Progress Animation
    - Animierte Fortschrittsanzeige waehrend Pipeline laeuft
    - Stage-Labels (Generating... Validating... Building...)
    - Elapsed-Time Anzeige

SCHRITT 2: Error Display
    - Bessere Fehleranzeige mit Error-Code und Fix-Hints
    - Collapsible Error-Details
    - Copy-to-Clipboard fuer Fehlermeldungen

SCHRITT 3: Keyboard Shortcuts
    - Ctrl+G: Generate
    - Ctrl+Shift+A: Apply Preview
    - Escape: Cancel/Discard

3b. Lokal testen: Alle 194+ Tests muessen PASS sein (plus neue)
3c. HANDOFF.md updaten, committen und pushen

Wichtig: Alle GDScript-Konventionen aus HANDOFF.md einhalten.
```

