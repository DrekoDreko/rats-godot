extends SceneTree
## Bench: "Sair da partida" on a solo run, where there is no lobby at all.
##
## The branch this covers is the one the fix rewrote. It used to be chosen by
## looking at where we had ended up *after* leaving; it is now chosen by asking
## `LobbyManager` whether there was ever a lobby, before. A solo player has none,
## so nobody moves him and the menu must make the scene change itself.

const MAP := "res://scenes/world.tscn"

var _failures := 0
var _step := 0
var _waited := 0.0


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(delta: float) -> bool:
	var session := root.get_node_or_null("SessionManager")
	var lobby := root.get_node_or_null("LobbyManager")

	if _step == 0:
		# A solo run: no wire, no lobby.
		if lobby.lobby_id != 0:
			print("FAIL: expected no lobby on a fresh run")
			_failures += 1
			return true
		session.reset()
		session.register_player(111, "solo", true)
		change_scene_to_file(MAP)
		_step = 1
		return false

	if _step == 1:
		_waited += delta
		if _waited < 2.0:
			return false
		var menu: Node = get_first_node_in_group("pause_menu")
		if menu == null:
			print("FAIL: no pause menu in the map")
			_failures += 1
			return true
		menu.open()
		menu.get_node("Center/Panel/Margin/Rows/Leave").pressed.emit()
		print("--- solo player pressed 'Sair da partida' ---")
		_waited = 0.0
		_step = 2
		return false

	if _step == 2:
		_waited += delta
		if _waited < 3.0:
			return false
		var path := "<none>" if current_scene == null else current_scene.scene_file_path
		if path == "res://scenes/lobby.tscn":
			print("  ok   solo player reached the lobby screen")
		else:
			print("  FAIL solo player ended up at %s" % path)
			_failures += 1
		if not paused:
			print("  ok   the tree is running again")
		else:
			print("  FAIL the tree was left paused")
			_failures += 1
		print("--- %d failure(s) ---" % _failures)
		return true

	return true
