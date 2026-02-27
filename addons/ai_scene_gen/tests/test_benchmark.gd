@tool
extends GutTest

## Performance benchmarks and memory profiling for SceneBuilder.
## Measures build-time scaling across spec sizes, verifies linear complexity,
## enforces per-tier time thresholds, and validates cleanup after discard/apply.

const SHAPES: Array[String] = ["box", "sphere", "cylinder", "capsule", "plane"]
const BENCH_ITERATIONS: int = 3

const TIER_SMALL: int = 10
const TIER_MEDIUM: int = 100
const TIER_LARGE: int = 500

const THRESHOLD_SMALL_MS: float = 50.0
const THRESHOLD_MEDIUM_MS: float = 500.0
const THRESHOLD_LARGE_MS: float = 2500.0

const LINEARITY_TOLERANCE: float = 3.0

var _factory: ProceduralPrimitiveFactory
var _resolver: AssetResolver
var _registry: AssetTagRegistry


func before_each() -> void:
	_factory = ProceduralPrimitiveFactory.new()
	_resolver = AssetResolver.new()
	_registry = AssetTagRegistry.new()


# region --- Spec Generator ---

## Builds a minimal valid SceneSpec dictionary with N flat nodes.
func _make_spec(node_count: int, seed_val: int = 42) -> Dictionary:
	var nodes: Array[Dictionary] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val

	for i: int in range(node_count):
		var shape_idx: int = i % SHAPES.size()
		var node_dict: Dictionary = {
			"id": "node_%04d" % i,
			"name": "Node_%04d" % i,
			"node_type": "MeshInstance3D",
			"primitive_shape": SHAPES[shape_idx],
			"position": [rng.randf_range(-20.0, 20.0), 0.0, rng.randf_range(-20.0, 20.0)],
			"rotation_degrees": [0.0, rng.randf_range(0.0, 360.0), 0.0],
			"scale": [rng.randf_range(0.5, 3.0), rng.randf_range(0.5, 3.0), rng.randf_range(0.5, 3.0)],
			"material": {
				"albedo": [rng.randf(), rng.randf(), rng.randf()],
				"roughness": rng.randf_range(0.1, 1.0)
			},
			"collision": false,
			"asset_tag": null,
			"children": [],
			"metadata": {}
		}
		nodes.append(node_dict)

	return {
		"spec_version": "1.0.0",
		"meta": {
			"generator": "ai_scene_gen",
			"style_preset": "blockout",
			"bounds_meters": [40.0, 20.0, 40.0],
			"prompt_hash": "sha256:benchmark",
			"timestamp_utc": "2026-02-27T00:00:00Z"
		},
		"determinism": {
			"seed": seed_val,
			"variation_mode": false,
			"fingerprint": "bench_%d" % node_count
		},
		"limits": {
			"max_nodes": maxi(node_count * 2, 256),
			"max_scale_component": 50.0,
			"max_light_energy": 16.0,
			"max_tree_depth": 4,
			"poly_budget_triangles": 500000
		},
		"nodes": nodes,
		"rules": {
			"snap_to_ground": false,
			"clamp_to_bounds": false,
			"disallow_overlaps": false
		}
	}


## Builds a spec with nested children to stress tree depth.
func _make_nested_spec(breadth: int, depth: int, seed_val: int = 42) -> Dictionary:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_val
	var top_nodes: Array[Dictionary] = []
	for i: int in range(breadth):
		top_nodes.append(_make_nested_node(i, 0, depth, rng))

	return {
		"spec_version": "1.0.0",
		"meta": {
			"generator": "ai_scene_gen",
			"style_preset": "blockout",
			"bounds_meters": [40.0, 20.0, 40.0],
			"prompt_hash": "sha256:bench_nested",
			"timestamp_utc": "2026-02-27T00:00:00Z"
		},
		"determinism": {
			"seed": seed_val,
			"variation_mode": false,
			"fingerprint": "bench_nested_%d_%d" % [breadth, depth]
		},
		"limits": {
			"max_nodes": 4096,
			"max_scale_component": 50.0,
			"max_light_energy": 16.0,
			"max_tree_depth": depth + 1,
			"poly_budget_triangles": 500000
		},
		"nodes": top_nodes,
		"rules": {
			"snap_to_ground": false,
			"clamp_to_bounds": false,
			"disallow_overlaps": false
		}
	}


func _make_nested_node(idx: int, current_depth: int, max_depth: int, rng: RandomNumberGenerator) -> Dictionary:
	var children: Array[Dictionary] = []
	if current_depth < max_depth:
		children.append(_make_nested_node(0, current_depth + 1, max_depth, rng))

	var shape_idx: int = idx % SHAPES.size()
	return {
		"id": "d%d_n%d" % [current_depth, idx],
		"name": "D%d_N%d" % [current_depth, idx],
		"node_type": "MeshInstance3D",
		"primitive_shape": SHAPES[shape_idx],
		"position": [rng.randf_range(-5.0, 5.0), 0.0, rng.randf_range(-5.0, 5.0)],
		"rotation_degrees": [0.0, 0.0, 0.0],
		"scale": [1.0, 1.0, 1.0],
		"material": {"albedo": [0.5, 0.5, 0.5], "roughness": 0.5},
		"collision": false,
		"asset_tag": null,
		"children": children,
		"metadata": {}
	}

# endregion


# region --- Bench Helpers ---

## Resolves + builds a spec, returns {"root": Node3D, "result": BuildResult, "usec": int}.
func _bench_build(spec: Dictionary) -> Dictionary:
	var resolved: ResolvedSpec = _resolver.resolve_nodes(spec, _registry)
	var root: Node3D = Node3D.new()
	var builder: SceneBuilder = SceneBuilder.new(null, _factory)
	var t0: int = Time.get_ticks_usec()
	var result: BuildResult = builder.build(resolved.get_spec(), root)
	var elapsed: int = Time.get_ticks_usec() - t0
	return {"root": root, "result": result, "usec": elapsed}


## Runs build N times and returns median elapsed_usec.
func _bench_median(spec: Dictionary, iterations: int) -> float:
	var times: Array[float] = []
	var roots: Array[Node3D] = []
	for _i: int in range(iterations):
		var data: Dictionary = _bench_build(spec)
		times.append(data["usec"] as float)
		roots.append(data["root"] as Node3D)

	for r: Node3D in roots:
		r.queue_free()

	times.sort()
	var mid: int = iterations / 2
	if iterations % 2 == 1:
		return times[mid]
	return (times[mid - 1] + times[mid]) / 2.0


## Counts all descendants recursively (including node itself).
func _count_tree(node: Node) -> int:
	var count: int = 1
	for i: int in range(node.get_child_count()):
		count += _count_tree(node.get_child(i))
	return count

# endregion


# region --- Build-Time Benchmarks ---

func test_build_small_under_threshold() -> void:
	var spec: Dictionary = _make_spec(TIER_SMALL)
	var median_us: float = _bench_median(spec, BENCH_ITERATIONS)
	var median_ms: float = median_us / 1000.0
	gut.p("  small (%d nodes): %.2f ms (threshold %.0f ms)" % [TIER_SMALL, median_ms, THRESHOLD_SMALL_MS])
	assert_true(median_ms < THRESHOLD_SMALL_MS,
		"small build (%.2f ms) should be under %.0f ms" % [median_ms, THRESHOLD_SMALL_MS])


func test_build_medium_under_threshold() -> void:
	var spec: Dictionary = _make_spec(TIER_MEDIUM)
	var median_us: float = _bench_median(spec, BENCH_ITERATIONS)
	var median_ms: float = median_us / 1000.0
	gut.p("  medium (%d nodes): %.2f ms (threshold %.0f ms)" % [TIER_MEDIUM, median_ms, THRESHOLD_MEDIUM_MS])
	assert_true(median_ms < THRESHOLD_MEDIUM_MS,
		"medium build (%.2f ms) should be under %.0f ms" % [median_ms, THRESHOLD_MEDIUM_MS])


func test_build_large_under_threshold() -> void:
	var spec: Dictionary = _make_spec(TIER_LARGE)
	var median_us: float = _bench_median(spec, BENCH_ITERATIONS)
	var median_ms: float = median_us / 1000.0
	gut.p("  large (%d nodes): %.2f ms (threshold %.0f ms)" % [TIER_LARGE, median_ms, THRESHOLD_LARGE_MS])
	assert_true(median_ms < THRESHOLD_LARGE_MS,
		"large build (%.2f ms) should be under %.0f ms" % [median_ms, THRESHOLD_LARGE_MS])


func test_build_time_scales_linearly() -> void:
	var sizes: Array[int] = [10, 50, 100, 200]
	var times: Array[float] = []
	for s: int in sizes:
		var spec: Dictionary = _make_spec(s)
		var t: float = _bench_median(spec, BENCH_ITERATIONS)
		times.append(t)
		gut.p("  %d nodes -> %.1f us" % [s, t])

	var time_10: float = maxf(times[0], 1.0)
	var time_200: float = times[3]
	var expected_ratio: float = 200.0 / 10.0
	var actual_ratio: float = time_200 / time_10
	gut.p("  ratio 200/10: expected ~%.1f, actual %.1f (tolerance %.1fx)" % [
		expected_ratio, actual_ratio, LINEARITY_TOLERANCE])
	assert_true(actual_ratio < expected_ratio * LINEARITY_TOLERANCE,
		"build time ratio (%.1f) should be under %.1fx linear (%.1f)" % [
			actual_ratio, LINEARITY_TOLERANCE, expected_ratio * LINEARITY_TOLERANCE])


func test_build_nested_spec_performance() -> void:
	var spec: Dictionary = _make_nested_spec(10, 4)
	var data: Dictionary = _bench_build(spec)
	var result: BuildResult = data["result"] as BuildResult
	var root: Node3D = data["root"] as Node3D
	var elapsed_ms: float = (data["usec"] as float) / 1000.0

	assert_true(result.is_success(), "nested build should succeed")
	gut.p("  nested (10 branches x depth 4): %d nodes, %.2f ms" % [
		result.get_node_count(), elapsed_ms])
	assert_true(elapsed_ms < THRESHOLD_MEDIUM_MS,
		"nested build (%.2f ms) should be under %.0f ms" % [elapsed_ms, THRESHOLD_MEDIUM_MS])
	root.queue_free()


func test_build_result_duration_consistent() -> void:
	var spec: Dictionary = _make_spec(TIER_MEDIUM)
	var resolved: ResolvedSpec = _resolver.resolve_nodes(spec, _registry)
	var root: Node3D = Node3D.new()
	var builder: SceneBuilder = SceneBuilder.new(null, _factory)
	var result: BuildResult = builder.build(resolved.get_spec(), root)

	assert_true(result.is_success(), "build should succeed")
	assert_true(result.get_build_duration_ms() >= 0,
		"duration_ms (%d) should be non-negative" % result.get_build_duration_ms())
	root.queue_free()

# endregion


# region --- Memory Profiling ---

func test_node_count_matches_spec() -> void:
	var node_count: int = 50
	var spec: Dictionary = _make_spec(node_count)
	var data: Dictionary = _bench_build(spec)
	var result: BuildResult = data["result"] as BuildResult
	var root: Node3D = data["root"] as Node3D

	assert_true(result.is_success(), "build should succeed")
	assert_eq(result.get_node_count(), node_count,
		"BuildResult node_count (%d) should match spec nodes (%d)" % [
			result.get_node_count(), node_count])
	var tree_total: int = _count_tree(root) - 1
	assert_true(tree_total >= node_count,
		"actual tree (%d) should have at least spec-level nodes (%d)" % [tree_total, node_count])
	root.queue_free()


func test_large_spec_node_count_matches() -> void:
	var spec: Dictionary = _make_spec(TIER_LARGE)
	var data: Dictionary = _bench_build(spec)
	var result: BuildResult = data["result"] as BuildResult
	var root: Node3D = data["root"] as Node3D

	assert_true(result.is_success(), "large build should succeed")
	assert_eq(result.get_node_count(), TIER_LARGE,
		"large BuildResult node_count (%d) should match spec nodes (%d)" % [
			result.get_node_count(), TIER_LARGE])
	var tree_total: int = _count_tree(root) - 1
	assert_true(tree_total >= TIER_LARGE,
		"actual tree (%d) should have at least spec-level nodes (%d)" % [tree_total, TIER_LARGE])
	root.queue_free()


func test_cleanup_after_discard() -> void:
	var spec: Dictionary = _make_spec(50)
	var data: Dictionary = _bench_build(spec)
	var root: Node3D = data["root"] as Node3D
	var result: BuildResult = data["result"] as BuildResult
	assert_true(result.is_success(), "build should succeed")

	var scene_root: Node3D = Node3D.new()
	add_child(scene_root)
	var preview: PreviewLayer = PreviewLayer.new()
	var show_err: Dictionary = preview.show_preview(root, scene_root)
	assert_true(show_err.is_empty(), "show_preview should succeed")
	assert_true(preview.is_preview_active(), "preview should be active")

	var pre_count: int = _count_tree(scene_root)
	assert_true(pre_count > 1, "scene_root should have children after show")

	preview.discard()
	assert_false(preview.is_preview_active(), "preview should be inactive after discard")
	assert_eq(preview.get_preview_node_count(), 0, "preview node count should be 0 after discard")
	scene_root.queue_free()


func test_cleanup_after_apply() -> void:
	var spec: Dictionary = _make_spec(30)
	var data: Dictionary = _bench_build(spec)
	var root: Node3D = data["root"] as Node3D
	var result: BuildResult = data["result"] as BuildResult
	assert_true(result.is_success(), "build should succeed")

	var scene_root: Node3D = Node3D.new()
	add_child(scene_root)
	var preview: PreviewLayer = PreviewLayer.new()
	preview.show_preview(root, scene_root)

	var apply_err: Dictionary = preview.apply_to_scene(null, scene_root)
	assert_true(apply_err.is_empty(), "apply should succeed")
	assert_false(preview.is_preview_active(), "preview should be inactive after apply")

	var applied_count: int = scene_root.get_child_count()
	assert_true(applied_count > 0,
		"scene_root should have children after apply (got %d)" % applied_count)
	scene_root.queue_free()


func test_no_leak_repeated_build_discard() -> void:
	var preview: PreviewLayer = PreviewLayer.new()
	var scene_root: Node3D = Node3D.new()
	add_child(scene_root)

	for iteration: int in range(5):
		var spec: Dictionary = _make_spec(20, iteration)
		var data: Dictionary = _bench_build(spec)
		var root: Node3D = data["root"] as Node3D
		var result: BuildResult = data["result"] as BuildResult
		assert_true(result.is_success(), "iteration %d build should succeed" % iteration)

		preview.show_preview(root, scene_root)
		assert_true(preview.is_preview_active(), "iteration %d preview active" % iteration)

		preview.discard()
		assert_false(preview.is_preview_active(), "iteration %d preview discarded" % iteration)
		assert_eq(preview.get_preview_node_count(), 0,
			"iteration %d preview count should be 0" % iteration)

	assert_false(preview.is_preview_active(), "preview should be inactive after all discards")
	assert_eq(preview.get_preview_node_count(), 0, "final preview count should be 0")
	scene_root.queue_free()


func test_triangle_count_positive_for_primitives() -> void:
	var spec: Dictionary = _make_spec(20)
	var data: Dictionary = _bench_build(spec)
	var result: BuildResult = data["result"] as BuildResult

	assert_true(result.is_success(), "build should succeed")
	assert_true(result.get_triangle_count() > 0,
		"triangle count (%d) should be positive for primitive nodes" % result.get_triangle_count())
	gut.p("  20 primitive nodes -> %d triangles" % result.get_triangle_count())
	(data["root"] as Node3D).queue_free()


func test_hash_deterministic_across_sizes() -> void:
	var spec: Dictionary = _make_spec(100)
	var data_a: Dictionary = _bench_build(spec)
	var data_b: Dictionary = _bench_build(spec)

	var hash_a: String = (data_a["result"] as BuildResult).get_build_hash()
	var hash_b: String = (data_b["result"] as BuildResult).get_build_hash()
	assert_eq(hash_a, hash_b, "same spec should produce same hash")

	(data_a["root"] as Node3D).queue_free()
	(data_b["root"] as Node3D).queue_free()

# endregion
