@tool
class_name SceneTemplate
extends Resource

## Data-driven template for reusable scene generation presets.
## Stores prompt text and all generation settings.
## Can be saved/loaded as .tres files via ResourceSaver/ResourceLoader.

@export var template_name: String = ""
@export var description: String = ""
@export var prompt: String = ""
@export var style_preset: String = "blockout"
@export var two_stage: bool = false
@export var seed_value: int = 42
@export var bounds_x: float = 50.0
@export var bounds_y: float = 30.0
@export var bounds_z: float = 50.0
@export var is_builtin: bool = false


## Creates a duplicate with all fields copied.
func duplicate_template() -> SceneTemplate:
	var copy: SceneTemplate = SceneTemplate.new()
	copy.template_name = template_name
	copy.description = description
	copy.prompt = prompt
	copy.style_preset = style_preset
	copy.two_stage = two_stage
	copy.seed_value = seed_value
	copy.bounds_x = bounds_x
	copy.bounds_y = bounds_y
	copy.bounds_z = bounds_z
	copy.is_builtin = false
	return copy


## Populates this template from a generation request dictionary.
func from_request(request: Dictionary) -> void:
	prompt = request.get("user_prompt", "") as String
	style_preset = request.get("style_preset", "blockout") as String
	two_stage = request.get("two_stage", false) as bool
	seed_value = request.get("seed", 42) as int
	var bounds: Variant = request.get("bounds_meters", [50.0, 30.0, 50.0])
	if bounds is Array and (bounds as Array).size() >= 3:
		bounds_x = float((bounds as Array)[0])
		bounds_y = float((bounds as Array)[1])
		bounds_z = float((bounds as Array)[2])


## Returns a dictionary matching the generation request shape (prompt + settings).
func to_request_overrides() -> Dictionary:
	return {
		"user_prompt": prompt,
		"style_preset": style_preset,
		"two_stage": two_stage,
		"seed": seed_value,
		"bounds_meters": [bounds_x, bounds_y, bounds_z],
	}
