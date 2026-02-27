@tool
extends GutTest

## Golden and snapshot tests for deterministic scene building.
## Verifies frozen SceneSpec JSON files produce expected node trees,
## and repeated builds yield identical results.

const OUTDOOR_SPEC_PATH: String = "res://addons/ai_scene_gen/mocks/outdoor_clearing.scenespec.json"
const INTERIOR_SPEC_PATH: String = "res://addons/ai_scene_gen/mocks/interior_room.scenespec.json"
const POS_TOLERANCE: float = 0.001
const COLOR_TOLERANCE: float = 0.01

const OUTDOOR_EXPECTED_NODE_COUNT: int = 9
const OUTDOOR_EXPECTED_TRI_COUNT: int = 1176
const OUTDOOR_EXPECTED_ROOT_CHILDREN: int = 7
const OUTDOOR_ROOT_NAMES: Array[String] = [
	"AIGenEnvironment", "AIGenCamera", "sun",
	"Ground", "OakTree_01", "Boulder_01", "DirtPath"
]

const INTERIOR_EXPECTED_NODE_COUNT: int = 8
const INTERIOR_EXPECTED_TRI_COUNT: int = 48
const INTERIOR_EXPECTED_ROOT_CHILDREN: int = 7
const INTERIOR_ROOT_NAMES: Array[String] = [
	"AIGenEnvironment", "AIGenCamera", "ceiling_light",
	"Floor", "WallNorth", "WallSouth", "Table"
]

var _factory: ProceduralPrimitiveFactory
var _resolver: AssetResolver
var _registry: AssetTagRegistry


func before_each() -> void:
	_factory = ProceduralPrimitiveFactory.new()
	_resolver = AssetResolver.new()
	_registry = AssetTagRegistry.new()


# region --- Helpers ---

func _load_spec(path: String) -> Dictionary:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed as Dictionary
	return {}


## Resolves and builds a spec with a fresh SceneBuilder each time.
func _resolve_and_build(spec: Dictionary) -> Dictionary:
	var builder: SceneBuilder = SceneBuilder.new(null, _factory)
	var resolved: ResolvedSpec = _resolver.resolve_nodes(spec, _registry)
	var root: Node3D = Node3D.new()
	var result: BuildResult = builder.build(resolved.get_spec(), root)
	return {"root": root, "result": result}


func _find_child_by_name(parent: Node, child_name: String) -> Node:
	for i: int in range(parent.get_child_count()):
		if str(parent.get_child(i).name) == child_name:
			return parent.get_child(i)
	return null


func _get_root_child_names(root: Node3D) -> Array[String]:
	var names: Array[String] = []
	for i: int in range(root.get_child_count()):
		names.append(str(root.get_child(i).name))
	return names


func _get_material_color(node: Node3D) -> Color:
	for i: int in range(node.get_child_count()):
		var child: Node = node.get_child(i)
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child as MeshInstance3D
			if mi.material_override is StandardMaterial3D:
				return (mi.material_override as StandardMaterial3D).albedo_color
	return Color(-1.0, -1.0, -1.0)


func _assert_pos(node: Node3D, expected: Vector3, label: String) -> void:
	if node == null:
		fail_test("%s is null — cannot check position" % label)
		return
	var tol: Vector3 = Vector3(POS_TOLERANCE, POS_TOLERANCE, POS_TOLERANCE)
	assert_almost_eq(node.position, expected, tol, "%s position" % label)


func _assert_color(got: Color, expected: Color, label: String) -> void:
	assert_almost_eq(got.r, expected.r, COLOR_TOLERANCE, "%s color.r" % label)
	assert_almost_eq(got.g, expected.g, COLOR_TOLERANCE, "%s color.g" % label)
	assert_almost_eq(got.b, expected.b, COLOR_TOLERANCE, "%s color.b" % label)


func _collect_tree_names(node: Node, depth: int = 0) -> Array[String]:
	var names: Array[String] = []
	for i: int in range(node.get_child_count()):
		var child: Node = node.get_child(i)
		var normalized: String = _normalize_auto_name(str(child.name))
		names.append("%d:%s" % [depth, normalized])
		names.append_array(_collect_tree_names(child, depth + 1))
	return names


## Strips Godot's unique ID suffix from auto-generated names (@Class@ID -> @Class).
func _normalize_auto_name(node_name: String) -> String:
	if node_name.begins_with("@") and node_name.count("@") >= 2:
		var at_pos: int = node_name.find("@", 1)
		return node_name.substr(0, at_pos)
	return node_name

# endregion


# region --- Golden: Outdoor Clearing ---

func test_golden_outdoor_structure() -> void:
	var spec: Dictionary = _load_spec(OUTDOOR_SPEC_PATH)
	assert_false(spec.is_empty(), "outdoor spec should load")

	var data: Dictionary = _resolve_and_build(spec)
	var root: Node3D = data["root"] as Node3D
	var result: BuildResult = data["result"] as BuildResult

	assert_true(result.is_success(), "outdoor build should succeed")
	assert_eq(result.get_node_count(), OUTDOOR_EXPECTED_NODE_COUNT, "outdoor node count")
	assert_eq(result.get_triangle_count(), OUTDOOR_EXPECTED_TRI_COUNT, "outdoor triangle count")
	assert_eq(root.get_child_count(), OUTDOOR_EXPECTED_ROOT_CHILDREN, "outdoor root children")
	assert_true(result.get_build_hash().begins_with("build:"), "hash prefix")
	assert_eq(result.get_build_hash().length(), 6 + 64, "hash length (build: + 64 hex)")

	var names: Array[String] = _get_root_child_names(root)
	for expected_name: String in OUTDOOR_ROOT_NAMES:
		assert_has(names, expected_name, "root should contain '%s'" % expected_name)

	assert_true(_find_child_by_name(root, "AIGenEnvironment") is WorldEnvironment, "env type")
	assert_true(_find_child_by_name(root, "AIGenCamera") is Camera3D, "camera type")
	assert_true(_find_child_by_name(root, "sun") is DirectionalLight3D, "sun type")

	var oak: Node = _find_child_by_name(root, "OakTree_01")
	assert_not_null(oak, "OakTree_01 exists")
	if oak != null:
		assert_eq(oak.get_child_count(), 2, "OakTree_01 children count")
		assert_not_null(_find_child_by_name(oak, "Trunk"), "Trunk exists")
		assert_not_null(_find_child_by_name(oak, "Canopy"), "Canopy exists")

	root.queue_free()


func test_golden_outdoor_positions() -> void:
	var spec: Dictionary = _load_spec(OUTDOOR_SPEC_PATH)
	var data: Dictionary = _resolve_and_build(spec)
	var root: Node3D = data["root"] as Node3D

	_assert_pos(
		_find_child_by_name(root, "Ground") as Node3D,
		Vector3(0.0, -0.25, 0.0), "Ground"
	)
	_assert_pos(
		_find_child_by_name(root, "OakTree_01") as Node3D,
		Vector3(-8.0, 0.0, 5.0), "OakTree_01"
	)
	_assert_pos(
		_find_child_by_name(root, "Boulder_01") as Node3D,
		Vector3(6.0, 0.3, -3.0), "Boulder_01"
	)
	_assert_pos(
		_find_child_by_name(root, "DirtPath") as Node3D,
		Vector3(0.0, 0.01, 0.0), "DirtPath"
	)

	var oak: Node3D = _find_child_by_name(root, "OakTree_01") as Node3D
	if oak != null:
		_assert_pos(
			_find_child_by_name(oak, "Trunk") as Node3D,
			Vector3(0.0, 1.5, 0.0), "Trunk"
		)
		_assert_pos(
			_find_child_by_name(oak, "Canopy") as Node3D,
			Vector3(0.0, 4.0, 0.0), "Canopy"
		)

	root.queue_free()


func test_golden_outdoor_materials() -> void:
	var spec: Dictionary = _load_spec(OUTDOOR_SPEC_PATH)
	var data: Dictionary = _resolve_and_build(spec)
	var root: Node3D = data["root"] as Node3D

	var ground: Node3D = _find_child_by_name(root, "Ground") as Node3D
	if ground != null:
		_assert_color(_get_material_color(ground), Color(0.35, 0.55, 0.2), "Ground")

	var oak: Node3D = _find_child_by_name(root, "OakTree_01") as Node3D
	if oak != null:
		var trunk: Node3D = _find_child_by_name(oak, "Trunk") as Node3D
		if trunk != null:
			_assert_color(_get_material_color(trunk), Color(0.4, 0.3, 0.15), "Trunk")
		var canopy: Node3D = _find_child_by_name(oak, "Canopy") as Node3D
		if canopy != null:
			_assert_color(_get_material_color(canopy), Color(0.2, 0.6, 0.15), "Canopy")

	var boulder: Node3D = _find_child_by_name(root, "Boulder_01") as Node3D
	if boulder != null:
		_assert_color(_get_material_color(boulder), Color(0.5, 0.5, 0.48), "Boulder_01")

	root.queue_free()

# endregion


# region --- Golden: Interior Room ---

func test_golden_interior_structure() -> void:
	var spec: Dictionary = _load_spec(INTERIOR_SPEC_PATH)
	assert_false(spec.is_empty(), "interior spec should load")

	var data: Dictionary = _resolve_and_build(spec)
	var root: Node3D = data["root"] as Node3D
	var result: BuildResult = data["result"] as BuildResult

	assert_true(result.is_success(), "interior build should succeed")
	assert_eq(result.get_node_count(), INTERIOR_EXPECTED_NODE_COUNT, "interior node count")
	assert_eq(result.get_triangle_count(), INTERIOR_EXPECTED_TRI_COUNT, "interior triangle count")
	assert_eq(root.get_child_count(), INTERIOR_EXPECTED_ROOT_CHILDREN, "interior root children")

	var names: Array[String] = _get_root_child_names(root)
	for expected_name: String in INTERIOR_ROOT_NAMES:
		assert_has(names, expected_name, "root should contain '%s'" % expected_name)

	assert_true(_find_child_by_name(root, "AIGenEnvironment") is WorldEnvironment, "env type")
	assert_true(_find_child_by_name(root, "AIGenCamera") is Camera3D, "camera type")
	assert_true(_find_child_by_name(root, "ceiling_light") is OmniLight3D, "ceiling_light type")

	var table: Node = _find_child_by_name(root, "Table")
	assert_not_null(table, "Table exists")
	if table != null:
		assert_eq(table.get_child_count(), 1, "Table children count")
		assert_not_null(_find_child_by_name(table, "TableTop"), "TableTop exists")

	root.queue_free()


func test_golden_interior_positions() -> void:
	var spec: Dictionary = _load_spec(INTERIOR_SPEC_PATH)
	var data: Dictionary = _resolve_and_build(spec)
	var root: Node3D = data["root"] as Node3D

	_assert_pos(
		_find_child_by_name(root, "Floor") as Node3D,
		Vector3(0.0, -0.05, 0.0), "Floor"
	)
	_assert_pos(
		_find_child_by_name(root, "WallNorth") as Node3D,
		Vector3(0.0, 2.0, 3.0), "WallNorth"
	)
	_assert_pos(
		_find_child_by_name(root, "WallSouth") as Node3D,
		Vector3(0.0, 2.0, -3.0), "WallSouth"
	)
	_assert_pos(
		_find_child_by_name(root, "Table") as Node3D,
		Vector3(0.0, 0.0, 0.5), "Table"
	)

	var table: Node3D = _find_child_by_name(root, "Table") as Node3D
	if table != null:
		_assert_pos(
			_find_child_by_name(table, "TableTop") as Node3D,
			Vector3(0.0, 0.75, 0.0), "TableTop"
		)

	root.queue_free()


func test_golden_interior_materials() -> void:
	var spec: Dictionary = _load_spec(INTERIOR_SPEC_PATH)
	var data: Dictionary = _resolve_and_build(spec)
	var root: Node3D = data["root"] as Node3D

	var floor_node: Node3D = _find_child_by_name(root, "Floor") as Node3D
	if floor_node != null:
		_assert_color(_get_material_color(floor_node), Color(0.6, 0.55, 0.45), "Floor")

	var wall_n: Node3D = _find_child_by_name(root, "WallNorth") as Node3D
	if wall_n != null:
		_assert_color(_get_material_color(wall_n), Color(0.85, 0.82, 0.78), "WallNorth")

	var table: Node3D = _find_child_by_name(root, "Table") as Node3D
	if table != null:
		var table_top: Node3D = _find_child_by_name(table, "TableTop") as Node3D
		if table_top != null:
			_assert_color(_get_material_color(table_top), Color(0.5, 0.35, 0.2), "TableTop")

	root.queue_free()

# endregion


# region --- Snapshot: Determinism Verification ---

func test_snapshot_outdoor_deterministic() -> void:
	var spec: Dictionary = _load_spec(OUTDOOR_SPEC_PATH)
	var data_a: Dictionary = _resolve_and_build(spec)
	var data_b: Dictionary = _resolve_and_build(spec)

	var result_a: BuildResult = data_a["result"] as BuildResult
	var result_b: BuildResult = data_b["result"] as BuildResult

	assert_eq(result_a.get_build_hash(), result_b.get_build_hash(), "outdoor hash identical across builds")
	assert_eq(result_a.get_node_count(), result_b.get_node_count(), "outdoor node count identical")
	assert_eq(result_a.get_triangle_count(), result_b.get_triangle_count(), "outdoor tri count identical")

	(data_a["root"] as Node3D).queue_free()
	(data_b["root"] as Node3D).queue_free()


func test_snapshot_interior_deterministic() -> void:
	var spec: Dictionary = _load_spec(INTERIOR_SPEC_PATH)
	var data_a: Dictionary = _resolve_and_build(spec)
	var data_b: Dictionary = _resolve_and_build(spec)

	var result_a: BuildResult = data_a["result"] as BuildResult
	var result_b: BuildResult = data_b["result"] as BuildResult

	assert_eq(result_a.get_build_hash(), result_b.get_build_hash(), "interior hash identical across builds")
	assert_eq(result_a.get_node_count(), result_b.get_node_count(), "interior node count identical")
	assert_eq(result_a.get_triangle_count(), result_b.get_triangle_count(), "interior tri count identical")

	(data_a["root"] as Node3D).queue_free()
	(data_b["root"] as Node3D).queue_free()


func test_snapshot_different_specs_differ() -> void:
	var outdoor: Dictionary = _load_spec(OUTDOOR_SPEC_PATH)
	var interior: Dictionary = _load_spec(INTERIOR_SPEC_PATH)

	var data_out: Dictionary = _resolve_and_build(outdoor)
	var data_in: Dictionary = _resolve_and_build(interior)

	var hash_out: String = (data_out["result"] as BuildResult).get_build_hash()
	var hash_in: String = (data_in["result"] as BuildResult).get_build_hash()

	assert_ne(hash_out, hash_in, "different specs produce different hashes")

	(data_out["root"] as Node3D).queue_free()
	(data_in["root"] as Node3D).queue_free()


func test_snapshot_tree_structure_identical() -> void:
	var spec: Dictionary = _load_spec(OUTDOOR_SPEC_PATH)
	var data_a: Dictionary = _resolve_and_build(spec)
	var data_b: Dictionary = _resolve_and_build(spec)

	var root_a: Node3D = data_a["root"] as Node3D
	var root_b: Node3D = data_b["root"] as Node3D

	var names_a: Array[String] = _collect_tree_names(root_a)
	var names_b: Array[String] = _collect_tree_names(root_b)

	assert_eq(names_a.size(), names_b.size(), "tree name list sizes should match")
	for i: int in range(mini(names_a.size(), names_b.size())):
		assert_eq(names_a[i], names_b[i], "tree node at index %d" % i)

	root_a.queue_free()
	root_b.queue_free()

# endregion
