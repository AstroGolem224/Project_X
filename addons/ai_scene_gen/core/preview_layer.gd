@tool
class_name PreviewLayer
extends RefCounted

## Manages the _AIPreviewRoot node in the editor scene tree.
## Handles show, apply, and discard of AI-generated preview content.

const LOG_CATEGORY: String = "ai_scene_gen.preview"
const PREVIEW_ROOT_NAME: String = "_AIPreviewRoot"

const PREVIEW_ERR_NO_SCENE: String = "PREVIEW_ERR_NO_SCENE"
const PREVIEW_ERR_ALREADY_ACTIVE: String = "PREVIEW_ERR_ALREADY_ACTIVE"
const PREVIEW_ERR_NOT_ACTIVE: String = "PREVIEW_ERR_NOT_ACTIVE"

var _logger: RefCounted = null
var _preview_root: Node3D = null
var _is_active: bool = false
var _applied_children: Array[Node] = []


func _init(logger: RefCounted = null) -> void:
	_logger = logger


## Adds built_root to scene_root as _AIPreviewRoot and sets owners for editor visibility.
## @param built_root: The generated node tree to preview.
## @param scene_root: The active editor scene root to parent under.
## @return Empty {} on success, error dict on failure.
func show_preview(built_root: Node3D, scene_root: Node3D) -> Dictionary:
	if scene_root == null:
		return _make_error(PREVIEW_ERR_NO_SCENE, "No scene is open. Open or create a scene first.", "Open or create a scene in the editor.")

	if _is_active:
		return _make_error(PREVIEW_ERR_ALREADY_ACTIVE, "A preview is already active. Apply or discard it first.", "Apply or discard the current preview before generating again.")

	built_root.name = PREVIEW_ROOT_NAME
	scene_root.add_child(built_root)
	_set_owner_recursive(built_root, scene_root)

	_preview_root = built_root
	_is_active = true

	var node_count: int = _count_descendants(built_root)
	_log("info", "preview_shown: %d nodes" % node_count)
	return {}


## Reparents preview children to scene_root and removes _AIPreviewRoot.
## Uses EditorUndoRedoManager for full undo/redo support when available.
## @param undo_redo: EditorUndoRedoManager from plugin (null = direct apply without undo).
## @param scene_root: The active editor scene root.
## @return Empty {} on success, error dict on failure.
func apply_to_scene(undo_redo: EditorUndoRedoManager, scene_root: Node3D) -> Dictionary:
	if not _is_active or _preview_root == null:
		return _make_error(PREVIEW_ERR_NOT_ACTIVE, "No preview is active.", "Generate a scene first.")

	if scene_root == null:
		return _make_error(PREVIEW_ERR_NO_SCENE, "No scene is open. Open or create a scene first.", "Open or create a scene in the editor.")

	if undo_redo == null:
		_do_apply(scene_root)
		return {}

	undo_redo.create_action("AI Scene Gen: Apply Preview")
	undo_redo.add_do_method(self, "_do_apply", scene_root)
	undo_redo.add_undo_method(self, "_undo_apply", scene_root)
	undo_redo.add_do_reference(_preview_root)
	undo_redo.add_undo_reference(_preview_root)
	for i: int in range(_preview_root.get_child_count()):
		var child: Node = _preview_root.get_child(i)
		undo_redo.add_do_reference(child)
		undo_redo.add_undo_reference(child)
	undo_redo.commit_action()

	return {}


func _do_apply(scene_root: Node3D) -> void:
	if _preview_root == null:
		return
	_applied_children.clear()
	var children: Array[Node] = []
	for i: int in range(_preview_root.get_child_count()):
		children.append(_preview_root.get_child(i))
	for child: Node in children:
		_preview_root.remove_child(child)
		scene_root.add_child(child)
		_set_owner_recursive(child, scene_root)
		_applied_children.append(child)
	if _preview_root.get_parent() != null:
		_preview_root.get_parent().remove_child(_preview_root)
	_is_active = false
	_log("info", "preview_applied")


func _undo_apply(scene_root: Node3D) -> void:
	if _preview_root == null or scene_root == null:
		return
	scene_root.add_child(_preview_root)
	_set_owner_recursive(_preview_root, scene_root)
	for child: Node in _applied_children:
		if not is_instance_valid(child):
			continue
		if child.get_parent() != null:
			child.get_parent().remove_child(child)
		_preview_root.add_child(child)
		_set_owner_recursive(child, scene_root)
	_applied_children.clear()
	_is_active = true
	_log("info", "preview_apply_undone")


## Removes the preview root and all its children without applying.
func discard() -> void:
	if _preview_root != null and is_instance_valid(_preview_root):
		_preview_root.queue_free()
	_preview_root = null
	_is_active = false
	_log("info", "preview_discarded")


## Returns true if a preview is currently shown.
func is_preview_active() -> bool:
	return _is_active


## Returns total node count (root + descendants) when active, else 0.
func get_preview_node_count() -> int:
	if not _is_active or _preview_root == null:
		return 0
	return _count_descendants(_preview_root)


## Returns a summary of preview state for UI display.
func get_diff_summary() -> Dictionary:
	return {
		"is_active": _is_active,
		"added_count": get_preview_node_count(),
		"preview_root_name": PREVIEW_ROOT_NAME
	}


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	if node != owner_node:
		node.set_owner(owner_node)
	for i: int in range(node.get_child_count()):
		_set_owner_recursive(node.get_child(i), owner_node)


func _count_descendants(node: Node) -> int:
	var count: int = 1
	for i: int in range(node.get_child_count()):
		count += _count_descendants(node.get_child(i))
	return count


func _make_error(code: String, message: String, fix_hint: String) -> Dictionary:
	return {
		"stage": "preview",
		"severity": "error",
		"code": code,
		"message": message,
		"path": "",
		"fix_hint": fix_hint
	}


func _log(level: String, message: String) -> void:
	if _logger == null:
		return
	match level:
		"debug":
			_logger.log_debug(LOG_CATEGORY, message)
		"info":
			_logger.log_info(LOG_CATEGORY, message)
		"warning":
			_logger.log_warning(LOG_CATEGORY, message)
		"error":
			_logger.log_error(LOG_CATEGORY, message)
