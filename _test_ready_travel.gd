extends SceneTree
## Bench: the ready flags must survive a phase change on every machine, not only
## on the host's. Reproduces the LOBBY -> TRAVEL hand-off that left a guest's
## board green while the host read it as red.

var _session: Node
var _phase: Node
var _ready_mgr: Node
var _contracts: Node
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
	# Autoloads are in the tree but their names are not global in a --script
	# bench, so they are fetched by node name on the first frame.
	if _step == 0:
		_session = root.get_node_or_null("SessionManager")
		_phase = root.get_node_or_null("PhaseManager")
		_ready_mgr = root.get_node_or_null("ReadyManager")
		_contracts = root.get_node_or_null("ContractManager")
		if _session == null or _phase == null or _ready_mgr == null:
			print("FAIL: autoloads not found")
			return true
		_step = 1
		return false

	print("--- a crew of two, both ready in the lobby ---")
	_session.reset()
	_session.register_player(111, "host", true)
	_session.register_player(222, "guest", false)
	if _contracts != null and _contracts.count() > 0:
		_contracts.sign(_contracts.at(0).id)
	_check("van no longer held by the clipboard", _ready_mgr.blocked, false)
	_session.set_ready(111, true)
	_session.set_ready(222, true)
	_check("all_ready in lobby", _session.all_ready(), true)

	print("--- the van pulls off ---")
	# Solo/offline path: `_apply` runs locally, which is the same function the
	# rpc lands in on a client. If the reset is inside it, both flags drop.
	_phase.go_to(Phase.Type.TRAVEL)
	_check("phase", Phase.name_of(_session.phase), "travel")
	_check("host flag cleared", _session.is_ready(111), false)
	_check("guest flag cleared", _session.is_ready(222), false)
	_check("nobody ready on the road", _session.all_ready(), false)

	print("--- ready means something on the road ---")
	_check("station is active in travel", _ready_mgr.is_active(), true)

	print("--- one press each takes the van off the road ---")
	_ready_mgr.request_set(111, true)
	_check("host green after one press", _session.is_ready(111), true)
	_check("still on the road", Phase.name_of(_session.phase), "travel")
	_ready_mgr.request_set(222, true)
	_check("travel ended on the last man", Phase.name_of(_session.phase), "survey")
	_check("flags cleared again for survey", _session.ready_count(), 0)

	print("")
	if _failures == 0:
		print("ALL PASSED")
	else:
		print("%d FAILED" % _failures)
	return true
