extends SceneTree
## Rat replication bench: two machines in one process.
##
## Run with: godot --headless --script _test_rat_sync.gd
##
## The same trick as `_test_sync.gd`, turned on the rats instead of the players:
## two `SceneMultiplayer`s over ENet on the loopback, each rooted at its own
## subtree, which is as close to two machines as one process gets. `/root/A` is
## the host and `/root/B` is the guest.
##
## Each side carries the same `Rats` container with a `MultiplayerSpawner` over
## it, which is the pair `world.tscn` carries. The host then adds rats to it the
## way `house.gd` does — named, given to peer 1, placed, and only then added —
## and the question the whole bench asks is whether they turn up on the other
## side and behave like animals once they do.
##
## What is checked:
##
## - A rat added on the host becomes a rat on the guest, under the same name.
## - The guest's copy belongs to the host and knows it: its physics is off, so
##   it does not think and never moves itself.
## - The host's rat moving is the guest's rat moving: it arrives, it arrives
##   *behind* — eased, not teleported — and it catches up when the host stops.
## - The coat crosses, so the same animal is the same colour on both screens.
## - A rat killed on the host reads as dead on the guest, and a guest cannot
##   kill or pick up a rat that is not his.
## - The host taking a rat off the map takes it off the guest's map too.
## - And the whole point of the guards: with no wire at all a rat thinks for
##   itself exactly as it always did — the solo game is untouched.

const PORT := 47130
## Frames of slack between one step and the next.
const WAIT := 8
## How long the connection is given before the bench gives up on it.
const PATIENCE := 600
## How many frames the host drags its rat for, and how far it goes each one.
const STEPS := 40
const STRIDE := 0.08
## How far the drawn rat may be off the real one once everything has landed.
const CAUGHT_UP := 0.25
## The biggest single frame of movement that still reads as running.
const NOT_A_TELEPORT := 0.6

const RAT_SCENE := "res://scenes/rat.tscn"
## The body that stands for a player on everybody else's machine. The bench
## needs one because a guest's catch is held against it (`rat.gd:
## _capture_point_of`), which is the whole of what the grab checks below test.
const AVATAR_SCENE := "res://scenes/player_avatar.tscn"
## Where the solo rat is stood. Off the origin on purpose — see the step.
const SOLO_SPOT := Vector3(11.0, 0.0, -7.0)

var _mp_host: SceneMultiplayer
var _mp_guest: SceneMultiplayer
## The guest's id on the wire. ENet lets a client pick its own, so it is read
## back rather than assumed.
var _guest_id := 0

var _rats_host: Node3D
var _rats_guest: Node3D

var _rat_host: Node3D
var _rat_guest: Node3D

## Where the watched rat was last frame, and the worst it did: the biggest step
## it took in one frame and the furthest it ever fell behind.
var _last_seen := Vector3.ZERO
var _max_step := 0.0
var _max_gap := 0.0

## The second rat, the live one the guest reaches across the wire and grabs.
var _catch_host: Node3D
var _catch_guest: Node3D
## What the purse held before the guest strangled his catch.
var _wallet_before := 0

## The solo rat, put up at the end with no wire under it at all.
var _solo: Node3D
var _solo_rat: Node3D

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	# Without a screen the loop runs at thousands of frames a second, and the
	# easing in `_draw_remote` would pass whole between two physics frames.
	Engine.max_fps = 60

	var host_peer := ENetMultiplayerPeer.new()
	host_peer.create_server(PORT, 4)
	var guest_peer := ENetMultiplayerPeer.new()
	guest_peer.create_client("127.0.0.1", PORT)
	_guest_id = guest_peer.get_unique_id()

	_mp_host = _build_world("A", host_peer)
	_mp_guest = _build_world("B", guest_peer)
	_rats_host = root.get_node("A/Rats")
	_rats_guest = root.get_node("B/Rats")


## One machine's worth of map: the `Rats` container and the spawner over it. The
## multiplayer is hung off the subtree before the spawner is in it, so that the
## spawner comes up on a wire rather than solo.
func _build_world(world_name: String, peer: MultiplayerPeer) -> SceneMultiplayer:
	var world := Node3D.new()
	world.name = world_name
	root.add_child(world)

	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	set_multiplayer(api, NodePath("/root/%s" % world_name))

	# A floor to stand on. Without one the rat falls for ever, and a rat that
	# never stops moving is a rat the easing can never catch: what it chases is
	# always one frame further down. The game has floors; the bench needs one too
	# or it measures the fall rather than the following.
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = box
	floor_shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(floor_shape)
	world.add_child(floor_body)

	var rats := Node3D.new()
	rats.name = "Rats"
	world.add_child(rats)

	var spawner := MultiplayerSpawner.new()
	spawner.name = "RatSpawner"
	spawner.spawn_path = NodePath("..")
	spawner.add_spawnable_scene(RAT_SCENE)
	rats.add_child(spawner)
	return api


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_the_wire_comes_up()
		1: return _check_a_rat_crosses()
		2: return _check_the_guest_does_not_think()
		3: return _check_it_follows()
		4: return _check_it_catches_up()
		5: return _check_the_coat_crossed()
		6: return _check_a_death_crosses()
		7: return _check_a_guest_can_grab()
		8: return _check_the_guest_is_paid()
		9: return _check_it_leaves()
		10: return _check_a_solo_rat_thinks()
	return _finish()

# --- Steps -----------------------------------------------------------------

## The guest dials the host. Everything after this waits on nothing.
func _check_the_wire_comes_up() -> bool:
	if _mp_guest.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		if _clock < PATIENCE:
			return false
		print("FAIL: the guest never reached the host")
		_failures += 1
		return _finish()
	print("--- host is peer 1, guest is peer %d ---" % _guest_id)
	return _next()


## The host puts a rat down. It should turn up on the guest under the same name.
func _check_a_rat_crosses() -> bool:
	if _rat_host == null:
		var packed: PackedScene = load(RAT_SCENE)
		var rat := packed.instantiate() as Node3D
		# The order `house.gd` uses, and the order that matters: name, authority
		# and place all settled before the node is in the tree.
		rat.name = "Rat_1"
		rat.set_multiplayer_authority(1)
		rat.position = Vector3(2.0, 0.0, 3.0)
		_rats_host.add_child(rat)
		_rat_host = rat
		_clock = 0
		return false

	_rat_guest = _rats_guest.get_node_or_null("Rat_1") as Node3D
	if _rat_guest == null:
		if _clock < PATIENCE:
			return false
		print("FAIL: the rat never reached the guest")
		print("      the guest's container holds: %s" % [_names(_rats_guest)])
		_failures += 1
		return _finish()

	print("PASS: the host's rat is a rat on the guest, under the name %s" % _rat_guest.name)
	if _rat_guest.get_script() == null:
		print("FAIL: it arrived without its script")
		_failures += 1
	return _next()


## Whose rat it is, and what that switched off. This is the whole authority
## model: the guest's copy is a puppet with no opinions.
func _check_the_guest_does_not_think() -> bool:
	# A moment to have run its `_ready` and a few frames of its own.
	if _clock < WAIT:
		return false

	if _rat_guest.get_multiplayer_authority() != 1:
		print("FAIL: the guest's rat thinks it belongs to peer %d, not the host"
				% _rat_guest.get_multiplayer_authority())
		_failures += 1
	else:
		print("PASS: the guest's rat belongs to the host")

	if _rat_guest.is_physics_processing():
		print("FAIL: the guest's rat is still running its physics — it is thinking")
		_failures += 1
	else:
		print("PASS: the guest's rat has its physics switched off")

	if not _rat_host.is_physics_processing():
		print("FAIL: the host's rat is not running its physics — nobody is thinking")
		_failures += 1
	else:
		print("PASS: the host's rat thinks for itself")

	_last_seen = _rat_guest.global_position
	return _next()


## The host drags its rat across the floor. The guest's should follow it, and
## follow it the way an animal does: behind, and without ever teleporting.
func _check_it_follows() -> bool:
	if _clock <= STEPS:
		_rat_host.global_position += Vector3(STRIDE, 0.0, 0.0)
		# The rat publishes from its own `_physics_process`, which is running on
		# the host. Nothing to do here but let it.
		var here := _rat_guest.global_position
		_max_step = maxf(_max_step, here.distance_to(_last_seen))
		_max_gap = maxf(_max_gap, here.distance_to(_rat_host.global_position))
		_last_seen = here
		return false

	if _max_step <= 0.0:
		print("FAIL: the guest's rat never moved at all")
		_failures += 1
		return _next()
	if _max_step > NOT_A_TELEPORT:
		print("FAIL: the guest's rat jumped %.2f m in one frame — that is not running"
				% _max_step)
		_failures += 1
	else:
		print("PASS: it followed, biggest single frame %.3f m" % _max_step)
	if _max_gap <= 0.0:
		print("FAIL: it was never behind — it is being teleported, not eased")
		_failures += 1
	else:
		print("PASS: it ran behind, worst gap %.2f m" % _max_gap)
	return _next()


## The host stops. The guest's rat should close the gap and settle on it.
func _check_it_catches_up() -> bool:
	if _clock < 60:
		return false
	var gap := _rat_guest.global_position.distance_to(_rat_host.global_position)
	if gap > CAUGHT_UP:
		print("FAIL: it never caught up — still %.2f m behind after a second" % gap)
		_failures += 1
	else:
		print("PASS: it caught up, %.3f m off" % gap)
	return _next()


## The coat. It is rolled on the host and crosses as an index, so that the same
## animal is the same colour on both screens.
func _check_the_coat_crossed() -> bool:
	var mine: int = _rat_host.sync_fur
	var theirs: int = _rat_guest.sync_fur
	if mine < 0:
		print("SKIP: this species has no furs to roll")
		return _next()
	if mine != theirs:
		print("FAIL: the host's rat wears fur %d, the guest's wears %d" % [mine, theirs])
		_failures += 1
	else:
		print("PASS: the same rat wears the same coat on both screens (fur %d)" % mine)
	return _next()


## A rat killed on the host, and the guard the other way: a guest may not kill
## or pick up a rat that is not his.
func _check_a_death_crosses() -> bool:
	if _clock == 1:
		_rat_host.take_damage(99)
		return false
	if _clock < WAIT * 3:
		return false

	if not _rat_host.is_dead():
		print("FAIL: the host's rat survived a killing blow")
		_failures += 1
	if _rat_guest.sync_state != _rat_host.sync_state:
		print("FAIL: the guest reads state %d, the host says %d"
				% [_rat_guest.sync_state, _rat_host.sync_state])
		_failures += 1
	else:
		print("PASS: the death crossed — both sides read state %d" % _rat_host.sync_state)

	# A guest may now swing at a rat and grab one — the blow and the grab cross
	# to the host and the host decides. What no machine may do, from either end,
	# is touch an animal that is already dead: this one is a carcass, so both
	# must refuse it outright rather than sending anything over the wire.
	var before: int = _rat_guest.sync_state
	_rat_guest.take_damage(99)
	if _rat_guest.sync_state != before:
		print("FAIL: the guest changed the state of a rat that was already dead")
		_failures += 1
	else:
		print("PASS: a dead rat takes no further hits from the guest")
	if _rat_guest.capture(_rats_guest):
		print("FAIL: the guest picked up a corpse")
		_failures += 1
	else:
		print("PASS: the guest cannot pick up a rat that is already dead")
	return _next()


## The whole point of the change: a *live* rat that a guest grabs becomes his.
##
## The grab is a request — it crosses to the host, the host is the machine that
## thinks for the animal, and it is the host that actually puts the rat in a
## hand. What is checked here is that all three machines end up agreeing about
## it: the guest asked, the host carried it out, and both of them name the same
## man as the one holding it.
func _check_a_guest_can_grab() -> bool:
	if _catch_host == null:
		var packed: PackedScene = load(RAT_SCENE)
		var rat := packed.instantiate() as Node3D
		rat.name = "Rat_2"
		rat.set_multiplayer_authority(1)
		rat.position = Vector3(-4.0, 0.0, 5.0)
		_rats_host.add_child(rat)
		_catch_host = rat
		_clock = 0
		return false

	if _catch_guest == null:
		_catch_guest = _rats_guest.get_node_or_null("Rat_2") as Node3D
		if _catch_guest == null:
			if _clock < PATIENCE:
				return false
			print("FAIL: the second rat never reached the guest")
			_failures += 1
			return _next()
		_clock = 0
		return false

	# The guest's body, standing on the host's map. In the game the crowd node
	# puts one of these up for every peer that says his van is standing
	# (`player_avatars.gd`); here it is placed by hand, because what is being
	# tested is the catch and not the crowd. It matters: it is what a guest's rat
	# is held against on every machine but his own, and without it the host has
	# nothing to hang the catch on.
	if _clock == 1:
		var packed_avatar: PackedScene = load(AVATAR_SCENE)
		var avatar := packed_avatar.instantiate() as PlayerAvatar
		# Named and owned the way the crowd names and owns one, because the name
		# is the address on the wire and the authority is what stops this machine
		# writing to somebody else's body.
		avatar.name = "Player%d" % _guest_id
		avatar.peer_id = _guest_id
		avatar.set_multiplayer_authority(_guest_id)
		root.get_node("A").add_child(avatar)
		avatar.global_position = Vector3(-4.0, 0.0, 6.5)
		return false

	# A moment on its feet before anybody grabs at it, so the grab lands on a rat
	# that is properly up rather than one still finding the floor.
	if _clock == WAIT:
		# The hand the guest holds it in. In the game this is the capture point
		# under his own camera; here any node in his own tree will do, because
		# what is being tested is who the host says owns the catch, and the host
		# never sees this node at all.
		_catch_guest.capture(_rats_guest)
		return false
	if _clock < WAIT * 6:
		return false

	if _catch_host.holder_peer() != _guest_id:
		print("FAIL: the host says the rat is held by peer %d, not by the guest (%d)"
				% [_catch_host.holder_peer(), _guest_id])
		_failures += 1
		return _next()
	print("PASS: the guest asked, and the host put the rat in his hand")

	if not _catch_guest.is_held_by_me():
		print("FAIL: the guest does not know the rat it grabbed is his")
		_failures += 1
	else:
		print("PASS: the guest knows the catch is his")

	if not _catch_host.is_captured():
		print("FAIL: the host does not have the rat as captured at all")
		_failures += 1
	else:
		print("PASS: the rat is captured on the host, which is where it is thought for")
	return _next()


## And the money. A rat strangled by a guest is the guest's catch, and the
## payment has to cross back to him — for a long while every rat in the game paid
## the host, whoever had actually done the work.
func _check_the_guest_is_paid() -> bool:
	if _clock == 1:
		_wallet_before = _wallet_total()
		_catch_guest.die_in_hands(Death.Type.STRANGULATION)
		return false
	# The gesture is a whole one: the body goes limp and is then stowed, and the
	# money only lands at the far end of it.
	if _clock < 180:
		return false

	# The rat frees itself at the end of the stowing — that is where a strangled
	# animal goes, into the player's belt and off the map — so by now `_catch_host`
	# is very often already gone. That it is gone is half the proof the gesture ran
	# all the way through.
	var gained := _wallet_total() - _wallet_before
	if gained <= 0:
		print("FAIL: the guest strangled a rat and was paid %d" % gained)
		_failures += 1
	else:
		print("PASS: the guest was paid $%d for the rat he strangled" % gained)
	return _next()


## This process has one `Wallet` autoload standing in for both machines, so the
## total cannot say *which* pocket the money reached — only that it was paid at
## all, and paid once. What proves it went to the right man is the peer the rat
## names as its killer, and that is checked above by `holder_peer`.
func _wallet_total() -> int:
	var wallet := root.get_node_or_null("Wallet")
	return wallet.money if wallet != null else 0


## The host takes the rat off the map. The spawner should take the guest's copy
## with it — which is how a hunt ends without a rat left standing on one screen.
func _check_it_leaves() -> bool:
	if _clock == 1:
		# It may have gone already: the first rat was killed several steps back
		# and a carcass takes itself off the map on its own clock (`rat.gd:
		# _vanish`). Either way what is being checked is the same — that the
		# guest's copy went with it — so a rat that has already left is not a
		# reason to stop, only a reason not to free it twice.
		if is_instance_valid(_rat_host):
			_rat_host.queue_free()
		return false
	if _clock < PATIENCE and _rats_guest.get_node_or_null("Rat_1") != null:
		return false
	if _rats_guest.get_node_or_null("Rat_1") != null:
		print("FAIL: the rat is gone on the host and still standing on the guest")
		_failures += 1
	else:
		print("PASS: the host taking the rat off the map took it off the guest's too")
	return _next()


## And the case that matters most, because it is the one the game is played in
## today: no wire at all. A lone player's rat is its own authority, so it thinks,
## it moves itself, and nothing above changed that.
func _check_a_solo_rat_thinks() -> bool:
	if _solo == null:
		_solo = Node3D.new()
		_solo.name = "Solo"
		root.add_child(_solo)
		# No `set_multiplayer` on this subtree: it inherits the root's, which has
		# no peer at all. That is the solo game.
		var packed: PackedScene = load(RAT_SCENE)
		var rat := packed.instantiate() as Node3D
		rat.name = "Rat_Solo"
		_solo.add_child(rat)
		# Stood somewhere it could not have arrived at by accident, so that
		# `sync_position` finding its way there is proof the rat ran its own
		# frame rather than proof of a default.
		rat.global_position = SOLO_SPOT
		_solo_rat = rat
		_clock = 0
		return false

	if _clock < 30:
		return false

	if not _solo_rat.is_multiplayer_authority():
		print("FAIL: a solo rat does not own itself")
		_failures += 1
	else:
		print("PASS: a solo rat owns itself")
	if not _solo_rat.is_physics_processing():
		print("FAIL: a solo rat is not thinking — the guards broke the solo game")
		_failures += 1
	else:
		print("PASS: a solo rat thinks for itself")
	if not _solo_rat.visible:
		print("FAIL: a solo rat is invisible — it is waiting for a packet that never comes")
		_failures += 1
	else:
		print("PASS: a solo rat is drawn straight away")
	# It has had half a second to run its own frames, so its own `_publish` has
	# put where it stands into `sync_position`. Compared on the flat: there is no
	# floor under the solo subtree, so it has been falling the whole time and its
	# height is the one thing that will not match.
	var published := Vector2(_solo_rat.sync_position.x, _solo_rat.sync_position.z)
	var wanted := Vector2(SOLO_SPOT.x, SOLO_SPOT.z)
	if published.distance_to(wanted) > 0.5:
		print("FAIL: a solo rat never published — `_publish` is not running (%.2v)"
				% _solo_rat.sync_position)
		_failures += 1
	else:
		print("PASS: a solo rat runs its own frame (published %.2v)" % _solo_rat.sync_position)
	return _next()

# --- Plumbing ---------------------------------------------------------------

func _names(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		out.append(child.name)
	return out


func _next() -> bool:
	_step += 1
	_clock = 0
	return false


func _finish() -> bool:
	if _failures == 0:
		print("--- all rat replication checks passed ---")
	else:
		print("--- %d check(s) failed ---" % _failures)
	if _mp_host != null and _mp_host.multiplayer_peer != null:
		_mp_host.multiplayer_peer.close()
	if _mp_guest != null and _mp_guest.multiplayer_peer != null:
		_mp_guest.multiplayer_peer.close()
	quit(1 if _failures > 0 else 0)
	return true
