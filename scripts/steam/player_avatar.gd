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
## What it asks of the character it stands for is four things and no more:
## `animation_state()` and `arms_state()` for what he is, `attacked` and
## `squeezed` for what he does. That is the whole contract, and it is why this
## file knows nothing about weapons, rats or belts — a squeeze arrives here as a
## squeeze, not as a click on a pair of hands.

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
	## Retired. It used to mean "a rat in his hands", back when that was the
	## whole of what a man could be seen doing and it beat everything else in
	## `player.gd: animation_state()` — which is exactly why a player carrying a
	## rat slid across the floor with his feet nailed down. What his legs do and
	## what his hands do are two questions now, and this one is the wrong answer
	## to both.
	##
	## Kept rather than deleted because the number is what crosses the wire:
	## removing it would renumber everything under it, and two machines on
	## different builds would read the same packet differently. Nothing produces
	## it and nothing should.
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

## What his *hands* are doing, which is a separate question from what the rest
## of him is doing and crosses the wire separately.
##
## It is a second variable and not more values on `State` because the two
## multiply: a man holding a rat can be standing, walking, running or down on
## his knees, and folding that into one enum means four more values today and
## four more again the next time a body can be in two conditions at once. Two
## small numbers on the wire is cheaper than that in every sense, and it is what
## lets `PlayerModel` keep one clip per state and pose the arms over the top.
enum Arms {
	## Empty, and doing whatever the animation says.
	FREE,
	## Full: a rat is being held in front of him, and being strangled. The arms
	## are posed at it rather than animated (`PlayerArms`).
	HOLDING,
}

## The one-off things, the ones with no state to be in: they happen, everybody
## sees them happen, and a moment later there is nothing left to show. They go
## by `act()` and not by `State` for exactly that reason.
enum Action {
	## Used whatever is in his hands: a grab, a trap going down, a swing.
	SWING,
	## One squeeze of the neck of a rat already held.
	##
	## It is an action and not a state for the reason all of these are: it
	## happens and then there is nothing left to show, and the *rhythm* of them
	## is the whole of what a watcher learns from it. A man hammering at an
	## animal is about to kill it; a man who has stopped is about to lose it
	## (`hands.gd: decay`), and until this crossed the wire the two looked
	## identical from outside — which is to say, both looked like a man standing
	## still.
	##
	## New values go on the end, the same as `State` and for the same reason.
	SQUEEZE,
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
## How far away a name is still written at full strength, and how far away it
## has faded out altogether, in metres.
##
## A name is there to tell one hazmat suit from another in the room you are in,
## and both numbers come from that. Inside `TAG_FULL_DISTANCE` is about the size
## of a room in these houses, so a teammate you are working alongside is always
## named. Past `TAG_FADE_DISTANCE` he is somebody you cannot make out anyway, and
## a name still hanging over him would be the label reaching further than the
## eye — four billboards legible across a whole floor, telling you where everyone
## is standing through the walls between you.
const TAG_FULL_DISTANCE := 12.0
const TAG_FADE_DISTANCE := 18.0

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
## What his hands are doing, as an `Arms`.
var sync_arms := Arms.FREE

## The character this avatar reads, on the machine it belongs to. Null on
## everybody else's, where the wire is the source instead.
var _source: Node3D
## A packet has landed: this body knows where it stands.
var _seen := false

## How fast this body is travelling along the ground, in metres per second.
##
## It does not cross the wire, and it does not need to: everything that wants it
## can work it out from the positions that already do. On our own machine it is
## read straight off the character; on everybody else's it is the distance
## between two packets over the time between them, which is the same number the
## sender would have written and one variable fewer on the wire.
##
## What wants it is the rats. A man walking past is worth less notice than a man
## running past (`rat.gd: _alert_radius_for`), and until this existed the rats
## could only ask that of the character standing on their own machine — so a
## guest could sprint through a room and be, to every rat in it, a man strolling.
var speed := 0.0

## Where the last packet put this body, and how long ago. The two of them are
## what `speed` is worked out from on a watched avatar.
var _last_sync_position := Vector3.ZERO
var _sync_age := 0.0

@onready var _model: PlayerModel = $Model
@onready var _tag: Label3D = $Name
## How solid the name and its outline are with nothing faded — whatever the
## scene was built with.
##
## Kept because the fade *scales* these rather than setting the alpha outright.
## The outline is deliberately half transparent (it is there to lift the letters
## off a white wall, not to draw a box round them), and a fade that wrote
## `outline_modulate.a = faded` would throw that away the moment anybody walked
## close enough to be at full strength — the thick black letters this was fixing
## in the first place, back again at ten metres.
@onready var _tag_alpha: float = _tag.modulate.a
@onready var _tag_outline_alpha: float = _tag.outline_modulate.a
@onready var _sync: MultiplayerSynchronizer = $Sync
## Where a rat this player has grabbed is held, on the machines that are only
## watching him. It stands in for the `Head/CapturePoint` of `player.tscn`, which
## exists on his machine alone: the host has no character for a guest, only this
## body, so a guest's catch has to hang off something that is here.
##
## It sits at chest height in front of the body rather than in the middle of a
## screen, and that difference is the point. On the holder's own machine the
## animal is held against his camera, filling the frame; to everybody else he is
## a man carrying a rat in front of him, which is what they should see.
##
## **It is moved onto the hands every frame** (`_process`), rather than resting
## at the fixed spot the scene puts it at. The spot in the scene was a guess at
## where a pair of hands would be if the body had any, and it was near enough
## while `HOLDING` played `Idle` and the arms hung at his sides — near enough,
## that is, to a rat visibly floating in mid-air beside a man ignoring it. Now
## that the arms are posed there is a real answer (`PlayerModel.grip_point`), and
## the animal hangs in the grip. What the scene sets is only where it sits before
## the first frame.
@onready var capture_point: Node3D = $CapturePoint


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
	# With no wire under it `is_multiplayer_authority` has no id to read and
	# complains for the question; solo there is one machine and every avatar on
	# it is ours.
	var ours := not multiplayer.has_multiplayer_peer() \
		or multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
		or is_multiplayer_authority()
	if ours:
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
	sync_arms = _source.arms_state()
	# Read off the character rather than worked out from his last position: he is
	# a `CharacterBody3D` and already knows, and the number he knows is the true
	# one rather than one frame's approximation of it.
	var body := _source as CharacterBody3D
	if body != null:
		speed = Vector2(body.velocity.x, body.velocity.z).length()
	# Kept on top of the character rather than left at the origin: nobody here
	# sees it, but the remote debugger's tree — and anything that ever goes
	# looking for a player's body — should find it where the player is.
	global_position = sync_position
	rotation.y = sync_yaw


## Anybody else's: what arrived is a target, not a place to be.
func _process(delta: float) -> void:
	if not _seen:
		return
	# How fast he is going, from the ground his last two packets covered. It is
	# measured against `sync_position` — where the wire says he is — and not
	# against the drawn body, which is deliberately behind it: easing the drawn
	# position and then measuring it would report a man slowing down every time
	# the smoothing caught up with him.
	_sync_age += delta
	if not sync_position.is_equal_approx(_last_sync_position):
		var travelled := Vector2(
			sync_position.x - _last_sync_position.x,
			sync_position.z - _last_sync_position.z
		).length()
		# A packet that arrives on the same frame as the last one would divide by
		# nothing; one that arrives after a long silence says more about the wire
		# than about the man, so the window is floored at the interval the
		# synchroniser is set to.
		speed = travelled / maxf(_sync_age, 0.05)
		_last_sync_position = sync_position
		_sync_age = 0.0
	elif _sync_age > 0.25:
		# Nothing new for a quarter of a second: he is standing still, or the
		# wire has gone quiet. Either way he is not running, and leaving the last
		# reading up would keep a man who stopped dead looking like a sprinter.
		speed = 0.0

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
	# And his hands separately — see `Arms` for why the two are not one number.
	_model.set_arms(sync_arms)
	# The held rat hangs off the grip rather than off a fixed spot in the scene.
	# After the model has been told, so that the point read is this frame's and
	# not the last one's: the animal lagging the hands by a frame is the whole
	# difference between a rat being carried and a rat being followed.
	capture_point.global_position = _model.grip_point()
	# Where the name is being read from. The camera and not our own character:
	# the two part company the moment a player looks around, and it is the camera
	# that is doing the reading. Null in a bench, and in the frames before a map
	# has settled on one — the name simply keeps whatever strength it had.
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		fade_tag(camera.global_position)


## The character to read, handed over by the crowd on the machine this player is
## sitting at. It is also where the one-off actions are picked up: the character
## says he used what is in his hands, and that goes out to everybody as an
## `act`.
func follow(player: Node3D) -> void:
	_source = player
	player.attacked.connect(_on_source_attacked)
	player.squeezed.connect(_on_source_squeezed)


## Something that happened, rather than something that is. It runs on every
## machine, this one included (`call_local`), so that it lands at the same moment
## for the player who did it and for the player watching him.
##
## Only the peer this avatar belongs to may call it, and that is the whole of
## the authority model here: everybody owns his own body and nobody else's.
##
## A squeeze shows: the hands close on the animal (`PlayerArms.squeeze`).
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
	# The squeeze has something to draw, and it is drawn here rather than left to
	# whatever listens to `acted`: it is the body's own gesture, and the body is
	# this file's business. The swing still has nothing, for the reason above.
	if action == Action.SQUEEZE and _model != null:
		_model.squeeze()
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
	# The first packet is a place, not a movement: measuring from the origin
	# would call him a man crossing the map at a thousand metres a second.
	_last_sync_position = sync_position
	_sync_age = 0.0
	visible = true


## The name, dimmed by how far off its owner is, as seen from `viewer`.
##
## Done here rather than in the scene because a `Label3D` has no distance fade of
## its own — the `distance_fade_*` properties belong to `BaseMaterial3D`, and
## writing them into the `.tscn` is the worst kind of wrong: the scene loads, no
## error is printed, and the name simply never fades. That is not a guess; it was
## written that way first and `_test_nametag.gd` is what caught it.
##
## Only ever run on somebody else's avatar. Ours is never drawn at all, and
## `_process` is switched off on it.
##
## The viewpoint is handed in rather than read off the camera in here, and that
## is worth a word. A `Camera3D` is only ever current in a viewport that is
## really drawing, so headless `get_camera_3d()` is null and a fade that asked
## for it itself could not be tested at all — it would quietly do nothing on the
## bench and there would be no way to tell that from doing nothing in the game.
func fade_tag(viewer: Vector3) -> void:
	var distance := viewer.distance_to(global_position)
	# `inverse_lerp` is not clamped, so a man standing on top of us would come
	# back brighter than opaque and one across the map darker than gone.
	var faded := clampf(
		inverse_lerp(TAG_FADE_DISTANCE, TAG_FULL_DISTANCE, distance), 0.0, 1.0
	)
	_tag.modulate.a = _tag_alpha * faded
	# The outline is what makes a name readable against a wall, so it fades with
	# the name rather than staying behind as a ghost of it.
	_tag.outline_modulate.a = _tag_outline_alpha * faded
	# Nothing to draw at all once it is gone: a fully transparent label is still
	# a quad the renderer sorts and rasterises every frame, once per player.
	_tag.visible = faded > 0.0


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


func _on_source_squeezed() -> void:
	act.rpc(Action.SQUEEZE)
