@tool
class_name AiSceneGenPlugin
extends EditorPlugin

const PLUGIN_NAME: String = "AI Scene Generator"
const PLUGIN_VERSION: String = "1.0.0"
const LOG_CATEGORY: String = "ai_scene_gen.plugin"

var _dock: Control = null
var _orchestrator: RefCounted = null
var _persistence: RefCounted = null
var _logger: RefCounted = null
var _mock_provider: RefCounted = null


func _enter_tree() -> void:
	_logger = AiSceneGenLogger.new()
	_logger.set_log_level(AiSceneGenLogger.LogLevel.DEBUG)
	_logger.log_info(LOG_CATEGORY, "%s v%s loading..." % [PLUGIN_NAME, PLUGIN_VERSION])

	_persistence = AiSceneGenPersistence.new(_logger)

	_orchestrator = AiSceneGenOrchestrator.new(_logger)

	_mock_provider = MockProvider.new(_logger)
	_orchestrator.set_llm_provider(_mock_provider)

	_dock = AiSceneGenDock.new()
	_dock.name = "AISceneGen"
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, _dock)

	_setup_provider_list()
	_connect_signals()
	_load_settings_to_ui()

	_logger.log_info(LOG_CATEGORY, "%s v%s loaded." % [PLUGIN_NAME, PLUGIN_VERSION])


func _exit_tree() -> void:
	_disconnect_signals()
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	_orchestrator = null
	_persistence = null
	_mock_provider = null
	if _logger != null:
		_logger.log_info(LOG_CATEGORY, "%s unloaded." % PLUGIN_NAME)
	_logger = null


func _setup_provider_list() -> void:
	if _dock == null:
		return
	_dock.set_provider_list(["MockProvider"])
	_dock.set_model_list(_mock_provider.get_available_models())


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
	var scene_root: Node = get_editor_interface().get_edited_scene_root()
	if scene_root == null:
		_dock.show_errors([{
			"code": "UI_ERR_NO_SCENE",
			"message": "No scene open. Create or open a 3D scene first.",
			"path": "",
			"severity": "error",
			"stage": "ui",
			"fix_hint": "Open an existing scene or create a new Scene3D."
		}])
		return
	_dock.set_state(AiSceneGenDock.DockState.GENERATING)
	_orchestrator.start_generation(request, scene_root)


func _on_apply_requested() -> void:
	var scene_root: Node = get_editor_interface().get_edited_scene_root()
	if scene_root == null:
		return
	_orchestrator.apply_preview(scene_root)
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
