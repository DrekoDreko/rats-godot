extends CanvasLayer
## The escape from the glue, and the remaining lifetime of the strip in front of
## the player.
##
## The escape is the timing bar the strangling used to ask for: a pointer sweeps
## the track and the click only counts inside the green. Three of those and the
## boot comes off. The rule of it — where the green is, how fast the pointer
## runs, what a hit is worth — belongs to `glue_trap.gd`; this draws what the
## trap is already thinking.

const TEXT_SCENE := preload("res://scenes/big_font_outlined_label.tscn")

var _counter: BigFontOutlinedLabel
var _prompt: BigFontOutlinedLabel
var _status: BigFontOutlinedLabel
var _bar: Control
var _panel: VBoxContainer

func _ready() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = VBoxContainer.new()
	root.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	# Sized and parked on the health bar: the escape is read in a glance, and a
	# strip that wide used to sit over the middle of the screen.
	_panel.offset_left = -72.0
	_panel.offset_right = 72.0
	_panel.offset_top = -142.0
	_panel.offset_bottom = -62.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_counter = TEXT_SCENE.instantiate()
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_counter.font_size = 16
	_panel.add_child(_counter)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(144.0, 11.0)
	# Shrunk and not filled: a label wider than the track would otherwise stretch
	# the panel, and the track with it.
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	_panel.add_child(_bar)
	_prompt = TEXT_SCENE.instantiate()
	_prompt.text = tr("HUD_GLUE_INSTRUCTION")
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_prompt)
	_status = TEXT_SCENE.instantiate()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_status)

func _process(_delta: float) -> void:
	var player := get_parent()
	if player == null:
		return
	var stuck: bool = player.is_glued()
	var glue: GlueTrap = player._glue if stuck else _aimed_glue(player.camera)
	var escaping := stuck and is_instance_valid(glue)
	_counter.visible = escaping
	_prompt.visible = escaping
	_bar.visible = escaping
	if escaping:
		# Asked of the strip rather than of the class, so that a bench which
		# loads this script by hand still finds the number (`godot --script`
		# compiles it before the global class list exists).
		var hits: float = glue.ESCAPE_HITS
		_counter.text = tr("HUD_GLUE_BUTTON") % [roundi(player.glue_progress * hits), int(hits)]
		# Redrawn from here rather than off a signal: the pointer moves every
		# frame, so a signal per frame buys nothing over asking for it.
		_bar.queue_redraw()
	_status.visible = is_instance_valid(glue)
	if _status.visible:
		_status.text = glue.status_text()
	_panel.visible = not player.is_ui_open() and not player.is_dead() and (stuck or _status.visible)

## The track, the green, and the pointer running down it. Drawn and not built
## out of nodes because it is three rectangles and a line that move every frame.
func _draw_bar() -> void:
	var glue: GlueTrap = get_parent()._glue
	if not is_instance_valid(glue):
		return
	var track := Rect2(2.0, (_bar.size.y - 5.0) * 0.5, _bar.size.x - 4.0, 5.0)
	_bar.draw_rect(track, Color(0.03, 0.03, 0.03, 0.9))
	_bar.draw_rect(Rect2(track.position.x + glue.sweep_zone_start * track.size.x,
		track.position.y, glue.sweep_zone_width * track.size.x, track.size.y),
		Color(0.3, 0.9, 0.35))
	_bar.draw_rect(track, Color.WHITE, false, 1.0)
	var x := track.position.x + glue.sweep_pointer * track.size.x
	_bar.draw_line(Vector2(x, 0.0), Vector2(x, _bar.size.y), Color.BLACK, 4.0)
	_bar.draw_line(Vector2(x, 0.0), Vector2(x, _bar.size.y), Color.WHITE, 2.0)

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
