@tool
class_name AiSceneGenOrchestrator
extends RefCounted

## Central pipeline controller that orchestrates prompt compilation, LLM requests,
## validation, asset resolution, scene building, post-processing, and preview.

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal pipeline_state_changed(old_state: int, new_state: int)
signal pipeline_progress(percent: float, message: String)
signal pipeline_completed(spec: Dictionary)
signal pipeline_failed(errors: Array[Dictionary])

# ---------------------------------------------------------------------------
# Enums & Constants
# ---------------------------------------------------------------------------

enum PipelineState {
	IDLE = 0,
	GENERATING = 1,
	VALIDATING = 2,
	RESOLVING = 3,
	BUILDING = 4,
	POST_PROCESSING = 5,
	PREVIEW_READY = 6,
	APPLYING = 7,
	ERROR = 8,
}

const LOG_CATEGORY: String = "ai_scene_gen.orchestrator"
const MAX_JSON_RETRIES: int = 2
const MAX_SCHEMA_RETRIES: int = 1

# ---------------------------------------------------------------------------
# Private vars
# ---------------------------------------------------------------------------

var _state: int = PipelineState.IDLE
var _logger: RefCounted = null
var _prompt_compiler: RefCounted = null
var _llm_provider: RefCounted = null
var _validator: RefCounted = null
var _asset_registry: Resource = null
var _asset_resolver: RefCounted = null
var _scene_builder: RefCounted = null
var _post_processor: RefCounted = null
var _preview_layer: RefCounted = null
var _primitive_factory: RefCounted = null
var _last_spec: Dictionary = {}
var _last_errors: Array[Dictionary] = []
var _correlation_id: String = ""


func _init(logger: RefCounted = null) -> void:
	_logger = logger
	_prompt_compiler = PromptCompiler.new(logger)
	_validator = SceneSpecValidator.new(logger)
	_asset_registry = AssetTagRegistry.new()
	_asset_registry.set_logger(logger)
	_asset_resolver = AssetResolver.new(logger)
	_primitive_factory = ProceduralPrimitiveFactory.new(logger)
	_scene_builder = SceneBuilder.new(logger, _primitive_factory)
	_post_processor = PostProcessor.new(logger)
	_preview_layer = PreviewLayer.new(logger)


# ---------------------------------------------------------------------------
# Public – Provider / Registry access
# ---------------------------------------------------------------------------

## Injects the LLM provider used for generation requests.
## @param provider: An LLMProvider-compatible RefCounted (must implement send_request).
func set_llm_provider(provider: RefCounted) -> void:
	_llm_provider = provider


## Returns the currently configured LLM provider, or null.
func get_llm_provider() -> RefCounted:
	return _llm_provider


## Returns the asset tag registry so UI layers can browse/edit tags.
func get_asset_registry() -> Resource:
	return _asset_registry


# ---------------------------------------------------------------------------
# Public – Pipeline operations
# ---------------------------------------------------------------------------

## Runs the full generation pipeline: compile -> LLM -> validate -> resolve -> build -> post -> preview.
## @param request: Generation request dictionary (prompt, style_preset, selected_model, seed, …).
## @param scene_root: The active editor scene root node to parent the preview under.
func start_generation(request: Dictionary, scene_root: Node3D) -> void:
	if _state != PipelineState.IDLE and _state != PipelineState.ERROR:
		_emit_error("ORCH_ERR_ALREADY_RUNNING", "A generation is already in progress.")
		return

	_last_spec = {}
	_last_errors = []
	_correlation_id = "run_" + str(Time.get_ticks_msec())
	_log("info", "pipeline started [%s]" % _correlation_id)

	# --- Step 1: Compile prompt ---
	_change_state(PipelineState.GENERATING)
	pipeline_progress.emit(0.0, "Compiling prompt...")

	var compiled_prompt: String = _prompt_compiler.compile_single_stage(request)
	if compiled_prompt.is_empty():
		_fail_pipeline("ORCH_ERR_STAGE_FAILED", "Pipeline failed at 'compile': prompt compilation returned empty.")
		return

	var fingerprint: String = _prompt_compiler.build_determinism_fingerprint(request)
	_log("debug", "fingerprint: %s" % fingerprint)
	pipeline_progress.emit(0.1, "Sending to LLM...")

	# --- Step 2: LLM request with retries ---
	if _llm_provider == null:
		_fail_pipeline("ORCH_ERR_STAGE_FAILED", "No LLM provider configured.")
		return

	var model: String = request.get("selected_model", "") as String
	var seed_val: int = request.get("seed", 42) as int
	var raw_json: String = ""
	var json_retries: int = 0
	var last_response: RefCounted = null

	while json_retries <= MAX_JSON_RETRIES:
		var response: RefCounted = _llm_provider.send_request(compiled_prompt, model, 0.0, seed_val)
		last_response = response
		if not response.is_success():
			json_retries += 1
			_log("warning", "LLM attempt %d/%d failed: %s" % [json_retries, MAX_JSON_RETRIES + 1, response.get_error_message()])
			if json_retries > MAX_JSON_RETRIES:
				_fail_pipeline("ORCH_ERR_RETRY_EXHAUSTED", "LLM request failed after %d retries: %s" % [MAX_JSON_RETRIES, response.get_error_message()])
				return
			continue
		raw_json = response.get_raw_body()
		break

	if _logger != null and last_response != null:
		_logger.record_metric("llm_latency_ms", last_response.get_latency_ms())
	pipeline_progress.emit(0.3, "Validating SceneSpec...")

	# --- Step 3: Validate ---
	_change_state(PipelineState.VALIDATING)

	raw_json = _strip_markdown_fences(raw_json)
	var validation: RefCounted = _validator.validate_json_string(raw_json)

	if not validation.is_valid():
		_last_errors = validation.get_errors()
		_tag_errors_with_correlation(_last_errors)
		_fail_pipeline_with_errors(_last_errors)
		return

	var spec_or_null: Variant = validation.get_spec_or_null()
	if spec_or_null == null:
		_fail_pipeline("ORCH_ERR_STAGE_FAILED", "Validation passed but spec is null.")
		return

	var spec: Dictionary = spec_or_null as Dictionary
	_last_spec = spec
	pipeline_progress.emit(0.5, "Resolving assets...")

	# --- Step 4: Resolve assets ---
	_change_state(PipelineState.RESOLVING)

	var resolved: RefCounted = _asset_resolver.resolve_nodes(spec, _asset_registry)
	_log("info", "assets resolved=%d, fallback=%d, missing=%s" % [
		resolved.get_resolved_count(),
		resolved.get_fallback_count(),
		str(resolved.get_missing_tags()),
	])
	pipeline_progress.emit(0.6, "Building scene...")

	# --- Step 5: Build scene ---
	_change_state(PipelineState.BUILDING)

	var preview_root: Node3D = Node3D.new()
	var build_result: RefCounted = _scene_builder.build(resolved.get_spec(), preview_root)

	if not build_result.is_success():
		_last_errors = build_result.get_errors()
		preview_root.queue_free()
		_fail_pipeline_with_errors(_last_errors)
		return

	if _logger != null:
		_logger.record_metric("build_node_count", build_result.get_node_count())
		_logger.record_metric("build_duration_ms", build_result.get_build_duration_ms())
	pipeline_progress.emit(0.8, "Post-processing...")

	# --- Step 6: Post-process ---
	_change_state(PipelineState.POST_PROCESSING)

	var post_warnings: Array[Dictionary] = _post_processor.execute_all(preview_root, spec)
	if not post_warnings.is_empty():
		_log("info", "%d post-processing warning(s)" % post_warnings.size())
	pipeline_progress.emit(0.9, "Showing preview...")

	# --- Step 7: Preview ---
	var preview_err: Dictionary = _preview_layer.show_preview(preview_root, scene_root)
	if not preview_err.is_empty():
		preview_root.queue_free()
		_fail_pipeline(
			preview_err.get("code", "PREVIEW_ERR") as String,
			preview_err.get("message", "Preview failed") as String,
		)
		return

	_change_state(PipelineState.PREVIEW_READY)
	pipeline_progress.emit(1.0, "Preview ready.")
	pipeline_completed.emit(spec)
	_log("info", "pipeline completed [%s]" % _correlation_id)


## Cancels a running generation and returns to IDLE.
func cancel_generation() -> void:
	if _state == PipelineState.IDLE:
		return
	_change_state(PipelineState.IDLE)
	_log("info", "generation cancelled by user")


## Applies the current preview into the scene tree permanently.
## @param scene_root: The active editor scene root.
func apply_preview(scene_root: Node3D) -> void:
	if _state != PipelineState.PREVIEW_READY:
		_emit_error("ORCH_ERR_STAGE_FAILED", "Cannot apply: no preview active.")
		return

	_change_state(PipelineState.APPLYING)
	var err: Dictionary = _preview_layer.apply_to_scene(scene_root)

	if not err.is_empty():
		_fail_pipeline(
			err.get("code", "") as String,
			err.get("message", "") as String,
		)
		return

	_change_state(PipelineState.IDLE)
	_log("info", "preview applied to scene")


## Discards the current preview without applying.
func discard_preview() -> void:
	_preview_layer.discard()
	_change_state(PipelineState.IDLE)
	_log("info", "preview discarded")


## Re-runs the pipeline from validation onward using a pre-existing spec.
## Skips prompt compilation and LLM request.
## @param spec: A SceneSpec dictionary to validate and build.
## @param scene_root: The active editor scene root.
func rebuild_from_spec(spec: Dictionary, scene_root: Node3D) -> void:
	if _state != PipelineState.IDLE and _state != PipelineState.ERROR:
		_emit_error("ORCH_ERR_ALREADY_RUNNING", "A generation is already in progress.")
		return

	_last_spec = {}
	_last_errors = []
	_correlation_id = "rebuild_" + str(Time.get_ticks_msec())
	_log("info", "rebuild started [%s]" % _correlation_id)

	# Validate
	_change_state(PipelineState.VALIDATING)
	pipeline_progress.emit(0.3, "Validating SceneSpec...")

	var raw_json: String = JSON.stringify(spec)
	var validation: RefCounted = _validator.validate_json_string(raw_json)

	if not validation.is_valid():
		_last_errors = validation.get_errors()
		_tag_errors_with_correlation(_last_errors)
		_fail_pipeline_with_errors(_last_errors)
		return

	var validated_spec: Variant = validation.get_spec_or_null()
	if validated_spec == null:
		_fail_pipeline("ORCH_ERR_STAGE_FAILED", "Validation passed but spec is null.")
		return

	_last_spec = validated_spec as Dictionary
	pipeline_progress.emit(0.5, "Resolving assets...")

	# Resolve
	_change_state(PipelineState.RESOLVING)
	var resolved: RefCounted = _asset_resolver.resolve_nodes(_last_spec, _asset_registry)
	_log("info", "assets resolved=%d, fallback=%d, missing=%s" % [
		resolved.get_resolved_count(),
		resolved.get_fallback_count(),
		str(resolved.get_missing_tags()),
	])
	pipeline_progress.emit(0.6, "Building scene...")

	# Build
	_change_state(PipelineState.BUILDING)
	var preview_root: Node3D = Node3D.new()
	var build_result: RefCounted = _scene_builder.build(resolved.get_spec(), preview_root)

	if not build_result.is_success():
		_last_errors = build_result.get_errors()
		preview_root.queue_free()
		_fail_pipeline_with_errors(_last_errors)
		return

	if _logger != null:
		_logger.record_metric("build_node_count", build_result.get_node_count())
		_logger.record_metric("build_duration_ms", build_result.get_build_duration_ms())
	pipeline_progress.emit(0.8, "Post-processing...")

	# Post-process
	_change_state(PipelineState.POST_PROCESSING)
	var post_warnings: Array[Dictionary] = _post_processor.execute_all(preview_root, _last_spec)
	if not post_warnings.is_empty():
		_log("info", "%d post-processing warning(s)" % post_warnings.size())
	pipeline_progress.emit(0.9, "Showing preview...")

	# Preview
	var preview_err: Dictionary = _preview_layer.show_preview(preview_root, scene_root)
	if not preview_err.is_empty():
		preview_root.queue_free()
		_fail_pipeline(
			preview_err.get("code", "PREVIEW_ERR") as String,
			preview_err.get("message", "Preview failed") as String,
		)
		return

	_change_state(PipelineState.PREVIEW_READY)
	pipeline_progress.emit(1.0, "Preview ready.")
	pipeline_completed.emit(_last_spec)
	_log("info", "rebuild completed [%s]" % _correlation_id)


# ---------------------------------------------------------------------------
# Public – State accessors
# ---------------------------------------------------------------------------

## Returns the current pipeline state as a PipelineState enum value.
func get_current_state() -> int:
	return _state


## Returns the last successfully validated spec, or empty dict.
func get_last_spec() -> Dictionary:
	return _last_spec


## Returns errors from the most recent pipeline failure.
func get_last_errors() -> Array[Dictionary]:
	return _last_errors


# ---------------------------------------------------------------------------
# Private – State machine
# ---------------------------------------------------------------------------

func _change_state(new_state: int) -> void:
	var old: int = _state
	_state = new_state
	pipeline_state_changed.emit(old, new_state)
	_log("debug", "state: %s -> %s" % [_state_name(old), _state_name(new_state)])


func _state_name(state: int) -> String:
	match state:
		PipelineState.IDLE:
			return "IDLE"
		PipelineState.GENERATING:
			return "GENERATING"
		PipelineState.VALIDATING:
			return "VALIDATING"
		PipelineState.RESOLVING:
			return "RESOLVING"
		PipelineState.BUILDING:
			return "BUILDING"
		PipelineState.POST_PROCESSING:
			return "POST_PROCESSING"
		PipelineState.PREVIEW_READY:
			return "PREVIEW_READY"
		PipelineState.APPLYING:
			return "APPLYING"
		PipelineState.ERROR:
			return "ERROR"
		_:
			return "UNKNOWN(%d)" % state


# ---------------------------------------------------------------------------
# Private – Error helpers
# ---------------------------------------------------------------------------

func _fail_pipeline(code: String, message: String) -> void:
	var err: Dictionary = _make_error(code, message)
	_last_errors = [err]
	_log("error", "[%s] %s" % [code, message])
	_change_state(PipelineState.ERROR)
	pipeline_failed.emit(_last_errors)


func _fail_pipeline_with_errors(errors: Array[Dictionary]) -> void:
	_last_errors = errors
	for err: Dictionary in errors:
		_log("error", "[%s] %s" % [err.get("code", ""), err.get("message", "")])
	_change_state(PipelineState.ERROR)
	pipeline_failed.emit(errors)


func _emit_error(code: String, message: String) -> void:
	_log("error", "[%s] %s" % [code, message])
	pipeline_failed.emit([_make_error(code, message)])


func _make_error(code: String, message: String) -> Dictionary:
	return {
		"stage": "orchestrator",
		"severity": "error",
		"code": code,
		"message": message,
		"path": "",
		"fix_hint": "",
		"correlation_id": _correlation_id,
	}


func _tag_errors_with_correlation(errors: Array[Dictionary]) -> void:
	for err: Dictionary in errors:
		err["correlation_id"] = _correlation_id


# ---------------------------------------------------------------------------
# Private – Utility
# ---------------------------------------------------------------------------

func _strip_markdown_fences(text: String) -> String:
	var stripped: String = text.strip_edges()
	if not stripped.begins_with("```"):
		return stripped

	var first_brace: int = stripped.find("{")
	var last_brace: int = stripped.rfind("}")
	if first_brace == -1 or last_brace == -1 or last_brace <= first_brace:
		return stripped

	return stripped.substr(first_brace, last_brace - first_brace + 1)


func _log(level: String, message: String) -> void:
	if _logger == null:
		return
	match level:
		"debug":
			_logger.log_debug(LOG_CATEGORY, message)
		"info":
			_logger.log_info(LOG_CATEGORY, message)
		"warning":
			_logger.log_warning(LOG_CATEGORY, message)
		"error":
			_logger.log_error(LOG_CATEGORY, message)
