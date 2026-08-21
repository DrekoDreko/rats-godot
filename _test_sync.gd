extends SceneTree
## Player synchronisation bench: two clients in one process.
##
## Run with: godot --headless --script _test_sync.gd
##
## It needs no Steam and no second machine, which is the whole point of it. The
## acceptance test for this — two accounts, two windows, one walking while the
## other watches — cannot be run on one computer, so what is run here instead is
## the same thing one layer down: two `SceneMultiplayer`s over ENet on the
## loopback, each rooted at its own subtree, which is as close to two clients as
## a single process gets. Steam is only ever the transport underneath; the
## replication above it is the same replication either way.
##
## `/root/A` is the host and `/root/B` is the guest. Each carries a stand-in for
## the character — a `Node3D` with the two things the avatar actually reads off
## a player, `animation_state()` and an `attacked` signal — and the same
## `Players` node the map carries. The stand-in is moved by hand rather than
## driven by `player.gd`, and that is deliberate: `Input` is global to the
## process, so a keypress meant for one of the two would move both, and a body
## that follows because it was told to and a body that follows because it read
## the same keyboard look exactly alike.
##
## What is checked is everything the acceptance test would look at:
##
## - Both sides put up one capsule per player on the wire, ours included, under
##   the same name, with the authority on the peer it stands for.
## - Our own is never drawn, and somebody else's is not drawn either until the
##   first packet says where he is.
## - A player walking on one side is a body walking on the other: it arrives, it
##   arrives *behind* — it is eased, not teleported — and it catches up when he
##   stops.
## - His state crosses too, and the capsule plays it: a bob for the run that is
##   not there when he stands still.
## - An action crosses as an action: one `act` over the wire, one arm going out.
## - A name that lands after the capsule is up lands on the capsule.
## - Somebody closing their game takes their capsule off the other's map.
##
## The last two steps leave the stand-ins behind and open the real map with no
## wire under it at all, which is the solo hunt: nobody standing about, and the
## real character answering the one question the avatar asks of him.

## The loopback port. Nothing else in the project listens, and the bench closes
## it on the way out.
const PORT := 47120
## Frames of slack between one step and the next.
const WAIT := 8
## How long the connection is given before the bench gives up on it.
const PATIENCE := 600
## How many frames the walk lasts, and how far he goes each one — 0.12 m at 60
## frames a second is about seven metres a second, which is the game's own walk.
const STEPS := 40
const STRIDE := 0.12
## A Steam ID for the guest, for the one step that pretends to be Steam.
const GUEST_STEAM_ID := 76561190000000002
## How far the drawn body is allowed to be off the real one once the walking has
## stopped and everything has landed.
const CAUGHT_UP := 0.2
## The biggest single frame of movement that still reads as walking. Anything
## more than this on one frame is a teleport.
const NOT_A_TELEPORT := 0.5

## The character the avatar reads, cut down to the two things it asks for. The
## real one is `player.gd`, which has a belt, a camera and flesh on top of this.
class StubPlayer extends Node3D:
	signal attacked(hit: bool)

	var state := PlayerAvatar.State.IDLE

	func animation_state() -> PlayerAvatar.State:
		return state

	## The map puts every character on his own standing spot on the way in. The
	## real one remembers it as the spot to respawn on; here there is nothing to
	## respawn from.
	func set_spawn(spot: Vector3) -> void:
		global_position = spot

	func swing() -> void:
		attacked.emit(true)


var _lobby: Node

var _mp_host: SceneMultiplayer
var _mp_guest: SceneMultiplayer
## The guest's id on the wire. ENet lets a client pick its own, so it is never
## simply "2" and is read back rather than assumed.
var _guest_id := 0

## The real map, opened at the end for the solo case.
var _world: Node3D

var _stub_host: StubPlayer
var _stub_guest: StubPlayer
var _crowd_host: Node3D
var _crowd_guest: Node3D

## Where the watched body was last frame, and the worst it did: the biggest step
## it took in one frame and the furthest it ever fell behind.
var _last_seen := Vector3.ZERO
var _max_step := 0.0
var _max_gap := 0.0
## The lowest and highest the model sat while a state was being played.
var _low := 0.0
var _high := 0.0
## What arrived on `acted`, and how far the nub on the chest travelled.
var _actions: Array[int] = []
var _nub_rest := 0.0
var _nub_moved := 0.0

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	# Without a screen the loop runs at thousands of frames a second, and every
	# easing in the avatar would pass whole between two physics frames.
	Engine.max_fps = 60
	_lobby = root.get_node_or_null("LobbyManager")

	var host_peer := ENetMultiplayerPeer.new()
	host_peer.create_server(PORT, 4)
	var guest_peer := ENetMultiplayerPeer.new()
	guest_peer.create_client("127.0.0.1", PORT)
	_guest_id = guest_peer.get_unique_id()

	_mp_host = _build_world("A", host_peer)
	_mp_guest = _build_world("B", guest_peer)
	_stub_host = root.get_node("A/Player")
	_stub_guest = root.get_node("B/Player")
	_crowd_host = root.get_node("A/Players")
	_crowd_guest = root.get_node("B/Players")


## One machine's worth of game. The subtree goes up first and the multiplayer is
## hung off it *before* anything that talks to the wire is in it: the crowd node
## reads the peer on its way in, and a crowd that came up first would come up
## solo.
func _build_world(world_name: String, peer: MultiplayerPeer) -> SceneMultiplayer:
	var world := Node3D.new()
	world.name = world_name
	root.add_child(world)

	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	set_multiplayer(api, NodePath("/root/%s" % world_name))

	var stub := StubPlayer.new()
	stub.name = "Player"
	world.add_child(stub)

	var crowd := Node3D.new()
	crowd.set_script(load("res://scripts/steam/player_avatars.gd"))
	crowd.name = "Players"
	world.add_child(crowd)
	return api


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_the_wire_comes_up()
		1: return _check_everybody_is_up()
		2: return _check_a_body_appears()
		3: return _check_he_walks()
		4: return _check_he_runs()
		5: return _check_he_stands_still()
		6: return _check_an_action_crosses()
		7: return _check_a_late_name_lands()
		8: return _check_he_leaves()
		9: return _check_a_solo_hunt()
		10: return _check_the_character_answers()
	return _finish()

# --- Steps -----------------------------------------------------------------

## The guest dials the host. Everything after this waits on nothing.
func _check_the_wire_comes_up() -> bool:
	if _lobby == null or _crowd_host == null or _crowd_guest == null:
		print("FAIL: the bench did not come up")
		_failures += 1
		return _finish()
	if _mp_guest.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		if _clock < PATIENCE:
			return false
		print("FAIL: the guest never reached the host")
		_failures += 1
		return _finish()
	if _clock < PATIENCE and (_crowd_host.count() < 2 or _crowd_guest.count() < 2):
		return false
	print("--- host is peer 1, guest is peer %d ---" % _guest_id)
	return _advance()


## One capsule per player on either side, ours included, named the same on both
## machines and owned by the peer it stands for. The names are what the packets
## are addressed to, so a mismatch here is the whole thing not working.
func _check_everybody_is_up() -> bool:
	_expect(_crowd_host.count() == 2, "the host should have two bodies, and has %d" % _crowd_host.count())
	_expect(_crowd_guest.count() == 2, "the guest should have two bodies, and has %d" % _crowd_guest.count())

	var mine := _avatar(_crowd_host, 1)
	var theirs := _avatar(_crowd_host, _guest_id)
	if mine == null or theirs == null:
		print("FAIL: the host is missing one of the two bodies")
		_failures += 1
		return _finish()
	_expect(mine.name == "Player1", "our own body should be named after our peer id")
	_expect(theirs.name == "Player%d" % _guest_id, "and the guest's after his")
	_expect(_avatar(_crowd_guest, 1) != null and _avatar(_crowd_guest, 1).name == "Player1",
		"the guest should have the host's body under the same name")

	_expect(mine.is_multiplayer_authority(), "we should own our own body")
	_expect(not theirs.is_multiplayer_authority(), "and not the guest's")
	_expect(_avatar(_crowd_guest, _guest_id).is_multiplayer_authority(),
		"the guest should own his, on his own machine")
	_expect(not _avatar(_crowd_guest, 1).is_multiplayer_authority(),
		"and not the host's — nobody is host of anybody's movement")

	_expect(not mine.visible, "we are inside our own capsule and should not see it")
	_expect(not _stub_host.global_position.is_equal_approx(Vector3.ZERO),
		"the map should have stepped our character onto a standing spot of his own")
	return _advance()


## Somebody else's capsule is not drawn until the wire says where he stands: a
## body at the origin is a lie, and the origin is where an undrawn one sits.
func _check_a_body_appears() -> bool:
	if _clock < WAIT * 2:
		return false
	var mirror := _avatar(_crowd_guest, 1)
	_expect(mirror.visible, "the host's body should be up on the guest's map by now")
	_expect(mirror.global_position.distance_to(_stub_host.global_position) < CAUGHT_UP,
		"and standing where he is standing")
	_expect(not _avatar(_crowd_guest, _guest_id).visible, "the guest still does not see his own")
	return _advance()


## The one the whole thing is for: the host walks, and a body walks on the
## guest's map. It should arrive, arrive a little behind — eased and not
## teleported — and catch up when he stops.
func _check_he_walks() -> bool:
	var mirror := _avatar(_crowd_guest, 1)
	if _clock == 1:
		_max_step = 0.0
		_max_gap = 0.0
		_last_seen = mirror.global_position
		return false

	if _clock <= STEPS:
		_stub_host.global_position += Vector3(STRIDE, 0.0, 0.0)
		_stub_host.rotation.y = -PI * 0.5 * float(_clock) / float(STEPS)
		_stub_host.state = PlayerAvatar.State.WALKING
		_max_gap = maxf(_max_gap, mirror.global_position.distance_to(_stub_host.global_position))
	_max_step = maxf(_max_step, mirror.global_position.distance_to(_last_seen))
	_last_seen = mirror.global_position
	if _clock < STEPS + WAIT * 4:
		return false

	var apart := mirror.global_position.distance_to(_stub_host.global_position)
	_expect(apart < CAUGHT_UP, "he should have caught up once the walking stopped, and is %.2f m off" % apart)
	_expect(_max_gap > 0.0, "and should have been following, not being placed")
	_expect(_max_step < NOT_A_TELEPORT, "no single frame should be a teleport, and one was %.2f m" % _max_step)
	_expect(absf(angle_difference(mirror.rotation.y, _stub_host.rotation.y)) < 0.05,
		"he should be facing the way the host is facing")
	_expect(mirror.sync_state == PlayerAvatar.State.WALKING, "and be walking, as far as the guest knows")

	# Our own body is not eased at all: it is the source, and it sits on the
	# character it is read off.
	_expect(_avatar(_crowd_host, 1).global_position.is_equal_approx(_stub_host.global_position),
		"our own body should sit on our own character")
	# Nobody moved who did not move.
	_expect(_avatar(_crowd_host, _guest_id).global_position.is_equal_approx(_stub_guest.global_position),
		"the guest never moved, and his body should be standing where he is")
	print("--- walked %.1f m, %.2f m behind at worst, %.2f m in the biggest frame ---" % [
		_stub_host.global_position.x, _max_gap, _max_step,
	])
	return _advance()


## The state crosses as well as the place, and the capsule plays it — which,
## with no model to animate yet, means it bobs.
func _check_he_runs() -> bool:
	var mirror := _avatar(_crowd_guest, 1)
	if _clock == 1:
		_stub_host.state = PlayerAvatar.State.RUNNING
		_low = 999.0
		_high = -999.0
		return false
	if _clock < WAIT:
		return false
	var model := mirror.get_node("Model") as Node3D
	_low = minf(_low, model.position.y)
	_high = maxf(_high, model.position.y)
	if _clock < WAIT + 60:
		return false
	_expect(mirror.sync_state == PlayerAvatar.State.RUNNING, "the run should have crossed the wire")
	_expect(_high - _low > 0.04, "and should show as a bob, which moved %.3f m" % (_high - _low))
	return _advance()


## And standing still is standing still: the bob stops with him.
func _check_he_stands_still() -> bool:
	var mirror := _avatar(_crowd_guest, 1)
	if _clock == 1:
		_stub_host.state = PlayerAvatar.State.IDLE
		return false
	if _clock < WAIT * 3:
		return false
	if _clock == WAIT * 3:
		_low = 999.0
		_high = -999.0
		return false
	var model := mirror.get_node("Model") as Node3D
	_low = minf(_low, model.position.y)
	_high = maxf(_high, model.position.y)
	if _clock < WAIT * 3 + 30:
		return false
	_expect(mirror.sync_state == PlayerAvatar.State.IDLE, "standing still should have crossed too")
	_expect(_high - _low < 0.01, "and nothing should be moving, which moved %.3f m" % (_high - _low))
	return _advance()


## The half that is not a state: he uses what is in his hands, and the arm goes
## out on everybody's screen. One click is one action, not one a frame.
func _check_an_action_crosses() -> bool:
	var mirror := _avatar(_crowd_guest, 1)
	if _clock == 1:
		_actions.clear()
		_nub_moved = 0.0
		_nub_rest = (mirror.get_node("Model/Front") as Node3D).position.z
		mirror.acted.connect(func(action: int) -> void: _actions.append(action))
		_stub_host.swing()
		return false
	_nub_moved = maxf(_nub_moved, absf((mirror.get_node("Model/Front") as Node3D).position.z - _nub_rest))
	if _clock < WAIT * 4:
		return false
	_expect(_actions.size() == 1, "one swing should cross once, and %d arrived" % _actions.size())
	_expect(not _actions.is_empty() and _actions[0] == PlayerAvatar.Action.SWING,
		"and should arrive as a swing")
	_expect(_nub_moved > 0.1, "the arm should have gone out, and it moved %.2f m" % _nub_moved)
	return _advance()


## A name that Steam sent late, or a peer that introduced himself while the map
## was still opening: it lands on the capsule that is already standing there.
func _check_a_late_name_lands() -> bool:
	var theirs := _avatar(_crowd_host, _guest_id)
	if _clock == 1:
		_expect(theirs.player_name == _lobby.UNKNOWN_NAME,
			"a peer who has not said who he is should read as \"...\"")
		_lobby.remember_identity(_guest_id, GUEST_STEAM_ID, "Verminator")
		return false
	if _clock < WAIT:
		return false
	_expect(theirs.player_name == "Verminator", "the name should have landed on the body already up")
	_expect((theirs.get_node("Name") as Label3D).text == "Verminator", "and be written over it")
	_expect(theirs.steam_id == GUEST_STEAM_ID, "and the Steam ID with it")
	return _advance()


## Somebody closes their game. The wire says so, and their capsule goes.
func _check_he_leaves() -> bool:
	if _clock == 1:
		_mp_guest.multiplayer_peer.close()
		return false
	if _crowd_host.count() > 1 and _clock < PATIENCE:
		return false
	_expect(_crowd_host.count() == 1, "only our own body should be left, and %d is" % _crowd_host.count())
	_expect(_avatar(_crowd_host, _guest_id) == null, "the one who left should be gone")
	_expect(_crowd_host.get_child_count() == 1, "and their node freed, not merely forgotten")
	return _advance()

## The map as it opens for one player on his own, with the real character in it
## and no wire at all: nobody is standing about, and nothing has gone up that
## would have to be taken down again.
func _check_a_solo_hunt() -> bool:
	if _clock == 1:
		_world = load("res://scenes/world.tscn").instantiate()
		root.add_child(_world)
		return false
	if _clock < WAIT * 4:
		return false
	var crowd := _world.get_node("Players") as Node3D
	_expect(crowd.count() == 0, "a solo hunt has nobody standing about, and %d is" % crowd.count())
	_expect(crowd.get_child_count() == 0, "and nothing hanging off the node")
	return _advance()


## And the real character answers the one question the avatar asks him. The
## states themselves are covered above with a stand-in; what is checked here is
## that `player.gd` reads its own body honestly — standing still is idle, and
## three metres of air is not.
func _check_the_character_answers() -> bool:
	var player := _world.get_node("Player") as CharacterBody3D
	if _clock == 1:
		_expect(player.animation_state() == PlayerAvatar.State.IDLE,
			"a player standing on the floor should read as idle")
		player.global_position += Vector3.UP * 3.0
		return false
	if _clock < WAIT:
		return false
	_expect(player.animation_state() == PlayerAvatar.State.AIRBORNE,
		"and a player in the air should read as airborne")
	return _advance()

# --- Plumbing --------------------------------------------------------------

func _avatar(crowd: Node3D, peer_id: int) -> PlayerAvatar:
	return crowd.avatar_of(peer_id)


func _expect(condition: bool, what: String) -> void:
	if condition:
		return
	print("FAIL: %s" % what)
	_failures += 1


func _advance() -> bool:
	_step += 1
	_clock = 0
	return false


func _finish() -> bool:
	if _mp_host != null and _mp_host.multiplayer_peer != null:
		_mp_host.multiplayer_peer.close()
	print("--- %d frames, %d failure(s) ---" % [_frames, _failures])
	return true
