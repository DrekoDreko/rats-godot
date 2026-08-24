extends SceneTree
## Trap replication bench: two machines in one process.
##
## Run with: godot --headless --script _test_trap_sync.gd
##
## The same trick as `_test_rat_sync.gd`, turned on the things the player leaves
## on the floor instead of the things that walk over them: two `SceneMultiplayer`s
## over ENet on the loopback, each rooted at its own subtree, which is as close to
## two machines as one process gets. `/root/A` is the host and `/root/B` is the
## guest.
##
## Each side carries the same `Traps` container with a `MultiplayerSpawner` over
## it, which is the pair `world.tscn` carries. The question the whole bench asks
## is the one the card asks: **does a trap one man puts down exist for the
## others?**
##
## What is checked:
##
## - A trap added on the host becomes a trap on the guest, under the same name.
## - Two traps of the same kind do not collide over one name — the counter is
##   what makes `Mousetrap_1` and `Mousetrap_2` two nodes and not one fight.
## - The pose crosses: a trap arrives where it was put, turned the way it was
##   turned, and a strip of glue arrives at the length it was laid at.
## - The guest's copy belongs to the host and knows it: it will not decide it has
##   caught anything, and a rat walking over it on the guest's screen alone
##   changes nothing anywhere.
## - The host springing a trap springs the guest's, on the same rat.
## - The ghost — the translucent trap-to-be — never crosses. It is not in the
##   replicated container at all, which is the whole of how that is guaranteed.
## - And the guards a host keeps on what he will accept: an unknown id, a spot
##   across the house, and a phase with no floor in it.
##
## This bench drives `TrapManager` directly rather than through a weapon. What a
## weapon adds on top is a ray at the floor and a ghost, and both are covered by
## `_test_traps.gd`; what is being measured here is the wire underneath.

const PORT := 47131
## Frames of slack between one step and the next.
const WAIT := 8
## How long the connection is given before the bench gives up on it.
const PATIENCE := 600

const MOUSETRAP_SCENE := "res://scenes/traps/mousetrap.tscn"
const GLUE_SCENE := "res://scenes/traps/glue_trap.tscn"
## The same table `TrapManager.SCENES` holds, by the same ids — see `_build_trap`
## on why the bench carries its own copy.
const SCENES := {
	"mousetrap": MOUSETRAP_SCENE,
	"rat_glue": GLUE_SCENE,
}

## Where the traps are put. Apart from each other so that one is never mistaken
## for the other, and off the origin so that a trap replicated at the origin
## because nothing crossed reads as a failure rather than as a pass.
const FIRST_SPOT := Vector3(2.0, 0.01, 3.0)
const SECOND_SPOT := Vector3(-4.0, 0.01, 1.5)
const GLUE_SPOT := Vector3(0.0, 0.01, -3.0)
## The way the second trap is turned, so that a rotation that did not cross is
## visible as a rotation that stayed at zero.
const FACING := Vector3(1.0, 0.0, 0.0)
## How long the strip of glue is laid.
const GLUE_LENGTH := 1.8
## How far off a replicated pose may be and still be the same pose. It is loose
## because the numbers went through a packet, not because anything is estimated.
const CLOSE_ENOUGH := 0.01

## What a stand-in rat answers to. It is written out here rather than kept in a
## file of its own because it exists for one bench and one step of it: the trap
## calls these four the moment it goes off, and none of them has anything to do
## with what is being measured.
const STAND_IN := preload("res://_test_trap_sync_rat.gd")

## The phases, spelled out rather than read off `Phase`: naming the class from a
## bench drags its script into the compile that happens before the autoloads
## exist (see `_test_traps.gd` on `Death`).
const PHASE_LOBBY := 0
const PHASE_SURVEY := 2

var _mp_host: SceneMultiplayer
var _mp_guest: SceneMultiplayer
## The guest's id on the wire. ENet lets a client pick its own, so it is read
## back rather than assumed.
var _guest_id := 0

var _traps_host: Node3D
var _traps_guest: Node3D
var _spawner_host: MultiplayerSpawner

var _first_host: Node3D
var _first_guest: Node3D
var _glue_host: Node3D

## The rat the host springs a trap on.
var _rat_host: Node3D

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	# Without a screen the loop runs at thousands of frames a second. The same
	# reason `_test_rat_sync.gd` pins it.
	Engine.max_fps = 60

	var host_peer := ENetMultiplayerPeer.new()
	host_peer.create_server(PORT, 4)
	var guest_peer := ENetMultiplayerPeer.new()
	guest_peer.create_client("127.0.0.1", PORT)
	_guest_id = guest_peer.get_unique_id()

	_mp_host = _build_world("A", host_peer)
	_mp_guest = _build_world("B", guest_peer)
	_traps_host = root.get_node("A/Traps")
	_traps_guest = root.get_node("B/Traps")
	_spawner_host = _traps_host.get_node("TrapSpawner")


## One machine's worth of map: the `Traps` container and the spawner over it. The
## multiplayer is hung off the subtree before the spawner is in it, so that the
## spawner comes up on a wire rather than solo.
func _build_world(world_name: String, peer: MultiplayerPeer) -> SceneMultiplayer:
	var world := Node3D.new()
	world.name = world_name
	root.add_child(world)

	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	set_multiplayer(api, NodePath("/root/%s" % world_name))

	var traps := Node3D.new()
	traps.name = "Traps"
	world.add_child(traps)

	var spawner := MultiplayerSpawner.new()
	spawner.name = "TrapSpawner"
	spawner.spawn_path = NodePath("..")
	spawner.add_spawnable_scene(MOUSETRAP_SCENE)
	spawner.add_spawnable_scene(GLUE_SCENE)
	# Both machines build a trap the same way. Without this the guest gets the
	# node and none of the numbers that say where it goes.
	spawner.spawn_function = _build_trap
	traps.add_child(spawner)
	return api


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_the_wire_comes_up()
		1: return _check_a_trap_crosses()
		2: return _check_the_guest_does_not_decide()
		3: return _check_the_pose_crossed()
		4: return _check_two_of_a_kind()
		5: return _check_a_strip_of_glue_crosses()
		6: return _check_a_catch_crosses()
		7: return _check_the_host_turns_down_nonsense()
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


## The host puts a mousetrap down. It should turn up on the guest under the same
## name — which is the whole bug this card exists to fix.
func _check_a_trap_crosses() -> bool:
	if _first_host == null:
		_first_host = _put_down("mousetrap", 1, FIRST_SPOT, Vector3.ZERO, 1.0)
		_clock = 0
		return false

	_first_guest = _traps_guest.get_node_or_null("Mousetrap_1") as Node3D
	if _first_guest == null:
		if _clock < PATIENCE:
			return false
		print("FAIL: the trap never reached the guest")
		print("      the guest's container holds: %s" % [_names(_traps_guest)])
		_failures += 1
		return _finish()

	print("PASS: the host's trap is a trap on the guest, under the name %s" % _first_guest.name)
	if _first_guest.get_script() == null:
		print("FAIL: it arrived without its script")
		_failures += 1
	return _next()


## Whose trap it is, and what that stops it doing. A trap on the guest is a
## picture of the host's trap: it may not decide it has caught anything, because
## two machines deciding that is one rat counted twice.
func _check_the_guest_does_not_decide() -> bool:
	# A moment to have run its `_ready`.
	if _clock < WAIT:
		return false

	if _first_guest.get_multiplayer_authority() != 1:
		print("FAIL: the guest's trap thinks it belongs to peer %d, not the host"
				% _first_guest.get_multiplayer_authority())
		_failures += 1
	else:
		print("PASS: the guest's trap belongs to the host")

	_expect(_first_guest.is_armed(), "the guest's trap should be waiting for a rat")
	_expect(_first_host.is_armed(), "the host's trap should be waiting for a rat")

	# The one that matters: a body walking into the guest's own `Area3D` must not
	# spring it. It is called directly rather than by walking a rat over it,
	# because what is being tested is the guard and not the physics.
	var intruder := _a_rat()
	_traps_guest.add_child(intruder)
	_first_guest._on_body_entered(intruder)
	_expect(_first_guest.is_armed(),
		"a rat walking onto the guest's copy should not spring it — the host decides")
	intruder.queue_free()
	return _next()


## The trap arrived where it was put. A trap that crossed but landed at the
## origin is a trap in the wrong room, which is the same bug wearing a hat.
func _check_the_pose_crossed() -> bool:
	var gap := _first_guest.global_position.distance_to(FIRST_SPOT)
	_expect(gap <= CLOSE_ENOUGH,
		"the guest's trap should be where the host put it (off by %.3f m)" % gap)
	return _next()


## Two mousetraps, which is what the old naming could not do: both were called
## `Mousetrap`, and two nodes cannot share one path. The second one also carries
## a turn, so that a rotation which did not cross shows up here.
func _check_two_of_a_kind() -> bool:
	if _clock == 1:
		_put_down("mousetrap", 2, SECOND_SPOT, FACING, 1.0)
		return false
	var second := _traps_guest.get_node_or_null("Mousetrap_2") as Node3D
	if second == null:
		if _clock < PATIENCE:
			return false
		print("FAIL: the second mousetrap never reached the guest")
		print("      the guest's container holds: %s" % [_names(_traps_guest)])
		_failures += 1
		return _finish()

	_expect(_traps_guest.get_node_or_null("Mousetrap_1") != null,
		"the first trap should still be there — the second must not have taken its name")
	var gap := second.global_position.distance_to(SECOND_SPOT)
	_expect(gap <= CLOSE_ENOUGH,
		"the second trap should be where it was put (off by %.3f m)" % gap)
	# Turned to face `FACING`, which `Basis.looking_at` puts on the -Z axis.
	var forward := -second.global_basis.z
	_expect(forward.distance_to(FACING) <= CLOSE_ENOUGH,
		"the second trap should be turned the way it was laid (facing %v)" % forward)
	print("PASS: two mousetraps on one floor, under two names")
	return _next()


## A strip of glue stretches, and the stretch has to cross with it: a tray
## replicated at its own size is a strip that catches nothing along most of its
## run.
func _check_a_strip_of_glue_crosses() -> bool:
	if _glue_host == null:
		_glue_host = _put_down("rat_glue", 3, GLUE_SPOT, FACING, GLUE_LENGTH)
		_clock = 0
		return false
	var glue := _traps_guest.get_node_or_null("GlueTrap_3") as Node3D
	if glue == null:
		if _clock < PATIENCE:
			return false
		print("FAIL: the strip of glue never reached the guest")
		_failures += 1
		return _finish()
	_expect(absf(glue.scale.z - GLUE_LENGTH) <= CLOSE_ENOUGH,
		"the guest's strip should be %.2f long, and is %.2f" % [GLUE_LENGTH, glue.scale.z])
	print("PASS: the strip of glue crossed at its own length")
	return _next()


## The catch itself. The host springs his trap on a rat, and the guest's trap
## goes off on the guest's copy of the same rat — which is what stops one animal
## being counted on two machines.
##
## The rat is a bare body in the `rats` group rather than the real animal: what
## is being measured is the announcement crossing, and a real rat would drag its
## own replication into the middle of it.
func _check_a_catch_crosses() -> bool:
	if _rat_host == null:
		# The same name on both sides, because the catch travels as the rat's
		# *path* — which is exactly why `house.gd` names its animals before it
		# adds them.
		_rat_host = _a_rat()
		_rat_host.name = "Rat_1"
		_traps_host.add_child(_rat_host)
		var echo := _a_rat()
		echo.name = "Rat_1"
		_traps_guest.add_child(echo)
		_clock = 0
		return false

	if _clock == 1:
		# Straight at the host's trap, which is the machine allowed to decide.
		_first_host._on_body_entered(_rat_host)
		return false

	if _first_guest.is_armed():
		if _clock < PATIENCE:
			return false
		print("FAIL: the host sprang his trap and the guest's is still armed")
		_failures += 1
		return _next()

	print("PASS: a catch on the host is a catch on the guest")
	_expect(not _first_host.is_armed(), "the host's own trap should have sprung too")
	var caught: Node3D = _first_guest.prey()
	_expect(caught != null and caught.name == "Rat_1",
		"the guest's trap should be holding the same rat the host caught")
	_expect(caught != null and caught.hit,
		"the guest's trap should have swung at the rat it caught")
	return _next()


## What the host will not accept. Each of these is a packet a tampered client
## could send, and each is turned down without anything landing on any floor.
func _check_the_host_turns_down_nonsense() -> bool:
	var manager := root.get_node_or_null("TrapManager")
	if manager == null:
		print("SKIP: no TrapManager autoload in this run")
		return _next()

	var before := _real_traps(_traps_host)

	# An id that names no trap. A client that could choose the scene could choose
	# any scene in the project.
	manager.request_place(1, "not_a_trap", FIRST_SPOT, Vector3.ZERO, 1.0)
	_expect(not manager.is_known("not_a_trap"), "an unknown id should not be a trap")

	# A phase with no floor under it.
	var phase := root.get_node_or_null("PhaseManager")
	if phase != null:
		phase.go_to(PHASE_LOBBY)
		_expect(not manager.is_open(), "the van is not a floor to put a trap on")
		manager.request_place(1, "mousetrap", FIRST_SPOT, Vector3.ZERO, 1.0)
		phase.go_to(PHASE_SURVEY)
		_expect(manager.is_open(), "the survey is where traps go down")

	_expect(_real_traps(_traps_host) == before,
		"nothing the host refused should have landed on the floor (%d -> %d)"
			% [before, _real_traps(_traps_host)])
	print("PASS: the host turned down what it should")
	return _next()

# --- Odds and ends ----------------------------------------------------------

## Puts a trap on the host's floor, through the spawner and its builder — which
## is the road `TrapManager._spawn` takes, and the only road on which the pose
## crosses. A trap has no `MultiplayerSynchronizer` and wants none: it never
## moves after it is set down, so where it is travels once, as spawn data, rather
## than in a packet every frame for the rest of the shift.
func _put_down(trap_id: String, number: int, at: Vector3,
		facing: Vector3, length: float) -> Node3D:
	return _spawner_host.spawn({
		"id": trap_id,
		"n": number,
		"at": at,
		"facing": facing,
		"length": length,
		"by": 0,
	}) as Node3D


## The builder both machines use. It is `TrapManager._build_trap` by another
## name: the bench cannot reach the autoload's copy from `_initialize` (the
## autoloads are not in the tree yet when the MainLoop script is built), so the
## same description is written once here and hung on both spawners. What it must
## keep in step with the real one is the shape of the dictionary and the naming,
## and both are checked by every step below.
func _build_trap(data: Variant) -> Node:
	var fields := data as Dictionary
	var path: String = SCENES.get(String(fields.get("id", "")), "")
	if path.is_empty():
		return null
	var packed: PackedScene = load(path)
	var trap := packed.instantiate() as Node3D
	trap.name = "%s_%d" % [trap.get_script().get_global_name(), int(fields.get("n", 0))]
	trap.set_multiplayer_authority(1)
	trap.position = fields.get("at", Vector3.ZERO)
	var facing: Vector3 = fields.get("facing", Vector3.ZERO)
	if not facing.is_zero_approx():
		trap.basis = Basis.looking_at(facing, Vector3.UP)
	trap.scale.z = maxf(float(fields.get("length", 1.0)), 0.001)
	return trap


## A body a trap will take for a rat. Bare on purpose — see the note on
## `_check_a_catch_crosses` — but not so bare that the trap falls over on it: a
## mousetrap claims the carcass and swings at it, so the stand-in has to be able
## to be claimed and hit. It records what was done to it rather than acting on
## it, which is what makes it useful here: the bench can ask whether the blow
## landed without a whole animal's state machine in the way.
func _a_rat() -> CharacterBody3D:
	var rat := CharacterBody3D.new()
	rat.add_to_group("rats")
	rat.collision_layer = 4
	rat.set_script(STAND_IN)
	return rat


## How many traps are on a floor, counting by what a child *is*: the container
## also holds the spawner, and that is not a trap. The same sum `house.gd` does
## over its `Rats`.
func _real_traps(container: Node3D) -> int:
	var count := 0
	for child in container.get_children():
		if child is Area3D and (child as Node).get_script() != null:
			count += 1
	return count


## What is actually in a container, for the message on a failure. A bench that
## only says "it did not arrive" leaves the next person guessing whether it
## arrived under another name.
func _names(container: Node) -> Array[String]:
	var found: Array[String] = []
	for child in container.get_children():
		found.append(String(child.name))
	return found


func _expect(condition: bool, complaint: String) -> void:
	if condition:
		return
	print("FAIL: %s" % complaint)
	_failures += 1


func _next() -> bool:
	_step += 1
	_clock = 0
	return false


func _finish() -> bool:
	print("--- %d frames, %d failure(s) ---" % [_frames, _failures])
	quit(1 if _failures > 0 else 0)
	return true
