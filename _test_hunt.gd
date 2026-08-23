extends SceneTree
## Hunt phase test bench (Card 13).
##
## Run with: godot --headless --script _test_hunt.gd
##
## Tests:
## 1. House scene loads in SURVEY and transitions to HUNT without reloading the scene.
## 2. Placed traps from SURVEY persist in Traps container.
## 3. Blackout sequence and transition to dark hunt lighting.
## 4. Rat hole visual highlights deactivated in HUNT.
## 5. Player flashlight available.
## 6. Attack weapons unbarred in HUNT, trap weapons have longer hunt cooldown.
## 7. Authoritative host spawns rats according to contract infestation in distant nests.
## 8. Eliminating all rats concludes HUNT phase and advances to RESULT.

const HOUSE_SCENE := "res://scenes/world.tscn"

const LOBBY := 0
const TRAVEL := 1
const SURVEY := 2
const HUNT := 3
const RESULT := 4

const ANA := 111
const BRUNO := 222
const WAIT := 8
const BLACKOUT_FRAMES := 65

var _session: Node
var _phase: Node
var _ready_mgr: Node
var _contract_mgr: Node

var _failures := 0
var _frames := 0
var _step := 0
var _clock := 0

var _house_node: Node


func _initialize() -> void:
	Engine.max_fps = 60

	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_ready_mgr = root.get_node_or_null("ReadyManager")
	_contract_mgr = root.get_node_or_null("ContractManager")


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_setup_survey()
		1: return _check_survey_initial_state()
		2: return _check_transition_to_hunt()
		3: return _check_blackout_and_lighting()
		4: return _check_hunt_environment_and_weapons()
		5: return _check_rat_spawning_and_nests()
		6: return _check_hunt_completion_to_result()
	return _finish()


func _check_setup_survey() -> bool:
	if _phase == null or _session == null or _contract_mgr == null:
		print("FAIL: Autoloads missing")
		return _finish()

	_session.reset()
	_session.register_player(ANA, "Ana", true)
	_session.register_player(BRUNO, "Bruno", false)

	_contract_mgr.sign("hallow_street")
	_phase.set_house(HOUSE_SCENE)
	_phase.go_to(SURVEY)
	return _advance()


func _check_survey_initial_state() -> bool:
	if _clock < WAIT:
		return false

	_house_node = current_scene
	_expect(_house_node != null, "house scene instantiated")
	_expect(_phase.current() == SURVEY, "starts in SURVEY phase")

	var rats_root: Node3D = _house_node.rats_root()
	_expect(rats_root != null, "house has Rats container node")
	_expect(_house_node.spawned_rat_count() == 0, "zero rats spawned during survey")

	# Place a trap to verify persistence across phase change
	var traps_root: Node3D = _house_node.traps_root()
	var test_trap := Node3D.new()
	test_trap.name = "SurveyPlacedTrap"
	traps_root.add_child(test_trap)
	test_trap.global_position = Vector3(2.0, 0.01, 3.0)
	_expect(_house_node.installed_trap_count() > 0, "trap placed in survey")

	# Check player flashlight
	var player: Node = _house_node.get_node_or_null("Player")
	_expect(player != null, "player in house")
	if player != null:
		var flashlight: Node = player.get_node_or_null("Head/Camera/Flashlight")
		_expect(flashlight != null, "player has Flashlight SpotLight3D")

	return _advance()


func _check_transition_to_hunt() -> bool:
	if _clock == 1:
		_house_node.set_meta("house_instance_id", _house_node.get_instance_id())
		_phase.go_to(HUNT)
		return false

	if _clock < WAIT:
		return false

	_expect(_phase.current() == HUNT, "phase transitioned to HUNT")
	_expect(current_scene == _house_node, "same house scene kept on screen")
	_expect(_house_node.get_meta("house_instance_id") == _house_node.get_instance_id(), "no scene reload occurred")
	_expect(_house_node.is_in_blackout(), "1-second blackout active immediately on transition")
	return _advance()


func _check_blackout_and_lighting() -> bool:
	# Wait for 1-second blackout duration to complete
	if _clock < BLACKOUT_FRAMES:
		return false

	_expect(not _house_node.is_in_blackout(), "blackout ended after 1 second")
	_expect(_house_node.is_hunt_lighting(), "dark hunt lighting applied")
	return _advance()


func _check_hunt_environment_and_weapons() -> bool:
	# Check persistent trap survival
	var traps_root: Node3D = _house_node.traps_root()
	var surviving_trap: Node3D = traps_root.get_node_or_null("SurveyPlacedTrap")
	_expect(surviving_trap != null, "trap placed during survey survived in place into hunt")
	if surviving_trap != null:
		_expect(surviving_trap.global_position.is_equal_approx(Vector3(2.0, 0.01, 3.0)), "trap position intact")

	# Check rat holes visual highlight extinguished
	var holes := get_nodes_in_group("rat_holes")
	var any_highlighted := false
	for h in holes:
		if h.has_method("is_highlighted") and h.is_highlighted():
			any_highlighted = true
	_expect(not any_highlighted, "rat hole visual highlights are off in hunt")

	# Check player attack weapons unbarred
	var player: Node = _house_node.get_node_or_null("Player")
	if player != null and player.get("inventory") != null:
		var inv: Node = player.inventory
		_expect(not inv.has_bars(), "weapons are unbarred in hunt phase")

		var mousetrap: Node = player.get_node_or_null("Head/Mousetrap")
		if mousetrap != null:
			_expect(mousetrap.get_cooldown() == mousetrap.hunt_cooldown, "trap weapon uses hunt_cooldown during HUNT")
			_expect(mousetrap.hunt_cooldown > mousetrap.cooldown, "hunt cooldown is longer than standard survey cooldown")

	return _advance()


func _check_rat_spawning_and_nests() -> bool:
	var spawned: int = _house_node.spawned_rat_count()
	var contract: Resource = _contract_mgr.current()
	var expected_count: int = contract.infestation if contract != null else 6
	_expect(spawned == expected_count, "host spawned %d rats according to contract infestation (found %d)" % [expected_count, spawned])

	var active: int = _house_node.active_rat_count()
	_expect(active == spawned, "all spawned rats are currently active/alive")

	# Verify rats spawned at distant nest points (Kitchen/Living burrows away from front door)
	var rats_root: Node3D = _house_node.rats_root()
	var front_door := Vector3(0.0, 0.0, 10.0)
	var all_distant := true
	for child in rats_root.get_children():
		var rat := child as Node3D
		if rat != null:
			var dist := rat.global_position.distance_to(front_door)
			if dist < 6.0:
				all_distant = false
	_expect(all_distant, "all rats spawned in nests distant from the front door")

	return _advance()


func _check_hunt_completion_to_result() -> bool:
	if _clock == 1:
		# Eliminate all rats to trigger hunt completion
		var rats_root: Node3D = _house_node.rats_root()
		for child in rats_root.get_children():
			var rat := child as Node3D
			if rat != null and rat.has_method("take_damage"):
				rat.take_damage(99)
		return false

	if _clock < WAIT:
		return false

	_expect(_house_node.active_rat_count() == 0, "all rats eliminated")
	_expect(_phase.current() == RESULT, "hunt automatically concluded and advanced to RESULT phase")
	return _advance()


func _expect(condition: bool, what: String) -> void:
	if condition:
		print("  ok   %s" % what)
		return
	print("FAIL: %s" % what)
	_failures += 1


func _advance() -> bool:
	_step += 1
	_clock = 0
	return false


func _finish() -> bool:
	print("--- %d frames, %d failure(s) ---" % [_frames, _failures])
	if _failures == 0:
		print("\nhunt phase bench: all good.")
	else:
		print("\nhunt phase bench: %d failed." % _failures)
	quit(1 if _failures > 0 else 0)
	return true
