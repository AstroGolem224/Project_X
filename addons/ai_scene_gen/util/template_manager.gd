@tool
class_name SceneTemplateManager
extends RefCounted

## Manages built-in and custom scene templates.
## Built-in templates are created from constant definitions.
## Custom templates are persisted as .tres files under CUSTOM_DIR.

const CUSTOM_DIR: String = "res://addons/ai_scene_gen/templates/custom/"
const LOG_CATEGORY: String = "ai_scene_gen.template_manager"

var _logger: RefCounted = null
var _builtin_templates: Array[SceneTemplate] = []
var _custom_templates: Array[SceneTemplate] = []


func _init(logger: RefCounted = null) -> void:
	_logger = logger
	_init_builtin_templates()
	_load_custom_templates()


## Returns all templates (built-in first, then custom) sorted by name.
func get_all_templates() -> Array[SceneTemplate]:
	var all: Array[SceneTemplate] = []
	for t: SceneTemplate in _builtin_templates:
		all.append(t)
	for t: SceneTemplate in _custom_templates:
		all.append(t)
	return all


## Returns all template names in display order.
func get_template_names() -> Array[String]:
	var names: Array[String] = []
	for t: SceneTemplate in _builtin_templates:
		names.append(t.template_name)
	for t: SceneTemplate in _custom_templates:
		names.append(t.template_name)
	return names


## Returns a template by name, or null if not found.
func get_template(name: String) -> SceneTemplate:
	for t: SceneTemplate in _builtin_templates:
		if t.template_name == name:
			return t
	for t: SceneTemplate in _custom_templates:
		if t.template_name == name:
			return t
	return null


## Returns true if the template with the given name is a built-in.
func is_builtin(name: String) -> bool:
	for t: SceneTemplate in _builtin_templates:
		if t.template_name == name:
			return true
	return false


## Saves a new custom template. Returns OK on success.
## Overwrites if a custom template with the same name exists.
func save_custom_template(template: SceneTemplate) -> int:
	if template.template_name.is_empty():
		_log("warning", "save_custom_template: name cannot be empty")
		return ERR_INVALID_PARAMETER

	template.is_builtin = false
	_ensure_dir(CUSTOM_DIR)

	var file_name: String = _sanitize_filename(template.template_name)
	var path: String = CUSTOM_DIR + file_name + ".tres"

	var err: Error = ResourceSaver.save(template, path)
	if err != OK:
		_log("error", "save_custom_template failed for '%s': %s" % [template.template_name, error_string(err)])
		return int(err)

	_remove_custom_by_name(template.template_name)
	_custom_templates.append(template)
	_log("info", "saved custom template '%s' to %s" % [template.template_name, path])
	return OK


## Deletes a custom template by name. Built-in templates cannot be deleted.
## Returns OK on success, ERR_DOES_NOT_EXIST if not found, ERR_UNAUTHORIZED for built-in.
func delete_custom_template(name: String) -> int:
	if is_builtin(name):
		_log("warning", "delete_custom_template: cannot delete built-in '%s'" % name)
		return ERR_UNAUTHORIZED

	var found: bool = false
	for i: int in range(_custom_templates.size()):
		if _custom_templates[i].template_name == name:
			var file_name: String = _sanitize_filename(name)
			var path: String = CUSTOM_DIR + file_name + ".tres"
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
			_custom_templates.remove_at(i)
			found = true
			_log("info", "deleted custom template '%s'" % name)
			break

	if not found:
		_log("warning", "delete_custom_template: '%s' not found" % name)
		return ERR_DOES_NOT_EXIST
	return OK


## Exports a template to a .tres file at the given path.
func export_template(name: String, path: String) -> int:
	if not path.begins_with("res://"):
		_log("warning", "export_template: path must start with res://, got '%s'" % path)
		return ERR_INVALID_PARAMETER

	var template: SceneTemplate = get_template(name)
	if template == null:
		_log("warning", "export_template: template '%s' not found" % name)
		return ERR_DOES_NOT_EXIST

	var copy: SceneTemplate = template.duplicate_template()
	var err: Error = ResourceSaver.save(copy, path)
	if err != OK:
		_log("error", "export_template failed: %s" % error_string(err))
		return int(err)

	_log("info", "exported template '%s' to %s" % [name, path])
	return OK


## Imports a template from a .tres file and adds it as custom.
func import_template(path: String) -> int:
	if not path.begins_with("res://"):
		_log("warning", "import_template: path must start with res://, got '%s'" % path)
		return ERR_INVALID_PARAMETER

	var res: Resource = ResourceLoader.load(path)
	if res == null or not (res is SceneTemplate):
		_log("error", "import_template: could not load SceneTemplate from '%s'" % path)
		return ERR_CANT_OPEN

	var template: SceneTemplate = res as SceneTemplate
	template.is_builtin = false

	if template.template_name.is_empty():
		var base: String = path.get_file().get_basename()
		template.template_name = base

	return save_custom_template(template)


## Returns the number of built-in templates.
func get_builtin_count() -> int:
	return _builtin_templates.size()


## Returns the number of custom templates.
func get_custom_count() -> int:
	return _custom_templates.size()


# --- Private ---


func _init_builtin_templates() -> void:
	_builtin_templates.clear()

	var outdoor: SceneTemplate = SceneTemplate.new()
	outdoor.template_name = "Outdoor Clearing"
	outdoor.description = "A natural forest clearing with trees, rocks, and a dirt path."
	outdoor.prompt = "A forest clearing with an oak tree, mossy boulder, and a winding dirt path. Soft sunlight from above. Grass ground."
	outdoor.style_preset = "blockout"
	outdoor.two_stage = false
	outdoor.seed_value = 42
	outdoor.bounds_x = 40.0
	outdoor.bounds_y = 20.0
	outdoor.bounds_z = 40.0
	outdoor.is_builtin = true
	_builtin_templates.append(outdoor)

	var interior: SceneTemplate = SceneTemplate.new()
	interior.template_name = "Interior Room"
	interior.description = "A simple rectangular room with walls, floor, and a table."
	interior.prompt = "A rectangular room with four walls, a wooden floor, and a table in the center. Warm ambient lighting."
	interior.style_preset = "blockout"
	interior.two_stage = false
	interior.seed_value = 100
	interior.bounds_x = 10.0
	interior.bounds_y = 4.0
	interior.bounds_z = 10.0
	interior.is_builtin = true
	_builtin_templates.append(interior)

	var dungeon: SceneTemplate = SceneTemplate.new()
	dungeon.template_name = "Dungeon Corridor"
	dungeon.description = "A narrow stone corridor with torches and arched ceiling."
	dungeon.prompt = "A dark stone dungeon corridor, narrow with arched ceiling. Wall-mounted torches on both sides. Cobblestone floor. Mysterious atmosphere."
	dungeon.style_preset = "stylized"
	dungeon.two_stage = true
	dungeon.seed_value = 666
	dungeon.bounds_x = 6.0
	dungeon.bounds_y = 5.0
	dungeon.bounds_z = 30.0
	dungeon.is_builtin = true
	_builtin_templates.append(dungeon)


func _load_custom_templates() -> void:
	_custom_templates.clear()
	if not DirAccess.dir_exists_absolute(CUSTOM_DIR):
		return

	var dir: DirAccess = DirAccess.open(CUSTOM_DIR)
	if dir == null:
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			var path: String = CUSTOM_DIR + file_name
			var res: Resource = ResourceLoader.load(path)
			if res != null and res is SceneTemplate:
				var template: SceneTemplate = res as SceneTemplate
				template.is_builtin = false
				_custom_templates.append(template)
				_log("debug", "loaded custom template '%s' from %s" % [template.template_name, path])
		file_name = dir.get_next()
	dir.list_dir_end()


func _remove_custom_by_name(name: String) -> void:
	for i: int in range(_custom_templates.size()):
		if _custom_templates[i].template_name == name:
			_custom_templates.remove_at(i)
			return


func _sanitize_filename(name: String) -> String:
	var safe: String = name.to_lower().replace(" ", "_")
	var result: String = ""
	for i: int in range(safe.length()):
		var c: String = safe[i]
		if c.is_valid_identifier() or c == "_":
			result += c
	if result.is_empty():
		result = "template"
	return result


func _ensure_dir(dir_path: String) -> void:
	if DirAccess.dir_exists_absolute(dir_path):
		return
	DirAccess.make_dir_recursive_absolute(dir_path)


func _log(level: String, message: String) -> void:
	if _logger == null:
		return
	match level:
		"debug":
			_logger.log_debug(LOG_CATEGORY, message)
		"info":
			_logger.log_info(LOG_CATEGORY, message)
		"warning":
			_logger.log_warning(LOG_CATEGORY, message)
		"error":
			_logger.log_error(LOG_CATEGORY, message)
