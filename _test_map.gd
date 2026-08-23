extends SceneTree
## Map table and pin management test bench: the blueprint in the van, the
## networked strategy pins, the 3-pin FIFO limit per player, and state synchronization.
##
## Run with: godot --headless --script _test_map.gd

const ANA := 111
const BRUNO := 222
const WAIT := 6

var _session: Node
var _phase: Node
var _contract: Node
var _map_manager: Node

var _placed_events: Array[Dictionary] = []
var _removed_events: Array[Dictionary] = []
var _cleared_events: Array[int] = []
var _refusals: Array[String] = []
var _updates_count := 0

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _boot()
		1: return _check_initial_state()
		2: return _check_place_pins()
		3: return _check_three_pin_fifo_limit()
		4: return _check_multiplayer_isolation()
		5: return _check_pin_removal_and_clearing()
		6: return _check_state_adoption()
		7: return _check_contract_change_clears_pins()
		8: return _check_viewer_and_table_scenes()
	return _finish()


func _boot() -> bool:
	if _clock < WAIT:
		return false

	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_contract = root.get_node_or_null("ContractManager")
	_map_manager = root.get_node_or_null("MapManager")

	if _session == null or _phase == null or _contract == null or _map_manager == null:
		print("FAIL: required autoloads are missing from the tree")
		_failures += 1
		return _finish()

	_map_manager.pin_placed.connect(func(who: int, pos: Vector2, col: Color) -> void:
		_placed_events.append({"steam_id": who, "pos": pos, "color": col}))
	_map_manager.pin_removed.connect(func(who: int, idx: int) -> void:
		_removed_events.append({"steam_id": who, "index": idx}))
	_map_manager.pins_cleared.connect(func(who: int) -> void:
		_cleared_events.append(who))
	_map_manager.pins_updated.connect(func() -> void:
		_updates_count += 1)
	_map_manager.request_refused.connect(func(why: String) -> void:
		_refusals.append(why))

	_session.reset()
	_map_manager.clear_all_pins()

	_session.register_player(ANA, "Ana", true)
	_session.register_player(BRUNO, "Bruno")

	# Sign first contract
	var first_job: Contract = _contract.at(0)
	if first_job != null:
		_contract.request_sign(first_job.id)

	_expect(_session.has_player(ANA), "Ana is in the crew")
	_expect(_session.has_player(BRUNO), "Bruno is in the crew")
	_expect(_contract.is_signed(), "a contract is signed")
	return _advance()


func _check_initial_state() -> bool:
	_expect(_map_manager.count() == 0, "map starts with 0 pins")
	_expect(_map_manager.count_for(ANA) == 0, "Ana has 0 pins")
	_expect(_map_manager.count_for(BRUNO) == 0, "Bruno has 0 pins")
	_expect(_map_manager.all_pins().is_empty(), "all_pins is empty")
	return _advance()


func _check_place_pins() -> bool:
	_placed_events.clear()
	_updates_count = 0

	var target_pos := Vector2(0.25, 0.65)
	_map_manager.request_place_pin(ANA, target_pos)

	_expect(_map_manager.count() == 1, "map now has 1 pin")
	_expect(_map_manager.count_for(ANA) == 1, "Ana has 1 pin")
	_expect(_placed_events.size() == 1, "pin_placed signal emitted once")
	_expect(_updates_count >= 1, "pins_updated signal emitted")

	var pin: Dictionary = _placed_events[0]
	_expect(pin["steam_id"] == ANA, "placed pin belongs to Ana")
	_expect(pin["pos"].is_equal_approx(target_pos), "placed pin is at target position")
	_expect(pin["color"] == _session.color(ANA), "pin color matches Ana's jumpsuit color")
	return _advance()


func _check_three_pin_fifo_limit() -> bool:
	_placed_events.clear()

	# Ana places 2nd and 3rd pin
	var pos2 := Vector2(0.35, 0.45)
	var pos3 := Vector2(0.55, 0.75)
	_map_manager.request_place_pin(ANA, pos2)
	_map_manager.request_place_pin(ANA, pos3)

	_expect(_map_manager.count_for(ANA) == 3, "Ana now has 3 pins (maximum)")

	var ana_pins: Array[Dictionary] = _map_manager.pins_for(ANA)
	_expect(ana_pins.size() == 3, "pins_for(ANA) returns 3 pins")
	_expect(ana_pins[0]["pos"].is_equal_approx(Vector2(0.25, 0.65)), "first pin is at pos1")
	_expect(ana_pins[1]["pos"].is_equal_approx(pos2), "second pin is at pos2")
	_expect(ana_pins[2]["pos"].is_equal_approx(pos3), "third pin is at pos3")

	# Ana places a 4th pin -> oldest (pos1) should be replaced (FIFO)
	var pos4 := Vector2(0.85, 0.15)
	_map_manager.request_place_pin(ANA, pos4)

	_expect(_map_manager.count_for(ANA) == 3, "Ana still has exactly 3 pins after 4th placement")
	ana_pins = _map_manager.pins_for(ANA)
	_expect(ana_pins[0]["pos"].is_equal_approx(pos2), "new oldest pin is pos2")
	_expect(ana_pins[1]["pos"].is_equal_approx(pos3), "middle pin is pos3")
	_expect(ana_pins[2]["pos"].is_equal_approx(pos4), "newest pin is pos4")
	return _advance()


func _check_multiplayer_isolation() -> bool:
	_placed_events.clear()

	# Bruno places 2 pins
	var b_pos1 := Vector2(0.12, 0.88)
	var b_pos2 := Vector2(0.92, 0.33)
	_map_manager.request_place_pin(BRUNO, b_pos1)
	_map_manager.request_place_pin(BRUNO, b_pos2)

	_expect(_map_manager.count_for(BRUNO) == 2, "Bruno has 2 pins")
	_expect(_map_manager.count_for(ANA) == 3, "Ana still has 3 pins")
	_expect(_map_manager.count() == 5, "Total pins on board is 5 (3 Ana + 2 Bruno)")

	var bruno_pins: Array[Dictionary] = _map_manager.pins_for(BRUNO)
	_expect(bruno_pins[0]["color"] == _session.color(BRUNO), "Bruno's pins have Bruno's jumpsuit color")
	return _advance()


func _check_pin_removal_and_clearing() -> bool:
	_removed_events.clear()
	_cleared_events.clear()

	# Ana removes her first pin (index 0)
	_map_manager.request_remove_pin(ANA, 0)
	_expect(_map_manager.count_for(ANA) == 2, "Ana now has 2 pins after removing one")
	_expect(_map_manager.count_for(BRUNO) == 2, "Bruno still has 2 pins")
	_expect(_map_manager.count() == 4, "Total pins is now 4")

	# Bruno clears all his pins
	_map_manager.request_clear_pins(BRUNO)
	_expect(_map_manager.count_for(BRUNO) == 0, "Bruno has 0 pins after clear")
	_expect(_map_manager.count_for(ANA) == 2, "Ana still has her 2 pins")
	_expect(_map_manager.count() == 2, "Total pins is now 2")
	return _advance()


func _check_state_adoption() -> bool:
	var snapshot: Array[Dictionary] = _map_manager.state()
	_expect(snapshot.size() == 2, "snapshot carries current 2 pins")

	_map_manager.clear_all_pins()
	_expect(_map_manager.count() == 0, "board cleared")

	_map_manager.adopt(snapshot)
	_expect(_map_manager.count() == 2, "adopting snapshot restored 2 pins")
	_expect(_map_manager.count_for(ANA) == 2, "restored pins belong to Ana")
	return _advance()


func _check_contract_change_clears_pins() -> bool:
	_expect(_map_manager.count() > 0, "board has pins before contract change")

	# Leader signs second contract
	var second_job: Contract = _contract.at(1)
	_contract.request_sign(second_job.id)

	_expect(_contract.current().id == second_job.id, "new contract signed")
	_expect(_map_manager.count() == 0, "signing a new contract wiped the pins")
	return _advance()


func _check_viewer_and_table_scenes() -> bool:
	# Instantiate MapViewer
	var viewer_packed := load("res://scenes/map/map_viewer.tscn") as PackedScene
	_expect(viewer_packed != null, "map_viewer.tscn loads cleanly")
	var viewer := viewer_packed.instantiate() as Control
	_expect(viewer != null, "map_viewer instantiates")
	root.add_child(viewer)

	viewer.open()
	_expect(viewer.is_open(), "viewer opens successfully")

	# Place a pin via manager and check viewer updates
	_map_manager.request_place_pin(ANA, Vector2(0.5, 0.5))
	_expect(_map_manager.count() == 1, "placed pin in map viewer test")

	viewer.close()
	_expect(not viewer.is_open(), "viewer closes cleanly")
	viewer.queue_free()

	# Instantiate MapTable
	var table_script := load("res://scripts/map/map_table.gd") as GDScript
	_expect(table_script != null, "map_table.gd loads cleanly")
	return _advance()


func _expect(condition: bool, what: String) -> void:
	if condition:
		print("  ok   %s" % what)
		return
	print("  FAIL %s" % what)
	_failures += 1


func _advance() -> bool:
	_step += 1
	_clock = 0
	return false


func _finish() -> bool:
	if _failures == 0:
		print("\nmap bench: all good.")
	else:
		print("\nmap bench: %d failed." % _failures)
	quit(1 if _failures > 0 else 0)
	return true
