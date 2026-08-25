extends SceneTree
## The guest half of `_test_ready_wire.gd`: connects, mirrors the crew, and then
## reports what its *own* SessionManager holds once the phase change has landed.

var _step := 0
var _waited := 0.0


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(delta: float) -> bool:
	var session := root.get_node_or_null("SessionManager")

	if _step == 0:
		var port := 42311
		var args := OS.get_cmdline_user_args()
		if args.size() > 0:
			port = int(args[0])
		var peer := ENetMultiplayerPeer.new()
		if peer.create_client("127.0.0.1", port) != OK:
			print("GUEST FAIL: could not dial")
			return true
		root.multiplayer.multiplayer_peer = peer
		_step = 1
		return false

	if _step == 1:
		_waited += delta
		if root.multiplayer.get_unique_id() <= 1 and _waited < 10.0:
			return false
		# The guest's own copy of the crew, raised green in the lobby exactly as
		# the real client does when its own boards are pressed.
		session.reset()
		session.register_player(111, "host", true)
		session.register_player(222, "guest", false)
		session.set_ready(111, true)
		session.set_ready(222, true)
		print("GUEST: green in the lobby, ready_count=%d" % session.ready_count())
		_waited = 0.0
		_step = 2
		return false

	_waited += delta
	if _waited < 4.0:
		return false

	# The moment of truth: did the host's phase change clear this machine's flags?
	var phase_name := Phase.name_of(session.phase)
	var count: int = session.ready_count()
	print("GUEST: phase=%s ready_count=%d" % [phase_name, count])
	var verdict := ""
	if phase_name == "travel" and count == 0:
		verdict = "GUEST PASSED: the flags were cleared here too"
	else:
		verdict = "GUEST FAILED: phase=%s ready_count=%d (wanted travel/0)" 			% [phase_name, count]
	print(verdict)
	# stdout of a process started by `OS.create_process` does not come back to
	# the parent's terminal, so the verdict is left where the host can read it.
	var file := FileAccess.open("user://guest_verdict.txt", FileAccess.WRITE)
	if file != null:
		file.store_string(verdict)
		file.close()
	return true
