extends SceneTree
## Bench: two real machines on a real wire.
##
## The offline bench cannot see this bug at all — with no peer, `go_to` and
## `_apply` run on the same machine, so a reset done in either place looks the
## same. What broke on the road only exists when the host's copy of the crew and
## the guest's are two separate dictionaries, so this runs a second Godot as the
## guest and asks the guest's own `SessionManager` what it thinks.

const PORT := 42311

var _failures := 0
var _step := 0
var _waited := 0.0
var _guest: OS
var _pid := -1


func _initialize() -> void:
	Engine.max_fps = 60


func _check(label: String, got: Variant, want: Variant) -> void:
	if got == want:
		print("  ok   %s -> %s" % [label, got])
		return
	_failures += 1
	print("  FAIL %s -> got %s, wanted %s" % [label, got, want])


func _physics_process(delta: float) -> bool:
	var session := root.get_node_or_null("SessionManager")
	var phase := root.get_node_or_null("PhaseManager")

	if _step == 0:
		# Stand the host up on a real ENet peer.
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_server(PORT, 4)
		if err != OK:
			print("FAIL: could not open the wire (%d)" % err)
			return true
		root.multiplayer.multiplayer_peer = peer
		session.reset()
		session.register_player(111, "host", true)
		session.register_player(222, "guest", false)
		# Both green in the lobby, on the host's copy.
		session.set_ready(111, true)
		session.set_ready(222, true)
		print("--- host: crew of two, both green in the lobby ---")
		_check("host says all_ready", session.all_ready(), true)
		_step = 1
		return false

	if _step == 1:
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("user://guest_verdict.txt"))
		# The guest connects and mirrors the same crew, then reports what its own
		# SessionManager holds after the phase change lands.
		_pid = OS.create_process(OS.get_executable_path(), [
			"--headless", "--path", ProjectSettings.globalize_path("res://"),
			"--script", "res://_test_ready_wire_guest.gd", "--", str(PORT)])
		if _pid <= 0:
			print("FAIL: could not start the guest")
			return true
		_step = 2
		return false

	if _step == 2:
		_waited += delta
		if root.multiplayer.get_peers().size() == 0:
			if _waited > 10.0:
				print("FAIL: the guest never connected")
				return true
			return false
		print("--- the guest is on the wire ---")
		_waited = 0.0
		_step = 3
		return false

	if _step == 3:
		# Give the guest a moment to raise its own flags locally, then pull off.
		_waited += delta
		if _waited < 1.0:
			return false
		print("--- the van pulls off (host calls go_to) ---")
		phase.go_to(Phase.Type.TRAVEL)
		_waited = 0.0
		_step = 4
		return false

	if _step == 4:
		_waited += delta
		if _waited < 2.0:
			return false
		# The guest prints its own verdict; the host checks its own side.
		_check("host: phase", Phase.name_of(session.phase), "travel")
		_check("host: flags cleared", session.ready_count(), 0)
		print("--- (the guest's own verdict is printed by its process) ---")
		_waited = 0.0
		_step = 5
		return false

	_waited += delta
	if _waited < 3.0:
		return false
	if _pid > 0:
		OS.kill(_pid)
	var file := FileAccess.open("user://guest_verdict.txt", FileAccess.READ)
	if file == null:
		_failures += 1
		print("  FAIL the guest left no verdict")
	else:
		var verdict := file.get_as_text().strip_edges()
		file.close()
		print("  %s" % verdict)
		if not verdict.begins_with("GUEST PASSED"):
			_failures += 1
	print("")
	if _failures == 0:
		print("HOST SIDE PASSED")
	else:
		print("%d FAILED on the host" % _failures)
	return true
