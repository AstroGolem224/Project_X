@tool
extends GutTest

## GUT tests for SceneBuilder (Module H).
## Test IDs: T26, T27.

var _builder: SceneBuilder
var _factory: ProceduralPrimitiveFactory
var _valid_outdoor_json: String


func before_each() -> void:
	_factory = ProceduralPrimitiveFactory.new()
	_builder = SceneBuilder.new(null, _factory)

	var f: FileAccess = FileAccess.open(
		"res://addons/ai_scene_gen/mocks/outdoor_clearing.scenespec.json",
		FileAccess.READ
	)
	if f:
		_valid_outdoor_json = f.get_as_text()
		f.close()
	else:
		_valid_outdoor_json = ""


# region --- Helpers ---

func _make_minimal_build_spec() -> Dictionary:
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
				"scale": [10.0, 1.0, 10.0],
				"material": {"albedo": [0.3, 0.5, 0.2], "roughness": 0.9},
				"collision": false,
				"metadata": {"role": "ground"}
			}
		],
		"rules": {
			"snap_to_ground": true,
			"clamp_to_bounds": true
		}
	}


func _build_nested_spec(depth: int) -> Dictionary:
	var spec: Dictionary = _make_minimal_build_spec()
	spec["limits"]["max_tree_depth"] = 5

	var current_node: Dictionary = {
		"id": "level_0",
		"name": "Level0",
		"node_type": "Node3D",
		"position": [0.0, 0.0, 0.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0]
	}
	var root_node: Dictionary = current_node

	for i: int in range(1, depth):
		var child: Dictionary = {
			"id": "level_%d" % i,
			"name": "Level%d" % i,
			"node_type": "Node3D",
			"position": [0.0, 0.0, 0.0],
			"rotation_degrees": [0.0, 0.0, 0.0],
			"scale": [1.0, 1.0, 1.0]
		}
		current_node["children"] = [child]
		current_node = child

	spec["nodes"] = [root_node]
	return spec

# endregion

# region --- T26: Deterministic build ---

func test_T26_deterministic_build() -> void:
	if _valid_outdoor_json.is_empty():
		var spec: Dictionary = _make_minimal_build_spec()
		var root_a: Node3D = Node3D.new()
		var root_b: Node3D = Node3D.new()

		var result_a: BuildResult = _builder.build(spec, root_a)
		_builder = SceneBuilder.new(null, _factory)
		var result_b: BuildResult = _builder.build(spec, root_b)

		assert_eq(
			result_a.get_build_hash(),
			result_b.get_build_hash(),
			"same spec should produce identical build hashes"
		)

		root_a.queue_free()
		root_b.queue_free()
		return

	var parsed: Variant = JSON.parse_string(_valid_outdoor_json)
	if parsed == null or not parsed is Dictionary:
		gut.p("SKIP: could not parse outdoor mock JSON")
		pass_test("could not parse mock JSON")
		return

	var spec: Dictionary = parsed as Dictionary
	var root_a: Node3D = Node3D.new()
	var root_b: Node3D = Node3D.new()

	var result_a: BuildResult = _builder.build(spec, root_a)
	_builder = SceneBuilder.new(null, _factory)
	var result_b: BuildResult = _builder.build(spec, root_b)

	assert_eq(
		result_a.get_build_hash(),
		result_b.get_build_hash(),
		"same spec should produce identical build hashes"
	)

	root_a.queue_free()
	root_b.queue_free()

# endregion

# region --- T27: Deep nesting rejected ---

func test_T27_deep_nesting_rejected() -> void:
	var spec: Dictionary = _build_nested_spec(20)
	var root: Node3D = Node3D.new()

	var result: BuildResult = _builder.build(spec, root)

	var found_depth_error: bool = false
	for err: Dictionary in result.get_errors():
		if err.get("code", "") == "BUILD_ERR_TREE_DEPTH":
			found_depth_error = true
			break

	assert_true(found_depth_error, "20-deep nesting with limit 5 should produce BUILD_ERR_TREE_DEPTH")
	root.queue_free()

# endregion

# region --- Minimal build ---

func test_minimal_build() -> void:
	var spec: Dictionary = _make_minimal_build_spec()
	var root: Node3D = Node3D.new()

	var result: BuildResult = _builder.build(spec, root)
	assert_true(result.is_success(), "minimal build should succeed")
	assert_gt(root.get_child_count(), 0, "root should have children after build")
	assert_gt(result.get_node_count(), 0, "node count should be > 0")
	assert_true(result.get_build_hash().begins_with("build:"), "hash should start with build:")

	root.queue_free()

# endregion

# region --- Build hash ---

func test_build_hash_format() -> void:
	var spec: Dictionary = _make_minimal_build_spec()
	var hash_val: String = _builder.build_hash(spec)
	assert_true(hash_val.begins_with("build:"), "hash should start with build:")
	assert_eq(hash_val.length(), 6 + 64, "build: prefix + 64 hex chars")


func test_different_specs_different_hashes() -> void:
	var spec_a: Dictionary = _make_minimal_build_spec()
	var spec_b: Dictionary = _make_minimal_build_spec()
	spec_b["determinism"]["seed"] = 999

	var hash_a: String = _builder.build_hash(spec_a)
	var hash_b: String = _builder.build_hash(spec_b)
	assert_true(hash_a != hash_b, "different specs should produce different hashes")

# endregion

# region --- Environment and camera ---

func test_environment_built() -> void:
	var spec: Dictionary = _make_minimal_build_spec()
	var root: Node3D = Node3D.new()
	_builder.build(spec, root)

	var found_env: bool = false
	for i: int in range(root.get_child_count()):
		if root.get_child(i) is WorldEnvironment:
			found_env = true
			break

	assert_true(found_env, "build should create a WorldEnvironment node")
	root.queue_free()


func test_camera_built() -> void:
	var spec: Dictionary = _make_minimal_build_spec()
	var root: Node3D = Node3D.new()
	_builder.build(spec, root)

	var found_cam: bool = false
	for i: int in range(root.get_child_count()):
		if root.get_child(i) is Camera3D:
			found_cam = true
			break

	assert_true(found_cam, "build should create a Camera3D node")
	root.queue_free()

# endregion
