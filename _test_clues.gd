extends SceneTree
## Bench for the clue system: burrow pairs, dropping trails, streaks of piss and
## the rubbish the rats raid.
##
## Autoloads are fetched off `root` in the first `_physics_process` and not by
## their global names: the `MainLoop` script is compiled before the autoloads are
## in the tree, so `ClueManager` does not exist as an identifier here. Phases are
## written as plain integers for the same reason — `Phase.Type` is another
## project script this bench cannot name (LOBBY 0, TRAVEL 1, SURVEY 2, HUNT 3).

var _frame := 0
var _world: Node
var _session: Node
var _phase_manager: Node
var _stock: Node
var _clue: Node
var _lobby: Node
var _traps: Node
var _steam_id := 0
var _failures: Array[String] = []
var _streaks_at_survey := 0


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_open_house()
		20:
			_check_survey()
		24:
			_drop_bait()
		30:
			_check_bait()
			_start_hunt()
		40:
			_check_hunt()
			_check_marking()
		46:
			_check_streak_bite()
		50:
			_corner_a_rat()
		260:
			_check_bolt()
			_set_up_lure()
		266:
			_check_lure()
			_check_no_dribble()
			_check_spray_decision()
			_check_spray_cone()
			_check_splatter()
			_start_windup()
		320:
			_check_windup()
			_finish()
			return true
	_watch_bolt()
	return false


func _open_house() -> void:
	_session = root.get_node_or_null("SessionManager")
	_phase_manager = root.get_node_or_null("PhaseManager")
	_stock = root.get_node_or_null("Stock")
	_clue = root.get_node_or_null("ClueManager")
	_traps = root.get_node_or_null("TrapManager")
	_lobby = root.get_node_or_null("LobbyManager")
	_steam_id = _lobby.our_steam_id()
	# The house opens during the survey, which is the phase the clues are for.
	_session.phase = 2
	_session.random_seed = 12345
	_stock.add("rat_bait", 3)
	var packed: PackedScene = load("res://scenes/world.tscn")
	_world = packed.instantiate()
	root.add_child(_world)


# --- The survey -------------------------------------------------------------

func _check_survey() -> void:
	var holes := get_nodes_in_group("rat_holes")
	_expect(holes.size() == 6, "six burrows, got %d" % holes.size())

	# Every burrow that names a partner is reachable from the other end too, which
	# is the whole of what `RatHole.linked()` is for.
	var paired := 0
	for node in holes:
		var far_end: Node = node.linked()
		if far_end == null:
			continue
		paired += 1
		_expect(far_end.linked() == node,
			"%s <-> %s reads from both ends" % [node.name, far_end.name])
	_expect(paired == 6, "all six burrows paired, got %d" % paired)

	# Every burrow stands in a wall, with its slit on the wall face and the pace
	# of floor it is entered from inside the room.
	var map := (holes[0] as Node3D).get_world_3d().navigation_map
	for node in holes:
		var hole: Node3D = node
		var at: Vector3 = hole.global_position
		var on_a_wall := absf(absf(at.x) - 30.0) < 0.01 or absf(absf(at.z) - 30.0) < 0.01
		_expect(on_a_wall, "%s is in a wall (%.1f, %.1f)" % [hole.name, at.x, at.z])
		var stand: Vector3 = hole.mouth()
		_expect(stand.length() < at.length(), "%s opens into the room" % hole.name)
		# And that pace of floor is somewhere a rat can actually stand.
		var snapped := NavigationServer3D.map_get_closest_point(map, stand)
		var off := Vector2(snapped.x - stand.x, snapped.z - stand.z).length()
		_expect(off < 0.2, "%s is entered from the mesh, %.2f m off" % [hole.name, off])

	var piles := get_nodes_in_group("garbage")
	_expect(piles.size() == 5, "five heaps of rubbish, got %d" % piles.size())
	for pile in piles:
		_expect(pile.is_in_group("lures"), "%s pulls on its own" % pile.name)

	var droppings := _world.get_node_or_null("Clues/Droppings")
	_expect(droppings != null and droppings.get_child_count() > 0,
		"droppings laid, got %d piles" % (droppings.get_child_count() if droppings else -1))

	# Nothing that belongs on the boards is hanging in the air. The navigation mesh
	# this house bakes sits at y = 0.20 and the floor is at y = 0, which is exactly
	# the mistake `ClueManager.on_the_boards` exists to stop.
	var highest := -99.0
	for i in droppings.get_child_count():
		highest = maxf(highest, (droppings.get_child(i) as Node3D).global_position.y)
	_expect(highest < 0.05, "the droppings are on the floor, highest y = %.3f" % highest)

	var streaks := get_nodes_in_group("streaks")
	_streaks_at_survey = streaks.size()
	# One per run and no more. Twelve was a burst sewer; three was a house the crew
	# walked straight through.
	var runs: Array = _clue.rat_runs()
	_expect(streaks.size() == runs.size(),
		"one streak per run, %d streaks for %d runs" % [streaks.size(), runs.size()])
	var wettest := -99.0
	for node in streaks:
		wettest = maxf(wettest, (node as Node3D).global_position.y)
	_expect(wettest < 0.05, "and the streaks are on it too, highest y = %.3f" % wettest)

	# Every streak lies out on a run, and lies along it. A smear has a direction,
	# and the direction is only a clue if it came from the route.
	var adrift := 0
	var crooked := 0
	for node in streaks:
		var streak: Node3D = node
		var closest := 99.0
		var heading := Vector3.FORWARD
		for run in runs:
			for i in range(1, (run as PackedVector3Array).size()):
				var from: Vector3 = run[i - 1]
				var to: Vector3 = run[i]
				var on_leg := Geometry3D.get_closest_point_to_segment(
					streak.global_position, from, to)
				var away := on_leg.distance_to(streak.global_position)
				if away >= closest:
					continue
				closest = away
				var leg := to - from
				leg.y = 0.0
				if not leg.is_zero_approx():
					heading = leg.normalized()
		if closest > 1.0:
			adrift += 1
			continue
		var forward := -streak.global_basis.z
		forward.y = 0.0
		if forward.normalized().dot(heading) < 0.9:
			crooked += 1
	_expect(adrift == 0, "all of them out on a run, %d adrift" % adrift)
	_expect(crooked == 0, "and all of them lying along it, %d crooked" % crooked)

	_check_streaks_are_drawn(streaks)

	# The tub is on the van's shelf like everything else he can spend, and it hangs
	# on the belt like everything else he can put down.
	var shop: Node = root.get_node_or_null("ShopManager")
	var item: Resource = shop.find("rat_bait")
	_expect(item != null, "the shelf sells rat bait")
	_expect(item != null and item.weapon_node == "RatBait",
		"and there is a weapon on the belt for it")
	var player: Node3D = get_first_node_in_group("player")
	_expect(player.get_node_or_null("Head/RatBait") != null,
		"which the player is dressed with")


## Where the crew put its food. Nothing about the level chose this spot: it is a
## patch of open floor in the middle of the map, which is the whole point of the
## bait being a thing the player drops rather than a thing he pours into a bin.
const BAIT_SPOT := Vector3(-18.0, 0.05, -12.0)


func _drop_bait() -> void:
	var player: Node3D = get_first_node_in_group("player")

	# First from across the house, which the host refuses: a client naming a spot
	# in a room nobody has walked into is the thing the reach check is for.
	player.global_position = Vector3(7.0, 0.68, 24.0)
	_traps.request_place(_steam_id, "rat_bait", BAIT_SPOT, Vector3.FORWARD)
	_expect(_bait_piles().is_empty(), "bait asked for across the house is refused")
	_expect(_stock.count("rat_bait") == 3, "and costs him nothing")

	# Then from where a man could actually have reached.
	player.global_position = BAIT_SPOT + Vector3(1.5, 0.68, 0.0)
	_traps.request_place(_steam_id, "rat_bait", BAIT_SPOT, Vector3.FORWARD)


## Every handful of food the crew has dropped. The heaps of rubbish are lures too,
## so the group alone is not the answer.
func _bait_piles() -> Array:
	var found := []
	for node in get_nodes_in_group("lures"):
		if node is BaitPile:
			found.append(node)
	return found


func _check_bait() -> void:
	var piles := _bait_piles()
	_expect(piles.size() == 1, "the food is on the floor where he pointed")
	if piles.is_empty():
		return
	var pile: Node3D = piles[0]
	_expect(pile.global_position.distance_to(BAIT_SPOT) < 0.01,
		"on the spot and not at the origin")
	_expect(_stock.count("rat_bait") == 2,
		"one tub left the bag, %d remain" % _stock.count("rat_bait"))
	_expect(pile.placed_by == _steam_id, "and it knows whose it is")


# --- The hunt ---------------------------------------------------------------

func _start_hunt() -> void:
	_session.phase = 3
	_phase_manager.phase_changed.emit(2, 3)


func _check_hunt() -> void:
	var rats := get_nodes_in_group("rats")
	_expect(rats.size() == 6, "six rats out, got %d" % rats.size())

	# Every animal came out of a nest — a burrow mouth or a heap of rubbish — and
	# none of them out of a wall or the origin.
	var nests: Array[Vector3] = []
	for node in get_nodes_in_group("rat_holes"):
		nests.append((node as Node3D).mouth())
	for node in get_nodes_in_group("garbage"):
		nests.append((node as Node3D).global_position)
	var stray := 0
	var markers := 0
	for rat in rats:
		var closest := 99.0
		for nest in nests:
			closest = minf(closest, (rat as Node3D).global_position.distance_to(nest))
		if closest > 1.5:
			stray += 1
		if rat.species != null and rat.species.sprays:
			markers += 1
			_sprayer = rat
	_expect(stray == 0, "every rat came out of a nest, %d did not" % stray)
	_expect(markers > 0, "a spraying breed is in the walls, got %d" % markers)
	_expect(markers < rats.size(), "not every rat is a sprayer, got %d" % markers)


func _check_marking() -> void:
	var before := get_nodes_in_group("streaks").size()
	_clue.mark(Vector3(0.0, 0.1, 0.0))
	var after := get_nodes_in_group("streaks").size()
	_expect(after == before + 1,
		"a mark wets the floor, %d -> %d" % [before, after])


## **The check that would have caught the puddle nobody could find.** Every
## surface in the game is drawn through the PS1 shader, which is hung on it at
## runtime by the applier at the root of the world, and that shader writes
## `ALPHA_SCISSOR_THRESHOLD = alpha_scissor` — so a material whose albedo alpha is
## below that threshold has every one of its fragments discarded and is never
## drawn at all. The first puddle in this game was a translucent disc at alpha 0.6
## against a scissor of 1.0: it existed, it hurt people, it was in the right place,
## and it was invisible on every machine in every frame.
func _check_streaks_are_drawn(streaks: Array) -> void:
	var invisible := 0
	var checked := 0
	for node in streaks:
		for child in (node as Node3D).get_children():
			var mesh := child as MeshInstance3D
			if mesh == null:
				# The stain hangs under its own node so it can be scaled as one.
				for grandchild in child.get_children():
					var inner := grandchild as MeshInstance3D
					if inner != null:
						checked += 1
						if not _is_drawn(inner):
							invisible += 1
				continue
			checked += 1
			if not _is_drawn(mesh):
				invisible += 1
	_expect(checked > 0, "the streaks have lines to draw, %d surfaces" % checked)
	_expect(invisible == 0,
		"and the shader draws all of it, %d scissored away" % invisible)

	# What you see is what hurts: the lines are modelled at `BASE_RADIUS` and scaled
	# by the ratio, so the drawing follows the bite rather than drifting from it.
	var streak: Node3D = streaks[0]
	var stain: Node3D = streak.get_node_or_null("Stain")
	var wanted: float = streak.radius / RatStreak.BASE_RADIUS
	_expect(stain != null and is_equal_approx(stain.scale.x, wanted),
		"the lines are drawn at the radius that bites, %.2f vs %.2f"
			% [stain.scale.x if stain != null else -1.0, wanted])
	# And the longest line fits inside that bite, so nothing is drawn on ground
	# that does not hurt.
	var reach := 0.0
	for line in stain.get_children():
		var mesh := line as MeshInstance3D
		if mesh == null:
			continue
		var box := mesh.mesh as BoxMesh
		reach = maxf(reach, box.size.z * 0.5 * wanted)
	_expect(reach <= streak.radius,
		"the lines fit inside it, %.2f m of line in %.2f m" % [reach, streak.radius])
	_expect(streak.get_node_or_null("Hiss") != null
			and (streak.get_node("Hiss") as AudioStreamPlayer3D).stream != null,
		"and it makes a noise when it bites")


## Whether a surface survives the PS1 shader's alpha scissor. Anything painted
## with less alpha than the threshold is discarded fragment by fragment, which
## looks exactly like a node that was never added.
func _is_drawn(mesh: MeshInstance3D) -> bool:
	var mat := mesh.get_surface_override_material(0)
	if mat == null:
		mat = mesh.material_override
	if mat == null and mesh.mesh != null:
		mat = mesh.mesh.surface_get_material(0)
	if mat is ShaderMaterial:
		var shader_mat: ShaderMaterial = mat
		var color = shader_mat.get_shader_parameter("albedo_color")
		var scissor = shader_mat.get_shader_parameter("alpha_scissor")
		if color == null:
			return true
		return float(color.a) >= (1.0 if scissor == null else float(scissor))
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_color.a >= 1.0
	return true


func _check_streak_bite() -> void:
	var streak: Node3D = get_nodes_in_group("streaks")[0]
	var player: Node3D = get_first_node_in_group("player")
	var whole: int = player.health()
	player.global_position = streak.global_position + Vector3(0.0, 0.68, 0.0)
	# One tick of the puddle's own clock, plus a frame for it to land.
	var wait: float = streak.tick + 0.1
	var elapsed := 0.0
	while elapsed < wait:
		elapsed += 1.0 / 60.0
		streak._physics_process(1.0 / 60.0)
	_expect(player.health() < whole,
		"standing in it costs flesh, %d -> %d" % [whole, player.health()])

	# And standing a stride off it costs nothing. This is the check that proves the
	# radius actually shrank: at the old 0.95 m the player would still be in it.
	var clear: int = player.health()
	player.global_position = streak.global_position + Vector3(0.6, 0.68, 0.0)
	elapsed = 0.0
	while elapsed < wait:
		elapsed += 1.0 / 60.0
		streak._physics_process(1.0 / 60.0)
	_expect(player.health() == clear, "a stride off it costs nothing")

	player.global_position = streak.global_position + Vector3(12.0, 0.68, 0.0)
	elapsed = 0.0
	while elapsed < wait:
		elapsed += 1.0 / 60.0
		streak._physics_process(1.0 / 60.0)
	_expect(player.health() == clear, "out of reach it costs nothing")


# --- Bolting through the walls ----------------------------------------------

## The spraying breed, picked out of the hunt, and what the flesh read before the
## wind-up started.
var _sprayer: Node3D
var _health_before_windup := 0

## `State.SPRAYING` as a plain integer. `rat.gd` carries no `class_name`, so a
## bench cannot name its enum — and the value is the wire format anyway, so
## writing it out is the honest spelling. WANDERING 0, IDLE 1, FLEEING 2,
## HIDING 3, CAPTURED 4, DEAD 5, SPRAYING 6.
const SPRAYING := 6


## Which rat the bolt test is being run on, and where it has to end up.
var _bolter: Node3D
var _far_end: Node3D
## How far off the far mouth the animal was **on the frame it came through**, or
## -1 while it has not. Latched rather than measured at the end: the dive does not
## end the flight, so a rat checked three seconds later has quite properly run
## several metres on from where it surfaced.
var _bolt_distance := -1.0


## Watches for the dive. `_bolt_time` going positive is the one unambiguous sign
## that `_dive_into` ran, and it is only ever set there.
func _watch_bolt() -> void:
	if _bolter == null or _bolt_distance >= 0.0 or _bolter._bolt_time <= 0.0:
		return
	_bolt_distance = _bolter.global_position.distance_to(_far_end.mouth())
	print("  ..   dove through on frame %d" % _frame)


## Puts one rat beside a burrow with a man four strides off it. The burrow leads
## clean across the map, so diving in is the best thing available to the animal
## and the far mouth is what it should be standing at.
func _corner_a_rat() -> void:
	var holes := get_nodes_in_group("rat_holes")
	var mouth: Node3D = null
	for node in holes:
		if node.name == "HoleHallway":
			mouth = node
	_far_end = mouth.linked()

	_bolter = get_nodes_in_group("rats")[0]
	_bolter.global_position = Vector3(-27.0, 0.1, 4.0)
	_bolter._bolt_time = 0.0
	# Inside the rat's own `panic_radius` (6 m) so it bolts without needing to see
	# him, and more than that away from the burrow so the burrow is not itself a
	# place it is running from.
	var player: Node3D = get_first_node_in_group("player")
	player.global_position = Vector3(-27.0, 0.68, 0.0)


func _check_bolt() -> void:
	_expect(_bolt_distance >= 0.0, "the cornered rat took the burrow")
	_expect(_bolt_distance >= 0.0 and _bolt_distance < 3.0,
		"it came out at %s, %.1f m off it" % [_far_end.name, _bolt_distance])
	# And it is still running, from the far end of the house rather than from the
	# corner it was cornered in: a burrow is a way out, not a hiding place.
	var mouth := _bolter.global_position.distance_to(Vector3(-30.0, 0.0, 9.0))
	_expect(mouth > 20.0, "and is nowhere near where it went in, %.1f m" % mouth)
	_expect(_bolter._bolt_time > 0.0, "and will not dive straight back in")


# --- The pull of the food ---------------------------------------------------

## Puts a rat in smelling distance of the heap the crew baited, with nobody near
## it, and asks it where it fancies strolling. The pull is a preference and not a
## command (`LURE_PULL`), so what is checked is that the food wins some of the
## rolls rather than all of them.
func _set_up_lure() -> void:
	var player: Node3D = get_first_node_in_group("player")
	player.global_position = Vector3(7.0, 0.68, 24.0)
	_bolter.global_position = BAIT_SPOT + Vector3(6.0, 0.05, 4.0)


func _check_lure() -> void:
	var drawn := 0
	for _roll in 30:
		_bolter._pick_wander_target()
		if not _bolter._has_target:
			continue
		if _bolter._target.distance_to(BAIT_SPOT) < 4.0:
			drawn += 1
	_expect(drawn > 0, "the dropped bait draws a calm rat, %d of 30 rolls" % drawn)
	_expect(drawn < 30, "but not every roll, %d of 30" % drawn)


# --- The spraying breed -----------------------------------------------------

## Nothing drips any more. The breed used to wet the floor every nine to sixteen
## seconds while it wandered, which is what filled the map with piss nobody saw an
## animal make; every fresh mark is now a spray somebody was standing in front of.
##
## Asserted as an absence, which is the honest test for a thing that was deleted:
## if `_wet_the_floor` ever comes back this fails on the spot.
func _check_no_dribble() -> void:
	_expect(not _sprayer.has_method("_wet_the_floor"),
		"the breed no longer dribbles as it walks")


## When it decides to turn round. A pure predicate over positions — no frames, no
## navigation mesh, no wire — which is the whole reason the decision was split out
## of the flight into `_should_spray()`.
func _check_spray_decision() -> void:
	var player: Node3D = get_first_node_in_group("player")
	_sprayer.global_position = Vector3(-8.0, 0.1, 6.0)
	_sprayer._spray_time = 0.0

	player.global_position = _sprayer.global_position + Vector3(1.5, 0.68, 0.0)
	_expect(_sprayer._should_spray(), "a man at a stride and a half gets sprayed")

	player.global_position = _sprayer.global_position + Vector3(5.0, 0.68, 0.0)
	_expect(not _sprayer._should_spray(), "a man across the room does not")

	player.global_position = _sprayer.global_position + Vector3(1.5, 0.68, 0.0)
	_sprayer._spray_time = 3.0
	_expect(not _sprayer._should_spray(), "and neither does one it just sprayed")
	_sprayer._spray_time = 0.0


## Where it lands. `_spray_at` is the far end of the wire and takes two plain
## arguments, so the cone can be fired at a standing player without waiting for an
## animal to decide anything. With no peer, `get_remote_sender_id()` is zero and
## the sender check lets it through — the same road a solo hunt takes.
func _check_spray_cone() -> void:
	var player: Node3D = get_first_node_in_group("player")
	var from := Vector3(-8.0, 0.1, 6.0)
	var facing := Vector3.RIGHT

	var whole: int = player.health()
	player.global_position = from + Vector3(1.5, 0.68, 0.0)
	_sprayer._spray_at(from, facing)
	_expect(player.health() < whole,
		"a faceful costs flesh, %d -> %d" % [whole, player.health()])

	# Behind it. A rat sprays what it is looking at and nothing else.
	var after: int = player.health()
	player.global_position = from + Vector3(-1.5, 0.68, 0.0)
	_sprayer._spray_at(from, facing)
	_expect(player.health() == after, "standing behind it costs nothing")

	# In front but out of reach.
	player.global_position = from + Vector3(6.0, 0.68, 0.0)
	_sprayer._spray_at(from, facing)
	_expect(player.health() == after, "and out of range costs nothing")


## The wind-up: the third of a second that makes the whole thing dodgeable. The
## state is entered here and stepped by hand, so the check is about the clock and
## not about whether an animal happened to corner anybody.
func _start_windup() -> void:
	var player: Node3D = get_first_node_in_group("player")
	_sprayer.global_position = Vector3(-8.0, 0.1, 6.0)
	_sprayer._spray_time = 0.0
	player.global_position = _sprayer.global_position + Vector3(1.2, 0.68, 0.0)
	_health_before_windup = player.health()
	_streaks_before_windup = get_nodes_in_group("streaks").size()
	_sprayer._change_state(SPRAYING)
	# One frame of it. Far short of the wind-up, so nothing may have landed yet.
	_sprayer._process_spray(1.0 / 60.0)
	_expect(player.health() == _health_before_windup,
		"the wind-up hurts nobody on its own")
	_expect(_sprayer.animator.current_animation == "Rat|Attack",
		"and the animal is visibly rearing up, playing %s"
			% _sprayer.animator.current_animation)


var _streaks_before_windup := 0


## Half a second of real physics later. The wind-up and the recovery are the state
## machine's own clocks, so they are left to run rather than turned by hand — a
## bench that cranks them is testing its own arithmetic.
func _check_windup() -> void:
	var player: Node3D = get_first_node_in_group("player")
	_expect(player.health() < _health_before_windup,
		"and then it lands, %d -> %d" % [_health_before_windup, player.health()])
	_expect(get_nodes_in_group("streaks").size() == _streaks_before_windup + 1,
		"leaving a fresh mark on the boards")
	_expect(_sprayer._spray_time > 0.0, "and it will not do it again straight away")


## Piss on the lens. Asserted on the state behind the drawing and never on pixels:
## `_draw` may not run at all under the headless renderer.
func _check_splatter() -> void:
	var player: Node3D = get_first_node_in_group("player")
	var lens: Node = get_first_node_in_group("player").get_tree() \
		.current_scene if false else _find_splatter()
	if lens == null:
		_expect(false, "the HUD has a lens to splatter")
		return
	lens.clear()
	player.splash()
	_expect(lens.visible and lens.spot_count() > 0,
		"a faceful lands on the lens, %d spots" % lens.spot_count())
	# And it does not outlive the body it was on.
	player.died.emit()
	_expect(lens.spot_count() == 0, "and a respawn wipes it")


func _find_splatter() -> Node:
	for node in _world.get_children():
		var found := node.get_node_or_null("Splatter")
		if found != null:
			return found
	return null


# --- Reporting --------------------------------------------------------------

func _expect(condition: bool, what: String) -> void:
	if condition:
		print("  ok   %s" % what)
		return
	_failures.append(what)
	print("  FAIL %s" % what)


func _finish() -> void:
	if _failures.is_empty():
		print("\nclues: every check passed")
		return
	print("\nclues: %d FAILED" % _failures.size())
	for failure in _failures:
		print("  - %s" % failure)
