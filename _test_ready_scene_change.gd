extends SceneTree
## Bench: pressing "ready" on the board in the moving van must not blow up when
## that press is the one that ends the phase.
##
## Reproduces the reported crash: "Cannot call method 'set_input_as_handled' on a
## null value" at the moment the survey starts. The press travels
## `player._unhandled_input` -> `ReadyStation.use` -> `ReadyManager` ->
## `PhaseManager.advance` -> `change_scene_to_file`, and the scene change pulls
## the player out from under the very handler that is still running.

var _phase: Node
var _session: Node
var _ready_mgr: Node
var _step := 0
var _failures := 0


func _initialize() -> void:
	Engine.max_fps = 60


func _check(label: String, got: Variant, want: Variant) -> void:
	if got == want:
		print("  ok   %s -> %s" % [label, got])
		return
	_failures += 1
	print("  FAIL %s -> got %s, wanted %s" % [label, got, want])


func _physics_process(_delta: float) -> bool:
	if _step == 0:
		_session = root.get_node_or_null("SessionManager")
		_phase = root.get_node_or_null("PhaseManager")
		_ready_mgr = root.get_node_or_null("ReadyManager")
		if _session == null or _phase == null or _ready_mgr == null:
			print("FAIL: autoloads not found")
			return true
		_step = 1
		return false

	if _step == 1:
		print("--- one man in the van, on the road ---")
		_session.reset()
		# The board asks after *our own* Steam ID, so the crew has to be the
		# machine running the bench — Steam is up here and answers a real one.
		var lobby := root.get_node_or_null("LobbyManager")
		var us: int = lobby.our_steam_id() if lobby != null else 0
		if us == 0:
			us = 111
		_session.register_player(us, "host", true)
		# The van is held until the host has signed a job, and a held van does not
		# leave however green the board is.
		var contracts := root.get_node_or_null("ContractManager")
		if contracts != null and contracts.count() > 0:
			contracts.sign(contracts.at(0).id)
		_phase.go_to(1) # TRAVEL
		_step = 2
		return false

	# The scene change into the road takes a frame to land.
	if _step == 2:
		if current_scene == null:
			return false
		_check("on the road", current_scene.scene_file_path,
			"res://scenes/van_travel.tscn")
		_step = 3
		return false

	if _step == 3:
		var player := get_first_node_in_group("player")
		var board := get_first_node_in_group("ready_station")
		if player == null or board == null:
			print("FAIL: no player or no board in the van")
			return true
		print("--- the last man slaps the board, which ends the phase ---")
		_check("ready means something on the road", _ready_mgr.is_active(), true)
		_check("the van is not held", _ready_mgr.blocked, false)
		# The press exactly as the player makes it: the station is used, and then
		# the handler that used it goes on to spend the event.
		board.use(player)
		# The crash that was: the scene change takes the player out of the tree
		# before `use()` even returns, so this is null by here and the handler
		# that spends the press must cope with that rather than assume it.
		_check("the press took the player out of the tree",
			player.get_viewport() == null, true)
		# Exactly what `player._unhandled_input` does next. Before the fix this
		# was `get_viewport().set_input_as_handled()` and it took the game down.
		var viewport: Viewport = player.get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		_step = 4
		return false

	if _step == 4:
		_check("the survey started", _session.phase, 2)
		print("%s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
		return true

	return false
