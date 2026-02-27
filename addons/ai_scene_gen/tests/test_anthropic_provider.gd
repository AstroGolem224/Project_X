@tool
extends GutTest

## GUT tests for AnthropicProvider (Module C).
## Covers: configuration, error guards, cancel, default models, token extraction.

var _provider: AnthropicProvider


func before_each() -> void:
	_provider = AnthropicProvider.new()


# region --- Provider identity ---

func test_provider_name() -> void:
	assert_eq(_provider.get_provider_name(), "Anthropic")


func test_needs_api_key_true() -> void:
	assert_true(_provider.needs_api_key(), "Anthropic should require API key")


func test_needs_base_url_false() -> void:
	assert_false(_provider.needs_base_url(), "Anthropic should not need base URL")

# endregion

# region --- Configuration ---

func test_is_configured_without_http_node() -> void:
	_provider.set_api_key("sk-ant-test-key")
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
	_provider.set_api_key("sk-ant-test-key")
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
	var response: LLMResponse = await _provider.send_request("test", "claude-sonnet-4-20250514", 0.0, 42)
	assert_false(response.is_success())
	assert_eq(response.get_error_code(), "LLM_ERR_NOT_CONFIGURED")


func test_send_request_empty_model() -> void:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	_provider.set_http_node(http)
	_provider.set_api_key("sk-ant-test-key")

	var response: LLMResponse = await _provider.send_request("test", "", 0.0, 42)
	assert_false(response.is_success())
	assert_eq(response.get_error_code(), "LLM_ERR_NOT_CONFIGURED")
	http.queue_free()


func test_send_request_empty_api_key() -> void:
	var http: HTTPRequest = HTTPRequest.new()
	add_child(http)
	_provider.set_http_node(http)

	var response: LLMResponse = await _provider.send_request("test", "claude-sonnet-4-20250514", 0.0, 42)
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
	assert_eq(models.size(), 3, "should return 3 default models")
	assert_has(models, "claude-sonnet-4-20250514", "should contain claude-sonnet-4-20250514")
	assert_has(models, "claude-opus-4-20250514", "should contain claude-opus-4-20250514")
	assert_has(models, "claude-haiku-3-5-20241022", "should contain claude-haiku-3-5-20241022")


func test_fetch_models_falls_back_without_config() -> void:
	var models: Array[String] = await _provider.fetch_available_models()
	assert_eq(models.size(), 3, "should fall back to defaults without HTTP node")
	assert_has(models, "claude-sonnet-4-20250514")

# endregion

# region --- Token usage extraction ---

func test_extract_token_usage_from_valid_response() -> void:
	var resp: Dictionary = {
		"usage": {
			"input_tokens": 200,
			"output_tokens": 400,
		}
	}
	var usage: Dictionary = _provider._extract_token_usage(resp)
	assert_eq(usage["prompt_tokens"], 200, "input_tokens should map to prompt_tokens")
	assert_eq(usage["completion_tokens"], 400, "output_tokens should map to completion_tokens")


func test_extract_token_usage_missing_usage() -> void:
	var resp: Dictionary = {}
	var usage: Dictionary = _provider._extract_token_usage(resp)
	assert_eq(usage.size(), 0, "should return empty dict when no usage field")


func test_extract_content_from_valid_response() -> void:
	var resp: Dictionary = {
		"content": [
			{
				"type": "text",
				"text": '{"spec_version":"1.0.0"}',
			}
		]
	}
	var content: String = _provider._extract_content(resp)
	assert_eq(content, '{"spec_version":"1.0.0"}')


func test_extract_content_empty_content() -> void:
	var resp: Dictionary = {"content": []}
	var content: String = _provider._extract_content(resp)
	assert_eq(content, "", "should return empty string for empty content array")

# endregion
