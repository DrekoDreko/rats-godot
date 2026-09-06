extends SceneTree
## The totem is the way into the store, and the camera walks there and back.
##
## Run with: godot --headless --script _test_store_terminal.gd
##
## What is checked, and why each one would be invisible in play until it bit:
##
## - **`E` at the terminal puts the racks up.** The store used to open from
##   anywhere in the van; it is a machine again, and pressing the key at it has
##   to reach the same screen.
## - **The camera goes to the glass.** A camera of its own is made current, lands
##   square in front of the screen and close enough that the picture fills most
##   of the view — the player's own cannot be used, since the cabin shake writes
##   it every frame.
## - **The store is drawn on the monitor.** The racks live in the viewport
##   painted onto the glass, and the glass is dark until they are up.
## - **The mouse is carried onto the glass.** The pointer is turned into a point
##   in the viewport's own pixels, and anything that misses the screen is
##   dropped rather than clamped onto the nearest tile.
## - **The man is held for the whole trip.** He is taken over before the camera
##   leaves and handed back only after it has come home — a man who gets his
##   legs mid-flight walks the van blind.
## - **The store shut means the key does nothing.** Parked or in the lobby the
##   machine refuses, and refuses without taking anybody over.

## Frames of slack between steps. The trip is 0.45 s, so a step that waits on it
## waits longer than the rest.
const WAIT := 6
## Frames to let a camera trip finish: 0.45 s at 60 fps, and some slack.
const TRIP_FRAMES := 40
## The phase the van is on the road in — copied rather than read off `Phase`,
## for the reason `_test_van_shop.gd` gives.
const PHASE_TRAVEL := 1
const PHASE_LOBBY := 0
## The scene the totem lives in.
const TRAVEL := "res://scenes/van_travel.tscn"
## Whose money this is, when Steam is not running.
const FALLBACK_ID := 111
const OUR_NAME := "Us"

var _van: Node3D
var _terminal: Node
var _store: Node
var _player: Node3D
var _shop: Node
var _session: Node
var _phase: Node
var _clock := 0
var _step := 0
var _failures := 0


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_clock += 1
	match _step:
		0: return _stand_the_van_up()
		1: return _check_key_opens_the_store()
		2: return _check_camera_reached_the_monitor()
		3: return _check_closing_brings_him_home()
		4: return _check_shut_store_refuses()
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

# --- Steps ------------------------------------------------------------------

## The van on the road, with a man in it and the store open.
func _stand_the_van_up() -> bool:
	if _clock < 2:
		return false
	_shop = root.get_node_or_null("ShopManager")
	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	if _shop == null or _session == null or _phase == null:
		print("FAIL: the autoloads are not in the tree")
		return _finish()

	_session.reset()
	var steam: Node = root.get_node_or_null("SteamManager")
	var us: int = steam.get_steam_id() if steam != null else 0
	if us == 0:
		us = FALLBACK_ID
	_session.register_player(us, OUR_NAME, true)

	# The phase is set with the scene path blanked so that `PhaseManager` does
	# not change scenes under us: the van is put up by hand instead.
	var travel_scene: String = _phase.scenes[PHASE_TRAVEL]
	_phase.scenes[PHASE_TRAVEL] = ""
	_phase.go_to(PHASE_TRAVEL)
	_phase.scenes[PHASE_TRAVEL] = travel_scene
	_van = (load(TRAVEL) as PackedScene).instantiate() as Node3D
	root.add_child(_van)

	_terminal = _van.get_node_or_null("Stations/StoreTerminal")
	_store = get_first_node_in_group("store_screen")
	_player = _van.get_node_or_null("Player") as Node3D
	_ok(_terminal != null, "the van has a terminal on the totem")
	_ok(_store != null, "and the store screen is in it")
	_ok(_store != null and _store.get_parent() is SubViewport,
		"drawn inside a viewport and not over the game")
	_ok(_player != null, "and a man to shop with")
	if _terminal == null or _store == null or _player == null:
		return _finish()
	_ok(_shop.is_open(), "the store is open on the road")
	return _next()


## The press itself: the racks come up, and the man is taken over from the
## moment the camera leaves rather than when it lands.
func _check_key_opens_the_store() -> bool:
	if _clock == 1:
		_terminal.use(_player)
		return false
	if _clock < WAIT:
		return false

	_ok(_terminal.is_open(), "E at the terminal put somebody at the machine")
	_ok(_player.is_ui_open(), "and took his legs before the camera left")
	_ok(_terminal.prompt == "step back from the terminal",
		"prompt turned into the leave line")
	_ok(not _store._open, "and the racks wait for the camera to land")
	return _next()


## The camera lands square in front of the glass, close enough that the screen
## is what is being looked at, and the monitor is lit once it has.
func _check_camera_reached_the_monitor() -> bool:
	if _clock < TRIP_FRAMES:
		return false

	var screen := _van.get_node_or_null("Stations/StoreTerminal/Screen") as MeshInstance3D
	var glass := _van.get_node_or_null("Stations/StoreTerminal/Screen/Viewport") as SubViewport
	var travel := _van.get_node_or_null("Stations/StoreTerminal/TravelCamera") as Camera3D
	_ok(travel != null, "a camera of its own did the travelling")
	if travel == null or screen == null:
		return _next()

	_ok(travel.current, "and it is the one being looked through")
	# Square to the glass: on its axis, in front of it, and looking back at it.
	var offset := travel.global_position - screen.global_position
	var facing := screen.global_transform.basis.z.normalized()
	_ok(offset.cross(facing).length() < 0.01, "square on the screen's own axis")
	_ok(offset.dot(facing) > 0.0, "in front of the glass and not behind it")

	# And near enough that the picture is most of what is on screen: the whole
	# point of the complaint that started this — a camera that framed the totem
	# rather than the monitor.
	var height: float = (screen.mesh as QuadMesh).size.y
	var covered := 2.0 * offset.length() * tan(deg_to_rad(travel.fov) * 0.5)
	_ok(height / covered > 0.8,
		"the screen fills the view (%d%% of it)" % roundi(height / covered * 100.0))

	# The mouse has to arrive on the glass in the glass's own pixels: the middle
	# of the window is the middle of the screen, since the camera is square on it.
	var middle: Vector2 = Vector2(root.get_visible_rect().size) * 0.5
	var landed: Vector2 = _terminal._glass_pixel(middle)
	var want := Vector2(glass.size) * 0.5
	_ok(landed.distance_to(want) < 2.0,
		"the pointer lands where it is pointing (%s of %s)" % [landed, glass.size])
	_ok(_terminal._glass_pixel(Vector2(2, 2)).x < 0.0,
		"and a click on the van beside the monitor is dropped")

	_ok(_store._open, "the racks are up once it has")
	_ok(glass != null and glass.render_target_update_mode == SubViewport.UPDATE_ALWAYS,
		"and the monitor is drawing")
	var lit := screen.get_surface_override_material(0) as StandardMaterial3D
	_ok(lit != null and lit.albedo_texture is ViewportTexture,
		"with the viewport painted onto the glass")
	return _next()


## Closing plays the trip backwards, and he gets himself back at the end of it
## and not before.
func _check_closing_brings_him_home() -> bool:
	if _clock == 1:
		_store.close()
		return false
	if _clock == 3:
		_ok(not _terminal.is_open(), "the machine is free again on the way home")
		_ok(_player.is_ui_open(), "but the man is still held while it flies")
		return false
	if _clock < TRIP_FRAMES:
		return false

	var screen := _van.get_node_or_null("Stations/StoreTerminal/Screen") as MeshInstance3D
	var dark := screen.get_surface_override_material(0) as StandardMaterial3D
	_ok(dark != null and dark.albedo_texture == null, "the monitor went dark")
	_ok(not _player.is_ui_open(), "and he has his legs back once it has landed")
	_ok(_player.camera.current, "looking through his own eyes again")
	_ok(_terminal.prompt == "use the terminal", "prompt went back to the use line")
	return _next()


## Off the road the machine turns him away, and turns him away without taking
## anything of his.
func _check_shut_store_refuses() -> bool:
	if _clock == 1:
		var lobby_scene: String = _phase.scenes[PHASE_LOBBY]
		_phase.scenes[PHASE_LOBBY] = ""
		_phase.go_to(PHASE_LOBBY)
		_phase.scenes[PHASE_LOBBY] = lobby_scene
		return false
	if _clock == 3:
		_ok(not _shop.is_open(), "the store is shut off the road")
		_terminal.use(_player)
		return false
	if _clock < WAIT:
		return false

	_ok(not _terminal.is_open(), "the key does nothing at a shut store")
	_ok(not _player.is_ui_open(), "and it took nothing off the man")
	_ok(_player.camera.current, "and left him his own camera")
	return _next()


func _finish() -> bool:
	if _failures == 0:
		print("\nstore terminal bench: all good.")
	else:
		print("\nstore terminal bench: %d failure(s)." % _failures)
	quit(1 if _failures > 0 else 0)
	return true
