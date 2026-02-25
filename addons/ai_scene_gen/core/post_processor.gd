@tool
class_name PostProcessor
extends RefCounted

## Post-processing pipeline that runs ordered passes over a built scene tree.
## Each pass may clamp, reframe, deduplicate, or warn about issues.

const LOG_CATEGORY: String = "ai_scene_gen.postprocess"

const POST_WARN_BOUNDS_CLAMPED: String = "POST_WARN_BOUNDS_CLAMPED"
const POST_WARN_SNAP_MISS: String = "POST_WARN_SNAP_MISS"
const POST_WARN_SNAP_NO_GROUND: String = "POST_WARN_SNAP_NO_GROUND"
const POST_WARN_CAMERA_FAR: String = "POST_WARN_CAMERA_FAR"
const POST_WARN_OVERLAP: String = "POST_WARN_OVERLAP"
const MAX_COLLISION_WARNINGS: int = 10

var _passes: Array = []
var _logger: RefCounted = null


func _init(logger: RefCounted = null) -> void:
	_logger = logger
	_passes = [
		BoundsClampPass.new(logger),
		SnapToGroundPass.new(logger),
		CameraFramingPass.new(logger),
		CollisionCheckPass.new(logger),
		NamingPass.new(logger),
	]


## Appends a custom pass to the end of the pipeline.
func add_pass(p: RefCounted) -> void:
	_passes.append(p)


## Removes the first pass whose get_pass_name() matches pass_name.
func remove_pass(pass_name: String) -> void:
	for i: int in range(_passes.size()):
		if _passes[i].get_pass_name() == pass_name:
			_passes.remove_at(i)
			return


## Executes every pass in order, returning the combined warnings array.
## @param root: Scene root node to process.
## @param spec: The resolved scene specification dictionary.
## @return Combined array of warning dictionaries from all passes.
func execute_all(root: Node3D, spec: Dictionary) -> Array[Dictionary]:
	var all_warnings: Array[Dictionary] = []
	for p: RefCounted in _passes:
		var pass_name: String = p.get_pass_name()
		var start_ms: int = Time.get_ticks_msec()
		var warnings: Array[Dictionary] = p.execute(root, spec)
		var elapsed_ms: int = Time.get_ticks_msec() - start_ms
		_log("info", "Pass '%s' completed in %d ms — %d warning(s)" % [pass_name, elapsed_ms, warnings.size()])
		all_warnings.append_array(warnings)
	return all_warnings


## Returns the ordered list of pass names currently in the pipeline.
func get_pass_names() -> Array[String]:
	var names: Array[String] = []
	for p: RefCounted in _passes:
		names.append(p.get_pass_name())
	return names


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


# region --- Inner Classes ---


## Base class for all post-processing passes.
class PostProcessorPass extends RefCounted:
	var _logger: RefCounted = null

	func _init(logger: RefCounted = null) -> void:
		_logger = logger

	func get_pass_name() -> String:
		return ""

	func execute(_root: Node3D, _spec: Dictionary) -> Array[Dictionary]:
		return []

	func _make_warning(code: String, message: String, fix_hint: String, node_path: String = "") -> Dictionary:
		return {
			"code": code,
			"message": message,
			"path": node_path,
			"severity": "warning",
			"stage": "post",
			"fix_hint": fix_hint,
		}

	func _log(level: String, message: String) -> void:
		if _logger == null:
			return
		match level:
			"debug":
				_logger.log_debug("ai_scene_gen.postprocess", message)
			"info":
				_logger.log_info("ai_scene_gen.postprocess", message)
			"warning":
				_logger.log_warning("ai_scene_gen.postprocess", message)
			"error":
				_logger.log_error("ai_scene_gen.postprocess", message)


## Clamps every child node's position to the scene bounds defined in spec.meta.bounds_meters.
class BoundsClampPass extends PostProcessorPass:

	func get_pass_name() -> String:
		return "BoundsClamp"

	func execute(root: Node3D, spec: Dictionary) -> Array[Dictionary]:
		var warnings: Array[Dictionary] = []
		var meta: Dictionary = spec.get("meta", {}) as Dictionary
		var bounds: Array = meta.get("bounds_meters", [10.0, 10.0, 10.0]) as Array
		if bounds.size() < 3:
			return warnings

		var half_x: float = float(bounds[0]) / 2.0
		var max_y: float = float(bounds[1])
		var half_z: float = float(bounds[2]) / 2.0

		var children: Array[Node] = _collect_descendants(root)
		for child: Node in children:
			if not child is Node3D:
				continue
			var node: Node3D = child as Node3D
			var original: Vector3 = node.position
			var clamped: Vector3 = Vector3(
				clampf(original.x, -half_x, half_x),
				clampf(original.y, -1.0, max_y),
				clampf(original.z, -half_z, half_z),
			)
			if not clamped.is_equal_approx(original):
				node.position = clamped
				var node_path: String = str(node.get_path()) if node.is_inside_tree() else str(node.name)
				warnings.append(_make_warning(
					"POST_WARN_BOUNDS_CLAMPED",
					"Node '%s' was clamped to scene bounds." % node.name,
					"Move the node inside the scene bounds.",
					node_path,
				))
		return warnings

	func _collect_descendants(node: Node) -> Array[Node]:
		var result: Array[Node] = []
		for child: Node in node.get_children():
			result.append(child)
			result.append_array(_collect_descendants(child))
		return result


## Warns about nodes that appear to be floating above the ground plane.
## MVP: does not raycast — only detects and warns.
class SnapToGroundPass extends PostProcessorPass:
	const _SKIP_TYPES: Array[String] = ["Camera3D", "DirectionalLight3D", "OmniLight3D", "SpotLight3D", "WorldEnvironment"]
	const _FLOAT_THRESHOLD: float = 0.5

	func get_pass_name() -> String:
		return "SnapToGround"

	func execute(root: Node3D, spec: Dictionary) -> Array[Dictionary]:
		var warnings: Array[Dictionary] = []
		var rules: Dictionary = spec.get("rules", {}) as Dictionary
		if not rules.get("snap_to_ground", false):
			return warnings

		var ground_node: Node3D = _find_ground(root)
		if ground_node == null:
			warnings.append(_make_warning(
				"POST_WARN_SNAP_NO_GROUND",
				"No ground plane found — snap-to-ground skipped.",
				"Add a node named 'Ground' or 'Floor', or set role metadata to 'ground'.",
			))
			return warnings

		var ground_y: float = ground_node.position.y

		var children: Array[Node] = _collect_descendants(root)
		for child: Node in children:
			if not child is Node3D:
				continue
			var node: Node3D = child as Node3D
			if node == ground_node:
				continue
			if _is_skip_type(node):
				continue
			if node.position.y > ground_y + _FLOAT_THRESHOLD:
				var node_path: String = str(node.get_path()) if node.is_inside_tree() else str(node.name)
				warnings.append(_make_warning(
					"POST_WARN_SNAP_MISS",
					"Node '%s' could not be snapped to ground (no surface below)." % node.name,
					"Manually lower this node or enable physics-based snap.",
					node_path,
				))
		return warnings

	func _find_ground(root: Node3D) -> Node3D:
		for child: Node in root.get_children():
			if not child is Node3D:
				continue
			var n3d: Node3D = child as Node3D
			var lname: String = n3d.name.to_lower()
			if lname.contains("ground") or lname.contains("floor"):
				return n3d
			if n3d.has_meta("role") and str(n3d.get_meta("role")) == "ground":
				return n3d
		return null

	func _is_skip_type(node: Node3D) -> bool:
		var cls: String = node.get_class()
		return cls in _SKIP_TYPES

	func _collect_descendants(node: Node) -> Array[Node]:
		var result: Array[Node] = []
		for child: Node in node.get_children():
			result.append(child)
			result.append_array(_collect_descendants(child))
		return result


## Repositions the camera so the entire scene AABB is visible in frame.
class CameraFramingPass extends PostProcessorPass:
	const _FRAMING_MARGIN: float = 1.5

	func get_pass_name() -> String:
		return "CameraFraming"

	func execute(root: Node3D, _spec: Dictionary) -> Array[Dictionary]:
		var warnings: Array[Dictionary] = []
		var camera: Camera3D = _find_camera(root)
		if camera == null:
			return warnings

		var aabb: AABB = _compute_scene_aabb(root, camera)
		if aabb.size.is_equal_approx(Vector3.ZERO):
			return warnings

		var center: Vector3 = aabb.get_center()
		var aabb_size: Vector3 = aabb.size
		var max_extent: float = maxf(aabb_size.x, maxf(aabb_size.y, aabb_size.z))
		var half_fov_rad: float = deg_to_rad(camera.fov / 2.0)
		var distance: float = max_extent / (2.0 * tan(half_fov_rad)) * _FRAMING_MARGIN

		if distance > 200.0:
			warnings.append(_make_warning(
				"POST_WARN_CAMERA_FAR",
				"Camera framing distance is %.1f m — scene may appear very small." % distance,
				"Reduce scene bounds or group objects closer together.",
			))

		camera.position = center + Vector3(0.0, aabb_size.y * 0.5, distance)
		var forward: Vector3 = (center - camera.position).normalized()
		if not forward.is_equal_approx(Vector3.ZERO):
			camera.basis = Basis.looking_at(forward)
		return warnings

	func _find_camera(root: Node3D) -> Camera3D:
		for child: Node in root.get_children():
			if child is Camera3D:
				return child as Camera3D
		return null

	func _compute_scene_aabb(root: Node3D, camera: Camera3D) -> AABB:
		var first: bool = true
		var combined: AABB = AABB()
		for child: Node in root.get_children():
			if child == camera:
				continue
			if child is WorldEnvironment:
				continue
			if not child is Node3D:
				continue
			if child is Light3D:
				continue
			var node: Node3D = child as Node3D
			var node_aabb: AABB = _get_node_aabb(node)
			if first:
				combined = node_aabb
				first = false
			else:
				combined = combined.merge(node_aabb)
		return combined

	func _get_node_aabb(node: Node3D) -> AABB:
		if node is MeshInstance3D:
			var mi: MeshInstance3D = node as MeshInstance3D
			if mi.mesh != null:
				return mi.transform * mi.mesh.get_aabb()
		var pos: Vector3 = node.position
		var half: Vector3 = node.scale * 0.5
		return AABB(pos - half, node.scale)


## Detects significant AABB overlaps between MeshInstance3D pairs.
class CollisionCheckPass extends PostProcessorPass:
	const _OVERLAP_RATIO: float = 0.5

	func get_pass_name() -> String:
		return "CollisionCheck"

	func execute(root: Node3D, _spec: Dictionary) -> Array[Dictionary]:
		var warnings: Array[Dictionary] = []
		var meshes: Array[MeshInstance3D] = _collect_meshes(root)

		for i: int in range(meshes.size()):
			if warnings.size() >= PostProcessor.MAX_COLLISION_WARNINGS:
				break
			var a: MeshInstance3D = meshes[i]
			var aabb_a: AABB = _approx_aabb(a)
			for j: int in range(i + 1, meshes.size()):
				if warnings.size() >= PostProcessor.MAX_COLLISION_WARNINGS:
					break
				var b: MeshInstance3D = meshes[j]
				var aabb_b: AABB = _approx_aabb(b)
				if _overlaps_significantly(aabb_a, aabb_b):
					warnings.append(_make_warning(
						"POST_WARN_OVERLAP",
						"Nodes '%s' and '%s' overlap significantly." % [a.name, b.name],
						"Move one of the nodes or reduce its scale.",
					))
		return warnings

	func _collect_meshes(root: Node) -> Array[MeshInstance3D]:
		var result: Array[MeshInstance3D] = []
		for child: Node in root.get_children():
			if child is MeshInstance3D:
				result.append(child as MeshInstance3D)
			result.append_array(_collect_meshes(child))
		return result

	func _approx_aabb(node: MeshInstance3D) -> AABB:
		if node.mesh != null:
			return node.transform * node.mesh.get_aabb()
		var half: Vector3 = node.scale * 0.5
		return AABB(node.position - half, node.scale)

	func _overlaps_significantly(a: AABB, b: AABB) -> bool:
		var intersection: AABB = a.intersection(b)
		if intersection.size.x <= 0.0 or intersection.size.y <= 0.0 or intersection.size.z <= 0.0:
			return false
		var inter_vol: float = intersection.size.x * intersection.size.y * intersection.size.z
		var vol_a: float = a.size.x * a.size.y * a.size.z
		var vol_b: float = b.size.x * b.size.y * b.size.z
		var smaller: float = minf(vol_a, vol_b)
		if smaller <= 0.0:
			return false
		return inter_vol / smaller > _OVERLAP_RATIO


## Deduplicates node names by appending _N suffixes.
class NamingPass extends PostProcessorPass:

	func get_pass_name() -> String:
		return "NamingPass"

	func execute(root: Node3D, _spec: Dictionary) -> Array[Dictionary]:
		var seen: Dictionary = {}
		var children: Array[Node] = _collect_descendants(root)
		for child: Node in children:
			if not child is Node3D:
				continue
			var original_name: String = str(child.name)
			if seen.has(original_name):
				var count: int = (seen[original_name] as int) + 1
				seen[original_name] = count
				child.name = "%s_%d" % [original_name, count]
			else:
				seen[original_name] = 0
		return []

	func _collect_descendants(node: Node) -> Array[Node]:
		var result: Array[Node] = []
		for child: Node in node.get_children():
			result.append(child)
			result.append_array(_collect_descendants(child))
		return result


# endregion
