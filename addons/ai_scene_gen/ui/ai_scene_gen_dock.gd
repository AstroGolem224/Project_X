@tool
class_name AiSceneGenDock extends Control

# --- Signals ---

signal generate_requested(request: Dictionary)
signal apply_requested()
signal discard_requested()
signal cancel_requested()
signal import_requested(path: String)
signal export_requested(path: String)
signal provider_changed(provider_name: String)
signal connection_test_requested(provider_name: String)

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

## Maps known error codes to human-readable fix suggestions used as fallback
## when the error dictionary itself does not carry a fix_hint.
const ERROR_HINTS: Dictionary = {
	"UI_ERR_EMPTY_PROMPT": "Enter a scene description in the prompt field.",
	"UI_ERR_INVALID_BOUNDS": "Set each bound axis between 0.5 and 1000.",
	"UI_ERR_INVALID_SEED": "Enter a seed between 0 and 2147483647.",
	"UI_ERR_NO_SCENE": "Open or create a 3D scene (Node3D root).",
	"UI_ERR_NOT_3D": "Scene root must be Node3D or a subclass.",
	"ORCH_ERR_ALREADY_RUNNING": "Wait for the current generation to finish or cancel it.",
	"ORCH_ERR_STAGE_FAILED": "Check provider connection and prompt, then retry.",
	"ORCH_ERR_RETRY_EXHAUSTED": "Simplify your prompt or try a different model.",
	"ORCH_ERR_CANCELLED": "Generation was cancelled. Click Generate to start again.",
	"LLM_ERR_NETWORK": "Check your network connection and provider URL.",
	"LLM_ERR_TIMEOUT": "Increase timeout or simplify the prompt.",
	"LLM_ERR_AUTH": "Verify your API key is correct and has sufficient quota.",
	"LLM_ERR_RATE_LIMIT": "Wait a moment and retry — you hit the rate limit.",
	"LLM_ERR_SERVER": "The LLM server returned an error. Try again later.",
	"LLM_ERR_NON_JSON": "The model returned non-JSON output. Try a different model.",
	"EXPORT_ERR_NO_SPEC": "Generate a scene before exporting.",
	"EXPORT_ERR_WRITE": "Check file permissions and path.",
	"IMPORT_ERR_FAILED": "Check that the file is valid SceneSpec JSON.",
}

# --- Private vars (UI elements) ---

var _prompt_edit: TextEdit
var _provider_dropdown: OptionButton
var _model_dropdown: OptionButton
var _custom_model_edit: LineEdit
var _style_dropdown: OptionButton
var _seed_spinbox: SpinBox
var _seed_random_button: Button
var _two_stage_check: CheckBox
var _variation_check: CheckBox
var _bounds_x: SpinBox
var _bounds_y: SpinBox
var _bounds_z: SpinBox
var _host_url_row: HBoxContainer
var _host_url_edit: LineEdit
var _api_key_row: HBoxContainer
var _api_key_edit: LineEdit
var _generate_button: Button
var _apply_button: Button
var _discard_button: Button
var _import_button: Button
var _export_button: Button
var _status_label: Label
var _progress_bar: ProgressBar
var _elapsed_label: Label
var _error_container: VBoxContainer
var _error_scroll: ScrollContainer
var _error_header_row: HBoxContainer
var _copy_all_errors_button: Button
var _asset_tag_section: VBoxContainer
var _asset_tag_container: VBoxContainer
var _asset_tag_checks: Array[CheckBox] = []
var _asset_tag_empty_label: Label
var _test_connection_button: Button
var _connection_result_label: Label
var _state: int = DockState.IDLE
var _generation_start_msec: int = 0
var _progress_tween: Tween = null
var _last_errors_text: String = ""


func _ready() -> void:
	custom_minimum_size = Vector2(300, 0)

	var root_vbox: VBoxContainer = VBoxContainer.new()
	root_vbox.set_anchors_preset(PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 6)
	add_child(root_vbox)

	_build_header(root_vbox)
	_build_prompt_section(root_vbox)
	_build_settings_section(root_vbox)
	_build_asset_tag_section(root_vbox)
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
	_test_connection_button.pressed.connect(_on_test_connection_pressed)
	_copy_all_errors_button.pressed.connect(_on_copy_all_errors_pressed)

	set_state(DockState.IDLE)
	set_process(false)


func _process(_delta: float) -> void:
	if _state != DockState.GENERATING or _generation_start_msec <= 0:
		return
	var elapsed_ms: int = Time.get_ticks_msec() - _generation_start_msec
	var total_secs: int = elapsed_ms / 1000
	_elapsed_label.text = "%02d:%02d" % [total_secs / 60, total_secs % 60]


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event as InputEventKey
	if not key.pressed or key.echo:
		return

	if key.keycode == KEY_G and key.ctrl_pressed and not key.shift_pressed and not key.alt_pressed:
		if _state == DockState.IDLE or _state == DockState.ERROR:
			_on_generate_pressed()
			get_viewport().set_input_as_handled()
	elif key.keycode == KEY_A and key.ctrl_pressed and key.shift_pressed and not key.alt_pressed:
		if _state == DockState.PREVIEW_READY:
			_on_apply_pressed()
			get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE:
		if _state == DockState.GENERATING:
			cancel_requested.emit()
			get_viewport().set_input_as_handled()
		elif _state == DockState.PREVIEW_READY:
			_on_discard_pressed()
			get_viewport().set_input_as_handled()


# --- Public methods ---


## Transition the dock to a new state, enabling/disabling controls accordingly.
func set_state(new_state: int) -> void:
	_state = new_state
	match _state:
		DockState.IDLE:
			_generate_button.disabled = false
			_generate_button.text = "Generate Scene (Ctrl+G)"
			_apply_button.disabled = true
			_discard_button.disabled = true
			_import_button.disabled = false
			_export_button.disabled = false
			_progress_bar.visible = false
			_elapsed_label.visible = false
			_status_label.text = "Ready"
			_stop_elapsed_timer()
		DockState.GENERATING:
			_generate_button.disabled = false
			_generate_button.text = "Cancel (Esc)"
			_apply_button.disabled = true
			_discard_button.disabled = true
			_import_button.disabled = true
			_export_button.disabled = true
			_progress_bar.visible = true
			_elapsed_label.visible = true
			_status_label.text = "Generating…"
			_start_elapsed_timer()
		DockState.PREVIEW_READY:
			_generate_button.disabled = true
			_generate_button.text = "Generate Scene (Ctrl+G)"
			_apply_button.disabled = false
			_discard_button.disabled = false
			_import_button.disabled = true
			_export_button.disabled = false
			_progress_bar.visible = false
			_elapsed_label.visible = false
			_status_label.text = "Preview ready — apply or discard."
			_stop_elapsed_timer()
		DockState.ERROR:
			_generate_button.disabled = false
			_generate_button.text = "Generate Scene (Ctrl+G)"
			_apply_button.disabled = true
			_discard_button.disabled = true
			_import_button.disabled = false
			_export_button.disabled = false
			_progress_bar.visible = false
			_elapsed_label.visible = false
			_status_label.text = "Errors occurred."
			_stop_elapsed_timer()


## Display validation / generation errors in the error panel with collapsible
## details and per-error / bulk copy-to-clipboard buttons.
func show_errors(errors: Array[Dictionary]) -> void:
	clear_errors()
	var full_text_parts: Array[String] = []

	for err: Dictionary in errors:
		var severity: String = err.get("severity", "info")
		var code: String = err.get("code", "")
		var message: String = err.get("message", "")
		var fix_hint: String = err.get("fix_hint", "")
		if fix_hint.is_empty():
			fix_hint = ERROR_HINTS.get(code, "") as String

		var prefix: String
		var color: Color
		match severity:
			"error":
				prefix = "ERROR"
				color = Color(1.0, 0.3, 0.3)
			"warning":
				prefix = "WARN"
				color = Color(1.0, 0.85, 0.2)
			_:
				prefix = "INFO"
				color = Color(0.7, 0.7, 0.7)

		var card: PanelContainer = PanelContainer.new()
		var card_vbox: VBoxContainer = VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 2)
		card.add_child(card_vbox)

		var header_row: HBoxContainer = HBoxContainer.new()
		var code_label: Label = Label.new()
		code_label.text = "[%s] %s" % [prefix, code]
		code_label.add_theme_color_override("font_color", color)
		code_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header_row.add_child(code_label)

		var single_err_text: String = "%s: %s" % [code, message]
		if not fix_hint.is_empty():
			single_err_text += "\nFix: %s" % fix_hint

		var copy_btn: Button = Button.new()
		copy_btn.text = "Copy"
		copy_btn.flat = true
		copy_btn.add_theme_font_size_override("font_size", 11)
		copy_btn.pressed.connect(_copy_text_to_clipboard.bind(single_err_text))
		header_row.add_child(copy_btn)
		card_vbox.add_child(header_row)

		var msg_label: Label = Label.new()
		msg_label.text = message
		msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg_label.add_theme_font_size_override("font_size", 13)
		card_vbox.add_child(msg_label)

		if not fix_hint.is_empty():
			var detail_container: VBoxContainer = VBoxContainer.new()
			detail_container.visible = false

			var hint_label: Label = Label.new()
			hint_label.text = "Fix: %s" % fix_hint
			hint_label.add_theme_font_size_override("font_size", 12)
			hint_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
			hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			detail_container.add_child(hint_label)

			var toggle_btn: Button = Button.new()
			toggle_btn.text = "▶ Show Fix"
			toggle_btn.flat = true
			toggle_btn.add_theme_font_size_override("font_size", 11)
			toggle_btn.pressed.connect(func() -> void:
				detail_container.visible = not detail_container.visible
				toggle_btn.text = ("▼ Hide Fix" if detail_container.visible else "▶ Show Fix")
			)
			card_vbox.add_child(toggle_btn)
			card_vbox.add_child(detail_container)

		_error_container.add_child(card)
		full_text_parts.append(single_err_text)

	_last_errors_text = "\n\n".join(PackedStringArray(full_text_parts))
	_error_header_row.visible = errors.size() > 0
	_error_scroll.visible = true
	set_state(DockState.ERROR)


## Update the progress bar (animated) and status message during generation.
func show_progress(percent: float, message: String) -> void:
	var target: float = percent * 100.0
	if is_inside_tree():
		if _progress_tween != null and _progress_tween.is_valid():
			_progress_tween.kill()
		_progress_tween = create_tween()
		_progress_tween.tween_property(_progress_bar, "value", target, 0.3).set_ease(Tween.EASE_OUT)
	else:
		_progress_bar.value = target
	_status_label.text = message
	_progress_bar.visible = true
	_elapsed_label.visible = true


## Populate the provider dropdown from an external list.
func set_provider_list(providers: Array[String]) -> void:
	_provider_dropdown.clear()
	for p: String in providers:
		_provider_dropdown.add_item(p)
	if _provider_dropdown.item_count > 0:
		_provider_dropdown.select(0)
	_update_connection_test_visibility()


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

	var model_text: String = _custom_model_edit.text.strip_edges()
	if model_text.is_empty() and _model_dropdown.selected >= 0:
		model_text = _model_dropdown.get_item_text(_model_dropdown.selected)

	var style_text: String = "blockout"
	if _style_dropdown.selected >= 0:
		style_text = _style_dropdown.get_item_text(_style_dropdown.selected)

	var selected_tags: Array[String] = []
	for check: CheckBox in _asset_tag_checks:
		if check.button_pressed:
			selected_tags.append(check.text)

	return {
		"user_prompt": _prompt_edit.text,
		"selected_provider": provider_text,
		"selected_model": model_text,
		"style_preset": style_text,
		"two_stage": _two_stage_check.button_pressed,
		"variation": _variation_check.button_pressed,
		"seed": int(_seed_spinbox.value),
		"bounds_meters": [_bounds_x.value, _bounds_y.value, _bounds_z.value],
		"available_asset_tags": selected_tags,
		"project_constraints": "",
		"api_key": _api_key_edit.text if _api_key_edit != null else "",
		"host_url": _host_url_edit.text if _host_url_edit != null else "",
	}


## Shows or hides the host URL input field.
func set_host_url_visible(is_visible: bool) -> void:
	if _host_url_row == null:
		return
	_host_url_row.visible = is_visible


## Sets the host URL field text (e.g. from persisted settings).
func set_host_url(url: String) -> void:
	if _host_url_edit == null:
		return
	_host_url_edit.text = url


## Returns the currently entered host URL.
func get_host_url() -> String:
	if _host_url_edit == null:
		return ""
	return _host_url_edit.text


## Shows or hides the API key input field.
func set_api_key_visible(is_visible: bool) -> void:
	_api_key_row.visible = is_visible


## Sets the API key field text (e.g. from persisted settings).
func set_api_key(key: String) -> void:
	_api_key_edit.text = key


## Returns the currently entered API key.
func get_api_key() -> String:
	return _api_key_edit.text


## Displays the result of a connection test and re-enables the test button.
func show_connection_result(success: bool, model_count: int) -> void:
	_test_connection_button.disabled = false
	_connection_result_label.visible = true
	if success:
		_connection_result_label.text = "Connected — %d models" % model_count
		_connection_result_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		_connection_result_label.text = "Failed: could not reach provider"
		_connection_result_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))


## Remove all errors and hide the error panel.
func clear_errors() -> void:
	for child: Node in _error_container.get_children():
		child.queue_free()
	_error_scroll.visible = false
	_error_header_row.visible = false
	_last_errors_text = ""


## Updates the asset tag browser with tags from the registry.
## @param tags: All registered tags (sorted).
## @param registry: The AssetTagRegistry to read category metadata from.
func update_asset_tags(tags: Array[String], registry: Resource = null) -> void:
	_asset_tag_checks.clear()
	for child: Node in _asset_tag_container.get_children():
		child.queue_free()

	if tags.is_empty():
		_asset_tag_empty_label = Label.new()
		_asset_tag_empty_label.text = "No asset tags registered"
		_asset_tag_empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		_asset_tag_container.add_child(_asset_tag_empty_label)
		return

	for tag: String in tags:
		var label_text: String = tag
		if registry != null and registry.has_method("get_entry"):
			var entry: Dictionary = registry.get_entry(tag)
			var res_type: String = entry.get("resource_type", "")
			if not res_type.is_empty():
				label_text = "%s  [%s]" % [tag, res_type]
		var check: CheckBox = CheckBox.new()
		check.text = tag
		check.tooltip_text = label_text
		check.button_pressed = false
		_asset_tag_checks.append(check)
		_asset_tag_container.add_child(check)


# --- Private: signal handlers ---


func _on_generate_pressed() -> void:
	if _state == DockState.GENERATING:
		cancel_requested.emit()
		return

	if _prompt_edit.text.strip_edges() == "":
		var errs: Array[Dictionary] = [{
			"severity": "error",
			"code": "UI_ERR_EMPTY_PROMPT",
			"message": "Scene description cannot be empty.",
			"fix_hint": "Enter a prompt describing the scene you want to generate.",
		}]
		show_errors(errs)
		return

	var bx: float = _bounds_x.value
	var by: float = _bounds_y.value
	var bz: float = _bounds_z.value
	if bx <= 0.0 or by <= 0.0 or bz <= 0.0 or bx > 1000.0 or by > 1000.0 or bz > 1000.0:
		var errs: Array[Dictionary] = [{
			"severity": "error",
			"code": "UI_ERR_INVALID_BOUNDS",
			"message": "All bound axes must be > 0 and <= 1000.",
			"fix_hint": "Set each bound axis to a value between 0.5 and 1000.",
		}]
		show_errors(errs)
		return

	var seed_val: int = int(_seed_spinbox.value)
	if seed_val < 0 or seed_val > MAX_SEED:
		var errs: Array[Dictionary] = [{
			"severity": "error",
			"code": "UI_ERR_INVALID_SEED",
			"message": "Seed must be between 0 and %d." % MAX_SEED,
			"fix_hint": "Enter a seed value in the valid range.",
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
	_update_connection_test_visibility()
	provider_changed.emit(provider_name)


func _on_test_connection_pressed() -> void:
	var provider_name: String = ""
	if _provider_dropdown.selected >= 0:
		provider_name = _provider_dropdown.get_item_text(_provider_dropdown.selected)
	_test_connection_button.disabled = true
	_connection_result_label.text = "Testing…"
	_connection_result_label.visible = true
	_connection_result_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	connection_test_requested.emit(provider_name)


func _on_import_pressed() -> void:
	import_requested.emit("")


func _on_export_pressed() -> void:
	export_requested.emit("")


func _on_copy_all_errors_pressed() -> void:
	if not _last_errors_text.is_empty():
		DisplayServer.clipboard_set(_last_errors_text)


# --- Private: helpers ---


func _update_connection_test_visibility() -> void:
	var provider_name: String = ""
	if _provider_dropdown.selected >= 0:
		provider_name = _provider_dropdown.get_item_text(_provider_dropdown.selected)
	var show: bool = provider_name != "MockProvider" and not provider_name.is_empty()
	_test_connection_button.visible = show
	if show:
		_test_connection_button.disabled = false
	_connection_result_label.visible = false
	_connection_result_label.text = ""


func _start_elapsed_timer() -> void:
	_generation_start_msec = Time.get_ticks_msec()
	_elapsed_label.text = "00:00"
	set_process(true)


func _stop_elapsed_timer() -> void:
	set_process(false)
	_generation_start_msec = 0


func _copy_text_to_clipboard(text: String) -> void:
	DisplayServer.clipboard_set(text)


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

	var provider_row: HBoxContainer = HBoxContainer.new()
	provider_row.add_child(_make_label("Provider:"))
	_provider_dropdown = OptionButton.new()
	_provider_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	provider_row.add_child(_provider_dropdown)
	_test_connection_button = Button.new()
	_test_connection_button.text = "Test Connection"
	_test_connection_button.visible = false
	provider_row.add_child(_test_connection_button)
	parent.add_child(provider_row)

	_connection_result_label = Label.new()
	_connection_result_label.text = ""
	_connection_result_label.visible = false
	parent.add_child(_connection_result_label)

	_model_dropdown = _add_labeled_option(parent, "Model:")

	var custom_model_row: HBoxContainer = HBoxContainer.new()
	custom_model_row.add_child(_make_label("Custom:"))
	_custom_model_edit = LineEdit.new()
	_custom_model_edit.placeholder_text = "e.g. qwen3.5:27b (overrides dropdown)"
	_custom_model_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_model_row.add_child(_custom_model_edit)
	parent.add_child(custom_model_row)

	_host_url_row = HBoxContainer.new()
	_host_url_row.add_child(_make_label("Host:"))
	_host_url_edit = LineEdit.new()
	_host_url_edit.placeholder_text = "http://localhost:11434"
	_host_url_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_url_row.add_child(_host_url_edit)
	parent.add_child(_host_url_row)
	_host_url_row.visible = false

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

	_two_stage_check = CheckBox.new()
	_two_stage_check.text = "Two-Stage (detailed planning)"
	_two_stage_check.button_pressed = false
	parent.add_child(_two_stage_check)

	_variation_check = CheckBox.new()
	_variation_check.text = "Variation Mode"
	_variation_check.button_pressed = false
	parent.add_child(_variation_check)

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


func _build_asset_tag_section(parent: VBoxContainer) -> void:
	_asset_tag_section = VBoxContainer.new()

	var toggle_btn: Button = Button.new()
	toggle_btn.text = "▶ Available Asset Tags"
	toggle_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle_btn.flat = true
	_asset_tag_section.add_child(toggle_btn)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size.y = 100
	scroll.visible = false

	_asset_tag_container = VBoxContainer.new()
	_asset_tag_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_asset_tag_container)
	_asset_tag_section.add_child(scroll)

	_asset_tag_empty_label = Label.new()
	_asset_tag_empty_label.text = "No asset tags registered"
	_asset_tag_empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_asset_tag_container.add_child(_asset_tag_empty_label)

	toggle_btn.pressed.connect(func() -> void:
		scroll.visible = not scroll.visible
		toggle_btn.text = ("▼ " if scroll.visible else "▶ ") + "Available Asset Tags"
	)

	parent.add_child(_asset_tag_section)


func _build_action_buttons(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())

	_generate_button = Button.new()
	_generate_button.text = "Generate Scene (Ctrl+G)"
	_generate_button.tooltip_text = "Generate a 3D scene from the prompt (Ctrl+G)"
	_generate_button.custom_minimum_size.y = 36
	_generate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_generate_button)

	var action_row: HBoxContainer = HBoxContainer.new()
	_apply_button = Button.new()
	_apply_button.text = "Apply (Ctrl+Shift+A)"
	_apply_button.tooltip_text = "Apply the preview to the scene (Ctrl+Shift+A)"
	_apply_button.disabled = true
	_apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(_apply_button)

	_discard_button = Button.new()
	_discard_button.text = "Discard (Esc)"
	_discard_button.tooltip_text = "Discard the preview (Escape)"
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

	var status_row: HBoxContainer = HBoxContainer.new()
	_status_label = Label.new()
	_status_label.text = "Ready"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_status_label)

	_elapsed_label = Label.new()
	_elapsed_label.text = "00:00"
	_elapsed_label.visible = false
	_elapsed_label.add_theme_font_size_override("font_size", 12)
	_elapsed_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	status_row.add_child(_elapsed_label)
	parent.add_child(status_row)

	_progress_bar = ProgressBar.new()
	_progress_bar.value = 0
	_progress_bar.visible = false
	parent.add_child(_progress_bar)


func _build_error_section(parent: VBoxContainer) -> void:
	_error_header_row = HBoxContainer.new()
	_error_header_row.visible = false
	var error_title: Label = Label.new()
	error_title.text = "Errors"
	error_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	error_title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_error_header_row.add_child(error_title)

	_copy_all_errors_button = Button.new()
	_copy_all_errors_button.text = "Copy All"
	_copy_all_errors_button.flat = true
	_error_header_row.add_child(_copy_all_errors_button)
	parent.add_child(_error_header_row)

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
