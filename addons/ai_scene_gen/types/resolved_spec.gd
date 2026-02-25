class_name ResolvedSpec
extends RefCounted

## Spec after resource resolution (references resolved, fallbacks applied).

var _spec: Dictionary = {}
var _resolved_count: int = 0
var _fallback_count: int = 0
var _missing_tags: Array[String] = []


## Creates a resolved spec with resolution stats.
## @param spec: Spec Dictionary with resolved references.
## @param resolved_count: Number of references successfully resolved.
## @param fallback_count: Number of references resolved via fallback.
## @param missing_tags: Tags that could not be resolved.
## @return A configured ResolvedSpec instance.
static func create(spec: Dictionary, resolved_count: int, fallback_count: int, missing_tags: Array[String]) -> ResolvedSpec:
	var r: ResolvedSpec = ResolvedSpec.new()
	r._spec = spec
	r._resolved_count = resolved_count
	r._fallback_count = fallback_count
	r._missing_tags.assign(missing_tags)
	return r


func get_spec() -> Dictionary:
	return _spec


func get_resolved_count() -> int:
	return _resolved_count


func get_fallback_count() -> int:
	return _fallback_count


func get_missing_tags() -> Array[String]:
	return _missing_tags.duplicate()
