@tool
extends GutTest

## GUT tests for OllamaProvider (Module C).
## Covers: configuration, error guards, cancel, default models.

var _provider: OllamaProvider


func before_each() -> void:
	_provider = OllamaProvider.new()


# region --- Provider identity ---

func test_provider_name() -> void:
	assert_eq(_provider.get_provider_name(), "Ollama")


func test_needs_api_key_false() -> void:
	assert_false(_provider.needs_api_key(), "Ollama should not need API key")


func test_needs_base_url_true() -> void:
	assert_true(_provider.needs_base_url(), "Ollama should need base URL")


func test_default_base_url() -> void:
	assert_eq(
		_provider.get_default_base_url(),
		"http://localhost:11434",
		"default base URL should be localhost:11434"
	)

# endregion

# region --- Configuration ---

func test_is_configured_without_http_node() -> void:
	assert_false(_provider.is_configured(), "should not be configured without HTTP node")


func test_is_configured_with_http_node() -> void:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	_provider.set_http_node(http)
	assert_true(_provider.is_configured(), "should be configured with HTTP node")
	http.queue_free()


func test_set_base_url_changes_url() -> void:
	_provider.set_base_url("http://192.168.1.42:11434")
	assert_true(
		_provider.needs_base_url(),
		"needs_base_url should still be true after set"
	)

# endregion

# region --- Health check ---

func test_health_check_without_http_node() -> void:
	var result: Dictionary = _provider.health_check()
	assert_eq(result["status"], "error", "health_check without http_node should return error")

# endregion

# region --- Send request error guards ---

func test_send_request_without_http_node() -> void:
	var response: LLMResponse = await _provider.send_request("test prompt", "llama3:latest", 0.0, 42)
	assert_false(response.is_success(), "should fail without HTTP node")
	assert_eq(response.get_error_code(), "LLM_ERR_NOT_CONFIGURED")


func test_send_request_empty_model() -> void:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	_provider.set_http_node(http)

	var response: LLMResponse = await _provider.send_request("test prompt", "", 0.0, 42)
	assert_false(response.is_success(), "should fail with empty model")
	assert_eq(response.get_error_code(), "LLM_ERR_NOT_CONFIGURED")
	http.queue_free()

# endregion

# region --- Cancel safety ---

func test_cancel_without_http_node_no_crash() -> void:
	_provider.cancel()
	pass_test("cancel without http_node should not crash")


func test_cancel_with_http_node_no_crash() -> void:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	_provider.set_http_node(http)
	_provider.cancel()
	pass_test("cancel with http_node should not crash")
	http.queue_free()

# endregion

# region --- Default models ---

func test_get_available_models_returns_defaults() -> void:
	var models: Array[String] = _provider.get_available_models()
	assert_gt(models.size(), 0, "should return at least one default model")
	assert_has(models, "llama3:latest", "should contain llama3:latest")


func test_fetch_models_without_http_returns_cached() -> void:
	var models: Array[String] = await _provider.fetch_available_models()
	assert_gt(models.size(), 0, "should return cached models when no HTTP node")

# endregion
