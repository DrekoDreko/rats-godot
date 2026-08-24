class_name PlayerAvatar
extends Node3D
## One player as everybody else sees him: the man in the hazmat suit, with his
## Steam name over him, standing where the wire says he is standing.
##
## There is one of these per player on the wire, our own included — and that is
## the part worth getting straight. Godot replicates a node onto the node with
## the *same path* on the other machine, so for our position to reach anybody
## there has to be a node here that stands for us and that they have too. That
## is this one, put up for every peer under the same name (see
## `scripts/steam/player_avatars.gd`), and the one standing for us is simply
## never drawn: we are already in the map as the character in `player.tscn`, and
## we are inside this very body looking out of it.
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
## Nothing is drawn before the first packet lands, either. A body that is up but
## has never been told where its player is would stand at the origin, which is a
## lie the moment somebody looks at it.
##
## The state is handed straight to `PlayerModel`, which turns it into an
## animation. That this file no longer knows *how* is the point of the split:
## the same scene draws the character on his own machine, so a man's legs move
## the same way on his screen and on his colleague's, and neither this file nor
## `player.gd` has to be told what running looks like.
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
	## Down on his knees and still. Waiting, listening, or lining something up.
	CROUCHING,
	## Down on his knees and moving. It was one state with `CROUCHING` for as long
	## as the body was a capsule, on the reasoning that a crouching man creeping
	## and a crouching man waiting look the same from across the room. They did,
	## because there was nothing to tell them apart with. The model has a walk on
	## its knees and a wait on its knees, and telling a man who is closing on you
	## from a man who is sitting still is worth the one extra value.
	##
	## New values go on the end. The number is what crosses the wire, so moving an
	## existing one would put every machine on a different reading of the same
	## packet.
	CROUCH_WALKING,
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
## A packet has landed: this body knows where it stands.
var _seen := false

@onready var _model: PlayerModel = $Model
@onready var _tag: Label3D = $Name
@onready var _sync: MultiplayerSynchronizer = $Sync


func _ready() -> void:
	_tag.text = player_name
	# The colour is read from `SessionManager` and never kept here, so that a
	# body is wearing what the crew says he is wearing rather than what he was
	# wearing when this node went up. What changes it is the host, and this
	# hears about it the same way every other panel in the game does.
	#
	# Reached through the tree rather than by its global name, and that is not
	# fussiness: a bench run with `--script` compiles this file before the
	# autoloads are in the tree, so the global name is not a name yet and the
	# whole class fails to compile — which shows up not as a missing colour but
	# as every avatar instantiating as a plain `Node3D` with no script on it.
	# `_test_color.gd` says the same thing at its top, and takes the same road.
	var colors := _autoload("ColorManager")
	if colors != null:
		colors.color_changed.connect(_on_color_changed)
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
	# What he is doing is handed straight over: the model owns the question of
	# which animation that is. The crouch is worth a word — the animation lowers
	# the body by a third of a metre on its own, so nothing here lowers it as
	# well. The capsule had to be dropped by hand to look like it was kneeling; a
	# man with knees does not.
	_model.set_state(sync_state)


## The character to read, handed over by the crowd on the machine this player is
## sitting at. It is also where the one-off actions are picked up: the character
## says he used what is in his hands, and that goes out to everybody as an
## `act`.
func follow(player: Node3D) -> void:
	_source = player
	player.attacked.connect(_on_source_attacked)


## Something that happened, rather than something that is. It runs on every
## machine, this one included (`call_local`), so that it lands at the same moment
## for the player who did it and for the player watching him.
##
## Only the peer this avatar belongs to may call it, and that is the whole of
## the authority model here: everybody owns his own body and nobody else's.
##
## **A swing currently shows nothing.** The capsule had a nub on its chest that
## was thrown forward and pulled back, and that went with the capsule; the model
## has no swing animation to put in its place. The message still crosses and
## `acted` still fires, so a sound or a hit marker hung off this works today —
## what is missing is the arm, and it is missing on purpose rather than by
## oversight. The whole of the fix, when there is an animation, is one call in
## `PlayerModel`.
@rpc("authority", "call_local", "reliable")
func act(action: Action) -> void:
	acted.emit(action)

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
	var session := _autoload("SessionManager")
	if _model == null or steam_id == 0 or session == null \
			or not session.has_player(steam_id):
		return
	_model.set_tint(session.color(steam_id))


## An autoload, reached without going through our own position in the tree.
##
## Two reasons it is not simply the global name, and not `get_node` either. The
## global name does not exist in a bench run with `--script`, where this file is
## compiled before the autoloads are in the tree — and a name that is not a name
## yet fails the whole class to compile, which shows up as every avatar coming up
## as a plain `Node3D` with no script on it. And `get_node` walks from *here*,
## while `steam_id` is filled in by the crowd one line before `add_child`
## (`player_avatars.gd`), so at that moment there is no here to walk from.
func _autoload(autoload_name: String) -> Node:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return null
	return loop.root.get_node_or_null(NodePath(autoload_name))


func _on_source_attacked(_hit: bool) -> void:
	act.rpc(Action.SWING)
