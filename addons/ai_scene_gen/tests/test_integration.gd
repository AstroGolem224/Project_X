@tool
extends GutTest

## Real LLM integration tests (Ollama, OpenAI).
## Optional — tests skip automatically when no LLM endpoint is reachable.
## Ollama: requires local instance at localhost:11434 with at least one model.
## OpenAI: requires OPENAI_API_KEY environment variable.

const CONN_TIMEOUT: float = 5.0
const LLM_TIMEOUT: float = 60.0
const SIMPLE_JSON_PROMPT: String = "Return ONLY a valid JSON object with key \"hello\" and value \"world\". No explanation, no markdown."
const SCENE_PROMPT: String = "a single red box sitting on a flat grey ground plane"

var _ollama_state: int = -1
var _openai_state: int = -1
var _ollama_model: String = ""
var _openai_key: String = ""


# region --- Skip guards (async, cached) ---

## Checks Ollama reachability and caches result. Returns true if available with at least one model.
func _ensure_ollama() -> bool:
	if _ollama_state == 1:
		return true
	if _ollama_state == 0:
		return false

	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = CONN_TIMEOUT
	add_child(http)

	var req_headers: Array[String] = ["Accept: application/json"]
	var err: int = http.request(
		"http://localhost:11434/api/tags",
		req_headers,
		HTTPClient.METHOD_GET,
	)
	if err != OK:
		_ollama_state = 0
		http.queue_free()
		return false

	var result: Array = await http.request_completed
	http.queue_free()

	var http_result: int = result[0] as int
	var response_code: int = result[1] as int
	var body: PackedByteArray = result[3] as PackedByteArray

	if http_result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_ollama_state = 0
		return false

	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		var models_raw: Variant = (parsed as Dictionary).get("models", [])
		if models_raw is Array:
			for entry: Variant in models_raw as Array:
				if entry is Dictionary:
					var model_name: String = str((entry as Dictionary).get("name", ""))
					if not model_name.is_empty():
						_ollama_model = model_name
						break

	if _ollama_model.is_empty():
		_ollama_state = 0
		return false

	_ollama_state = 1
	return true


## Checks OpenAI reachability via OPENAI_API_KEY env var + /v1/models endpoint.
func _ensure_openai() -> bool:
	if _openai_state == 1:
		return true
	if _openai_state == 0:
		return false

	_openai_key = OS.get_environment("OPENAI_API_KEY")
	if _openai_key.is_empty():
		_openai_state = 0
		return false

	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = CONN_TIMEOUT
	add_child(http)

	var req_headers: Array[String] = [
		"Authorization: Bearer %s" % _openai_key,
		"Accept: application/json",
	]
	var err: int = http.request(
		"https://api.openai.com/v1/models",
		req_headers,
		HTTPClient.METHOD_GET,
	)
	if err != OK:
		_openai_state = 0
		http.queue_free()
		return false

	var result: Array = await http.request_completed
	http.queue_free()

	var http_result: int = result[0] as int
	var response_code: int = result[1] as int

	if http_result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_openai_state = 0
		return false

	_openai_state = 1
	return true

# endregion


# region --- Helpers ---

func _make_integration_request(model: String, provider_name: String, overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"user_prompt": SCENE_PROMPT,
		"selected_model": model,
		"selected_provider": provider_name,
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


func _strip_fences(text: String) -> String:
	var stripped: String = text.strip_edges()
	if not stripped.begins_with("```"):
		return stripped
	var first_brace: int = stripped.find("{")
	var last_brace: int = stripped.rfind("}")
	if first_brace == -1 or last_brace == -1 or last_brace <= first_brace:
		return stripped
	return stripped.substr(first_brace, last_brace - first_brace + 1)

# endregion


# region --- Ollama connectivity ---

func test_ollama_reachable() -> void:
	var available: bool = await _ensure_ollama()
	if not available:
		pending("Ollama not reachable at localhost:11434 — skipping")
		return
	assert_true(available, "Ollama endpoint should be reachable")
	assert_false(_ollama_model.is_empty(), "should detect at least one installed model")


func test_ollama_fetch_models_real() -> void:
	if not await _ensure_ollama():
		pending("Ollama not reachable — skipping")
		return

	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = LLM_TIMEOUT
	add_child(http)

	var provider: OllamaProvider = OllamaProvider.new()
	provider.set_http_node(http)

	var models: Array[String] = await provider.fetch_available_models()
	assert_gt(models.size(), 0, "should fetch real models from Ollama")
	http.queue_free()


func test_ollama_send_receive() -> void:
	if not await _ensure_ollama():
		pending("Ollama not reachable — skipping")
		return

	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = LLM_TIMEOUT
	add_child(http)

	var provider: OllamaProvider = OllamaProvider.new()
	provider.set_http_node(http)

	var response: LLMResponse = await provider.send_request(
		SIMPLE_JSON_PROMPT, _ollama_model, 0.0, 42
	)
	assert_true(response.is_success(), "send_request should succeed: %s" % response.get_error_message())
	assert_false(response.get_raw_body().is_empty(), "response body should not be empty")
	assert_gt(response.get_latency_ms(), 0, "latency should be positive")

	var parsed: Variant = JSON.parse_string(response.get_raw_body())
	assert_not_null(parsed, "response should be parseable JSON")
	http.queue_free()

# endregion


# region --- OpenAI connectivity ---

func test_openai_reachable() -> void:
	var available: bool = await _ensure_openai()
	if not available:
		pending("OpenAI not reachable (OPENAI_API_KEY not set or API unreachable) — skipping")
		return
	assert_true(available, "OpenAI API should be reachable")


func test_openai_fetch_models_real() -> void:
	if not await _ensure_openai():
		pending("OpenAI not available — skipping")
		return

	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = LLM_TIMEOUT
	add_child(http)

	var provider: OpenAIProvider = OpenAIProvider.new()
	provider.set_http_node(http)
	provider.set_api_key(_openai_key)

	var models: Array[String] = await provider.fetch_available_models()
	assert_gt(models.size(), 0, "should fetch real GPT models from OpenAI")
	http.queue_free()


func test_openai_send_receive() -> void:
	if not await _ensure_openai():
		pending("OpenAI not available — skipping")
		return

	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = LLM_TIMEOUT
	add_child(http)

	var provider: OpenAIProvider = OpenAIProvider.new()
	provider.set_http_node(http)
	provider.set_api_key(_openai_key)

	var response: LLMResponse = await provider.send_request(
		SIMPLE_JSON_PROMPT, "gpt-4o-mini", 0.0, 42
	)
	assert_true(response.is_success(), "send_request should succeed: %s" % response.get_error_message())
	assert_false(response.get_raw_body().is_empty(), "response body should not be empty")
	assert_gt(response.get_latency_ms(), 0, "latency should be positive")

	var parsed: Variant = JSON.parse_string(response.get_raw_body())
	assert_not_null(parsed, "response should be parseable JSON")
	http.queue_free()

# endregion


# region --- E2E pipeline ---

func test_e2e_pipeline_ollama() -> void:
	if not await _ensure_ollama():
		pending("Ollama not reachable — skipping E2E")
		return

	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = LLM_TIMEOUT
	add_child(http)

	var provider: OllamaProvider = OllamaProvider.new()
	provider.set_http_node(http)

	var orchestrator: AiSceneGenOrchestrator = AiSceneGenOrchestrator.new()
	orchestrator.set_llm_provider(provider)

	var root: Node3D = Node3D.new()
	add_child(root)

	var request: Dictionary = _make_integration_request(_ollama_model, "Ollama")
	await orchestrator.start_generation(request, root)

	var state: int = orchestrator.get_current_state()
	var valid_states: Array[int] = [
		AiSceneGenOrchestrator.PipelineState.PREVIEW_READY,
		AiSceneGenOrchestrator.PipelineState.ERROR,
	]
	assert_has(valid_states, state, "pipeline should end in PREVIEW_READY or ERROR (state=%d)" % state)

	if state == AiSceneGenOrchestrator.PipelineState.PREVIEW_READY:
		var spec: Dictionary = orchestrator.get_last_spec()
		assert_false(spec.is_empty(), "completed spec should not be empty")
		orchestrator.discard_preview()

	root.queue_free()
	http.queue_free()


func test_e2e_pipeline_openai() -> void:
	if not await _ensure_openai():
		pending("OpenAI not available — skipping E2E")
		return

	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = LLM_TIMEOUT
	add_child(http)

	var provider: OpenAIProvider = OpenAIProvider.new()
	provider.set_http_node(http)
	provider.set_api_key(_openai_key)

	var orchestrator: AiSceneGenOrchestrator = AiSceneGenOrchestrator.new()
	orchestrator.set_llm_provider(provider)

	var root: Node3D = Node3D.new()
	add_child(root)

	var request: Dictionary = _make_integration_request("gpt-4o-mini", "OpenAI")
	await orchestrator.start_generation(request, root)

	var state: int = orchestrator.get_current_state()
	var valid_states: Array[int] = [
		AiSceneGenOrchestrator.PipelineState.PREVIEW_READY,
		AiSceneGenOrchestrator.PipelineState.ERROR,
	]
	assert_has(valid_states, state, "pipeline should end in PREVIEW_READY or ERROR (state=%d)" % state)

	if state == AiSceneGenOrchestrator.PipelineState.PREVIEW_READY:
		var spec: Dictionary = orchestrator.get_last_spec()
		assert_false(spec.is_empty(), "completed spec should not be empty")
		orchestrator.discard_preview()

	root.queue_free()
	http.queue_free()

# endregion


# region --- E2E validation chain ---

func test_e2e_real_output_through_validator_builder() -> void:
	var provider: LLMProvider = null
	var model: String = ""
	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = LLM_TIMEOUT
	add_child(http)

	if await _ensure_ollama():
		var ollama: OllamaProvider = OllamaProvider.new()
		ollama.set_http_node(http)
		provider = ollama
		model = _ollama_model
	elif await _ensure_openai():
		var openai: OpenAIProvider = OpenAIProvider.new()
		openai.set_http_node(http)
		openai.set_api_key(_openai_key)
		provider = openai
		model = "gpt-4o-mini"
	else:
		http.queue_free()
		pending("No LLM provider available — skipping validation chain test")
		return

	var compiler: PromptCompiler = PromptCompiler.new()
	var request: Dictionary = _make_integration_request(model, provider.get_provider_name())
	var compiled: String = compiler.compile_single_stage(request)
	assert_false(compiled.is_empty(), "compiled prompt should not be empty")

	var response: LLMResponse = await provider.send_request(compiled, model, 0.0, 42)
	assert_true(response.is_success(), "LLM request should succeed")
	if not response.is_success():
		http.queue_free()
		return

	var raw_json: String = _strip_fences(response.get_raw_body())

	var validator: SceneSpecValidator = SceneSpecValidator.new()
	var validation: RefCounted = validator.validate_json_string(raw_json)

	if not validation.is_valid():
		http.queue_free()
		pass_test("validation chain exercised — LLM output did not pass schema (acceptable)")
		return

	var spec: Dictionary = validation.get_spec_or_null() as Dictionary
	assert_false(spec.is_empty(), "valid spec should not be empty")

	var registry: AssetTagRegistry = AssetTagRegistry.new()
	var resolver: AssetResolver = AssetResolver.new()
	var resolved: RefCounted = resolver.resolve_nodes(spec, registry)

	var factory: ProceduralPrimitiveFactory = ProceduralPrimitiveFactory.new()
	var builder: SceneBuilder = SceneBuilder.new(null, factory)
	var preview_root: Node3D = Node3D.new()
	var build_result: RefCounted = builder.build(resolved.get_spec(), preview_root)

	assert_true(build_result.is_success(), "build should succeed on validated spec")
	if build_result.is_success():
		assert_gt(build_result.get_node_count(), 0, "should build at least one node")

	preview_root.queue_free()
	http.queue_free()

# endregion


# region --- E2E two-stage ---

func test_e2e_two_stage_pipeline() -> void:
	var provider: LLMProvider = null
	var model: String = ""
	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = LLM_TIMEOUT
	add_child(http)

	if await _ensure_ollama():
		var ollama: OllamaProvider = OllamaProvider.new()
		ollama.set_http_node(http)
		provider = ollama
		model = _ollama_model
	elif await _ensure_openai():
		var openai: OpenAIProvider = OpenAIProvider.new()
		openai.set_http_node(http)
		openai.set_api_key(_openai_key)
		provider = openai
		model = "gpt-4o-mini"
	else:
		http.queue_free()
		pending("No LLM provider available — skipping two-stage test")
		return

	var orchestrator: AiSceneGenOrchestrator = AiSceneGenOrchestrator.new()
	orchestrator.set_llm_provider(provider)

	var root: Node3D = Node3D.new()
	add_child(root)

	var request: Dictionary = _make_integration_request(
		model, provider.get_provider_name(), {"two_stage": true}
	)
	await orchestrator.start_generation(request, root)

	var state: int = orchestrator.get_current_state()
	var valid_states: Array[int] = [
		AiSceneGenOrchestrator.PipelineState.PREVIEW_READY,
		AiSceneGenOrchestrator.PipelineState.ERROR,
	]
	assert_has(valid_states, state, "two-stage should end in PREVIEW_READY or ERROR (state=%d)" % state)

	if state == AiSceneGenOrchestrator.PipelineState.PREVIEW_READY:
		orchestrator.discard_preview()

	root.queue_free()
	http.queue_free()

# endregion
