extends CanvasLayer
## Local escape feedback and the remaining lifetime of the aimed-at strip.

const TEXT_SCENE := preload("res://scenes/big_font_outlined_label.tscn")

var _prompt: BigFontOutlinedLabel
var _status: BigFontOutlinedLabel
var _bar: ProgressBar
var _panel: VBoxContainer

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = VBoxContainer.new()
	root.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -180.0
	_panel.offset_right = 180.0
	_panel.offset_top = -180.0
	_panel.offset_bottom = -80.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt = TEXT_SCENE.instantiate()
	_prompt.text = "Press Space repeatedly to escape"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_prompt)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(360.0, 16.0)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_bar)
	_status = TEXT_SCENE.instantiate()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_status)

func _process(_delta: float) -> void:
	var player := get_parent()
	if player == null:
		return
	var stuck: bool = player.is_glued()
	_prompt.visible = stuck
	_bar.visible = stuck
	_bar.value = player.glue_progress
	var glue: GlueTrap = player._glue if stuck else _aimed_glue(player.camera)
	_status.visible = is_instance_valid(glue)
	if _status.visible:
		_status.text = glue.status_text()
	_panel.visible = not player.is_ui_open() and not player.is_dead() and (stuck or _status.visible)

func _aimed_glue(camera: Camera3D) -> GlueTrap:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * 3.0, 1)
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	for glue: GlueTrap in get_tree().get_nodes_in_group("glue_traps"):
		var shape_node := glue.get_node("Collision") as CollisionShape3D
		var box := shape_node.shape as BoxShape3D
		var point := shape_node.to_local(hit.position)
		if absf(point.x) <= box.size.x * 0.5 and absf(point.z) <= box.size.z * 0.5 \
				and absf(point.y) <= 0.15:
			return glue
	return null
