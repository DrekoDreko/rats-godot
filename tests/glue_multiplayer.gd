extends SceneTree
## Two real ENet peers in one tree, with independent multiplayer roots.

class AvatarRegistry extends Node:
	var bodies: Dictionary = {}
	func avatar_of(peer: int) -> Node3D: return bodies.get(peer)

var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		_failures += 1

func _pump(seconds := 0.15) -> void:
	await create_timer(seconds).timeout

func _run() -> void:
	var fixtures: Script = load("res://tests/glue_trap.gd")
	var host_root := Node3D.new()
	host_root.name = "Host"
	root.add_child(host_root)
	var guest_root := Node3D.new()
	guest_root.name = "Guest"
	root.add_child(guest_root)
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	var port := 24000 + int(Time.get_ticks_msec() % 10000)
	if server.create_server(port, 2) != OK or client.create_client("127.0.0.1", port) != OK:
		push_error("Cannot create loopback ENet peers")
		quit(1)
		return
	var host_api := SceneMultiplayer.new()
	var guest_api := SceneMultiplayer.new()
	set_multiplayer(host_api, host_root.get_path())
	set_multiplayer(guest_api, guest_root.get_path())
	host_api.multiplayer_peer = server
	guest_api.multiplayer_peer = client
	await _pump(0.3)
	var guest_id := client.get_unique_id()
	_check(host_api.get_peers().has(guest_id), "ENet peers connect")
	var scene: PackedScene = load("res://scenes/traps/glue_trap.tscn")
	var host = scene.instantiate()
	var guest = scene.instantiate()
	host.name = "Glue"
	guest.name = "Glue"
	host_root.add_child(host)
	guest_root.add_child(guest)
	host.set_physics_process(false)
	guest.set_physics_process(false)
	var local_player = fixtures.PlayerStub.new()
	local_player.add_to_group("player")
	host_root.add_child(local_player)
	var remote_player = fixtures.PlayerStub.new()
	host_root.add_child(remote_player)
	var registry := AvatarRegistry.new()
	registry.add_to_group("player_avatars_root")
	registry.bodies[guest_id] = remote_player
	host_root.add_child(registry)
	for branch: Node in [host_root, guest_root]:
		var rat = fixtures.RatStub.new()
		rat.name = "Rat"
		rat.add_to_group("rats")
		branch.add_child(rat)
	host._on_body_entered(host_root.get_node("Rat"))
	host._physics_process(0.0)
	await _pump()
	_check(host._players.size() == 2 and host.remaining == 20.0, "Two players each consume ten seconds")
	_check(guest._players.size() == 2 and guest.remaining == host.remaining, "Guest receives player capture and lifetime")
	_check(guest_root.get_node("Rat").is_pinned(), "Rat capture reaches guest")
	# Sender identity controls whose progress changes.
	for index in 4:
		host._physics_process(0.2)
		guest.press_escape()
		await _pump(0.06)
	_check(host._players[1].progress == 0.0 and host._players[guest_id].progress == 4.0,
		"Guest presses affect only the sender")
	host._physics_process(2.35)
	await _pump()
	_check(guest._players[guest_id].progress == 0.0, "Host decay reaches guest")
	for index in 6:
		host._physics_process(0.2)
		guest.press_escape()
		await _pump(0.06)
	_check(not host._players.has(guest_id) and host._players.has(1), "Guest escapes independently")
	_check(not guest._players.has(guest_id), "Guest receives escape confirmation")
	# A client cannot overwrite authoritative lifetime through the state RPC.
	print("Expected rejection follows: guest attempting an authority-only RPC")
	guest._receive_state.rpc_id(1, 40.0, {}, {})
	await _pump()
	_check(host.remaining < 20.0 and host._players.has(1), "Host rejects client state mutation")
	host.remaining = 0.01
	host._physics_process(0.02)
	await _pump(0.1)
	_check(guest._players.is_empty() and not guest_root.get_node("Rat").is_pinned(), "Expiration releases guest occupants")
	# Close transport before fixture teardown; production despawn uses its spawner.
	server.close()
	client.close()
	host_root.queue_free()
	guest_root.queue_free()
	await process_frame
	await process_frame
	if _failures == 0:
		print("OK: ENet glue captures, simultaneous wear, sender ownership, decay, escape and expiration")
	quit(_failures)
