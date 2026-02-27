@tool
class_name PromptCompiler
extends RefCounted

## Compiles user prompts and settings into LLM-ready system instruction strings.
## Supports single-stage, plan-stage, and spec-stage compilation.

const MAX_PROMPT_CHARS: int = 2000
const MAX_TOKEN_ESTIMATE: int = 12000
const VALID_STYLE_PRESETS: Array[String] = ["blockout", "stylized", "realistic-lite"]
const SCHEMA_VERSION: String = "1.0.0"
const DEFAULT_MAX_NODES: int = 256
const DEFAULT_MAX_SCALE: float = 50.0
const DEFAULT_MAX_LIGHT_ENERGY: float = 5.0

const PROMPT_ERR_EMPTY: String = "PROMPT_ERR_EMPTY"
const PROMPT_ERR_INVALID_PRESET: String = "PROMPT_ERR_INVALID_PRESET"
const PROMPT_ERR_TOO_LONG: String = "PROMPT_ERR_TOO_LONG"

const SYSTEM_TEMPLATE: String = """You are a 3D scene layout engine. You ONLY output valid JSON conforming to
SceneSpec v1.0.0. You NEVER output explanations, markdown, or code.

RULES:
1. Output ONLY a single JSON object. No text before or after.
2. All node_type values must be from this allowlist:
   MeshInstance3D, StaticBody3D, DirectionalLight3D, OmniLight3D,
   SpotLight3D, Camera3D, WorldEnvironment, Node3D
3. All primitive_shape values must be from this allowlist:
   box, sphere, cylinder, capsule, plane
4. All positions must be within bounds: x in [-{half_bound_x}, {half_bound_x}],
   y in [0, {bound_y}], z in [-{half_bound_z}, {half_bound_z}]
5. Maximum {max_nodes} nodes total (including children).
6. Scale components must be in [0.01, {max_scale}].
7. Light energy must be in [0.0, {max_light_energy}].
8. seed = {seed}. Use this to deterministically vary placement (e.g.,
   hash node index + seed for position offsets).
9. Style preset: {style_preset}
   - blockout: simple shapes, solid muted colors, no detail
   - stylized: rounded shapes, vibrant colors, slight variation
   - realistic-lite: realistic proportions, neutral palette, subtle detail
10. If available_asset_tags are provided, prefer using them in asset_tag
    fields. If a tag does not match, use null and set primitive_shape.
11. Always include: ground plane, at least 1 light, a camera.
12. Each node must have a material object. Required fields: albedo (RGB
    0-1 array), roughness (0-1 float). Optional PBR fields: metallic
    (0-1), emission (RGB 0-1 array), emission_energy (0-16), normal_scale
    (0-2), transparency (0-1), preset (string).
    Available material presets: wood, stone, metal, glass, water, plastic,
    fabric, concrete, brick, sand, grass, dirt, ceramic, rubber, marble,
    ice, gold, silver, copper, chrome, lava, neon.
    When preset is set, its defaults are used; explicit fields override.
    Optional texture fields (only include when the user explicitly
    requests textures): albedo_texture, normal_texture,
    roughness_texture, metallic_texture, emission_texture. Each must be
    a res:// path to an existing project texture file. Do NOT invent
    texture paths — only use them if the user provides specific paths
    or explicitly asks for textured materials.
13. Set spec_version to "1.0.0". Set generator to "ai_scene_gen".
14. Do not include code, scripts, file paths, or unsupported fields.
    If unsure, choose safe primitive fallbacks.

AVAILABLE ASSET TAGS: {asset_tags}
PROJECT CONSTRAINTS: {constraints}
SCENE BOUNDS (meters): {bounds}
{plan_section}USER REQUEST: {user_prompt}"""

const PLAN_OUTPUT_APPENDIX: String = """

OUTPUT FORMAT: Output a JSON object with a single key 'plan' containing an array of {name, approximate_position, role, notes} objects. This is a plan only, not a SceneSpec."""

const LOG_CATEGORY: String = "ai_scene_gen.prompt_compiler"

var _logger: RefCounted


func _init(logger: RefCounted = null) -> void:
	_logger = logger


## Compiles a single-stage prompt. Returns "" on validation failure.
## @param request: Dictionary with user_prompt, selected_model, selected_provider, style_preset, seed, bounds_meters, available_asset_tags, project_constraints
## @return: Compiled prompt string or empty on error
func compile_single_stage(request: Dictionary) -> String:
	return _compile_internal(request, "", false)


## Compiles a plan-stage prompt with appended plan output format.
## @param request: Same shape as compile_single_stage
## @return: Compiled prompt string or empty on error
func compile_plan_stage(request: Dictionary) -> String:
	return _compile_internal(request, "", true)


## Compiles a spec-stage prompt with layout plan injected before user request.
## @param request: Same shape as compile_single_stage
## @param plan_text: The plan JSON/output from the plan stage
## @return: Compiled prompt string or empty on error
func compile_spec_stage(request: Dictionary, plan_text: String) -> String:
	var plan_section: String = "\nLAYOUT PLAN (follow this): %s\n\n" % plan_text
	return _compile_internal(request, plan_section, false)


## Compiles a schema-retry prompt that includes the original instructions,
## the invalid JSON, and the validation errors for the LLM to fix.
## @param request: Same shape as compile_single_stage
## @param invalid_json: The raw JSON that failed schema validation (truncated to 2000 chars)
## @param errors: Array of error dictionaries from the validator
## @return: Compiled prompt string or empty on error
func compile_retry_stage(request: Dictionary, invalid_json: String, errors: Array[Dictionary]) -> String:
	var base_prompt: String = _compile_internal(request, "", false)
	if base_prompt.is_empty():
		return ""

	var error_lines: String = ""
	for err: Dictionary in errors:
		error_lines += "- [%s] %s\n" % [err.get("code", ""), err.get("message", "")]

	var truncated_json: String = invalid_json.left(2000)
	var retry_suffix: String = (
		"\n\nYour previous JSON output was invalid:\n%s\n\n"
		+ "Validation errors:\n%s\n"
		+ "Fix ALL the above issues and output ONLY a corrected JSON object."
	) % [truncated_json, error_lines]

	return base_prompt + retry_suffix


## Returns the raw system instruction template (un-interpolated).
func get_system_instruction() -> String:
	return SYSTEM_TEMPLATE


## Estimates token count via heuristic: prompt.length() / 4.
## @param prompt: Full prompt string
## @return: Approximate token count
func estimate_token_count(prompt: String) -> int:
	return ceili(prompt.length() / 4.0)


## Builds a deterministic fingerprint from request inputs.
## @param request: Full GenerationRequest dictionary
## @return: "sha256:" followed by hex-encoded SHA-256 hash
func build_determinism_fingerprint(request: Dictionary) -> String:
	var user_prompt: String = request.get("user_prompt", "").strip_edges()
	var seed_val: Variant = request.get("seed", 0)
	var style_preset: String = request.get("style_preset", "blockout")
	var bounds_meters: Variant = request.get("bounds_meters", [10.0, 5.0, 10.0])
	var available_asset_tags: Variant = request.get("available_asset_tags", [])
	var project_constraints: Variant = request.get("project_constraints", "")

	var combined: String = "%s%s%s%s%s%s%s" % [
		user_prompt,
		str(seed_val),
		style_preset,
		str(bounds_meters),
		str(available_asset_tags),
		str(project_constraints),
		SCHEMA_VERSION
	]

	var data: PackedByteArray = combined.to_utf8_buffer()
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	var hash_bytes: PackedByteArray = ctx.finish()
	return "sha256:" + hash_bytes.hex_encode()


func _compile_internal(request: Dictionary, plan_section: String, append_plan_format: bool) -> String:
	var user_prompt: String = request.get("user_prompt", "").strip_edges()
	if user_prompt.is_empty():
		_log_error(PROMPT_ERR_EMPTY, "Cannot compile an empty prompt.")
		return ""

	if request.get("variation", false):
		var variation_seed: int = randi()
		user_prompt += " [variation_seed=%d]" % variation_seed

	var style_preset: String = request.get("style_preset", "blockout")
	if style_preset not in VALID_STYLE_PRESETS:
		_log_error(PROMPT_ERR_INVALID_PRESET, "Unknown style preset: '%s'." % style_preset)
		return ""

	var bounds_meters: Array = _get_bounds_array(request)
	var half_bound_x: float = bounds_meters[0] / 2.0
	var bound_y: float = bounds_meters[1]
	var half_bound_z: float = bounds_meters[2] / 2.0

	var available_asset_tags: Array = request.get("available_asset_tags", [])
	var asset_tags_str: String = "None"
	if available_asset_tags.size() > 0:
		var tags: Array[String] = []
		for tag in available_asset_tags:
			tags.append(str(tag))
		asset_tags_str = ", ".join(tags)

	var project_constraints: Variant = request.get("project_constraints", "")
	var constraints_str: String = "None"
	if project_constraints != null and str(project_constraints).strip_edges().length() > 0:
		constraints_str = str(project_constraints)

	var seed_val: int = int(request.get("seed", 0))
	var max_nodes: int = int(request.get("max_nodes", DEFAULT_MAX_NODES))
	var max_scale: float = float(request.get("max_scale_component", DEFAULT_MAX_SCALE))
	var max_light_energy: float = float(request.get("max_light_energy", DEFAULT_MAX_LIGHT_ENERGY))

	var base_template: String = SYSTEM_TEMPLATE
	var interpolated: String = base_template.format({
		"half_bound_x": half_bound_x,
		"bound_y": bound_y,
		"half_bound_z": half_bound_z,
		"max_nodes": max_nodes,
		"max_scale": max_scale,
		"max_light_energy": max_light_energy,
		"seed": seed_val,
		"style_preset": style_preset,
		"asset_tags": asset_tags_str,
		"constraints": constraints_str,
		"bounds": str(bounds_meters),
		"plan_section": plan_section,
		"user_prompt": user_prompt
	})

	var result: String = interpolated
	if append_plan_format:
		result = interpolated + PLAN_OUTPUT_APPENDIX

	if estimate_token_count(result) > MAX_TOKEN_ESTIMATE:
		_log_error(PROMPT_ERR_TOO_LONG, "Prompt exceeds 12,000 token estimate. Simplify or reduce constraints.")
		return ""

	return result


func _get_bounds_array(request: Dictionary) -> Array:
	var bounds_meters: Variant = request.get("bounds_meters", [10.0, 5.0, 10.0])
	if bounds_meters is Array and bounds_meters.size() >= 3:
		return bounds_meters
	if bounds_meters is Vector3:
		var v: Vector3 = bounds_meters
		return [v.x, v.y, v.z]
	if bounds_meters is PackedVector3Array and bounds_meters.size() > 0:
		var v: Vector3 = bounds_meters[0]
		return [v.x, v.y, v.z]
	return [10.0, 5.0, 10.0]


func _log_error(code: String, message: String) -> void:
	if _logger != null and _logger.has_method("log_error"):
		_logger.log_error(LOG_CATEGORY, "[%s] %s" % [code, message])
	else:
		push_error("%s[%s] %s" % ["[AI_SCENE_GEN]", LOG_CATEGORY, message])
