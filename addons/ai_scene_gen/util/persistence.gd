@tool
class_name AiSceneGenPersistence
extends RefCounted

## Handles saving/loading of plugin settings, SceneSpec files, and model caches.

# region --- Constants ---

const SETTINGS_DIR: String = "res://addons/ai_scene_gen/"
const SETTINGS_FILE: String = "res://addons/ai_scene_gen/settings.json"
const CACHE_DIR: String = "res://addons/ai_scene_gen/cache/"
const ASSET_REGISTRY_FILE: String = "res://addons/ai_scene_gen/asset_tags.tres"

const DEFAULT_SETTINGS: Dictionary = {
	"selected_provider": "MockProvider",
	"selected_model": "mock-outdoor",
	"style_preset": "blockout",
	"seed": 42,
	"bounds_meters": [50.0, 30.0, 50.0],
	"max_nodes": 256,
	"telemetry_enabled": false
}

const LOG_CATEGORY: String = "ai_scene_gen.persistence"
const PERSIST_ERR_PATH: String = "Path '{path}' is outside the project directory."
const PERSIST_ERR_READ: String = "Could not load '{path}': {reason}."
const PERSIST_ERR_CORRUPT: String = "File '{path}' contains invalid JSON."
const PERSIST_ERR_VERSION: String = "SceneSpec version '{v}' is not supported by this plugin version."
const PERSIST_ERR_WRITE: String = "Could not save to '{path}': {reason}."

# endregion

# region --- Private ---

var _logger: RefCounted
var _cached_settings: Dictionary = {}
var _editor_interface: Object = null

# endregion

# region --- Constructor ---

func _init(logger: RefCounted = null) -> void:
	_logger = logger


# endregion

# region --- Public API ---

## Merges settings with defaults, writes to SETTINGS_FILE. Returns OK or ERR_FILE_CANT_WRITE.
func save_settings(settings: Dictionary) -> int:
	var merged: Dictionary = DEFAULT_SETTINGS.duplicate()
	for key in settings:
		if key in merged:
			merged[key] = settings[key]
	_ensure_dir(SETTINGS_DIR)
	var file: FileAccess = FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if file == null:
		var err: int = FileAccess.get_open_error()
		_log("WARNING", PERSIST_ERR_WRITE.format({"path": SETTINGS_FILE, "reason": str(err)}))
		return ERR_FILE_CANT_WRITE
	file.store_string(JSON.stringify(merged, "\t"))
	file.close()
	_cached_settings = merged
	_log("INFO", "settings_saved")
	return OK


## Loads settings from file. Returns DEFAULT_SETTINGS if file missing or corrupt.
func load_settings() -> Dictionary:
	if not FileAccess.file_exists(SETTINGS_FILE):
		var defaults: Dictionary = DEFAULT_SETTINGS.duplicate()
		_cached_settings = defaults
		return defaults
	var file: FileAccess = FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if file == null:
		var defaults: Dictionary = DEFAULT_SETTINGS.duplicate()
		_cached_settings = defaults
		return defaults
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if parsed == null:
		_log("WARNING", PERSIST_ERR_CORRUPT.format({"path": SETTINGS_FILE}))
		var defaults: Dictionary = DEFAULT_SETTINGS.duplicate()
		_cached_settings = defaults
		return defaults
	var loaded: Dictionary = parsed
	var merged: Dictionary = DEFAULT_SETTINGS.duplicate()
	for key in loaded:
		if key in merged:
			merged[key] = loaded[key]
	_cached_settings = merged
	return merged


## Exports spec dict to JSON file. Path must start with res://.
## Returns OK, ERR_INVALID_PARAMETER (bad path), or ERR_FILE_CANT_WRITE.
func export_spec(spec: Dictionary, path: String) -> int:
	if not path.begins_with("res://"):
		_log("WARNING", PERSIST_ERR_PATH.format({"path": path}))
		return ERR_INVALID_PARAMETER
	var dir_path: String = path.get_base_dir()
	_ensure_dir(dir_path)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var err: int = FileAccess.get_open_error()
		_log("WARNING", PERSIST_ERR_WRITE.format({"path": path, "reason": str(err)}))
		return ERR_FILE_CANT_WRITE
	file.store_string(JSON.stringify(spec, "\t"))
	file.close()
	_log("INFO", "spec_exported")
	return OK


## Imports spec dict from JSON file. Path must start with res://.
## Returns empty dict on error (path, missing file, corrupt JSON, unsupported version).
func import_spec(path: String) -> Dictionary:
	if not path.begins_with("res://"):
		_log("WARNING", PERSIST_ERR_PATH.format({"path": path}))
		return {}
	if not FileAccess.file_exists(path):
		_log("WARNING", PERSIST_ERR_READ.format({"path": path, "reason": "File does not exist"}))
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		var err: int = FileAccess.get_open_error()
		_log("WARNING", PERSIST_ERR_READ.format({"path": path, "reason": str(err)}))
		return {}
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if parsed == null:
		_log("WARNING", PERSIST_ERR_CORRUPT.format({"path": path}))
		return {}
	var data: Dictionary = parsed
	if data.has("spec_version"):
		var ver: Variant = data["spec_version"]
		if str(ver) != "1.0.0":
			_log("WARNING", PERSIST_ERR_VERSION.format({"v": str(ver)}))
			return {}
	return data


## Saves model list for provider to cache. Overwrites existing cache.
func save_model_cache(provider: String, models: Array[String]) -> void:
	_ensure_dir(CACHE_DIR)
	var cache_path: String = CACHE_DIR + "models_" + provider + ".json"
	var payload: Dictionary = {
		"models": models.duplicate(),
		"timestamp": int(Time.get_unix_time_from_system())
	}
	var file: FileAccess = FileAccess.open(cache_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "\t"))
		file.close()


## Loads cached model list for provider. Returns [] if missing or older than max_age_seconds.
func load_model_cache(provider: String, max_age_seconds: float = 3600.0) -> Array[String]:
	var cache_path: String = CACHE_DIR + "models_" + provider + ".json"
	if not FileAccess.file_exists(cache_path):
		return []
	var file: FileAccess = FileAccess.open(cache_path, FileAccess.READ)
	if file == null:
		return []
	var content: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(content)
	if parsed == null:
		return []
	var data: Dictionary = parsed
	var ts: Variant = data.get("timestamp", 0)
	var age: float = Time.get_unix_time_from_system() - float(ts)
	if age > max_age_seconds:
		return []
	var raw_models: Variant = data.get("models", [])
	var result: Array[String] = []
	for item in raw_models:
		result.append(str(item))
	return result


## Returns path to settings file.
func get_settings_path() -> String:
	return SETTINGS_FILE


## Returns API key for provider from EditorSettings. Returns "" if EditorInterface unavailable.
## Call set_editor_interface() from the plugin to enable API key storage.
func get_api_key(provider: String) -> String:
	if _editor_interface == null:
		return ""
	var settings: EditorSettings = _editor_interface.get_editor_settings()
	if settings == null:
		return ""
	var key_name: String = "ai_scene_gen/api_keys/" + provider
	if not settings.has_setting(key_name):
		return ""
	return str(settings.get_setting(key_name))


## Stores API key for provider in EditorSettings. No-op if EditorInterface unavailable.
func set_api_key(provider: String, key: String) -> void:
	if _editor_interface == null:
		return
	var settings: EditorSettings = _editor_interface.get_editor_settings()
	if settings == null:
		return
	var key_name: String = "ai_scene_gen/api_keys/" + provider
	settings.set_setting(key_name, key)


## Returns stored provider URL from EditorSettings. Returns "" if unset.
func get_provider_url(provider: String) -> String:
	if _editor_interface == null:
		return ""
	var settings: EditorSettings = _editor_interface.get_editor_settings()
	if settings == null:
		return ""
	var key_name: String = "ai_scene_gen/provider_urls/" + provider
	if not settings.has_setting(key_name):
		return ""
	return str(settings.get_setting(key_name))


## Stores provider URL in EditorSettings. No-op if EditorInterface unavailable.
func set_provider_url(provider: String, url: String) -> void:
	if _editor_interface == null:
		return
	var settings: EditorSettings = _editor_interface.get_editor_settings()
	if settings == null:
		return
	var key_name: String = "ai_scene_gen/provider_urls/" + provider
	settings.set_setting(key_name, url)


## Injects EditorInterface for API key get/set. Call from plugin after construction.
func set_editor_interface(editor_interface: Object) -> void:
	_editor_interface = editor_interface


# endregion

# region --- Private Helpers ---

func _log(level: String, message: String) -> void:
	if _logger == null:
		return
	if level == "INFO":
		_logger.log_info(LOG_CATEGORY, message)
	elif level == "WARNING":
		_logger.log_warning(LOG_CATEGORY, message)
	elif level == "ERROR":
		_logger.log_error(LOG_CATEGORY, message)
	else:
		_logger.log_debug(LOG_CATEGORY, message)


func _ensure_dir(dir_path: String) -> void:
	if DirAccess.dir_exists_absolute(dir_path):
		return
	DirAccess.make_dir_recursive_absolute(dir_path)


# endregion
