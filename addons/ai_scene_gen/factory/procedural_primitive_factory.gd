@tool
class_name ProceduralPrimitiveFactory
extends RefCounted

## Factory for procedurally generated 3D primitives (box, sphere, cylinder, capsule, plane).
## Used as fallback when asset tags resolve to no match.

const ALLOWED_SHAPES: Array[String] = ["box", "sphere", "cylinder", "capsule", "plane"]
const MAX_SIZE_COMPONENT: float = 100.0

const TRIANGLES_BOX: int = 12
const TRIANGLES_SPHERE: int = 512
const TRIANGLES_CYLINDER: int = 128
const TRIANGLES_CAPSULE: int = 576
const TRIANGLES_PLANE: int = 2

const LOG_CATEGORY: String = "ai_scene_gen.primitives"

var _logger: RefCounted = null
var _total_triangles_generated: int = 0
var _primitives_created_count: int = 0


func _init(logger: RefCounted = null) -> void:
	_logger = logger


## Creates a procedural primitive mesh with optional collision.
## @param shape: One of "box", "sphere", "cylinder", "capsule", "plane".
## @param size: Dimensions (x=width/radius-scale, y=height, z=depth for plane).
## @param color: Albedo color for StandardMaterial3D.
## @param roughness: Material roughness 0..1.
## @param with_collision: If true, adds StaticBody3D + CollisionShape3D.
## @return: Wrapper Node3D with MeshInstance3D (and collision when requested), or null on validation failure.
func create_primitive(
	shape: String,
	size: Vector3,
	color: Color,
	roughness: float,
	with_collision: bool
) -> Node3D:
	if not is_allowed_shape(shape):
		_log("error", "PRIM_ERR_UNKNOWN_SHAPE")
		return null

	if size.x <= 0 or size.y <= 0 or size.z <= 0:
		_log("error", "PRIM_ERR_INVALID_SIZE")
		return null
	if size.x > MAX_SIZE_COMPONENT or size.y > MAX_SIZE_COMPONENT or size.z > MAX_SIZE_COMPONENT:
		_log("error", "PRIM_ERR_INVALID_SIZE")
		return null

	var wrapper: Node3D = Node3D.new()
	wrapper.name = "Prim_%s" % shape

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	var mesh: PrimitiveMesh = _create_mesh_for_shape(shape, size)
	if mesh == null:
		_log("error", "PRIM_ERR_UNKNOWN_SHAPE")
		wrapper.free()
		return null

	mesh_instance.mesh = mesh

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	mesh_instance.material_override = material

	wrapper.add_child(mesh_instance)

	if with_collision:
		_add_collision_to_wrapper(wrapper, shape, size)

	var tri_count: int = get_triangle_count(shape, size)
	_total_triangles_generated += tri_count
	_primitives_created_count += 1

	_log("debug", "primitive_created: %s size=%s" % [shape, size])

	return wrapper


## Returns the static triangle count for budget tracking.
func get_triangle_count(shape: String, _size: Vector3) -> int:
	match shape:
		"box":
			return TRIANGLES_BOX
		"sphere":
			return TRIANGLES_SPHERE
		"cylinder":
			return TRIANGLES_CYLINDER
		"capsule":
			return TRIANGLES_CAPSULE
		"plane":
			return TRIANGLES_PLANE
		_:
			return 0


## Returns a copy of the allowed shape names.
func get_allowed_shapes() -> Array[String]:
	return ALLOWED_SHAPES.duplicate()


## Returns true if the shape name is in the allowlist.
func is_allowed_shape(shape: String) -> bool:
	return shape in ALLOWED_SHAPES


## Returns total triangles generated since init or last reset.
func get_total_triangles_generated() -> int:
	return _total_triangles_generated


## Returns number of primitives created since init or last reset.
func get_primitives_created_count() -> int:
	return _primitives_created_count


## Resets triangle and primitive counters to 0.
func reset_counters() -> void:
	_total_triangles_generated = 0
	_primitives_created_count = 0


func _log(level: String, message: String) -> void:
	if _logger == null:
		return
	match level:
		"debug":
			_logger.log_debug(LOG_CATEGORY, message)
		"info":
			_logger.log_info(LOG_CATEGORY, message)
		"warning":
			_logger.log_warning(LOG_CATEGORY, message)
		"error":
			_logger.log_error(LOG_CATEGORY, message)


func _create_mesh_for_shape(shape: String, size: Vector3) -> PrimitiveMesh:
	match shape:
		"box":
			var m: BoxMesh = BoxMesh.new()
			m.size = Vector3(size.x, size.y, size.z)
			return m
		"sphere":
			var m: SphereMesh = SphereMesh.new()
			m.radius = size.x * 0.5
			m.height = size.y
			m.rings = 32
			m.radial_segments = 16
			return m
		"cylinder":
			var m: CylinderMesh = CylinderMesh.new()
			m.top_radius = size.x * 0.5
			m.bottom_radius = size.x * 0.5
			m.height = size.y
			m.radial_segments = 32
			return m
		"capsule":
			var m: CapsuleMesh = CapsuleMesh.new()
			m.radius = size.x * 0.5
			m.height = size.y
			return m
		"plane":
			var m: PlaneMesh = PlaneMesh.new()
			m.size = Vector2(size.x, size.z)
			return m
		_:
			return null


func _add_collision_to_wrapper(wrapper: Node3D, shape: String, size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	var col_shape_node: CollisionShape3D = CollisionShape3D.new()
	var shape_resource: Shape3D = null

	match shape:
		"box":
			var s: BoxShape3D = BoxShape3D.new()
			s.size = Vector3(size.x, size.y, size.z)
			shape_resource = s
		"sphere":
			var s: SphereShape3D = SphereShape3D.new()
			s.radius = size.x * 0.5
			shape_resource = s
		"cylinder":
			var s: CylinderShape3D = CylinderShape3D.new()
			s.height = size.y
			s.radius = size.x * 0.5
			shape_resource = s
		"capsule":
			var s: CapsuleShape3D = CapsuleShape3D.new()
			s.radius = size.x * 0.5
			s.height = size.y
			shape_resource = s
		"plane":
			var s: WorldBoundaryShape3D = WorldBoundaryShape3D.new()
			s.plane = Plane(0, 1, 0, 0)
			shape_resource = s

	if shape_resource != null:
		col_shape_node.shape = shape_resource
		body.add_child(col_shape_node)
		wrapper.add_child(body)
