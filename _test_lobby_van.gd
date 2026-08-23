extends SceneTree
## Lobby van bench: the room the crew is configured in, and the things the card
## asks of it.
##
## Run with: godot --headless --script _test_lobby_van.gd
##
## What is checked here is everything about the van that is a *number* — that
## the box is closed, that the four spots are inside it and apart from each
## other, that the four stations are where a player can reach them, and that
## the belt is barred while he is in there. What cannot be checked here is the
## acceptance test of the card itself — two players seeing each other walk about
## — which needs two instances and is done by hand.
##
## One machine and no wire throughout, which is the solo path the game takes
## anyway when Steam is not running.
##
## **Nothing in here names a `class_name` of the project, and nothing names an
## autoload by its global name.** A bench is the `MainLoop`, so it is compiled
## before the autoloads are in the tree and before the global class list is
## built — and a bench that mentions `Inventory` does not merely fail itself, it
## takes `inventory.gd` down with it and the player scene comes up crippled.
## Autoloads are picked up off `root` by node name, and a type is checked by
## asking the object what its script is rather than by naming the class.

## The van.
const VAN := "res://scenes/lobby_van.tscn"

## The scripts the stations are expected to be running, by path. Compared
## against `get_script().resource_path` rather than with `is`, for the reason
## in the header.
const READY_STATION_SCRIPT := "res://scripts/session/ready_station.gd"
const COLOR_STATION_SCRIPT := "res://scripts/session/color_station.gd"
const CLIPBOARD_STATION_SCRIPT := "res://scripts/session/clipboard_station.gd"
const RADIO_STATION_SCRIPT := "res://scripts/session/radio_station.gd"

## The inside of the box body, straight off `models/box_van.py`. If the truck is
## rebuilt with different numbers, these are what have to move with it — and the
## bench failing is the point: a van whose walls moved and whose collision did
## not is a van a player walks out through.
const INNER_HALF_WIDTH := 1.6
const INNER_FLOOR := 0.622
const INNER_ROOF := 3.02
const INNER_BACK := 3.5
const INNER_FRONT := -3.5

## Stand-in Steam IDs, as in the other benches.
const ANA := 111
const BRUNO := 222
const CARLA := 333
const DANI := 444

## Frames of slack for a scene to stand up and for the spawn node to have had
## its own frame of patience.
const WAIT := 8

var _session: Node
var _phase: Node

var _van: Node3D
var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	Engine.max_fps = 60
	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_it_loads()
		1: return _check_the_box_is_closed()
		2: return _check_the_spots()
		3: return _check_the_stations()
		4: return _check_the_belt_is_barred()
		5: return _check_the_belt_comes_back()
	return _finish()

# --- Steps -----------------------------------------------------------------

## It stands up at all, with a crew already in it — the van is entered with the
## crew list already filled, since a player only reaches it through the lobby.
func _check_it_loads() -> bool:
	if _clock == 1:
		if _session == null or _phase == null:
			print("FAIL: the session autoloads are not in the tree")
			return _finish()
		_session.register_player(ANA, "Ana", true)
		_session.register_player(BRUNO, "Bruno")
		_session.register_player(CARLA, "Carla")
		_session.register_player(DANI, "Dani")

		var packed := load(VAN) as PackedScene
		if packed == null:
			print("FAIL: %s does not load" % VAN)
			return _finish()
		_van = packed.instantiate() as Node3D
		root.add_child(_van)
		return false
	if _clock < WAIT:
		return false

	_expect(_van != null, "the van stands up")
	if _van == null:
		return _finish()
	_expect(_van.get_node_or_null("Van") != null, "with the truck in it")
	_expect(_van.get_node_or_null("Spawns") != null, "and the spawn points")
	_expect(_van.get_node_or_null("HUDPhase") != null, "and the phase HUD (card 04)")
	_expect(_van.get_node_or_null("Player") != null, "and this machine's own player")
	var lobby_scene: String = _phase.scene_of(Phase.Type.LOBBY)
	_expect(lobby_scene == VAN, "and the phase machine already points the lobby at it")
	return _advance()

## The card asks for a box a player cannot escape. What is checked is that every
## face of it has collision on the scenery layer, and that the yard outside has
## a fence — a player may walk a few steps down the ramp and no further.
func _check_the_box_is_closed() -> bool:
	var shell := _van.get_node_or_null("Van/Shell") as StaticBody3D
	if shell == null:
		print("FAIL: the van has no collision shell")
		return _advance()

	_expect(shell.collision_layer & 1 != 0, "the shell is on the scenery layer")
	_expect(shell.is_in_group("scenery"), "and in the scenery group")

	# Every wall of the box, by name, so that a missing one is named in the
	# failure rather than left to be counted.
	for wall in ["Floor", "SideL", "SideR", "Bulkhead", "Roof", "Ramp"]:
		_expect(shell.get_node_or_null(wall) != null, "the shell has its %s" % wall)

	var yard := _van.get_node_or_null("Yard") as StaticBody3D
	_expect(yard != null, "the yard outside is fenced")
	if yard != null:
		_expect(yard.get_child_count() >= 4, "on all four sides")
	return _advance()

## Four spots, all of them inside the box and none of them on top of another.
## The card asks for up to four, given out by the order the crew went in.
func _check_the_spots() -> bool:
	var spawns := _van.get_node_or_null("Spawns")
	if spawns == null:
		print("FAIL: the van has no spawn node")
		return _advance()

	var how_many: int = spawns.count()
	_expect(how_many == 4, "there are four spots")

	var seen: Array[Vector3] = []
	for steam_id in [ANA, BRUNO, CARLA, DANI]:
		var spot: Vector3 = spawns.spot_of(steam_id)
		_expect(absf(spot.x) < INNER_HALF_WIDTH, "%d stands between the walls" % steam_id)
		_expect(spot.z > INNER_FRONT and spot.z < INNER_BACK,
			"%d stands between the cab and the door" % steam_id)
		_expect(spot.y >= INNER_FLOOR - 0.05 and spot.y < INNER_ROOF,
			"%d stands on the floor" % steam_id)
		for other in seen:
			_expect(spot.distance_to(other) > 0.9,
				"%d does not stand inside a colleague" % steam_id)
		seen.append(spot)

	_expect(seen.size() == 4, "four players, four spots")

	# Somebody the crew has never heard of still has to stand somewhere.
	var stranger: Vector3 = spawns.spot_of(999)
	_expect(stranger == seen[0], "a player nobody knows takes the first spot")
	return _advance()

## The four stations the van holds, each of them something the player can
## reach: colour (card 06), contract (card 08), ready (card 03) and the radio
## (card 07).
func _check_the_stations() -> bool:
	var stations := _van.get_node_or_null("Stations")
	if stations == null:
		print("FAIL: the van has no stations")
		return _advance()

	var color := stations.get_node_or_null("ColorPanel") as Area3D
	var clipboard := stations.get_node_or_null("Clipboard") as Area3D
	var ready_board := stations.get_node_or_null("ReadyStation") as Area3D
	var radio := stations.get_node_or_null("Radio") as Area3D

	_expect(color != null, "there is a colour station")
	_expect(clipboard != null, "there is a contract station")
	_expect(ready_board != null, "there is a ready station")
	_expect(radio != null, "there is a radio to call a friend on")

	# The ready board is the one that is actually written, and it is the node
	# from card 03 rather than a second copy of it.
	if ready_board != null:
		_expect(_script_of(ready_board) == READY_STATION_SCRIPT,
			"and the ready station is card 03's own board")
		_expect(ready_board.is_in_group("ready_station"),
			"found by its group like everywhere else")

	# The colour panel is card 06's own, fitted in the place the pending one
	# stood — which is the swap that card promised would be one line and no
	# re-lay-out, so the geometry checks below still have to pass unchanged.
	if color != null:
		_expect(_script_of(color) == COLOR_STATION_SCRIPT,
			"the colour panel is card 06's own panel")
		_expect(color.is_in_group("color_station"),
			"found by its group like everywhere else")

	# The radio is card 07's own, and is the fitting the invite goes out from.
	if radio != null:
		_expect(_script_of(radio) == RADIO_STATION_SCRIPT,
			"the radio is card 07's own handset")
		_expect(radio.is_in_group("radio_station"),
			"found by its group like everywhere else")

	# The clipboard is card 08's own, fitted in the place the pending one stood —
	# the same one-line swap card 06 made, which is why the geometry checks
	# below still pass unchanged.
	if clipboard != null:
		_expect(_script_of(clipboard) == CLIPBOARD_STATION_SCRIPT,
			"the clipboard is card 08's own board")
		_expect(clipboard.is_in_group("clipboard_station"),
			"found by its group like everywhere else")

	var all_stations: Array[Area3D] = [color, clipboard, ready_board, radio]
	for station in all_stations:
		if station == null:
			continue
		_expect(station.collision_layer == 8,
			"%s sits on the interaction layer" % station.name)
		var prompt: String = station.prompt
		_expect(not prompt.is_empty(), "%s offers a prompt" % station.name)

		# Reachable means: inside the box, at a height a standing player can
		# look at.
		var at: Vector3 = station.global_position
		_expect(absf(at.x) <= INNER_HALF_WIDTH + 0.2,
			"%s is on a wall of the van" % station.name)
		_expect(at.y > INNER_FLOOR and at.y < INNER_ROOF,
			"%s is at a height a player can look at" % station.name)
		_expect(at.z > INNER_FRONT and at.z < INNER_BACK,
			"%s is inside the box" % station.name)

	# Two players at two different stations must not be standing on each other.
	if color != null and clipboard != null:
		_expect(color.global_position.distance_to(clipboard.global_position) > 1.5,
			"the colour panel and the clipboard are not the same corner")
	return _advance()

## The card asks for a lobby with nothing but empty hands: the belt is barred
## while the van is parked.
func _check_the_belt_is_barred() -> bool:
	var belt := _belt()
	if belt == null:
		print("FAIL: there is no belt in the van")
		return _advance()

	var barred: bool = belt.has_bars()
	_expect(barred, "the belt is barred in the parked van")
	var slots: int = belt.slot_count()
	for index in slots:
		var is_barred: bool = belt.is_barred(index)
		_expect(is_barred, "slot %d is barred" % index)
		var took_it: bool = belt.equip(index)
		_expect(not took_it, "and asking for slot %d is refused" % index)

	var hands_out: bool = belt.hands_out()
	_expect(hands_out, "so what the player has out is his own hands")
	_expect(belt.hands() != null, "which he still has")
	return _advance()

## And it is given back on the way out: the road is where the crew tries what it
## bought.
##
## The van the bench has been reading up to here was added to `root` by hand, so
## that its geometry could be measured without a phase change in the way. A real
## phase change loads a van of its own as the tree's `current_scene`, and two
## vans in the tree at once means two players in the `player` group — with the
## belt that gets unbarred belonging to the new one and the belt being asked
## about belonging to the old. So the bench's own van is taken down first, and
## what is checked afterwards is the belt of whoever is actually standing in the
## scene.
func _check_the_belt_comes_back() -> bool:
	if _clock == 1:
		_van.queue_free()
		_van = null
		return false
	if _clock == 2:
		_phase.scenes[Phase.Type.TRAVEL] = VAN
		_phase.go_to(Phase.Type.TRAVEL)
		return false
	if _clock < WAIT * 2:
		return false

	var player := root.get_tree().get_first_node_in_group("player")
	if player == null:
		print("FAIL: nobody is standing in the scene after the phase change")
		return _advance()
	var belt: Node = player.inventory
	var barred: bool = belt.has_bars()
	_expect(not barred, "leaving the lobby unbars the belt")
	var slots: int = belt.slot_count()
	var took_it: bool = belt.equip(0)
	_expect(took_it or slots == 0, "and a slot can be asked for again")
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
	return true
