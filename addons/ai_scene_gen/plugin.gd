@tool
class_name AiSceneGenPlugin
extends EditorPlugin

const PLUGIN_NAME: String = "AI Scene Generator"
const PLUGIN_VERSION: String = "1.0.0"
const LOG_CATEGORY: String = "ai_scene_gen.plugin"
const HTTP_TIMEOUT: float = 120.0

var _dock: Control = null
var _orchestrator: RefCounted = null
var _persistence: RefCounted = null
var _logger: RefCounted = null
var _http_request: HTTPRequest = null
var _providers: Dictionary = {}
var _provider_switch_id: int = 0
var _import_dialog: EditorFileDialog = null
var _export_dialog: EditorFileDialog = null


func _enter_tree() -> void:
	_logger = AiSceneGenLogger.new()
	_logger.set_log_level(AiSceneGenLogger.LogLevel.DEBUG)
	_logger.log_info(LOG_CATEGORY, "%s v%s loading..." % [PLUGIN_NAME, PLUGIN_VERSION])

	_persistence = AiSceneGenPersistence.new(_logger)
	_persistence.set_editor_interface(EditorInterface)

	_http_request = HTTPRequest.new()
	_http_request.timeout = HTTP_TIMEOUT
	add_child(_http_request)

	_orchestrator = AiSceneGenOrchestrator.new(_logger)
	_register_providers()

	_setup_file_dialogs()

	_dock = AiSceneGenDock.new()
	_dock.name = "AISceneGen"
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)

	_setup_provider_list()
	_connect_signals()
	_load_settings_to_ui()
	_sync_asset_tags_to_dock()

	_logger.log_info(LOG_CATEGORY, "%s v%s loaded." % [PLUGIN_NAME, PLUGIN_VERSION])


func _exit_tree() -> void:
	_disconnect_signals()
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _import_dialog != null:
		_import_dialog.queue_free()
		_import_dialog = null
	if _export_dialog != null:
		_export_dialog.queue_free()
		_export_dialog = null
	if _http_request != null:
		_http_request.cancel_request()
		_http_request.queue_free()
		_http_request = null
	_providers.clear()
	_orchestrator = null
	_persistence = null
	if _logger != null:
		_logger.log_info(LOG_CATEGORY, "%s unloaded." % PLUGIN_NAME)
	_logger = null


func _register_providers() -> void:
	var mock: MockProvider = MockProvider.new(_logger)
	_providers["MockProvider"] = mock

	var ollama: OllamaProvider = OllamaProvider.new(_logger)
	ollama.set_http_node(_http_request)
	_providers["Ollama"] = ollama

	var openai: OpenAIProvider = OpenAIProvider.new(_logger)
	openai.set_http_node(_http_request)
	_providers["OpenAI"] = openai

	var anthropic: AnthropicProvider = AnthropicProvider.new(_logger)
	anthropic.set_http_node(_http_request)
	_providers["Anthropic"] = anthropic

	_orchestrator.set_llm_provider(mock)


func _setup_provider_list() -> void:
	if _dock == null:
		return
	var provider_names: Array[String] = []
	for key: Variant in _providers.keys():
		provider_names.append(str(key))
	_dock.set_provider_list(provider_names)

	var first_name: String = provider_names[0] if not provider_names.is_empty() else ""
	var first_provider: Variant = _providers.get(first_name)
	if first_provider != null:
		var models: Array[String] = first_provider.get_available_models()
		_dock.set_model_list(models)
		_dock.set_api_key_visible(first_provider.needs_api_key())


func _load_settings_to_ui() -> void:
	if _persistence == null or _dock == null:
		return
	var _settings: Dictionary = _persistence.load_settings()


func _connect_signals() -> void:
	if _dock == null or _orchestrator == null:
		return
	_dock.generate_requested.connect(_on_generate_requested)
	_dock.apply_requested.connect(_on_apply_requested)
	_dock.discard_requested.connect(_on_discard_requested)
	_dock.provider_changed.connect(_on_provider_changed)
	_dock.import_requested.connect(_on_import_requested)
	_dock.export_requested.connect(_on_export_requested)
	_dock.connection_test_requested.connect(_on_connection_test_requested)
	_orchestrator.pipeline_state_changed.connect(_on_pipeline_state_changed)
	_orchestrator.pipeline_progress.connect(_on_pipeline_progress)
	_orchestrator.pipeline_completed.connect(_on_pipeline_completed)
	_orchestrator.pipeline_failed.connect(_on_pipeline_failed)


func _disconnect_signals() -> void:
	if _dock != null:
		if _dock.generate_requested.is_connected(_on_generate_requested):
			_dock.generate_requested.disconnect(_on_generate_requested)
		if _dock.apply_requested.is_connected(_on_apply_requested):
			_dock.apply_requested.disconnect(_on_apply_requested)
		if _dock.discard_requested.is_connected(_on_discard_requested):
			_dock.discard_requested.disconnect(_on_discard_requested)
		if _dock.provider_changed.is_connected(_on_provider_changed):
			_dock.provider_changed.disconnect(_on_provider_changed)
		if _dock.import_requested.is_connected(_on_import_requested):
			_dock.import_requested.disconnect(_on_import_requested)
		if _dock.export_requested.is_connected(_on_export_requested):
			_dock.export_requested.disconnect(_on_export_requested)
		if _dock.connection_test_requested.is_connected(_on_connection_test_requested):
			_dock.connection_test_requested.disconnect(_on_connection_test_requested)
	if _orchestrator != null:
		if _orchestrator.pipeline_state_changed.is_connected(_on_pipeline_state_changed):
			_orchestrator.pipeline_state_changed.disconnect(_on_pipeline_state_changed)
		if _orchestrator.pipeline_progress.is_connected(_on_pipeline_progress):
			_orchestrator.pipeline_progress.disconnect(_on_pipeline_progress)
		if _orchestrator.pipeline_completed.is_connected(_on_pipeline_completed):
			_orchestrator.pipeline_completed.disconnect(_on_pipeline_completed)
		if _orchestrator.pipeline_failed.is_connected(_on_pipeline_failed):
			_orchestrator.pipeline_failed.disconnect(_on_pipeline_failed)


func _on_generate_requested(request: Dictionary) -> void:
	var raw_root: Node = EditorInterface.get_edited_scene_root()
	if raw_root == null:
		var errs: Array[Dictionary] = [{
			"code": "UI_ERR_NO_SCENE",
			"message": "No scene open. Create or open a 3D scene first.",
			"path": "",
			"severity": "error",
			"stage": "ui",
			"fix_hint": "Open an existing scene or create a new Scene3D."
		}]
		_dock.show_errors(errs)
		return
	if not raw_root is Node3D:
		var errs: Array[Dictionary] = [{
			"code": "UI_ERR_NOT_3D",
			"message": "Scene root must be a Node3D (or subclass). Current root is '%s'." % raw_root.get_class(),
			"path": "",
			"severity": "error",
			"stage": "ui",
			"fix_hint": "Create a new scene with a Node3D root."
		}]
		_dock.show_errors(errs)
		return

	var provider_name: String = request.get("selected_provider", "") as String
	var api_key: String = request.get("api_key", "") as String
	var host_url: String = request.get("host_url", "") as String
	var provider: Variant = _providers.get(provider_name)
	if provider != null:
		if provider.needs_base_url() and not host_url.is_empty():
			provider.set_base_url(host_url)
			_persistence.set_provider_url(provider_name, host_url)
		if provider.needs_api_key():
			provider.set_api_key(api_key)
			_persistence.set_api_key(provider_name, api_key)
		_orchestrator.set_llm_provider(provider)

	var scene_root: Node3D = raw_root as Node3D
	_dock.set_state(AiSceneGenDock.DockState.GENERATING)
	await _orchestrator.start_generation(request, scene_root)


func _on_apply_requested() -> void:
	var raw_root: Node = EditorInterface.get_edited_scene_root()
	if raw_root == null or not raw_root is Node3D:
		return
	var scene_root: Node3D = raw_root as Node3D
	_orchestrator.apply_preview(get_undo_redo(), scene_root)
	_dock.set_state(AiSceneGenDock.DockState.IDLE)
	_dock.clear_errors()


func _on_discard_requested() -> void:
	_orchestrator.discard_preview()
	_dock.set_state(AiSceneGenDock.DockState.IDLE)
	_dock.clear_errors()


func _on_pipeline_state_changed(_old_state: int, new_state: int) -> void:
	if _dock == null:
		return
	match new_state:
		AiSceneGenOrchestrator.PipelineState.IDLE:
			_dock.set_state(AiSceneGenDock.DockState.IDLE)
		AiSceneGenOrchestrator.PipelineState.PREVIEW_READY:
			_dock.set_state(AiSceneGenDock.DockState.PREVIEW_READY)
		AiSceneGenOrchestrator.PipelineState.ERROR:
			_dock.set_state(AiSceneGenDock.DockState.ERROR)


func _on_pipeline_progress(percent: float, message: String) -> void:
	if _dock != null:
		_dock.show_progress(percent, message)


func _on_pipeline_completed(_spec: Dictionary) -> void:
	if _dock != null:
		_dock.show_progress(1.0, "Preview ready. Apply or discard.")


func _on_pipeline_failed(errors: Array[Dictionary]) -> void:
	if _dock != null:
		_dock.show_errors(errors)


func _setup_file_dialogs() -> void:
	_import_dialog = EditorFileDialog.new()
	_import_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_import_dialog.add_filter("*.scenespec.json", "SceneSpec JSON")
	_import_dialog.title = "Import SceneSpec"
	_import_dialog.file_selected.connect(_on_import_file_selected)
	add_child(_import_dialog)

	_export_dialog = EditorFileDialog.new()
	_export_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_export_dialog.add_filter("*.scenespec.json", "SceneSpec JSON")
	_export_dialog.title = "Export SceneSpec"
	_export_dialog.file_selected.connect(_on_export_file_selected)
	add_child(_export_dialog)


func _on_import_requested(_path: String) -> void:
	if _import_dialog != null:
		_import_dialog.popup_centered_ratio(0.6)


func _on_export_requested(_path: String) -> void:
	var spec: Dictionary = _orchestrator.get_last_spec()
	if spec.is_empty():
		var errs: Array[Dictionary] = [{
			"code": "EXPORT_ERR_NO_SPEC",
			"message": "No SceneSpec to export. Generate a scene first.",
			"path": "",
			"severity": "error",
			"stage": "ui",
			"fix_hint": "Generate a scene before exporting.",
		}]
		_dock.show_errors(errs)
		return
	if _export_dialog != null:
		_export_dialog.popup_centered_ratio(0.6)


func _on_import_file_selected(path: String) -> void:
	var spec: Dictionary = _persistence.import_spec(path)
	if spec.is_empty():
		var errs: Array[Dictionary] = [{
			"code": "IMPORT_ERR_FAILED",
			"message": "Failed to import SceneSpec from '%s'." % path,
			"path": path,
			"severity": "error",
			"stage": "ui",
			"fix_hint": "Check that the file exists, is valid JSON, and has spec_version 1.0.0.",
		}]
		_dock.show_errors(errs)
		return

	var raw_root: Node = EditorInterface.get_edited_scene_root()
	if raw_root == null or not raw_root is Node3D:
		var errs: Array[Dictionary] = [{
			"code": "UI_ERR_NO_SCENE",
			"message": "No 3D scene open. Open or create a 3D scene before importing.",
			"path": "",
			"severity": "error",
			"stage": "ui",
			"fix_hint": "Open a scene with a Node3D root.",
		}]
		_dock.show_errors(errs)
		return

	var scene_root: Node3D = raw_root as Node3D
	_dock.set_state(AiSceneGenDock.DockState.GENERATING)
	_orchestrator.rebuild_from_spec(spec, scene_root)


func _on_export_file_selected(path: String) -> void:
	var spec: Dictionary = _orchestrator.get_last_spec()
	if spec.is_empty():
		return
	var result: int = _persistence.export_spec(spec, path)
	if result != OK:
		var errs: Array[Dictionary] = [{
			"code": "EXPORT_ERR_WRITE",
			"message": "Failed to write SceneSpec to '%s'." % path,
			"path": path,
			"severity": "error",
			"stage": "ui",
			"fix_hint": "Check file permissions and that the path starts with res://.",
		}]
		_dock.show_errors(errs)
		return
	_logger.log_info(LOG_CATEGORY, "SceneSpec exported to %s" % path)


func _sync_asset_tags_to_dock() -> void:
	if _dock == null or _orchestrator == null:
		return
	var registry: Resource = _orchestrator.get_asset_registry()
	if registry == null:
		return
	var tags: Array[String] = registry.get_all_tags()
	_dock.update_asset_tags(tags, registry)


func _on_provider_changed(provider_name: String) -> void:
	_provider_switch_id += 1
	var my_switch_id: int = _provider_switch_id

	var provider: Variant = _providers.get(provider_name)
	if provider == null:
		_logger.log_warning(LOG_CATEGORY, "Unknown provider: %s" % provider_name)
		return

	_orchestrator.set_llm_provider(provider)

	var show_url: bool = provider.needs_base_url()
	_dock.set_host_url_visible(show_url)
	if show_url:
		var stored_url: String = _persistence.get_provider_url(provider_name)
		if stored_url.is_empty():
			stored_url = provider.get_default_base_url()
		_dock.set_host_url(stored_url)
		provider.set_base_url(stored_url)

	var show_key: bool = provider.needs_api_key()
	_dock.set_api_key_visible(show_key)
	if show_key:
		var stored_key: String = _persistence.get_api_key(provider_name)
		_dock.set_api_key(stored_key)
		provider.set_api_key(stored_key)

	var cached_models: Array[String] = _persistence.load_model_cache(provider_name)
	if not cached_models.is_empty():
		_dock.set_model_list(cached_models)

	var models_raw: Variant = await provider.fetch_available_models()
	if _provider_switch_id != my_switch_id:
		return

	var models: Array[String] = []
	if models_raw is Array:
		for m: Variant in models_raw as Array:
			models.append(str(m))
	_dock.set_model_list(models)
	if not models.is_empty():
		_persistence.save_model_cache(provider_name, models)


func _on_connection_test_requested(provider_name: String) -> void:
	_provider_switch_id += 1
	var my_switch_id: int = _provider_switch_id

	var provider: Variant = _providers.get(provider_name)
	if provider == null:
		_dock.show_connection_result(false, 0)
		return

	var models_raw: Variant = await provider.fetch_available_models()
	if _provider_switch_id != my_switch_id:
		return

	var models: Array[String] = []
	if models_raw is Array:
		for m: Variant in models_raw as Array:
			models.append(str(m))

	if models.size() > 0:
		_dock.show_connection_result(true, models.size())
		_dock.set_model_list(models)
		_persistence.save_model_cache(provider_name, models)
	else:
		_dock.show_connection_result(false, 0)
