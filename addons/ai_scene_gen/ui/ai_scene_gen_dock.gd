@tool
class_name AiSceneGenDock extends Control

# --- Signals ---

signal generate_requested(request: Dictionary)
signal apply_requested()
signal discard_requested()
signal import_requested(path: String)
signal export_requested(path: String)
signal provider_changed(provider_name: String)

# --- Enums / Constants ---

enum DockState {
	IDLE = 0,
	GENERATING = 1,
	PREVIEW_READY = 2,
	ERROR = 3,
}

const STYLE_PRESETS: Array[String] = ["blockout", "stylized", "realistic-lite"]
const DEFAULT_BOUNDS_XZ: float = 50.0
const DEFAULT_BOUNDS_Y: float = 30.0
const MAX_SEED: int = 2147483647

# --- Private vars (UI elements) ---

var _prompt_edit: TextEdit
var _provider_dropdown: OptionButton
var _model_dropdown: OptionButton
var _style_dropdown: OptionButton
var _seed_spinbox: SpinBox
var _seed_random_button: Button
var _bounds_x: SpinBox
var _bounds_y: SpinBox
var _bounds_z: SpinBox
var _api_key_row: HBoxContainer
var _api_key_edit: LineEdit
var _generate_button: Button
var _apply_button: Button
var _discard_button: Button
var _import_button: Button
var _export_button: Button
var _status_label: Label
var _progress_bar: ProgressBar
var _error_container: VBoxContainer
var _error_scroll: ScrollContainer
var _state: int = DockState.IDLE


func _ready() -> void:
	custom_minimum_size = Vector2(300, 0)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.set_anchors_preset(PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 6)
	add_child(root_vbox)

	_build_header(root_vbox)
	_build_prompt_section(root_vbox)
	_build_settings_section(root_vbox)
	_build_action_buttons(root_vbox)
	_build_io_buttons(root_vbox)
	_build_status_section(root_vbox)
	_build_error_section(root_vbox)

	_generate_button.pressed.connect(_on_generate_pressed)
	_apply_button.pressed.connect(_on_apply_pressed)
	_discard_button.pressed.connect(_on_discard_pressed)
	_import_button.pressed.connect(_on_import_pressed)
	_export_button.pressed.connect(_on_export_pressed)
	_seed_random_button.pressed.connect(_on_random_seed_pressed)
	_provider_dropdown.item_selected.connect(_on_provider_selected)

	set_state(DockState.IDLE)


# --- Public methods ---


## Transition the dock to a new state, enabling/disabling controls accordingly.
func set_state(new_state: int) -> void:
	_state = new_state
	match _state:
		DockState.IDLE:
			_generate_button.disabled = false
			_apply_button.disabled = true
			_discard_button.disabled = true
			_import_button.disabled = false
			_export_button.disabled = false
			_progress_bar.visible = false
			_status_label.text = "Ready"
		DockState.GENERATING:
			_generate_button.disabled = true
			_apply_button.disabled = true
			_discard_button.disabled = true
			_import_button.disabled = true
			_export_button.disabled = true
			_progress_bar.visible = true
			_status_label.text = "Generating…"
		DockState.PREVIEW_READY:
			_generate_button.disabled = true
			_apply_button.disabled = false
			_discard_button.disabled = false
			_import_button.disabled = true
			_export_button.disabled = false
			_progress_bar.visible = false
			_status_label.text = "Preview ready — apply or discard."
		DockState.ERROR:
			_generate_button.disabled = false
			_apply_button.disabled = true
			_discard_button.disabled = true
			_import_button.disabled = false
			_export_button.disabled = false
			_progress_bar.visible = false
			_status_label.text = "Errors occurred."


## Display validation / generation errors in the error panel.
## Each entry expects keys: severity (String), code (String), message (String),
## and optionally fix_hint (String).
func show_errors(errors: Array[Dictionary]) -> void:
	clear_errors()
	for err: Dictionary in errors:
		var severity: String = err.get("severity", "info")
		var code: String = err.get("code", "")
		var message: String = err.get("message", "")
		var fix_hint: String = err.get("fix_hint", "")

		var prefix: String
		var color: Color
		match severity:
			"error":
				prefix = "[!] "
				color = Color(1.0, 0.3, 0.3)
			"warning":
				prefix = "[?] "
				color = Color(1.0, 0.85, 0.2)
			_:
				prefix = "[i] "
				color = Color(0.7, 0.7, 0.7)

		var lbl: Label = Label.new()
		lbl.text = "%s%s: %s" % [prefix, code, message]
		lbl.add_theme_color_override("font_color", color)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_error_container.add_child(lbl)

		if fix_hint != "":
			var hint_lbl: Label = Label.new()
			hint_lbl.text = "  Fix: %s" % fix_hint
			hint_lbl.add_theme_font_size_override("font_size", 12)
			hint_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			hint_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_error_container.add_child(hint_lbl)

	_error_scroll.visible = true
	set_state(DockState.ERROR)


## Update the progress bar and status message during generation.
func show_progress(percent: float, message: String) -> void:
	_progress_bar.value = percent * 100.0
	_status_label.text = message
	_progress_bar.visible = true


## Populate the provider dropdown from an external list.
func set_provider_list(providers: Array[String]) -> void:
	_provider_dropdown.clear()
	for p: String in providers:
		_provider_dropdown.add_item(p)
	if _provider_dropdown.item_count > 0:
		_provider_dropdown.select(0)


## Populate the model dropdown from an external list.
func set_model_list(models: Array[String]) -> void:
	_model_dropdown.clear()
	for m: String in models:
		_model_dropdown.add_item(m)
	if _model_dropdown.item_count > 0:
		_model_dropdown.select(0)


## Build and return the full generation request dictionary from current UI values.
func get_generation_request() -> Dictionary:
	var provider_text: String = ""
	if _provider_dropdown.selected >= 0:
		provider_text = _provider_dropdown.get_item_text(_provider_dropdown.selected)

	var model_text: String = ""
	if _model_dropdown.selected >= 0:
		model_text = _model_dropdown.get_item_text(_model_dropdown.selected)

	var style_text: String = "blockout"
	if _style_dropdown.selected >= 0:
		style_text = _style_dropdown.get_item_text(_style_dropdown.selected)

	return {
		"user_prompt": _prompt_edit.text,
		"selected_provider": provider_text,
		"selected_model": model_text,
		"style_preset": style_text,
		"seed": int(_seed_spinbox.value),
		"bounds_meters": [_bounds_x.value, _bounds_y.value, _bounds_z.value],
		"available_asset_tags": [] as Array[String],
		"project_constraints": "",
		"api_key": _api_key_edit.text,
	}


## Shows or hides the API key input field.
func set_api_key_visible(is_visible: bool) -> void:
	_api_key_row.visible = is_visible


## Sets the API key field text (e.g. from persisted settings).
func set_api_key(key: String) -> void:
	_api_key_edit.text = key


## Returns the currently entered API key.
func get_api_key() -> String:
	return _api_key_edit.text


## Remove all errors and hide the error panel.
func clear_errors() -> void:
	for child: Node in _error_container.get_children():
		child.queue_free()
	_error_scroll.visible = false


# --- Private: signal handlers ---


func _on_generate_pressed() -> void:
	if _prompt_edit.text.strip_edges() == "":
		var errs: Array[Dictionary] = [{
			"severity": "error",
			"code": "EMPTY_PROMPT",
			"message": "Scene description cannot be empty.",
			"fix_hint": "Enter a prompt describing the scene you want to generate.",
		}]
		show_errors(errs)
		return
	clear_errors()
	var request: Dictionary = get_generation_request()
	generate_requested.emit(request)


func _on_apply_pressed() -> void:
	apply_requested.emit()


func _on_discard_pressed() -> void:
	discard_requested.emit()
	clear_errors()
	set_state(DockState.IDLE)


func _on_random_seed_pressed() -> void:
	_seed_spinbox.value = randi() % (MAX_SEED + 1)


func _on_provider_selected(index: int) -> void:
	var provider_name: String = _provider_dropdown.get_item_text(index)
	provider_changed.emit(provider_name)


func _on_import_pressed() -> void:
	import_requested.emit("")


func _on_export_pressed() -> void:
	export_requested.emit("")


# --- Private: UI builders ---


func _build_header(parent: VBoxContainer) -> void:
	var header: Label = Label.new()
	header.text = "AI Scene Generator"
	header.add_theme_font_size_override("font_size", 18)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(header)
	parent.add_child(HSeparator.new())


func _build_prompt_section(parent: VBoxContainer) -> void:
	var lbl: Label = Label.new()
	lbl.text = "Scene Description:"
	parent.add_child(lbl)

	_prompt_edit = TextEdit.new()
	_prompt_edit.custom_minimum_size.y = 100
	_prompt_edit.placeholder_text = "Describe your scene… e.g. 'a medieval courtyard with a well in the center'"
	_prompt_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(_prompt_edit)


func _build_settings_section(parent: VBoxContainer) -> void:
	var settings_lbl: Label = Label.new()
	settings_lbl.text = "Settings"
	parent.add_child(settings_lbl)
	parent.add_child(HSeparator.new())

	_provider_dropdown = _add_labeled_option(parent, "Provider:")
	_model_dropdown = _add_labeled_option(parent, "Model:")

	_api_key_row = HBoxContainer.new()
	_api_key_row.add_child(_make_label("API Key:"))
	_api_key_edit = LineEdit.new()
	_api_key_edit.placeholder_text = "Enter API key…"
	_api_key_edit.secret = true
	_api_key_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_api_key_row.add_child(_api_key_edit)
	parent.add_child(_api_key_row)
	_api_key_row.visible = false

	_style_dropdown = _add_labeled_option(parent, "Style:")
	for preset: String in STYLE_PRESETS:
		_style_dropdown.add_item(preset)
	_style_dropdown.select(0)

	# Seed row
	var seed_row: HBoxContainer = HBoxContainer.new()
	seed_row.add_child(_make_label("Seed:"))
	_seed_spinbox = SpinBox.new()
	_seed_spinbox.min_value = 0
	_seed_spinbox.max_value = MAX_SEED
	_seed_spinbox.value = 42
	_seed_spinbox.step = 1
	_seed_spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_row.add_child(_seed_spinbox)
	_seed_random_button = Button.new()
	_seed_random_button.text = "Random"
	seed_row.add_child(_seed_random_button)
	parent.add_child(seed_row)

	# Bounds
	var bounds_lbl: Label = Label.new()
	bounds_lbl.text = "Bounds (meters):"
	parent.add_child(bounds_lbl)

	var bounds_row: HBoxContainer = HBoxContainer.new()
	bounds_row.add_child(_make_label("X:"))
	_bounds_x = _make_bounds_spinbox(DEFAULT_BOUNDS_XZ)
	bounds_row.add_child(_bounds_x)
	bounds_row.add_child(_make_label("Y:"))
	_bounds_y = _make_bounds_spinbox(DEFAULT_BOUNDS_Y)
	bounds_row.add_child(_bounds_y)
	bounds_row.add_child(_make_label("Z:"))
	_bounds_z = _make_bounds_spinbox(DEFAULT_BOUNDS_XZ)
	bounds_row.add_child(_bounds_z)
	parent.add_child(bounds_row)


func _build_action_buttons(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())

	_generate_button = Button.new()
	_generate_button.text = "Generate Scene"
	_generate_button.custom_minimum_size.y = 36
	_generate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_generate_button)

	var action_row: HBoxContainer = HBoxContainer.new()
	_apply_button = Button.new()
	_apply_button.text = "Apply"
	_apply_button.disabled = true
	_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_apply_button)

	_discard_button = Button.new()
	_discard_button.text = "Discard"
	_discard_button.disabled = true
	_discard_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_discard_button)
	parent.add_child(action_row)


func _build_io_buttons(parent: VBoxContainer) -> void:
	var io_row: HBoxContainer = HBoxContainer.new()
	_import_button = Button.new()
	_import_button.text = "Import Spec"
	_import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	io_row.add_child(_import_button)

	_export_button = Button.new()
	_export_button.text = "Export Spec"
	_export_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	io_row.add_child(_export_button)
	parent.add_child(io_row)


func _build_status_section(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())

	_status_label = Label.new()
	_status_label.text = "Ready"
	parent.add_child(_status_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.value = 0
	_progress_bar.visible = false
	parent.add_child(_progress_bar)


func _build_error_section(parent: VBoxContainer) -> void:
	_error_scroll = ScrollContainer.new()
	_error_scroll.custom_minimum_size.y = 80
	_error_scroll.visible = false

	_error_container = VBoxContainer.new()
	_error_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_error_scroll.add_child(_error_container)
	parent.add_child(_error_scroll)


# --- Private: factory helpers ---


func _add_labeled_option(parent: VBoxContainer, label_text: String) -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_child(_make_label(label_text))
	var opt: OptionButton = OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(opt)
	parent.add_child(row)
	return opt


func _make_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	return lbl


func _make_bounds_spinbox(default_value: float) -> SpinBox:
	var sb: SpinBox = SpinBox.new()
	sb.min_value = 1.0
	sb.max_value = 1000.0
	sb.step = 0.5
	sb.value = default_value
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sb
