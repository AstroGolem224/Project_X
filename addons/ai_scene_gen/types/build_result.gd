class_name BuildResult
extends RefCounted

## Result of scene build: either success with root and stats, or failure with errors.

var _success: bool = false
var _root: Node3D = null
var _node_count: int = 0
var _triangle_count: int = 0
var _errors: Array[Dictionary] = []
var _build_duration_ms: int = 0
var _build_hash: String = ""


## Creates a successful build result.
## @param root: Root Node3D of the built scene tree.
## @param node_count: Total node count built.
## @param triangle_count: Total mesh triangle count.
## @param build_hash: Hash identifying this build.
## @param duration_ms: Build duration in milliseconds.
## @return A configured BuildResult instance.
static func create_success(root: Node3D, node_count: int, triangle_count: int, build_hash: String, duration_ms: int) -> BuildResult:
	var r: BuildResult = BuildResult.new()
	r._success = true
	r._root = root
	r._node_count = node_count
	r._triangle_count = triangle_count
	r._build_hash = build_hash
	r._build_duration_ms = duration_ms
	return r


## Creates a failed build result.
## @param errors: Errors in error contract format.
## @param duration_ms: Build duration in milliseconds.
## @return A configured BuildResult instance.
static func create_failure(errors: Array[Dictionary], duration_ms: int) -> BuildResult:
	var r: BuildResult = BuildResult.new()
	r._success = false
	r._errors.assign(errors)
	r._build_duration_ms = duration_ms
	return r


func is_success() -> bool:
	return _success


func get_root() -> Node3D:
	return _root


func get_node_count() -> int:
	return _node_count


func get_triangle_count() -> int:
	return _triangle_count


func get_errors() -> Array[Dictionary]:
	return _errors.duplicate()


func get_build_duration_ms() -> int:
	return _build_duration_ms


func get_build_hash() -> String:
	return _build_hash
