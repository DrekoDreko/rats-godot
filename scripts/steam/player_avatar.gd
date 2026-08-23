class_name PlayerAvatar
extends Node3D
## One player as everybody else sees him: a capsule with his Steam name over it,
## standing where the wire says he is standing.
##
## There is one of these per player on the wire, our own included — and that is
## the part worth getting straight. Godot replicates a node onto the node with
## the *same path* on the other machine, so for our position to reach anybody
## there has to be a node here that stands for us and that they have too. That
## is this one, put up for every peer under the same name (see
## `scripts/steam/player_avatars.gd`), and the one standing for us is simply
## never drawn: we are already in the map as the character in `player.tscn`, and
## we are inside this very capsule looking out of it.
##
## Which way it works depends on who owns it, and on nothing else:
##
## - **Ours** (`is_multiplayer_authority()`). It reads the character every
##   physics frame — where he is, which way he faces, what he is doing — and
##   writes that into the three `sync_*` variables. The `MultiplayerSynchronizer`
##   under it does the rest: nothing here sends a packet by hand.
## - **Somebody else's.** Those same three variables are written by the wire,
##   twenty times a second, and what is drawn *follows* them rather than jumping
##   to them. That easing is the whole difference between a body walking and a
##   body appearing twenty times a second in slightly different places.
##
## The one exception to the easing is the long jump: anything further off than
## `SNAP_DISTANCE` is not a walk, it is a respawn or a hole in the wire, and
## sliding across the map to it would read as flying.
##
## Nothing is drawn before the first packet lands, either. A capsule that is up
## but has never been told where its player is would stand at the origin, which
## is a lie the moment somebody looks at it.
##
## The state is the whole of the animation there is to play, the character being
## a capsule: it bobs as he walks, harder and faster as he runs, sits low while
## he has a rat in his hands, lower still while he is down on his knees, and
## rides high while he is off the ground. When the real model arrives, `_animate`
## is the one thing here to throw away.
##
## What it asks of the character it stands for is two things and no more:
## `animation_state()` and an `attacked` signal. That is the whole contract, and
## it is why this file knows nothing about weapons, rats or belts.

## Somebody's arm went out — ours, or anybody else's by way of `act()`. It is
## what a sound would hang off the day there is one.
signal acted(action: Action)

## What a player can be seen doing. The character works out which one he is in
## (`player.gd`), this file draws it, and the wire carries the number between
## the two.
enum State {
	IDLE,
	WALKING,
	RUNNING,
	## Off the ground: jumped, or walked off something.
	AIRBORNE,
	## A rat in his hands, which is why he is walking so slowly.
	HOLDING,
	## Down on his knees, moving or not. It is the pose that matters here and not
	## the pace: a crouching man creeping and a crouching man waiting look the
	## same from across the room, and both of them are hunting.
	CROUCHING,
}

## The one-off things, the ones with no state to be in: they happen, everybody
## sees them happen, and a moment later there is nothing left to show. They go
## by `act()` and not by `State` for exactly that reason.
enum Action {
	## Used whatever is in his hands: a grab, a trap going down, a swing.
	SWING,
}

## How fast the drawn body closes on what the wire last said, per second. It is
## a rate and not a duration: what it buys is a body that is always closing the
## gap and never overshooting it, whatever the frame rate at either end.
##
## It is also the whole of the latency the players will feel. Twenty at a run is
## about a third of a metre behind the truth, which is a friend you are walking
## with rather than a friend you are chasing; much higher and every packet that
## goes missing shows up as a twitch instead of being quietly ridden out.
const SMOOTHING := 20.0
## Further off than this and nothing is smoothed at all. A player who respawned
## did not run there.
const SNAP_DISTANCE := 4.0
## How fast the model settles into the pose of a new state.
const POSE_SMOOTHING := 18.0

## Who this stands for, as the wire counts people. It is the name of the node
## too, and that is what makes the paths line up on both machines.
var peer_id := 0
## Who this stands for, as Steam counts people. Handed over by the crowd, which
## had it from the peer himself (see `LobbyManager.steam_id_of_peer`).
##
## It is also what the overalls are painted from, so setting it repaints them.
## Safe before the node is in the tree, like `player_name` and for the same
## reason: the crowd knows who this is a moment before the node is a node.
var steam_id := 0:
	set(value):
		steam_id = value
		_repaint()

## The name floating over the capsule. Safe to set before the node is in the
## tree — the label picks it up on the way in — because whoever puts one of
## these up knows the name a moment before the node is a node.
var player_name := "":
	set(value):
		player_name = value
		if _tag != null:
			_tag.text = value

# --- What crosses the wire --------------------------------------------------
# Written by whoever owns this avatar, read by everybody else. They are plain
# variables and not the node's own transform on purpose: what arrives is where
# the player *is*, and where he is drawn is allowed to be a little behind it.

## Where he is standing, in world space.
var sync_position := Vector3.ZERO
## Which way he is facing. The yaw only: the pitch is his camera's business, and
## nothing outside his own screen is drawn from it.
var sync_yaw := 0.0
## What he is doing, as a `State`.
var sync_state := State.IDLE

## The character this avatar reads, on the machine it belongs to. Null on
## everybody else's, where the wire is the source instead.
var _source: Node3D
## A packet has landed: this capsule knows where it stands.
var _seen := false
## Where the walk cycle is, from 0 to 1.
var _bob := 0.0
## Resting depth of the nub on the chest, so that a swing has somewhere to come
## back to.
var _front_rest := 0.0
var _swing: Tween

## The overalls' own material, made private on the way up so that dressing one
## man does not dress the whole van in his colour — the scene hands the same
## `StandardMaterial3D` to every capsule otherwise.
var _body_material: StandardMaterial3D

@onready var _model: Node3D = $Model
@onready var _body: MeshInstance3D = $Model/Body
@onready var _front: Node3D = $Model/Front
@onready var _tag: Label3D = $Name
@onready var _sync: MultiplayerSynchronizer = $Sync


func _ready() -> void:
	_tag.text = player_name
	_front_rest = _front.position.z
	_body_material = _own_body_material()
	# The colour is read from `SessionManager` and never kept here, so that a
	# body is wearing what the crew says he is wearing rather than what he was
	# wearing when this node went up. What changes it is the host, and this
	# hears about it the same way every other panel in the game does.
	ColorManager.color_changed.connect(_on_color_changed)
	_repaint()
	# Not drawn yet either way: ours is never drawn at all, and anybody else's
	# waits for the wire to say where he is.
	visible = false
	if is_multiplayer_authority():
		# We are the source, so there is nothing to ease towards.
		set_process(false)
		return
	set_physics_process(false)
	_sync.synchronized.connect(_on_synchronized)


## Ours, and only ours: the character is read, and the reading is what goes out.
## In `_physics_process` because that is where the character moves — reading him
## between two of his own steps would put a stutter on the wire that no amount
## of smoothing at the other end could take back out.
func _physics_process(_delta: float) -> void:
	if _source == null:
		return
	sync_position = _source.global_position
	sync_yaw = _source.rotation.y
	sync_state = _source.animation_state()
	# Kept on top of the character rather than left at the origin: nobody here
	# sees it, but the remote debugger's tree — and anything that ever goes
	# looking for a player's body — should find it where the player is.
	global_position = sync_position
	rotation.y = sync_yaw


## Anybody else's: what arrived is a target, not a place to be.
func _process(delta: float) -> void:
	if not _seen:
		return
	var weight := 1.0 - exp(-SMOOTHING * delta)
	if global_position.distance_to(sync_position) > SNAP_DISTANCE:
		global_position = sync_position
	else:
		global_position = global_position.lerp(sync_position, weight)
	rotation.y = lerp_angle(rotation.y, sync_yaw, weight)
	_animate(delta)


## The character to read, handed over by the crowd on the machine this player is
## sitting at. It is also where the one-off actions are picked up: the character
## says he used what is in his hands, and that goes out to everybody as an
## `act`.
func follow(player: Node3D) -> void:
	_source = player
	player.attacked.connect(_on_source_attacked)


## Something that happened, rather than something that is. It runs on every
## machine, this one included (`call_local`), so that the arm goes out at the
## same moment for the player who swung it and for the player watching him.
##
## Only the peer this avatar belongs to may call it, and that is the whole of
## the authority model here: everybody owns his own body and nobody else's.
@rpc("authority", "call_local", "reliable")
func act(action: Action) -> void:
	acted.emit(action)
	if action == Action.SWING:
		_swing_arm()

# --- Drawing him ------------------------------------------------------------

## The first packet: he stops being a rumour and becomes a body. Snapped rather
## than eased, because there is nothing yet to ease from.
func _on_synchronized() -> void:
	if _seen:
		return
	_seen = true
	global_position = sync_position
	rotation.y = sync_yaw
	visible = true


## The animation, such as a capsule can have one: a bob for the walk, a bigger
## and faster one for the run, a dip for the rat in his hands, a deeper one for
## the crouch and a lift for the ground not being under him.
func _animate(delta: float) -> void:
	var cycle := 0.0
	var height := 0.0
	var settle := 0.0
	match sync_state:
		State.WALKING:
			cycle = 2.2
			height = 0.05
		State.RUNNING:
			cycle = 3.6
			height = 0.09
		State.AIRBORNE:
			settle = 0.06
		State.HOLDING:
			settle = -0.12
		State.CROUCHING:
			settle = -0.35
	_bob = fmod(_bob + delta * cycle, 1.0) if cycle > 0.0 else 0.0
	var pose := settle + sin(_bob * TAU) * height
	_model.position.y = lerpf(_model.position.y, pose, 1.0 - exp(-POSE_SMOOTHING * delta))


## Somebody's colour was settled. Only ours is worth a repaint, and asking which
## is cheaper than repainting four capsules every time one man picks.
func _on_color_changed(changed_id: int, _color: Color) -> void:
	if changed_id == steam_id:
		_repaint()


## The overalls, in whatever colour the crew says this man is wearing. Called on
## the way up, whenever the Steam ID is filled in — which for a peer whose
## introduction is still in the air happens after the capsule is already up — and
## whenever the host settles a colour.
##
## A man the crew has never heard of keeps the colour the scene was built in.
## That is not a fallback so much as the honest answer: there is nothing to read,
## and grey would be a claim about him.
func _repaint() -> void:
	if _body_material == null or steam_id == 0 or not SessionManager.has_player(steam_id):
		return
	_body_material.albedo_color = SessionManager.color(steam_id)


## A private copy of the capsule's material, for the reason above.
func _own_body_material() -> StandardMaterial3D:
	if _body == null:
		return null
	var source := _body.get_active_material(0) as StandardMaterial3D
	var copy: StandardMaterial3D = source.duplicate() if source != null \
		else StandardMaterial3D.new()
	_body.set_surface_override_material(0, copy)
	return copy


## The nub on the chest goes out and comes back. It is the placeholder for an
## arm on the placeholder for a body, and it is what makes an action on the far
## side of the map something you can watch happen.
func _swing_arm() -> void:
	if _swing != null and _swing.is_running():
		_swing.kill()
	_swing = create_tween()
	_swing.tween_property(_front, "position:z", _front_rest - 0.25, 0.08)
	_swing.tween_property(_front, "position:z", _front_rest, 0.16)


func _on_source_attacked(_hit: bool) -> void:
	act.rpc(Action.SWING)
