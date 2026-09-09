class_name HingedDoor
extends Node3D
## A door in the house, and the fact that anybody may swing it.
##
## The leaf is modelled in Blender with its **origin on the hinge**, so opening
## one is a rotation about this node's own Y and nothing else — no offset to
## correct, no pivot node to keep in step with the mesh. The two poses come off
## the model as well: the exporter carries `closed_deg` and `open_deg` through as
## glTF extras, which means moving a door in Blender moves the door in the game
## and there is no second copy of the angle here to fall out of date.
##
## **A door is shared furniture, so it goes over the wire.** Unlike the van's
## doors — which are a function of the phase, and so work themselves out
## identically on every machine from `PhaseManager` — a house door moves because
## somebody pushed it, and a man who opens one has to open it for the crew. The
## swing is announced with `any_peer` rather than `authority`: there is no host
## here who owns the door, only whoever reached it first.
##
## The leaf carries its own collision, and that collision **moves with it**
## (`AnimatableBody3D`), so a closed door blocks the corridor and an open one
## does not. It sits on the scenery layer with the walls, which is also the layer
## the navigation mesh is baked from — a rat routes around a door exactly the way
## it routes around a wall.

## How long the leaf takes to swing, and how it eases. Slow enough to read as a
## door rather than a switch, quick enough not to hold a man in a doorway with a
## rat behind him.
const SWING_TIME := 0.45
const SWING_EASE := Tween.EASE_OUT
const SWING_TRANS := Tween.TRANS_CUBIC

## The names the Blender exporter writes the two poses under, and the metadata
## key the importer parks them in. glTF `extras` arrive as one dictionary hung on
## the node rather than as separate metadata entries, so both keys are read out of
## `EXTRAS_KEY`. See `_read_poses`.
const EXTRAS_KEY := "extras"
const CLOSED_KEY := "closed_deg"
const OPEN_KEY := "open_deg"

## Where the poses fall back to when the model carries no extras — a door that
## opens a quarter turn anticlockwise from wherever it was placed. A door with no
## angles on it is a modelling mistake rather than a valid state, so this exists
## to keep such a door usable and visibly wrong, not to be relied on.
const FALLBACK_SWING := -90.0

signal swung(open: bool)

## The two poses, in radians about local Y.
var _closed := 0.0
var _open := 0.0
var _is_open := false
var _swing: Tween = null


func _ready() -> void:
	_read_poses()
	rotation.y = _closed


## Whether the leaf is currently swung out of its frame.
func is_open() -> bool:
	return _is_open


## Swings the door the other way, for everybody. Called by the `Interactable`
## sitting in the doorway.
func toggle(_by: Node3D = null) -> void:
	if _on_the_wire():
		_set_open.rpc(not _is_open)
	else:
		_set_open(not _is_open)


## The swing itself, run on every machine at once, the caller's included
## (`call_local`). This is the only place `_is_open` is written.
##
## `any_peer`: a door belongs to whoever is standing at it, and the crew is not
## arranged around a host for this. Two men pushing the same door in the same
## frame is not a conflict worth arbitrating — both packets arrive, the second
## settles the pose, and the door ends up somewhere both of them can see.
@rpc("any_peer", "call_local", "reliable")
func _set_open(open: bool) -> void:
	if open == _is_open:
		return
	_is_open = open
	_swing_to(_open if open else _closed)
	swung.emit(open)


## Animates the leaf to a pose, cancelling whatever swing was already running so
## that a door pushed twice in quick succession does not fight itself.
func _swing_to(angle: float) -> void:
	if _swing != null and _swing.is_valid():
		_swing.kill()
	_swing = create_tween()
	_swing.set_ease(SWING_EASE).set_trans(SWING_TRANS)
	_swing.tween_property(self, ^"rotation:y", angle, SWING_TIME)


## The two poses, taken off the model where the modeller left them.
##
## The importer hangs the glTF `extras` object on the node as a single metadata
## dictionary, so this is `get_meta` rather than anything gltf-aware. A door whose
## model carries neither
## angle keeps the rotation it was placed at and opens `FALLBACK_SWING` from
## there, which is wrong-looking on purpose — a silent right answer here would
## hide a door that never got its angles.
func _read_poses() -> void:
	var closed_deg := rotation_degrees.y
	var open_deg := closed_deg + FALLBACK_SWING
	var extras: Dictionary = get_meta(EXTRAS_KEY, {}) as Dictionary
	if extras.has(CLOSED_KEY):
		closed_deg = float(extras[CLOSED_KEY])
		open_deg = closed_deg + FALLBACK_SWING
	if extras.has(OPEN_KEY):
		open_deg = float(extras[OPEN_KEY])
	_closed = deg_to_rad(closed_deg)
	_open = deg_to_rad(open_deg)


## Whether there is anybody to say it to. An `rpc` with no wire under it is an
## error in the log for a call that would have run here anyway — the same
## question the traps ask before their own announcements.
func _on_the_wire() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	return not multiplayer.multiplayer_peer is OfflineMultiplayerPeer
