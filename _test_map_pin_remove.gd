extends SceneTree
## Right-click takes a pin off the plan, and does not shut the viewer doing it.
##
## Regression bench: `cancel` is bound to the right mouse button as well as Esc,
## so the guard at the top of `MapViewer._unhandled_input` used to swallow every
## right click and close the plan. The removal branch below it was unreachable.
##
## Run with: godot --headless --script _test_map_pin_remove.gd

const ANA := 111
const WAIT := 8

var _frames := 0
var _clock := 0
var _step := 0
var _failures := 0

var _session: Node
var _contract: Node
var _map: Node
var _viewer: Control


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _boot()
		1: return _place_pins()
		2: return _check_rmb_removes()
		3: return _check_esc_still_closes()
	return _finish()


func _ok(passed: bool, label: String) -> void:
	if passed:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_failures += 1


func _next() -> bool:
	_step += 1
	_clock = 0
	return false


func _boot() -> bool:
	if _clock < WAIT:
		return false

	_session = root.get_node_or_null("SessionManager")
	_contract = root.get_node_or_null("ContractManager")
	_map = root.get_node_or_null("MapManager")
	if _session == null or _contract == null or _map == null:
		print("FAIL: autoloads missing")
		_failures += 1
		return _finish()

	_session.reset()
	_session.register_player(ANA, "Ana")
	var first_job: Contract = _contract.at(0)
	if first_job == null:
		print("FAIL: no contract to sign")
		_failures += 1
		return _finish()
	_contract.request_sign(first_job.id)

	var scene: PackedScene = load("res://scenes/map/map_viewer.tscn")
	_viewer = scene.instantiate() as Control
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.add_child(_viewer)
	_viewer.size = Vector2(960, 540)
	_viewer.open()
	return _next()


func _place_pins() -> bool:
	if _clock < 4:
		return false

	_map.clear_all_pins()
	_map.request_place_pin(ANA, Vector2(0.25, 0.25))
	_map.request_place_pin(ANA, Vector2(0.75, 0.75))
	return _next()


## The real thing: a right button press, fed the way the window feeds it.
func _check_rmb_removes() -> bool:
	if _clock == 1:
		_ok(_map.count_for(ANA) == 2, "two pins on the plan to start")
		_ok(_viewer.is_open(), "viewer is open before the right click")
		return false

	if _clock == 2:
		# Aim at the first pin, in screen space, so the pick radius finds it.
		var screen_pos: Vector2 = _viewer._plan_uv_to_screen(Vector2(0.25, 0.25))
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = true
		ev.position = screen_pos
		ev.global_position = screen_pos
		_viewer._unhandled_input(ev)
		return false

	if _clock < 6:
		return false

	_ok(_map.count_for(ANA) == 1, "right click took a pin off")
	_ok(_viewer.is_open(), "right click did NOT close the viewer")
	return _next()


## And the way out is still there.
func _check_esc_still_closes() -> bool:
	if _clock == 1:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = true
		_viewer._unhandled_input(ev)
		return false

	if _clock < 4:
		return false

	_ok(not _viewer.is_open(), "Esc still closes the plan")
	return _next()


func _finish() -> bool:
	if _failures == 0:
		print("\npin remove bench: all good.")
	else:
		print("\npin remove bench: %d failure(s)." % _failures)
	quit(1 if _failures > 0 else 0)
	return true
