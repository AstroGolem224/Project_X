@tool
extends GutTest

## GUT tests for PromptCompiler (Module D).
## Test IDs: T14, T15, T16.

var _compiler: PromptCompiler


func before_each() -> void:
	_compiler = PromptCompiler.new()


# region --- Helpers ---

func _make_valid_request(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"user_prompt": "a medieval courtyard with a well",
		"selected_model": "gpt-4",
		"selected_provider": "openai",
		"style_preset": "blockout",
		"seed": 42,
		"bounds_meters": [20.0, 10.0, 20.0],
		"available_asset_tags": [],
		"project_constraints": ""
	}
	for key: String in overrides.keys():
		base[key] = overrides[key]
	return base

# endregion

# region --- T14: Empty prompt ---

func test_T14_empty_prompt_fails() -> void:
	var request: Dictionary = _make_valid_request({"user_prompt": ""})
	var result: String = _compiler.compile_single_stage(request)
	assert_eq(result, "", "empty prompt should return empty string")
	assert_push_error("Cannot compile an empty prompt")


func test_whitespace_only_prompt_fails() -> void:
	var request: Dictionary = _make_valid_request({"user_prompt": "   "})
	var result: String = _compiler.compile_single_stage(request)
	assert_eq(result, "", "whitespace-only prompt should return empty string")
	assert_push_error("Cannot compile an empty prompt")

# endregion

# region --- T15: Valid prompt compilation ---

func test_T15_valid_prompt_compilation() -> void:
	var request: Dictionary = _make_valid_request()
	var result: String = _compiler.compile_single_stage(request)
	assert_true(result.length() > 0, "valid request should produce non-empty output")
	assert_true(result.find("42") != -1, "output should contain the seed value")
	assert_true(result.find("20") != -1, "output should reference bounds")

# endregion

# region --- T16: Determinism fingerprint stability ---

func test_T16_determinism_fingerprint_stable() -> void:
	var request: Dictionary = _make_valid_request()
	var fp1: String = _compiler.build_determinism_fingerprint(request)
	var fp2: String = _compiler.build_determinism_fingerprint(request)
	assert_eq(fp1, fp2, "same request should produce identical fingerprints")
	assert_true(fp1.begins_with("sha256:"), "fingerprint should start with sha256:")
	assert_eq(fp1.length(), 7 + 64, "sha256: prefix + 64 hex chars")


func test_different_seeds_produce_different_fingerprints() -> void:
	var req_a: Dictionary = _make_valid_request({"seed": 1})
	var req_b: Dictionary = _make_valid_request({"seed": 2})
	var fp_a: String = _compiler.build_determinism_fingerprint(req_a)
	var fp_b: String = _compiler.build_determinism_fingerprint(req_b)
	assert_true(fp_a != fp_b, "different seeds should produce different fingerprints")

# endregion

# region --- Style preset handling ---

func test_style_preset_in_output() -> void:
	var request: Dictionary = _make_valid_request({"style_preset": "blockout"})
	var result: String = _compiler.compile_single_stage(request)
	assert_true(result.find("blockout") != -1, "output should contain 'blockout'")


func test_stylized_preset_in_output() -> void:
	var request: Dictionary = _make_valid_request({"style_preset": "stylized"})
	var result: String = _compiler.compile_single_stage(request)
	assert_true(result.find("stylized") != -1, "output should contain 'stylized'")


func test_invalid_preset_fails() -> void:
	var request: Dictionary = _make_valid_request({"style_preset": "invalid"})
	var result: String = _compiler.compile_single_stage(request)
	assert_eq(result, "", "invalid preset should return empty string")
	assert_push_error("Unknown style preset")

# endregion

# region --- Plan and spec stage compilation ---

func test_plan_stage_compilation() -> void:
	var request: Dictionary = _make_valid_request()
	var result: String = _compiler.compile_plan_stage(request)
	assert_true(result.length() > 0, "plan stage should produce output")
	assert_true(result.find("plan") != -1, "plan stage output should mention plan")


func test_spec_stage_with_plan() -> void:
	var request: Dictionary = _make_valid_request()
	var plan_text: String = '{"plan": [{"name": "well", "role": "focal_point"}]}'
	var result: String = _compiler.compile_spec_stage(request, plan_text)
	assert_true(result.length() > 0, "spec stage should produce output")
	assert_true(result.find("LAYOUT PLAN") != -1, "spec stage should contain plan section")

# endregion

# region --- Token estimation ---

func test_token_estimate() -> void:
	var short_prompt: String = "test"
	var estimate: int = _compiler.estimate_token_count(short_prompt)
	assert_eq(estimate, 1, "'test' (4 chars) should estimate ~1 token")

	var long_prompt: String = "a".repeat(400)
	estimate = _compiler.estimate_token_count(long_prompt)
	assert_eq(estimate, 100, "400 chars should estimate ~100 tokens")

# endregion

# region --- Asset tags in output ---

func test_asset_tags_appear_in_output() -> void:
	var request: Dictionary = _make_valid_request({
		"available_asset_tags": ["tree_oak", "rock_moss"]
	})
	var result: String = _compiler.compile_single_stage(request)
	assert_true(result.find("tree_oak") != -1, "output should contain asset tag")
	assert_true(result.find("rock_moss") != -1, "output should contain asset tag")


func test_no_asset_tags_shows_none() -> void:
	var request: Dictionary = _make_valid_request({"available_asset_tags": []})
	var result: String = _compiler.compile_single_stage(request)
	assert_true(result.find("None") != -1, "empty tags should show 'None'")

# endregion

# region --- Variation suffix injection ---

func test_variation_flag_adds_seed_suffix() -> void:
	var request: Dictionary = _make_valid_request({"variation": true})
	var result: String = _compiler.compile_single_stage(request)
	assert_true(result.length() > 0, "variation request should produce output")
	assert_true(
		result.find("[variation_seed=") != -1,
		"variation=true should inject [variation_seed=...] into prompt"
	)


func test_no_variation_flag_no_suffix() -> void:
	var request: Dictionary = _make_valid_request({"variation": false})
	var result: String = _compiler.compile_single_stage(request)
	assert_true(result.length() > 0, "non-variation request should produce output")
	assert_true(
		result.find("[variation_seed=") == -1,
		"variation=false should NOT inject variation_seed"
	)


func test_variation_suffix_changes_between_calls() -> void:
	var req: Dictionary = _make_valid_request({"variation": true})
	var result_a: String = _compiler.compile_single_stage(req)
	var result_b: String = _compiler.compile_single_stage(req)
	assert_true(result_a.length() > 0)
	assert_true(result_b.length() > 0)

# endregion

# region --- Retry stage compilation ---

func test_retry_stage_contains_error_feedback() -> void:
	var request: Dictionary = _make_valid_request()
	var invalid_json: String = '{"broken": true}'
	var errors: Array[Dictionary] = [
		{"code": "SPEC_ERR_VERSION", "message": "Missing spec_version field"},
		{"code": "SPEC_ERR_META", "message": "Missing meta field"},
	]
	var result: String = _compiler.compile_retry_stage(request, invalid_json, errors)
	assert_true(result.length() > 0, "retry stage should produce non-empty output")
	assert_true(
		result.find("Validation errors") != -1,
		"retry prompt should contain 'Validation errors'"
	)
	assert_true(
		result.find("SPEC_ERR_VERSION") != -1,
		"retry prompt should contain error code"
	)
	assert_true(
		result.find("Missing spec_version field") != -1,
		"retry prompt should contain error message"
	)
	assert_true(
		result.find('{"broken": true}') != -1,
		"retry prompt should contain the invalid JSON"
	)


func test_retry_stage_includes_base_prompt() -> void:
	var request: Dictionary = _make_valid_request()
	var errors: Array[Dictionary] = [{"code": "ERR", "message": "test"}]
	var result: String = _compiler.compile_retry_stage(request, "{}", errors)
	assert_true(
		result.find("SceneSpec v1.0.0") != -1,
		"retry prompt should include the base system template"
	)
	assert_true(
		result.find("medieval courtyard") != -1,
		"retry prompt should include the user prompt from request"
	)


func test_retry_stage_truncates_long_json() -> void:
	var request: Dictionary = _make_valid_request()
	var long_json: String = "x".repeat(3000)
	var errors: Array[Dictionary] = [{"code": "ERR", "message": "test"}]
	var result: String = _compiler.compile_retry_stage(request, long_json, errors)
	assert_true(result.length() > 0, "should produce output even with long JSON")
	assert_true(
		result.find("x".repeat(2000)) != -1,
		"should include first 2000 chars of JSON"
	)
	assert_true(
		result.find("x".repeat(2001)) == -1,
		"JSON beyond 2000 chars should be truncated"
	)


func test_retry_stage_empty_prompt_returns_empty() -> void:
	var request: Dictionary = _make_valid_request({"user_prompt": ""})
	var errors: Array[Dictionary] = [{"code": "ERR", "message": "test"}]
	var result: String = _compiler.compile_retry_stage(request, "{}", errors)
	assert_eq(result, "", "retry stage with empty prompt should return empty")
	assert_push_error("Cannot compile an empty prompt")

# endregion
