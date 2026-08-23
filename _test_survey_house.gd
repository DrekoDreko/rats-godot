extends SceneTree
## Survey phase and House scene test bench (Card 12).
##
## Run with: godot --headless --script _test_survey_house.gd
##
## Tests:
## 1. scenes/world.tscn loads and instantiates with all required components.
## 2. Front door spawn markers and HouseSpawns placement.
## 3. 60-second authoritative SURVEY timer and phase properties.
## 4. Attack weapon barring in SURVEY (denial sound/refusal signal), non-attack utilities allowed.
## 5. RatHole highlights active in SURVEY and deactivated in HUNT.
## 6. Trap placement into persistent Traps node.
## 7. Seamless transition SURVEY -> HUNT without scene reload: placed traps survive in place.
## 8. The blueprint is a van fixture: no map in the belt, and the van carries the table.

const HOUSE_SCENE := "res://scenes/world.tscn"

const LOBBY := 0
const TRAVEL := 1
const SURVEY := 2
const HUNT := 3
const RESULT := 4

const HOUSE_SCRIPT_PATH := "res://scripts/house/house.gd"
const SPAWNS_SCRIPT_PATH := "res://scripts/session/house_spawns.gd"
const RAT_HOLE_SCRIPT_PATH := "res://scripts/house/rat_hole.gd"
const MAP_WEAPON_SCRIPT_PATH := "res://scripts/weapons/map_weapon.gd"

const ANA := 111
const BRUNO := 222
const WAIT := 8

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
		0: return _check_setup_and_load_house()
		1: return _check_front_door_spawns()
		2: return _check_survey_timer_and_rules()
		3: return _check_survey_weapon_restrictions()
		4: return _check_rat_hole_highlights_in_survey()
		5: return _check_trap_placement_in_survey()
		6: return _check_map_is_van_only()
		7: return _check_transition_to_hunt_and_persistence()
	return _finish()


func _check_setup_and_load_house() -> bool:
	if _phase == null or _session == null or _contract_mgr == null:
		print("FAIL: Autoloads missing")
		return _finish()

	_session.reset()
	_session.register_player(ANA, "Ana", true)
	_session.register_player(BRUNO, "Bruno", false)

	# Ensure ContractManager signs a contract pointing to the world scene
	_contract_mgr.sign("hallow_street")
	_expect(_phase.scene_of(SURVEY) == HOUSE_SCENE, "survey scene is world.tscn")
	_expect(_phase.scene_of(HUNT) == HOUSE_SCENE, "hunt scene is world.tscn")

	# Transition to SURVEY phase
	_phase.go_to(SURVEY)
	return _advance()


func _check_front_door_spawns() -> bool:
	if _clock < WAIT:
		return false

	_house_node = current_scene
	_expect(_house_node != null, "house scene is instantiated and set as current_scene")
	_expect(_house_node.get_script() != null and _house_node.get_script().resource_path == HOUSE_SCRIPT_PATH,
		"house root has house.gd script attached")

	var spawns: Node = _house_node.get_node_or_null("Spawns")
	_expect(spawns != null, "house has HouseSpawns node")
	if spawns != null and spawns.has_method("count"):
		_expect(spawns.count() >= 4, "house has at least 4 front door spawn markers (found %d)" % spawns.count())
		var ana_spot: Vector3 = spawns.spot_of(ANA)
		var bruno_spot: Vector3 = spawns.spot_of(BRUNO)
		_expect(ana_spot != bruno_spot, "players get distinct spawn positions at the front door")

	var player: Node = _house_node.get_node_or_null("Player")
	_expect(player != null, "player exists in house scene")

	# Searched rather than addressed: the station rides the van now, and where
	# the van parks it is the van's business rather than this bench's.
	var ready_st: Node = _house_node.find_child("ReadyStation", true, false)
	_expect(ready_st != null, "ready station exists in house scene")

	var hud_phase: Node = _house_node.get_node_or_null("HUD_Phase")
	_expect(hud_phase != null, "HUD_Phase is instantiated in the world scene")

	return _advance()


func _check_survey_timer_and_rules() -> bool:
	_expect(_phase.current() == SURVEY, "currently in SURVEY phase")
	_expect(_phase.has_timer(), "SURVEY has an authoritative clock")
	_expect(_phase.seconds_left > 0.0 and _phase.seconds_left <= 60.0, "survey timer is counting down (60s)")
	return _advance()


func _check_survey_weapon_restrictions() -> bool:
	var player: Node = _house_node.get_node_or_null("Player")
	if player == null or player.get("inventory") == null:
		print("FAIL: player inventory not found")
		return _finish()

	var inv: Node = player.inventory

	# Test custom slot with an attack weapon vs non-attack
	var test_attack_weapon := Node3D.new()
	test_attack_weapon.set_script(load("res://scripts/weapons/weapon.gd"))
	test_attack_weapon.name = "TestBat"
	player.get_node("Head").add_child(test_attack_weapon)

	# Verify is_attack_weapon default and overrides
	_expect(test_attack_weapon.is_attack_weapon(), "standard weapons default to is_attack_weapon == true")

	var trap_weapon: Node = player.get_node("Head/Mousetrap")
	if trap_weapon != null:
		_expect(not trap_weapon.is_attack_weapon(), "traps are non-attack items")

	# Test barring attack weapons
	var new_slots: Array[NodePath] = inv.slots.duplicate()
	new_slots.append(test_attack_weapon.get_path())
	inv.slots = new_slots
	inv.bar_attack_weapons()

	var attack_slot_idx: int = inv.slot_count() - 1
	_expect(inv.is_barred(attack_slot_idx), "attack weapon slot is barred during survey")

	# Attempt to equip barred slot -> must emit refused signal and return false
	var refused_called := [false]
	var on_refused := func(_idx: int) -> void:
		refused_called[0] = true
	inv.refused.connect(on_refused)
	var equip_result: bool = inv.equip(attack_slot_idx)
	inv.refused.disconnect(on_refused)
	_expect(not equip_result, "equipping barred attack weapon returns false")
	_expect(refused_called[0], "refused signal is emitted when trying to equip barred weapon")

	# Verify non-attack slots (traps and map) are NOT barred
	for i in inv.slot_count() - 1:
		var w: Node = inv.weapon_in(i)
		if w != null and not w.is_attack_weapon():
			_expect(not inv.is_barred(i), "non-attack slot %d (%s) is allowed in survey" % [i, w.display_name])

	test_attack_weapon.queue_free()
	new_slots.remove_at(attack_slot_idx)
	inv.slots = new_slots
	return _advance()


func _check_rat_hole_highlights_in_survey() -> bool:
	var holes := get_nodes_in_group("rat_holes")
	_expect(holes.size() >= 3, "house has rat holes / escape routes (found %d)" % holes.size())

	var all_highlighted := true
	for node in holes:
		if node.has_method("is_highlighted") and not node.is_highlighted():
			all_highlighted = false
	_expect(all_highlighted, "all rat holes are highlighted during SURVEY phase")
	return _advance()


func _check_trap_placement_in_survey() -> bool:
	var house: Node = _house_node
	var traps_root: Node3D = house.traps_root()
	_expect(traps_root != null, "house has persistent Traps node")

	var initial_count: int = house.installed_trap_count()

	# Place a test trap in Traps root (simulating TrapWeapon placement)
	var test_trap := Node3D.new()
	test_trap.name = "PlacedMousetrap"
	traps_root.add_child(test_trap)
	test_trap.global_position = Vector3(1.5, 0.01, 2.5)

	_expect(house.installed_trap_count() == initial_count + 1, "trap successfully installed in Traps container")
	return _advance()


## The blueprint left the belt: it is studied at the van's table and nowhere else.
func _check_map_is_van_only() -> bool:
	var player: Node = _house_node.get_node_or_null("Player")
	_expect(player.get_node_or_null("Head/FoldedMap") == null,
		"no folded map hangs on the belt")

	var belt: Node = player.get_node_or_null("Head/Inventory")
	var carries_map := false
	for slot: NodePath in belt.slots:
		var item: Node = belt.get_node_or_null(slot)
		if item != null and item.get_script() != null 			and String(item.get_script().resource_path).ends_with("map_weapon.gd"):
			carries_map = true
	_expect(not carries_map, "no belt slot holds a map")

	# The table is where it went, and it is a fixture of the van in this scene.
	var table: Node = _house_node.get_node_or_null("Van/MapTable")
	_expect(table != null, "the van in the map carries the blueprint table")
	if table != null:
		_expect(table.is_in_group("map_station"), "the table is found by its group")
	return _advance()


func _check_transition_to_hunt_and_persistence() -> bool:
	if _clock == 1:
		# Mark house node with metadata to prove instance survival
		_house_node.set_meta("house_instance_id", _house_node.get_instance_id())

		# Advance to HUNT phase
		_phase.go_to(HUNT)
		return false

	if _clock < WAIT:
		return false

	_expect(_phase.current() == HUNT, "phase successfully transitioned to HUNT")
	_expect(current_scene == _house_node, "House scene was NOT reloaded on SURVEY -> HUNT transition")
	_expect(_house_node.has_meta("house_instance_id") and _house_node.get_meta("house_instance_id") == _house_node.get_instance_id(),
		"exact same house instance survived transition")

	# Verify installed trap survived exactly in place
	var house: Node = _house_node
	var traps_root: Node3D = house.traps_root()
	var surviving_trap: Node3D = traps_root.get_node_or_null("PlacedMousetrap")
	_expect(surviving_trap != null, "trap installed during SURVEY is still present in HUNT")
	if surviving_trap != null:
		_expect(surviving_trap.global_position.is_equal_approx(Vector3(1.5, 0.01, 2.5)),
			"trap position remained exactly where placed (%s)" % surviving_trap.global_position)

	# Verify rat hole visual highlights are now DEACTIVATED in HUNT
	var holes := get_nodes_in_group("rat_holes")
	var any_highlighted := false
	for node in holes:
		if node.has_method("is_highlighted") and node.is_highlighted():
			any_highlighted = true
	_expect(not any_highlighted, "rat hole visual highlights are removed in HUNT phase")

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
		print("\nsurvey house bench: all good.")
	else:
		print("\nsurvey house bench: %d failed." % _failures)
	quit(1 if _failures > 0 else 0)
	return true
