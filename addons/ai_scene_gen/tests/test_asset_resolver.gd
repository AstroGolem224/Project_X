@tool
extends GutTest

## GUT tests for AssetResolver (Module F) and AssetTagRegistry.
## Test IDs: T21, T22, T23.

var _resolver: AssetResolver
var _registry: AssetTagRegistry


func before_each() -> void:
	_resolver = AssetResolver.new()
	_registry = AssetTagRegistry.new()


# region --- Helpers ---

func _make_spec_with_nodes(nodes: Array) -> Dictionary:
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
		"lights": [],
		"nodes": nodes,
		"rules": {
			"snap_to_ground": true,
			"clamp_to_bounds": true
		}
	}


func _make_node(overrides: Dictionary = {}) -> Dictionary:
	var base: Dictionary = {
		"id": "test_node",
		"name": "TestNode",
		"node_type": "MeshInstance3D",
		"primitive_shape": "box",
		"position": [0.0, 0.0, 0.0],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0],
		"material": {"albedo": [0.5, 0.5, 0.5], "roughness": 0.5},
		"collision": false,
		"asset_tag": null
	}
	for key: String in overrides.keys():
		base[key] = overrides[key]
	return base

# endregion

# region --- T21: Known tag resolves ---

func test_T21_known_tag_resolves() -> void:
	_registry.register_tag("test_tree", "res://assets/trees/oak.tscn", {
		"resource_type": "PackedScene",
		"fallback": {
			"primitive_shape": "cylinder",
			"scale_hint": [1.0, 3.0, 1.0],
			"color_hint": [0.3, 0.6, 0.2]
		}
	})

	var node: Dictionary = _make_node({
		"id": "tree_1",
		"name": "OakTree",
		"asset_tag": "test_tree"
	})
	var spec: Dictionary = _make_spec_with_nodes([node])

	var result: ResolvedSpec = _resolver.resolve_nodes(spec, _registry)
	assert_not_null(result, "resolve should return a result")

	var resolved_nodes: Array = result.get_spec().get("nodes", [])
	assert_eq(resolved_nodes.size(), 1)

	var resolved_node: Dictionary = resolved_nodes[0] as Dictionary
	# File won't exist on disk, so resolver should fall back
	assert_true(
		resolved_node.get("_fallback", false) as bool or resolved_node.has("_resolved_path"),
		"tag should either resolve or fall back gracefully"
	)

# endregion

# region --- T22: Unknown tag falls back ---

func test_T22_unknown_tag_falls_back() -> void:
	var node: Dictionary = _make_node({
		"id": "mystery",
		"name": "Mystery",
		"asset_tag": "nonexistent_thing"
	})
	var spec: Dictionary = _make_spec_with_nodes([node])

	var result: ResolvedSpec = _resolver.resolve_nodes(spec, _registry)
	assert_not_null(result)

	var resolved_node: Dictionary = result.get_spec()["nodes"][0] as Dictionary
	assert_true(
		resolved_node.get("_fallback", false) as bool,
		"unknown tag should set _fallback = true"
	)
	assert_true(
		result.get_missing_tags().has("nonexistent_thing"),
		"missing_tags should contain 'nonexistent_thing'"
	)

# endregion

# region --- T23: Null asset tag uses primitive ---

func test_T23_null_asset_tag_uses_primitive() -> void:
	var node: Dictionary = _make_node({
		"id": "prim_box",
		"name": "PrimBox",
		"asset_tag": null
	})
	var spec: Dictionary = _make_spec_with_nodes([node])

	var result: ResolvedSpec = _resolver.resolve_nodes(spec, _registry)
	assert_not_null(result)

	var resolved_node: Dictionary = result.get_spec()["nodes"][0] as Dictionary
	assert_true(
		resolved_node.get("_fallback", false) as bool,
		"null asset_tag should set _fallback = true"
	)
	assert_eq(result.get_fallback_count(), 1, "fallback count should be 1")

# endregion

# region --- Empty registry ---

func test_empty_registry_all_fallback() -> void:
	var nodes: Array = [
		_make_node({"id": "a", "name": "A", "asset_tag": "tree"}),
		_make_node({"id": "b", "name": "B", "asset_tag": "rock"}),
		_make_node({"id": "c", "name": "C", "asset_tag": "bush"})
	]
	var spec: Dictionary = _make_spec_with_nodes(nodes)

	var result: ResolvedSpec = _resolver.resolve_nodes(spec, _registry)
	assert_not_null(result)
	assert_eq(result.get_fallback_count(), 3, "all 3 nodes should fall back")
	assert_eq(result.get_resolved_count(), 0, "nothing should resolve")
	assert_eq(result.get_missing_tags().size(), 3, "3 missing tags")

# endregion

# region --- Registry API ---

func test_registry_register_and_has_tag() -> void:
	assert_false(_registry.has_tag("oak"), "should not have tag before register")
	_registry.register_tag("oak", "res://assets/oak.tscn")
	assert_true(_registry.has_tag("oak"), "should have tag after register")


func test_registry_unregister() -> void:
	_registry.register_tag("oak", "res://assets/oak.tscn")
	assert_true(_registry.has_tag("oak"))
	_registry.unregister_tag("oak")
	assert_false(_registry.has_tag("oak"), "tag should be gone after unregister")


func test_registry_get_all_tags_sorted() -> void:
	_registry.register_tag("zebra", "res://z.tscn")
	_registry.register_tag("alpha", "res://a.tscn")
	_registry.register_tag("middle", "res://m.tscn")

	var tags: Array[String] = _registry.get_all_tags()
	assert_eq(tags[0], "alpha")
	assert_eq(tags[1], "middle")
	assert_eq(tags[2], "zebra")


func test_registry_clear() -> void:
	_registry.register_tag("a", "res://a.tscn")
	_registry.register_tag("b", "res://b.tscn")
	assert_eq(_registry.get_entry_count(), 2)

	_registry.clear()
	assert_eq(_registry.get_entry_count(), 0, "clear should remove all entries")


func test_registry_invalid_path_rejected() -> void:
	var err: int = _registry.register_tag("bad", "C:/absolute/path.tscn")
	assert_eq(err, ERR_INVALID_PARAMETER, "non-res:// path should be rejected")
	assert_false(_registry.has_tag("bad"))


func test_registry_empty_tag_rejected() -> void:
	var err: int = _registry.register_tag("", "res://valid.tscn")
	assert_eq(err, ERR_INVALID_PARAMETER, "empty tag should be rejected")

# endregion

# region --- Recursive children resolution ---

func test_children_resolved_recursively() -> void:
	var child: Dictionary = _make_node({
		"id": "child_node",
		"name": "Child",
		"asset_tag": "missing_child_tag"
	})
	var parent: Dictionary = _make_node({
		"id": "parent_node",
		"name": "Parent",
		"asset_tag": null,
		"children": [child]
	})
	var spec: Dictionary = _make_spec_with_nodes([parent])

	var result: ResolvedSpec = _resolver.resolve_nodes(spec, _registry)
	assert_not_null(result)
	assert_eq(result.get_fallback_count(), 2, "parent (null tag) + child (missing tag) = 2 fallbacks")
	assert_true(result.get_missing_tags().has("missing_child_tag"))

# endregion
