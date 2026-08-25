class_name MapViewer
extends Control
## Tactical blueprint viewer and collaborative pin planner.
##
## Opened by the van's map table (`MapTable`), and only there: the plan is
## studied in the van before the shift, never carried into the house.
##
## **Navigation & Interaction:**
## - Left Click on the blueprint: places a strategy pin at that location.
## - Right Click on a placed pin: removes that pin.
## - Left Mouse Drag / WASD / Arrow Keys: pans the map around.
## - Mouse Wheel / +/-: zooms smoothly between MIN_ZOOM (1.0x) and MAX_ZOOM (3.5x).
## - Esc / E: closes the viewer.

signal closed()

const MIN_ZOOM := 1.0
const MAX_ZOOM := 3.5
const ZOOM_STEP := 0.25
const PAN_SPEED := 400.0
const PIN_PICK_RADIUS := 16.0

## Default placeholder texture if no contract is signed.
const NO_CONTRACT_TITLE := "NO CONTRACT SIGNED"
const NO_CONTRACT_SUB := "STUDY THE CLIPBOARD FIRST"

## Audio cues (optional)
@export var pin_sound: AudioStream
@export var close_sound: AudioStream

@onready var _plan_container: Control = $PlanContainer
@onready var _plan_rect: TextureRect = $PlanContainer/PlanRect
@onready var _pins_overlay: Control = $PlanContainer/PinsOverlay
@onready var _title_label: Label = $Header/Margin/HBox/Title
@onready var _info_label: Label = $Header/Margin/HBox/Info
@onready var _pins_count_label: Label = $Header/Margin/HBox/PinsCount
@onready var _audio_player: AudioStreamPlayer = $Audio

var _zoom := 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _drag_start_mouse := Vector2.ZERO
var _drag_start_pan := Vector2.ZERO

var _active_contract: Contract


func _ready() -> void:
	# Keep input working even if tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	MapManager.pins_updated.connect(_on_pins_updated)
	ContractManager.contract_signed.connect(_on_contract_signed)
	SessionManager.player_changed.connect(_on_player_changed)

	_pins_overlay.draw.connect(_on_pins_draw)
	_refresh_contract()
	_update_transform()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# The way out is `E`, and Esc by its key and not by its action: `cancel` is
	# bound to the right mouse button too, and over the plan that button means
	# "take that pin off" (`_handle_right_click_remove`). Asking for the action
	# here would shut the viewer on every attempt to remove a pin, and the
	# removal below would never be reached at all.
	var closing := event.is_action_pressed("interact")
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		closing = true
	if closing:
		close()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_zoom(_zoom + ZOOM_STEP, mb.position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_zoom(_zoom - ZOOM_STEP, mb.position)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_start_mouse = mb.position
				_drag_start_pan = _pan
			else:
				if _dragging and mb.position.distance_to(_drag_start_mouse) < 6.0:
					# It was a click, not a pan drag -> Place Pin
					_handle_click_place(mb.position)
				_dragging = false
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_handle_right_click_remove(mb.position)
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		_pan = _drag_start_pan + (mm.position - _drag_start_mouse)
		_clamp_pan()
		_update_transform()
		get_viewport().set_input_as_handled()

	elif event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		if k.keycode == KEY_C:
			# Shortcut: clear our pins
			MapManager.request_clear_pins(_our_steam_id())
			_play_sound(close_sound)
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return

	# Keyboard panning (WASD / Arrows)
	var move_vec := Vector2.ZERO
	if Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_LEFT):
		move_vec.x += 1.0
	if Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_RIGHT):
		move_vec.x -= 1.0
	if Input.is_action_pressed("move_forward") or Input.is_key_pressed(KEY_UP):
		move_vec.y += 1.0
	if Input.is_action_pressed("move_back") or Input.is_key_pressed(KEY_DOWN):
		move_vec.y -= 1.0

	if move_vec != Vector2.ZERO:
		_pan += move_vec * PAN_SPEED * delta
		_clamp_pan()
		_update_transform()


## Opens the map viewer.
func open() -> void:
	visible = true
	_refresh_contract()
	_reset_view()
	_update_header()
	_pins_overlay.queue_redraw()


## Closes the map viewer.
func close() -> void:
	if not visible:
		return
	visible = false
	_dragging = false
	_play_sound(close_sound)
	closed.emit()


func is_open() -> bool:
	return visible


func _reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	_update_transform()


func _set_zoom(new_zoom: float, mouse_pivot: Vector2) -> void:
	var clamped := clampf(new_zoom, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(_zoom, clamped):
		return

	var center := size * 0.5
	var pivot := mouse_pivot - center
	var factor := clamped / _zoom
	_pan = (_pan - pivot) * factor + pivot
	_zoom = clamped
	_clamp_pan()
	_update_transform()


func _clamp_pan() -> void:
	var max_pan := (size * 0.5) * (_zoom - 1.0) + Vector2(60, 60) * _zoom
	_pan.x = clampf(_pan.x, -max_pan.x, max_pan.x)
	_pan.y = clampf(_pan.y, -max_pan.y, max_pan.y)


func _update_transform() -> void:
	if _plan_container == null:
		return
	_plan_container.scale = Vector2(_zoom, _zoom)
	_plan_container.position = (size * 0.5) + _pan - ((_plan_container.size * 0.5) * _zoom)
	_pins_overlay.queue_redraw()


func _handle_click_place(screen_pos: Vector2) -> void:
	var uv := _screen_to_plan_uv(screen_pos)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return

	var us := _our_steam_id()
	MapManager.request_place_pin(us, uv)
	_play_sound(pin_sound)


func _handle_right_click_remove(screen_pos: Vector2) -> void:
	var uv := _screen_to_plan_uv(screen_pos)
	if uv.x < 0.0 or uv.x > 1.0 or uv.y < 0.0 or uv.y > 1.0:
		return

	var us := _our_steam_id()
	var our_pins := MapManager.pins_for(us)
	if our_pins.is_empty():
		return

	# Find if clicking near one of our pins
	var plan_size := _plan_rect.size
	var best_idx := -1
	var best_dist := PIN_PICK_RADIUS / _zoom

	for i in our_pins.size():
		var pin_pos: Vector2 = our_pins[i].get("pos", Vector2.ZERO)
		var pin_pixels := pin_pos * plan_size
		var click_pixels := uv * plan_size
		var dist := pin_pixels.distance_to(click_pixels)
		if dist < best_dist:
			best_dist = dist
			best_idx = i

	if best_idx != -1:
		MapManager.request_remove_pin(us, best_idx)
		_play_sound(close_sound)
	else:
		# If right-clicking anywhere on map and not on a specific pin, remove oldest
		MapManager.request_remove_pin(us, 0)
		_play_sound(close_sound)


func _screen_to_plan_uv(screen_pos: Vector2) -> Vector2:
	if _plan_rect == null or _plan_rect.size.x <= 0 or _plan_rect.size.y <= 0:
		return Vector2(-1, -1)
	var local_pos := (screen_pos - _plan_container.position) / _zoom
	var u := local_pos.x / _plan_rect.size.x
	var v := local_pos.y / _plan_rect.size.y
	return Vector2(u, v)


func _plan_uv_to_screen(uv: Vector2) -> Vector2:
	var local_pos := uv * _plan_rect.size
	return _plan_container.position + (local_pos * _zoom)


func _refresh_contract() -> void:
	_active_contract = ContractManager.current()
	if _plan_rect != null:
		if _active_contract != null and _active_contract.floor_plan != null:
			_plan_rect.texture = _active_contract.floor_plan
		else:
			_plan_rect.texture = null
	_update_header()


func _update_header() -> void:
	if _title_label == null:
		return
	if _active_contract == null:
		_title_label.text = NO_CONTRACT_TITLE
		_info_label.text = NO_CONTRACT_SUB
		_pins_count_label.text = ""
		return

	_title_label.text = "%s  —  %s" % [_active_contract.client_name.to_upper(), _active_contract.address]
	_info_label.text = "INFESTATION: %d RATS   |   REWARD: $%d" % [_active_contract.infestation, _active_contract.reward]
	
	var us := _our_steam_id()
	var my_pins := MapManager.count_for(us)
	_pins_count_label.text = "PINS: %d/3" % my_pins
	_pins_count_label.modulate = SessionManager.color(us)


func _on_pins_draw() -> void:
	var all_pins := MapManager.all_pins()
	var us := _our_steam_id()
	var plan_size := _plan_rect.size

	for pin in all_pins:
		var pos_norm: Vector2 = pin.get("pos", Vector2.ZERO)
		var center := pos_norm * plan_size
		var color: Color = pin.get("color", Color.WHITE)
		var is_ours: bool = pin.get("steam_id", 0) == us

		# Draw Pin Needle Shadow & Tip
		var shadow_offset := Vector2(2, 3)
		_pins_overlay.draw_line(center + shadow_offset, center + Vector2(0, 10) + shadow_offset, Color(0, 0, 0, 0.4), 2.0)
		_pins_overlay.draw_line(center, center + Vector2(0, 10), Color(0.85, 0.85, 0.9), 2.0)

		# Draw Pin Head (Outlined Circle + Color Core)
		_pins_overlay.draw_circle(center, 9.0, Color.BLACK)
		_pins_overlay.draw_circle(center, 7.5, color)
		_pins_overlay.draw_circle(center, 4.0, Color.WHITE.lerp(color, 0.3))

		# If it's our pin, draw a pulsing outer marker ring
		if is_ours:
			_pins_overlay.draw_arc(center, 12.0, 0, TAU, 16, Color.WHITE, 1.5)


func _on_pins_updated() -> void:
	_update_header()
	if _pins_overlay != null:
		_pins_overlay.queue_redraw()


func _on_contract_signed(_id: String) -> void:
	_refresh_contract()
	_pins_overlay.queue_redraw()


func _on_player_changed(_steam_id: int) -> void:
	_update_header()
	if _pins_overlay != null:
		_pins_overlay.queue_redraw()


func _play_sound(stream: AudioStream) -> void:
	if _audio_player != null and stream != null:
		_audio_player.stream = stream
		_audio_player.play()


func _our_steam_id() -> int:
	var steam_id := LobbyManager.our_steam_id()
	if steam_id != 0 and SessionManager.has_player(steam_id):
		return steam_id
	var crew := SessionManager.players.keys()
	return crew[0] if crew.size() == 1 else steam_id
