extends SceneTree
## Shop test bench: the computer in the back of the van, the money that leaves
## the wallet and the traps that land on the belt.
##
## Run with: godot --headless --script _test_shop.gd
##
## What is checked here is the whole round trip of a purchase: a wallet that
## cannot pay buys nothing and the button says so, a wallet that can pay hands
## the units over, the square that was blank on the belt fills up on the spot —
## name and count at once, because a weapon nobody owns has neither — and using
## the last one empties it again. The screen itself is
## checked where it counts — that it takes the player out of the map while it is
## up, and gives him back when it closes.

## Frames of slack between one step and the next.
const WAIT := 8
## What the mousetrap costs, and how many it hands over. It is read off the
## resource so the bench does not go stale when the price moves.
const ITEM_PATH := "res://resources/store/mousetrap.tres"
## Which loop of the belt the mousetrap hangs from. The hands are on none of
## them, so the first slot is the first thing there is to buy.
const TRAP_SLOT := 0
## Where the player stands to actually put a trap down. It is the map's own
## starting point, which is open floor by construction.
const FLOOR_STATION := Vector3(0.0, 0.1, 4.0)
## How far down the head is tipped to aim at the floor in front of him.
const LOOK_DOWN := -0.9

var _world: Node3D
var _player: CharacterBody3D
var _head: Node3D
var _inventory: Node
var _hotbar: Control
var _shop: Control
var _computer: Node3D
var _trap: Node3D
## The autoloads. In a bench run with `--script` their global names do not exist
## yet — the MainLoop script is compiled before they enter the tree — so they are
## picked up by node name instead.
var _wallet: Node
var _stock: Node
var _item: Resource
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
	_inventory = _player.get_node("Head/Inventory")
	_trap = _player.get_node("Head/Mousetrap")
	_hotbar = _world.get_node("HUD/Hotbar")
	_shop = _world.get_node("HUD/Shop")
	_computer = _world.get_node("van/ShopComputer")
	_wallet = root.get_node_or_null("Wallet")
	_stock = root.get_node_or_null("Stock")
	_item = load(ITEM_PATH)
	# The player is driven from here: no input and no gravity.
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	# The cadence of the weapon is not what this bench is about, and at sixty
	# frames a second three uses would cost two seconds of waiting.
	_trap.cooldown = 0.0

func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_start()
		1: return _check_broke()
		2: return _check_opens()
		3: return _check_buys()
		4: return _check_reaches_the_belt()
		5: return _check_runs_out()
		6: return _check_closes()
	return _finish()

# --- Steps -----------------------------------------------------------------

## Nothing bought yet: the shop is off screen, the wallet is empty and the
## trap's square is as blank as the two beside it.
func _check_start() -> bool:
	if _clock < WAIT:
		return false
	# The shop only hooks up to the computer after one idle frame.
	if _computer.used.get_connections().is_empty():
		return false
	if _wallet == null or _stock == null:
		print("FAIL: the autoloads are not in the tree")
		return _finish()
	_wallet.reset()
	_stock.reset()
	print("--- the shelf has %d item(s) ---" % _computer.catalogue.size())
	_expect(_computer.catalogue.size() == 2, "the computer should sell two things")
	_expect(not _shop.visible, "the shop should start off screen")
	_expect(not _player.is_ui_open(), "the player should start in the map")
	_expect(_stock.count(_item.id) == 0, "the shift should start with an empty box")
	_expect(_inventory.equip(TRAP_SLOT), "the trap's slot should be reachable")
	_expect(_inventory.current() == null, "a weapon nobody bought holds nothing")
	_expect(_name_in(TRAP_SLOT) == "", "an unbought square should say nothing, and says \"%s\"" % _name_in(TRAP_SLOT))
	_expect(_count_in(TRAP_SLOT) == "", "an unbought square should count nothing, and counts \"%s\"" % _count_in(TRAP_SLOT))
	_expect(_inventory.equip_hands(), "Q should bring the hands back")
	return _advance()

## A wallet that cannot pay buys nothing, and it is turned down before the money
## is touched.
func _check_broke() -> bool:
	_expect(not _wallet.spend(_item.price), "an empty wallet should not pay")
	var money: int = _wallet.money
	_expect(money == 0, "a refused purchase should leave the wallet alone")
	_expect(_buy_button().disabled, "the button should be dead with no money for it")
	# Enough rats to pay for one box, and a little over.
	var species: Resource = load("res://resources/species/common_rat.tres")
	while _wallet.money < _item.price:
		_wallet.collect(species, 0)
	print("--- $%d earned, the box costs $%d ---" % [_wallet.money, _item.price])
	_expect(not _buy_button().disabled, "the button should come alive with the money in")
	return _advance()

## Using the computer opens the screen and takes the player out of the map.
func _check_opens() -> bool:
	_computer.use(_player)
	_expect(_shop.visible, "the computer should open the shop")
	_expect(_player.is_ui_open(), "the shop should take the player out of the map")
	_expect(not _hotbar.visible, "the belt has nothing to say while the shop is up")
	return _advance()

## The purchase: the price leaves the wallet and the units land in the stock.
func _check_buys() -> bool:
	var before: int = _wallet.money
	_buy_button().pressed.emit()
	var price: int = _item.price
	var amount: int = _item.amount
	_expect(_wallet.money == before - price, "the price should leave the wallet")
	_expect(_stock.count(_item.id) == amount, "the units should land in the stock")
	return _advance()

## The square that was blank a moment ago now has the weapon in it: its name,
## and what is left in the box in the corner.
func _check_reaches_the_belt() -> bool:
	if _clock < WAIT:
		return false
	_expect(_inventory.equip(TRAP_SLOT), "the trap's slot should still be reachable")
	_expect(_inventory.current() == _trap, "the bought trap should be in hand")
	_expect(_trap.available(), "a full box is a weapon that can be taken out")
	_expect(_name_in(TRAP_SLOT) == _trap.display_name, "the square should read \"%s\", and reads \"%s\"" % [
		_trap.display_name, _name_in(TRAP_SLOT),
	])
	_expect(_count_in(TRAP_SLOT) == str(_item.amount), "the square should count %d, and counts \"%s\"" % [
		_item.amount, _count_in(TRAP_SLOT),
	])
	return _advance()

## Every use takes one out, and the last one takes the weapon with it: the
## square goes blank again without anybody swapping anything.
func _check_runs_out() -> bool:
	if _clock < WAIT:
		return false
	# A trap is put down on the *floor*, and a click with nowhere to put one
	# spends nothing (`scripts/weapons/mousetrap_weapon.gd`). The player is
	# standing at the computer with a desk in front of him, so he is moved onto
	# open floor and made to look down at it before the box is emptied.
	_player.global_position = FLOOR_STATION
	_player.rotation = Vector3.ZERO
	_head.rotation.x = LOOK_DOWN
	var amount: int = _item.amount
	for i in amount:
		_inventory.try_use()
	_expect(_stock.count(_item.id) == 0, "the box should be empty after %d uses" % amount)
	_expect(not _trap.available(), "an empty box is not a weapon that can be taken out")
	_expect(_inventory.index() == TRAP_SLOT, "running out should not move the belt")
	_expect(_inventory.current() == null, "the empty box should leave the hands")
	_expect(_name_in(TRAP_SLOT) == "", "the square should go blank, and reads \"%s\"" % _name_in(TRAP_SLOT))
	_expect(_count_in(TRAP_SLOT) == "", "the square should count nothing, and counts \"%s\"" % _count_in(TRAP_SLOT))
	# One more click on an empty box does nothing, and least of all goes negative.
	_inventory.try_use()
	_expect(_stock.count(_item.id) == 0, "a click on an empty box should buy nobody anything")
	return _advance()

## Closing gives the player back the map, the mouse and the rest of the HUD.
func _check_closes() -> bool:
	_shop.close()
	_expect(not _shop.visible, "closing should take the shop off screen")
	_expect(not _player.is_ui_open(), "closing should give the player back to the map")
	_expect(_hotbar.visible, "the belt should come back with the shop gone")
	return _advance()

# --- Tools -----------------------------------------------------------------

func _expect(condition: bool, what: String) -> void:
	if condition:
		return
	print("FAIL: %s" % what)
	_failures += 1

## The buy button of the first item on the shelf. The rows are built in code, so
## it is looked for where it ends up and not by a path written by hand.
func _buy_button() -> Button:
	var items: VBoxContainer = _shop.get_node("Center/Panel/Margin/Rows/Items")
	for row in items.get_children():
		for child in row.get_children():
			var button := child as Button
			if button != null:
				return button
	return null

## What the corner of a hotbar square is counting.
func _count_in(index: int) -> String:
	var slot: PanelContainer = _hotbar.get_node("Slot%d" % (index + 1))
	var count: Label = slot.get_node("Count")
	return count.text

## What a hotbar square is calling its weapon, which is nothing at all while
## there is no weapon in it.
func _name_in(index: int) -> String:
	var slot: PanelContainer = _hotbar.get_node("Slot%d" % (index + 1))
	var label: Label = slot.get_node("Name")
	return label.text

func _advance() -> bool:
	_step += 1
	_clock = 0
	return false

func _finish() -> bool:
	print("--- %d frames, %d failure(s) ---" % [_frames, _failures])
	return true
