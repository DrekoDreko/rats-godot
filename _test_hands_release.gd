extends SceneTree
## Release bench: the rat has to come loose when the player stops clicking.
##
## Run with: godot --headless --script _test_hands_release.gd
##
## Two machines in one process, the same trick as `_test_rat_sync.gd`: `/root/A`
## is the host and `/root/B` is the guest, each with its own `SceneMultiplayer`
## over ENet on the loopback. The guest carries a real `player.tscn`, so what
## does the grabbing and the letting go is the game's own `Hands`.
##
## The question is only one, and it is the bug this bench was written for: with
## the wire up and the guest holding a rat, do the messages he sends about it
## actually reach the host?
##
## They did not, and the reason was the reparenting. A guest's own catch used to
## be moved under his camera (`rat.gd: _draw_remote_capture`), which renames the
## node from `Rats/Rat_1` to `Player/Head/CapturePoint/Rat_1` — and a node's path
## is its address on the wire. Every `rpc_id` the guest sent about that rat was
## addressed to a path the host could not resolve, so the host dropped the packet
## and answered "Requested node was not found". What the player saw was a rat he
## could not let go of: he stopped clicking, his own hand opened, and the animal
## stayed in his fist for the rest of the hunt.
##
## What is checked, all of it from the guest's side:
##
## - He can take a rat the host is thinking for.
## - He lets go, and the host agrees the rat is loose.
## - He squeezes and strangles, and both reach the host.
##
## The host's own catch is the other half of the rule and is checked in
## `_test_rat_sync.gd`, which puts a rat in the host's hand and reads it back off
## the guest.

const PORT := 47137
const WAIT := 8
const PATIENCE := 600
const RAT_SCENE := "res://scenes/rat.tscn"
const PLAYER_SCENE := "res://scenes/player.tscn"
const AVATAR_SCENE := "res://scenes/player_avatar.tscn"

var _mp_host: SceneMultiplayer
var _mp_guest: SceneMultiplayer
var _guest_id := 0
var _rats_host: Node3D
var _rats_guest: Node3D
var _rat_host: Node3D
var _rat_guest: Node3D
var _rat2_host: Node3D
var _rat2_guest: Node3D
var _player: CharacterBody3D
var _hands: Node3D

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0

func _initialize() -> void:
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

	# The guest's own character, which is where the hands live.
	var player: CharacterBody3D = load(PLAYER_SCENE).instantiate()
	player.name = "Player"
	player.set_multiplayer_authority(_guest_id)
	root.get_node("B").add_child(player)
	player.global_position = Vector3(-4.0, 0.0, 6.5)
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	_player = player
	_hands = player.get_node("Head/Hands")

func _build_world(world_name: String, peer: MultiplayerPeer) -> SceneMultiplayer:
	var world := Node3D.new()
	world.name = world_name
	root.add_child(world)
	var api := SceneMultiplayer.new()
	api.multiplayer_peer = peer
	set_multiplayer(api, NodePath("/root/%s" % world_name))
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
		0: return _wire_up()
		1: return _put_a_rat_up()
		2: return _guest_grabs()
		3: return _guest_lets_go()
		4: return _guest_squeezes_and_kills()
	return _finish()

func _wire_up() -> bool:
	if _mp_guest.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		if _clock < PATIENCE:
			return false
		print("FAIL: the guest never reached the host")
		_failures += 1
		return _finish()
	print("--- host is peer 1, guest is peer %d ---" % _guest_id)
	return _next()

func _put_a_rat_up() -> bool:
	if _rat_host == null:
		var rat: Node3D = load(RAT_SCENE).instantiate()
		rat.name = "Rat_1"
		rat.set_multiplayer_authority(1)
		rat.position = Vector3(-4.0, 0.0, 5.0)
		_rats_host.add_child(rat)
		_rat_host = rat
		# The guest's body on the host's map: what his catch hangs off there.
		var avatar: PlayerAvatar = load(AVATAR_SCENE).instantiate()
		avatar.name = "Player%d" % _guest_id
		avatar.peer_id = _guest_id
		avatar.set_multiplayer_authority(_guest_id)
		root.get_node("A").add_child(avatar)
		avatar.global_position = Vector3(-4.0, 0.0, 6.5)
		_clock = 0
		return false
	_rat_guest = _rats_guest.get_node_or_null("Rat_1") as Node3D
	if _rat_guest == null:
		if _clock < PATIENCE:
			return false
		print("FAIL: the rat never reached the guest")
		_failures += 1
		return _finish()
	if _clock < WAIT:
		return false
	return _next()

func _guest_grabs() -> bool:
	if _clock == 1:
		# The grab the way the weapon does it, without needing the rat in the
		# sights: straight through `capture`.
		_rat_guest.capture(_player.get_node("Head/CapturePoint"))
		return false
	if _clock < WAIT * 4:
		return false
	if _rat_host.holder_peer() != _guest_id:
		print("FAIL: the host never gave the rat to the guest")
		_failures += 1
		return _finish()
	print("PASS: the guest is holding the rat")
	return _next()

func _guest_lets_go() -> bool:
	# Grabbed properly through the weapon this time, so the hands know about it.
	if _clock == 1:
		_rat_guest.escape()
		return false
	if _clock < WAIT * 4:
		return false
	if _rat_host.holder_peer() != 0:
		print("FAIL: the guest let go and the host still has him holding it (peer %d)"
				% _rat_host.holder_peer())
		_failures += 1
	else:
		print("PASS: the guest let go and the host agrees the rat is loose")
	return _next()

## The other two messages a guest sends about the rat in his fist. They went by
## the same address the escape did, so they broke the same way.
func _guest_squeezes_and_kills() -> bool:
	if _rat2_host == null:
		var rat2: Node3D = load(RAT_SCENE).instantiate()
		_rat2_host = rat2
		_rat2_host.name = "Rat_2"
		_rat2_host.set_multiplayer_authority(1)
		_rat2_host.position = Vector3(-4.0, 0.0, 5.0)
		_rats_host.add_child(_rat2_host)
		_clock = 0
		return false
	if _rat2_guest == null:
		_rat2_guest = _rats_guest.get_node_or_null("Rat_2") as Node3D
		if _rat2_guest == null:
			if _clock < PATIENCE:
				return false
			print("FAIL: the second rat never reached the guest")
			_failures += 1
			return _finish()
		_clock = 0
		return false
	if _clock == WAIT:
		_rat2_guest.capture(_player.get_node("Head/CapturePoint"))
		return false
	if _clock == WAIT * 3:
		_rat2_guest.squeeze()
		return false
	if _clock == WAIT * 4:
		_rat2_guest.die_in_hands()
		return false
	if _clock < WAIT * 8:
		return false
	if not _rat2_host.is_dead():
		print("FAIL: the guest strangled the rat and the host never heard of it")
		_failures += 1
	else:
		print("PASS: the guest's squeeze and kill both reached the host")
	return _next()

func _next() -> bool:
	_step += 1
	_clock = 0
	return false

func _finish() -> bool:
	print("--- %d frames, %d failure(s) ---" % [_frames, _failures])
	quit(1 if _failures > 0 else 0)
	return true
