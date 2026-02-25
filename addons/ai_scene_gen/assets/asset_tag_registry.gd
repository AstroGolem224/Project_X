@tool
class_name AssetTagRegistry
extends Resource

## Resource that maps string tags to res:// resource paths and metadata.
## Can be saved as .tres and loaded back.

const ASSET_ERR_PATH_INVALID: String = "ASSET_ERR_PATH_INVALID"
const LOG_CATEGORY: String = "ai_scene_gen.asset_resolver"

@export var _entries: Dictionary = {}

var _logger: RefCounted = null


## Sets the logger used for diagnostic output.
## @param logger: RefCounted with log_debug, log_info, log_warning, log_error methods.
func set_logger(logger: RefCounted) -> void:
	_logger = logger


## Registers a tag with resource path and optional metadata.
## @param tag: Tag identifier (must not be empty).
## @param res_path: Godot resource path (must start with res://).
## @param metadata: Optional dict with resource_type, thumbnail_path, estimated_triangles, tags_secondary, fallback.
## @return: OK on success, ERR_INVALID_PARAMETER if validation fails.
func register_tag(tag: String, res_path: String, metadata: Dictionary = {}) -> int:
	if tag.is_empty():
		_log("warning", "register_tag: tag cannot be empty")
		return ERR_INVALID_PARAMETER
	if not res_path.begins_with("res://"):
		_log("error", "[%s] resource_path must start with res://, got '%s'" % [ASSET_ERR_PATH_INVALID, res_path])
		return ERR_INVALID_PARAMETER

	var entry: Dictionary = _build_entry(tag, res_path, metadata)
	_entries[tag] = entry
	return OK


## Removes the tag from the registry if it exists.
## @param tag: Tag to unregister.
func unregister_tag(tag: String) -> void:
	if tag in _entries:
		_entries.erase(tag)


## Returns true if the tag is registered.
## @param tag: Tag to check.
## @return: True if tag exists in _entries.
func has_tag(tag: String) -> bool:
	return tag in _entries


## Returns the entry dictionary for the given tag.
## @param tag: Tag to look up.
## @return: Entry dict or empty dict if not found.
func get_entry(tag: String) -> Dictionary:
	return _entries.get(tag, {})


## Returns all registered tags sorted alphabetically.
## @return: Array of tag strings.
func get_all_tags() -> Array[String]:
	var keys: Array[String] = []
	for k in _entries.keys():
		keys.append(str(k))
	keys.sort()
	return keys


## Returns the number of registered entries.
## @return: Entry count.
func get_entry_count() -> int:
	return _entries.size()


## Saves this registry to a .tres file.
## @param path: Godot resource path (must start with res://).
## @return: OK on success, ERR_INVALID_PARAMETER if path invalid, or ResourceSaver error.
func save_to_file(path: String) -> int:
	if not path.begins_with("res://"):
		_log("error", "[%s] save path must start with res://, got '%s'" % [ASSET_ERR_PATH_INVALID, path])
		return ERR_INVALID_PARAMETER

	var err: Error = ResourceSaver.save(self, path)
	if err != OK:
		_log("error", "save_to_file failed: %s" % error_string(err))
	else:
		_log("info", "saved registry to %s (%d entries)" % [path, _entries.size()])
	return int(err)


## Loads entries from a registry .tres file and merges into this instance.
## @param path: Godot resource path (must start with res://).
## @return: OK on success, ERR_INVALID_PARAMETER if path invalid, or ResourceLoader error.
func load_from_file(path: String) -> int:
	if not path.begins_with("res://"):
		_log("error", "[%s] load path must start with res://, got '%s'" % [ASSET_ERR_PATH_INVALID, path])
		return ERR_INVALID_PARAMETER

	var res: Resource = ResourceLoader.load(path) as Resource
	if res == null:
		_log("error", "load_from_file failed: could not load resource at '%s'" % path)
		return ERR_CANT_OPEN

	if res is AssetTagRegistry:
		var other: AssetTagRegistry = res as AssetTagRegistry
		_entries = other._entries.duplicate(true)
		_log("info", "loaded registry from %s (%d entries)" % [path, _entries.size()])
		return OK

	_log("error", "load_from_file: resource at '%s' is not AssetTagRegistry" % path)
	return ERR_INVALID_PARAMETER


## Clears all registered entries.
func clear() -> void:
	_entries.clear()


func _log(level: String, message: String) -> void:
	if _logger == null:
		return
	if level == "debug" and _logger.has_method("log_debug"):
		_logger.log_debug(LOG_CATEGORY, message)
	elif level == "info" and _logger.has_method("log_info"):
		_logger.log_info(LOG_CATEGORY, message)
	elif level == "warning" and _logger.has_method("log_warning"):
		_logger.log_warning(LOG_CATEGORY, message)
	elif (level == "error" or level == "err") and _logger.has_method("log_error"):
		_logger.log_error(LOG_CATEGORY, message)


func _build_entry(tag: String, res_path: String, metadata: Dictionary) -> Dictionary:
	var entry: Dictionary = {
		"tag": tag,
		"resource_path": res_path,
		"resource_type": metadata.get("resource_type", "PackedScene"),
		"thumbnail_path": metadata.get("thumbnail_path", ""),
		"estimated_triangles": metadata.get("estimated_triangles", 0),
		"tags_secondary": metadata.get("tags_secondary", [])
	}
	var fallback: Variant = metadata.get("fallback", null)
	if fallback != null and fallback is Dictionary:
		entry["fallback"] = (fallback as Dictionary).duplicate(true)
	else:
		entry["fallback"] = {}
	return entry
