extends Control
## Piss on the lens: what a faceful from a sprayer leaves behind
## (`rat.gd::_spray_at`).
##
## Like every other piece of this HUD it keeps no count of its own and asks nobody
## anything — the player announces that he has been caught (`splashed`) and this
## draws it. It is the same shape as the health bar's white flash on `damaged`,
## and for the same reason: the player owns *what just happened to me*, and the
## screen is only its echo.
##
## **It is the answer to "why is my health going down".** A bar draining says a
## man is being hurt and nothing else; a lens full of yellow says he was hurt *by
## a rat that turned round and got him*, which is a thing he can learn to avoid.
## Stepping on an old streak does not do this — that is his boots, and the hiss
## out of the floor is answer enough (`scripts/house/rat_streak.gd`).
##
## **Alpha is fine here, and it is worth saying why.** Everything on the floor in
## this game has to be opaque, because the PS1 shader discards any fragment below
## full alpha (`scripts/ps1.gdshader`). That is a *spatial* shader built-in. This
## is a `CanvasItem` in a `CanvasLayer` with no shader on it at all, so the rule
## does not reach here — and piss on a lens is translucent, so translucent is what
## it should be.
##
## **The fade is a tween and not a `_process`.** Four seconds of `queue_redraw()`
## every frame to lower one number is work for nothing; the project's vocabulary
## for a short event is a tween on a property (`explosive_cheese::_flash_and_remove`,
## `mousetrap::_snap`), and `modulate:a` fades everything drawn here at once.

## How many spots one faceful throws, and the most that may ever be on screen at
## once. The cap is what stops two sprayers catching a man together and whiting
## out his whole view for four seconds.
const SPOTS := Vector2i(6, 11)
const MAX_SPOTS := 24
## How big one spot is, in pixels of the 640x360 viewport.
const RADIUS := Vector2(5.0, 18.0)
## How much of the middle is kept clear, in pixels. An eighteen-pixel blob sitting
## on the crosshair for four seconds is not a splatter, it is a blindfold — and
## the thing he needs to keep his eyes on is twenty centimetres long.
const CENTRE_CLEAR := 26.0
## Where down the screen the spots start. The spray came off something at his
## feet, so it lands low.
const LOW_BIAS := 0.3
## How long it takes to dry, in seconds.
const FADE := 4.0
## The wet middle of a spot and the thinner ring round it.
const CORE := Color(0.86, 0.82, 0.32, 0.72)
const RIM := Color(0.52, 0.47, 0.19, 0.45)
const RIM_SCALE := 1.35

## Every spot on the lens, packed as (x, y, radius). A `Vector3` and not a
## dictionary because this is walked in `_draw`.
var _blobs: Array[Vector3] = []
## The drying. Held so a second faceful can cut it short and start again rather
## than fading from wherever the first one had got to.
var _fade: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

	# Wait one frame so the player is already in the tree. The tree is held across
	# the wait rather than asked for again after it: a phase can end on the frame
	# this HUD is waiting through, and a node resuming out of the tree has no
	# `get_tree()` to reach through — the same guard `hud_prompt.gd` explains.
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	if not is_inside_tree():
		return
	var player := tree.get_first_node_in_group("player")
	if player == null:
		return
	player.splashed.connect(_on_splashed)
	# Waking up back at the van with a lens full of piss would be a wound that
	# outlived the body it was on.
	player.died.connect(clear)


## Caught. The spots are added rather than replaced, so a second faceful in the
## same breath is worse than the first — up to the cap.
func _on_splashed() -> void:
	for _spot in randi_range(SPOTS.x, SPOTS.y):
		if _blobs.size() >= MAX_SPOTS:
			break
		_blobs.append(_roll_blob())
	_start_drying()
	show()
	queue_redraw()


## Wiped. Called on respawn, and by the bench.
func clear() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
	_blobs.clear()
	modulate.a = 1.0
	hide()
	queue_redraw()


## How many spots are on the lens. It is what the bench reads: `_draw` may never
## run at all under the headless renderer, so what is checked has to be the state
## behind the drawing rather than the pixels.
func spot_count() -> int:
	return _blobs.size()


## One spot, somewhere in the lower part of the frame and clear of the middle.
## Pushed out of the centre rather than re-rolled, so the roll always terminates.
func _roll_blob() -> Vector3:
	var frame := size
	var at := Vector2(
		randf() * frame.x,
		lerpf(frame.y * LOW_BIAS, frame.y, randf()))
	var middle := frame * 0.5
	var away := at - middle
	if away.length() < CENTRE_CLEAR:
		if away.is_zero_approx():
			away = Vector2.DOWN
		at = middle + away.normalized() * CENTRE_CLEAR
	return Vector3(at.x, at.y, randf_range(RADIUS.x, RADIUS.y))


func _start_drying() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	modulate.a = 1.0
	_fade = create_tween()
	# Holds nearly opaque and then goes quickly, which is what a splatter drying
	# on glass does — and what a linear fade does not.
	_fade.tween_property(self, "modulate:a", 0.0, FADE) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade.tween_callback(clear)


func _draw() -> void:
	for blob in _blobs:
		var at := Vector2(blob.x, blob.y)
		draw_circle(at, blob.z * RIM_SCALE, RIM)
		draw_circle(at, blob.z, CORE)
