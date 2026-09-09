class_name DroppingTrail
extends Node3D
## The droppings on the floor, and the reason they are where they are.
##
## Rats have been living in this house for weeks before the van pulled up, and
## they have been walking the same two or three routes the whole time: out of a
## hole in the skirting, across the boards, into whatever heap of rubbish has
## food in it. What they left behind on those routes is the crew's one free
## reading of the map. **Follow the droppings and you arrive at either a burrow
## or a bin.**
##
## So the trail is not decorated on by hand. It is laid along the *navigation
## path* every rat is actually going to walk — which means a designer who moves a
## crate and reroutes the room moves the droppings with it, and a clue can never
## point somewhere the animals cannot go. A hand laid trail would only be true on
## the day it was laid.
##
## Which routes those are is not worked out here: it is asked of
## `ClueManager.rat_runs()`. The streaks of piss are laid down the same routes,
## and the mess is only a clue if both agree about where the rats go.
##
## **Nothing here crosses the wire, and nothing needs to.** The trail is dirt:
## it catches nothing, it hurts nobody, and it never changes once it is down. The
## same mesh baked from the same scene and the same `SessionManager.random_seed`
## gives every machine the same droppings in the same places, which is cheaper
## and steadier than a hundred nodes replicated to say so.
##
## They stay on the floor for the whole shift. The highlight over a hole goes out
## when the hunt starts — that one is the game pointing at something, and pointing
## at it for ever would make the survey worth nothing — but a dropping is a
## physical thing lying on the boards, and a house that tidied itself the moment
## the rats came out would be taking evidence away rather than the crew's
## advantage.

## How far apart the piles are laid along the route, in metres. Close enough to
## read as a trail from across a room, far enough not to look like a painted line.
const SPACING := 2.6
## How far a pile may sit off the centre of the route. A rat does not walk a
## surveyor's line, and a trail dead down the middle of the path reads as a
## texture rather than as something an animal left.
const WANDER := 0.45
## How many pellets go in one pile, and how big one is.
const PELLETS := Vector2i(2, 4)
const PELLET_SIZE := Vector3(0.05, 0.03, 0.075)
## What droppings are the colour of.
const DROPPING_COLOR := Color(0.13, 0.1, 0.08)
## How many frames to give the navigation mesh before asking it anything. It is
## baked in `scripts/navigation.gd::_ready` and only answers queries after the
## server's first sync, which is the same wait `rat.gd::_map_ready` makes.
const BAKE_WAIT := 4


func _ready() -> void:
	# The tree is held across the wait rather than asked for again after it: a
	# phase can arrive off the wire on any of these frames and free this scene,
	# and a node resuming out of the tree has no `get_tree()` to reach through.
	var tree := get_tree()
	if tree == null:
		return
	for _frame in BAKE_WAIT:
		await tree.process_frame
		if not is_inside_tree():
			return
	_lay_trails()


## One trail per route. The routes are the same ones the piss is laid down, so
## they are asked for rather than worked out here (`ClueManager.rat_runs`).
func _lay_trails() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SessionManager.random_seed
	for run in ClueManager.rat_runs():
		_lay_along(run, rng)


## Piles of droppings down one route, every `SPACING` metres of it. The path is a
## handful of corners rather than a smooth curve, so it is walked corner to
## corner and the leftover of each leg is carried into the next — otherwise every
## turn in the house would have a pile sitting exactly on it.
func _lay_along(path: PackedVector3Array, rng: RandomNumberGenerator) -> void:
	if path.size() < 2:
		return
	var walked := SPACING * 0.5
	for i in range(1, path.size()):
		var from := path[i - 1]
		var to := path[i]
		var leg := from.distance_to(to)
		if leg <= 0.001:
			continue
		var side := (to - from).normalized().cross(Vector3.UP)
		while walked < leg:
			var at := from.lerp(to, walked / leg)
			at += side * rng.randf_range(-WANDER, WANDER)
			_drop(at, rng)
			walked += SPACING
		walked -= leg


## One pile of pellets on the boards.
##
## `at` comes off a navigation path, which is **not** the floor — the mesh in
## `world.tscn` bakes a fifth of a metre up — so where it actually lands is asked
## of `ClueManager.on_the_boards`. That is also what keeps a trail up a ramp
## sitting on the ramp.
func _drop(at: Vector3, rng: RandomNumberGenerator) -> void:
	var pile := Node3D.new()
	pile.position = ClueManager.on_the_boards(at)
	add_child(pile)
	var count := rng.randi_range(PELLETS.x, PELLETS.y)
	for _pellet in count:
		var mesh := MeshInstance3D.new()
		mesh.mesh = _pellet_mesh()
		mesh.material_override = _pellet_material()
		mesh.position = Vector3(rng.randf_range(-0.09, 0.09), 0.0, rng.randf_range(-0.09, 0.09))
		mesh.rotation.y = rng.randf_range(0.0, TAU)
		pile.add_child(mesh)


## The one box and the one skin every pellet in the house is drawn with. Built
## once and shared: a house lays a few hundred of these, and a mesh apiece would
## be a few hundred resources to say the same thing.
static var _mesh: BoxMesh
static var _material: StandardMaterial3D


func _pellet_mesh() -> BoxMesh:
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = PELLET_SIZE
	return _mesh


func _pellet_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.albedo_color = DROPPING_COLOR
	return _material
