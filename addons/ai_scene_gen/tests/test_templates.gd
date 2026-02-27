@tool
extends GutTest

## GUT tests for Scene Templates / Presets (Prio 15).
## Covers: SceneTemplate Resource, TemplateManager (built-in + custom CRUD,
## import/export), Dock template UI integration.

var _dock: AiSceneGenDock
var _manager: SceneTemplateManager


func before_each() -> void:
	_dock = AiSceneGenDock.new()
	add_child(_dock)
	_manager = SceneTemplateManager.new(null)


func after_each() -> void:
	if is_instance_valid(_dock):
		remove_child(_dock)
		_dock.queue_free()
	_cleanup_custom_dir()


# region --- SceneTemplate Resource ---

func test_scene_template_defaults() -> void:
	var t: SceneTemplate = SceneTemplate.new()
	assert_eq(t.template_name, "", "default name should be empty")
	assert_eq(t.prompt, "", "default prompt should be empty")
	assert_eq(t.style_preset, "blockout", "default style should be blockout")
	assert_eq(t.two_stage, false, "default two_stage should be false")
	assert_eq(t.seed_value, 42, "default seed should be 42")
	assert_eq(t.bounds_x, 50.0, "default bounds_x should be 50")
	assert_eq(t.bounds_y, 30.0, "default bounds_y should be 30")
	assert_eq(t.bounds_z, 50.0, "default bounds_z should be 50")
	assert_eq(t.is_builtin, false, "default is_builtin should be false")


func test_scene_template_from_request() -> void:
	var t: SceneTemplate = SceneTemplate.new()
	var request: Dictionary = {
		"user_prompt": "a dark cave",
		"style_preset": "stylized",
		"two_stage": true,
		"seed": 999,
		"bounds_meters": [20.0, 10.0, 30.0],
	}
	t.from_request(request)
	assert_eq(t.prompt, "a dark cave")
	assert_eq(t.style_preset, "stylized")
	assert_eq(t.two_stage, true)
	assert_eq(t.seed_value, 999)
	assert_eq(t.bounds_x, 20.0)
	assert_eq(t.bounds_y, 10.0)
	assert_eq(t.bounds_z, 30.0)


func test_scene_template_to_request_overrides() -> void:
	var t: SceneTemplate = SceneTemplate.new()
	t.prompt = "a castle"
	t.style_preset = "realistic-lite"
	t.two_stage = true
	t.seed_value = 7
	t.bounds_x = 100.0
	t.bounds_y = 50.0
	t.bounds_z = 100.0

	var overrides: Dictionary = t.to_request_overrides()
	assert_eq(overrides["user_prompt"], "a castle")
	assert_eq(overrides["style_preset"], "realistic-lite")
	assert_eq(overrides["two_stage"], true)
	assert_eq(overrides["seed"], 7)
	var bounds: Array = overrides["bounds_meters"]
	assert_eq(bounds[0], 100.0)
	assert_eq(bounds[1], 50.0)
	assert_eq(bounds[2], 100.0)


func test_scene_template_duplicate() -> void:
	var t: SceneTemplate = SceneTemplate.new()
	t.template_name = "Original"
	t.prompt = "test prompt"
	t.is_builtin = true

	var copy: SceneTemplate = t.duplicate_template()
	assert_eq(copy.template_name, "Original")
	assert_eq(copy.prompt, "test prompt")
	assert_eq(copy.is_builtin, false, "duplicate should not be builtin")

# endregion

# region --- TemplateManager built-in ---

func test_manager_has_three_builtin_templates() -> void:
	assert_eq(_manager.get_builtin_count(), 3, "should have 3 built-in templates")


func test_manager_builtin_names() -> void:
	var names: Array[String] = _manager.get_template_names()
	assert_has(names, "Outdoor Clearing")
	assert_has(names, "Interior Room")
	assert_has(names, "Dungeon Corridor")


func test_manager_get_builtin_template() -> void:
	var t: SceneTemplate = _manager.get_template("Outdoor Clearing")
	assert_not_null(t, "should find Outdoor Clearing")
	assert_true(t.is_builtin, "should be marked as builtin")
	assert_false(t.prompt.is_empty(), "should have a prompt")


func test_manager_builtin_is_builtin() -> void:
	assert_true(_manager.is_builtin("Outdoor Clearing"))
	assert_true(_manager.is_builtin("Interior Room"))
	assert_true(_manager.is_builtin("Dungeon Corridor"))
	assert_false(_manager.is_builtin("NonExistent"))


func test_manager_get_nonexistent_returns_null() -> void:
	var t: SceneTemplate = _manager.get_template("does_not_exist")
	assert_null(t, "non-existent template should return null")


func test_manager_builtin_outdoor_has_correct_bounds() -> void:
	var t: SceneTemplate = _manager.get_template("Outdoor Clearing")
	assert_eq(t.bounds_x, 40.0)
	assert_eq(t.bounds_y, 20.0)
	assert_eq(t.bounds_z, 40.0)


func test_manager_builtin_dungeon_uses_two_stage() -> void:
	var t: SceneTemplate = _manager.get_template("Dungeon Corridor")
	assert_true(t.two_stage, "dungeon should use two-stage")
	assert_eq(t.style_preset, "stylized")

# endregion

# region --- TemplateManager custom CRUD ---

func test_manager_save_custom_template() -> void:
	var t: SceneTemplate = SceneTemplate.new()
	t.template_name = "My Custom"
	t.prompt = "custom scene"

	var err: int = _manager.save_custom_template(t)
	assert_eq(err, OK, "save should succeed")
	assert_eq(_manager.get_custom_count(), 1, "should have 1 custom template")


func test_manager_save_empty_name_fails() -> void:
	var t: SceneTemplate = SceneTemplate.new()
	t.template_name = ""

	var err: int = _manager.save_custom_template(t)
	assert_eq(err, ERR_INVALID_PARAMETER, "empty name should fail")


func test_manager_save_overwrites_existing() -> void:
	var t1: SceneTemplate = SceneTemplate.new()
	t1.template_name = "Overwrite Me"
	t1.prompt = "original"
	_manager.save_custom_template(t1)

	var t2: SceneTemplate = SceneTemplate.new()
	t2.template_name = "Overwrite Me"
	t2.prompt = "updated"
	_manager.save_custom_template(t2)

	assert_eq(_manager.get_custom_count(), 1, "should still have 1 custom")
	var loaded: SceneTemplate = _manager.get_template("Overwrite Me")
	assert_eq(loaded.prompt, "updated", "should have updated prompt")


func test_manager_delete_custom_template() -> void:
	var t: SceneTemplate = SceneTemplate.new()
	t.template_name = "Delete Me"
	t.prompt = "to be deleted"
	_manager.save_custom_template(t)

	var err: int = _manager.delete_custom_template("Delete Me")
	assert_eq(err, OK, "delete should succeed")
	assert_eq(_manager.get_custom_count(), 0, "should have 0 custom after delete")
	assert_null(_manager.get_template("Delete Me"), "should not find deleted template")


func test_manager_delete_builtin_fails() -> void:
	var err: int = _manager.delete_custom_template("Outdoor Clearing")
	assert_eq(err, ERR_UNAUTHORIZED, "deleting builtin should fail")
	assert_eq(_manager.get_builtin_count(), 3, "builtins should be unchanged")


func test_manager_delete_nonexistent_fails() -> void:
	var err: int = _manager.delete_custom_template("Ghost Template")
	assert_eq(err, ERR_DOES_NOT_EXIST, "deleting non-existent should fail")


func test_manager_custom_listed_after_builtin() -> void:
	var t: SceneTemplate = SceneTemplate.new()
	t.template_name = "ZZZ Custom Last"
	t.prompt = "custom"
	_manager.save_custom_template(t)

	var names: Array[String] = _manager.get_template_names()
	assert_eq(names.size(), 4, "3 builtin + 1 custom")
	assert_eq(names[3], "ZZZ Custom Last", "custom should be after builtins")


func test_manager_custom_is_not_builtin() -> void:
	var t: SceneTemplate = SceneTemplate.new()
	t.template_name = "Custom One"
	t.prompt = "custom"
	_manager.save_custom_template(t)

	assert_false(_manager.is_builtin("Custom One"))

# endregion

# region --- TemplateManager import/export ---

func test_manager_export_invalid_path() -> void:
	var err: int = _manager.export_template("Outdoor Clearing", "C:/bad/path.tres")
	assert_eq(err, ERR_INVALID_PARAMETER, "non-res:// path should fail")


func test_manager_export_nonexistent_template() -> void:
	var err: int = _manager.export_template("Ghost", "res://test_export.tres")
	assert_eq(err, ERR_DOES_NOT_EXIST)


func test_manager_import_invalid_path() -> void:
	var err: int = _manager.import_template("C:/bad/path.tres")
	assert_eq(err, ERR_INVALID_PARAMETER)

# endregion

# region --- Dock template UI ---

func test_dock_template_dropdown_exists() -> void:
	assert_not_null(_dock._template_dropdown, "template dropdown should exist")


func test_dock_template_load_button_exists() -> void:
	assert_not_null(_dock._template_load_button, "load button should exist")


func test_dock_template_save_button_exists() -> void:
	assert_not_null(_dock._template_save_button, "save button should exist")


func test_dock_template_delete_button_exists() -> void:
	assert_not_null(_dock._template_delete_button, "delete button should exist")


func test_dock_set_template_list_populates_dropdown() -> void:
	var names: Array[String] = ["Outdoor Clearing", "Interior Room", "Custom One"]
	_dock.set_template_list(names, 2)
	assert_eq(_dock._template_dropdown.item_count, 3, "should have 3 items")


func test_dock_set_template_list_marks_builtin() -> void:
	var names: Array[String] = ["Outdoor Clearing", "Custom One"]
	_dock.set_template_list(names, 1)
	var first_text: String = _dock._template_dropdown.get_item_text(0)
	assert_string_contains(first_text, "[built-in]", "built-in should be labeled")
	var second_text: String = _dock._template_dropdown.get_item_text(1)
	assert_false(second_text.contains("[built-in]"), "custom should not be labeled built-in")


func test_dock_delete_disabled_for_builtin() -> void:
	var names: Array[String] = ["Outdoor Clearing", "Custom One"]
	_dock.set_template_list(names, 1)
	_dock._template_dropdown.select(0)
	_dock._update_template_delete_state()
	assert_true(_dock._template_delete_button.disabled, "delete should be disabled for builtin")


func test_dock_delete_enabled_for_custom() -> void:
	var names: Array[String] = ["Outdoor Clearing", "Custom One"]
	_dock.set_template_list(names, 1)
	_dock._template_dropdown.select(1)
	_dock._update_template_delete_state()
	assert_false(_dock._template_delete_button.disabled, "delete should be enabled for custom")


func test_dock_get_selected_template_name() -> void:
	var names: Array[String] = ["A Template", "B Template"]
	_dock.set_template_list(names, 0)
	_dock._template_dropdown.select(1)
	assert_eq(_dock.get_selected_template_name(), "B Template")


func test_dock_apply_template_fills_prompt() -> void:
	var t: SceneTemplate = SceneTemplate.new()
	t.prompt = "apply this prompt"
	t.style_preset = "stylized"
	t.two_stage = true
	t.seed_value = 123
	t.bounds_x = 15.0
	t.bounds_y = 8.0
	t.bounds_z = 25.0

	_dock.apply_template(t)
	assert_eq(_dock._prompt_edit.text, "apply this prompt")
	assert_eq(_dock._two_stage_check.button_pressed, true)
	assert_eq(int(_dock._seed_spinbox.value), 123)
	assert_eq(_dock._bounds_x.value, 15.0)
	assert_eq(_dock._bounds_y.value, 8.0)
	assert_eq(_dock._bounds_z.value, 25.0)


func test_dock_apply_template_null_safe() -> void:
	_dock.apply_template(null)
	assert_eq(_dock._prompt_edit.text, "", "should not crash on null template")


func test_dock_template_load_signal() -> void:
	var names: Array[String] = ["Test Template"]
	_dock.set_template_list(names, 0)
	_dock._template_dropdown.select(0)
	watch_signals(_dock)
	_dock._on_template_load_pressed()
	assert_signal_emitted(_dock, "template_load_requested")


func test_dock_template_delete_signal() -> void:
	var names: Array[String] = ["Custom One"]
	_dock.set_template_list(names, 0)
	_dock._template_dropdown.select(0)
	watch_signals(_dock)
	_dock._on_template_delete_pressed()
	assert_signal_emitted(_dock, "template_delete_requested")


func test_dock_template_export_signal() -> void:
	var names: Array[String] = ["Template A"]
	_dock.set_template_list(names, 0)
	_dock._template_dropdown.select(0)
	watch_signals(_dock)
	_dock._on_template_export_pressed()
	assert_signal_emitted(_dock, "template_export_requested")


func test_dock_template_import_signal() -> void:
	watch_signals(_dock)
	_dock._on_template_import_pressed()
	assert_signal_emitted(_dock, "template_import_requested")


func test_dock_empty_template_list_disables_buttons() -> void:
	var empty: Array[String] = []
	_dock.set_template_list(empty, 0)
	assert_true(_dock._template_load_button.disabled, "load should be disabled for empty list")
	assert_true(_dock._template_delete_button.disabled, "delete should be disabled for empty list")

# endregion


# --- Helpers ---


func _cleanup_custom_dir() -> void:
	var custom_dir: String = SceneTemplateManager.CUSTOM_DIR
	if not DirAccess.dir_exists_absolute(custom_dir):
		return
	var dir: DirAccess = DirAccess.open(custom_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
