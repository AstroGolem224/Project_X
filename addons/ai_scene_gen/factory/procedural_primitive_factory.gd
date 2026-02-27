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

const MATERIAL_PRESETS: Dictionary = {
	"wood": {"albedo": [0.45, 0.32, 0.18], "roughness": 0.85, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 1.0, "transparency": 0.0},
	"stone": {"albedo": [0.55, 0.53, 0.50], "roughness": 0.90, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 1.0, "transparency": 0.0},
	"metal": {"albedo": [0.56, 0.57, 0.58], "roughness": 0.25, "metallic": 0.95, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 1.0, "transparency": 0.0},
	"glass": {"albedo": [0.90, 0.93, 0.95], "roughness": 0.05, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.0, "transparency": 0.8},
	"water": {"albedo": [0.15, 0.35, 0.55], "roughness": 0.05, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.5, "transparency": 0.6},
	"plastic": {"albedo": [0.80, 0.20, 0.20], "roughness": 0.40, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.5, "transparency": 0.0},
	"fabric": {"albedo": [0.60, 0.55, 0.50], "roughness": 0.95, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.8, "transparency": 0.0},
	"concrete": {"albedo": [0.65, 0.63, 0.60], "roughness": 0.92, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 1.0, "transparency": 0.0},
	"brick": {"albedo": [0.62, 0.30, 0.22], "roughness": 0.88, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 1.0, "transparency": 0.0},
	"sand": {"albedo": [0.82, 0.72, 0.50], "roughness": 0.95, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.5, "transparency": 0.0},
	"grass": {"albedo": [0.30, 0.55, 0.18], "roughness": 0.90, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.7, "transparency": 0.0},
	"dirt": {"albedo": [0.48, 0.35, 0.22], "roughness": 0.95, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.8, "transparency": 0.0},
	"ceramic": {"albedo": [0.92, 0.90, 0.88], "roughness": 0.20, "metallic": 0.05, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.3, "transparency": 0.0},
	"rubber": {"albedo": [0.15, 0.15, 0.15], "roughness": 0.95, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.5, "transparency": 0.0},
	"marble": {"albedo": [0.93, 0.91, 0.89], "roughness": 0.15, "metallic": 0.05, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.3, "transparency": 0.0},
	"ice": {"albedo": [0.75, 0.88, 0.95], "roughness": 0.08, "metallic": 0.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.3, "transparency": 0.5},
	"gold": {"albedo": [1.0, 0.77, 0.34], "roughness": 0.20, "metallic": 1.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.5, "transparency": 0.0},
	"silver": {"albedo": [0.77, 0.78, 0.78], "roughness": 0.18, "metallic": 1.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.5, "transparency": 0.0},
	"copper": {"albedo": [0.72, 0.45, 0.20], "roughness": 0.30, "metallic": 1.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.5, "transparency": 0.0},
	"chrome": {"albedo": [0.55, 0.56, 0.56], "roughness": 0.02, "metallic": 1.0, "emission": [0.0, 0.0, 0.0], "emission_energy": 0.0, "normal_scale": 0.0, "transparency": 0.0},
	"lava": {"albedo": [0.20, 0.02, 0.0], "roughness": 0.85, "metallic": 0.0, "emission": [1.0, 0.35, 0.0], "emission_energy": 3.0, "normal_scale": 1.0, "transparency": 0.0},
	"neon": {"albedo": [0.05, 0.05, 0.05], "roughness": 0.30, "metallic": 0.0, "emission": [0.2, 1.0, 0.5], "emission_energy": 4.0, "normal_scale": 0.0, "transparency": 0.0},
}

const ALLOWED_MATERIAL_PRESETS: Array[String] = [
	"wood", "stone", "metal", "glass", "water", "plastic", "fabric",
	"concrete", "brick", "sand", "grass", "dirt", "ceramic", "rubber",
	"marble", "ice", "gold", "silver", "copper", "chrome", "lava", "neon",
]

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


## Returns a copy of available material preset names.
func get_preset_names() -> Array[String]:
	return ALLOWED_MATERIAL_PRESETS.duplicate()


## Returns the preset dictionary for a given name, or empty dict if unknown.
func get_preset(preset_name: String) -> Dictionary:
	if preset_name in MATERIAL_PRESETS:
		return (MATERIAL_PRESETS[preset_name] as Dictionary).duplicate()
	return {}


## Returns true if preset_name is in the allowlist.
func is_allowed_preset(preset_name: String) -> bool:
	return preset_name in ALLOWED_MATERIAL_PRESETS


## Creates a StandardMaterial3D from a SceneSpec material dictionary.
## Resolves preset first, then applies explicit overrides.
## @param mat: Material dictionary from the SceneSpec node.
## @return Configured StandardMaterial3D.
func create_material_from_spec(mat: Dictionary) -> StandardMaterial3D:
	var base: Dictionary = {}

	if mat.has("preset") and mat["preset"] is String:
		var pname: String = str(mat["preset"])
		if pname in MATERIAL_PRESETS:
			base = (MATERIAL_PRESETS[pname] as Dictionary).duplicate()

	var albedo_default: Variant = base.get("albedo", [0.5, 0.5, 0.5])
	var albedo_arr: Array = mat.get("albedo", albedo_default) as Array
	var roughness: float = float(mat.get("roughness", base.get("roughness", 0.5)))
	var metallic: float = float(mat.get("metallic", base.get("metallic", 0.0)))

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = _arr_to_color(albedo_arr)
	material.roughness = clampf(roughness, 0.0, 1.0)
	material.metallic = clampf(metallic, 0.0, 1.0)

	var emission_energy: float = float(mat.get("emission_energy", base.get("emission_energy", 0.0)))
	if emission_energy > 0.0:
		var emission_default: Variant = base.get("emission", [0.0, 0.0, 0.0])
		var emission_arr: Array = mat.get("emission", emission_default) as Array
		material.emission_enabled = true
		material.emission = _arr_to_color(emission_arr)
		material.emission_energy_multiplier = clampf(emission_energy, 0.0, 16.0)

	var transparency: float = float(mat.get("transparency", base.get("transparency", 0.0)))
	if transparency > 0.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var alpha: float = clampf(1.0 - transparency, 0.0, 1.0)
		material.albedo_color.a = alpha

	return material


## Creates a primitive using a full material spec dictionary.
## @param shape: Primitive shape name.
## @param size: Dimensions vector.
## @param mat: Material spec dictionary (albedo, roughness, metallic, preset, etc.).
## @param with_collision: Whether to add collision shapes.
## @return Wrapper Node3D or null on validation failure.
func create_primitive_with_material(
	shape: String,
	size: Vector3,
	mat: Dictionary,
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
	mesh_instance.material_override = create_material_from_spec(mat)
	wrapper.add_child(mesh_instance)

	if with_collision:
		_add_collision_to_wrapper(wrapper, shape, size)

	var tri_count: int = get_triangle_count(shape, size)
	_total_triangles_generated += tri_count
	_primitives_created_count += 1

	_log("debug", "primitive_created: %s size=%s" % [shape, str(size)])

	return wrapper


func _arr_to_color(arr: Array) -> Color:
	if arr.size() < 3:
		return Color.WHITE
	return Color(float(arr[0]), float(arr[1]), float(arr[2]))


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
