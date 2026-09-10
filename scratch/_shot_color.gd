extends Node
## Screenshot rig: puts the terminal up on the palette page, in a viewport the
## size of the CRT in the van, seeds a crew of one in a colour, and photographs
## the suit before and after a drag across it. Not part of the game.

const TERMINAL := preload("res://scenes/terminal_screen.tscn")

## The glass itself (`world.tscn`, Van/StoreTerminal/Screen/Viewport). Shooting
## at any other size is shooting a layout the player never sees.
const GLASS := Vector2i(640, 507)

const SHOTS := "C:/Users/FERRAR~1/AppData/Local/Temp/claude/C--Users-Ferrareto-Documents-Lucas-GAMES-rats-godot/c146f076-9c9d-4754-b407-527e8ac26f24/scratchpad/"

## Somewhere in the middle of the preview frame, in glass pixels, and how far
## the pointer is dragged from there.
const GRAB := Vector2(105, 250)
const DRAG := Vector2(120, 0)

var _view: SubViewport


class PreviewUser extends Node3D:
	func set_ui_open(_is_open: bool) -> void:
		pass


func _ready() -> void:
	SessionManager.register_player(111, "Lucas", true)
	SessionManager.set_color(111, SessionManager.COLORS[5])

	_view = SubViewport.new()
	_view.size = GLASS
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)

	var terminal := TERMINAL.instantiate()
	_view.add_child(terminal)
	var user := PreviewUser.new()
	add_child(user)
	await get_tree().process_frame
	terminal.open(user)
	# One arrow to the left of the shop is the last page in the order.
	terminal.get_node("Nav/Left").emit_signal("pressed")

	await _settle()
	await _shot("color_shot.png")

	# The mouse the way the monitor delivers it: a point on the glass, and no
	# `relative` on the motion (`scripts/session/store_terminal.gd`).
	_click(GRAB, true)
	await _settle()
	_move(GRAB + DRAG * 0.5)
	_move(GRAB + DRAG)
	_click(GRAB + DRAG, false)
	await _settle()
	await _shot("color_shot_turned.png")

	get_tree().quit()


func _click(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	_view.push_input(event, true)


func _move(at: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.relative = Vector2.ZERO
	_view.push_input(event, true)


func _settle() -> void:
	for i in 20:
		await get_tree().process_frame


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	_view.get_texture().get_image().save_png(SHOTS + file)
	print("shot written: ", SHOTS + file)
