extends SceneTree
## Rat perception bench: who a rat is actually afraid of.
##
## Run with: godot --headless --script _test_rat_fear.gd
##
## A rat thinks on one machine and is hunted on several. For a long while it only
## ever asked about *one* player — `get_first_node_in_group("player")`, which on
## any machine is the character sitting at it — so on the host every guest was
## invisible: a man could walk up to a rat, stand on it, and be groomed at.
##
## What replaced that is `_hunters()`, which is the local character plus every
## `PlayerAvatar` that stands for somebody across the wire. This bench holds that
## claim to the fire with no wire at all: avatars are stood on the map by hand,
## which is exactly what a remote player looks like to a rat, and the questions
## are asked directly.
##
## What is checked:
##
## - A rat alone in a room is afraid of nobody, and its own machine's character
##   counts as somebody.
## - An avatar — a player at another machine — is somebody the rat can see and
##   measure itself against. This is the bug that started all of it.
## - The threat a rat measures against is the *nearest* man, whichever kind of
##   body he happens to be.
## - Sight is asked of everybody: a rat hidden from the near man and open to the
##   far one has been seen.
## - Cornered between two, it runs at neither of them.
## - Our own avatar is not counted twice — every peer has one, ours included.

const RAT_SCENE := "res://scenes/rat.tscn"
const AVATAR_SCENE := "res://scenes/player_avatar.tscn"
const PLAYER_SCENE := "res://scenes/player.tscn"

## Where the rat stands for the whole bench. Everything else is placed around it.
const RAT_SPOT := Vector3.ZERO

var _world: Node3D
var _rat: Node3D
var _failures := 0
var _frames := 0
## Whether the checks that need no physics have already run, and the wall for
## the one that does is standing. See `_physics_process`.
var _staged := false


func _initialize() -> void:
	Engine.max_fps = 60

	_world = Node3D.new()
	_world.name = "World"
	root.add_child(_world)

	var packed: PackedScene = load(RAT_SCENE)
	_rat = packed.instantiate() as Node3D
	_rat.name = "Rat"
	_world.add_child(_rat)
	_rat.global_position = RAT_SPOT


func _physics_process(_delta: float) -> bool:
	_frames += 1
	# A couple of frames for the rat to have run its `_ready` and settled.
	if _frames < 4:
		return false

	# The sight checks are rays, and a body only answers rays once the physics
	# server has taken it in — which happens between frames, not on the line that
	# added it. So the one check that needs a wall sets its room up on one frame
	# and asks its questions on the next; the rest need nothing and run in one go.
	if not _staged:
		_staged = true
		_check_an_empty_room()
		_check_an_avatar_is_a_hunter()
		_check_the_nearest_is_the_threat()
		_check_it_runs_between_them()
		_check_our_own_body_is_not_counted_twice()
		_stage_the_wall()
		return false

	_check_everybody_gets_a_look()

	if _failures == 0:
		print("--- all rat perception checks passed ---")
	else:
		print("--- %d check(s) failed ---" % _failures)
	quit(1 if _failures > 0 else 0)
	return true

# --- Checks -----------------------------------------------------------------

## Nobody about at all. It is the floor of the whole thing: with no hunters the
## rat must not invent one, and must not fall over asking.
func _check_an_empty_room() -> void:
	_clear()
	var hunters: Array = _rat.call("_hunters")
	_expect(hunters.is_empty(), "an empty room holds no hunters (found %d)" % hunters.size())
	_expect(not _rat.call("_sees_player"), "a rat alone is seen by nobody")
	_expect(is_inf(_rat.call("_player_distance")), "a rat alone measures nobody")


## The bug this whole change is about: a man at another machine is a man.
##
## He is a `PlayerAvatar` and not a character — that is the only body the host
## has for him — and until this he was not in the rat's world at all.
func _check_an_avatar_is_a_hunter() -> void:
	_clear()
	_stand_avatar(7, Vector3(3.0, 0.0, 0.0))

	var hunters: Array = _rat.call("_hunters")
	if not _expect(hunters.size() == 1,
			"a player at another machine is a hunter (found %d)" % hunters.size()):
		return
	var distance: float = _rat.call("_player_distance")
	_expect(absf(distance - 3.0) < 0.2,
			"the rat measures him at %.2f m, and he is standing at 3" % distance)
	_expect(_rat.call("_sees_player"),
			"a man standing three metres away in an empty room is seen")


## Which of them the flight is measured against. Two bodies of different kinds,
## and the near one wins whichever kind it is.
func _check_the_nearest_is_the_threat() -> void:
	_clear()
	_stand_avatar(7, Vector3(12.0, 0.0, 0.0))
	_stand_avatar(8, Vector3(2.0, 0.0, 0.0))

	var distance: float = _rat.call("_player_distance")
	_expect(absf(distance - 2.0) < 0.2,
			"with men at 2 m and 12 m the rat measures %.2f" % distance)

	# And the other way round, to be sure it is distance deciding and not the
	# order they were put up in.
	_clear()
	_stand_avatar(7, Vector3(2.0, 0.0, 0.0))
	_stand_avatar(8, Vector3(12.0, 0.0, 0.0))
	distance = _rat.call("_player_distance")
	_expect(absf(distance - 2.0) < 0.2,
			"the order they arrived in does not decide the threat (%.2f)" % distance)


## Puts up the room the sight check needs, a frame before it is asked about: one
## man close by with a wall between him and the rat, and nobody else yet.
func _stage_the_wall() -> void:
	_clear()
	_stand_avatar(7, Vector3(2.0, 0.0, 0.0))
	_stand_wall(Vector3(1.0, 0.0, 0.0))


## Sight is everybody's, not just the near man's. The near man has a wall in
## front of him; a second one is then stood in the open further off, and his
## clear line is enough for the rat to have been seen.
func _check_everybody_gets_a_look() -> void:
	var near := _rat.call("_hunters")[0] as Node3D
	_expect(not _rat.call("_sees", near),
			"a man behind a wall does not see the rat")
	_expect(not _rat.call("_sees_player"),
			"with only that man about, the rat is unseen")

	# Now a second man in the open, further away. He needs no frame of his own:
	# what he asks of the physics server is a ray through empty space, and the
	# only body in it is the wall, which is already in.
	_stand_avatar(8, Vector3(0.0, 0.0, 6.0))
	_expect(_rat.call("_sees_player"),
			"the man in the open sees it, though the near one cannot")


## Cornered. With a man on each side the way out is between them, and the old
## "away from the nearest" would have run the animal straight into one of them.
func _check_it_runs_between_them() -> void:
	_clear()
	_stand_avatar(7, Vector3(4.0, 0.0, 0.0))
	_stand_avatar(8, Vector3(-4.0, 0.0, 0.0))

	var out: Vector3 = _rat.call("_away_from_hunters")
	# Both men are on the X axis, so the only direction that is away from both is
	# along Z. Which way along it does not matter — the room is symmetrical.
	_expect(absf(out.x) < 0.3,
			"cornered between two, it does not run at either of them (x = %.2f)" % out.x)
	_expect(absf(out.z) > 0.7,
			"it takes the gap between them (z = %.2f)" % out.z)

	# And with one man only it still answers what it always did: straight away
	# from him.
	_clear()
	_stand_avatar(7, Vector3(5.0, 0.0, 0.0))
	out = _rat.call("_away_from_hunters")
	_expect(out.x < -0.8,
			"with one man it runs straight away from him (x = %.2f)" % out.x)


## Every peer has an avatar, ours included — that is how our own position reaches
## anybody. It stands exactly where our character stands, so counting both would
## have the rat afraid of one man twice.
func _check_our_own_body_is_not_counted_twice() -> void:
	_clear()
	var player := _stand_player(Vector3(4.0, 0.0, 0.0))
	# Our own avatar, named for the peer we are. With no wire at all
	# `multiplayer.get_unique_id()` is 1, which is what the crowd would have
	# called us.
	_stand_avatar(1, player.global_position)

	var hunters: Array = _rat.call("_hunters")
	_expect(hunters.size() == 1,
			"our own body is one man, not two (found %d)" % hunters.size())

# --- Plumbing ---------------------------------------------------------------

## Takes everybody off the map, leaving the rat alone on it.
func _clear() -> void:
	for node in _world.get_children():
		if node == _rat:
			continue
		_world.remove_child(node)
		node.queue_free()
	# The groups are what the rat reads, and a node that has been asked to free
	# itself is still in them until the frame ends. Taken out by hand so that the
	# next check starts in a genuinely empty room.
	for group in ["player", "player_avatars"]:
		for node in get_nodes_in_group(group):
			node.remove_from_group(group)


## A player at another machine, as this one sees him: an avatar, drawn, with a
## peer id of his own.
func _stand_avatar(peer_id: int, spot: Vector3) -> Node3D:
	var packed: PackedScene = load(AVATAR_SCENE)
	var avatar := packed.instantiate() as PlayerAvatar
	avatar.name = "Player%d" % peer_id
	avatar.peer_id = peer_id
	_world.add_child(avatar)
	avatar.global_position = spot
	# `_hunters` skips a body that has never had a packet — it would be standing
	# at the origin claiming to be somewhere. These are stood by hand, so they are
	# marked as drawn by hand too.
	avatar.visible = true
	return avatar


## The character at *this* machine.
func _stand_player(spot: Vector3) -> Node3D:
	var packed: PackedScene = load(PLAYER_SCENE)
	var player := packed.instantiate() as Node3D
	player.name = "Player"
	_world.add_child(player)
	player.global_position = spot
	return player


## Something to hide behind, on the scenery layer the sight checks read.
func _stand_wall(spot: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 4.0, 8.0)
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	body.global_position = spot + Vector3.UP


func _expect(condition: bool, message: String) -> bool:
	if condition:
		print("PASS: %s" % message)
		return true
	print("FAIL: %s" % message)
	_failures += 1
	return false
