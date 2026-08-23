class_name RoadScroll
extends Node3D
## The world going past the windows: the illusion that the van is moving when
## nothing in the scene is.
##
## **Nothing moves the van and nothing moves the player.** The card is explicit
## about it and the reason is worth writing down: a van that really drove would
## be a `CharacterBody3D` carrying four other `CharacterBody3D`s on its floor,
## and Godot does not carry them — the crew would slide out of the back the
## first time it turned, or judder against the floor for two minutes solid.
## Every physics body in this scene stands still on a road that is not there,
## and what moves is a texture.
##
## So the movement is done twice over, in two different ways, because two
## different things have to sell it:
##
## - **The ground.** A plane under the windows with its UV scrolled along its
##   length. It has no features to count, so scrolling it reads as speed and
##   never as a repeat, however long the phase runs.
## - **The things beside the road.** Poles, signs, a fence — objects that *do*
##   have features, so scrolling them would read as a loop the moment the same
##   pole came round twice. They are moved instead, backwards along the run, and
##   wrapped to the far end when they pass the near one (`_recycle`). One pole
##   is every pole, which is what a PSX game did too.
##
## **The speed is one number and everything reads it.** `speed` is metres per
## second and drives the ground, the scenery and — through `travelled()` — the
## engine note. A van that slows down slows down all at once rather than in
## three places that have to be kept in step.
##
## The whole thing lives outside the van's own body, in world space: the objects
## it recycles are its own children and it never looks at the truck. Which means
## the same node dropped in a different scene with different children still
## works, and a van rebuilt around it does not break it.

## How fast the world is going past, in metres per second. Fifty km/h in a box
## truck on a suburban road, which is fast enough to read as motion through a
## window and slow enough that a pole does not strobe as it passes.
@export var speed := 14.0

## The mesh whose UV is scrolled: the road surface itself. Anything with a
## material that has an `uv1_offset` — a `StandardMaterial3D` on a plane is what
## the scene uses.
@export var ground_path: NodePath = ^"Ground"

## How many times the road texture repeats over the length of the ground plane.
## The UV offset is `travelled / length * tiling`, so this is what decides
## whether the scroll reads as tarmac going past or as a smear.
@export var ground_length := 96.0

## The parent of everything that is moved rather than scrolled. Each child is
## recycled independently, so a pole and a fence panel can run at the same speed
## without being spaced evenly.
@export var props_path: NodePath = ^"Props"

## The stretch a prop lives in, measured along Z in this node's own space. A prop
## that passes `wrap_near` is put back `wrap_far`, and the two numbers together
## are the length of the loop — long enough that the player never sees the same
## pole leave one window and arrive in the other.
@export var wrap_near := 40.0
@export var wrap_far := -80.0

## Whether the world is going past at all. The scene turns this off the moment
## the van is not on the road, so a van left standing in another phase does not
## quietly scroll its road for the rest of the shift.
@export var running := true:
	set(value):
		if running == value:
			return
		running = value
		set_process(running)

@onready var _ground: MeshInstance3D = get_node_or_null(ground_path) as MeshInstance3D
@onready var _props: Node3D = get_node_or_null(props_path) as Node3D

## The ground's own material, copied on the way up so that scrolling this road
## does not scroll every other plane sharing the resource.
var _ground_material: StandardMaterial3D

## How far the van has "gone", in metres. It only ever grows, and everything
## derived from the movement is a function of it — which is what keeps the road,
## the props and the engine from drifting apart over two minutes.
var _travelled := 0.0

## The props, read once. The row does not grow while the van is on the road.
var _prop_nodes: Array[Node3D] = []


func _ready() -> void:
	_ground_material = _own_ground_material()
	if _props != null:
		for child in _props.get_children():
			var prop := child as Node3D
			if prop != null:
				_prop_nodes.append(prop)
	set_process(running)


func _process(delta: float) -> void:
	var step := speed * delta
	_travelled += step
	_scroll_ground()
	_move_props(step)


## How far the van has come, in metres. The engine loop reads it to know how
## hard to sound, and a bench reads it to know the road ran at all.
func travelled() -> float:
	return _travelled


## The road surface, slid along its own length. `uv1_offset` and not the mesh
## position: moving the plane would take it out from under the van in a hundred
## metres, and moving it back would be the same wrap the props do — with a seam
## the props do not have, because tarmac has no features to hide one behind.
func _scroll_ground() -> void:
	if _ground_material == null or ground_length <= 0.0:
		return
	var offset := fmod(_travelled / ground_length, 1.0)
	# Negative, so that the texture runs towards the back of the van: +Z is the
	# rear doorway, and the world has to go that way for the van to be going the
	# other.
	_ground_material.uv1_offset = Vector3(0.0, -offset * _ground_tiling(), 0.0)


## Everything beside the road, moved backwards and wrapped round. Each prop is
## wrapped on its own rather than the whole row at once, so that props spaced
## unevenly stay spaced unevenly instead of snapping into a rhythm.
func _move_props(step: float) -> void:
	var span := wrap_near - wrap_far
	if span <= 0.0:
		return
	for prop in _prop_nodes:
		var at := prop.position
		at.z += step
		# `while` and not `if`: a frame long enough to carry a prop past the end
		# twice — a stall, a breakpoint, a scene loading — should put it back on
		# the road rather than leave it somewhere beyond the far end where it
		# never comes round again.
		while at.z > wrap_near:
			at.z -= span
		prop.position = at


## How many times the road texture repeats over the plane. Read off the material
## so that changing the tiling in the editor changes the scroll with it, rather
## than leaving the two disagreeing and the road sliding at the wrong rate.
func _ground_tiling() -> float:
	if _ground_material == null:
		return 1.0
	return maxf(1.0, _ground_material.uv1_scale.y)


## A private copy of the ground's material. Same reason the ready board copies
## its plate: Godot hands every instance the same resource, and scrolling a
## shared one would scroll every road in the game.
func _own_ground_material() -> StandardMaterial3D:
	if _ground == null:
		return null
	var source := _ground.get_active_material(0) as StandardMaterial3D
	if source == null:
		return null
	var copy: StandardMaterial3D = source.duplicate()
	_ground.set_surface_override_material(0, copy)
	return copy
