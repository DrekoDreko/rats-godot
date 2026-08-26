extends SceneTree
## Van-on-the-road bench: the scene card 09 asks for, and the things about it
## that are numbers.
##
## Run with: godot --headless --script _test_travel.gd
##
## What is checked here is that the box is shut, that the world outside really
## moves while the phase says it should and really stops when it does not, that
## the belt comes back, and that the two new stations are where a player can
## reach them. What cannot be checked here is the acceptance test of the card —
## two clients counting the same 120 seconds — which needs two instances and a
## lobby, and is done by hand.
##
## The clock itself is not re-tested: it belongs to the phase machine and
## `_test_phase.gd` already covers it. What *is* checked is the one thing card 09
## adds to it — that arriving on the road starts it without anybody asking.
##
## One machine and no wire throughout, which is the solo path the game takes when
## Steam is not running.
##
## **Nothing in here names a `class_name` of the project, and nothing names an
## autoload by its global name.** A bench is the `MainLoop`, so it is compiled
## before the autoloads are in the tree and before the global class list is
## built — a bench that mentions `RoadScroll` takes `road_scroll.gd` down with it
## and the van comes up with a bare `Node3D` where the road should be. Autoloads
## are picked up off `root` by node name, and a type is checked by asking the
## object what its script is.

## The scene under test, and the parked van it is grown from.
const TRAVEL := "res://scenes/van_travel.tscn"

## The phases, by their integer value. `Phase.Type` is a `class_name` and so
## cannot be named here — see the header. The order is the one in `phase.gd`.
const LOBBY := 0
const TRAVEL_PHASE := 1

## How long the road phase is meant to run, straight off `phase.gd`. The card
## asks for two minutes and this is what fails if somebody changes it.
const TRAVEL_SECONDS := 120.0

## The scripts the pieces are expected to be running, by path. Compared against
## `get_script().resource_path` rather than with `is`, for the reason above.
const TRAVEL_SCRIPT := "res://scripts/travel/van_travel.gd"
const ROAD_SCRIPT := "res://scripts/travel/road_scroll.gd"
const SHAKE_SCRIPT := "res://scripts/travel/cabin_shake.gd"
const READY_STATION_SCRIPT := "res://scripts/session/ready_station.gd"
const PENDING_STATION_SCRIPT := "res://scripts/session/pending_station.gd"
const SHOP_SHELF_SCRIPT := "res://scripts/shop/shop_shelf.gd"
## The map table card 11 fitted in the stand-in's place.
const MAP_TABLE_SCRIPT := "res://scripts/map/map_table.gd"

## The inside of the box body, straight off `models/box_van.py` — the same
## numbers the menu bench measures against, because it is the same truck.
const INNER_HALF_WIDTH := 1.6
const INNER_FLOOR := 0.622
const INNER_ROOF := 3.02
const INNER_BACK := 3.5
const INNER_FRONT := -3.5

## Stand-in Steam IDs, as in the other benches.
const ANA := 111
const BRUNO := 222

## Frames of slack for a scene to stand up and for the spawn node to have had its
## own frame of patience.
const WAIT := 8

var _session: Node
var _phase: Node

var _van: Node3D
var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0

## What the road had gone when it was last looked at, so that the next step can
## say whether it moved.
var _travelled := 0.0


func _initialize() -> void:
	Engine.max_fps = 60
	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_it_loads()
		1: return _check_the_box_is_shut()
		2: return _check_the_stations()
		3: return _check_the_belt_is_free()
		4: return _check_the_road_moves()
		5: return _check_the_road_stops()
	return _finish()

# --- Steps -----------------------------------------------------------------

## It stands up at all, on the road, with a crew already in it — a player only
## reaches this scene through the lobby, so it is entered with the crew list
## already filled and the phase already `TRAVEL`.
func _check_it_loads() -> bool:
	if _clock == 1:
		if _session == null or _phase == null:
			print("FAIL: the session autoloads are not in the tree")
			return _finish()
		_session.register_player(ANA, "Ana", true)
		_session.register_player(BRUNO, "Bruno")

		# The shift is walked onto the road properly rather than having
		# `SessionManager.phase` written by hand, because the clock is what is
		# being checked and only a real `go_to` starts one. What is *not* wanted
		# is the phase machine loading its own copy of the van as the current
		# scene: this bench adds its own by hand so that it can measure the
		# geometry without a scene change in the way, and two vans in the tree
		# would mean two players in the `player` group. So the road is pointed at
		# nothing for the length of the change — an empty path is a phase the
		# machine changes without loading anything — and put back afterwards.
		_phase.scenes[TRAVEL_PHASE] = ""
		_phase.go_to(TRAVEL_PHASE)
		_phase.scenes[TRAVEL_PHASE] = TRAVEL

		# The phase is settled before the scene is built, because the van reads
		# it on the way up rather than waiting for a change — which is the whole
		# point of `_apply_state` being called from `_ready`.
		var packed := load(TRAVEL) as PackedScene
		if packed == null:
			print("FAIL: %s does not load" % TRAVEL)
			return _finish()
		_van = packed.instantiate() as Node3D
		root.add_child(_van)
		return false
	if _clock < WAIT:
		return false

	_expect(_van != null, "the van stands up")
	if _van == null:
		return _finish()
	_expect(_script_of(_van) == TRAVEL_SCRIPT, "and it is card 09's own van")
	_expect(_van.get_node_or_null("Van") != null, "with the truck in it")
	_expect(_van.get_node_or_null("Road") != null, "and a road going past")
	_expect(_van.get_node_or_null("CabinShake") != null, "and a tremor in the cabin")
	_expect(_van.get_node_or_null("Spawns") != null, "and the spawn points")
	_expect(_van.get_node_or_null("HUDPhase") != null, "and the phase HUD (card 04)")
	_expect(_van.get_node_or_null("Player") != null, "and this machine's own player")

	var road := _van.get_node_or_null("Road")
	_expect(_script_of(road) == ROAD_SCRIPT, "the road is the scrolling one")
	var shake := _van.get_node_or_null("CabinShake")
	_expect(_script_of(shake) == SHAKE_SCRIPT, "the tremor is card 09's own")

	# The phase machine already points the road phase at this file — it did so
	# before the scene existed, and this is what says the two agree.
	var travel_scene: String = _phase.scene_of(TRAVEL_PHASE)
	_expect(travel_scene == TRAVEL, "and the phase machine points the road at it")

	# The card asks for a clock of two minutes, started on arrival without
	# anybody pressing anything. The clock itself is the phase machine's and is
	# tested there; what is checked here is that the number is still the one the
	# card asks for, and that the road phase is one that has a clock at all.
	var has_clock: bool = _phase.has_timer()
	_expect(has_clock, "the road is a phase with a clock on it")
	var left: float = _phase.seconds_left
	_expect(left > 0.0 and left <= TRAVEL_SECONDS,
		"and there is time on it, without anybody starting it")
	return _advance()

## The card asks for the back door shut. The lobby's van is open at the rear and
## walks a player down a ramp; this one must not, or the crew steps out at fifty
## kilometres an hour.
func _check_the_box_is_shut() -> bool:
	var shell := _van.get_node_or_null("Van/Shell") as StaticBody3D
	if shell == null:
		print("FAIL: the van has no collision shell")
		return _advance()

	_expect(shell.collision_layer & 1 != 0, "the shell is on the scenery layer")
	_expect(shell.is_in_group("scenery"), "and in the scenery group")

	for wall in ["Floor", "SideL", "SideR", "Bulkhead", "Roof"]:
		_expect(shell.get_node_or_null(wall) != null, "the shell has its %s" % wall)

	# The one real difference from the parked van: a wall across the doorway
	# where the ramp used to be.
	_expect(shell.get_node_or_null("Tailgate") != null,
		"the back is shut on the road")
	_expect(shell.get_node_or_null("Ramp") == null,
		"and there is no ramp down out of a moving van")
	_expect(_van.get_node_or_null("Van/Shutter") != null,
		"with a shutter across it to look at")

	# A van on the road has no yard around it — the world outside is the scroll,
	# and a fence would be a fence going past at the same speed as the road,
	# which is to say standing still.
	_expect(_van.get_node_or_null("Yard") == null,
		"and no parked-up yard fenced around it")
	return _advance()

## The stations the card asks for: the shop (card 10), the map table (card 11)
## and the ready board (card 03) kept from the lobby. The shelf is fitted for
## real now; the map table is still a stand-in.
func _check_the_stations() -> bool:
	var stations := _van.get_node_or_null("Stations")
	if stations == null:
		print("FAIL: the van has no stations")
		return _advance()

	var shop := stations.get_node_or_null("Shop") as Area3D
	var map := stations.get_node_or_null("MapTable") as Area3D
	var ready_board := stations.get_node_or_null("ReadyStation") as Area3D

	_expect(shop != null, "there is a shop shelf")
	_expect(map != null, "there is a map table")
	_expect(ready_board != null, "and the ready station is kept")

	if ready_board != null:
		_expect(_script_of(ready_board) == READY_STATION_SCRIPT,
			"the ready station is card 03's own board")
		_expect(ready_board.is_in_group("ready_station"),
			"found by its group like everywhere else")

	# The shelf is written (card 10): it carries its own script, it is out of the
	# stand-in group, and it stands the goods it sells on its boards rather than
	# being an empty cabinet. That swap is the one the stand-in was fitted to
	# make cheap — the geometry did not move.
	if shop != null:
		_expect(_script_of(shop) == SHOP_SHELF_SCRIPT, "the shelf is card 10's own")
		_expect(not shop.is_in_group("pending_station"),
			"the shelf is no longer a stand-in")
		var goods := shop.get_node_or_null("Goods")
		_expect(goods != null and goods.get_child_count() > 0,
			"the shelf has goods standing on it")

	# The map table is written (card 11): it carries its own script, it is out of the
	# stand-in group, and it holds the blueprint of the active contract.
	if map != null:
		_expect(_script_of(map) == MAP_TABLE_SCRIPT, "the table is card 11's own")
		_expect(not map.is_in_group("pending_station"),
			"the table is no longer a stand-in")
		_expect(map.is_in_group("map_station"), "the table is found by its group")
		var surface := map.get_node_or_null("PlanSurface")
		_expect(surface != null, "the table has a blueprint sheet on its surface")

	var all_stations: Array[Area3D] = [shop, map, ready_board]
	for station in all_stations:
		if station == null:
			continue
		_expect(station.collision_layer == 8,
			"%s sits on the interaction layer" % station.name)
		var prompt: String = station.prompt
		_expect(not prompt.is_empty(), "%s offers a prompt" % station.name)

		var at: Vector3 = station.global_position
		_expect(absf(at.x) <= INNER_HALF_WIDTH + 0.2,
			"%s is inside the walls of the van" % station.name)
		_expect(at.y > INNER_FLOOR and at.y < INNER_ROOF,
			"%s is at a height a player can reach" % station.name)
		_expect(at.z > INNER_FRONT and at.z < INNER_BACK,
			"%s is inside the box" % station.name)

	# Three men at three stations must not be standing on each other.
	if shop != null and map != null:
		_expect(shop.global_position.distance_to(map.global_position) > 1.5,
			"the shelf and the table are not the same corner")
	if shop != null and ready_board != null:
		_expect(shop.global_position.distance_to(ready_board.global_position) > 1.0,
			"the shelf and the ready board are not the same corner")
	return _advance()

## The card says weapons are enabled on the road: the crew is meant to equip what
## it just bought and try it. The lock belongs to the spawn node, which reads the
## phase — so what is checked is that the phase it reads here leaves the belt
## alone.
func _check_the_belt_is_free() -> bool:
	var belt := _belt()
	if belt == null:
		print("FAIL: there is no belt in the van")
		return _advance()

	var barred: bool = belt.has_bars()
	_expect(not barred, "the belt is free on the road")
	var slots: int = belt.slot_count()
	for index in slots:
		var is_barred: bool = belt.is_barred(index)
		_expect(not is_barred, "slot %d is not barred" % index)
	return _advance()

## The world goes past while the phase says the van is moving. What is measured
## is the road's own odometer, which is what the ground scroll and the props are
## both driven from — if it moves, they moved.
func _check_the_road_moves() -> bool:
	var road := _van.get_node_or_null("Road")
	if road == null:
		print("FAIL: there is no road to move")
		return _advance()

	if _clock == 1:
		var moving: bool = _van.is_moving()
		_expect(moving, "the van knows it is on the road")
		var running: bool = road.running
		_expect(running, "so the world outside is going past")
		_travelled = road.travelled()
		return false
	if _clock < WAIT:
		return false

	var now: float = road.travelled()
	_expect(now > _travelled, "and after a few frames it has gone somewhere")

	# The props are moved rather than scrolled, and every one of them has to stay
	# on the road: a prop wrapped past the far end never comes round again.
	var props := road.get_node_or_null("Props")
	_expect(props != null, "there are things beside the road")
	if props != null:
		var near: float = road.wrap_near
		var far: float = road.wrap_far
		_expect(near > far, "the loop the props run round has a length")
		for child in props.get_children():
			var prop := child as Node3D
			if prop == null:
				continue
			_expect(prop.position.z <= near + 0.001,
				"%s has not run off the near end" % prop.name)
			_expect(prop.position.z >= far - 0.001,
				"%s has not run off the far end" % prop.name)

	_travelled = now
	return _advance()

## And it stops when the shift moves on. A van left standing in another phase
## quietly driving nowhere is the bug this guards: the road, the tremor and the
## engine all have to go with the phase, not with the scene being loaded.
func _check_the_road_stops() -> bool:
	var road := _van.get_node_or_null("Road")
	if road == null:
		return _advance()

	if _clock == 1:
		# The phase is changed under the van rather than the van being told: this
		# is the signal path the real shift uses, and the point is that the van
		# hears it without anybody wiring it up per scene.
		_phase.go_to(LOBBY)
		return false
	if _clock < WAIT:
		return false

	var moving: bool = _van.is_moving()
	_expect(not moving, "off the road, the van knows it has stopped")
	var running: bool = road.running
	_expect(not running, "so the world outside stands still")

	var before: float = road.travelled()
	_travelled = before
	if _clock < WAIT * 2:
		return false
	_expect(is_equal_approx(road.travelled(), _travelled),
		"and the odometer has stopped counting")
	return _advance()

# --- Plumbing --------------------------------------------------------------

## This machine's own belt, off the player in the van.
func _belt() -> Node:
	var player := _van.get_node_or_null("Player")
	if player == null:
		return null
	return player.inventory


## What script a node is running, by path. Named this way rather than with `is`
## so that the bench never mentions a `class_name` — see the header.
func _script_of(node: Node) -> String:
	if node == null:
		return ""
	var script := node.get_script() as Script
	return "" if script == null else script.resource_path


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
	quit(1 if _failures > 0 else 0)
	return true
