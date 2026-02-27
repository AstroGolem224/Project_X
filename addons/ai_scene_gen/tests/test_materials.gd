@tool
extends GutTest

## GUT tests for Advanced Materials (Prio 16).
## Tests material presets, PBR property creation, validator extensions,
## builder integration, and dock UI material controls.

var _factory: ProceduralPrimitiveFactory
var _validator: SceneSpecValidator
var _builder: SceneBuilder

const POS_TOLERANCE: float = 0.001
const COLOR_TOLERANCE: float = 0.01


func before_each() -> void:
	_factory = ProceduralPrimitiveFactory.new()
	_validator = SceneSpecValidator.new()
	_builder = SceneBuilder.new(null, _factory)


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
		"nodes": [],
		"rules": {
			"snap_to_ground": true,
			"clamp_to_bounds": true
		}
	}


func _make_node_with_material(mat: Dictionary) -> Dictionary:
	return {
		"id": "test_node",
		"name": "TestNode",
		"node_type": "MeshInstance3D",
		"primitive_shape": "box",
		"position": [0.0, 0.0, 0.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0],
		"material": mat,
		"collision": false,
		"metadata": {"role": "ground"}
	}


func _get_mesh_material(node: Node3D) -> StandardMaterial3D:
	for i: int in range(node.get_child_count()):
		var child: Node = node.get_child(i)
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			if mi.material_override is StandardMaterial3D:
				return mi.material_override as StandardMaterial3D
	return null

# endregion


# region --- Factory: Material Presets ---

func test_all_preset_names_available() -> void:
	var names: Array[String] = _factory.get_preset_names()
	assert_gt(names.size(), 0, "should have presets")
	assert_has(names, "wood", "should have wood")
	assert_has(names, "metal", "should have metal")
	assert_has(names, "glass", "should have glass")
	assert_has(names, "gold", "should have gold")
	assert_has(names, "lava", "should have lava")
	assert_has(names, "neon", "should have neon")


func test_get_preset_returns_dict() -> void:
	var wood: Dictionary = _factory.get_preset("wood")
	assert_false(wood.is_empty(), "wood preset should not be empty")
	assert_true(wood.has("albedo"), "preset should have albedo")
	assert_true(wood.has("roughness"), "preset should have roughness")
	assert_true(wood.has("metallic"), "preset should have metallic")


func test_get_unknown_preset_returns_empty() -> void:
	var unknown: Dictionary = _factory.get_preset("unicorn_dust")
	assert_true(unknown.is_empty(), "unknown preset should return empty dict")


func test_is_allowed_preset() -> void:
	assert_true(_factory.is_allowed_preset("stone"), "stone should be allowed")
	assert_true(_factory.is_allowed_preset("chrome"), "chrome should be allowed")
	assert_false(_factory.is_allowed_preset("unobtanium"), "unobtanium should not be allowed")

# endregion


# region --- Factory: create_material_from_spec ---

func test_material_from_spec_basic() -> void:
	var mat: Dictionary = {"albedo": [1.0, 0.0, 0.0], "roughness": 0.7}
	var material: StandardMaterial3D = _factory.create_material_from_spec(mat)
	assert_not_null(material, "should create material")
	assert_almost_eq(material.albedo_color.r, 1.0, COLOR_TOLERANCE, "red channel")
	assert_almost_eq(material.albedo_color.g, 0.0, COLOR_TOLERANCE, "green channel")
	assert_almost_eq(material.roughness, 0.7, COLOR_TOLERANCE, "roughness")
	assert_almost_eq(material.metallic, 0.0, COLOR_TOLERANCE, "metallic default")


func test_material_from_spec_metallic() -> void:
	var mat: Dictionary = {"albedo": [0.5, 0.5, 0.5], "roughness": 0.2, "metallic": 0.9}
	var material: StandardMaterial3D = _factory.create_material_from_spec(mat)
	assert_almost_eq(material.metallic, 0.9, COLOR_TOLERANCE, "metallic")
	assert_almost_eq(material.roughness, 0.2, COLOR_TOLERANCE, "roughness")


func test_material_from_spec_emission() -> void:
	var mat: Dictionary = {
		"albedo": [0.1, 0.1, 0.1],
		"roughness": 0.5,
		"emission": [1.0, 0.5, 0.0],
		"emission_energy": 3.0
	}
	var material: StandardMaterial3D = _factory.create_material_from_spec(mat)
	assert_true(material.emission_enabled, "emission should be enabled")
	assert_almost_eq(material.emission.r, 1.0, COLOR_TOLERANCE, "emission red")
	assert_almost_eq(material.emission.g, 0.5, COLOR_TOLERANCE, "emission green")
	assert_almost_eq(material.emission_energy_multiplier, 3.0, COLOR_TOLERANCE, "emission energy")


func test_material_from_spec_transparency() -> void:
	var mat: Dictionary = {"albedo": [0.9, 0.9, 1.0], "roughness": 0.1, "transparency": 0.7}
	var material: StandardMaterial3D = _factory.create_material_from_spec(mat)
	assert_eq(material.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "transparency mode")
	assert_almost_eq(material.albedo_color.a, 0.3, COLOR_TOLERANCE, "alpha = 1 - transparency")


func test_material_from_spec_preset_only() -> void:
	var mat: Dictionary = {"preset": "gold"}
	var material: StandardMaterial3D = _factory.create_material_from_spec(mat)
	assert_almost_eq(material.metallic, 1.0, COLOR_TOLERANCE, "gold metallic")
	assert_almost_eq(material.albedo_color.r, 1.0, COLOR_TOLERANCE, "gold albedo.r")
	assert_almost_eq(material.roughness, 0.2, COLOR_TOLERANCE, "gold roughness")


func test_material_from_spec_preset_with_override() -> void:
	var mat: Dictionary = {"preset": "metal", "roughness": 0.8}
	var material: StandardMaterial3D = _factory.create_material_from_spec(mat)
	assert_almost_eq(material.metallic, 0.95, COLOR_TOLERANCE, "metal metallic from preset")
	assert_almost_eq(material.roughness, 0.8, COLOR_TOLERANCE, "roughness overridden")


func test_material_from_spec_unknown_preset_ignored() -> void:
	var mat: Dictionary = {"preset": "unobtanium", "albedo": [0.5, 0.5, 0.5], "roughness": 0.5}
	var material: StandardMaterial3D = _factory.create_material_from_spec(mat)
	assert_almost_eq(material.albedo_color.r, 0.5, COLOR_TOLERANCE, "should use explicit albedo")
	assert_almost_eq(material.roughness, 0.5, COLOR_TOLERANCE, "should use explicit roughness")

# endregion


# region --- Factory: create_primitive_with_material ---

func test_primitive_with_material_basic() -> void:
	var mat: Dictionary = {"albedo": [0.3, 0.6, 0.1], "roughness": 0.9}
	var node: Node3D = _factory.create_primitive_with_material(
		"box", Vector3(2.0, 2.0, 2.0), mat, false
	)
	assert_not_null(node, "should create primitive")
	var m: StandardMaterial3D = _get_mesh_material(node)
	assert_not_null(m, "should have material")
	assert_almost_eq(m.albedo_color.r, 0.3, COLOR_TOLERANCE, "albedo.r")
	assert_almost_eq(m.roughness, 0.9, COLOR_TOLERANCE, "roughness")
	node.free()


func test_primitive_with_material_preset() -> void:
	var mat: Dictionary = {"preset": "glass"}
	var node: Node3D = _factory.create_primitive_with_material(
		"sphere", Vector3(1.0, 1.0, 1.0), mat, false
	)
	assert_not_null(node, "should create glass sphere")
	var m: StandardMaterial3D = _get_mesh_material(node)
	assert_eq(m.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "glass transparency")
	assert_almost_eq(m.roughness, 0.05, COLOR_TOLERANCE, "glass roughness")
	node.free()


func test_primitive_with_material_unknown_shape_rejected() -> void:
	var mat: Dictionary = {"albedo": [0.5, 0.5, 0.5], "roughness": 0.5}
	var node: Node3D = _factory.create_primitive_with_material(
		"hexagon", Vector3(1.0, 1.0, 1.0), mat, false
	)
	assert_null(node, "unknown shape should return null")


func test_primitive_with_material_invalid_size_rejected() -> void:
	var mat: Dictionary = {"albedo": [0.5, 0.5, 0.5], "roughness": 0.5}
	var node: Node3D = _factory.create_primitive_with_material(
		"box", Vector3(0.0, 1.0, 1.0), mat, false
	)
	assert_null(node, "zero size should return null")


func test_primitive_with_material_lava_emission() -> void:
	var mat: Dictionary = {"preset": "lava"}
	var node: Node3D = _factory.create_primitive_with_material(
		"sphere", Vector3(2.0, 2.0, 2.0), mat, false
	)
	assert_not_null(node, "should create lava sphere")
	var m: StandardMaterial3D = _get_mesh_material(node)
	assert_true(m.emission_enabled, "lava should have emission")
	assert_gt(m.emission_energy_multiplier, 0.0, "lava emission energy > 0")
	node.free()

# endregion


# region --- Validator: Extended Material Fields ---

func test_validator_accepts_basic_material() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({"albedo": [0.5, 0.5, 0.5], "roughness": 0.5})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_true(result.is_valid(), "basic material should pass")


func test_validator_accepts_full_pbr_material() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5],
		"roughness": 0.3,
		"metallic": 0.9,
		"emission": [1.0, 0.5, 0.0],
		"emission_energy": 2.0,
		"normal_scale": 1.5,
		"transparency": 0.3,
		"preset": "metal"
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_true(result.is_valid(), "full PBR material should pass")


func test_validator_rejects_metallic_out_of_range() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5, "metallic": 1.5
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "metallic 1.5 should fail")


func test_validator_rejects_emission_energy_out_of_range() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"emission": [1.0, 0.0, 0.0], "emission_energy": 20.0
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "emission_energy 20 should fail")


func test_validator_rejects_transparency_out_of_range() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5, "transparency": -0.1
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "negative transparency should fail")


func test_validator_rejects_normal_scale_out_of_range() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5, "normal_scale": 3.0
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "normal_scale 3.0 should fail")


func test_validator_rejects_unknown_preset() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5, "preset": "unobtanium"
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "unknown preset should fail")


func test_validator_accepts_valid_preset() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5, "preset": "gold"
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_true(result.is_valid(), "gold preset should pass")


func test_validator_rejects_unknown_material_field() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5, "sparkle_factor": 9000
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "unknown material field should fail")


func test_validator_rejects_invalid_emission_color() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"emission": [2.0, 0.0, 0.0], "emission_energy": 1.0
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "emission color > 1.0 should fail")

# endregion


# region --- Builder: PBR Material Integration ---

func test_builder_applies_metallic() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.6, 0.6, 0.6], "roughness": 0.2, "metallic": 0.95
	})]
	var root: Node3D = Node3D.new()
	var result: BuildResult = _builder.build(spec, root)
	assert_true(result.is_success(), "build should succeed")

	var test_node: Node3D = null
	for i: int in range(root.get_child_count()):
		if str(root.get_child(i).name) == "TestNode":
			test_node = root.get_child(i) as Node3D
			break
	assert_not_null(test_node, "TestNode should exist")
	if test_node != null:
		var m: StandardMaterial3D = _get_mesh_material(test_node)
		assert_not_null(m, "should have material")
		if m != null:
			assert_almost_eq(m.metallic, 0.95, COLOR_TOLERANCE, "metallic applied")
			assert_almost_eq(m.roughness, 0.2, COLOR_TOLERANCE, "roughness applied")
	root.queue_free()


func test_builder_applies_preset() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({"preset": "gold"})]
	var root: Node3D = Node3D.new()
	var result: BuildResult = _builder.build(spec, root)
	assert_true(result.is_success(), "build with preset should succeed")

	var test_node: Node3D = null
	for i: int in range(root.get_child_count()):
		if str(root.get_child(i).name) == "TestNode":
			test_node = root.get_child(i) as Node3D
			break
	assert_not_null(test_node, "TestNode should exist")
	if test_node != null:
		var m: StandardMaterial3D = _get_mesh_material(test_node)
		assert_not_null(m, "should have material")
		if m != null:
			assert_almost_eq(m.metallic, 1.0, COLOR_TOLERANCE, "gold metallic")
	root.queue_free()


func test_builder_applies_transparency() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.9, 0.93, 0.95], "roughness": 0.05, "transparency": 0.8
	})]
	var root: Node3D = Node3D.new()
	var result: BuildResult = _builder.build(spec, root)
	assert_true(result.is_success(), "build with transparency should succeed")

	var test_node: Node3D = null
	for i: int in range(root.get_child_count()):
		if str(root.get_child(i).name) == "TestNode":
			test_node = root.get_child(i) as Node3D
			break
	if test_node != null:
		var m: StandardMaterial3D = _get_mesh_material(test_node)
		if m != null:
			assert_eq(m.transparency, BaseMaterial3D.TRANSPARENCY_ALPHA, "transparency mode")
			assert_almost_eq(m.albedo_color.a, 0.2, COLOR_TOLERANCE, "alpha")
	root.queue_free()


func test_builder_fallback_albedo_roughness_only() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.3, 0.5, 0.2], "roughness": 0.9
	})]
	var root: Node3D = Node3D.new()
	var result: BuildResult = _builder.build(spec, root)
	assert_true(result.is_success(), "basic material should still work")

	var test_node: Node3D = null
	for i: int in range(root.get_child_count()):
		if str(root.get_child(i).name) == "TestNode":
			test_node = root.get_child(i) as Node3D
			break
	if test_node != null:
		var m: StandardMaterial3D = _get_mesh_material(test_node)
		if m != null:
			assert_almost_eq(m.albedo_color.r, 0.3, COLOR_TOLERANCE, "albedo.r")
			assert_almost_eq(m.roughness, 0.9, COLOR_TOLERANCE, "roughness")
			assert_almost_eq(m.metallic, 0.0, COLOR_TOLERANCE, "metallic default 0")
	root.queue_free()

# endregion


# region --- Golden: Updated Mock Specs Still Valid ---

func test_golden_outdoor_with_pbr_fields_valid() -> void:
	var f: FileAccess = FileAccess.open(
		"res://addons/ai_scene_gen/mocks/outdoor_clearing.scenespec.json",
		FileAccess.READ
	)
	if f == null:
		pass_test("mock file not found — skip")
		return
	var json: String = f.get_as_text()
	f.close()
	var result: ValidationResult = _validator.validate_json_string(json)
	assert_true(result.is_valid(), "updated outdoor spec should still validate")


func test_golden_interior_with_pbr_fields_valid() -> void:
	var f: FileAccess = FileAccess.open(
		"res://addons/ai_scene_gen/mocks/interior_room.scenespec.json",
		FileAccess.READ
	)
	if f == null:
		pass_test("mock file not found — skip")
		return
	var json: String = f.get_as_text()
	f.close()
	var result: ValidationResult = _validator.validate_json_string(json)
	assert_true(result.is_valid(), "updated interior spec should still validate")

# endregion


# region --- Dock: Material UI ---

func test_dock_material_preset_in_request() -> void:
	var dock: AiSceneGenDock = AiSceneGenDock.new()
	add_child_autoqfree(dock)
	await get_tree().process_frame

	var request: Dictionary = dock.get_generation_request()
	assert_true(request.has("material_preset"), "request should have material_preset key")


func test_dock_material_preset_default_empty() -> void:
	var dock: AiSceneGenDock = AiSceneGenDock.new()
	add_child_autoqfree(dock)
	await get_tree().process_frame

	var preset: String = dock.get_selected_material_preset()
	assert_eq(preset, "", "default material preset should be empty (none)")

# endregion
