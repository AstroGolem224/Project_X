@tool
extends GutTest

## GUT tests for ProceduralPrimitiveFactory (Module G).
## Test IDs: T24, T25.

var _factory: ProceduralPrimitiveFactory


func before_each() -> void:
	_factory = ProceduralPrimitiveFactory.new()


func after_each() -> void:
	_factory.reset_counters()


# region --- T24: All five shapes create valid nodes ---

func test_T24_all_five_shapes_create_valid_nodes() -> void:
	var shapes: Array[String] = ["box", "sphere", "cylinder", "capsule", "plane"]
	for shape: String in shapes:
		var node: Node3D = _factory.create_primitive(
			shape, Vector3(2.0, 2.0, 2.0), Color.WHITE, 0.5, false
		)
		assert_not_null(node, "%s should create a non-null node" % shape)
		assert_true(node is Node3D, "%s result should be Node3D" % shape)
		assert_gt(node.get_child_count(), 0, "%s should have children (MeshInstance3D)" % shape)
		node.free()

# endregion

# region --- T25: Unknown shape rejected ---

func test_T25_unknown_shape_rejected() -> void:
	var node: Node3D = _factory.create_primitive(
		"hexagon", Vector3(1.0, 1.0, 1.0), Color.WHITE, 0.5, false
	)
	assert_null(node, "hexagon should return null")

# endregion

# region --- Size validation ---

func test_zero_size_component_rejected() -> void:
	var node: Node3D = _factory.create_primitive(
		"box", Vector3(0.0, 1.0, 1.0), Color.WHITE, 0.5, false
	)
	assert_null(node, "zero-width box should return null")


func test_negative_size_component_rejected() -> void:
	var node: Node3D = _factory.create_primitive(
		"box", Vector3(-1.0, 1.0, 1.0), Color.WHITE, 0.5, false
	)
	assert_null(node, "negative-width box should return null")


func test_oversized_component_rejected() -> void:
	var node: Node3D = _factory.create_primitive(
		"box", Vector3(999.0, 1.0, 1.0), Color.WHITE, 0.5, false
	)
	assert_null(node, "size > MAX_SIZE_COMPONENT should return null")

# endregion

# region --- Collision generation ---

func test_collision_generated() -> void:
	var node: Node3D = _factory.create_primitive(
		"box", Vector3(2.0, 2.0, 2.0), Color.WHITE, 0.5, true
	)
	assert_not_null(node, "box with collision should not be null")

	var found_static_body: bool = false
	for i: int in range(node.get_child_count()):
		var child: Node = node.get_child(i)
		if child is StaticBody3D:
			found_static_body = true
			break

	assert_true(found_static_body, "collision=true should produce a StaticBody3D child")
	node.free()


func test_no_collision_when_disabled() -> void:
	var node: Node3D = _factory.create_primitive(
		"box", Vector3(2.0, 2.0, 2.0), Color.WHITE, 0.5, false
	)
	assert_not_null(node)

	var found_static_body: bool = false
	for i: int in range(node.get_child_count()):
		if node.get_child(i) is StaticBody3D:
			found_static_body = true
			break

	assert_false(found_static_body, "collision=false should produce no StaticBody3D")
	node.free()

# endregion

# region --- Triangle count ---

func test_triangle_count_box() -> void:
	var count: int = _factory.get_triangle_count("box", Vector3.ONE)
	assert_eq(count, 12, "box should have 12 triangles")


func test_triangle_count_sphere() -> void:
	var count: int = _factory.get_triangle_count("sphere", Vector3.ONE)
	assert_eq(count, 512, "sphere should have 512 triangles")


func test_triangle_count_cylinder() -> void:
	var count: int = _factory.get_triangle_count("cylinder", Vector3.ONE)
	assert_eq(count, 128, "cylinder should have 128 triangles")


func test_triangle_count_capsule() -> void:
	var count: int = _factory.get_triangle_count("capsule", Vector3.ONE)
	assert_eq(count, 576, "capsule should have 576 triangles")


func test_triangle_count_plane() -> void:
	var count: int = _factory.get_triangle_count("plane", Vector3.ONE)
	assert_eq(count, 2, "plane should have 2 triangles")


func test_triangle_count_unknown_shape() -> void:
	var count: int = _factory.get_triangle_count("pentagon", Vector3.ONE)
	assert_eq(count, 0, "unknown shape should return 0 triangles")

# endregion

# region --- Counter tracking ---

func test_counters_increment_on_create() -> void:
	assert_eq(_factory.get_primitives_created_count(), 0)
	assert_eq(_factory.get_total_triangles_generated(), 0)

	var node: Node3D = _factory.create_primitive(
		"box", Vector3(1.0, 1.0, 1.0), Color.WHITE, 0.5, false
	)
	assert_not_null(node)
	assert_eq(_factory.get_primitives_created_count(), 1)
	assert_eq(_factory.get_total_triangles_generated(), 12)
	node.free()


func test_counter_reset() -> void:
	var node: Node3D = _factory.create_primitive(
		"sphere", Vector3(1.0, 1.0, 1.0), Color.WHITE, 0.5, false
	)
	assert_not_null(node)
	assert_gt(_factory.get_primitives_created_count(), 0)

	_factory.reset_counters()
	assert_eq(_factory.get_primitives_created_count(), 0)
	assert_eq(_factory.get_total_triangles_generated(), 0)
	node.free()

# endregion

# region --- Shape allowlist ---

func test_is_allowed_shape() -> void:
	assert_true(_factory.is_allowed_shape("box"))
	assert_true(_factory.is_allowed_shape("sphere"))
	assert_false(_factory.is_allowed_shape("hexagon"))
	assert_false(_factory.is_allowed_shape(""))

# endregion
