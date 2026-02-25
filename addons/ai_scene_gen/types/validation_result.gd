@tool
class_name ValidationResult
extends RefCounted

## Result of spec validation: either valid with spec, or invalid with errors.

var _errors: Array[Dictionary] = []
var _warnings: Array[Dictionary] = []
var _spec: Dictionary = {}
var _has_spec: bool = false


## Creates a valid result with parsed spec and optional warnings.
## @param spec: Parsed and validated spec Dictionary.
## @param warnings: Optional warnings (error contract format).
## @return A configured ValidationResult instance.
static func create_valid(spec: Dictionary, warnings: Array[Dictionary]) -> ValidationResult:
	var r: ValidationResult = ValidationResult.new()
	r._spec = spec
	r._has_spec = true
	r._warnings.assign(warnings)
	return r


## Creates an invalid result with errors and optional warnings.
## @param errors: Errors in error contract format.
## @param warnings: Optional warnings (error contract format).
## @return A configured ValidationResult instance.
static func create_invalid(errors: Array[Dictionary], warnings: Array[Dictionary]) -> ValidationResult:
	var r: ValidationResult = ValidationResult.new()
	r._errors.assign(errors)
	r._warnings.assign(warnings)
	return r


func is_valid() -> bool:
	return _errors.is_empty()


func get_errors() -> Array[Dictionary]:
	return _errors.duplicate()


func get_warnings() -> Array[Dictionary]:
	return _warnings.duplicate()


## Returns the validated spec if valid, otherwise null.
func get_spec_or_null() -> Variant:
	return _spec if _has_spec else null


## Returns errors and warnings combined.
func get_all_issues() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(_errors)
	out.append_array(_warnings)
	return out
