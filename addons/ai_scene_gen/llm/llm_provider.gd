@tool
class_name LLMProvider
extends RefCounted

## Abstract base class for LLM providers.
## Subclasses override virtual methods to implement concrete providers (OpenAI, Anthropic, mock, etc.).

var _logger: RefCounted = null
var _http_node: HTTPRequest = null
var _api_key: String = ""


func _init(logger: RefCounted = null) -> void:
	_logger = logger


## Returns the provider display name.
## @return Provider identifier string.
func get_provider_name() -> String:
	return ""


## Returns list of available model identifiers for this provider.
## @return Array of model name strings.
func get_available_models() -> Array[String]:
	var result: Array[String] = []
	return result


## Whether the provider is properly configured (API keys, etc.).
## @return true if ready to send requests.
func is_configured() -> bool:
	return false


## Performs a health check on the provider (connectivity, auth, etc.).
## @return Dictionary with "status" and "message" keys.
func health_check() -> Dictionary:
	return {"status": "not_implemented", "message": "Provider does not implement health_check"}


## Whether this provider requires a configurable base URL.
func needs_base_url() -> bool:
	return false


## Returns the default base URL for this provider (empty if not applicable).
func get_default_base_url() -> String:
	return ""


## Sets the provider base URL. Override in subclasses that support it.
func set_base_url(_url: String) -> void:
	pass


## Whether this provider requires an API key.
func needs_api_key() -> bool:
	return false


## Sets the API key for providers that require one.
func set_api_key(key: String) -> void:
	_api_key = key


## Returns the stored API key.
func get_api_key() -> String:
	return _api_key


## Injects an HTTPRequest node owned by the plugin (RefCounted cannot own Nodes).
func set_http_node(node: HTTPRequest) -> void:
	_http_node = node


## Cancels any in-flight HTTP request. Override for custom cancel logic.
func cancel() -> void:
	if _http_node != null:
		_http_node.cancel_request()


## Fetches available models asynchronously (override for HTTP-based providers).
## Default implementation returns get_available_models() synchronously.
func fetch_available_models() -> Array[String]:
	return get_available_models()


## Sends a prompt to the LLM and returns the response.
## Subclasses may use await internally; callers should always await this method.
## @param compiled_prompt: Full prompt string to send.
## @param model: Model identifier.
## @param temperature: Sampling temperature (0.0–2.0).
## @param seed: Optional seed for determinism.
## @return LLMResponse (success or failure).
func send_request(_compiled_prompt: String, _model: String, _temperature: float, _seed: int) -> LLMResponse:
	return LLMResponse.create_failure("LLM_ERR_NOT_CONFIGURED", "Provider not implemented", 0)


## Logs a message via the configured logger.
## @param level: Log level (e.g. "info", "warning", "error").
## @param message: Message to log.
func _log(level: String, message: String) -> void:
	if _logger == null:
		return
	match level:
		"debug":
			_logger.log_debug("ai_scene_gen.llm", message)
		"info":
			_logger.log_info("ai_scene_gen.llm", message)
		"warning":
			_logger.log_warning("ai_scene_gen.llm", message)
		"error":
			_logger.log_error("ai_scene_gen.llm", message)
