extends SceneTree
## Traps test bench: the two things the player leaves on the floor, and the two
## quite different ways they end a rat.
##
## Run with: godot --headless --script _test_traps.gd
##
## What is checked here is the trade the two traps are built around. The
## mousetrap works while the player is somewhere else and hands back a mangled
## animal (`Death.Type.TRAP`, three quarters); the glue kills nothing, holds the
## rat where it stands, and waits for the player to come and finish it himself —
## and finished by hand it pays the whole price of the animal.
##
## The last six steps are the mousetrap's other half of the bargain, which comes
## due long after the money does: the body stays in the trap, the spot it is
## lying on empties of rats, and getting the floor back costs the player time on
## his feet. What he scrapes up is bent, and the bill for that arrives later
## still — the day he goes to set it down again, with the price hanging over his
## sights and an empty wallet meaning it simply does not land.
##
## Also checked, because it is the one thing a placed trap could quietly break:
## no trap joins the `scenery` group. The navigation mesh is baked from that
## group, and a trap that joined it would be baked into the floor as an obstacle
## — every rat in the map would then route politely around every trap the player
## ever set.

## Frames of slack between one step and the next.
const WAIT := 8
## How long a step waits for something to happen before giving up on it.
const LIMIT := 150
## The two loops of the belt the traps hang from.
const TRAP_SLOT := 0
const GLUE_SLOT := 1
## Copied instead of read off `Death`: naming the class from a bench drags its
## script into the compile that happens before the autoloads exist, and `Stock`
## is not there yet to be found (see `_test_inventory.gd`).
const DEATH_TRAP := 3
const DEATH_STRANGULATION := 1
const TRAP_MULTIPLIER := 0.75
const STRANGLE_MULTIPLIER := 1.0
## What the belt reads while the hands are out (`Inventory.HANDS_INDEX`).
const HANDS_INDEX := -1
## Where the player stands to put something down. It is the map's own starting
## point, which is open floor by construction — a spot picked by eye can easily
## be past the edge of the boards, and the ground ray would find nothing there.
const FLOOR_STATION := Vector3(0.0, 0.1, 4.0)
## How far down the head is tipped to aim at the floor in front of him.
const LOOK_DOWN := -0.9
## Where the player is sent when he must not be the reason for anything. It is
## well past `safe_radius` (26 m) from anywhere the rats are put, so a rat that
## bolts from a fouled trap is bolting from the trap and from nothing else.
const FAR_STATION := Vector3(0.0, 0.1, -40.0)
## What setting down a salvaged trap costs (the weapon's `salvage_fee`), and what
## the player is given to pay it with.
const SALVAGE_FEE := 2
const CLEANING_PURSE := 50

var _world: Node3D
var _player: CharacterBody3D
var _head: Node3D
var _hands: Node3D
var _inventory: Node
var _traps: Node3D
var _rats: Node3D
## The autoloads. In a bench run with `--script` their global names do not exist
## yet — the MainLoop script is compiled before they enter the tree — so they are
## picked up by node name instead.
var _wallet: Node
var _stock: Node
var _phase: Node

var _trap_node: Node3D
var _glue_node: Node3D
var _rat: Node3D
## The one the mousetrap killed, held on to separately: `_rat` moves on to the
## glue's business four steps later, and the body in the trap is still wanted.
var _trap_rat: Node3D
var _handle: Area3D
var _money_before := 0
var _squeezes := 0
var _polygons_before := 0

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
	_traps = _world.get_node("Traps")
	_rats = _world.get_node("Rats")
	_wallet = root.get_node_or_null("Wallet")
	_stock = root.get_node_or_null("Stock")
	_phase = root.get_node_or_null("PhaseManager")
	# The player is driven from here: no input and no gravity.
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)
	# The cadence of the weapons is not what this bench is about, and the two
	# clicks that lay a strip of glue happen on the same frame here. Without this
	# the second one lands inside the first one's cooldown and is dropped.
	for weapon in [_player.get_node("Head/Mousetrap"), _player.get_node("Head/RatGlue")]:
		weapon.cooldown = 0.0

func _physics_process(delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_enters_the_house()
		1: return _check_setup()
		2: return _check_places_mousetrap()
		3: return _check_navmesh_untouched()
		4: return _check_mousetrap_kills()
		5: return _check_glue_first_click()
		6: return _check_glue_cancel()
		7: return _check_glue_places()
		8: return _check_glue_pins()
		9: return _check_pinned_dies_fast()
		10: return _check_glue_pays_more()
		11: return _check_carcass_stays()
		12: return _check_trap_scares()
		13: return _check_cleaning_takes_time()
		14: return _check_cleaned_trap_is_gone()
		15: return _check_salvaged_trap_costs_to_place()
		16: return _check_broke_player_cannot_place()
	return _finish()

# --- Steps -----------------------------------------------------------------

## The van hands the player his boxes. Nothing has been bought in this bench, so
## the stock is credited straight — the buying itself is `_test_shop.gd`'s job.
## Into the house, before anything is measured.
##
## Traps are not put down locally any more — they are asked for, and the host
## turns down a request from a phase with no floor under it
## (`TrapManager.PHASES`). A shift standing in the survey is the state this whole
## bench was always describing; it simply never had to say so before.
##
## It is a step of its own rather than a line in `_check_setup` for two reasons.
## The phase machine cannot be touched from `_initialize` at all — an autoload is
## not in the tree yet when the MainLoop script is built, so it has no
## `multiplayer` to ask whether we are the host. And arriving in the survey
## rebakes the floor (`house.gd` lays the contract's geometry), which lands a
## frame or two later: a navmesh baseline taken in the same breath as the phase
## change is a baseline taken before the bake, and the check three steps down
## would then read the bake as the trap's doing.
func _check_enters_the_house() -> bool:
	if _phase == null:
		print("FAIL: the phase machine was not found")
		return _finish()
	if _clock == 1:
		_phase.go_to(2)
		return false
	if _clock < WAIT:
		return false
	_expect(_phase.current() == 2, "the bench should be standing in the survey")
	return _advance()

func _check_setup() -> bool:
	if _clock < WAIT:
		return false
	if _wallet == null or _stock == null:
		print("FAIL: the autoloads were not found")
		return _finish()
	_wallet.reset()
	_stock.reset()
	_stock.add("mousetrap", 3)
	_stock.add("rat_glue", 2)
	# The rats wander on their own and would walk onto the traps mid-step. They
	# are put to sleep and moved by hand, one at a time.
	for rat in _rats.get_children():
		rat.set_physics_process(false)
	var mesh: NavigationMesh = _world.get_node("Navigation").navigation_mesh
	_polygons_before = mesh.get_polygon_count()
	print("--- %d mousetraps, %d trays of glue, %d navmesh polygons ---" % [
		_stock.count("mousetrap"), _stock.count("rat_glue"), _polygons_before,
	])
	_expect(_traps != null, "the map should keep a Traps node for what gets put down")
	_expect(_placed_count() == 0, "nothing should be on the floor yet")
	return _advance()

## One click of the box puts one trap on the floor, and takes one out of the box.
func _check_places_mousetrap() -> bool:
	if _clock < WAIT:
		return false
	_stand_on_floor()
	_expect(_inventory.equip(TRAP_SLOT), "the belt should reach the box of traps")
	var before: int = _stock.count("mousetrap")
	_inventory.try_use()
	_expect(_stock.count("mousetrap") == before - 1,
		"placing a trap should take exactly one out of the box")

	_trap_node = _placed_trap("Mousetrap")
	if _trap_node == null:
		print("FAIL: no mousetrap landed on the floor")
		return _finish()
	print("--- mousetrap down at %v ---" % _trap_node.global_position)
	_expect(not _trap_node.is_in_group("scenery"),
		"a trap in the scenery group would be baked into the navmesh")
	_expect(_trap_node.collision_mask == 4, "a trap should watch the rats' layer and no other")
	_expect(_trap_node.collision_layer == 0, "nothing should collide with a trap")
	_expect(_trap_node.is_armed(), "a freshly placed trap should be waiting for a rat")
	return _advance()

## The floor the rats walk on is the same floor it was. This is the guard on the
## one thing a placed trap could quietly break.
func _check_navmesh_untouched() -> bool:
	var mesh: NavigationMesh = _world.get_node("Navigation").navigation_mesh
	_expect(mesh.get_polygon_count() == _polygons_before,
		"placing a trap should leave the navigation mesh alone (%d -> %d)" % [
			_polygons_before, mesh.get_polygon_count(),
		])
	return _advance()

## A rat that steps on it dies of it, mangled: it pays the trap's three quarters
## and not a penny more.
func _check_mousetrap_kills() -> bool:
	if _clock == 1:
		_rat = _loose_rat()
		if _rat == null:
			print("FAIL: no loose rat for the mousetrap")
			return _finish()
		_money_before = _wallet.money
		# Onto the trap, and awake enough to be noticed by it.
		_rat.global_position = _trap_node.global_position
		_rat.set_physics_process(true)
		return false
	if not _rat.is_dead():
		if _clock > LIMIT:
			print("FAIL: the rat on the mousetrap did not die in %d frames" % LIMIT)
			return _finish()
		return false

	_trap_rat = _rat
	var gain: int = _wallet.money - _money_before
	print("--- the mousetrap paid $%d ---" % gain)
	_expect(gain > 0, "a rat killed in a trap should pay something")
	_expect(_matches(gain, TRAP_MULTIPLIER),
		"a rat killed in a trap should pay the trap's share, and paid $%d" % gain)
	_expect(not _trap_node.is_armed(), "a trap that has caught its rat should be spent")
	return _advance()

## The first click of the glue pins the near end of the strip and nothing else:
## no tray leaves the box, the player still walks, and the belt is held.
func _check_glue_first_click() -> bool:
	if _clock < WAIT:
		return false
	_stand_on_floor()
	_expect(_inventory.equip(GLUE_SLOT), "the belt should reach the tray of glue")
	var glue: Node3D = _player.get_node("Head/RatGlue")
	var before: int = _stock.count("rat_glue")
	_inventory.try_use()
	_expect(glue.is_placing(), "the first click should pin the near end of the strip")
	_expect(_stock.count("rat_glue") == before,
		"the first click should spend nothing — the tray goes down on the second")
	_expect(not _inventory.is_busy(),
		"laying a strip should leave the player free to walk")
	_expect(_inventory.holds_belt(), "a strip half laid should hold the belt")
	_expect(not _inventory.equip(TRAP_SLOT), "the belt should be refused mid-strip")
	_expect(not _inventory.equip_hands(), "Q should be refused mid-strip")
	_expect(_placed_count() == 1, "nothing new should be on the floor yet")
	return _advance()

## Esc throws the run away, and the tray was never spent.
func _check_glue_cancel() -> bool:
	var glue: Node3D = _player.get_node("Head/RatGlue")
	var before: int = _stock.count("rat_glue")
	_expect(_inventory.cancel(), "a strip half laid should be there to be called off")
	_expect(not glue.is_placing(), "the called-off strip should be gone")
	_expect(_stock.count("rat_glue") == before, "calling off a strip should cost nothing")
	_expect(_placed_count() == 1, "a called-off strip should leave nothing behind")
	_expect(not _inventory.cancel(),
		"with nothing to call off the key should fall through to what it usually means")
	_expect(_inventory.equip_hands(), "the belt should open again once the strip is gone")
	return _advance()

## Two clicks with a walk in between put the whole run down, clamped to the
## length one tray makes.
func _check_glue_places() -> bool:
	if _clock < WAIT:
		return false
	_stand_on_floor()
	_expect(_inventory.equip(GLUE_SLOT), "the belt should reach the tray of glue again")
	var glue: Node3D = _player.get_node("Head/RatGlue")
	var before: int = _stock.count("rat_glue")
	_inventory.try_use()
	if not glue.is_placing():
		print("FAIL: the first click did not pin the strip")
		return _finish()
	# The player walks further than one tray reaches, so the clamp has something
	# to do.
	_player.global_position += Vector3(0.0, 0.0, -glue.max_length - 1.5)
	_inventory.try_use()

	_expect(_stock.count("rat_glue") == before - 1,
		"laying the strip should take exactly one tray out of the box")
	_expect(not glue.is_placing(), "the second click should finish the strip")
	_glue_node = _placed_trap("GlueTrap")
	if _glue_node == null:
		print("FAIL: no strip of glue landed on the floor")
		return _finish()
	var length: float = _glue_node.scale.z
	print("--- a strip of glue %.2f m long (of at most %.2f) ---" % [length, glue.max_length])
	_expect(length <= glue.max_length + 0.01,
		"the strip should stop at the length one tray makes, and ran %.2f m" % length)
	_expect(length >= glue.min_length, "the strip should be worth putting down")
	return _advance()

## A rat that walks onto it stops there — and stays a rat: alive, still on the
## books, and still something a weapon can be pointed at.
func _check_glue_pins() -> bool:
	if _clock == 1:
		_rat = _loose_rat()
		if _rat == null:
			print("FAIL: no loose rat for the glue")
			return _finish()
		_rat.global_position = _glue_node.global_position
		_rat.set_physics_process(true)
		return false
	if not _rat.is_pinned():
		if _clock > LIMIT:
			print("FAIL: the rat on the glue was not pinned in %d frames" % LIMIT)
			return _finish()
		return false

	print("--- rat stuck on the glue (%s) ---" % _rat.name)
	_expect(not _rat.is_dead(), "the glue should kill nothing")
	_expect(not _rat.is_captured(), "a rat stuck on the floor is in nobody's hand")
	_expect(_rat.is_in_group("rats"), "a stuck rat is still a rat, and still a target")
	_expect(_rat.effort() < 1.0, "a stuck rat should be less work than a loose one")
	_glue_node.set_meta("watched_position", _rat.global_position)
	return _advance()

## It stays where it was caught, and the hand that comes for it takes it off the
## glue in far fewer squeezes than a rat caught loose would cost.
func _check_pinned_dies_fast() -> bool:
	# A moment of standing still first: a rat that could leave would have left by
	# now.
	if _clock < 60:
		return false
	if _clock == 60:
		var caught_at: Vector3 = _glue_node.get_meta("watched_position")
		_expect(_rat.global_position.distance_to(caught_at) < 0.15,
			"a stuck rat should not have gone anywhere in a second of trying")
		_money_before = _wallet.money
		_aim_at(_rat)
		_expect(_inventory.equip_hands(), "the hands should come back for the stuck rat")
		_inventory.try_use()
		if not _rat.is_captured():
			print("FAIL: the stuck rat could not be picked up off the glue")
			return _finish()
		_expect(not _rat.is_pinned(), "picking the rat up should tear it off the glue")
		_squeezes = 0
		return false

	# One squeeze per frame, counted, until the animal gives in.
	if _inventory.is_busy():
		if _squeezes > _hands.squeezes_to_kill:
			print("FAIL: the stuck rat took more squeezes than a loose one")
			return _finish()
		_squeezes += 1
		_inventory.press_secondary()
		return false

	print("--- the stuck rat gave in after %d squeezes (a loose one takes %d) ---" % [
		_squeezes, _hands.squeezes_to_kill,
	])
	_expect(_squeezes < _hands.squeezes_to_kill,
		"a rat taken off the glue should give in sooner than a loose one")
	# The tray is spent the instant the rat comes off it; the peeling that takes
	# it off the floor is a gesture, and it is still running here.
	_expect(not is_instance_valid(_glue_node) or not _glue_node.is_armed(),
		"the tray should be spent once the rat is off it")
	return _advance()

## And the point of the whole thing: strangled, it pays the full price of the
## animal — more than the same rat would have paid caught in a mousetrap.
func _check_glue_pays_more() -> bool:
	# The body has to reach the waist before it turns into money.
	if _wallet.money == _money_before:
		if _clock > LIMIT:
			print("FAIL: the strangled rat never paid in %d frames" % LIMIT)
			return _finish()
		return false

	var gain: int = _wallet.money - _money_before
	print("--- the glue paid $%d ---" % gain)
	_expect(_matches(gain, STRANGLE_MULTIPLIER),
		"a rat taken off the glue and strangled should pay the whole animal, and paid $%d" % gain)
	_expect(float(gain) > float(gain) * TRAP_MULTIPLIER,
		"the glue should pay more than the mousetrap")
	# By now the peeling has had its quarter of a second: the spent tray is off
	# the floor for good, and the only thing left down there is the mousetrap.
	_expect(not is_instance_valid(_glue_node) or _glue_node.is_queued_for_deletion(),
		"the spent tray should peel off the floor and go")
	return _advance()

## The body the mousetrap killed is still lying in it, hundreds of frames after
## a rat killed anywhere else would have shrunk away and gone. It is the whole
## reason there is anything to come back for.
func _check_carcass_stays() -> bool:
	if _clock < WAIT:
		return false
	if not is_instance_valid(_trap_rat):
		print("FAIL: the rat the trap killed was freed like any other carcass")
		return _finish()
	_expect(not _trap_rat.is_queued_for_deletion(),
		"a body the trap has a claim on should not be on its way out")
	_expect(_trap_rat.is_held(), "the trap should still be holding what it killed")
	var slipped: float = _trap_rat.global_position.distance_to(_trap_node.global_position)
	print("--- the carcass lies %.2f m from the trap ---" % slipped)
	_expect(slipped < 0.6,
		"the body should settle in the trap and not be thrown clear of it (%.2f m)" % slipped)
	return _advance()

## And the spot it is lying on has gone bad. A rat put down beside the corpse
## leaves on its own, with the player nowhere near enough to be the reason.
func _check_trap_scares() -> bool:
	if _clock == 1:
		_expect(_trap_node.is_in_group("fear"),
			"a trap with a dead rat in it should be one of the map's foul spots")
		if not _trap_node.has_method("fear_radius"):
			print("FAIL: a foul spot should say how far the smell of it reaches")
			return _finish()
		_rat = _loose_rat()
		if _rat == null:
			print("FAIL: no loose rat to be scared off the trap")
			return _finish()
		# Him first: a rat that bolted because the player was standing there
		# would pass this step while proving nothing.
		_player.global_position = FAR_STATION
		_rat.global_position = _trap_node.global_position + Vector3(0.8, 0.0, 0.0)
		_rat.set_physics_process(true)
		var away: float = _player.global_position.distance_to(_rat.global_position)
		_expect(away > _rat.safe_radius,
			"the player must be out of the picture for this, and stood %.1f m off" % away)
		print("--- a rat set down %.2f m from the corpse, the player %.1f m away ---" % [
			_rat.global_position.distance_to(_trap_node.global_position), away,
		])
		return false

	var reach: float = _trap_node.fear_radius()
	var out: float = _rat.global_position.distance_to(_trap_node.global_position)
	if out < reach:
		if _clock > LIMIT * 2:
			print("FAIL: the rat sat on the foul spot for %d frames (%.2f m of %.2f)" % [
				LIMIT * 2, out, reach,
			])
			return _finish()
		return false
	print("--- the rat cleared the foul spot (%.2f m of %.2f) ---" % [out, reach])
	_rat.set_physics_process(false)
	return _advance()

## Cleaning is work. The trap offers the player a face to put his hands on, and
## that face answers to the key held down and not to a tap: a short press is let
## go of and buys nothing, and only the whole of `hold_time` finishes the job.
##
## The player is driven by hand here, which the rest of the bench never has to
## do: the counter that does the holding lives in his physics frame, so for this
## one step he is given it back.
func _check_cleaning_takes_time() -> bool:
	if _clock == 1:
		_handle = _trap_node.get_node_or_null("Handle") as Area3D
		if _handle == null:
			print("FAIL: a fouled trap should offer the player something to clean")
			return _finish()
		_expect(_handle.collision_layer == 8,
			"the trap's handle should sit on the interactable layer")
		_expect(_trap_node.collision_layer == 0,
			"the trap itself should still collide with nothing")
		_expect(_handle.is_held_work(), "cleaning a trap should be work and not a tap")
		# Enough in the wallet to pay the fee with, counted from here.
		while _wallet.money < CLEANING_PURSE:
			_wallet.collect(load("res://resources/species/common_rat.tres"), DEATH_STRANGULATION, 1.0)
		_money_before = _wallet.money
		_player.set_physics_process(true)
		return false

	# The work finishing takes the trap off the floor, and with it the face the
	# player was working on. That is the end of the step: whether it came too
	# early is what the clock below is asked.
	if not is_instance_valid(_handle):
		Input.action_release("interact")
		_player.set_physics_process(false)
		_expect(_clock > _tap_end() + 1,
			"a trap cleaned at frame %d was cleaned by a tap, not by the work" % _clock)
		print("--- the trap came up after %d frames of holding ---" % (_clock - _tap_end()))
		return _advance()

	# He is put back on his mark every frame: `_aim_at` writes his position
	# outright, which keeps him in reach and holds off the gravity he has just
	# been handed back.
	_aim_at(_handle)

	# The tap: pressed, held for a handful of frames, and let go of again.
	if _clock < _tap_end():
		Input.action_press("interact")
		return false
	if _clock == _tap_end():
		Input.action_release("interact")
		return false
	if _clock == _tap_end() + 1:
		_expect(_trap_node.is_in_group("fear"),
			"a few frames of the key down should clean nothing")
		return false

	# And now the whole of it. The step ends when the trap goes, above.
	Input.action_press("interact")
	if _clock > _tap_end() + int(_handle.hold_time * 60.0) + LIMIT:
		print("FAIL: holding the key for the whole of %.1f s cleaned nothing" % _handle.hold_time)
		return _finish()
	return false

## How long the tap lasts, in frames. It is short enough to be a tap by any
## reading of `hold_time`, and it is a function so the two halves of the step
## cannot drift apart.
func _tap_end() -> int:
	return WAIT

## What the work buys: the trap comes up off the floor, the body goes with it,
## the ground is ordinary ground again — and the trap is back in the box, for the
## price of the parts.
func _check_cleaned_trap_is_gone() -> bool:
	# The ground is clean the instant the work ends, and that is checked before
	# anything is waited for: the rats get their floor back straight away, and
	# not at the end of the little animation the trap leaves on.
	if _clock == 1:
		_expect(get_nodes_in_group("fear").is_empty(),
			"a cleaned trap should stop being a foul spot the moment it is cleaned")
		_expect(is_instance_valid(_trap_rat) and not _trap_rat.is_held(),
			"the body should be let go of when the trap that held it is cleaned")
		return false

	# The body goes on its own clock once it is let go of — the same
	# `CARCASS_TIME` every rat shot across the room gets — so this waits it out
	# rather than expecting the floor to clear at once.
	if _clock < LIMIT:
		return false
	_expect(not is_instance_valid(_trap_node) or _trap_node.is_queued_for_deletion(),
		"a cleaned trap should leave the floor")
	_expect(not is_instance_valid(_trap_rat) or _trap_rat.is_queued_for_deletion(),
		"the body should go the way of every other carcass once it is let go of")
	var paid: int = _money_before - _wallet.money
	print("--- cleaning cost $%d, and put %d trap(s) back in the bag ---" % [
		paid, _stock.count("mousetrap"),
	])
	_expect(paid == 0, "scraping a trap off the floor should cost only time, and cost $%d" % paid)
	_expect(_stock.count("mousetrap") > 0, "a cleaned trap should go back into the bag")
	_expect(_stock.salvaged("mousetrap") > 0,
		"a trap that came off the floor should be marked as the bent thing it is")
	return _advance()

## The bent one costs money to set down again, and the money goes at the moment
## it lands. What he bought at the computer still goes down free: the fee is on
## the salvage and on nothing else.
func _check_salvaged_trap_costs_to_place() -> bool:
	if _clock < WAIT:
		return false
	var weapon: Node3D = _player.get_node("Head/Mousetrap")
	_expect(weapon.salvage_fee == SALVAGE_FEE,
		"the box should charge for a new spring, and charges $%d" % weapon.salvage_fee)
	_expect(_stock.next_is_salvaged("mousetrap"),
		"the bent one should be the next out of the bag, ahead of anything bought")

	_stand_on_floor()
	_expect(_inventory.equip(TRAP_SLOT), "the belt should reach the box of traps")
	while _wallet.money < CLEANING_PURSE:
		_wallet.collect(load("res://resources/species/common_rat.tres"), DEATH_STRANGULATION, 1.0)
	_money_before = _wallet.money
	var bent_before: int = _stock.salvaged("mousetrap")
	_inventory.try_use()

	var paid: int = _money_before - _wallet.money
	print("--- setting the bent one down cost $%d ---" % paid)
	_expect(paid == SALVAGE_FEE,
		"setting down a salvaged trap should cost the fee, and cost $%d" % paid)
	_expect(_stock.salvaged("mousetrap") == bent_before - 1,
		"the bent one should be the one that left the bag")
	_trap_node = _placed_trap("Mousetrap")
	_expect(_trap_node != null, "the trap he paid for should be on the floor")

	# And the next one is a bought one, which he already paid for at the computer.
	_expect(not _stock.next_is_salvaged("mousetrap"),
		"with the bent one used up, what is left should be what he bought")
	_money_before = _wallet.money
	_inventory.try_use()
	_expect(_wallet.money == _money_before,
		"a trap bought at the computer should go down free")
	return _advance()

## And with an empty wallet the bent one stays in the bag. The click is an honest
## miss: nothing on the floor, nothing out of the bag, nothing out of the wallet.
func _check_broke_player_cannot_place() -> bool:
	if _clock < WAIT:
		return false
	# Back to one bent trap and nothing else, and no money to arm it with. The
	# bag is filled before the belt is asked for the weapon: emptying it puts the
	# weapon away on the spot (`Inventory._on_stock_changed`), and a belt holding
	# nothing has no box of traps to reach for.
	_stock.reset()
	_stock.salvage("mousetrap")
	_wallet.reset()
	_stand_on_floor()
	# The belt is not asked to swap here: the traps are already out from the step
	# before, and `equip` turns down the slot it is already holding.
	_inventory.equip(TRAP_SLOT)
	_expect(_inventory.current() != null,
		"the belt should still be holding the box of traps")
	var on_floor := _placed_count()
	var in_bag: int = _stock.count("mousetrap")
	_inventory.try_use()

	print("--- with $0 in his pocket, the bent trap stayed in the bag ---")
	_expect(_placed_count() == on_floor,
		"a trap he cannot pay to arm should not reach the floor")
	_expect(_stock.count("mousetrap") == in_bag,
		"a trap he cannot pay to arm should stay in the bag")
	_expect(_wallet.money == 0, "a placement that did not happen should cost nothing")
	return _advance()

# --- Tools -----------------------------------------------------------------

func _expect(condition: bool, what: String) -> void:
	if condition:
		return
	print("FAIL: %s" % what)
	_failures += 1

## Whether a payout is the one a given death pays for this species. The size a
## rat is born at moves the price a little, so it is a band and not a number.
func _matches(gain: int, multiplier: float) -> bool:
	var species: Resource = load("res://resources/species/common_rat.tres")
	var base: int = species.base_value
	var spread: float = species.variation
	var low := roundi(base * (1.0 - spread) * multiplier) - 1
	var high := roundi(base * (1.0 + spread) * multiplier) + 1
	return gain >= low and gain <= high

## How many traps are actually on the floor. The ghost hangs off the same node
## and is not one of them — it never runs, and that is what tells the two apart.
func _placed_count() -> int:
	var count := 0
	for child in _traps.get_children():
		if _is_a_trap(child):
			count += 1
	return count

## Whether a child of the container is a trap on the floor. The container holds
## one thing that is not: the `MultiplayerSpawner` that carries the traps to the
## other machines (`scripts/session/trap_manager.gd`). Counted by what a child
## *is* rather than by how many there are, which is what `house.gd` already does
## for the same reason on the `Rats` container.
##
## The ghost used to have to be told apart here too. It no longer lives in this
## container at all — a translucent trap-to-be must never be replicated — so
## anything a `Trap` script is on is a trap that was really put down.
func _is_a_trap(child: Node) -> bool:
	var trap := child as Area3D
	return trap != null and trap.get_script() != null

## The trap of a given kind that is on the floor, or null. The last one placed is
## the one wanted: the earlier ones are still lying about.
func _placed_trap(kind: String) -> Node3D:
	var found: Node3D = null
	for child in _traps.get_children():
		if not _is_a_trap(child):
			continue
		var trap := child as Node3D
		if kind in str(trap.get_script().get_global_name()):
			found = trap
	return found

## A rat that is still loose on the map: alive, in nobody's hand and on no trap.
func _loose_rat() -> Node3D:
	for node in get_nodes_in_group("rats"):
		var rat := node as Node3D
		if rat.is_dead() or rat.is_captured() or rat.is_pinned():
			continue
		return rat
	return null

## Puts the player on open floor, looking down at it, so the ground ray has
## somewhere to land.
func _stand_on_floor() -> void:
	_player.global_position = FLOOR_STATION
	_player.rotation = Vector3.ZERO
	_head.rotation.x = LOOK_DOWN

## Puts the player behind the rat and points body and head at it, so the rat
## falls inside the reach and the cone of the hands.
func _aim_at(rat: Node3D) -> void:
	var target := rat.global_position + Vector3.UP * 0.2
	_player.global_position = rat.global_position + Vector3(0.0, 0.0, 1.6)
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
