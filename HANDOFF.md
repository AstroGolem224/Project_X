# Agent Handoff: AI Scene Generator Plugin

> Dieses Dokument ist der vollstaendige Kontext fuer den naechsten Agenten.
> Lies zuerst dieses File, dann ARCHITECTURE_INTEGRATED.md fuer Details.

## Projekt-Ueberblick

**Repo:** https://github.com/AstroGolem224/Project_X.git
**Branch:** main
**Workspace:** `c:\Users\matth\OneDrive\Dokumente\GitHub\Project_X`
**Engine:** Godot 4.6.1 stable, pure GDScript, kein GDExtension
**Godot Pfad:** `J:\Godot\Godot_v4.6.1-stable_win64.exe`
**Typ:** `@tool` EditorPlugin unter `addons/ai_scene_gen/`

Ein Godot-Plugin das aus natuerlichsprachigen Prompts 3D-Szenen generiert.
Der LLM gibt JSON (SceneSpec) zurueck, das validiert und deterministisch
in einen Godot Node-Tree gebaut wird. Kein eval(), kein Code-Execution.

## Aktueller Stand: MVP + ASYNC + UNDO + IMPORT/EXPORT (Phase 1-6 + Prio 1-3)

Alle 12 Module (A-L) sind implementiert, verdrahtet, und **fehlerfrei getestet**.
Plugin laedt und entlaedt in Godot 4.6.1 headless ohne Fehler/Warnings.
Generate-Pipeline laeuft komplett durch (mit MockProvider).

### Was in der letzten Session gefixt wurde (7 Bugs)

1. **`@tool` fehlte auf 5 Type-Scripten** — `llm_response.gd`, `validation_result.gd`,
   `build_result.gd`, `resolved_spec.gd`, `logger.gd` hatten kein `@tool`.
   Konnten bei Editor-Nutzung subtile Fehler verursachen.

2. **`_LLMResponseScript` preload Duplikat** — `llm_provider.gd` hatte
   `const _LLMResponseScript: GDScript = preload(...)` obwohl `LLMResponse`
   bereits per `class_name` global registriert ist. Entfernt; alle Stellen
   nutzen jetzt `LLMResponse.create_success()`/`create_failure()` direkt.
   Betraf auch `mock_provider.gd`.

3. **Node vs Node3D Typ-Mismatch** — `plugin.gd` holte `get_edited_scene_root()`
   als `Node`, aber `orchestrator.start_generation()` erwartet `Node3D`.
   Jetzt mit `is Node3D`-Check und Fehlermeldung bei 2D-Szenen.

4. **Typed Array Mismatch (3 Stellen)** — Untyped `["MockProvider"]` und
   `[{error_dict}]` an `Array[String]`/`Array[Dictionary]` Parameter uebergeben.
   Crashte bei Dynamic Dispatch (duck-typed `_dock: Control`).
   Fix: Alle Arrays als typed Variable deklariert vor Uebergabe.
   Betraf `plugin.gd` (2x) und `ai_scene_gen_dock.gd` (1x).

5. **`null as String` crash** — `scene_builder.gd` castete
   `node["primitive_shape"] as String` ohne Null-Check. Mock-Daten
   haben `"primitive_shape": null`. Fix: Null-Guard + `str()`.

6. **`camera.look_at()` ohne Scene Tree** — `post_processor.gd`
   `CameraFramingPass` rief `look_at()` auf Nodes die noch nicht im
   Tree waren. Fix: `Basis.looking_at()` statt `look_at()`.

7. **`global_transform` ohne Scene Tree** — `CollisionCheckPass._approx_aabb()`
   und `CameraFramingPass._get_node_aabb()` nutzten `global_transform`
   auf Nodes ausserhalb des Trees. Fix: Lokales `transform` statt `global_transform`.

### File-Inventar (28 .gd + 2 .json + 2 .md + plugin.cfg + project.godot)

```
addons/ai_scene_gen/
  plugin.cfg                           # Plugin-Metadaten
  plugin.gd                            # EditorPlugin Entry — verdrahtet alle Module
  core/
    orchestrator.gd                    # B: Pipeline State Machine (synchron!)
    prompt_compiler.gd                 # D: Prompt-Zusammenbau
    scene_spec_validator.gd            # E: Schema-Validierung (1269 Zeilen) - groesstes Modul
    scene_builder.gd                   # H: Deterministischer Builder
    post_processor.gd                  # I: 5 Post-Processing Passes
    preview_layer.gd                   # J: Preview-Management
  types/
    llm_response.gd                    # @tool, LLMResponse mit static factory methods
    validation_result.gd               # @tool, ValidationResult
    build_result.gd                    # @tool, BuildResult
    resolved_spec.gd                   # @tool, ResolvedSpec
  llm/
    llm_provider.gd                    # C: Abstrakte Basisklasse + HTTP/API-Key Infrastruktur
    mock_provider.gd                   # C: Canned-Response Provider (synchron)
    ollama_provider.gd                 # C: Async Ollama Provider (localhost:11434)
  assets/
    asset_tag_registry.gd              # F: Tag-Registry (extends Resource, @export)
    asset_resolver.gd                  # F: Tag-Aufloesung mit Fallback
  factory/
    procedural_primitive_factory.gd    # G: 5 Primitives (box/sphere/cylinder/capsule/plane)
  ui/
    ai_scene_gen_dock.gd               # A: Komplettes Dock UI (rein programmatisch)
  util/
    logger.gd                          # @tool, AiSceneGenLogger mit 4 Log-Levels + Metrics
    persistence.gd                     # L: Settings/SceneSpec I/O
  mocks/
    outdoor_clearing.scenespec.json    # Example 1 (Outdoor Clearing mit Baum, Fels, Pfad)
    interior_room.scenespec.json       # Example 2 (Raum mit Waenden und Tisch)
  tests/                               # .gdignore vorhanden (Godot scannt nicht)
    test_validator.gd                  # 19 Tests (T01-T13, T38, T39)
    test_primitive_factory.gd          # 14 Tests (T24, T25 + extras)
    test_prompt_compiler.gd            # 13 Tests (T14-T16 + extras)
    test_scene_builder.gd             # 9 Tests (T26, T27 + extras)
    test_asset_resolver.gd             # 11 Tests (T21-T23 + extras)
  docs/
    README.md                          # Plugin-Quickstart
```

### class_name Mapping

| class_name | File | extends |
|---|---|---|
| AiSceneGenPlugin | plugin.gd | EditorPlugin |
| AiSceneGenDock | ui/ai_scene_gen_dock.gd | Control |
| AiSceneGenOrchestrator | core/orchestrator.gd | RefCounted |
| AiSceneGenLogger | util/logger.gd | RefCounted |
| AiSceneGenPersistence | util/persistence.gd | RefCounted |
| PromptCompiler | core/prompt_compiler.gd | RefCounted |
| SceneSpecValidator | core/scene_spec_validator.gd | RefCounted |
| SceneBuilder | core/scene_builder.gd | RefCounted |
| PostProcessor | core/post_processor.gd | RefCounted |
| PreviewLayer | core/preview_layer.gd | RefCounted |
| LLMProvider | llm/llm_provider.gd | RefCounted |
| MockProvider | llm/mock_provider.gd | LLMProvider |
| OllamaProvider | llm/ollama_provider.gd | LLMProvider |
| AssetTagRegistry | assets/asset_tag_registry.gd | Resource |
| AssetResolver | assets/asset_resolver.gd | RefCounted |
| ProceduralPrimitiveFactory | factory/procedural_primitive_factory.gd | RefCounted |
| LLMResponse | types/llm_response.gd | RefCounted |
| ValidationResult | types/validation_result.gd | RefCounted |
| BuildResult | types/build_result.gd | RefCounted |
| ResolvedSpec | types/resolved_spec.gd | RefCounted |

### Signal-Verdrahtung (plugin.gd)

```
AiSceneGenDock.generate_requested -> plugin._on_generate_requested -> orchestrator.start_generation()
AiSceneGenDock.apply_requested    -> plugin._on_apply_requested    -> orchestrator.apply_preview()
AiSceneGenDock.discard_requested  -> plugin._on_discard_requested  -> orchestrator.discard_preview()
orchestrator.pipeline_state_changed -> plugin._on_pipeline_state_changed -> dock.set_state()
orchestrator.pipeline_progress      -> plugin._on_pipeline_progress      -> dock.show_progress()
orchestrator.pipeline_completed     -> plugin._on_pipeline_completed     -> dock.show_progress(1.0)
orchestrator.pipeline_failed        -> plugin._on_pipeline_failed        -> dock.show_errors()
```

### Pipeline-Flow (orchestrator.start_generation)

```
1. PromptCompiler.compile_single_stage(request) -> compiled_prompt
2. LLMProvider.send_request(prompt, model, 0.0, seed) -> LLMResponse (raw JSON)
   (bis zu 2 Retries bei Fehler)
3. SceneSpecValidator.validate_json_string(raw_json) -> ValidationResult
4. AssetResolver.resolve_nodes(spec, registry) -> ResolvedSpec
5. SceneBuilder.build(resolved_spec, preview_root) -> BuildResult
6. PostProcessor.execute_all(root, spec) -> warnings
7. PreviewLayer.show_preview(root, scene_root)
```

## Bekannte Limitierungen (keine Bugs, aber Design-Grenzen)

1. ~~**Pipeline ist synchron**~~ ✅ GELOEST — `start_generation()` ist jetzt async
   mit `await` auf LLM-Calls. Cancellation-Guard via Correlation-ID.

2. ~~**Kein Undo/Redo**~~ ✅ GELOEST — `apply_to_scene()` nutzt
   `EditorUndoRedoManager` mit `_do_apply`/`_undo_apply`. Ctrl+Z revertiert Apply.

3. ~~**Keine Import/Export UI**~~ ✅ GELOEST — Import/Export Buttons im Dock,
   `EditorFileDialog` mit `.scenespec.json` Filter, voll verdrahtet mit Persistence.

4. **Post-Processor nutzt lokale Transforms** — Korrekt fuer flache
   Hierarchien (1 Ebene Kinder von preview_root). Bei tief verschachtelten
   Nodes waere `global_transform` genauer, geht aber erst nach Tree-Insert.
   Fuer MVP ausreichend.

## Fehlende Features (nach Architektur-Doc, priorisiert)

### Prio 1: Echte LLM Provider + Async Pipeline

- **Dateien erstellen:**
  - `llm/openai_provider.gd` — HTTPRequest + Bearer Token Auth
  - `llm/ollama_provider.gd` — HTTPRequest gegen localhost:11434
  - (optional spaeter) `llm/anthropic_provider.gd` — x-api-key Header

- **Architektur-Aenderungen:**
  - `LLMProvider.send_request()` wird async: `func send_request(...) -> LLMResponse`
    muss ein `await` nutzen (HTTPRequest.request_completed Signal)
  - Problem: LLMProvider ist RefCounted, kein Node. Kann kein HTTPRequest
    als Child haben. Loesung: `plugin.gd` erstellt HTTPRequest-Node in
    `_enter_tree()`, gibt Referenz an Provider via Setter.
  - `AiSceneGenOrchestrator.start_generation()` wird async (`await`)
  - `plugin._on_generate_requested()` ruft `await _orchestrator.start_generation()`
  - MockProvider bleibt synchron (kein await noetig, return sofort)

- **UI-Aenderungen:**
  - Provider-Dropdown muss dynamisch befuellt werden
  - Model-Dropdown aktualisiert sich bei Provider-Wechsel
  - API-Key Eingabefeld im Dock (oder via EditorSettings)
  - `AiSceneGenPersistence` hat `get_api_key()`/`set_api_key()` schon,
    braucht `set_editor_interface()` Aufruf von plugin.gd

### ~~Prio 2: EditorUndoRedoManager~~ ✅ ERLEDIGT

- `PreviewLayer.apply_to_scene(undo_redo, scene_root)` mit vollstaendigem Undo/Redo
- `_do_apply()` / `_undo_apply()` private Methoden, `_applied_children` Tracking
- `plugin.gd` uebergibt `get_undo_redo()` bei apply
- Null-Guard: ohne UndoRedoManager = direktes Apply (Fallback)

### ~~Prio 3: Import/Export UI~~ ✅ ERLEDIGT

- Import/Export Buttons im Dock mit State-Management
- `EditorFileDialog` (ACCESS_RESOURCES, `.scenespec.json` Filter)
- Import: `persistence.import_spec(path)` -> `orchestrator.rebuild_from_spec(spec, root)`
- Export: `persistence.export_spec(last_spec, path)` mit Fehlerhandling
- Dock Signals: `import_requested` / `export_requested` -> Plugin handlers

### Prio 4: Two-Stage Mode

- `PromptCompiler` hat `compile_plan_stage()` + `compile_spec_stage()` schon
- Orchestrator braucht zweiten LLM-Call: Plan -> Spec
- Heuristik: >30 Woerter oder >15 Objekte -> auto two-stage
- UI: Checkbox "Two-Stage" im Dock

### Prio 5: Variation Mode + Asset Tag Browser

- FR-14: Random Suffix an Prompt wenn Variation aktiviert
- FR-13: Panel das registrierte Tags zeigt

### Prio 6: CI/CD

- GUT als Addon installieren
- Tests via `godot --headless --script addons/gut/gut_cmdln.gd`
- GitHub Actions Workflow

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
- Abschnitt 6: LLM System Instruction Template
- Abschnitt 7: 40 Test Cases (T01-T40) + CI Plan
- Abschnitt 9: Mermaid-Diagramme (Component, Sequence, State, Data Flow)
- Abschnitt 10: Security & Safety Model
- Abschnitt 11: Acceptance Checklist

## Empfohlene naechste Schritte

1. ~~Godot oeffnen, Plugin testen, Bugs fixen~~ ✅ ERLEDIGT
2. ~~Async Pipeline + Ollama Provider~~ ✅ ERLEDIGT
3. ~~EditorUndoRedoManager in Preview Layer~~ ✅ ERLEDIGT
4. ~~Import/Export Buttons im Dock~~ ✅ ERLEDIGT
5. **Two-Stage Mode im Orchestrator** (naechster logischer Schritt)
6. Variation Mode + Asset Tag Browser
7. CI/CD (GUT + GitHub Actions)
