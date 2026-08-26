extends SceneTree
## Belt test bench: which loop a thing hangs from, and who decides it.
##
## Run with: godot --headless --script _test_belt.gd
##
## The belt is three empty loops and nothing else (`slot_capacity`). No loop
## belongs to any one item: what hangs from each is whatever the crew bought,
## in the order they bought it. This bench buys backwards — the glue first, the
## traps second — and the belt has to read the same way round, which is the
## whole of what it would fail to do if any loop were dressed in the scene.
##
## It also covers the two edges that come with a belt filled at runtime: the
## last unit of a thing being spent gives its loop back, and a thing picked up
## again takes whichever loop is free by then.
##
## Nothing is bought at the shelf here. The bag is credited straight
## (`Stock.add`), because what is under test is the belt reading the bag and not
## the money that filled it — that is `_test_van_shop.gd`.

## Frames of slack between one step and the next.
const WAIT := 4
## What the belt reads while the hands are out (`Inventory.HANDS_INDEX`). Copied
## rather than read off the class, the same way `_test_inventory.gd` copies it:
## naming `Inventory` from a bench drags its script into the compile that
## happens before the autoloads exist.
const HANDS_INDEX := -1

## The two things the player scene has a weapon dressed for, and the node each
## of them hangs on.
const GLUE_ID := "rat_glue"
const GLUE_NODE := "RatGlue"
const TRAP_ID := "mousetrap"
const TRAP_NODE := "Mousetrap"

var _world: Node3D
var _player: CharacterBody3D
var _inventory: Node
## The autoloads. In a bench run with `--script` their global names do not exist
## yet, so they are picked up by node name instead.
var _stock: Node
var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0

func _initialize() -> void:
	Engine.max_fps = 60
	_stock = root.get_node("Stock")
	_stock.reset()
	_world = load("res://scenes/world.tscn").instantiate()
	root.add_child(_world)
	_player = _world.get_node("Player")
	_inventory = _player.get_node("Head/Inventory")
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)

func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_empty_belt()
		1: return _check_first_purchase()
		2: return _check_second_purchase()
		3: return _check_spent_gives_the_loop_back()
		4: return _check_bought_again()
	return _finish()

# --- Steps -----------------------------------------------------------------

## A van nobody has bought anything from: three loops, all of them empty.
func _check_empty_belt() -> bool:
	if _clock < WAIT:
		return false
	print("--- the belt has %d loops ---" % _inventory.slot_count())
	_expect(_inventory.slot_count() == 3, "the belt should have three loops")
	for i in _inventory.slot_count():
		_expect(_inventory.weapon_in(i) == null, "loop %d should hang nothing" % (i + 1))
	_expect(_inventory.hands_out(), "the shift should start on the hands")
	_expect(_inventory.index() == HANDS_INDEX, "the hands are on no loop")
	return _advance()

## The first thing bought takes the first loop, whatever the thing is. Here it
## is the glue, which is second on the shelf and used to be second on the belt.
func _check_first_purchase() -> bool:
	if _clock < WAIT:
		return false
	_stock.add(GLUE_ID, 2)
	_expect(_name_on(0) == GLUE_NODE, "the first purchase should take loop 1, and loop 1 has \"%s\"" % _name_on(0))
	_expect(_inventory.weapon_in(1) == null, "loop 2 should still hang nothing")
	_expect(_inventory.weapon_in(2) == null, "loop 3 should still hang nothing")
	return _advance()

## The second takes the second, and the first stays where it is.
func _check_second_purchase() -> bool:
	if _clock < WAIT:
		return false
	_stock.add(TRAP_ID, 3)
	_expect(_name_on(0) == GLUE_NODE, "the glue should not move off loop 1")
	_expect(_name_on(1) == TRAP_NODE, "the traps should take loop 2, and loop 2 has \"%s\"" % _name_on(1))
	_stock.add(TRAP_ID, 3)
	_expect(_name_on(1) == TRAP_NODE, "a second box of the same thing takes no second loop")
	_expect(_inventory.weapon_in(2) == null, "loop 3 should still hang nothing")
	return _advance()

## Spending the last unit gives the loop back, so that the next thing bought has
## somewhere to go.
func _check_spent_gives_the_loop_back() -> bool:
	if _clock < WAIT:
		return false
	while _stock.count(GLUE_ID) > 0:
		_stock.spend_one(GLUE_ID)
	_expect(_inventory.weapon_in(0) == null, "the emptied box should give loop 1 back")
	_expect(_name_on(1) == TRAP_NODE, "the traps should stay on loop 2")
	return _advance()

## And a thing that comes back — a bent trap off the floor, a box bought again —
## takes whichever loop is free by then.
func _check_bought_again() -> bool:
	if _clock < WAIT:
		return false
	_stock.add(GLUE_ID, 1)
	_expect(_name_on(0) == GLUE_NODE, "the glue should hang again on the free loop")
	_expect(_name_on(1) == TRAP_NODE, "the traps should still be on loop 2")
	return _advance()

# --- Tools -----------------------------------------------------------------

## The name of the weapon on a loop, or "" for an empty one — what the assertion
## messages read, since a node is no use in a printed line.
func _name_on(slot: int) -> String:
	var weapon: Node = _inventory.weapon_in(slot)
	return "" if weapon == null else String(weapon.name)

func _expect(condition: bool, what: String) -> void:
	if condition:
		return
	print("FAIL: %s" % what)
	_failures += 1

func _advance() -> bool:
	_step += 1
	_clock = 0
	return false

func _finish() -> bool:
	print("--- %d frames, %d failure(s) ---" % [_frames, _failures])
	return true
