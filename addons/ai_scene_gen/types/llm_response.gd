@tool
class_name LLMResponse
extends RefCounted

## Wraps an LLM provider response (success or failure).

var _success: bool = false
var _raw_body: String = ""
var _error_code: String = ""
var _error_message: String = ""
var _latency_ms: int = 0
var _token_usage: Dictionary = {}


## Creates a successful LLM response.
## @param raw_body: Raw response body from the provider.
## @param latency_ms: Request latency in milliseconds.
## @param token_usage: Dictionary with token usage stats.
## @return A configured LLMResponse instance.
static func create_success(raw_body: String, latency_ms: int, token_usage: Dictionary) -> LLMResponse:
	var r: LLMResponse = LLMResponse.new()
	r._success = true
	r._raw_body = raw_body
	r._latency_ms = latency_ms
	r._token_usage = token_usage
	return r


## Creates a failed LLM response.
## @param error_code: Provider-specific error code.
## @param error_message: Human-readable error message.
## @param latency_ms: Request latency in milliseconds.
## @return A configured LLMResponse instance.
static func create_failure(error_code: String, error_message: String, latency_ms: int) -> LLMResponse:
	var r: LLMResponse = LLMResponse.new()
	r._success = false
	r._error_code = error_code
	r._error_message = error_message
	r._latency_ms = latency_ms
	return r


func is_success() -> bool:
	return _success


func get_raw_body() -> String:
	return _raw_body


func get_error_code() -> String:
	return _error_code


func get_error_message() -> String:
	return _error_message


func get_latency_ms() -> int:
	return _latency_ms


func get_token_usage() -> Dictionary:
	return _token_usage
