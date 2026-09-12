extends SceneTree
## Exercise the local overlay and host-owned completion with a real ENet peer.

class TestPlayer extends Node:
	signal died()
	var dead := false
	func is_dead() -> bool:
		return dead

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var phase = root.get_node("PhaseManager")
	var session = root.get_node("SessionManager")
	session.register_player(root.get_node("SteamManager").get_steam_id(), "Test player", true)
	phase.set_process(false)
	_check(phase.scene_of(Phase.Type.RESULT) == phase.scene_of(Phase.Type.TRAVEL),
		"Results are displayed in the Van")
	phase.scenes[Phase.Type.RESULT] = ""
	session.phase = Phase.Type.HUNT
	var house := Node.new()
	root.add_child(house)
	var player := TestPlayer.new()
	player.add_to_group("player")
	house.add_child(player)
	for hud_name in ["HUD", "HUD_Phase"]:
		var hud := CanvasLayer.new()
		hud.name = hud_name
		house.add_child(hud)
	var screen = load("res://scenes/death_screen.tscn").instantiate()
	house.add_child(screen)
	await process_frame
	_check(not screen.visible, "Living players do not see the death screen")
	player.dead = true
	player.died.emit()
	_check(screen.visible, "Death opens the overlay")
	_check(not house.get_node("HUD").visible, "Death hides gameplay HUD")
	_check(not house.get_node("HUD_Phase").visible, "Death hides phase HUD")
	TranslationServer.set_locale("pt_BR")
	_check(tr("DEATH_TITLE") == "VOCÊ MORREU", "Portuguese death title")
	_check(tr("DEATH_WAITING") == "Aguardando a partida finalizar...", "Portuguese waiting message")
	_check(phase._all_players_dead(), "Solo death ends the team")
	phase.go_to(Phase.Type.RESULT)
	_check(session.phase == Phase.Type.HUNT, "Other completion triggers preserve the death delay")
	phase._check_team_death(2.9)
	_check(session.phase == Phase.Type.HUNT, "Solo death waits three seconds")

	# A connected player with no avatar yet must keep the hunt alive.
	var server := ENetMultiplayerPeer.new()
	_check(server.create_server(0) == OK, "Create test server")
	root.multiplayer.multiplayer_peer = server
	var client := ENetMultiplayerPeer.new()
	var client_api := SceneMultiplayer.new()
	client_api.root_path = root.get_path()
	_check(client.create_client("127.0.0.1", server.host.get_local_port()) == OK, "Create test client")
	client_api.multiplayer_peer = client
	for frame in 120:
		client_api.poll()
		if not root.multiplayer.get_peers().is_empty():
			break
		await process_frame
	_check(not root.multiplayer.get_peers().is_empty(), "Test peer connected")
	_check(not phase._all_players_dead(), "Missing remote avatar is not presumed dead")
	var avatar = load("res://scenes/player_avatar.tscn").instantiate()
	avatar.peer_id = client.get_unique_id()
	avatar.set_multiplayer_authority(avatar.peer_id)
	house.add_child(avatar)
	_check(not phase._all_players_dead(), "Living teammate keeps the match running")
	phase._check_team_death(10.0)
	_check(session.phase == Phase.Type.HUNT, "Dead local player waits for teammate")
	_check(phase._team_death_elapsed == 0.0, "Living teammate resets team death delay")
	avatar.sync_dead = true
	_check(phase._all_players_dead(), "Replicated remote death completes the team")
	avatar.queue_free()
	client.close()
	server.close()
	root.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	client_api.multiplayer_peer = null

	# The same result transition used by rats and timeout releases the overlay.
	phase._apply(Phase.Type.RESULT)
	_check(not screen.visible, "Match result closes the death screen")
	player.dead = false
	session.phase = Phase.Type.HUNT
	phase._on_timeout()
	_check(session.phase == Phase.Type.RESULT, "Hunt timeout still ends a living team's match")
	player.dead = true
	session.phase = Phase.Type.HUNT
	phase.scenes[Phase.Type.TRAVEL] = ""
	phase._check_team_death(3.0)
	_check(session.phase == Phase.Type.RESULT, "Team death settles through RESULT")
	_check(phase.returning_after_team_death, "Team death selects automatic return")
	await process_frame
	_check(session.phase == Phase.Type.RESULT, "Results wait for confirmation in the Van")
	phase.advance()
	_check(session.phase == Phase.Type.TRAVEL, "Confirming results starts the next map selection")
	_check(not phase.returning_after_team_death, "Van clears the death return flag")
	phase._stop_clock()
	house.queue_free()
	await process_frame
	print("Death screen: %d failures" % _failures)
	quit(1 if _failures else 0)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
