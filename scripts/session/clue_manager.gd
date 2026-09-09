extends Node
## Where the rat piss is, and the one rule about it: nobody wets the floor of the
## house but the host, and everybody walks the same floor.
##
## Of the four things the crew can read off a house, three need nothing from here:
##
## - **Burrows** (`scripts/house/rat_hole.gd`) stand in the walls and are part of
##   the level.
## - **Rubbish** (`scripts/house/garbage_pile.gd`) is part of the level too, and
##   the crew does nothing to it.
## - **Droppings** (`scripts/house/dropping_trail.gd`) are dirt: nothing catches,
##   nothing changes, and every machine works out the same trail for itself off
##   the same seed, the same mesh and `on_the_boards` below. They are laid down
##   the routes `rat_runs()` answers with, and so is the piss — the two are only a
##   clue together.
##
## **The piss is the exception, and this is why.** A streak hurts whoever stands
## on it, and one that existed on a single screen would be a man taking damage his
## crew cannot see him take. So where they lie is decided in one place — here, on
## the host — and they arrive on every machine through the `MultiplayerSpawner`
## over the `Streaks` container, with the spot and the heading in the spawn
## dictionary, because a streak never moves again after it lands and a
## synchroniser on it would buy a packet a frame for ever to repeat two numbers.
##
## **The wound itself is nobody's business but the man who took it.** `RatStreak`
## measures its own machine's player and hurts him locally. There is no damage on
## the wire, and there should not be: flesh, money and stock are all
## single-player autoloads holding whatever belongs to whoever is at this desk.
##
## The bait the crew buys is **not** here. It is a thing a player leaves on the
## boards, which is `TrapManager`'s trade, and it goes down through the same
## checks and the same spawner as a mousetrap (`scripts/traps/bait_pile.gd`).

## The peer that decides. Peer 1 everywhere in this project — Godot hands it to
## the host the moment the wire comes up, and it is a surer answer than a Steam
## ID that may not have been introduced yet.
const HOST_PEER := 1

## The streak scene, registered on the `StreakSpawner` in `world.tscn`. A spawner
## refuses to replicate a scene that is not on its list, so the two have to agree.
const STREAK_SCENE := "res://scenes/clues/rat_streak.tscn"

## The longest walk worth calling a run, in metres. A burrow whose nearest food is
## on the other side of the map is not one its animals are making the trip to, and
## a trail drawn across the whole house is a clue that says nothing.
const MAX_RUN := 34.0

## How many frames to give the navigation mesh before laying anything on it. It is
## baked in `scripts/navigation.gd::_ready` and only answers queries after the
## server's first sync — the same wait `rat.gd::_map_ready` makes and
## `DroppingTrail` sits through.
const BAKE_WAIT := 4

## Where along a run the old streak is left, as a fraction of its length. Not at
## either end: the burrow mouth and the bin are both already marked by everything
## else about them, and the point of the streak is that it is out on the open
## floor between the two, where a man following the droppings is walking and not
## looking down.
const RUN_FROM := 0.25
const RUN_TO := 0.85

## How close to the front door a streak may be left. Nobody should walk out of the
## van into one before the shift has started.
const SPAWN_CLEARANCE := 8.0

## Nowhere: what the spot search gives back when the rolls ran out. Spelled the
## way `rat.gd` spells it.
const INVALID_POINT := Vector3.INF

## How far above and below a point to look for the boards, and how far into them
## whatever lands there is settled. See `on_the_boards`.
const BOARD_PROBE := 1.2
const BOARD_SINK := 0.012
## The floor and the walls, which is the only layer the boards could be on — the
## same one the navigation mesh is baked from (`world.tscn`).
const SCENERY_LAYER := 1

## How far short of where it was sent a navigation path may end and still count as
## having arrived. Spelled the way `rat.gd::MESH_TOLERANCE` spells it.
const MESH_SLACK := 1.5

## How many streaks the host has named so far. It only ever goes up — two nodes
## fighting over one path is the bug underneath a name reused — and it starts over
## with the shift, because a new house is a dry floor.
var _wet := 0


func _ready() -> void:
	# A streak can land while the game is paused — a pause menu is not a hiding
	# place from the wire — so the packet still has to be read. Same as
	# `PhaseManager`, `ReadyManager` and `TrapManager`.
	process_mode = Node.PROCESS_MODE_ALWAYS
	PhaseManager.phase_changed.connect(_on_phase_changed)

# --- Where the rats run -----------------------------------------------------

## The routes the animals have been walking since long before the van pulled up:
## one per burrow, from the pace of floor in front of its slit (`RatHole.mouth`)
## to the nearest heap of rubbish, along the navigation mesh they will actually
## walk it on.
##
## **It lives here because two things have to agree about it.** The droppings are
## laid down these routes (`scripts/house/dropping_trail.gd`) and so is the piss
## (`scatter_streaks`), and the two are only a clue *together* — follow the mess
## and you arrive at a burrow at one end and a bin at the other. Two copies of
## "which bin does this burrow raid" would drift apart the first time either was
## tuned, and the crew would be reading two different houses.
##
## It is a pure function of the level and the mesh: no state, no order, no clock.
## Either caller may ask whenever it is ready, which is what keeps the two nodes
## from having to be woken in a particular order.
##
## A burrow with no rubbish in reach falls back on the far mouth of its own run,
## so a pair still reads as a pair in a house with no bins in it at all. Paths
## that come back with fewer than two points are dropped: there is no route.
func rat_runs() -> Array[PackedVector3Array]:
	var runs: Array[PackedVector3Array] = []
	var tree := get_tree()
	if tree == null:
		return runs
	var map := _navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) <= 0:
		return runs

	for node in tree.get_nodes_in_group("rat_holes"):
		var hole := node as RatHole
		if hole == null:
			continue
		var destination := _raided_by(hole)
		if destination == null:
			continue
		var path := NavigationServer3D.map_get_path(
			map, hole.mouth(), destination.global_position, true)
		if path.size() >= 2:
			runs.append(path)
	return runs


## Where this burrow's rats have been going: the nearest heap of rubbish within
## `MAX_RUN`, or the far mouth of its own run when the house has no rubbish in it.
func _raided_by(hole: RatHole) -> Node3D:
	var nearest: Node3D = null
	var best := MAX_RUN
	for node in get_tree().get_nodes_in_group("garbage"):
		var pile := node as Node3D
		if pile == null:
			continue
		var distance := hole.global_position.distance_to(pile.global_position)
		if distance < best:
			best = distance
			nearest = pile
	return nearest if nearest != null else hole.linked()

# --- Streaks ----------------------------------------------------------------

## Lays the old piss down the runs, in a house that has just opened. **Host
## only** — it is called from `house.gd::_ready` — and awaited rather than run on
## the spot, because the navigation mesh is baked a frame or two earlier and does
## not answer queries until the server's first sync.
##
## **One per run, and no more.** This has been wrong twice and both mistakes are
## worth remembering. It began as three stains rolled uniformly at random across
## three thousand square metres, which the crew never met. The fix was twelve of
## them ringed around every burrow and bin — which they did meet, and which turned
## the house into a burst sewer, because a disc two metres across is ten times the
## length of the animal that made it. What is left now is the honest amount: a
## rat crossing open floor between its hole and its dinner dribbles once on the
## way, so there is one streak on each run, out in the middle where a man
## following the droppings is watching the droppings.
##
## The streak is turned along the leg of the path it sits on, so the lines point
## the way the animal went. That is the whole reason it is laid off `rat_runs()`
## rather than rolled somewhere: a smear has a direction, and a direction is only
## true if it came from the route.
func scatter_streaks() -> void:
	if not PhaseManager.is_host():
		return
	var tree := get_tree()
	if tree == null:
		return
	for _frame in BAKE_WAIT:
		await tree.process_frame
	# The house was closed while we waited — a peer dropped, somebody walked out
	# — and there is no floor left to mark.
	if streaks_root() == null:
		return

	var doorstep := _doorstep()
	for run in rat_runs():
		var at := _along(run, randf_range(RUN_FROM, RUN_TO))
		if at == INVALID_POINT:
			continue
		if doorstep != INVALID_POINT and at.distance_to(doorstep) < SPAWN_CLEARANCE:
			continue
		_spawn_streak(at, _heading_at(run, at))


## The point a given fraction of the way along a path, walked corner to corner so
## that a route with one long leg and three short ones is measured by its length
## and not by its number of corners.
func _along(path: PackedVector3Array, fraction: float) -> Vector3:
	if path.size() < 2:
		return INVALID_POINT
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	if total <= 0.001:
		return INVALID_POINT
	var wanted := total * clampf(fraction, 0.0, 1.0)
	var walked := 0.0
	for i in range(1, path.size()):
		var leg := path[i - 1].distance_to(path[i])
		if walked + leg >= wanted:
			return path[i - 1].lerp(path[i], (wanted - walked) / leg)
		walked += leg
	return path[-1]


## Which way the animal was going when it passed a point: the direction of the leg
## that point sits on, flattened. `Vector3.FORWARD` for a path with nothing to
## measure, which is a streak left pointing an arbitrary way rather than one that
## refuses to exist.
func _heading_at(path: PackedVector3Array, at: Vector3) -> Vector3:
	var best := Vector3.FORWARD
	var closest := INF
	for i in range(1, path.size()):
		var from := path[i - 1]
		var to := path[i]
		var on_leg := Geometry3D.get_closest_point_to_segment(at, from, to)
		var distance := on_leg.distance_to(at)
		if distance >= closest:
			continue
		var leg := to - from
		leg.y = 0.0
		if leg.is_zero_approx():
			continue
		closest = distance
		best = leg.normalized()
	return best


## A fresh streak, where a sprayer has just caught somebody
## (`rat.gd::_spray_at`). **Host only**: every rat thinks on the host, so this is
## only ever called there, and the guard is what keeps a guest that somehow gained
## authority over an animal from writing on everybody's floor.
##
## `facing` is which way the spray went, so the mark it leaves lies the same way
## as the ones laid on the runs.
func mark(at: Vector3, facing := Vector3.FORWARD) -> void:
	if not PhaseManager.is_host():
		return
	_spawn_streak(at, facing)


## The streak itself. There is no `rpc` here on purpose: the `MultiplayerSpawner`
## over the `Streaks` container is what carries the node to the other machines,
## and where it lies travels **as spawn data** (`_build_streak`) because a streak
## never moves again after it lands.
func _spawn_streak(at: Vector3, facing: Vector3) -> void:
	var spawner := _spawner()
	if spawner == null:
		return
	_wet += 1
	spawner.spawn({"n": _wet, "at": on_the_boards(at), "facing": facing})


## The same spot, dropped onto whatever surface is actually under it.
##
## **Nothing that belongs on the floor should be positioned off a navigation
## point.** The mesh is not the floor: it is baked with a cell height and an agent
## radius, and in `world.tscn` it comes out a fifth of a metre in the air — which
## is where the piss and the droppings were both hanging before this existed.
## It is not a constant to subtract, either; it is whatever the bake happened to
## round to, and a ramp or a platform rounds to something else.
##
## So the answer is asked of the physics instead: a short ray straight down onto
## the scenery layer, which is the same geometry the mesh was baked from
## (`scripts/navigation.gd`). With nothing under it — a point out over a hole in
## the floor, a bench with no scenery in it — the spot is handed back untouched,
## because a guess is worse than the number we were given.
##
## The result is sunk by `BOARD_SINK` rather than laid exactly on the surface. A
## level's collision and its visible floor need not agree to the millimetre —
## `world.tscn`'s plane sits two centimetres under its own collision box — and a
## small prop half in the boards reads correctly either way round, where one
## balanced on top of them floats the moment they disagree.
func on_the_boards(point: Vector3) -> Vector3:
	var root := streaks_root()
	if root == null:
		return point
	var world := root.get_world_3d()
	if world == null:
		return point
	var from := point + Vector3.UP * BOARD_PROBE
	var to := point - Vector3.UP * BOARD_PROBE
	var params := PhysicsRayQueryParameters3D.create(from, to, SCENERY_LAYER)
	var hit := world.direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return point
	return (hit.position as Vector3) - Vector3.UP * BOARD_SINK


## Builds one streak out of what came over the wire. **This runs on every
## machine** — it is the spawner's `spawn_function`, so the host runs it when
## `spawn()` is called and each guest runs it when the packet lands, with the same
## dictionary in hand.
##
## Everything is settled before the node is handed back, because the spawner adds
## it to the container the moment this returns. A pose written after that is a
## pose written on a streak that has already been in the world for a frame — and
## on the host, one that has already had a chance to burn somebody standing at the
## origin.
func _build_streak(data: Variant) -> Node:
	var fields := data as Dictionary
	if fields == null:
		return null
	if not ResourceLoader.exists(STREAK_SCENE):
		return null
	var packed := ResourceLoader.load(STREAK_SCENE) as PackedScene
	if packed == null:
		return null
	var streak := packed.instantiate() as Node3D
	if streak == null:
		return null
	# Named off the host's counter rather than left to the engine's `@Node3D@31`:
	# two nodes fighting over one path is the bug underneath every guest that
	# stops hearing about something.
	streak.name = "Streak_%d" % int(fields.get("n", 0))
	streak.set_multiplayer_authority(HOST_PEER)
	# `position` and not `global_position`: the node is not in the tree yet, and a
	# global write before it has a parent is a write onto nothing. The container
	# sits at the origin, so the two are the same number.
	streak.position = fields.get("at", Vector3.ZERO)
	var facing: Vector3 = fields.get("facing", Vector3.FORWARD)
	facing.y = 0.0
	if not facing.is_zero_approx():
		streak.basis = Basis.looking_at(facing, Vector3.UP)
	return streak


## Where the crew comes in. It is both the spot nothing is scattered on top of and
## the place every candidate has to be walkable from (`_reachable`), so it is worth
## being found reliably: `HouseSpawns` puts itself in the `house_spawns` group on
## the way up, which answers in the game and in the benches alike.
##
## Nowhere — spelled `INVALID_POINT` — in a world with no spawn markers in it. Both
## checks are then skipped rather than guessed at, because a world with no doorstep
## has no crew in it to protect.
func _doorstep() -> Vector3:
	var tree := get_tree()
	if tree == null:
		return INVALID_POINT
	var spawns := tree.get_first_node_in_group("house_spawns") as Node3D
	if spawns == null:
		return INVALID_POINT
	for child in spawns.get_children():
		var marker := child as Marker3D
		if marker != null:
			return marker.global_position
	return INVALID_POINT

# --- Where things live ------------------------------------------------------

## Where the streaks go: the `Streaks` node in `world.tscn`, which is the one the
## `MultiplayerSpawner` is watching. Found by **group** and not by path, for the
## same reason `TrapManager.traps_root` is — the benches instance `world.tscn`
## under the root without ever making it `current_scene`, and a path off
## `current_scene` would quietly miss them.
func streaks_root() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var found := tree.get_first_node_in_group("streaks_root") as Node3D
	if found != null:
		return found
	if tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null(^"Clues/Streaks") as Node3D


## The spawner over that container, with this autoload's builder hung on it. The
## hook is set here rather than in the scene because a `spawn_function` is a
## `Callable` and there is nowhere in a `.tscn` to write one — and setting it
## every time is harmless: it is the same callable, and assigning it again
## changes nothing.
func _spawner() -> MultiplayerSpawner:
	var root := streaks_root()
	if root == null:
		return null
	var spawner := root.get_node_or_null(^"StreakSpawner") as MultiplayerSpawner
	if spawner == null:
		for child in root.get_children():
			spawner = child as MultiplayerSpawner
			if spawner != null:
				break
	if spawner == null:
		return null
	if spawner.spawn_function != _build_streak:
		spawner.spawn_function = _build_streak
	return spawner


## The navigation map the house is walked on. Read off the container's own world
## rather than off a node of ours, because this autoload has no world.
func _navigation_map() -> RID:
	var root := streaks_root()
	if root == null:
		return RID()
	return root.get_world_3d().navigation_map

## A new shift is a dry floor, so the numbering starts over. Watched on the way
## *into* the lobby rather than out of the result: a shift abandoned halfway
## comes back through the lobby too, and that floor is just as dry.
func _on_phase_changed(_previous: Phase.Type, current: Phase.Type) -> void:
	if current == Phase.Type.LOBBY:
		_wet = 0


## Wipes the count, the way `TrapManager.reset()` does: the start of a shift, and
## the start of every test bench.
func reset() -> void:
	_wet = 0
