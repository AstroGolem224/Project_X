@tool
extends GutTest

## GUT tests for AiSceneGenDock (Module A).
## Covers: request shape, variation flag, two-stage flag, asset tags, state
## transitions, connection test, progress/elapsed, error display, cancel, shortcuts.

var _dock: AiSceneGenDock


func before_each() -> void:
	_dock = AiSceneGenDock.new()
	add_child(_dock)


func after_each() -> void:
	if is_instance_valid(_dock):
		remove_child(_dock)
		_dock.queue_free()


# region --- Request shape ---

func test_request_has_all_required_keys() -> void:
	var request: Dictionary = _dock.get_generation_request()
	var required_keys: Array[String] = [
		"user_prompt",
		"selected_provider",
		"selected_model",
		"style_preset",
		"two_stage",
		"variation",
		"seed",
		"bounds_meters",
		"available_asset_tags",
		"project_constraints",
	]
	for key: String in required_keys:
		assert_true(request.has(key), "request should have key '%s'" % key)


func test_request_default_values() -> void:
	var request: Dictionary = _dock.get_generation_request()
	assert_eq(request["user_prompt"], "", "default prompt should be empty")
	assert_eq(request["style_preset"], "blockout", "default style should be blockout")
	assert_eq(request["two_stage"], false, "default two_stage should be false")
	assert_eq(request["variation"], false, "default variation should be false")
	assert_eq(request["seed"], 42, "default seed should be 42")
	assert_eq(request["project_constraints"], "", "default constraints should be empty")


func test_request_bounds_default() -> void:
	var request: Dictionary = _dock.get_generation_request()
	var bounds: Array = request["bounds_meters"]
	assert_eq(bounds.size(), 3, "bounds should have 3 components")
	assert_eq(bounds[0], 50.0, "default X bound")
	assert_eq(bounds[1], 30.0, "default Y bound")
	assert_eq(bounds[2], 50.0, "default Z bound")


func test_request_available_asset_tags_empty_default() -> void:
	var request: Dictionary = _dock.get_generation_request()
	var tags: Array = request["available_asset_tags"]
	assert_eq(tags.size(), 0, "default asset tags should be empty")

# endregion

# region --- Variation flag ---

func test_variation_flag_in_request() -> void:
	_dock._variation_check.button_pressed = true
	var request: Dictionary = _dock.get_generation_request()
	assert_true(request["variation"] as bool, "variation should be true when checkbox is checked")


func test_variation_flag_off_by_default() -> void:
	var request: Dictionary = _dock.get_generation_request()
	assert_false(request["variation"] as bool, "variation should be false by default")

# endregion

# region --- Two-stage flag ---

func test_two_stage_flag_in_request() -> void:
	_dock._two_stage_check.button_pressed = true
	var request: Dictionary = _dock.get_generation_request()
	assert_true(request["two_stage"] as bool, "two_stage should be true when checkbox is checked")

# endregion

# region --- Asset tags ---

func test_asset_tags_selection_in_request() -> void:
	var tags: Array[String] = ["tree_oak", "rock_moss", "bush_small"]
	_dock.update_asset_tags(tags)

	assert_eq(_dock._asset_tag_checks.size(), 3, "should create 3 tag checkboxes")

	_dock._asset_tag_checks[0].button_pressed = true
	_dock._asset_tag_checks[2].button_pressed = true

	var request: Dictionary = _dock.get_generation_request()
	var selected: Array = request["available_asset_tags"]
	assert_eq(selected.size(), 2, "should have 2 selected tags")
	assert_has(selected, "tree_oak", "should contain tree_oak")
	assert_has(selected, "bush_small", "should contain bush_small")


func test_empty_asset_tags_shows_label() -> void:
	var empty_tags: Array[String] = []
	_dock.update_asset_tags(empty_tags)
	assert_eq(_dock._asset_tag_checks.size(), 0, "no checkboxes for empty tags")

# endregion

# region --- State transitions ---

func test_set_state_idle() -> void:
	_dock.set_state(AiSceneGenDock.DockState.IDLE)
	assert_false(_dock._generate_button.disabled, "generate should be enabled in IDLE")
	assert_true(_dock._apply_button.disabled, "apply should be disabled in IDLE")


func test_set_state_generating() -> void:
	_dock.set_state(AiSceneGenDock.DockState.GENERATING)
	assert_false(_dock._generate_button.disabled, "generate (cancel) should be enabled in GENERATING")
	assert_true(_dock._apply_button.disabled, "apply should be disabled in GENERATING")
	assert_eq(_dock._generate_button.text, "Cancel (Esc)", "button should show Cancel during GENERATING")


func test_set_state_preview_ready() -> void:
	_dock.set_state(AiSceneGenDock.DockState.PREVIEW_READY)
	assert_true(_dock._generate_button.disabled, "generate should be disabled in PREVIEW_READY")
	assert_false(_dock._apply_button.disabled, "apply should be enabled in PREVIEW_READY")
	assert_false(_dock._discard_button.disabled, "discard should be enabled in PREVIEW_READY")

# endregion

# region --- Cancel ---

func test_cancel_signal_emitted_during_generating() -> void:
	_dock.set_state(AiSceneGenDock.DockState.GENERATING)
	watch_signals(_dock)
	_dock._on_generate_pressed()
	assert_signal_emitted(_dock, "cancel_requested")


func test_generate_not_emitted_during_generating() -> void:
	_dock.set_state(AiSceneGenDock.DockState.GENERATING)
	watch_signals(_dock)
	_dock._on_generate_pressed()
	assert_signal_not_emitted(_dock, "generate_requested")


func test_generate_button_text_idle() -> void:
	_dock.set_state(AiSceneGenDock.DockState.IDLE)
	assert_eq(_dock._generate_button.text, "Generate Scene (Ctrl+G)")


func test_generate_button_text_error() -> void:
	_dock.set_state(AiSceneGenDock.DockState.ERROR)
	assert_eq(_dock._generate_button.text, "Generate Scene (Ctrl+G)")

# endregion

# region --- Progress / Elapsed ---

func test_elapsed_label_hidden_in_idle() -> void:
	_dock.set_state(AiSceneGenDock.DockState.IDLE)
	assert_false(_dock._elapsed_label.visible, "elapsed label should be hidden in IDLE")


func test_elapsed_label_visible_in_generating() -> void:
	_dock.set_state(AiSceneGenDock.DockState.GENERATING)
	assert_true(_dock._elapsed_label.visible, "elapsed label should be visible in GENERATING")


func test_elapsed_label_hidden_in_error() -> void:
	_dock.set_state(AiSceneGenDock.DockState.ERROR)
	assert_false(_dock._elapsed_label.visible, "elapsed label should be hidden in ERROR")


func test_show_progress_updates_status() -> void:
	_dock.show_progress(0.5, "Building scene...")
	assert_eq(_dock._status_label.text, "Building scene...", "status should show stage message")
	assert_true(_dock._progress_bar.visible, "progress bar should be visible")


func test_show_progress_shows_elapsed() -> void:
	_dock.show_progress(0.3, "Validating...")
	assert_true(_dock._elapsed_label.visible, "elapsed label should be visible during progress")

# endregion

# region --- Error display ---

func test_show_errors_creates_panel_containers() -> void:
	var errs: Array[Dictionary] = [{
		"severity": "error",
		"code": "TEST_ERR",
		"message": "Test error message.",
		"fix_hint": "Try fixing it.",
	}]
	_dock.show_errors(errs)
	assert_eq(_dock._error_container.get_child_count(), 1, "should create 1 error card")
	var card: Node = _dock._error_container.get_child(0)
	assert_true(card is PanelContainer, "error should be in a PanelContainer")


func test_show_errors_header_visible() -> void:
	var errs: Array[Dictionary] = [{
		"severity": "error",
		"code": "TEST_ERR",
		"message": "Test error.",
	}]
	_dock.show_errors(errs)
	assert_true(_dock._error_header_row.visible, "error header row should be visible")


func test_clear_errors_hides_header() -> void:
	var errs: Array[Dictionary] = [{
		"severity": "error",
		"code": "TEST_ERR",
		"message": "Test error.",
	}]
	_dock.show_errors(errs)
	_dock.clear_errors()
	assert_false(_dock._error_header_row.visible, "error header should be hidden after clear")
	assert_eq(_dock._last_errors_text, "", "errors text should be empty after clear")


func test_error_hints_fallback() -> void:
	var errs: Array[Dictionary] = [{
		"severity": "error",
		"code": "LLM_ERR_AUTH",
		"message": "Authentication failed.",
	}]
	_dock.show_errors(errs)
	assert_true(
		_dock._last_errors_text.find("Verify your API key") != -1,
		"should include fallback fix hint from ERROR_HINTS"
	)


func test_error_hints_dict_has_known_codes() -> void:
	var expected_codes: Array[String] = [
		"UI_ERR_EMPTY_PROMPT", "LLM_ERR_NETWORK", "LLM_ERR_AUTH",
		"ORCH_ERR_CANCELLED", "EXPORT_ERR_NO_SPEC",
	]
	for code: String in expected_codes:
		assert_true(
			AiSceneGenDock.ERROR_HINTS.has(code),
			"ERROR_HINTS should contain '%s'" % code
		)


func test_show_errors_multiple_creates_multiple_cards() -> void:
	var errs: Array[Dictionary] = [
		{"severity": "error", "code": "ERR_A", "message": "First error."},
		{"severity": "warning", "code": "WARN_B", "message": "Second warning."},
	]
	_dock.show_errors(errs)
	assert_eq(_dock._error_container.get_child_count(), 2, "should create 2 error cards")

# endregion

# region --- Connection test ---

func test_connection_test_signal_emitted() -> void:
	var providers: Array[String] = ["MockProvider", "Ollama"]
	_dock.set_provider_list(providers)
	_dock._provider_dropdown.select(1)
	_dock._update_connection_test_visibility()
	watch_signals(_dock)
	_dock._on_test_connection_pressed()
	assert_signal_emitted(_dock, "connection_test_requested")


func test_connection_test_signal_has_provider_name() -> void:
	var providers: Array[String] = ["MockProvider", "Ollama"]
	_dock.set_provider_list(providers)
	_dock._provider_dropdown.select(1)
	_dock._update_connection_test_visibility()
	watch_signals(_dock)
	_dock._on_test_connection_pressed()
	var params: Array = get_signal_parameters(_dock, "connection_test_requested")
	assert_eq(params[0], "Ollama", "signal should carry provider name")


func test_show_connection_result_success() -> void:
	_dock.show_connection_result(true, 5)
	assert_eq(_dock._connection_result_label.text, "Connected — 5 models")
	assert_true(_dock._connection_result_label.visible, "result label should be visible")
	assert_false(_dock._test_connection_button.disabled, "button should be re-enabled")


func test_show_connection_result_failure() -> void:
	_dock.show_connection_result(false, 0)
	assert_string_contains(_dock._connection_result_label.text, "Failed")
	assert_true(_dock._connection_result_label.visible, "result label should be visible")
	assert_false(_dock._test_connection_button.disabled, "button should be re-enabled")


func test_connection_test_button_hidden_for_mock() -> void:
	var providers: Array[String] = ["MockProvider", "Ollama"]
	_dock.set_provider_list(providers)
	assert_false(_dock._test_connection_button.visible, "button should be hidden for MockProvider")


func test_connection_test_button_visible_for_ollama() -> void:
	var providers: Array[String] = ["MockProvider", "Ollama"]
	_dock.set_provider_list(providers)
	_dock._provider_dropdown.select(1)
	_dock._update_connection_test_visibility()
	assert_true(_dock._test_connection_button.visible, "button should be visible for Ollama")


func test_connection_test_button_disabled_during_test() -> void:
	var providers: Array[String] = ["MockProvider", "Ollama"]
	_dock.set_provider_list(providers)
	_dock._provider_dropdown.select(1)
	_dock._update_connection_test_visibility()
	_dock._on_test_connection_pressed()
	assert_true(_dock._test_connection_button.disabled, "button should be disabled during test")
	assert_eq(_dock._connection_result_label.text, "Testing…", "label should show testing state")

# endregion

# region --- Provider and model lists ---

func test_set_provider_list() -> void:
	var providers: Array[String] = ["MockProvider", "Ollama"]
	_dock.set_provider_list(providers)
	assert_eq(_dock._provider_dropdown.item_count, 2, "should have 2 providers")


func test_set_model_list() -> void:
	var models: Array[String] = ["mock-outdoor", "mock-interior"]
	_dock.set_model_list(models)
	assert_eq(_dock._model_dropdown.item_count, 2, "should have 2 models")

# endregion
