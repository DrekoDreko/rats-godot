class_name StoreTerminal
extends Interactable
## The terminal in the front of the van: the totem the crew buys its kit at.
##
## **The store is a screen in the room.** The racks are not drawn over the game;
## they are drawn *on the monitor*, in a `SubViewport` painted onto the glass of
## the CRT (`Screen/Viewport`, holding `scenes/store_screen.tscn`). Nothing about
## the shop is a window in front of the van — it is pixels on a machine standing
## in it, and the van is still there around the plastic while a man shops.
##
## **The camera goes and the man stays.** `use()` takes his legs and his mouse,
## flies a camera of its own from where his eyes are to a seat right in front of
## the glass — close enough that the screen is what fills the view, not the
## totem — and only then lights the monitor. Closing plays the trip backwards
## and hands him back at the end of it, so he never gets his legs while the view
## is still somewhere else.
##
## It is a camera of its own rather than the player's because the van shakes the
## player's every frame while the wheels turn (`scripts/travel/cabin_shake.gd`).
## Two things writing one transform is a fight, and the one that would lose is
## the trip.
##
## **The mouse is carried onto the glass.** A layer inside a `SubViewport` hears
## nothing the window hears, so the pointer is turned into a point on the screen
## here — the ray out of the camera, where it lands on the quad, in that
## viewport's own pixels — and pushed in. The same goes for the keys: `E` and
## Esc are read here, because there is nobody inside the monitor to read them.
##
## **The screen decides nothing about money.** This is furniture: it lights a
## monitor and puts a screen on it, and the screen asks `ShopManager` like it
## always did.

## What the prompt reads at the machine, and what it reads with the racks up.
const PROMPT_USE := "use the terminal"
const PROMPT_LEAVE := "step back from the terminal"

## How long the camera takes to cross the van, each way. Long enough to read as
## walking up to the thing, short enough that a man buying three traps is not
## watching an animation between each one.
const TRAVEL_TIME := 0.45

## What the glass is framed with when the camera gets there: a tighter lens than
## the player's own, so that leaning in reads as leaning in rather than as the
## world going wide.
const READING_FOV := 42.0
## How much of the view the screen fills, top to bottom, once the camera has
## landed. Short of the whole thing on purpose — a little of the monitor's own
## case around the picture is what says the picture is on a monitor.
const SCREEN_FILL := 0.86

## What the glass looks like with nothing on it: a dead CRT, not a black hole.
const SCREEN_OFF := Color(0.03, 0.03, 0.04)


## The glass itself: the quad the store is painted onto, with the viewport it is
## painted from hanging under it.
@export var screen_path: NodePath = ^"Screen"
@export var viewport_path: NodePath = ^"Screen/Viewport"
## The buzz for a man who presses the key while the store is shut — parked, or
## still in the lobby.
@export var refused_path: NodePath = ^"Refused"

@onready var _screen: MeshInstance3D = get_node_or_null(screen_path) as MeshInstance3D
@onready var _viewport: SubViewport = get_node_or_null(viewport_path) as SubViewport
@onready var _refused: AudioStreamPlayer3D = get_node_or_null(refused_path) as AudioStreamPlayer3D

## The man at the machine, or null with nobody at it. He is what the legs and
## the mouse are handed back to, and what stops a second press opening a store
## that is already up.
var _user: Node3D
## The camera doing the travelling, built the first time anybody uses the
## machine and kept for the rest of the scene.
var _camera: Camera3D
## The trip itself, so that a second one can cut the first short rather than
## fight it — a man who shuts the store while it is still opening.
var _trip: Tween
## The store, found by group the first time it is asked for.
var _store_screen: StoreScreen
## The glass's own material, so that the monitor can be turned off without
## touching the one every other surface shares.
var _glass: StandardMaterial3D


func _ready() -> void:
	add_to_group("store_station")
	prompt = PROMPT_USE
	_paint_glass()
	_light_screen(false)
	PhaseManager.phase_changed.connect(_on_phase_changed)


## Hands on the machine. The store being shut is a refusal and not a silence:
## the man pressed a key at a thing that plainly has a screen on it, and being
## told "not now" is the answer.
func use(by: Node3D) -> void:
	super.use(by)
	if _user != null:
		return
	if not ShopManager.is_open():
		_play(_refused)
		return
	_open(by)


func is_open() -> bool:
	return _user != null


## The keys, on behalf of the screen that cannot hear them. Only while somebody
## is at the machine — the press that *opens* it is the player's, spent on the
## station he is looking at.
func _unhandled_input(event: InputEvent) -> void:
	if _user == null:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("toggle_mouse"):
		var screen := _store()
		if screen != null:
			screen.close()
		get_viewport().set_input_as_handled()


## And the mouse, turned into a point on the glass. Anything that misses the
## screen is dropped rather than clamped to its edge: a click on the van beside
## the monitor is not a click on the tile nearest the van.
func _input(event: InputEvent) -> void:
	if _user == null or _viewport == null or _camera == null:
		return
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	var at := _glass_pixel(event.position)
	if at.x < 0.0:
		return
	var inner := event.duplicate() as InputEvent
	inner.set("position", at)
	if inner is InputEventMouseMotion:
		(inner as InputEventMouseMotion).relative = Vector2.ZERO
	_viewport.push_input(inner, true)

# --- Walking up to it and away from it --------------------------------------

func _open(by: Node3D) -> void:
	if by == null or not by.has_method("set_ui_open"):
		return
	var screen := _store()
	if screen == null or _screen == null:
		return

	_user = by
	_user.set_ui_open(true)
	prompt = PROMPT_LEAVE

	if not screen.closed.is_connected(_on_screen_closed):
		screen.closed.connect(_on_screen_closed)

	_travel(_eyes_of(by), _reading_seat(), READING_FOV,
		func() -> void:
			_light_screen(true)
			screen.open())


## The way out: the monitor goes dark first, and the camera walks home with the
## van already back on screen behind it.
func _on_screen_closed() -> void:
	if _user == null:
		return
	var man := _user
	# Let go of him here rather than at the end of the trip: `_user` is what
	# says the machine is busy, and a man who cannot press the key again until
	# the camera has landed is a man whose second press vanishes.
	_user = null
	prompt = PROMPT_USE
	_light_screen(false)

	var eyes := _eyes_of(man)
	var eyes_camera := _eyes_camera(man)
	var fov := eyes_camera.fov if eyes_camera != null else READING_FOV
	_travel(_camera.global_transform if _camera != null else eyes, eyes, fov,
		func() -> void: _release(man))


## One leg of the trip. The camera is put where it is coming from, made the one
## being looked through, and slid to where it is going; `done` is called once it
## lands.
func _travel(from: Transform3D, to: Transform3D, to_fov: float, done: Callable) -> void:
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "TravelCamera"
		add_child(_camera)
		# Its transform is written in world coordinates: the seat it flies to is
		# a place in the van and not an offset from this node, and a camera that
		# had to be converted into this node's frame every step would be
		# arithmetic for nothing.
		_camera.top_level = true

	var eyes := _eyes_camera()
	var from_fov := _camera.fov
	if eyes != null and _user != null:
		from_fov = eyes.fov

	_camera.global_transform = from
	_camera.fov = from_fov
	_camera.current = true

	if _trip != null and _trip.is_valid():
		_trip.kill()
	_trip = create_tween()
	_trip.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_trip.set_parallel(true)
	# `interpolate_with` and not a tweened property: a `Transform3D` interpolated
	# a component at a time skews the basis on the way across, and the store
	# arrives leaning.
	_trip.tween_method(
		func(t: float) -> void: _camera.global_transform = from.interpolate_with(to, t),
		0.0, 1.0, TRAVEL_TIME)
	_trip.tween_property(_camera, "fov", to_fov, TRAVEL_TIME)
	_trip.chain().tween_callback(done)


## Hands the man back his own eyes, his legs and his mouse, in that order: the
## camera has to be his again before he can move, or he steers a view standing
## at the monitor.
func _release(man: Node3D) -> void:
	var eyes := _eyes_camera(man)
	if eyes != null:
		eyes.current = true
	if _camera != null:
		_camera.current = false
	if is_instance_valid(man) and man.has_method("set_ui_open"):
		man.set_ui_open(false)

# --- The glass --------------------------------------------------------------

## Where the camera reads the screen from: square to the glass, on its own
## centre, and far enough back that the picture fills `SCREEN_FILL` of the view
## at `READING_FOV`.
##
## It is worked out from the mesh rather than set by hand in the scene, so that a
## monitor that is remodelled, or a quad that is resized to match one, is framed
## by the same rule instead of by a marker somebody forgot to move.
func _reading_seat() -> Transform3D:
	var seat := _screen.global_transform
	var height := _screen_size().y * seat.basis.get_scale().y
	var back := (height * 0.5) / tan(deg_to_rad(READING_FOV) * 0.5) / SCREEN_FILL
	# The quad faces along its own +Z, and a camera looks down its own -Z, so
	# the seat is the glass's own frame pushed out in front of it.
	seat.origin += seat.basis.z.normalized() * back
	return seat


## Puts the viewport onto the glass, in code rather than in the scene file: a
## `ViewportTexture` saved into a `.tscn` has to resolve a path against the scene
## it is local to, and a material reached through a shared `QuadMesh` never gets
## that resolution run. The contract board on the wall pays the same toll.
func _paint_glass() -> void:
	if _screen == null or _viewport == null:
		return
	_glass = StandardMaterial3D.new()
	# Unshaded and nearest-filtered: a lit, smoothed screen is the one thing in
	# a van built to look like 1998 that would read as modern.
	_glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glass.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_screen.set_surface_override_material(0, _glass)


## The monitor on or off. Off is a dark screen and a viewport that has stopped
## drawing — the racks are three columns of labels and a live 3D preview of a
## man, and none of that is worth a frame while nobody is looking at it.
func _light_screen(on: bool) -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on \
			else SubViewport.UPDATE_DISABLED
	if _glass == null:
		return
	if on:
		_glass.albedo_texture = _viewport.get_texture()
		_glass.albedo_color = Color.WHITE
	else:
		_glass.albedo_texture = null
		_glass.albedo_color = SCREEN_OFF


## Where a point on the window lands on the glass, in that viewport's own pixels
## — or `(-1, -1)` for a point that misses the screen altogether.
func _glass_pixel(at: Vector2) -> Vector2:
	var miss := Vector2(-1.0, -1.0)
	if _screen == null or _viewport == null or _camera == null:
		return miss
	var from := _camera.project_ray_origin(at)
	var dir := _camera.project_ray_normal(at)
	var face := _screen.global_transform
	var plane := Plane(face.basis.z.normalized(), face.origin)
	var hit: Variant = plane.intersects_ray(from, dir)
	if hit == null:
		return miss

	var local := face.affine_inverse() * (hit as Vector3)
	var size := _screen_size()
	# Out of the glass by any margin is a miss: the van around the monitor is
	# not the edge of the rack.
	if absf(local.x) > size.x * 0.5 or absf(local.y) > size.y * 0.5:
		return miss
	var uv := Vector2(local.x / size.x + 0.5, 0.5 - local.y / size.y)
	return uv * Vector2(_viewport.size)


## How big the glass is in its own coordinates.
func _screen_size() -> Vector2:
	var quad := _screen.mesh as QuadMesh
	return quad.size if quad != null else Vector2.ONE

# --- Odds and ends ----------------------------------------------------------

## The store screen, wherever the scene hung it. Found by group rather than by
## path: it is a `CanvasLayer` living inside the monitor's viewport, and the
## group is what lets a bench stand one up somewhere else entirely.
func _store() -> StoreScreen:
	if _store_screen != null and is_instance_valid(_store_screen):
		return _store_screen
	_store_screen = get_tree().get_first_node_in_group("store_screen") as StoreScreen
	return _store_screen


## Where the man is looking from, in world coordinates.
func _eyes_of(man: Node3D) -> Transform3D:
	var eyes := _eyes_camera(man)
	return eyes.global_transform if eyes != null else global_transform


## His own camera. Asked of whoever is at the machine, and of whoever is standing
## in the scene once he has let go of it — the trip home is worked out after the
## store has already handed him back.
func _eyes_camera(man: Node3D = null) -> Camera3D:
	var who := man
	if who == null:
		who = _user
	if who == null:
		who = get_tree().get_first_node_in_group("player") as Node3D
	if who == null:
		return null
	return who.get("camera") as Camera3D


## The van parked, or the shift moved on with somebody still at the machine. The
## store shuts itself on the phase; this puts the camera back where it belongs
## rather than leaving the scene looking at a monitor.
func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	if _user == null:
		return
	var screen := _store()
	if screen != null:
		screen.close()


func _play(player: AudioStreamPlayer3D) -> void:
	if player != null and player.stream != null:
		player.play()
