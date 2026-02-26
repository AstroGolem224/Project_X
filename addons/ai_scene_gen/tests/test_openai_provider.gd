@tool
extends GutTest

## GUT tests for OpenAIProvider (Module C).
## Covers: configuration, error guards, cancel, default models, token extraction.

var _provider: OpenAIProvider


func before_each() -> void:
	_provider = OpenAIProvider.new()


# region --- Provider identity ---

func test_provider_name() -> void:
	assert_eq(_provider.get_provider_name(), "OpenAI")


func test_needs_api_key_true() -> void:
	assert_true(_provider.needs_api_key(), "OpenAI should require API key")


func test_needs_base_url_false() -> void:
	assert_false(_provider.needs_base_url(), "OpenAI should not need base URL")

# endregion

# region --- Configuration ---

func test_is_configured_without_http_node() -> void:
	_provider.set_api_key("sk-test-key")
	assert_false(_provider.is_configured(), "should not be configured without HTTP node")


func test_is_configured_without_api_key() -> void:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	_provider.set_http_node(http)
	assert_false(_provider.is_configured(), "should not be configured without API key")
	http.queue_free()


func test_is_configured_with_both() -> void:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	_provider.set_http_node(http)
	_provider.set_api_key("sk-test-key")
	assert_true(_provider.is_configured(), "should be configured with HTTP node and API key")
	http.queue_free()

# endregion

# region --- Health check ---

func test_health_check_without_http_node() -> void:
	var result: Dictionary = _provider.health_check()
	assert_eq(result["status"], "error")


func test_health_check_without_api_key() -> void:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	_provider.set_http_node(http)
	var result: Dictionary = _provider.health_check()
	assert_eq(result["status"], "error")
	http.queue_free()

# endregion

# region --- Send request error guards ---

func test_send_request_without_http_node() -> void:
	var response: LLMResponse = await _provider.send_request("test", "gpt-4o", 0.0, 42)
	assert_false(response.is_success())
	assert_eq(response.get_error_code(), "LLM_ERR_NOT_CONFIGURED")


func test_send_request_empty_model() -> void:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	_provider.set_http_node(http)
	_provider.set_api_key("sk-test-key")

	var response: LLMResponse = await _provider.send_request("test", "", 0.0, 42)
	assert_false(response.is_success())
	assert_eq(response.get_error_code(), "LLM_ERR_NOT_CONFIGURED")
	http.queue_free()


func test_send_request_empty_api_key() -> void:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	_provider.set_http_node(http)

	var response: LLMResponse = await _provider.send_request("test", "gpt-4o", 0.0, 42)
	assert_false(response.is_success())
	assert_eq(response.get_error_code(), "LLM_ERR_AUTH")
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
	assert_has(models, "gpt-4o", "should contain gpt-4o")
	assert_has(models, "gpt-4o-mini", "should contain gpt-4o-mini")


func test_fetch_models_without_http_returns_cached() -> void:
	var models: Array[String] = await _provider.fetch_available_models()
	assert_gt(models.size(), 0, "should return cached models when no HTTP node")

# endregion

# region --- Token usage extraction ---

func test_extract_token_usage_from_valid_response() -> void:
	var resp: Dictionary = {
		"usage": {
			"prompt_tokens": 150,
			"completion_tokens": 300,
			"total_tokens": 450,
		}
	}
	var usage: Dictionary = _provider._extract_token_usage(resp)
	assert_eq(usage["prompt_tokens"], 150)
	assert_eq(usage["completion_tokens"], 300)
	assert_eq(usage["total_tokens"], 450)


func test_extract_token_usage_missing_usage() -> void:
	var resp: Dictionary = {}
	var usage: Dictionary = _provider._extract_token_usage(resp)
	assert_eq(usage.size(), 0, "should return empty dict when no usage field")


func test_extract_content_from_valid_response() -> void:
	var resp: Dictionary = {
		"choices": [
			{
				"message": {
					"role": "assistant",
					"content": '{"spec_version":"1.0.0"}',
				}
			}
		]
	}
	var content: String = _provider._extract_content(resp)
	assert_eq(content, '{"spec_version":"1.0.0"}')


func test_extract_content_empty_choices() -> void:
	var resp: Dictionary = {"choices": []}
	var content: String = _provider._extract_content(resp)
	assert_eq(content, "", "should return empty string for empty choices")

# endregion
