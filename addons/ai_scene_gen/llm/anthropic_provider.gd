@tool
class_name AnthropicProvider
extends LLMProvider

## LLM provider for Anthropic Messages API (https://api.anthropic.com/v1).
## Supports Claude model family.

const API_BASE_URL: String = "https://api.anthropic.com"
const MESSAGES_ENDPOINT: String = "/v1/messages"
const MODELS_ENDPOINT: String = "/v1/models"
const ANTHROPIC_VERSION: String = "2023-06-01"
const DEFAULT_MODELS: Array[String] = [
	"claude-sonnet-4-20250514",
	"claude-opus-4-20250514",
	"claude-haiku-3-5-20241022",
]
const MAX_TOKENS: int = 4096

var _cached_models: Array[String] = []


func _init(logger: RefCounted = null) -> void:
	super._init(logger)
	_cached_models = DEFAULT_MODELS.duplicate()


func get_provider_name() -> String:
	return "Anthropic"


func get_available_models() -> Array[String]:
	return _cached_models.duplicate()


func is_configured() -> bool:
	return _http_node != null and not _api_key.is_empty()


func needs_api_key() -> bool:
	return true


func needs_base_url() -> bool:
	return false


func health_check() -> Dictionary:
	if _http_node == null:
		return {"status": "error", "message": "No HTTP node configured"}
	if _api_key.is_empty():
		return {"status": "error", "message": "No API key configured"}
	return {"status": "unknown", "message": "Use send_request() for connectivity check"}


## Fetches available models from Anthropic's /v1/models endpoint.
## Filters to claude models. Falls back to cached/default on failure.
func fetch_available_models() -> Array[String]:
	if _http_node == null or _api_key.is_empty():
		return _cached_models.duplicate()

	if _http_node.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_log("warning", "fetch_models skipped: HTTPRequest busy")
		return _cached_models.duplicate()

	var url: String = API_BASE_URL + MODELS_ENDPOINT
	var headers: Array[String] = [
		"x-api-key: %s" % _api_key,
		"anthropic-version: %s" % ANTHROPIC_VERSION,
		"Accept: application/json",
	]

	var err: int = _http_node.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_log("warning", "fetch_models request() failed: %d" % err)
		return _cached_models.duplicate()

	var result: Array = await _http_node.request_completed
	var http_result: int = result[0] as int
	var response_code: int = result[1] as int
	var body: PackedByteArray = result[3] as PackedByteArray

	if http_result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_log("warning", "fetch_models failed: http_result=%d, code=%d" % [http_result, response_code])
		return _cached_models.duplicate()

	var body_text: String = body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)
	if parsed == null or not (parsed is Dictionary):
		_log("warning", "fetch_models: invalid JSON response")
		return _cached_models.duplicate()

	var data: Dictionary = parsed as Dictionary
	var models_raw: Variant = data.get("data", [])
	if not (models_raw is Array):
		return _cached_models.duplicate()

	var models: Array[String] = []
	for entry: Variant in models_raw as Array:
		if entry is Dictionary:
			var model_id: String = str((entry as Dictionary).get("id", ""))
			if model_id.begins_with("claude-"):
				models.append(model_id)

	if models.is_empty():
		return _cached_models.duplicate()

	_cached_models = models.duplicate()
	_log("info", "fetched %d Claude model(s) from Anthropic" % models.size())
	return _cached_models.duplicate()


## Sends a prompt to Anthropic Messages API (async).
func send_request(compiled_prompt: String, model: String, temperature: float, seed: int) -> LLMResponse:
	if _http_node == null:
		return LLMResponse.create_failure(
			"LLM_ERR_NOT_CONFIGURED",
			"No HTTP node configured for Anthropic provider",
			0,
		)

	if model.is_empty():
		return LLMResponse.create_failure(
			"LLM_ERR_NOT_CONFIGURED",
			"No model specified for Anthropic request",
			0,
		)

	if _api_key.is_empty():
		return LLMResponse.create_failure(
			"LLM_ERR_AUTH",
			"No API key configured for Anthropic provider",
			0,
		)

	var messages: Array[Dictionary] = [
		{"role": "user", "content": "Generate the SceneSpec JSON now."},
	]

	var request_body: Dictionary = {
		"model": model,
		"max_tokens": MAX_TOKENS,
		"system": compiled_prompt,
		"messages": messages,
		"temperature": temperature,
	}

	# Anthropic API does not have a native seed param; we include it in metadata for traceability
	if seed != 0:
		request_body["metadata"] = {"user_id": "seed_%d" % seed}

	var json_body: String = JSON.stringify(request_body)
	var headers: Array[String] = [
		"Content-Type: application/json",
		"x-api-key: %s" % _api_key,
		"anthropic-version: %s" % ANTHROPIC_VERSION,
	]
	var url: String = API_BASE_URL + MESSAGES_ENDPOINT

	_log("info", "request -> %s (model=%s, prompt_len=%d)" % [url, model, compiled_prompt.length()])
	var start_ms: int = Time.get_ticks_msec()

	var err: int = _http_node.request(url, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		var elapsed: int = Time.get_ticks_msec() - start_ms
		return LLMResponse.create_failure(
			"LLM_ERR_NETWORK",
			"HTTPRequest.request() failed (error=%d)" % err,
			elapsed,
		)

	var result: Array = await _http_node.request_completed
	var elapsed: int = Time.get_ticks_msec() - start_ms

	var http_result: int = result[0] as int
	var response_code: int = result[1] as int
	var body: PackedByteArray = result[3] as PackedByteArray

	if http_result != HTTPRequest.RESULT_SUCCESS:
		return _map_http_result_error(http_result, elapsed)

	var body_text: String = body.get_string_from_utf8()

	if response_code == 401 or response_code == 403:
		return LLMResponse.create_failure("LLM_ERR_AUTH", "Authentication failed (%d)" % response_code, elapsed)
	if response_code == 429:
		return LLMResponse.create_failure("LLM_ERR_RATE_LIMIT", "Rate limited by Anthropic", elapsed)
	if response_code >= 500:
		return LLMResponse.create_failure("LLM_ERR_SERVER", "Server error (%d): %s" % [response_code, body_text.left(200)], elapsed)
	if response_code != 200:
		return LLMResponse.create_failure("LLM_ERR_NETWORK", "Unexpected HTTP %d: %s" % [response_code, body_text.left(200)], elapsed)

	var parsed: Variant = JSON.parse_string(body_text)
	if parsed == null or not (parsed is Dictionary):
		return LLMResponse.create_failure("LLM_ERR_NON_JSON", "Non-JSON response: %s" % body_text.left(200), elapsed)

	var resp: Dictionary = parsed as Dictionary
	var generated_text: String = _extract_content(resp)

	if generated_text.is_empty():
		return LLMResponse.create_failure("LLM_ERR_NON_JSON", "Empty content in Anthropic response", elapsed)

	var token_usage: Dictionary = _extract_token_usage(resp)

	_log("info", "response <- elapsed=%dms tokens=%s" % [elapsed, str(token_usage)])
	return LLMResponse.create_success(generated_text, elapsed, token_usage)


## Extracts the text content from Anthropic Messages response.
## Anthropic returns content as an array of content blocks.
func _extract_content(resp: Dictionary) -> String:
	var content: Variant = resp.get("content", [])
	if not (content is Array):
		return ""
	var content_arr: Array = content as Array
	if content_arr.is_empty():
		return ""
	var text_parts: String = ""
	for block: Variant in content_arr:
		if block is Dictionary:
			var block_dict: Dictionary = block as Dictionary
			if block_dict.get("type", "") == "text":
				text_parts += str(block_dict.get("text", ""))
	return text_parts


## Extracts token usage from the response["usage"] field.
func _extract_token_usage(resp: Dictionary) -> Dictionary:
	var usage: Variant = resp.get("usage")
	if usage == null or not (usage is Dictionary):
		return {}
	var u: Dictionary = usage as Dictionary
	var result: Dictionary = {}
	if u.has("input_tokens"):
		result["prompt_tokens"] = u["input_tokens"]
	if u.has("output_tokens"):
		result["completion_tokens"] = u["output_tokens"]
	return result


func _map_http_result_error(http_result: int, elapsed_ms: int) -> LLMResponse:
	match http_result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return LLMResponse.create_failure("LLM_ERR_NETWORK", "Cannot connect to Anthropic API", elapsed_ms)
		HTTPRequest.RESULT_CANT_RESOLVE:
			return LLMResponse.create_failure("LLM_ERR_NETWORK", "Cannot resolve api.anthropic.com", elapsed_ms)
		HTTPRequest.RESULT_TIMEOUT:
			return LLMResponse.create_failure("LLM_ERR_TIMEOUT", "Request timed out", elapsed_ms)
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return LLMResponse.create_failure("LLM_ERR_NETWORK", "Connection error to Anthropic API", elapsed_ms)
		_:
			return LLMResponse.create_failure("LLM_ERR_NETWORK", "HTTP request failed (result=%d)" % http_result, elapsed_ms)
