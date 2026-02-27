@tool
class_name SceneBuilder
extends RefCounted

## Deterministic scene tree builder.
## Takes a resolved SceneSpec dictionary and constructs the Godot node tree,
## returning a BuildResult with stats or errors.

const LOG_CATEGORY: String = "ai_scene_gen.builder"

const BUILD_ERR_TREE_DEPTH: String = "BUILD_ERR_TREE_DEPTH"
const BUILD_ERR_ASSET_LOAD: String = "BUILD_ERR_ASSET_LOAD"
const BUILD_ERR_ENVIRONMENT: String = "BUILD_ERR_ENVIRONMENT"
const BUILD_ERR_CAMERA: String = "BUILD_ERR_CAMERA"
const BUILD_ERR_LIGHT: String = "BUILD_ERR_LIGHT"

var _logger: RefCounted = null
var _primitive_factory: RefCounted = null
var _errors: Array[Dictionary] = []
var _node_count: int = 0
var _triangle_count: int = 0
var _group_count: int = 0
var _max_depth_reached: int = 0


func _init(logger: RefCounted = null, primitive_factory: RefCounted = null) -> void:
	_logger = logger
	_primitive_factory = primitive_factory


## Builds the full scene tree under root from a resolved spec.
## @param resolved_spec: The fully resolved scene specification dictionary.
## @param root: Root Node3D to parent all generated nodes under.
## @return BuildResult with success stats or failure errors.
func build(resolved_spec: Dictionary, root: Node3D) -> BuildResult:
	var start_ms: int = Time.get_ticks_msec()

	_errors.clear()
	_node_count = 0
	_triangle_count = 0
	_group_count = 0
	_max_depth_reached = 0

	var limits: Dictionary = resolved_spec.get("limits", {})
	var max_tree_depth: int = limits.get("max_tree_depth", 16) as int

	if resolved_spec.has("environment"):
		_build_environment(resolved_spec["environment"], root)

	if resolved_spec.has("camera"):
		_build_camera(resolved_spec["camera"], root)

	if resolved_spec.has("lights"):
		_build_lights(resolved_spec["lights"] as Array, root)

	var nodes: Array = resolved_spec.get("nodes", []) as Array
	for i: int in range(nodes.size()):
		_build_node(nodes[i] as Dictionary, root, 0, max_tree_depth)

	var hash_val: String = build_hash(resolved_spec)
	var duration_ms: int = Time.get_ticks_msec() - start_ms

	var has_error: bool = false
	for err: Dictionary in _errors:
		if err.get("severity", "") == "error":
			has_error = true
			break

	if has_error:
		_log("error", "build failed with %d error(s) in %dms" % [_errors.size(), duration_ms])
		return BuildResult.create_failure(_errors, duration_ms)

	_log("info", "build succeeded: %d nodes, %d tris, %d groups, depth=%d, hash=%s in %dms" % [
		_node_count, _triangle_count, _group_count, _max_depth_reached, hash_val, duration_ms
	])
	return BuildResult.create_success(root, _node_count, _triangle_count, hash_val, duration_ms, _group_count, _max_depth_reached)


## Produces a deterministic SHA-256 hash of the spec for cache/diffing.
## @param spec: The scene specification dictionary.
## @return Hash string prefixed with "build:".
func build_hash(spec: Dictionary) -> String:
	var json_str: String = JSON.stringify(spec)
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(json_str.to_utf8_buffer())
	var digest: PackedByteArray = ctx.finish()
	return "build:" + digest.hex_encode()


# ---------------------------------------------------------------------------
# Private build helpers
# ---------------------------------------------------------------------------

func _build_environment(env: Dictionary, root: Node3D) -> void:
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.name = "AIGenEnvironment"

	var environment: Environment = Environment.new()
	var sky_type: String = env.get("sky_type", "procedural") as String

	match sky_type:
		"procedural":
			var sky: Sky = Sky.new()
			var sky_mat: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
			if env.has("sky_color_top"):
				sky_mat.sky_top_color = _array_to_color(env["sky_color_top"] as Array)
			if env.has("sky_color_bottom"):
				sky_mat.sky_horizon_color = _array_to_color(env["sky_color_bottom"] as Array)
			sky.sky_material = sky_mat
			environment.sky = sky
			environment.background_mode = Environment.BG_SKY
		"color":
			environment.background_mode = Environment.BG_COLOR
			if env.has("sky_color_top"):
				environment.background_color = _array_to_color(env["sky_color_top"] as Array)
		"hdri":
			environment.background_mode = Environment.BG_SKY
		_:
			environment.background_mode = Environment.BG_COLOR

	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if env.has("ambient_light_color"):
		environment.ambient_light_color = _array_to_color(env["ambient_light_color"] as Array)
	if env.has("ambient_light_energy"):
		environment.ambient_light_energy = env["ambient_light_energy"] as float

	var fog_enabled: bool = env.get("fog_enabled", false) as bool
	environment.volumetric_fog_enabled = fog_enabled
	if fog_enabled and env.has("fog_density"):
		environment.volumetric_fog_density = env["fog_density"] as float

	world_env.environment = environment
	root.add_child(world_env)
	_node_count += 1


func _build_camera(cam: Dictionary, root: Node3D) -> void:
	var camera: Camera3D = Camera3D.new()
	camera.name = "AIGenCamera"

	var cam_pos: Vector3 = _array_to_vector3(cam.get("position", [0, 1, 5]) as Array)
	var cam_target: Vector3 = _array_to_vector3(cam.get("look_at", [0, 0, 0]) as Array)

	camera.position = cam_pos
	camera.look_at_from_position(cam_pos, cam_target)

	if cam.has("fov_degrees"):
		camera.fov = cam["fov_degrees"] as float
	if cam.has("near_clip"):
		camera.near = cam["near_clip"] as float
	if cam.has("far_clip"):
		camera.far = cam["far_clip"] as float

	root.add_child(camera)
	_node_count += 1


func _build_lights(lights: Array, root: Node3D) -> void:
	for i: int in range(lights.size()):
		var light_spec: Dictionary = lights[i] as Dictionary
		var light_type: String = light_spec.get("type", "DirectionalLight3D") as String
		var light_node: Light3D = null

		match light_type:
			"DirectionalLight3D":
				light_node = DirectionalLight3D.new()
			"OmniLight3D":
				light_node = OmniLight3D.new()
			"SpotLight3D":
				light_node = SpotLight3D.new()
			_:
				_errors.append(_make_error(
					BUILD_ERR_LIGHT,
					"unknown light type: %s" % light_type,
					"lights[%d]" % i,
					"use DirectionalLight3D, OmniLight3D, or SpotLight3D"
				))
				continue

		light_node.name = light_spec.get("id", "AIGenLight_%d" % i) as String

		if light_spec.has("color"):
			light_node.light_color = _array_to_color(light_spec["color"] as Array)
		if light_spec.has("energy"):
			light_node.light_energy = light_spec["energy"] as float
		if light_spec.has("shadow_enabled"):
			light_node.shadow_enabled = light_spec["shadow_enabled"] as bool
		if light_spec.has("rotation_degrees"):
			light_node.rotation_degrees = _array_to_vector3(light_spec["rotation_degrees"] as Array)
		if light_spec.has("position"):
			light_node.position = _array_to_vector3(light_spec["position"] as Array)

		root.add_child(light_node)
		_node_count += 1


func _build_node(node: Dictionary, parent: Node3D, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		_errors.append(_make_error(
			BUILD_ERR_TREE_DEPTH,
			"max tree depth %d exceeded at depth %d" % [max_depth, depth],
			node.get("name", "unknown") as String,
			"flatten scene hierarchy or increase max_tree_depth"
		))
		return

	var instance: Node3D = null
	var is_resolved_asset: bool = false

	if node.has("_resolved_path"):
		var resolved_path: String = node["_resolved_path"] as String
		var scene: PackedScene = ResourceLoader.load(resolved_path) as PackedScene
		if scene != null:
			instance = scene.instantiate() as Node3D
			is_resolved_asset = true
			_log("debug", "loaded asset: %s" % resolved_path)
		else:
			_errors.append(_make_error(
				BUILD_ERR_ASSET_LOAD,
				"failed to load asset: %s" % resolved_path,
				node.get("name", "unknown") as String,
				"check path or provide a primitive_shape fallback"
			))

	if instance == null and (node.get("_fallback", false) as bool or not node.has("_resolved_path")):
		if node.has("_fallback_shape") and _primitive_factory != null:
			var fb_shape: String = str(node["_fallback_shape"])
			var fb_scale: Array = node.get("_fallback_scale", [1, 1, 1]) as Array
			var fb_color: Array = node.get("_fallback_color", [0.5, 0.5, 0.5]) as Array
			var fb_size: Vector3 = _array_to_vector3(fb_scale)
			var fb_mat: Dictionary = {"albedo": fb_color, "roughness": 0.5}
			if _primitive_factory.has_method("create_primitive_with_material"):
				instance = _primitive_factory.create_primitive_with_material(
					fb_shape, fb_size, fb_mat, false
				)
			else:
				instance = _primitive_factory.create_primitive(
					fb_shape, fb_size, _array_to_color(fb_color), 0.5, false
				)
			if instance != null:
				_triangle_count += _primitive_factory.get_triangle_count(fb_shape, fb_size)
		elif node.has("primitive_shape") and node["primitive_shape"] != null and _primitive_factory != null:
			var shape: String = str(node["primitive_shape"])
			if shape != "":
				var size: Vector3 = _array_to_vector3(node.get("scale", [1, 1, 1]) as Array)
				var mat: Dictionary = node.get("material", {}) as Dictionary
				var collision: bool = node.get("collision", false) as bool
				if _primitive_factory.has_method("create_primitive_with_material"):
					instance = _primitive_factory.create_primitive_with_material(
						shape, size, mat, collision
					)
				else:
					var albedo: Array = mat.get("albedo", [0.5, 0.5, 0.5]) as Array
					var roughness: float = mat.get("roughness", 0.5) as float
					instance = _primitive_factory.create_primitive(
						shape, size, _array_to_color(albedo), roughness, collision
					)
				if instance != null:
					_triangle_count += _primitive_factory.get_triangle_count(shape, size)

	if instance == null:
		instance = Node3D.new()

	instance.name = node.get("name", "Node_%d" % _node_count) as String

	if node.has("position"):
		instance.position = _array_to_vector3(node["position"] as Array)
	if node.has("rotation_degrees"):
		instance.rotation_degrees = _array_to_vector3(node["rotation_degrees"] as Array)

	if is_resolved_asset and node.has("scale"):
		instance.scale = _array_to_vector3(node["scale"] as Array)

	parent.add_child(instance)
	_node_count += 1
	if depth > _max_depth_reached:
		_max_depth_reached = depth

	var children: Array = node.get("children", []) as Array
	if not children.is_empty():
		_group_count += 1
	for i: int in range(children.size()):
		_build_node(children[i] as Dictionary, instance, depth + 1, max_depth)


# ---------------------------------------------------------------------------
# Conversion helpers
# ---------------------------------------------------------------------------

func _array_to_vector3(arr: Array) -> Vector3:
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(arr[0] as float, arr[1] as float, arr[2] as float)


func _array_to_color(arr: Array) -> Color:
	if arr.size() < 3:
		return Color.WHITE
	return Color(arr[0] as float, arr[1] as float, arr[2] as float)


func _make_error(code: String, message: String, path: String, fix_hint: String) -> Dictionary:
	return {
		"stage": "build",
		"severity": "error",
		"code": code,
		"message": message,
		"path": path,
		"fix_hint": fix_hint
	}


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
