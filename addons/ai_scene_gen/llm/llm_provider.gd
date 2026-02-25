@tool
class_name LLMProvider
extends RefCounted

## Abstract base class for LLM providers.

const _LLMResponseScript: GDScript = preload("res://addons/ai_scene_gen/types/llm_response.gd")
## Subclasses override virtual methods to implement concrete providers (OpenAI, Anthropic, mock, etc.).

var _logger: RefCounted = null


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


## Sends a prompt to the LLM and returns the response.
## @param compiled_prompt: Full prompt string to send.
## @param model: Model identifier.
## @param temperature: Sampling temperature (0.0–2.0).
## @param seed: Optional seed for determinism.
## @return LLMResponse (success or failure).
func send_request(_compiled_prompt: String, _model: String, _temperature: float, _seed: int) -> LLMResponse:
	return _LLMResponseScript.create_failure("LLM_ERR_NOT_CONFIGURED", "Provider not implemented", 0) as LLMResponse


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
