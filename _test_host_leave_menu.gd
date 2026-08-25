extends SceneTree
## Bench: the **host** opens the pause menu in the map and presses "Sair da
## partida", with a guest standing in the same map.
##
## This is the road the player actually walks, and it is not the same road as a
## host process simply dying: the menu pauses the tree, the button calls
## `LobbyManager.leave_lobby()`, and the scene is changed out from under a map
## that still has the guest's avatars and synchronizers in it. The guest is a
## second Godot and reports whether it is still breathing afterwards.

const PORT := 42377
const MAP := "res://scenes/world.tscn"

var _failures := 0
var _step := 0
var _waited := 0.0
var _pid := -1
## The pause menu, kept from before the press so that what became of it can be
## asked afterwards.
var _menu: Node = null


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(delta: float) -> bool:
	var session := root.get_node_or_null("SessionManager")
	var lobby := root.get_node_or_null("LobbyManager")

	if _step == 0:
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(PORT, 4)
		if err != OK:
			print("FAIL: could not open the wire (%d)" % err)
			return true
		root.multiplayer.multiplayer_peer = peer
		# Make the lobby manager believe it is hosting a local wire, so that
		# `leave_lobby` walks its real body instead of returning at the door.
		lobby.lobby_id = 1
		lobby.is_local = true
		lobby.is_host = true
		lobby._peer = peer
		session.reset()
		session.register_player(111, "host", true)
		session.register_player(222, "guest", false)
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("user://guest_verdict.txt"))
		_pid = OS.create_process(OS.get_executable_path(), [
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://_test_host_leave_guest.gd",
		])
		print("--- host up, guest starting ---")
		_step = 1
		return false

	if _step == 1:
		_waited += delta
		if root.multiplayer.get_peers().size() > 0:
			change_scene_to_file(MAP)
			print("--- guest on the wire, host standing the map up ---")
			_waited = 0.0
			_step = 2
		elif _waited > 15.0:
			print("FAIL: the guest never dialled in")
			return true
		return false

	if _step == 2:
		_waited += delta
		if _waited < 3.0:
			return false
		var menu: Node = get_first_node_in_group("pause_menu")
		if menu == null:
			print("FAIL: no pause menu in the map")
			_failures += 1
			return true
		print("--- host opens the pause menu ---")
		menu.open()
		_waited = 0.0
		_step = 3
		return false

	if _step == 3:
		_waited += delta
		if _waited < 0.5:
			return false
		print("--- host presses 'Sair da partida' ---")
		var menu: Node = get_first_node_in_group("pause_menu")
		# Held on to across the press. The bug is that the button frees the node
		# it was pressed on — `NetworkGuard` changes the scene out from under it —
		# and whatever `_leave_match` does after that point it does with no tree
		# under it. `is_instance_valid` on a reference taken beforehand is the one
		# reading that tells the two apart from outside.
		_menu = menu
		menu.get_node("Center/Panel/Margin/Rows/Leave").pressed.emit()
		_waited = 0.0
		_step = 4
		return false

	if _step == 4:
		_waited += delta
		if _waited < 5.0:
			return false
		# The host is the machine that pressed the button, and it is the machine
		# the bug killed. Two things are asked of it: that it is still running at
		# all, and that it landed on the lobby screen rather than nowhere.
		var scene_path := "<none>" if current_scene == null else current_scene.scene_file_path
		if current_scene != null and scene_path == "res://scenes/lobby.tscn":
			print("  ok   host reached the lobby screen and is still running")
		else:
			print("  FAIL host ended up at %s" % scene_path)
			_failures += 1
		# The menu went with the scene that was torn down, which is what makes
		# the bug possible in the first place: anything `_leave_match` reads off
		# `self` after `leave_lobby()` is read off a freed node. The proof that it
		# no longer does is the engine's error stream — this bench prints
		# `Parameter "data.tree" is null` on the old code and nothing on the new —
		# so read the log as well as this verdict.
		if is_instance_valid(_menu):
			print("  FAIL the menu outlived the scene change")
			_failures += 1
		else:
			print("  ok   the menu went down with its scene")
		_waited = 0.0
		_step = 5
		return false

	if _step == 5:
		_waited += delta
		var verdict := FileAccess.open("user://guest_verdict.txt", FileAccess.READ)
		if verdict != null:
			print("--- what the guest says ---")
			print(verdict.get_as_text().strip_edges())
			verdict.close()
			return true
		if _waited > 25.0:
			print("FAIL: the guest never reported back (it probably died)")
			_failures += 1
			return true
		return false

	return true


func _finalize() -> void:
	if _pid > 0:
		OS.kill(_pid)
	print("--- %d failure(s) ---" % _failures)
