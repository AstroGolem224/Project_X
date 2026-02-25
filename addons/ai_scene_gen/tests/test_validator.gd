@tool
extends GutTest

## GUT tests for SceneSpecValidator (Module E).
## Test IDs: T01-T13, T38, T39.

var _validator: SceneSpecValidator
var _valid_outdoor_json: String
var _valid_interior_json: String


func before_each() -> void:
	_validator = SceneSpecValidator.new()

	var f1: FileAccess = FileAccess.open(
		"res://addons/ai_scene_gen/mocks/outdoor_clearing.scenespec.json",
		FileAccess.READ
	)
	if f1:
		_valid_outdoor_json = f1.get_as_text()
		f1.close()

	var f2: FileAccess = FileAccess.open(
		"res://addons/ai_scene_gen/mocks/interior_room.scenespec.json",
		FileAccess.READ
	)
	if f2:
		_valid_interior_json = f2.get_as_text()
		f2.close()


# region --- Helpers ---

func _make_minimal_valid_spec() -> Dictionary:
	return {
		"spec_version": "1.0.0",
		"meta": {
			"generator": "ai_scene_gen",
			"style_preset": "blockout",
			"bounds_meters": [50.0, 20.0, 50.0],
			"prompt_hash": "sha256:" + "a".repeat(64),
			"timestamp_utc": "2026-01-01T00:00:00Z"
		},
		"determinism": {
			"seed": 42,
			"variation_mode": false,
			"fingerprint": "abcdef1234567890"
		},
		"limits": {
			"max_nodes": 256,
			"max_scale_component": 50.0,
			"max_light_energy": 16.0,
			"max_tree_depth": 16,
			"poly_budget_triangles": 50000
		},
		"environment": {
			"sky_type": "procedural",
			"sky_color_top": [0.3, 0.5, 0.9],
			"sky_color_bottom": [0.7, 0.8, 1.0],
			"ambient_light_color": [1.0, 1.0, 1.0],
			"ambient_light_energy": 0.5,
			"fog_enabled": false,
			"fog_density": 0.0
		},
		"camera": {
			"position": [0.0, 5.0, 10.0],
			"look_at": [0.0, 0.0, 0.0],
			"fov_degrees": 70.0
		},
		"lights": [
			{
				"id": "sun",
				"type": "DirectionalLight3D",
				"rotation_degrees": [-45.0, 30.0, 0.0],
				"color": [1.0, 0.95, 0.8],
				"energy": 1.0,
				"shadow_enabled": true
			}
		],
		"nodes": [
			{
				"id": "ground",
				"name": "Ground",
				"node_type": "MeshInstance3D",
				"primitive_shape": "plane",
				"position": [0.0, 0.0, 0.0],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [50.0, 1.0, 50.0],
				"material": {"albedo": [0.3, 0.5, 0.2], "roughness": 0.9},
				"collision": true,
				"metadata": {"role": "ground"}
			}
		],
		"rules": {
			"snap_to_ground": true,
			"clamp_to_bounds": true
		}
	}


func _make_node(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"id": "test_node",
		"name": "TestNode",
		"node_type": "MeshInstance3D",
		"primitive_shape": "box",
		"position": [0.0, 1.0, 0.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0],
		"material": {"albedo": [0.5, 0.5, 0.5], "roughness": 0.5},
		"collision": false
	}
	for key: String in overrides.keys():
		base[key] = overrides[key]
	return base


func _has_error_code(result: ValidationResult, code: String) -> bool:
	for err: Dictionary in result.get_errors():
		if err.get("code", "") == code:
			return true
	return false

# endregion

# region --- T01-T02: Valid spec tests ---

func test_T01_valid_outdoor_spec_passes() -> void:
	if _valid_outdoor_json.is_empty():
		gut.p("SKIP: outdoor mock file not found")
		pass_test("mock file not available, skipping")
		return
	var result: ValidationResult = _validator.validate_json_string(_valid_outdoor_json)
	assert_true(result.is_valid(), "outdoor spec should pass validation")
	assert_eq(result.get_errors().size(), 0, "should have zero errors")


func test_T02_valid_interior_spec_passes() -> void:
	if _valid_interior_json.is_empty():
		gut.p("SKIP: interior mock file not found")
		pass_test("mock file not available, skipping")
		return
	var result: ValidationResult = _validator.validate_json_string(_valid_interior_json)
	assert_true(result.is_valid(), "interior spec should pass validation")

# endregion

# region --- T03: Parse errors ---

func test_T03_empty_json_string_fails() -> void:
	var result: ValidationResult = _validator.validate_json_string("")
	assert_false(result.is_valid(), "empty string should fail")
	assert_true(_has_error_code(result, "SPEC_ERR_PARSE"), "should contain SPEC_ERR_PARSE")
	assert_engine_error_count(1)

# endregion

# region --- T04: Missing fields ---

func test_T04_missing_spec_version_fails() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec.erase("spec_version")
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "missing spec_version should fail")
	assert_true(_has_error_code(result, "SPEC_ERR_PARSE"), "should report missing field")

# endregion

# region --- T05: Node count limit ---

func test_T05_node_count_exceeds_limit() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["limits"]["max_nodes"] = 256

	var big_nodes: Array = []
	for i: int in range(300):
		big_nodes.append(_make_node({"id": "n_%d" % i, "name": "Node%d" % i}))
	spec["nodes"] = big_nodes

	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "300 nodes with limit 256 should fail")
	assert_true(_has_error_code(result, "SPEC_ERR_LIMIT_NODES"), "should report SPEC_ERR_LIMIT_NODES")

# endregion

# region --- T06: Position out of bounds ---

func test_T06_position_out_of_bounds() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["meta"]["bounds_meters"] = [50.0, 50.0, 50.0]
	spec["nodes"] = [_make_node({"position": [999.0, 0.0, 0.0]})]

	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "position [999,0,0] out of bounds [50,50,50]")
	assert_true(_has_error_code(result, "SPEC_ERR_BOUNDS"), "should report SPEC_ERR_BOUNDS")

# endregion

# region --- T07: Disallowed node type ---

func test_T07_disallowed_node_type() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node({"node_type": "GDScript"})]

	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "GDScript node_type should be rejected")
	assert_true(_has_error_code(result, "SPEC_ERR_NODE_TYPE"), "should report SPEC_ERR_NODE_TYPE")

# endregion

# region --- T08: Disallowed primitive shape ---

func test_T08_disallowed_primitive_shape() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node({"primitive_shape": "script"})]

	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "primitive_shape 'script' should be rejected")
	assert_true(_has_error_code(result, "SPEC_ERR_PRIMITIVE"), "should report SPEC_ERR_PRIMITIVE")

# endregion

# region --- T09: Light energy exceeds max ---

func test_T09_light_energy_exceeds_max() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["limits"]["max_light_energy"] = 16.0
	spec["lights"] = [{
		"id": "hot_light",
		"type": "OmniLight3D",
		"rotation_degrees": [0.0, 0.0, 0.0],
		"color": [1.0, 1.0, 1.0],
		"energy": 99.0,
		"shadow_enabled": false
	}]

	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "energy 99 with max 16 should fail")
	assert_true(_has_error_code(result, "SPEC_ERR_LIMIT_ENERGY"), "should report SPEC_ERR_LIMIT_ENERGY")

# endregion

# region --- T10: Scale exceeds max ---

func test_T10_scale_exceeds_max() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["limits"]["max_scale_component"] = 50.0
	spec["nodes"] = [_make_node({"scale": [200.0, 1.0, 1.0]})]

	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "scale 200 with max 50 should fail")
	assert_true(_has_error_code(result, "SPEC_ERR_LIMIT_SCALE"), "should report SPEC_ERR_LIMIT_SCALE")

# endregion

# region --- T11: Duplicate node IDs ---

func test_T11_duplicate_node_ids() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [
		_make_node({"id": "rock", "name": "Rock1"}),
		_make_node({"id": "rock", "name": "Rock2"})
	]

	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "duplicate id 'rock' should fail")
	assert_true(_has_error_code(result, "SPEC_ERR_DUPLICATE_ID"), "should report SPEC_ERR_DUPLICATE_ID")

# endregion

# region --- T12: Code pattern in name ---

func test_T12_code_pattern_in_name() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node({"name": "eval(malicious)"})]

	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "name with eval( should fail")
	assert_true(_has_error_code(result, "SPEC_ERR_CODE_PATTERN"), "should report SPEC_ERR_CODE_PATTERN")

# endregion

# region --- T13: Additional unknown field ---

func test_T13_additional_unknown_field() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	var node: Dictionary = _make_node()
	node["evil_field"] = true
	spec["nodes"] = [node]

	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "unknown field should fail")
	assert_true(_has_error_code(result, "SPEC_ERR_ADDITIONAL_FIELD"), "should report SPEC_ERR_ADDITIONAL_FIELD")

# endregion

# region --- T38: Random dicts don't crash ---

func test_T38_random_dicts_dont_crash() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345

	for i: int in range(100):
		var random_dict: Dictionary = {}
		var key_count: int = rng.randi_range(0, 10)
		for j: int in range(key_count):
			var key: String = "field_%d" % rng.randi_range(0, 999)
			match rng.randi_range(0, 3):
				0:
					random_dict[key] = rng.randi()
				1:
					random_dict[key] = "str_%d" % rng.randi()
				2:
					random_dict[key] = rng.randf()
				3:
					random_dict[key] = rng.randi() % 2 == 0

		var result: ValidationResult = _validator.validate_spec(random_dict)
		assert_not_null(result, "iteration %d should return a result, not crash" % i)

# endregion

# region --- T39: Injection in name ---

func test_T39_injection_in_name_is_safe() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node({"name": "'; DROP TABLE; --"})]

	var result: ValidationResult = _validator.validate_spec(spec)
	assert_not_null(result, "SQL-injection name should not crash the validator")

# endregion

# region --- Extra validation coverage ---

func test_malformed_json_object_fails() -> void:
	var result: ValidationResult = _validator.validate_json_string("{invalid json}")
	assert_false(result.is_valid(), "malformed JSON should fail")
	assert_true(_has_error_code(result, "SPEC_ERR_PARSE"))
	assert_engine_error_count(1)


func test_json_array_root_fails() -> void:
	var result: ValidationResult = _validator.validate_json_string("[1, 2, 3]")
	assert_false(result.is_valid(), "array root should fail")
	assert_true(_has_error_code(result, "SPEC_ERR_PARSE"))


func test_minimal_valid_spec_passes() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_true(result.is_valid(), "minimal valid spec should pass")
	assert_eq(result.get_errors().size(), 0)


func test_wrong_spec_version_fails() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["spec_version"] = "99.0.0"
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "wrong spec version should fail")

# endregion
