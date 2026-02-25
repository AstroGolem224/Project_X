@tool
class_name AssetResolver
extends RefCounted

## Resolves asset_tag references in a SceneSpec against the AssetTagRegistry.

const LOG_CATEGORY: String = "ai_scene_gen.asset_resolver"
const ASSET_ERR_NOT_FOUND: String = "ASSET_ERR_NOT_FOUND"
const ASSET_WARN_TAG_MISS: String = "ASSET_WARN_TAG_MISS"

var _logger: RefCounted = null


func _init(logger: RefCounted = null) -> void:
	_logger = logger


## Resolves asset_tag references in spec against the registry.
## @param spec: SceneSpec dictionary with nodes array.
## @param registry: AssetTagRegistry to resolve tags against.
## @return ResolvedSpec with modified spec and resolution stats.
func resolve_nodes(spec: Dictionary, registry: Resource) -> ResolvedSpec:
	var modified_spec: Dictionary = _deep_copy_spec(spec)
	var resolved_count: int = 0
	var fallback_count: int = 0
	var missing_tags: Array[String] = []

	var resolved_count_ref: Array = [resolved_count]
	var fallback_count_ref: Array = [fallback_count]

	var nodes: Variant = modified_spec.get("nodes", null)
	if nodes is Array:
		for node in nodes:
			if node is Dictionary:
				_resolve_node_recursive(
					node as Dictionary,
					registry,
					resolved_count_ref,
					fallback_count_ref,
					missing_tags
				)

	return ResolvedSpec.create(
		modified_spec,
		resolved_count_ref[0],
		fallback_count_ref[0],
		missing_tags
	)


func _resolve_node_recursive(
	node: Dictionary,
	registry: Resource,
	resolved_count_ref: Array,
	fallback_count_ref: Array,
	missing_tags: Array[String]
) -> void:
	var asset_tag_var: Variant = node.get("asset_tag", null)
	var asset_tag: String = "" if asset_tag_var == null else str(asset_tag_var)

	if asset_tag.is_empty():
		node["_fallback"] = true
		fallback_count_ref[0] += 1
	else:
		if registry.has_method("has_tag") and registry.has_tag(asset_tag):
			var entry: Dictionary = registry.get_entry(asset_tag) if registry.has_method("get_entry") else {}
			var resource_path: String = entry.get("resource_path", "")

			if resource_path.is_empty() or not FileAccess.file_exists(resource_path):
				node["_fallback"] = true
				node["_fallback_from_registry"] = true
				var fallback: Variant = entry.get("fallback", null)
				if fallback != null and fallback is Dictionary:
					var fb: Dictionary = fallback as Dictionary
					node["_fallback_shape"] = fb.get("primitive_shape", "box")
					node["_fallback_scale"] = fb.get("scale_hint", [1.0, 1.0, 1.0])
					node["_fallback_color"] = fb.get("color_hint", [0.5, 0.5, 0.5])
				fallback_count_ref[0] += 1
				_log("warning", "[%s] Asset file not found: '%s'. Tag '%s' will use fallback." % [ASSET_ERR_NOT_FOUND, resource_path, asset_tag])
			else:
				node["_resolved_path"] = resource_path
				node["_resource_type"] = entry.get("resource_type", "PackedScene")
				resolved_count_ref[0] += 1
				_log("debug", "tag_resolved: %s -> %s" % [asset_tag, resource_path])
		else:
			node["_fallback"] = true
			if asset_tag not in missing_tags:
				missing_tags.append(asset_tag)
			fallback_count_ref[0] += 1
			_log("warning", "[%s] Tag '%s' not found in registry. Using primitive fallback." % [ASSET_WARN_TAG_MISS, asset_tag])

	var children: Variant = node.get("children", null)
	if children is Array:
		for child in children:
			if child is Dictionary:
				_resolve_node_recursive(
					child as Dictionary,
					registry,
					resolved_count_ref,
					fallback_count_ref,
					missing_tags
				)


func _deep_copy_spec(spec: Dictionary) -> Dictionary:
	var parsed: Variant = JSON.parse_string(JSON.stringify(spec))
	if parsed is Dictionary:
		return parsed
	return spec.duplicate(true)


func _log(level: String, message: String) -> void:
	if _logger == null:
		return
	match level:
		"debug":
			if _logger.has_method("log_debug"):
				_logger.log_debug(LOG_CATEGORY, message)
		"info":
			if _logger.has_method("log_info"):
				_logger.log_info(LOG_CATEGORY, message)
		"warning":
			if _logger.has_method("log_warning"):
				_logger.log_warning(LOG_CATEGORY, message)
		"error":
			if _logger.has_method("log_error"):
				_logger.log_error(LOG_CATEGORY, message)
