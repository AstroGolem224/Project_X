@tool
class_name MockProvider
extends LLMProvider

## Mock LLM provider that returns canned SceneSpec JSON from files.

## Use for testing and development without API keys.

const _mock_dir: String = "res://addons/ai_scene_gen/mocks/"
var _available_mocks: Dictionary = {}
var _default_mock: String = "outdoor_clearing"


func _init(logger: RefCounted = null) -> void:
	super._init(logger)
	_load_mocks()


## Returns the mock provider name.
func get_provider_name() -> String:
	return "MockProvider"


## Returns available mock model identifiers.
func get_available_models() -> Array[String]:
	var models: Array[String] = ["mock-outdoor", "mock-interior"]
	return models


## Mock is always configured.
func is_configured() -> bool:
	return true


## Mock provider is always available.
func health_check() -> Dictionary:
	return {"status": "ok", "message": "Mock provider always available"}


## Returns canned SceneSpec JSON based on model name.
## @param compiled_prompt: Ignored for mock.
## @param model: "mock-interior" -> interior_room, else -> outdoor_clearing.
## @param temperature: Ignored.
## @param seed: Ignored.
## @return LLMResponse with JSON body or failure.
func send_request(_compiled_prompt: String, model: String, _temperature: float, _seed: int) -> LLMResponse:
	var mock_key: String = "outdoor_clearing"
	if model == "mock-interior":
		mock_key = "interior_room"

	var json_content: Variant = _available_mocks.get(mock_key)
	if json_content == null or not (json_content is String):
		return LLMResponse.create_failure("LLM_ERR_NOT_CONFIGURED", "Mock file not found", 0)

	var token_usage: Dictionary = {"prompt_tokens": 500, "completion_tokens": 1000}
	return LLMResponse.create_success(json_content as String, 50, token_usage)


func _load_mocks() -> void:
	var dir: DirAccess = DirAccess.open(_mock_dir)
	if dir == null:
		_log("warning", "Mock dir not found: %s" % _mock_dir)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".scenespec.json"):
			var path: String = _mock_dir.path_join(file_name)
			var file: FileAccess = FileAccess.open(path, FileAccess.READ)
			if file != null:
				var content: String = file.get_as_text()
				file.close()
				var key: String = file_name.get_basename().replace(".scenespec", "")
				_available_mocks[key] = content
		file_name = dir.get_next()
	dir.list_dir_end()

	if Engine.is_editor_hint():
		_log("info", "Loaded %d mock(s) from %s" % [_available_mocks.size(), _mock_dir])
