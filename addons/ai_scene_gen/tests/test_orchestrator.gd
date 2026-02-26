@tool
extends GutTest

## GUT tests for AiSceneGenOrchestrator (Module B).
## Covers: state management, pipeline flow with MockProvider, cancel, two-stage heuristic,
## schema retry with error feedback.


## Mock provider that returns invalid schema JSON on early calls and valid JSON later.
## Used to exercise the schema-retry logic in the orchestrator.
class _SchemaRetryMock extends LLMProvider:
	var call_count: int = 0
	var valid_json: String = ""
	var succeed_on_attempt: int = 2

	func get_provider_name() -> String:
		return "SchemaRetryMock"

	func is_configured() -> bool:
		return true

	func get_available_models() -> Array[String]:
		var m: Array[String] = ["test-model"]
		return m

	func send_request(_prompt: String, _model: String, _temp: float, _seed: int) -> LLMResponse:
		call_count += 1
		if succeed_on_attempt > 0 and call_count >= succeed_on_attempt:
			var usage: Dictionary = {"prompt_tokens": 100, "completion_tokens": 200}
			return LLMResponse.create_success(valid_json, 10, usage)
		var usage: Dictionary = {"prompt_tokens": 50, "completion_tokens": 50}
		return LLMResponse.create_success('{"not_a_valid_spec": true}', 10, usage)


## Like _SchemaRetryMock but also captures the prompt sent to it.
class _PromptCaptureMock extends LLMProvider:
	var call_count: int = 0
	var valid_json: String = ""
	var succeed_on_attempt: int = 2
	var last_prompt: String = ""

	func get_provider_name() -> String:
		return "PromptCaptureMock"

	func is_configured() -> bool:
		return true

	func get_available_models() -> Array[String]:
		var m: Array[String] = ["test-model"]
		return m

	func send_request(prompt: String, _model: String, _temp: float, _seed: int) -> LLMResponse:
		call_count += 1
		last_prompt = prompt
		if succeed_on_attempt > 0 and call_count >= succeed_on_attempt:
			var usage: Dictionary = {"prompt_tokens": 100, "completion_tokens": 200}
			return LLMResponse.create_success(valid_json, 10, usage)
		var usage: Dictionary = {"prompt_tokens": 50, "completion_tokens": 50}
		return LLMResponse.create_success('{"not_a_valid_spec": true}', 10, usage)


var _orchestrator: AiSceneGenOrchestrator
var _root: Node3D
var _received_states: Array[int] = []
var _received_errors: Array[Dictionary] = []
var _completed_spec: Dictionary = {}


func before_each() -> void:
	_orchestrator = AiSceneGenOrchestrator.new()
	_root = Node3D.new()
	add_child(_root)
	_received_states = []
	_received_errors = []
	_completed_spec = {}
	_orchestrator.pipeline_state_changed.connect(_on_state_changed)
	_orchestrator.pipeline_failed.connect(_on_failed)
	_orchestrator.pipeline_completed.connect(_on_completed)


func after_each() -> void:
	if is_instance_valid(_root):
		remove_child(_root)
		_root.queue_free()


# region --- Signal handlers ---

func _on_state_changed(_old: int, new_state: int) -> void:
	_received_states.append(new_state)


func _on_failed(errors: Array[Dictionary]) -> void:
	_received_errors = errors


func _on_completed(spec: Dictionary) -> void:
	_completed_spec = spec

# endregion

# region --- Helpers ---

func _make_valid_request(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"user_prompt": "a simple test scene with one box",
		"selected_model": "mock-outdoor",
		"selected_provider": "MockProvider",
		"style_preset": "blockout",
		"seed": 42,
		"bounds_meters": [20.0, 10.0, 20.0],
		"available_asset_tags": [],
		"project_constraints": "",
		"two_stage": false,
		"variation": false,
	}
	for key: String in overrides.keys():
		base[key] = overrides[key]
	return base

# endregion

# region --- Initial state ---

func test_initial_state_is_idle() -> void:
	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.IDLE,
		"orchestrator should start in IDLE"
	)


func test_last_spec_empty_initially() -> void:
	assert_true(
		_orchestrator.get_last_spec().is_empty(),
		"last spec should be empty on init"
	)


func test_last_errors_empty_initially() -> void:
	assert_eq(
		_orchestrator.get_last_errors().size(),
		0,
		"last errors should be empty on init"
	)

# endregion

# region --- Pipeline with MockProvider ---

func test_pipeline_completes_with_mock_provider() -> void:
	_orchestrator.set_llm_provider(MockProvider.new())
	var request: Dictionary = _make_valid_request()

	await _orchestrator.start_generation(request, _root)

	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.PREVIEW_READY,
		"pipeline should reach PREVIEW_READY"
	)
	assert_false(
		_completed_spec.is_empty(),
		"completed spec should not be empty"
	)


func test_pipeline_transitions_through_states() -> void:
	_orchestrator.set_llm_provider(MockProvider.new())
	var request: Dictionary = _make_valid_request()

	await _orchestrator.start_generation(request, _root)

	assert_has(
		_received_states,
		AiSceneGenOrchestrator.PipelineState.GENERATING,
		"should pass through GENERATING"
	)
	assert_has(
		_received_states,
		AiSceneGenOrchestrator.PipelineState.VALIDATING,
		"should pass through VALIDATING"
	)
	assert_has(
		_received_states,
		AiSceneGenOrchestrator.PipelineState.BUILDING,
		"should pass through BUILDING"
	)
	assert_has(
		_received_states,
		AiSceneGenOrchestrator.PipelineState.PREVIEW_READY,
		"should reach PREVIEW_READY"
	)

# endregion

# region --- No provider ---

func test_no_provider_fails() -> void:
	var request: Dictionary = _make_valid_request()

	await _orchestrator.start_generation(request, _root)

	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.ERROR,
		"should be in ERROR without provider"
	)
	assert_gt(_received_errors.size(), 0, "should have errors")

# endregion

# region --- Cancel ---

func test_cancel_from_idle_is_noop() -> void:
	_orchestrator.cancel_generation()
	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.IDLE,
		"cancel from IDLE should stay IDLE"
	)
	assert_eq(_received_errors.size(), 0, "no errors on IDLE cancel")


func test_cancel_emits_cancelled_error() -> void:
	_orchestrator.set_llm_provider(MockProvider.new())
	_orchestrator._change_state(AiSceneGenOrchestrator.PipelineState.GENERATING)

	_orchestrator.cancel_generation()

	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.IDLE,
		"cancel should return to IDLE"
	)
	assert_gt(_received_errors.size(), 0, "should emit errors on cancel")

	var found_cancel: bool = false
	for err: Dictionary in _received_errors:
		if err.get("code", "") == "ORCH_ERR_CANCELLED":
			found_cancel = true
			break
	assert_true(found_cancel, "errors should contain ORCH_ERR_CANCELLED")

# endregion

# region --- Discard ---

func test_discard_returns_to_idle() -> void:
	_orchestrator.set_llm_provider(MockProvider.new())
	var request: Dictionary = _make_valid_request()

	await _orchestrator.start_generation(request, _root)
	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.PREVIEW_READY
	)

	_orchestrator.discard_preview()
	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.IDLE,
		"discard should return to IDLE"
	)

# endregion

# region --- Two-stage heuristic ---

func test_two_stage_explicit_flag() -> void:
	_orchestrator.set_llm_provider(MockProvider.new())
	var request: Dictionary = _make_valid_request({"two_stage": true})

	await _orchestrator.start_generation(request, _root)

	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.PREVIEW_READY,
		"two-stage with explicit flag should complete"
	)


func test_two_stage_word_count_heuristic() -> void:
	var long_prompt: String = ""
	for i: int in range(35):
		long_prompt += "word%d " % i

	_orchestrator.set_llm_provider(MockProvider.new())
	var request: Dictionary = _make_valid_request({"user_prompt": long_prompt.strip_edges()})

	await _orchestrator.start_generation(request, _root)

	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.PREVIEW_READY,
		"long prompt (>30 words) should trigger two-stage and complete"
	)

# endregion

# region --- Correlation ID ---

func test_correlation_id_changes_between_runs() -> void:
	_orchestrator.set_llm_provider(MockProvider.new())

	await _orchestrator.start_generation(_make_valid_request(), _root)
	_orchestrator.discard_preview()
	var first_errors: Array[Dictionary] = _orchestrator.get_last_errors()

	var root2: Node3D = Node3D.new()
	add_child(root2)
	await _orchestrator.start_generation(_make_valid_request({"seed": 99}), root2)

	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.PREVIEW_READY,
		"second run should also complete"
	)
	root2.queue_free()

# endregion

# region --- Schema retry ---

func test_schema_retry_succeeds_on_second_attempt() -> void:
	var valid_json: String = _load_mock_json()
	if valid_json.is_empty():
		pending("mock file not available")
		return

	var mock: _SchemaRetryMock = _SchemaRetryMock.new()
	mock.valid_json = valid_json
	mock.succeed_on_attempt = 2
	_orchestrator.set_llm_provider(mock)

	var request: Dictionary = _make_valid_request()
	await _orchestrator.start_generation(request, _root)

	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.PREVIEW_READY,
		"schema retry should recover and reach PREVIEW_READY"
	)
	assert_eq(mock.call_count, 2, "should have called LLM twice (initial + 1 schema retry)")


func test_schema_retry_exhaustion_fails() -> void:
	var mock: _SchemaRetryMock = _SchemaRetryMock.new()
	mock.valid_json = ""
	mock.succeed_on_attempt = 0
	_orchestrator.set_llm_provider(mock)

	var request: Dictionary = _make_valid_request()
	await _orchestrator.start_generation(request, _root)

	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.ERROR,
		"should fail after exhausting schema retries"
	)
	assert_gt(_received_errors.size(), 0, "should have validation errors")
	assert_eq(
		mock.call_count,
		1 + AiSceneGenOrchestrator.MAX_SCHEMA_RETRIES,
		"should have called LLM 1 + MAX_SCHEMA_RETRIES times"
	)


func test_schema_retry_passes_validation_errors_to_prompt() -> void:
	var valid_json: String = _load_mock_json()
	if valid_json.is_empty():
		pending("mock file not available")
		return

	var mock: _PromptCaptureMock = _PromptCaptureMock.new()
	mock.valid_json = valid_json
	mock.succeed_on_attempt = 2
	_orchestrator.set_llm_provider(mock)

	await _orchestrator.start_generation(_make_valid_request(), _root)

	assert_eq(
		_orchestrator.get_current_state(),
		AiSceneGenOrchestrator.PipelineState.PREVIEW_READY,
		"should complete after retry"
	)
	assert_true(
		mock.last_prompt.find("Validation errors") != -1,
		"retry prompt should contain validation error feedback"
	)
	assert_true(
		mock.last_prompt.find("not_a_valid_spec") != -1,
		"retry prompt should contain the invalid JSON"
	)

# endregion

# region --- Schema retry helpers ---

func _load_mock_json() -> String:
	var path: String = "res://addons/ai_scene_gen/mocks/outdoor_clearing.scenespec.json"
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content: String = file.get_as_text()
	file.close()
	return content

# endregion
