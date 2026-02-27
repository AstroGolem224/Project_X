@tool
extends GutTest

## GUT tests for Texture Mapping / UV Support (Prio 17).
## Tests texture field validation, factory texture loading (with fallback),
## prompt compiler texture instructions, and dock texture UI.

var _factory: ProceduralPrimitiveFactory
var _validator: SceneSpecValidator
var _builder: SceneBuilder

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
		"id": "tex_node",
		"name": "TexNode",
		"node_type": "MeshInstance3D",
		"primitive_shape": "box",
		"position": [0.0, 0.0, 0.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0],
		"material": mat,
		"collision": false,
		"metadata": {"role": "ground"}
	}

# endregion


# region --- Validator: Texture Fields Allowed ---

func test_validator_accepts_spec_without_textures() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({"albedo": [0.5, 0.5, 0.5], "roughness": 0.5})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_true(result.is_valid(), "spec without textures should still pass")


func test_validator_accepts_albedo_texture() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"albedo_texture": "res://textures/stone_albedo.png"
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_true(result.is_valid(), "valid albedo_texture path should pass")


func test_validator_accepts_all_texture_fields() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"albedo_texture": "res://textures/albedo.png",
		"normal_texture": "res://textures/normal.png",
		"roughness_texture": "res://textures/roughness.png",
		"metallic_texture": "res://textures/metallic.png",
		"emission_texture": "res://textures/emission.png"
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_true(result.is_valid(), "all texture fields with valid paths should pass")


func test_validator_rejects_texture_without_res_prefix() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"albedo_texture": "/textures/stone.png"
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "texture path without res:// should fail")


func test_validator_rejects_texture_non_string() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"normal_texture": 42
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "texture field with non-string should fail")


func test_validator_rejects_texture_http_path() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"albedo_texture": "http://example.com/tex.png"
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "http:// texture path should fail")


func test_validator_rejects_texture_empty_string() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"roughness_texture": ""
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_false(result.is_valid(), "empty string texture path should fail")


func test_validator_texture_fields_in_allowed_list() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"metallic_texture": "res://textures/metal.png",
		"emission_texture": "res://textures/emissive.png"
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_true(result.is_valid(), "metallic + emission texture should not trigger unknown field error")

# endregion


# region --- Validator: Backwards Compatibility ---

func test_validator_backwards_compat_albedo_roughness_only() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({"albedo": [1.0, 0.0, 0.0], "roughness": 0.7})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_true(result.is_valid(), "old-style material without textures must still pass")


func test_validator_backwards_compat_preset_only() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({"preset": "gold"})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_true(result.is_valid(), "preset-only material must still pass")


func test_validator_texture_with_preset_combined() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"preset": "stone",
		"albedo_texture": "res://textures/stone_diffuse.png",
		"normal_texture": "res://textures/stone_normal.png"
	})]
	var result: ValidationResult = _validator.validate_spec(spec)
	assert_true(result.is_valid(), "preset + texture combination should pass")

# endregion


# region --- Factory: Texture Loading ---

func test_factory_material_without_textures_unchanged() -> void:
	var mat: Dictionary = {"albedo": [0.5, 0.5, 0.5], "roughness": 0.5}
	var material: StandardMaterial3D = _factory.create_material_from_spec(mat)
	assert_not_null(material, "should create material")
	assert_null(material.albedo_texture, "no albedo texture expected")
	assert_false(material.normal_enabled, "normal should not be enabled")


func test_factory_missing_texture_no_crash() -> void:
	var mat: Dictionary = {
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"albedo_texture": "res://nonexistent_texture_abc123.png"
	}
	var material: StandardMaterial3D = _factory.create_material_from_spec(mat)
	assert_not_null(material, "material should still be created")
	assert_null(material.albedo_texture, "missing texture should result in null")


func test_factory_invalid_texture_path_no_crash() -> void:
	var mat: Dictionary = {
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"normal_texture": "invalid_path"
	}
	var material: StandardMaterial3D = _factory.create_material_from_spec(mat)
	assert_not_null(material, "material should still be created")
	assert_false(material.normal_enabled, "normal should not be enabled for invalid path")


func test_factory_empty_texture_path_no_crash() -> void:
	var mat: Dictionary = {
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"roughness_texture": ""
	}
	var material: StandardMaterial3D = _factory.create_material_from_spec(mat)
	assert_not_null(material, "material should still be created")
	assert_null(material.roughness_texture, "empty path should result in null texture")


func test_factory_multiple_missing_textures_no_crash() -> void:
	var mat: Dictionary = {
		"albedo": [0.3, 0.6, 0.1], "roughness": 0.8,
		"albedo_texture": "res://missing1.png",
		"normal_texture": "res://missing2.png",
		"roughness_texture": "res://missing3.png",
		"metallic_texture": "res://missing4.png",
		"emission_texture": "res://missing5.png"
	}
	var material: StandardMaterial3D = _factory.create_material_from_spec(mat)
	assert_not_null(material, "material should be created even with all textures missing")
	assert_almost_eq(material.albedo_color.r, 0.3, COLOR_TOLERANCE, "albedo preserved")
	assert_almost_eq(material.roughness, 0.8, COLOR_TOLERANCE, "roughness preserved")

# endregion


# region --- Factory: Primitive with Texture Material ---

func test_primitive_with_texture_material_no_crash() -> void:
	var mat: Dictionary = {
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"albedo_texture": "res://nonexistent.png"
	}
	var node: Node3D = _factory.create_primitive_with_material(
		"box", Vector3(1.0, 1.0, 1.0), mat, false
	)
	assert_not_null(node, "primitive should be created")
	node.free()


func test_primitive_with_preset_and_texture() -> void:
	var mat: Dictionary = {
		"preset": "wood",
		"albedo_texture": "res://nonexistent_wood.png"
	}
	var node: Node3D = _factory.create_primitive_with_material(
		"sphere", Vector3(2.0, 2.0, 2.0), mat, false
	)
	assert_not_null(node, "should create node with preset + texture")
	node.free()

# endregion


# region --- Builder: Texture Material Integration ---

func test_builder_handles_texture_material() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.5, 0.5, 0.5], "roughness": 0.5,
		"albedo_texture": "res://no_such_texture.png"
	})]
	var root: Node3D = Node3D.new()
	var result: BuildResult = _builder.build(spec, root)
	assert_true(result.is_success(), "build should succeed even with missing textures")
	root.queue_free()


func test_builder_preserves_color_with_missing_texture() -> void:
	var spec: Dictionary = _make_minimal_valid_spec()
	spec["nodes"] = [_make_node_with_material({
		"albedo": [0.8, 0.2, 0.1], "roughness": 0.6,
		"albedo_texture": "res://does_not_exist.png"
	})]
	var root: Node3D = Node3D.new()
	var result: BuildResult = _builder.build(spec, root)
	assert_true(result.is_success(), "build should succeed")

	var tex_node: Node3D = null
	for i: int in range(root.get_child_count()):
		if str(root.get_child(i).name) == "TexNode":
			tex_node = root.get_child(i) as Node3D
			break
	if tex_node != null:
		for j: int in range(tex_node.get_child_count()):
			var child: Node = tex_node.get_child(j)
			if child is MeshInstance3D:
				var mi: MeshInstance3D = child as MeshInstance3D
				if mi.material_override is StandardMaterial3D:
					var m: StandardMaterial3D = mi.material_override as StandardMaterial3D
					assert_almost_eq(m.albedo_color.r, 0.8, COLOR_TOLERANCE, "albedo color preserved")
	root.queue_free()

# endregion


# region --- Prompt Compiler: Texture Instructions ---

func test_prompt_contains_texture_instructions() -> void:
	var compiler: PromptCompiler = PromptCompiler.new()
	var instruction: String = compiler.get_system_instruction()
	assert_true(instruction.find("albedo_texture") != -1, "should mention albedo_texture")
	assert_true(instruction.find("normal_texture") != -1, "should mention normal_texture")
	assert_true(instruction.find("roughness_texture") != -1, "should mention roughness_texture")
	assert_true(instruction.find("metallic_texture") != -1, "should mention metallic_texture")
	assert_true(instruction.find("emission_texture") != -1, "should mention emission_texture")


func test_prompt_warns_about_inventing_paths() -> void:
	var compiler: PromptCompiler = PromptCompiler.new()
	var instruction: String = compiler.get_system_instruction()
	assert_true(instruction.find("Do NOT invent") != -1, "should warn LLM not to invent paths")

# endregion


# region --- Dock: Texture UI ---

func test_dock_texture_overrides_in_request() -> void:
	var dock: AiSceneGenDock = AiSceneGenDock.new()
	add_child_autoqfree(dock)
	await get_tree().process_frame

	var request: Dictionary = dock.get_generation_request()
	assert_true(request.has("texture_overrides"), "request should have texture_overrides key")
	assert_true(request["texture_overrides"] is Dictionary, "texture_overrides should be Dictionary")


func test_dock_texture_overrides_empty_by_default() -> void:
	var dock: AiSceneGenDock = AiSceneGenDock.new()
	add_child_autoqfree(dock)
	await get_tree().process_frame

	var overrides: Dictionary = dock.get_texture_overrides()
	assert_true(overrides.is_empty(), "default texture overrides should be empty")


func test_dock_has_texture_edits() -> void:
	var dock: AiSceneGenDock = AiSceneGenDock.new()
	add_child_autoqfree(dock)
	await get_tree().process_frame

	assert_true(dock._texture_edits.has("albedo_texture"), "should have albedo_texture edit")
	assert_true(dock._texture_edits.has("normal_texture"), "should have normal_texture edit")
	assert_true(dock._texture_edits.has("roughness_texture"), "should have roughness_texture edit")
	assert_true(dock._texture_edits.has("metallic_texture"), "should have metallic_texture edit")
	assert_true(dock._texture_edits.has("emission_texture"), "should have emission_texture edit")

# endregion


# region --- Golden Specs: Backwards Compatibility ---

func test_golden_outdoor_still_valid_with_texture_schema() -> void:
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
	assert_true(result.is_valid(), "outdoor spec should still validate with texture schema")


func test_golden_interior_still_valid_with_texture_schema() -> void:
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
	assert_true(result.is_valid(), "interior spec should still validate with texture schema")

# endregion
