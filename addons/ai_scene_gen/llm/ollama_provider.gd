@tool
class_name OllamaProvider
extends LLMProvider

## LLM provider for local Ollama instances (http://localhost:11434).
## Bearer-token-free, async HTTP via injected HTTPRequest node.

const DEFAULT_BASE_URL: String = "http://localhost:11434"
const GENERATE_ENDPOINT: String = "/api/generate"
const TAGS_ENDPOINT: String = "/api/tags"
const DEFAULT_MODELS: Array[String] = ["llama3:latest", "codellama:latest", "mistral:latest"]

var _base_url: String = DEFAULT_BASE_URL
var _cached_models: Array[String] = []


func _init(logger: RefCounted = null) -> void:
	super._init(logger)
	_cached_models = DEFAULT_MODELS.duplicate()


func get_provider_name() -> String:
	return "Ollama"


func get_available_models() -> Array[String]:
	return _cached_models.duplicate()


func is_configured() -> bool:
	return _http_node != null


func needs_api_key() -> bool:
	return false


func needs_base_url() -> bool:
	return true


func get_default_base_url() -> String:
	return DEFAULT_BASE_URL


func health_check() -> Dictionary:
	if _http_node == null:
		return {"status": "error", "message": "No HTTP node configured"}
	return {"status": "unknown", "message": "Use fetch_available_models() for async connectivity check"}


## Sets the Ollama base URL (e.g. "http://192.168.1.50:11434").
func set_base_url(url: String) -> void:
	_base_url = url


## Fetches available models from Ollama's /api/tags endpoint.
## Falls back to cached/default models on failure.
func fetch_available_models() -> Array[String]:
	if _http_node == null:
		return _cached_models.duplicate()

	if _http_node.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_log("warning", "fetch_models skipped: HTTPRequest busy")
		return _cached_models.duplicate()

	var url: String = _base_url + TAGS_ENDPOINT
	var headers: Array[String] = ["Accept: application/json"]

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
	var models_raw: Variant = data.get("models", [])
	if not (models_raw is Array):
		return _cached_models.duplicate()

	var models: Array[String] = []
	for entry: Variant in models_raw as Array:
		if entry is Dictionary:
			var name_val: String = str((entry as Dictionary).get("name", ""))
			if not name_val.is_empty():
				models.append(name_val)

	if models.is_empty():
		return _cached_models.duplicate()

	_cached_models = models.duplicate()
	_log("info", "fetched %d model(s) from Ollama" % models.size())
	return _cached_models.duplicate()


## Sends a prompt to Ollama's /api/generate endpoint (async, non-streaming).
func send_request(compiled_prompt: String, model: String, temperature: float, seed: int) -> LLMResponse:
	if _http_node == null:
		return LLMResponse.create_failure(
			"LLM_ERR_NOT_CONFIGURED",
			"No HTTP node configured for Ollama provider",
			0,
		)

	if model.is_empty():
		return LLMResponse.create_failure(
			"LLM_ERR_NOT_CONFIGURED",
			"No model specified for Ollama request",
			0,
		)

	var request_body: Dictionary = {
		"model": model,
		"prompt": compiled_prompt,
		"stream": false,
		"format": "json",
		"options": {
			"temperature": temperature,
			"seed": seed,
		},
	}

	var json_body: String = JSON.stringify(request_body)
	var headers: Array[String] = ["Content-Type: application/json"]
	var url: String = _base_url + GENERATE_ENDPOINT

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
		return LLMResponse.create_failure("LLM_ERR_RATE_LIMIT", "Rate limited by provider", elapsed)
	if response_code >= 500:
		return LLMResponse.create_failure("LLM_ERR_SERVER", "Server error (%d): %s" % [response_code, body_text.left(200)], elapsed)
	if response_code != 200:
		return LLMResponse.create_failure("LLM_ERR_NETWORK", "Unexpected HTTP %d: %s" % [response_code, body_text.left(200)], elapsed)

	var parsed: Variant = JSON.parse_string(body_text)
	if parsed == null or not (parsed is Dictionary):
		return LLMResponse.create_failure("LLM_ERR_NON_JSON", "Non-JSON response: %s" % body_text.left(200), elapsed)

	var ollama_resp: Dictionary = parsed as Dictionary
	var generated_text: String = str(ollama_resp.get("response", ""))

	if generated_text.is_empty():
		return LLMResponse.create_failure("LLM_ERR_NON_JSON", "Empty 'response' field in Ollama reply", elapsed)

	var token_usage: Dictionary = {}
	if ollama_resp.has("prompt_eval_count"):
		token_usage["prompt_tokens"] = ollama_resp["prompt_eval_count"]
	if ollama_resp.has("eval_count"):
		token_usage["completion_tokens"] = ollama_resp["eval_count"]

	_log("info", "response <- elapsed=%dms tokens=%s" % [elapsed, str(token_usage)])
	return LLMResponse.create_success(generated_text, elapsed, token_usage)


func _map_http_result_error(http_result: int, elapsed_ms: int) -> LLMResponse:
	match http_result:
		HTTPRequest.RESULT_CANT_CONNECT:
			return LLMResponse.create_failure("LLM_ERR_NETWORK", "Cannot connect to Ollama at %s" % _base_url, elapsed_ms)
		HTTPRequest.RESULT_CANT_RESOLVE:
			return LLMResponse.create_failure("LLM_ERR_NETWORK", "Cannot resolve hostname for Ollama", elapsed_ms)
		HTTPRequest.RESULT_TIMEOUT:
			return LLMResponse.create_failure("LLM_ERR_TIMEOUT", "Request timed out", elapsed_ms)
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return LLMResponse.create_failure("LLM_ERR_NETWORK", "Connection error to Ollama", elapsed_ms)
		_:
			return LLMResponse.create_failure("LLM_ERR_NETWORK", "HTTP request failed (result=%d)" % http_result, elapsed_ms)
