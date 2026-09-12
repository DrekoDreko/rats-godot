class_name LitterScatter
extends Node3D
## The rubbish strewn across the floor of an infested house, and where it comes
## from.
##
## The heaps of rubbish are level furniture put down by hand
## (`scripts/house/garbage_pile.gd`): a designer chose those spots because the
## trails lead to them and the rats nest in them, and a heap is a dozen of these
## same pieces stacked in one place. **This is the other kind of mess** — the banana skin in the hall, the bin bag split in a corner, the doll
## face down on the landing. It is not a clue and nothing reads it. It is what
## makes a room look lived in and then abandoned, and there is a lot of it.
##
## **Where it lands is asked of the navigation mesh.** The mesh is the floor the
## house actually has — baked from the scenery in `scripts/navigation.gd`, with
## the walls and furniture already cut out of it — so a point sampled from it is
## a point on real, walkable boards. Scattering inside a hand-drawn box instead
## would put rubbish inside walls in one house and leave whole rooms bare in the
## other, and it would have to be re-drawn for every level. This way the same
## node works in `world.tscn` and `world_2.tscn` with nothing configured, and it
## follows the house if the house is rebuilt.
##
## Sampling is done here rather than through `NavigationServer3D.map_get_random_point`
## for one reason, and it is the reason everything in this game that scatters is
## written this way: **the server's random point is drawn from its own generator,
## which no seed of ours reaches.** The polygons are walked and picked by area
## with our own `RandomNumberGenerator`, so the same shift seed lays the same
## rubbish on every machine — the same bargain `DroppingTrail` makes. Nothing
## crosses the wire, because nothing needs to.
##
## Height is not taken from the mesh either. The mesh is baked a fifth of a metre
## up in `world.tscn`, and a ramp rounds somewhere else again, so every piece is
## dropped onto whatever is really underneath it with `ClueManager.on_the_boards`
## — the same call the droppings and the streaks land through.

## The art itself is not listed here. A piece of rubbish is a `FloorLitter` and
## knows what it may be drawn as (`FloorLitter.ART`); this node only decides how
## many there are and where they go.

## How much floor gets one piece, in square metres.
##
## Measured against *walkable* floor and not against the footprint of the house,
## which is the only figure that means anything here: the navigation mesh is
## already cut back from the walls by the rat's radius and holed by every piece of
## furniture, so the two houses come out at 205 and 275 square metres against
## footprints half again as big.
##
## A piece and a half per square metre was tried first and was far too much — a
## room's floor vanished under rubbish and read as a tip rather than as a house
## somebody had stopped cleaning. At five square metres apiece the two houses come
## out around 41 and 55 pieces: several in view in any room, none of them piled.
const AREA_PER_PIECE := 5.0

## The most pieces one house may hold, whatever its floor works out to. A guard
## and not a target: it is what stops a level with a mistakenly enormous
## navigation mesh from laying ten thousand sprites and dropping the frame.
const MAX_PIECES := 400

## How far outside the house's own walls rubbish may still be dropped, in metres.
## A pace, so that a doorway's threshold and the strip of step immediately outside
## it are dressed like the rooms are, and the yard is not.
const OUTSIDE_REACH := 1.0

## How far apart two pieces must be, in metres. Rubbish that piles into the same
## spot reads as one object with a drawing error rather than as two things.
const MIN_GAP := 0.55

## How close to the crew's own doorstep rubbish may be left. The van's ramp and
## the step in front of it are where four people materialise at the start of a
## shift, and a banana skin bouncing under somebody's feet before he has walked
## anywhere is noise.
const SPAWN_CLEARANCE := 4.0

## How many frames to give the navigation mesh before reading it. It is baked in
## `scripts/navigation.gd::_ready` and the region only answers once the server has
## synced — the same wait `DroppingTrail` and `ClueManager` both sit through.
const BAKE_WAIT := 4

## How many times to re-roll a point that landed too close to something already
## down, before giving up on that piece. A handful: the floor is mostly empty at
## these densities, and a piece lost to a crowded corner costs nothing.
const PLACEMENT_TRIES := 6


func _ready() -> void:
	# The tree is held across the wait rather than asked for after it: a phase can
	# arrive off the wire on any of these frames and free this scene, and a node
	# resuming out of the tree has no `get_tree()` left to reach through. Same as
	# `DroppingTrail::_ready`.
	var tree := get_tree()
	if tree == null:
		return
	for _frame in BAKE_WAIT:
		await tree.process_frame
		if not is_inside_tree():
			return
	_strew()


## The rubbish, laid once, when the house opens.
func _strew() -> void:
	var polygons := _floor_polygons()
	if polygons.is_empty():
		return
	var floor_area := 0.0
	for triangle in polygons:
		floor_area += triangle["area"]
	if floor_area <= 0.0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = SessionManager.random_seed

	var wanted := mini(int(floor_area / AREA_PER_PIECE), MAX_PIECES)
	var doorstep := _doorstep()
	var placed: Array[Vector3] = []
	for _piece in wanted:
		var at := _find_spot(polygons, floor_area, placed, doorstep, rng)
		if at == ClueManager.INVALID_POINT:
			continue
		placed.append(at)
		_drop(at, rng)


## A spot for one piece: rolled on the mesh, dropped to the boards, and rejected
## if it landed on the doorstep or on top of something already down. Nowhere —
## spelled the way `ClueManager` spells it — when the rolls ran out.
func _find_spot(polygons: Array, floor_area: float, placed: Array[Vector3],
		doorstep: Vector3, rng: RandomNumberGenerator) -> Vector3:
	for _try in PLACEMENT_TRIES:
		var at := ClueManager.on_the_boards(_sample(polygons, floor_area, rng))
		if doorstep != ClueManager.INVALID_POINT \
				and at.distance_to(doorstep) < SPAWN_CLEARANCE:
			continue
		var crowded := false
		for other in placed:
			if at.distance_to(other) < MIN_GAP:
				crowded = true
				break
		if not crowded:
			return at
	return ClueManager.INVALID_POINT


## One piece of rubbish on the boards.
##
## The sprite is lifted by half its own height so it stands on the floor rather
## than being buried to its waist in it, and joins the `litter` group here rather
## than in its own `_ready`: the group means the rubbish strewn loose across a
## house, which is this node's doing and not every sprite's.
func _drop(at: Vector3, rng: RandomNumberGenerator) -> void:
	var sprite := FloorLitter.piece(rng)
	if sprite == null:
		return
	sprite.position = at + Vector3.UP * (sprite.drawn_height() * 0.5)
	sprite.add_to_group("litter")
	add_child(sprite)


## Every triangle of walkable floor in this house, each with the area it covers.
## The areas are what the sampling is weighted by: picking a triangle uniformly
## would crowd the rubbish into whichever rooms the baker happened to cut into
## many small polygons.
func _floor_polygons() -> Array:
	var region := _navigation_region()
	if region == null:
		return []
	var mesh := region.navigation_mesh
	if mesh == null:
		return []
	var vertices := mesh.get_vertices()
	if vertices.is_empty():
		return []
	var transform := region.global_transform
	var walls := _house_bounds()

	var triangles: Array = []
	for i in mesh.get_polygon_count():
		var indices := mesh.get_polygon(i)
		# Navigation polygons are convex but need not be triangles, so each is
		# fanned from its first corner — the standard decomposition, and the only
		# one that is correct for a convex polygon of any number of sides.
		for corner in range(1, indices.size() - 1):
			var a := transform * vertices[indices[0]]
			var b := transform * vertices[indices[corner]]
			var c := transform * vertices[indices[corner + 1]]
			if not _indoors(walls, (a + b + c) / 3.0):
				continue
			var area := (b - a).cross(c - a).length() * 0.5
			if area <= 0.0:
				continue
			triangles.append({"a": a, "b": b, "c": c, "area": area})
	return triangles


## Whether a patch of floor is part of the house.
##
## **The navigation mesh is not the house, and this is the whole reason this
## check exists.** It is baked from everything in the `scenery` group, which in
## both levels includes the yard the van parks in and the boundary walls around
## it — in `world.tscn` that is two thousand square metres of ground against a
## hundred and fifty of rooms. Scattering across the mesh unfiltered put nine
## pieces out of ten in the garden and a handful on top of the boundary walls
## nineteen metres up. The rubbish is meant to be strewn *through the house*.
##
## The house's own extent is the honest boundary: it is read off the level's
## `House` node rather than written down here, so it is correct in both houses
## and stays correct if either is rebuilt. A pace of slack is left around it
## (`OUTSIDE_REACH`) so a doorway's threshold still counts as indoors, and the
## ceiling is a hard lid — the roof is walkable as far as the baker is concerned,
## and rubbish on the tiles is rubbish nobody will ever stand next to.
func _indoors(walls: AABB, at: Vector3) -> bool:
	if walls.size == Vector3.ZERO:
		return true
	var grown := walls.grow(OUTSIDE_REACH)
	if at.x < grown.position.x or at.x > grown.end.x:
		return false
	if at.z < grown.position.z or at.z > grown.end.z:
		return false
	# Vertically the house is taken as it is: the slack that widens a doorway
	# would otherwise lift the lid a pace above the ridge and let the roof back in.
	return at.y >= walls.position.y - OUTSIDE_REACH and at.y <= walls.end.y


## How big the house is and where it stands, in world space: the box around every
## piece of geometry under the level's `House` node.
##
## An empty box when there is no house — a bench, a level built out of loose
## scenery — and `_indoors` then lets everything through rather than refusing
## everything, because a world with no house in it has nothing to be outside of.
func _house_bounds() -> AABB:
	var root := _level()
	var house := root.get_node_or_null(^"House") as Node3D if root != null else null
	if house == null:
		return AABB()

	var bounds := AABB()
	var started := false
	var pending: Array[Node] = [house]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null and mesh_instance.mesh != null:
			var box := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
			bounds = box if not started else bounds.merge(box)
			started = true
		for child in node.get_children():
			pending.append(child)
	return bounds


## A point on the floor, picked with each triangle weighted by how much floor it
## is. The roll walks the triangles accumulating area until it passes the target,
## then lands inside that one with the square-root trick — which is what makes the
## point uniform across the triangle instead of bunched towards its first corner.
func _sample(polygons: Array, floor_area: float, rng: RandomNumberGenerator) -> Vector3:
	var target := rng.randf() * floor_area
	var walked := 0.0
	var chosen: Dictionary = polygons[-1]
	for triangle in polygons:
		walked += triangle["area"]
		if walked >= target:
			chosen = triangle
			break
	var u := rng.randf()
	var v := rng.randf()
	var root := sqrt(u)
	var a: Vector3 = chosen["a"]
	var b: Vector3 = chosen["b"]
	var c: Vector3 = chosen["c"]
	return a + (b - a) * (1.0 - root) + (c - a) * (v * root)


## The level this node belongs to.
##
## **Never `get_tree().current_scene`.** In the running game the current scene is
## the `GamePostProcessWrapper`, and the house lives inside the `SubViewport` it
## owns — so a search through the current scene's children finds neither the
## navigation region nor the house, `_floor_polygons` comes back empty, and not
## one piece of rubbish is laid. The bench never saw it because it adds the world
## straight to the root. This is the same trap `ClueManager.streaks_root` is
## written the way it is to avoid.
##
## The level is reached by climbing instead, which is true wherever the scene is
## mounted: this node is `Clues/Litter`, so the world is its grandparent, and
## `owner` is the world for anything saved as part of it.
func _level() -> Node:
	if owner != null:
		return owner
	var node: Node = get_parent()
	while node != null:
		if node.get_node_or_null(^"Navigation") != null or node.get_node_or_null(^"House") != null:
			return node
		node = node.get_parent()
	return get_parent()


## The house's navigation region. Found by type under the level rather than by a
## path, so this node can sit anywhere in either level's `Clues` branch without
## being told where the region is.
func _navigation_region() -> NavigationRegion3D:
	var root := _level()
	if root == null:
		return null
	for child in root.get_children():
		var region := child as NavigationRegion3D
		if region != null:
			return region
	return null


## Where the crew comes in. Asked of the same `house_spawns` group
## `ClueManager._doorstep` uses, so the two agree about which floor is the
## doorstep — and nowhere, in a world with no markers, which skips the check
## rather than guessing at it.
func _doorstep() -> Vector3:
	var tree := get_tree()
	if tree == null:
		return ClueManager.INVALID_POINT
	var spawns := tree.get_first_node_in_group("house_spawns") as Node3D
	if spawns == null:
		return ClueManager.INVALID_POINT
	for child in spawns.get_children():
		var marker := child as Marker3D
		if marker != null:
			return marker.global_position
	return ClueManager.INVALID_POINT
