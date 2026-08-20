extends SceneTree
## Inventory test bench: the belt of three slots, the swap with `1`, `2` and `3`,
## and the one rule that holds it — with a rat kicking in the hand nothing gets
## swapped.
##
## Run with: godot --headless --script _test_inventory.gd
##
## What is checked here is what only shows up once there is more than one slot:
## an empty slot is a player with nothing in his hands (the click finds nothing,
## he goes back to running), a busy weapon does not leave the hand, and a slot
## that does not exist is a swap that is turned down without taking the belt
## with it.
##
## The other two slots carry the traps bought at the computer, and nothing has
## been bought here: an empty box is exactly the empty slot this bench was
## written for, and the square on screen says so with a zero.

## Frames of slack between one step and the next.
const WAIT := 8
## Where the player grabs from: behind the rat, within reach of the hands.
const STATION := Vector3(0.0, 0.0, 1.6)
## Height of the aim point on the rat — the same one the weapon uses.
const TARGET_HEIGHT := 0.2

var _world: Node3D
var _player: CharacterBody3D
var _head: Node3D
var _hands: Node3D
var _inventory: Node
var _hotbar: Control
var _rat: Node3D
var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0

func _initialize() -> void:
	# Without a screen the loop would run at thousands of frames per second and
	# a whole animation would pass between two physics frames.
	Engine.max_fps = 60
	_world = load("res://scenes/world.tscn").instantiate()
	root.add_child(_world)
	_player = _world.get_node("Player")
	_head = _player.get_node("Head")
	_hands = _player.get_node("Head/Hands")
	_inventory = _player.get_node("Head/Inventory")
	_hotbar = _world.get_node("HUD/Hotbar")
	# The player is driven from here: no input and no gravity.
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)

func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_start()
		1: return _check_empty_slot()
		2: return _check_locked_while_busy()
		3: return _check_free_after_kill()
		4: return _check_out_of_range()
	return _finish()

# --- Steps -----------------------------------------------------------------

## The belt starts on the hands, with them out and the other two put away.
func _check_start() -> bool:
	if _clock < WAIT:
		return false
	# The hotbar only hooks up to the player's signals after one idle frame.
	if _player.weapon_changed.get_connections().is_empty():
		return false
	print("--- the belt has %d slots ---" % _inventory.slot_count())
	_expect(_inventory.slot_count() == 3, "the belt should have three slots")
	_expect(_inventory.index() == 0, "it should start on the first slot")
	_expect(_inventory.current() == _hands, "the hands should be the ones in hand")
	_expect(_hands.is_processing(), "the equipped hands should be processing")
	_expect(_hands.visible, "the equipped hands should be visible")
	_expect(_inventory.weapons().size() == 3, "three weapons should be on the belt")
	_check_hotbar(0, "at the start")
	return _advance()

## A slot with an empty box: the hands go away, the click finds nothing to do and
## the player goes back to running — nothing in his hands is nothing holding him.
func _check_empty_slot() -> bool:
	if _clock < WAIT:
		return false
	_expect(_inventory.equip(1), "it should be possible to swap to the empty slot")
	_expect(_inventory.index() == 1, "the belt should be on the second slot")
	_expect(_inventory.current() == null, "a weapon with an empty box holds nothing")
	_expect(not _hands.is_processing(), "the stowed hands should stop processing")
	_expect(not _hands.visible, "the stowed hands should leave the screen")
	_expect(not _inventory.is_busy(), "an empty slot is never busy")

	_rat = _closest()
	if _rat == null:
		print("FAIL: no loose rat for the empty-slot test")
		return _finish()
	_aim_at(_rat)
	_inventory.try_use()
	_expect(not _rat.is_captured(), "an empty slot should not grab the rat")
	_expect(not _inventory.is_busy(), "an empty slot should stay free after the click")

	_check_hotbar(1, "on the empty slot")

	_expect(_inventory.equip(0), "it should be possible to go back to the hands")
	_expect(_hands.is_processing(), "the hands should process again once out")
	_check_hotbar(0, "back on the hands")
	return _advance()

## With the rat in hand the belt locks: neither an empty slot nor the slot the
## player is already on takes the hands away from him.
func _check_locked_while_busy() -> bool:
	if _clock < WAIT:
		return false
	_aim_at(_rat)
	_inventory.try_use()
	if not _rat.is_captured():
		print("FAIL: the rat was not captured with the hands out")
		return _finish()
	print("--- rat in hand (%s) ---" % _rat.name)
	_expect(_inventory.is_busy(), "the belt should read as busy with the rat in hand")
	_expect(not _inventory.equip(1), "the swap should be refused with the rat in hand")
	_expect(not _inventory.equip(2), "no slot should be reachable with the rat in hand")
	_expect(_inventory.index() == 0, "the refused swap should leave the belt where it was")
	_expect(_inventory.current() == _hands, "the hands should stay in hand")
	_expect(_hands.is_processing(), "the busy hands should go on processing")
	_expect(not _hotbar.visible, "the hotbar should leave the screen with the rat in hand")
	return _advance()

## Strangled and stowed, the hands come free and the belt opens again.
func _check_free_after_kill() -> bool:
	for i in _hands.squeezes_to_kill + 2:
		_inventory.press_secondary()
	if _inventory.is_busy():
		print("FAIL: the rat did not die after %d squeezes" % (_hands.squeezes_to_kill + 2))
		return _finish()
	_expect(_inventory.equip(2), "the belt should open again once the hands are free")
	_expect(_inventory.index() == 2, "the belt should be on the third slot")
	_expect(_inventory.current() == null, "the third slot's box is empty too")
	return _advance()

## A slot that does not exist, and the one already out: refused, and the belt
## stays exactly where it was.
func _check_out_of_range() -> bool:
	if _clock < WAIT:
		return false
	_expect(not _inventory.equip(7), "a slot past the end should be refused")
	_expect(not _inventory.equip(-1), "a slot before the start should be refused")
	_expect(not _inventory.equip(2), "the slot already out should be refused")
	_expect(_inventory.index() == 2, "the refused swaps should leave the belt where it was")
	_expect(_hotbar.visible, "the hotbar should come back once the hands are empty")
	return _advance()

# --- Tools -----------------------------------------------------------------

func _expect(condition: bool, what: String) -> void:
	if condition:
		return
	print("FAIL: %s" % what)
	_failures += 1

## What the hotbar is showing: a square per slot, the weapon's name standing in
## for the icon it does not have yet, the count of a box in the corner of the
## ones that come out of a box, and the thicker frame around the one in hand.
func _check_hotbar(index: int, when: String) -> void:
	var expected := ["Hands", "Trap", "Glue"]
	# Nothing has been bought in this bench: both boxes read zero, and the hands
	# have no count at all.
	var counts := ["", "0", "0"]
	for i in expected.size():
		var slot: PanelContainer = _hotbar.get_node("Slot%d" % (i + 1))
		var label: Label = slot.get_node("Name")
		var count: Label = slot.get_node("Count")
		_expect(label.text == expected[i], "slot %d should read \"%s\" %s, and reads \"%s\"" % [
			i + 1, expected[i], when, label.text,
		])
		_expect(label.visible == (expected[i] != ""), "slot %d: an empty square shows nothing %s" % [
			i + 1, when,
		])
		_expect(count.text == counts[i], "slot %d should count \"%s\" %s, and counts \"%s\"" % [
			i + 1, counts[i], when, count.text,
		])
		_expect(is_equal_approx(slot.size.x, slot.size.y), "slot %d should be a square, and is %.0fx%.0f %s" % [
			i + 1, slot.size.x, slot.size.y, when,
		])
		var frame: StyleBoxFlat = slot.get_theme_stylebox("panel")
		var picked := frame.border_width_left > 1
		_expect(picked == (i == index), "slot %d should be %s %s" % [
			i + 1, "framed" if i == index else "plain", when,
		])

## Puts the player behind the rat and points body and head at it, so the rat
## falls inside the reach and the cone of the hands.
func _aim_at(rat: Node3D) -> void:
	var target := rat.global_position + Vector3.UP * TARGET_HEIGHT
	_player.global_position = rat.global_position + STATION
	_player.look_at(Vector3(target.x, _player.global_position.y, target.z), Vector3.UP)
	_player.rotation.x = 0.0
	_player.rotation.z = 0.0
	var eye := _head.global_position
	_head.rotation.x = atan2(target.y - eye.y, Vector2(target.x - eye.x, target.z - eye.z).length())

func _advance() -> bool:
	_step += 1
	_clock = 0
	return false

func _finish() -> bool:
	print("--- %d frames, %d failure(s) ---" % [_frames, _failures])
	return true

func _closest() -> Node3D:
	var best: Node3D = null
	var smallest := INF
	for node in get_nodes_in_group("rats"):
		var rat := node as Node3D
		var distance := _flat(rat.global_position, _player.global_position)
		if distance < smallest:
			smallest = distance
			best = rat
	return best

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
