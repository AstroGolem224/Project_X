@tool
class_name SceneSpecValidator
extends RefCounted

## Validates scene spec dictionaries against the schema, enforcing type safety,
## value ranges, security constraints, and structural integrity.

# region --- Constants ---

const SCHEMA_VERSION: String = "1.0.0"

const ALLOWED_NODE_TYPES: Array[String] = [
	"MeshInstance3D", "StaticBody3D", "DirectionalLight3D", "OmniLight3D",
	"SpotLight3D", "Camera3D", "WorldEnvironment", "Node3D"
]

const ALLOWED_PRIMITIVE_SHAPES: Array[String] = [
	"box", "sphere", "cylinder", "capsule", "plane"
]

const ALLOWED_STYLE_PRESETS: Array[String] = [
	"blockout", "stylized", "realistic-lite"
]

const ALLOWED_SKY_TYPES: Array[String] = [
	"procedural", "color", "hdri"
]

const ALLOWED_LIGHT_TYPES: Array[String] = [
	"DirectionalLight3D", "OmniLight3D", "SpotLight3D"
]

const FORBIDDEN_CODE_PATTERNS: Array[String] = [
	"eval(", "load(", "preload(", "OS.", "FileAccess.",
	"Expression", "ClassDB", "Engine.get", "GDScript",
	"JavaScript", "Thread", "Mutex", "Semaphore"
]

const _REQUIRED_TOP_LEVEL_FIELDS: Array[String] = [
	"spec_version", "meta", "determinism", "limits",
	"environment", "camera", "lights", "nodes", "rules"
]

const _REQUIRED_META_FIELDS: Array[String] = [
	"generator", "style_preset", "bounds_meters", "prompt_hash", "timestamp_utc"
]

const _REQUIRED_DETERMINISM_FIELDS: Array[String] = [
	"seed", "variation_mode", "fingerprint"
]

const _REQUIRED_LIMITS_FIELDS: Array[String] = [
	"max_nodes", "max_scale_component", "max_light_energy",
	"max_tree_depth", "poly_budget_triangles"
]

const _REQUIRED_ENVIRONMENT_FIELDS: Array[String] = [
	"sky_type", "sky_color_top", "sky_color_bottom",
	"ambient_light_color", "ambient_light_energy", "fog_enabled", "fog_density"
]

const _REQUIRED_CAMERA_FIELDS: Array[String] = [
	"position", "look_at", "fov_degrees"
]

const _REQUIRED_LIGHT_FIELDS: Array[String] = [
	"id", "type", "rotation_degrees", "color", "energy", "shadow_enabled"
]

const _REQUIRED_NODE_FIELDS: Array[String] = [
	"id", "name", "node_type", "position", "rotation_degrees", "scale"
]

const _ALLOWED_NODE_FIELDS: Array[String] = [
	"id", "name", "node_type", "primitive_shape", "position",
	"rotation_degrees", "scale", "material", "collision",
	"asset_tag", "children", "metadata"
]

const _ALLOWED_MATERIAL_FIELDS: Array[String] = [
	"albedo", "roughness", "metallic", "emission", "emission_energy",
	"normal_scale", "transparency", "preset",
	"albedo_texture", "normal_texture", "roughness_texture",
	"metallic_texture", "emission_texture"
]

const ALLOWED_MATERIAL_PRESETS: Array[String] = [
	"wood", "stone", "metal", "glass", "water", "plastic", "fabric",
	"concrete", "brick", "sand", "grass", "dirt", "ceramic", "rubber",
	"marble", "ice", "gold", "silver", "copper", "chrome", "lava", "neon",
]

const _POLY_ESTIMATES: Dictionary = {
	"box": 12,
	"sphere": 512,
	"cylinder": 128,
	"capsule": 576,
	"plane": 2
}

# endregion

# region --- Private vars ---

var _logger: RefCounted

# endregion

# region --- Constructor ---

func _init(logger: RefCounted = null) -> void:
	_logger = logger

# endregion

# region --- Public methods ---

## Parses raw JSON and validates the resulting spec.
## @param raw_json: Raw JSON string to parse and validate.
## @return ValidationResult with errors/warnings or the valid spec.
func validate_json_string(raw_json: String) -> ValidationResult:
	var parsed: Variant = JSON.parse_string(raw_json)
	if parsed == null:
		var errors: Array[Dictionary] = [_make_error(
			"SPEC_ERR_PARSE",
			"Failed to parse JSON string",
			"",
			"error",
			"Ensure the input is valid JSON"
		)]
		return ValidationResult.create_invalid(errors, [] as Array[Dictionary])

	if not parsed is Dictionary:
		var errors: Array[Dictionary] = [_make_error(
			"SPEC_ERR_PARSE",
			"JSON root must be an object, got %s" % type_string(typeof(parsed)),
			"",
			"error",
			"Wrap spec in a JSON object {}"
		)]
		return ValidationResult.create_invalid(errors, [] as Array[Dictionary])

	return validate_spec(parsed as Dictionary)


## Validates a parsed spec dictionary against the full schema.
## Collects all errors and warnings without short-circuiting.
## @param spec: Parsed scene spec dictionary.
## @return ValidationResult with collected errors and warnings.
func validate_spec(spec: Dictionary) -> ValidationResult:
	var errors: Array[Dictionary] = []
	var warnings: Array[Dictionary] = []

	_validate_top_level_fields(spec, errors)
	_validate_spec_version(spec, errors)

	if spec.has("meta") and spec["meta"] is Dictionary:
		_validate_meta(spec["meta"] as Dictionary, errors, warnings)

	if spec.has("determinism") and spec["determinism"] is Dictionary:
		_validate_determinism(spec["determinism"] as Dictionary, errors)

	if spec.has("limits") and spec["limits"] is Dictionary:
		_validate_limits(spec["limits"] as Dictionary, errors)

	if spec.has("environment") and spec["environment"] is Dictionary:
		_validate_environment(spec["environment"] as Dictionary, errors)

	if spec.has("camera") and spec["camera"] is Dictionary:
		_validate_camera(spec["camera"] as Dictionary, errors)

	var limits: Dictionary = spec.get("limits", {}) as Dictionary
	var bounds: Array = []
	if spec.has("meta") and spec["meta"] is Dictionary:
		var meta: Dictionary = spec["meta"] as Dictionary
		if meta.has("bounds_meters") and meta["bounds_meters"] is Array:
			bounds = meta["bounds_meters"] as Array

	if spec.has("lights") and spec["lights"] is Array:
		_validate_lights(spec["lights"] as Array, limits, errors, warnings)

	if spec.has("nodes") and spec["nodes"] is Array:
		_validate_nodes(spec["nodes"] as Array, limits, bounds, errors, warnings)

	if spec.has("rules") and spec["rules"] is Dictionary:
		_validate_rules(spec["rules"] as Dictionary, errors)

	_check_poly_budget(spec, warnings)

	if errors.is_empty():
		return ValidationResult.create_valid(spec, warnings)
	return ValidationResult.create_invalid(errors, warnings)


## Returns the schema version this validator targets.
func get_schema_version() -> String:
	return SCHEMA_VERSION


## Returns a copy of the allowed node types list.
func get_allowed_node_types() -> Array[String]:
	return ALLOWED_NODE_TYPES.duplicate()


## Returns a copy of the allowed primitive shapes list.
func get_allowed_primitive_shapes() -> Array[String]:
	return ALLOWED_PRIMITIVE_SHAPES.duplicate()

# endregion

# region --- Private validation methods ---

func _validate_top_level_fields(spec: Dictionary, errors: Array[Dictionary]) -> void:
	var expected_types: Dictionary = {
		"spec_version": TYPE_STRING,
		"meta": TYPE_DICTIONARY,
		"determinism": TYPE_DICTIONARY,
		"limits": TYPE_DICTIONARY,
		"environment": TYPE_DICTIONARY,
		"camera": TYPE_DICTIONARY,
		"lights": TYPE_ARRAY,
		"nodes": TYPE_ARRAY,
		"rules": TYPE_DICTIONARY
	}

	for field: String in _REQUIRED_TOP_LEVEL_FIELDS:
		if not spec.has(field):
			errors.append(_make_error(
				"SPEC_ERR_PARSE",
				"Missing required top-level field '%s'" % field,
				field,
				"error",
				"Add the '%s' field to the spec" % field
			))
		elif typeof(spec[field]) != expected_types[field]:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Field '%s' must be %s, got %s" % [
					field,
					_type_name(expected_types[field]),
					_type_name(typeof(spec[field]))
				],
				field,
				"error",
				"Change '%s' to the correct type" % field
			))

	for key: String in spec.keys():
		if key not in _REQUIRED_TOP_LEVEL_FIELDS:
			errors.append(_make_error(
				"SPEC_ERR_ADDITIONAL_FIELD",
				"Unknown top-level field '%s'" % key,
				key,
				"error",
				"Remove the unknown field '%s'" % key
			))


func _validate_spec_version(spec: Dictionary, errors: Array[Dictionary]) -> void:
	if not spec.has("spec_version") or not spec["spec_version"] is String:
		return
	if spec["spec_version"] as String != SCHEMA_VERSION:
		errors.append(_make_error(
			"SPEC_ERR_VERSION",
			"Unsupported spec_version '%s', expected '%s'" % [spec["spec_version"], SCHEMA_VERSION],
			"spec_version",
			"error",
			"Set spec_version to '%s'" % SCHEMA_VERSION
		))


func _validate_meta(
	meta: Dictionary,
	errors: Array[Dictionary],
	warnings: Array[Dictionary]
) -> void:
	for field: String in _REQUIRED_META_FIELDS:
		if not meta.has(field):
			errors.append(_make_error(
				"SPEC_ERR_PARSE",
				"Missing required meta field '%s'" % field,
				"meta.%s" % field,
				"error",
				"Add '%s' to meta" % field
			))

	if meta.has("generator") and meta["generator"] is String:
		if meta["generator"] as String != "ai_scene_gen":
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"meta.generator must be 'ai_scene_gen', got '%s'" % meta["generator"],
				"meta.generator",
				"error",
				"Set meta.generator to 'ai_scene_gen'"
			))

	if meta.has("style_preset"):
		if not meta["style_preset"] is String \
			or (meta["style_preset"] as String) not in ALLOWED_STYLE_PRESETS:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"meta.style_preset must be one of %s" % str(ALLOWED_STYLE_PRESETS),
				"meta.style_preset",
				"error",
				"Use an allowed style_preset"
			))

	if meta.has("bounds_meters"):
		if not _is_vec3_positive(meta["bounds_meters"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"meta.bounds_meters must be an array of 3 positive numbers",
				"meta.bounds_meters",
				"error",
				"Provide [width, height, depth] as positive numbers"
			))

	if meta.has("prompt_hash"):
		if not _is_valid_prompt_hash(meta["prompt_hash"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"meta.prompt_hash must match 'sha256:' followed by 64 hex characters",
				"meta.prompt_hash",
				"error",
				"Generate a valid SHA-256 hash with 'sha256:' prefix"
			))

	if meta.has("timestamp_utc") and not meta["timestamp_utc"] is String:
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"meta.timestamp_utc must be a String",
			"meta.timestamp_utc",
			"error",
			"Provide timestamp as ISO 8601 string"
		))

	for key: String in meta.keys():
		if key not in _REQUIRED_META_FIELDS:
			errors.append(_make_error(
				"SPEC_ERR_ADDITIONAL_FIELD",
				"Unknown meta field '%s'" % key,
				"meta.%s" % key,
				"error",
				"Remove the unknown field '%s'" % key
			))


func _validate_determinism(det: Dictionary, errors: Array[Dictionary]) -> void:
	for field: String in _REQUIRED_DETERMINISM_FIELDS:
		if not det.has(field):
			errors.append(_make_error(
				"SPEC_ERR_PARSE",
				"Missing required determinism field '%s'" % field,
				"determinism.%s" % field,
				"error",
				"Add '%s' to determinism" % field
			))

	if det.has("seed"):
		if not _is_int(det["seed"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"determinism.seed must be an integer",
				"determinism.seed",
				"error",
				"Provide seed as integer 0-2147483647"
			))
		elif int(det["seed"]) < 0 or int(det["seed"]) > 2147483647:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"determinism.seed must be 0-2147483647, got %d" % int(det["seed"]),
				"determinism.seed",
				"error",
				"Use a seed in range 0-2147483647"
			))

	if det.has("variation_mode") and not det["variation_mode"] is bool:
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"determinism.variation_mode must be a bool",
			"determinism.variation_mode",
			"error",
			"Set variation_mode to true or false"
		))

	if det.has("fingerprint"):
		if not det["fingerprint"] is String:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"determinism.fingerprint must be a String",
				"determinism.fingerprint",
				"error",
				"Provide fingerprint as a string"
			))
		else:
			var fp: String = det["fingerprint"] as String
			if fp.length() < 8 or fp.length() > 128:
				errors.append(_make_error(
					"SPEC_ERR_TYPE",
					"determinism.fingerprint length must be 8-128, got %d" % fp.length(),
					"determinism.fingerprint",
					"error",
					"Adjust fingerprint length to 8-128 characters"
				))


func _validate_limits(limits: Dictionary, errors: Array[Dictionary]) -> void:
	for field: String in _REQUIRED_LIMITS_FIELDS:
		if not limits.has(field):
			errors.append(_make_error(
				"SPEC_ERR_PARSE",
				"Missing required limits field '%s'" % field,
				"limits.%s" % field,
				"error",
				"Add '%s' to limits" % field
			))

	_check_int_range(limits, "max_nodes", 1, 1024, "limits", errors)
	_check_float_range(limits, "max_scale_component", 0.01, 100.0, "limits", errors)
	_check_float_range(limits, "max_light_energy", 0.0, 16.0, "limits", errors)
	_check_int_range(limits, "max_tree_depth", 1, 16, "limits", errors)
	_check_int_range(limits, "poly_budget_triangles", 100, 500000, "limits", errors)


func _validate_environment(env: Dictionary, errors: Array[Dictionary]) -> void:
	for field: String in _REQUIRED_ENVIRONMENT_FIELDS:
		if not env.has(field):
			errors.append(_make_error(
				"SPEC_ERR_PARSE",
				"Missing required environment field '%s'" % field,
				"environment.%s" % field,
				"error",
				"Add '%s' to environment" % field
			))

	if env.has("sky_type"):
		if not env["sky_type"] is String \
			or (env["sky_type"] as String) not in ALLOWED_SKY_TYPES:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"environment.sky_type must be one of %s" % str(ALLOWED_SKY_TYPES),
				"environment.sky_type",
				"error",
				"Use an allowed sky_type"
			))

	for color_field: String in ["sky_color_top", "sky_color_bottom", "ambient_light_color"]:
		if env.has(color_field) and not _is_color3(env[color_field]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"environment.%s must be a color3 (array of 3 floats 0.0-1.0)" % color_field,
				"environment.%s" % color_field,
				"error",
				"Provide [r, g, b] with each component 0.0-1.0"
			))

	_check_float_range(env, "ambient_light_energy", 0.0, 4.0, "environment", errors)

	if env.has("fog_enabled") and not env["fog_enabled"] is bool:
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"environment.fog_enabled must be a bool",
			"environment.fog_enabled",
			"error",
			"Set fog_enabled to true or false"
		))

	_check_float_range(env, "fog_density", 0.0, 1.0, "environment", errors)


func _validate_camera(cam: Dictionary, errors: Array[Dictionary]) -> void:
	for field: String in _REQUIRED_CAMERA_FIELDS:
		if not cam.has(field):
			errors.append(_make_error(
				"SPEC_ERR_PARSE",
				"Missing required camera field '%s'" % field,
				"camera.%s" % field,
				"error",
				"Add '%s' to camera" % field
			))

	for vec_field: String in ["position", "look_at"]:
		if cam.has(vec_field) and not _is_vec3_in_range(cam[vec_field], -1000.0, 1000.0):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"camera.%s must be a vec3 with components in [-1000, 1000]" % vec_field,
				"camera.%s" % vec_field,
				"error",
				"Provide [x, y, z] within range"
			))

	_check_float_range(cam, "fov_degrees", 10.0, 170.0, "camera", errors)

	if cam.has("near_clip"):
		_check_float_range(cam, "near_clip", 0.01, 10.0, "camera", errors)

	if cam.has("far_clip"):
		_check_float_range(cam, "far_clip", 100.0, 10000.0, "camera", errors)


func _validate_lights(
	lights: Array,
	limits: Dictionary,
	errors: Array[Dictionary],
	warnings: Array[Dictionary]
) -> void:
	if lights.is_empty():
		warnings.append(_make_error(
			"SPEC_WARN_NO_LIGHTS",
			"No lights defined; scene will rely on ambient light only",
			"lights",
			"warning",
			"Add at least one light for better visibility"
		))
		return

	if lights.size() > 16:
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"Too many lights: %d (max 16)" % lights.size(),
			"lights",
			"error",
			"Reduce to 16 or fewer lights"
		))

	var max_energy: float = limits.get("max_light_energy", 16.0) as float

	for i: int in range(lights.size()):
		var light: Variant = lights[i]
		var path: String = "lights[%d]" % i

		if not light is Dictionary:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Light at index %d must be a Dictionary" % i,
				path,
				"error",
				"Provide light as an object"
			))
			continue

		var ld: Dictionary = light as Dictionary

		for field: String in _REQUIRED_LIGHT_FIELDS:
			if not ld.has(field):
				errors.append(_make_error(
					"SPEC_ERR_PARSE",
					"Missing required light field '%s'" % field,
					"%s.%s" % [path, field],
					"error",
					"Add '%s' to the light" % field
				))

		if ld.has("id") and not _is_valid_id(ld["id"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Light id must be 1-64 alphanumeric/underscore characters",
				"%s.id" % path,
				"error",
				"Use only [a-zA-Z0-9_], 1-64 chars"
			))

		if ld.has("type"):
			if not ld["type"] is String \
				or (ld["type"] as String) not in ALLOWED_LIGHT_TYPES:
				errors.append(_make_error(
					"SPEC_ERR_TYPE",
					"Light type must be one of %s" % str(ALLOWED_LIGHT_TYPES),
					"%s.type" % path,
					"error",
					"Use an allowed light type"
				))

		if ld.has("rotation_degrees") and not _is_vec3(ld["rotation_degrees"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Light rotation_degrees must be a vec3",
				"%s.rotation_degrees" % path,
				"error",
				"Provide [x, y, z] rotation"
			))

		if ld.has("color") and not _is_color3(ld["color"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Light color must be a color3 (array of 3 floats 0.0-1.0)",
				"%s.color" % path,
				"error",
				"Provide [r, g, b] with each component 0.0-1.0"
			))

		if ld.has("energy"):
			if not _is_number(ld["energy"]):
				errors.append(_make_error(
					"SPEC_ERR_TYPE",
					"Light energy must be a number",
					"%s.energy" % path,
					"error",
					"Provide energy as a number >= 0"
				))
			elif float(ld["energy"]) < 0.0:
				errors.append(_make_error(
					"SPEC_ERR_TYPE",
					"Light energy must be >= 0.0",
					"%s.energy" % path,
					"error",
					"Set energy to a non-negative value"
				))
			elif float(ld["energy"]) > max_energy:
				errors.append(_make_error(
					"SPEC_ERR_LIMIT_ENERGY",
					"Light energy %.2f exceeds limit %.2f" % [float(ld["energy"]), max_energy],
					"%s.energy" % path,
					"error",
					"Reduce energy to %.2f or lower" % max_energy
				))

		if ld.has("shadow_enabled") and not ld["shadow_enabled"] is bool:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Light shadow_enabled must be a bool",
				"%s.shadow_enabled" % path,
				"error",
				"Set shadow_enabled to true or false"
			))

		if ld.has("position") and not _is_vec3(ld["position"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Light position must be a vec3",
				"%s.position" % path,
				"error",
				"Provide [x, y, z] position"
			))


func _validate_nodes(
	nodes: Array,
	limits: Dictionary,
	bounds: Array,
	errors: Array[Dictionary],
	warnings: Array[Dictionary]
) -> void:
	var max_nodes: int = limits.get("max_nodes", 1024) as int
	var max_depth: int = limits.get("max_tree_depth", 16) as int

	var total_count: int = _count_nodes_recursive(nodes)
	if total_count > max_nodes:
		errors.append(_make_error(
			"SPEC_ERR_LIMIT_NODES",
			"Total node count %d exceeds max_nodes %d" % [total_count, max_nodes],
			"nodes",
			"error",
			"Reduce to %d or fewer nodes" % max_nodes
		))

	var depth: int = _max_depth_recursive(nodes, 1)
	if depth > max_depth:
		errors.append(_make_error(
			"BUILD_ERR_TREE_DEPTH",
			"Max tree depth %d exceeds limit %d" % [depth, max_depth],
			"nodes",
			"error",
			"Flatten node hierarchy to max depth %d" % max_depth
		))

	var ids: Dictionary = {}
	for i: int in range(nodes.size()):
		var node: Variant = nodes[i]
		var path: String = "nodes[%d]" % i

		if not node is Dictionary:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Node at index %d must be a Dictionary" % i,
				path,
				"error",
				"Provide node as an object"
			))
			continue

		_validate_single_node(
			node as Dictionary, path, limits, bounds, ids, errors, warnings, 1
		)

	if not _has_ground_node(nodes):
		warnings.append(_make_error(
			"SPEC_WARN_NO_GROUND",
			"No ground plane detected; objects may appear floating",
			"nodes",
			"warning",
			"Add a node with metadata.role='ground' or position.y <= 0"
		))


func _validate_single_node(
	node: Dictionary,
	path: String,
	limits: Dictionary,
	bounds: Array,
	ids: Dictionary,
	errors: Array[Dictionary],
	warnings: Array[Dictionary],
	depth: int
) -> void:
	for field: String in _REQUIRED_NODE_FIELDS:
		if not node.has(field):
			errors.append(_make_error(
				"SPEC_ERR_PARSE",
				"Missing required node field '%s'" % field,
				"%s.%s" % [path, field],
				"error",
				"Add '%s' to the node" % field
			))

	# --- id ---
	if node.has("id"):
		if not _is_valid_id(node["id"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Node id must be 1-64 alphanumeric/underscore characters",
				"%s.id" % path,
				"error",
				"Use only [a-zA-Z0-9_], 1-64 chars"
			))
		elif node["id"] as String in ids:
			errors.append(_make_error(
				"SPEC_ERR_DUPLICATE_ID",
				"Duplicate node id '%s'" % node["id"],
				"%s.id" % path,
				"error",
				"Use unique IDs for each node"
			))
		else:
			ids[node["id"] as String] = true

	# --- name ---
	if node.has("name"):
		if not node["name"] is String:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Node name must be a String",
				"%s.name" % path,
				"error",
				"Provide name as a string"
			))
		else:
			var name_str: String = node["name"] as String
			if name_str.length() < 1 or name_str.length() > 128:
				errors.append(_make_error(
					"SPEC_ERR_TYPE",
					"Node name length must be 1-128, got %d" % name_str.length(),
					"%s.name" % path,
					"error",
					"Adjust name length to 1-128 characters"
				))
			var pattern: String = _contains_code_pattern(name_str)
			if not pattern.is_empty():
				errors.append(_make_error(
					"SPEC_ERR_CODE_PATTERN",
					"Forbidden code pattern '%s' found in node name" % pattern,
					"%s.name" % path,
					"error",
					"Remove code injection patterns from names"
				))

	# --- node_type ---
	if node.has("node_type"):
		if not node["node_type"] is String \
			or (node["node_type"] as String) not in ALLOWED_NODE_TYPES:
			errors.append(_make_error(
				"SPEC_ERR_NODE_TYPE",
				"Unknown node_type '%s', allowed: %s" % [
					str(node.get("node_type", "")),
					str(ALLOWED_NODE_TYPES)
				],
				"%s.node_type" % path,
				"error",
				"Use an allowed node_type"
			))

	# --- primitive_shape ---
	if node.has("primitive_shape") and node["primitive_shape"] != null:
		if not node["primitive_shape"] is String \
			or (node["primitive_shape"] as String) not in ALLOWED_PRIMITIVE_SHAPES:
			errors.append(_make_error(
				"SPEC_ERR_PRIMITIVE",
				"Unknown primitive_shape '%s', allowed: %s" % [
					str(node.get("primitive_shape", "")),
					str(ALLOWED_PRIMITIVE_SHAPES)
				],
				"%s.primitive_shape" % path,
				"error",
				"Use an allowed primitive_shape"
			))

	# --- position + bounds ---
	if node.has("position"):
		if not _is_vec3(node["position"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Node position must be a vec3",
				"%s.position" % path,
				"error",
				"Provide [x, y, z] position"
			))
		elif bounds.size() == 3 and not _check_bounds(node["position"] as Array, bounds):
			errors.append(_make_error(
				"SPEC_ERR_BOUNDS",
				"Node position %s is outside bounds %s" % [
					str(node["position"]),
					str(bounds)
				],
				"%s.position" % path,
				"error",
				"Move node within the defined bounds"
			))

	# --- rotation_degrees ---
	if node.has("rotation_degrees") and not _is_vec3(node["rotation_degrees"]):
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"Node rotation_degrees must be a vec3",
			"%s.rotation_degrees" % path,
			"error",
			"Provide [x, y, z] rotation"
		))

	# --- scale ---
	var max_scale: float = limits.get("max_scale_component", 100.0) as float
	if node.has("scale"):
		if not _is_vec3(node["scale"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Node scale must be a vec3",
				"%s.scale" % path,
				"error",
				"Provide [x, y, z] scale"
			))
		else:
			var s: Array = node["scale"] as Array
			for ci: int in range(3):
				var component: float = float(s[ci])
				if component < 0.01 or component > max_scale:
					errors.append(_make_error(
						"SPEC_ERR_LIMIT_SCALE",
						"Scale component [%d]=%.4f out of range [0.01, %.2f]" % [
							ci, component, max_scale
						],
						"%s.scale" % path,
						"error",
						"Keep scale components between 0.01 and %.2f" % max_scale
					))
					break

	# --- material (optional) ---
	if node.has("material") and node["material"] != null:
		if not node["material"] is Dictionary:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Node material must be a Dictionary",
				"%s.material" % path,
				"error",
				"Provide material as an object with albedo and roughness"
			))
		else:
			var mat: Dictionary = node["material"] as Dictionary
			_validate_material(mat, "%s.material" % path, errors)


	# --- collision (optional) ---
	if node.has("collision") and not node["collision"] is bool:
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"Node collision must be a bool",
			"%s.collision" % path,
			"error",
			"Set collision to true or false"
		))

	# --- asset_tag (optional) ---
	if node.has("asset_tag") and node["asset_tag"] != null \
		and not node["asset_tag"] is String:
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"Node asset_tag must be a String or null",
			"%s.asset_tag" % path,
			"error",
			"Provide asset_tag as a string or null"
		))

	# --- metadata code pattern check ---
	if node.has("metadata") and node["metadata"] is Dictionary:
		var meta: Dictionary = node["metadata"] as Dictionary
		for key: String in meta.keys():
			if meta[key] is String:
				var pattern: String = _contains_code_pattern(meta[key] as String)
				if not pattern.is_empty():
					errors.append(_make_error(
						"SPEC_ERR_CODE_PATTERN",
						"Forbidden code pattern '%s' in metadata.%s" % [pattern, key],
						"%s.metadata.%s" % [path, key],
						"error",
						"Remove code injection patterns from metadata values"
					))

	# --- additional field check ---
	for key: String in node.keys():
		if key not in _ALLOWED_NODE_FIELDS:
			errors.append(_make_error(
				"SPEC_ERR_ADDITIONAL_FIELD",
				"Unknown node field '%s'" % key,
				"%s.%s" % [path, key],
				"error",
				"Remove the unknown field '%s'" % key
			))

	# --- children (recursive) ---
	if node.has("children") and node["children"] is Array:
		var children: Array = node["children"] as Array
		for ci: int in range(children.size()):
			var child: Variant = children[ci]
			var child_path: String = "%s.children[%d]" % [path, ci]
			if not child is Dictionary:
				errors.append(_make_error(
					"SPEC_ERR_TYPE",
					"Child node at %s must be a Dictionary" % child_path,
					child_path,
					"error",
					"Provide child node as an object"
				))
				continue
			_validate_single_node(
				child as Dictionary, child_path, limits, bounds,
				ids, errors, warnings, depth + 1
			)


func _validate_material(mat: Dictionary, path: String, errors: Array[Dictionary]) -> void:
	if mat.has("albedo") and not _is_color3(mat["albedo"]):
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"material.albedo must be a color3",
			"%s.albedo" % path,
			"error",
			"Provide [r, g, b] with each component 0.0-1.0"
		))
	if mat.has("roughness"):
		if not _is_number(mat["roughness"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"material.roughness must be a number",
				"%s.roughness" % path,
				"error",
				"Provide roughness as 0.0-1.0"
			))
		elif float(mat["roughness"]) < 0.0 or float(mat["roughness"]) > 1.0:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"material.roughness must be 0.0-1.0, got %.4f" % float(mat["roughness"]),
				"%s.roughness" % path,
				"error",
				"Set roughness between 0.0 and 1.0"
			))
	if mat.has("metallic"):
		if not _is_number(mat["metallic"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"material.metallic must be a number",
				"%s.metallic" % path,
				"error",
				"Provide metallic as 0.0-1.0"
			))
		elif float(mat["metallic"]) < 0.0 or float(mat["metallic"]) > 1.0:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"material.metallic must be 0.0-1.0, got %.4f" % float(mat["metallic"]),
				"%s.metallic" % path,
				"error",
				"Set metallic between 0.0 and 1.0"
			))
	if mat.has("emission") and not _is_color3_or_emission(mat["emission"]):
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"material.emission must be a color3 (0.0-1.0 per component)",
			"%s.emission" % path,
			"error",
			"Provide [r, g, b] with each component 0.0-1.0"
		))
	if mat.has("emission_energy"):
		if not _is_number(mat["emission_energy"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"material.emission_energy must be a number",
				"%s.emission_energy" % path,
				"error",
				"Provide emission_energy as 0.0-16.0"
			))
		elif float(mat["emission_energy"]) < 0.0 or float(mat["emission_energy"]) > 16.0:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"material.emission_energy must be 0.0-16.0, got %.4f" % float(mat["emission_energy"]),
				"%s.emission_energy" % path,
				"error",
				"Set emission_energy between 0.0 and 16.0"
			))
	if mat.has("normal_scale"):
		if not _is_number(mat["normal_scale"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"material.normal_scale must be a number",
				"%s.normal_scale" % path,
				"error",
				"Provide normal_scale as 0.0-2.0"
			))
		elif float(mat["normal_scale"]) < 0.0 or float(mat["normal_scale"]) > 2.0:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"material.normal_scale must be 0.0-2.0, got %.4f" % float(mat["normal_scale"]),
				"%s.normal_scale" % path,
				"error",
				"Set normal_scale between 0.0 and 2.0"
			))
	if mat.has("transparency"):
		if not _is_number(mat["transparency"]):
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"material.transparency must be a number",
				"%s.transparency" % path,
				"error",
				"Provide transparency as 0.0-1.0"
			))
		elif float(mat["transparency"]) < 0.0 or float(mat["transparency"]) > 1.0:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"material.transparency must be 0.0-1.0, got %.4f" % float(mat["transparency"]),
				"%s.transparency" % path,
				"error",
				"Set transparency between 0.0 and 1.0"
			))
	if mat.has("preset"):
		if not mat["preset"] is String:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"material.preset must be a String",
				"%s.preset" % path,
				"error",
				"Provide preset as a string from: %s" % str(ALLOWED_MATERIAL_PRESETS)
			))
		elif (mat["preset"] as String) not in ALLOWED_MATERIAL_PRESETS:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"Unknown material preset '%s', allowed: %s" % [mat["preset"], str(ALLOWED_MATERIAL_PRESETS)],
				"%s.preset" % path,
				"error",
				"Use an allowed material preset"
			))
	var texture_fields: Array[String] = [
		"albedo_texture", "normal_texture", "roughness_texture",
		"metallic_texture", "emission_texture"
	]
	for tex_field: String in texture_fields:
		if mat.has(tex_field):
			if not mat[tex_field] is String:
				errors.append(_make_error(
					"SPEC_ERR_TYPE",
					"material.%s must be a String" % tex_field,
					"%s.%s" % [path, tex_field],
					"error",
					"Provide a res:// path to a texture file"
				))
			else:
				var tex_path: String = mat[tex_field] as String
				if not tex_path.begins_with("res://"):
					errors.append(_make_error(
						"SPEC_ERR_TYPE",
						"material.%s must start with res://, got '%s'" % [tex_field, tex_path],
						"%s.%s" % [path, tex_field],
						"error",
						"Texture paths must begin with res://"
					))
	for key: Variant in mat.keys():
		var key_str: String = str(key)
		if key_str not in _ALLOWED_MATERIAL_FIELDS:
			errors.append(_make_error(
				"SPEC_ERR_ADDITIONAL_FIELD",
				"Unknown material field '%s'" % key_str,
				"%s.%s" % [path, key_str],
				"error",
				"Remove the unknown field '%s'" % key_str
			))


func _validate_rules(rules: Dictionary, errors: Array[Dictionary]) -> void:
	var required: Array[String] = ["snap_to_ground", "clamp_to_bounds"]
	for field: String in required:
		if not rules.has(field):
			errors.append(_make_error(
				"SPEC_ERR_PARSE",
				"Missing required rules field '%s'" % field,
				"rules.%s" % field,
				"error",
				"Add '%s' to rules" % field
			))
		elif not rules[field] is bool:
			errors.append(_make_error(
				"SPEC_ERR_TYPE",
				"rules.%s must be a bool" % field,
				"rules.%s" % field,
				"error",
				"Set %s to true or false" % field
			))

	if rules.has("disallow_overlaps") and not rules["disallow_overlaps"] is bool:
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"rules.disallow_overlaps must be a bool",
			"rules.disallow_overlaps",
			"error",
			"Set disallow_overlaps to true or false"
		))


func _check_poly_budget(spec: Dictionary, warnings: Array[Dictionary]) -> void:
	if not spec.has("nodes") or not spec["nodes"] is Array:
		return
	if not spec.has("limits") or not spec["limits"] is Dictionary:
		return

	var limits: Dictionary = spec["limits"] as Dictionary
	var poly_budget: int = limits.get("poly_budget_triangles", 500000) as int
	if poly_budget <= 0:
		return

	var estimated: int = _estimate_poly_count(spec["nodes"] as Array)
	if estimated > int(float(poly_budget) * 0.8):
		warnings.append(_make_error(
			"SPEC_WARN_POLY_BUDGET",
			"Estimated triangle count %d exceeds 80%% of budget %d" % [estimated, poly_budget],
			"nodes",
			"warning",
			"Reduce primitive complexity or increase poly_budget_triangles"
		))

# endregion

# region --- Helpers ---

func _make_error(
	code: String,
	message: String,
	path: String,
	severity: String,
	fix_hint: String
) -> Dictionary:
	return {
		"code": code,
		"message": message,
		"path": path,
		"severity": severity,
		"stage": "validate",
		"fix_hint": fix_hint
	}


func _is_vec3(value: Variant) -> bool:
	if not value is Array:
		return false
	var arr: Array = value as Array
	if arr.size() != 3:
		return false
	for component: Variant in arr:
		if not _is_number(component):
			return false
	return true


func _is_vec3_in_range(value: Variant, min_val: float, max_val: float) -> bool:
	if not _is_vec3(value):
		return false
	var arr: Array = value as Array
	for component: Variant in arr:
		var f: float = float(component)
		if f < min_val or f > max_val:
			return false
	return true


func _is_vec3_positive(value: Variant) -> bool:
	if not _is_vec3(value):
		return false
	var arr: Array = value as Array
	for component: Variant in arr:
		if float(component) <= 0.0:
			return false
	return true


func _is_color3(value: Variant) -> bool:
	if not value is Array:
		return false
	var arr: Array = value as Array
	if arr.size() != 3:
		return false
	for component: Variant in arr:
		if not _is_number(component):
			return false
		var f: float = float(component)
		if f < 0.0 or f > 1.0:
			return false
	return true


func _is_color3_or_emission(value: Variant) -> bool:
	if not value is Array:
		return false
	var arr: Array = value as Array
	if arr.size() != 3:
		return false
	for component: Variant in arr:
		if not _is_number(component):
			return false
		var f: float = float(component)
		if f < 0.0 or f > 1.0:
			return false
	return true


func _is_valid_id(value: Variant) -> bool:
	if not value is String:
		return false
	var s: String = value as String
	if s.length() < 1 or s.length() > 64:
		return false
	var regex: RegEx = RegEx.new()
	regex.compile("^[a-zA-Z0-9_]+$")
	return regex.search(s) != null


func _is_number(value: Variant) -> bool:
	return value is int or value is float


func _is_int(value: Variant) -> bool:
	if value is int:
		return true
	if value is float:
		var f: float = value as float
		return f == floorf(f)
	return false


func _is_valid_prompt_hash(value: Variant) -> bool:
	if not value is String:
		return false
	var s: String = value as String
	if not s.begins_with("sha256:"):
		return false
	var hex_part: String = s.substr(7)
	if hex_part.length() != 64:
		return false
	var regex: RegEx = RegEx.new()
	regex.compile("^[0-9a-fA-F]{64}$")
	return regex.search(hex_part) != null


func _contains_code_pattern(text: String) -> String:
	for pattern: String in FORBIDDEN_CODE_PATTERNS:
		if text.find(pattern) != -1:
			return pattern
	return ""


func _count_nodes_recursive(nodes: Array) -> int:
	var count: int = 0
	for node: Variant in nodes:
		count += 1
		if node is Dictionary:
			var d: Dictionary = node as Dictionary
			if d.has("children") and d["children"] is Array:
				count += _count_nodes_recursive(d["children"] as Array)
	return count


func _max_depth_recursive(nodes: Array, current_depth: int) -> int:
	var max_d: int = current_depth
	for node: Variant in nodes:
		if node is Dictionary:
			var d: Dictionary = node as Dictionary
			if d.has("children") and d["children"] is Array:
				var child_depth: int = _max_depth_recursive(
					d["children"] as Array, current_depth + 1
				)
				max_d = maxi(max_d, child_depth)
	return max_d


## Checks if position falls within the defined bounds.
## x: [-bx/2, bx/2], y: [-1, by], z: [-bz/2, bz/2]
func _check_bounds(position: Array, bounds: Array) -> bool:
	if position.size() < 3 or bounds.size() < 3:
		return false
	var px: float = float(position[0])
	var py: float = float(position[1])
	var pz: float = float(position[2])
	var bx: float = float(bounds[0])
	var by: float = float(bounds[1])
	var bz: float = float(bounds[2])
	if px < -bx / 2.0 or px > bx / 2.0:
		return false
	if py < -1.0 or py > by:
		return false
	if pz < -bz / 2.0 or pz > bz / 2.0:
		return false
	return true


func _has_ground_node(nodes: Array) -> bool:
	for node: Variant in nodes:
		if not node is Dictionary:
			continue
		var d: Dictionary = node as Dictionary
		if d.has("metadata") and d["metadata"] is Dictionary:
			var meta: Dictionary = d["metadata"] as Dictionary
			if meta.get("role", "") == "ground":
				return true
		if d.has("position") and _is_vec3(d["position"]):
			var pos: Array = d["position"] as Array
			if float(pos[1]) <= 0.0:
				return true
		if d.has("children") and d["children"] is Array:
			if _has_ground_node(d["children"] as Array):
				return true
	return false


func _estimate_poly_count(nodes: Array) -> int:
	var total: int = 0
	for node: Variant in nodes:
		if not node is Dictionary:
			continue
		var d: Dictionary = node as Dictionary
		if d.has("primitive_shape") and d["primitive_shape"] is String:
			var shape: String = d["primitive_shape"] as String
			if shape in _POLY_ESTIMATES:
				total += _POLY_ESTIMATES[shape] as int
		if d.has("children") and d["children"] is Array:
			total += _estimate_poly_count(d["children"] as Array)
	return total


func _check_int_range(
	data: Dictionary,
	field: String,
	min_val: int,
	max_val: int,
	section: String,
	errors: Array[Dictionary]
) -> void:
	if not data.has(field):
		return
	if not _is_int(data[field]):
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"%s.%s must be an integer" % [section, field],
			"%s.%s" % [section, field],
			"error",
			"Provide %s as an integer" % field
		))
		return
	var val: int = int(data[field])
	if val < min_val or val > max_val:
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"%s.%s must be %d-%d, got %d" % [section, field, min_val, max_val, val],
			"%s.%s" % [section, field],
			"error",
			"Set %s between %d and %d" % [field, min_val, max_val]
		))


func _check_float_range(
	data: Dictionary,
	field: String,
	min_val: float,
	max_val: float,
	section: String,
	errors: Array[Dictionary]
) -> void:
	if not data.has(field):
		return
	if not _is_number(data[field]):
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"%s.%s must be a number" % [section, field],
			"%s.%s" % [section, field],
			"error",
			"Provide %s as a number" % field
		))
		return
	var val: float = float(data[field])
	if val < min_val or val > max_val:
		errors.append(_make_error(
			"SPEC_ERR_TYPE",
			"%s.%s must be %.2f-%.2f, got %.4f" % [section, field, min_val, max_val, val],
			"%s.%s" % [section, field],
			"error",
			"Set %s between %.2f and %.2f" % [field, min_val, max_val]
		))


func _type_name(type_id: int) -> String:
	match type_id:
		TYPE_STRING:
			return "String"
		TYPE_DICTIONARY:
			return "Dictionary"
		TYPE_ARRAY:
			return "Array"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_BOOL:
			return "bool"
		_:
			return "type(%d)" % type_id

# endregion
