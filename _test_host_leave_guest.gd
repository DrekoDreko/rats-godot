extends SceneTree
## The guest side of `_test_host_leave.gd`. It dials the host, stands the map up
## the way a welcomed client does, and then survives — or does not — the host
## walking out from under it. Whatever it manages to say is written to
## `user://guest_verdict.txt`, which the host reads. Silence is the failure.

const PORT := 42377
const MAP := "res://scenes/world.tscn"

var _step := 0
var _waited := 0.0
var _lines: Array[String] = []
var _errors := 0


func _initialize() -> void:
	Engine.max_fps = 60


func _say(line: String) -> void:
	_lines.append(line)
	print(line)


func _report() -> void:
	var file := FileAccess.open("user://guest_verdict.txt", FileAccess.WRITE)
	file.store_string("\n".join(_lines))
	file.close()


func _physics_process(delta: float) -> bool:
	var session := root.get_node_or_null("SessionManager")

	if _step == 0:
		var peer := ENetMultiplayerPeer.new()
		var err := peer.create_client("127.0.0.1", PORT)
		if err != OK:
			_say("FAIL: guest could not dial (%d)" % err)
			_report()
			return true
		root.multiplayer.multiplayer_peer = peer
		_step = 1
		return false

	if _step == 1:
		_waited += delta
		if root.multiplayer.get_unique_id() > 1 and root.multiplayer.get_peers().size() > 0:
			# Seat a crew of two, as a welcome packet would, and stand the map up.
			session.reset()
			session.register_player(111, "host", true)
			session.register_player(222, "guest", false)
			change_scene_to_file(MAP)
			_say("  ok   guest stood the map up")
			_waited = 0.0
			_step = 2
		elif _waited > 15.0:
			_say("FAIL: guest never reached the host")
			_report()
			return true
		return false

	if _step == 2:
		# Wait for the host to pull the wire, then see what is left standing.
		_waited += delta
		if root.multiplayer.multiplayer_peer == null \
				or root.multiplayer.multiplayer_peer.get_connection_status() \
					!= MultiplayerPeer.CONNECTION_CONNECTED:
			_say("  ok   guest noticed the host go")
			_waited = 0.0
			_step = 3
		elif _waited > 20.0:
			_say("FAIL: the host never went away")
			_report()
			return true
		return false

	if _step == 3:
		# Five more seconds of running with no wire under us. If the process is
		# going to die on the way home, it dies in here.
		_waited += delta
		if _waited < 5.0:
			return false
		var current := current_scene
		_say("  ok   still alive %0.1fs after the host left" % _waited)
		_say("  scene now: %s" % ("<none>" if current == null else current.scene_file_path))
		_report()
		return true

	return true
