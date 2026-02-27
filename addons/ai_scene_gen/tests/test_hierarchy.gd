@tool
extends GutTest

## GUT tests for Prio 18: Hierarchical Node Groups / Parenting.
## Validates that the builder, validator, prompt compiler, and dock
## correctly handle nested node hierarchies (children arrays).

var _factory: ProceduralPrimitiveFactory
var _builder: SceneBuilder
var _validator: SceneSpecValidator


func before_each() -> void:
	_factory = ProceduralPrimitiveFactory.new()
	_builder = SceneBuilder.new(null, _factory)
	_validator = SceneSpecValidator.new()


# region --- Helpers ---

func _make_base_spec() -> Dictionary:
	return {
		"spec_version": "1.0.0",
		"meta": {
			"generator": "ai_scene_gen",
			"style_preset": "blockout",
			"bounds_meters": [20.0, 10.0, 20.0],
			"prompt_hash": "sha256:" + "a".repeat(64),
			"timestamp_utc": "2026-02-27T00:00:00Z"
		},
		"determinism": {
			"seed": 42,
			"variation_mode": false,
			"fingerprint": "hierarchy_test_fp"
		},
		"limits": {
			"max_nodes": 256,
			"max_scale_component": 50.0,
			"max_light_energy": 16.0,
			"max_tree_depth": 8,
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
		"lights": [{
			"id": "sun",
			"type": "DirectionalLight3D",
			"rotation_degrees": [-45.0, 30.0, 0.0],
			"color": [1.0, 0.95, 0.8],
			"energy": 1.0,
			"shadow_enabled": true
		}],
		"nodes": [],
		"rules": {
			"snap_to_ground": true,
			"clamp_to_bounds": true
		}
	}


func _make_table_group() -> Dictionary:
	return {
		"id": "table_group",
		"name": "Table",
		"node_type": "Node3D",
		"position": [2.0, 0.0, 1.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0],
		"children": [
			{
				"id": "table_top",
				"name": "TableTop",
				"node_type": "MeshInstance3D",
				"primitive_shape": "box",
				"position": [0.0, 0.75, 0.0],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [1.2, 0.05, 0.8],
				"material": {"albedo": [0.5, 0.35, 0.2], "roughness": 0.7},
				"collision": false,
				"metadata": {}
			},
			{
				"id": "table_leg_1",
				"name": "Leg1",
				"node_type": "MeshInstance3D",
				"primitive_shape": "cylinder",
				"position": [-0.5, 0.35, -0.3],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [0.05, 0.7, 0.05],
				"material": {"albedo": [0.5, 0.35, 0.2], "roughness": 0.7},
				"collision": false,
				"metadata": {}
			},
			{
				"id": "table_leg_2",
				"name": "Leg2",
				"node_type": "MeshInstance3D",
				"primitive_shape": "cylinder",
				"position": [0.5, 0.35, -0.3],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [0.05, 0.7, 0.05],
				"material": {"albedo": [0.5, 0.35, 0.2], "roughness": 0.7},
				"collision": false,
				"metadata": {}
			},
			{
				"id": "table_leg_3",
				"name": "Leg3",
				"node_type": "MeshInstance3D",
				"primitive_shape": "cylinder",
				"position": [-0.5, 0.35, 0.3],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [0.05, 0.7, 0.05],
				"material": {"albedo": [0.5, 0.35, 0.2], "roughness": 0.7},
				"collision": false,
				"metadata": {}
			},
			{
				"id": "table_leg_4",
				"name": "Leg4",
				"node_type": "MeshInstance3D",
				"primitive_shape": "cylinder",
				"position": [0.5, 0.35, 0.3],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [0.05, 0.7, 0.05],
				"material": {"albedo": [0.5, 0.35, 0.2], "roughness": 0.7},
				"collision": false,
				"metadata": {}
			}
		],
		"metadata": {"role": "furniture"}
	}


func _make_ground_node() -> Dictionary:
	return {
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


func _make_nested_chain(depth: int) -> Dictionary:
	var root_node: Dictionary = {
		"id": "chain_0",
		"name": "Chain0",
		"node_type": "Node3D",
		"position": [0.0, 0.0, 0.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0]
	}
	var current: Dictionary = root_node
	for i: int in range(1, depth):
		var child: Dictionary = {
			"id": "chain_%d" % i,
			"name": "Chain%d" % i,
			"node_type": "Node3D",
			"position": [0.0, float(i), 0.0],
			"rotation_degrees": [0.0, 0.0, 0.0],
			"scale": [1.0, 1.0, 1.0]
		}
		current["children"] = [child]
		current = child
	return root_node

# endregion

# region --- Builder: hierarchical build ---

func test_build_table_group_succeeds() -> void:
	var spec: Dictionary = _make_base_spec()
	spec["nodes"] = [_make_ground_node(), _make_table_group()]
	var root: Node3D = Node3D.new()

	var result: BuildResult = _builder.build(spec, root)

	assert_true(result.is_success(), "table group build should succeed")
	assert_eq(result.get_group_count(), 1, "one group (table)")
	root.queue_free()


func test_build_group_node_count() -> void:
	var spec: Dictionary = _make_base_spec()
	spec["nodes"] = [_make_ground_node(), _make_table_group()]
	var root: Node3D = Node3D.new()

	var result: BuildResult = _builder.build(spec, root)

	var expected_nodes: int = 1 + 1 + 1 + 5 + 1 + 1
	assert_eq(result.get_node_count(), expected_nodes,
		"env + camera + light + ground + table_group + 5 children = %d" % expected_nodes)
	root.queue_free()


func test_build_children_parented_correctly() -> void:
	var spec: Dictionary = _make_base_spec()
	spec["nodes"] = [_make_table_group()]
	var root: Node3D = Node3D.new()

	_builder.build(spec, root)

	var table_node: Node = null
	for i: int in range(root.get_child_count()):
		if root.get_child(i).name == "Table":
			table_node = root.get_child(i)
			break

	assert_not_null(table_node, "table group node should exist")
	if table_node != null:
		assert_eq(table_node.get_child_count(), 5,
			"table should have 5 children (top + 4 legs)")
		var top: Node = table_node.get_child(0)
		assert_eq(str(top.name), "TableTop", "first child should be TableTop")
	root.queue_free()


func test_build_children_positions_relative() -> void:
	var spec: Dictionary = _make_base_spec()
	spec["nodes"] = [_make_table_group()]
	var root: Node3D = Node3D.new()

	_builder.build(spec, root)

	var table_node: Node3D = null
	for i: int in range(root.get_child_count()):
		if root.get_child(i).name == "Table" and root.get_child(i) is Node3D:
			table_node = root.get_child(i) as Node3D
			break

	assert_not_null(table_node, "table group should exist")
	if table_node == null:
		return

	assert_almost_eq(table_node.position.x, 2.0, 0.01, "table at x=2")
	assert_almost_eq(table_node.position.z, 1.0, 0.01, "table at z=1")

	if table_node.get_child_count() > 0 and table_node.get_child(0) is Node3D:
		var top: Node3D = table_node.get_child(0) as Node3D
		assert_almost_eq(top.position.y, 0.75, 0.01, "top relative y=0.75")
		assert_almost_eq(top.position.x, 0.0, 0.01, "top relative x=0")
	root.queue_free()


func test_build_max_depth_tracked() -> void:
	var spec: Dictionary = _make_base_spec()
	spec["nodes"] = [_make_ground_node(), _make_table_group()]
	var root: Node3D = Node3D.new()

	var result: BuildResult = _builder.build(spec, root)

	assert_gte(result.get_max_depth(), 1,
		"max depth should be >= 1 (table group has children at depth 1)")
	root.queue_free()


func test_build_nested_chain_group_count() -> void:
	var spec: Dictionary = _make_base_spec()
	spec["nodes"] = [_make_nested_chain(4)]
	var root: Node3D = Node3D.new()

	var result: BuildResult = _builder.build(spec, root)

	assert_true(result.is_success(), "nested chain build should succeed")
	assert_eq(result.get_group_count(), 3,
		"3 group parents in chain of depth 4 (depth 0,1,2 each have children)")
	root.queue_free()


func test_build_deep_nesting_rejected() -> void:
	var spec: Dictionary = _make_base_spec()
	spec["limits"]["max_tree_depth"] = 3
	spec["nodes"] = [_make_nested_chain(10)]
	var root: Node3D = Node3D.new()

	var result: BuildResult = _builder.build(spec, root)

	var found_depth_error: bool = false
	for err: Dictionary in result.get_errors():
		if err.get("code", "") == "BUILD_ERR_TREE_DEPTH":
			found_depth_error = true
			break

	assert_true(found_depth_error,
		"nesting depth 10 with limit 3 should produce BUILD_ERR_TREE_DEPTH")
	root.queue_free()


func test_build_multiple_groups() -> void:
	var spec: Dictionary = _make_base_spec()
	var tree_group: Dictionary = {
		"id": "tree_group",
		"name": "Tree",
		"node_type": "Node3D",
		"position": [-3.0, 0.0, -2.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0],
		"children": [
			{
				"id": "trunk",
				"name": "Trunk",
				"node_type": "MeshInstance3D",
				"primitive_shape": "cylinder",
				"position": [0.0, 1.0, 0.0],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [0.3, 2.0, 0.3],
				"material": {"albedo": [0.4, 0.25, 0.1], "roughness": 0.9},
				"collision": false,
				"metadata": {}
			},
			{
				"id": "canopy",
				"name": "Canopy",
				"node_type": "MeshInstance3D",
				"primitive_shape": "sphere",
				"position": [0.0, 3.0, 0.0],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [2.0, 2.0, 2.0],
				"material": {"albedo": [0.2, 0.6, 0.15], "roughness": 0.8},
				"collision": false,
				"metadata": {}
			}
		],
		"metadata": {"role": "vegetation"}
	}
	spec["nodes"] = [_make_ground_node(), _make_table_group(), tree_group]
	var root: Node3D = Node3D.new()

	var result: BuildResult = _builder.build(spec, root)

	assert_true(result.is_success(), "multi-group build should succeed")
	assert_eq(result.get_group_count(), 2, "two groups (table + tree)")
	root.queue_free()


func test_build_flat_spec_zero_groups() -> void:
	var spec: Dictionary = _make_base_spec()
	spec["nodes"] = [_make_ground_node()]
	var root: Node3D = Node3D.new()

	var result: BuildResult = _builder.build(spec, root)

	assert_true(result.is_success(), "flat spec build should succeed")
	assert_eq(result.get_group_count(), 0, "flat spec has no groups")
	root.queue_free()

# endregion

# region --- Validator: hierarchy ---

func test_validator_accepts_nested_spec() -> void:
	var spec: Dictionary = _make_base_spec()
	spec["nodes"] = [_make_ground_node(), _make_table_group()]
	var raw: String = JSON.stringify(spec)

	var result: ValidationResult = _validator.validate_json_string(raw)

	assert_true(result.is_valid(), "spec with children should validate")


func test_validator_children_skip_bounds() -> void:
	var spec: Dictionary = _make_base_spec()
	spec["meta"]["bounds_meters"] = [4.0, 4.0, 4.0]
	var group: Dictionary = {
		"id": "grp",
		"name": "Group",
		"node_type": "Node3D",
		"position": [0.0, 0.0, 0.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0],
		"children": [{
			"id": "child_far",
			"name": "ChildFar",
			"node_type": "MeshInstance3D",
			"primitive_shape": "box",
			"position": [100.0, 100.0, 100.0],
			"rotation_degrees": [0.0, 0.0, 0.0],
			"scale": [1.0, 1.0, 1.0],
			"material": {"albedo": [0.5, 0.5, 0.5], "roughness": 0.5},
			"collision": false,
			"metadata": {}
		}],
		"metadata": {}
	}
	spec["nodes"] = [_make_ground_node(), group]
	var raw: String = JSON.stringify(spec)

	var result: ValidationResult = _validator.validate_json_string(raw)

	var has_bounds_err: bool = false
	for err: Dictionary in result.get_errors():
		if err.get("code", "") == "SPEC_ERR_BOUNDS":
			has_bounds_err = true
			break
	assert_false(has_bounds_err,
		"child node positions are relative and should not be bounds-checked")


func test_validator_depth_enforcement() -> void:
	var spec: Dictionary = _make_base_spec()
	spec["limits"]["max_tree_depth"] = 2
	spec["nodes"] = [_make_nested_chain(5)]
	var raw: String = JSON.stringify(spec)

	var result: ValidationResult = _validator.validate_json_string(raw)

	var has_depth_err: bool = false
	for err: Dictionary in result.get_errors():
		if err.get("code", "") == "BUILD_ERR_TREE_DEPTH":
			has_depth_err = true
			break
	assert_true(has_depth_err,
		"depth 5 with limit 2 should be rejected by validator")


func test_validator_children_unique_ids() -> void:
	var spec: Dictionary = _make_base_spec()
	var group: Dictionary = {
		"id": "grp",
		"name": "Group",
		"node_type": "Node3D",
		"position": [0.0, 0.0, 0.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0],
		"children": [
			{
				"id": "dup_id",
				"name": "ChildA",
				"node_type": "MeshInstance3D",
				"primitive_shape": "box",
				"position": [0.0, 0.0, 0.0],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [1.0, 1.0, 1.0],
				"material": {"albedo": [0.5, 0.5, 0.5], "roughness": 0.5},
				"collision": false,
				"metadata": {}
			},
			{
				"id": "dup_id",
				"name": "ChildB",
				"node_type": "MeshInstance3D",
				"primitive_shape": "box",
				"position": [1.0, 0.0, 0.0],
				"rotation_degrees": [0.0, 0.0, 0.0],
				"scale": [1.0, 1.0, 1.0],
				"material": {"albedo": [0.5, 0.5, 0.5], "roughness": 0.5},
				"collision": false,
				"metadata": {}
			}
		],
		"metadata": {}
	}
	spec["nodes"] = [group]
	var raw: String = JSON.stringify(spec)

	var result: ValidationResult = _validator.validate_json_string(raw)

	var has_dup_err: bool = false
	for err: Dictionary in result.get_errors():
		if err.get("code", "") == "SPEC_ERR_DUPLICATE_ID":
			has_dup_err = true
			break
	assert_true(has_dup_err,
		"duplicate ids across children should be rejected")

# endregion

# region --- Prompt Compiler: grouping instructions ---

func test_prompt_contains_grouping_instructions() -> void:
	var compiler: PromptCompiler = PromptCompiler.new()
	var system: String = compiler.get_system_instruction()

	assert_true(system.find("children") != -1,
		"system instructions should mention children")
	assert_true(system.find("group") != -1 or system.find("Group") != -1,
		"system instructions should mention grouping")
	assert_true(system.find("RELATIVE") != -1 or system.find("relative") != -1,
		"system instructions should mention relative positions")


func test_prompt_compiled_includes_grouping() -> void:
	var compiler: PromptCompiler = PromptCompiler.new()
	var request: Dictionary = {
		"user_prompt": "a simple room with a table",
		"style_preset": "blockout",
		"seed": 42,
		"bounds_meters": [10.0, 5.0, 10.0],
		"available_asset_tags": [],
		"project_constraints": "",
	}
	var prompt: String = compiler.compile_single_stage(request)

	assert_true(not prompt.is_empty(), "prompt should compile")
	assert_true(prompt.find("children") != -1,
		"compiled prompt should mention children for grouping")

# endregion

# region --- BuildResult: group/depth fields ---

func test_build_result_group_count_default() -> void:
	var result: BuildResult = BuildResult.create_success(
		Node3D.new(), 10, 100, "build:abc", 5
	)
	assert_eq(result.get_group_count(), 0, "default group_count is 0")
	assert_eq(result.get_max_depth(), 0, "default max_depth is 0")


func test_build_result_group_count_set() -> void:
	var result: BuildResult = BuildResult.create_success(
		Node3D.new(), 10, 100, "build:abc", 5, 3, 2
	)
	assert_eq(result.get_group_count(), 3, "group_count should be 3")
	assert_eq(result.get_max_depth(), 2, "max_depth should be 2")

# endregion

# region --- Dock: preview info ---

func test_dock_show_preview_info() -> void:
	var dock: AiSceneGenDock = AiSceneGenDock.new()
	add_child_autofree(dock)
	await get_tree().process_frame

	dock.show_preview_info(12, 3, 2)

	assert_true(dock._preview_info_label.visible, "info label should be visible")
	assert_true(dock._preview_info_label.text.find("12 nodes") != -1,
		"should show node count")
	assert_true(dock._preview_info_label.text.find("3 groups") != -1,
		"should show group count")
	assert_true(dock._preview_info_label.text.find("depth 2") != -1,
		"should show max depth")


func test_dock_preview_info_no_groups() -> void:
	var dock: AiSceneGenDock = AiSceneGenDock.new()
	add_child_autofree(dock)
	await get_tree().process_frame

	dock.show_preview_info(5, 0, 0)

	assert_true(dock._preview_info_label.visible, "info label should be visible")
	assert_true(dock._preview_info_label.text.find("5 nodes") != -1,
		"should show node count")
	assert_true(dock._preview_info_label.text.find("groups") == -1,
		"should not mention groups when 0")


func test_dock_preview_info_hidden_on_idle() -> void:
	var dock: AiSceneGenDock = AiSceneGenDock.new()
	add_child_autofree(dock)
	await get_tree().process_frame

	dock.show_preview_info(10, 2, 1)
	dock.set_state(AiSceneGenDock.DockState.IDLE)

	assert_false(dock._preview_info_label.visible,
		"info label should be hidden in IDLE state")

# endregion

# region --- Golden compat: interior_room with children ---

func test_interior_room_spec_has_children() -> void:
	var f: FileAccess = FileAccess.open(
		"res://addons/ai_scene_gen/mocks/interior_room.scenespec.json",
		FileAccess.READ
	)
	if f == null:
		gut.p("SKIP: interior_room mock not found")
		pass_test("mock not found")
		return

	var content: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(content)
	assert_not_null(parsed, "should parse")
	if parsed == null:
		return

	var spec: Dictionary = parsed as Dictionary
	var nodes: Array = spec.get("nodes", []) as Array
	var found_group: bool = false
	for node: Variant in nodes:
		if node is Dictionary:
			var d: Dictionary = node as Dictionary
			if d.has("children") and d["children"] is Array:
				var children: Array = d["children"] as Array
				if not children.is_empty():
					found_group = true
					break

	assert_true(found_group, "interior_room mock should have at least one group with children")


func test_interior_room_builds_with_groups() -> void:
	var f: FileAccess = FileAccess.open(
		"res://addons/ai_scene_gen/mocks/interior_room.scenespec.json",
		FileAccess.READ
	)
	if f == null:
		gut.p("SKIP: interior_room mock not found")
		pass_test("mock not found")
		return

	var content: String = f.get_as_text()
	f.close()

	var parsed: Variant = JSON.parse_string(content)
	if parsed == null:
		pass_test("could not parse")
		return

	var spec: Dictionary = parsed as Dictionary
	var root: Node3D = Node3D.new()
	var result: BuildResult = _builder.build(spec, root)

	assert_true(result.is_success(), "interior_room should build successfully")
	assert_gt(result.get_group_count(), 0,
		"interior_room should have at least 1 group (table)")
	root.queue_free()

# endregion
