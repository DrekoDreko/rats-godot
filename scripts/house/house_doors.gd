class_name HouseDoors
extends Node3D
## Turns the doors that came in with the house model into doors the crew can use.
##
## The leaves are modelled and exported in Blender, which means they arrive as
## plain `MeshInstance3D`s inside an imported `.glb` — geometry, and nothing that
## swings, blocks, or answers a keypress. Reimporting that file overwrites
## anything hand-added to it, so the rig cannot live in the imported scene: it is
## built here instead, at load, out of whatever leaves the model actually
## contains. **Add a door in Blender and it works in the game with nothing
## written here**, which is the whole point of doing it this way rather than
## wiring five doors into `world.tscn` by hand.
##
## Each leaf gets three things it did not come with:
##
## - a `HingedDoor` script on the leaf's own parent pivot, which is where the
##   swing and the wire live;
## - an `AnimatableBody3D` carrying the leaf's collision, so that a shut door
##   stops a man and an open one does not, and so that a rat's navigation mesh
##   sees a door the same way it sees a wall;
## - an `Interactable` in the doorway, which is what the player's ray finds and
##   what `E` actually presses.
##
## The leaf is **reparented** under the pivot rather than scripted directly: the
## importer owns the mesh node and rewrites it, so the moving parts are hung
## around it instead of on it.

## Which nodes in the model are doors. Everything else in the house — walls,
## floor — is scenery and is left alone.
const LEAF_PREFIX := "Door_"

## The leaf's collision box, in metres. Taken to match the modelled leaf
## (0.92 x 2.03 x 0.05) rather than measured off the mesh: a box is what a door
## should collide as, and an exact hull of a flat slab is a worse shape for a man
## to slide along than the slab's own dimensions.
const LEAF_SIZE := Vector3(0.92, 2.03, 0.06)

## How far out from the hinge the leaf's centre sits — half its width, which is
## where a box covering it has to go.
const LEAF_CENTRE_X := 0.46

## The reach of the prompt in the doorway: a box standing in the frame, wide and
## deep enough to be found from either side without being findable from the next
## room.
const REACH_SIZE := Vector3(1.2, 2.0, 1.1)

## The layers this rig sits on. The leaf collides as scenery (1) because that is
## what the navigation mesh is baked from and what the player walks into; the
## prompt answers on the interactable layer (8), which is the only mask the
## player's `Interact` ray reads.
const SCENERY_LAYER := 1
const INTERACT_LAYER := 8

## What the prompt reads, shut and open. Keys in `ui_strings`, the way the
## terminal's are. It is swapped on every swing rather than left as one wording:
## a man at an open door is being offered the opposite of what a man at a shut one
## is, and "use the door" would hide which.
const PROMPT_OPEN := "PROMPT_OPEN_DOOR"
const PROMPT_CLOSE := "PROMPT_CLOSE_DOOR"


func _ready() -> void:
	# The house is an imported scene and is still adding its own children when
	# this runs, which is a moment at which nothing may be added to it. The rig
	# is built a frame later, when the model is whole and its leaves can be
	# moved.
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	if not is_inside_tree():
		return
	for leaf in _leaves():
		_rig(leaf)


## Every door leaf in the house model, wherever the importer nested it. Searched
## by name for the same reason `van_doors.gd` searches: how deep a `.glb`'s nodes
## sit depends on how it was imported, and a path written here would be a path
## that breaks the next time the model changes.
func _leaves() -> Array[Node3D]:
	var found: Array[Node3D] = []
	var house := get_parent()
	if house == null:
		return found
	_collect(house, found)
	return found


func _collect(node: Node, into: Array[Node3D]) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and str(child.name).begins_with(LEAF_PREFIX):
			into.append(child as Node3D)
		else:
			_collect(child, into)


## One door: a pivot where the leaf stood, the leaf hung under it, a body to
## collide with and a prompt to press.
## The rig hangs under **this** node rather than under the imported model. The
## importer owns that subtree and rewrites it wholesale on the next reimport, so
## anything parked inside it would not survive; and nothing built at runtime is
## given an `owner`, because an owner is what makes a node get saved with a scene
## and none of this should ever be written back into `world.tscn`.
##
## The leaf keeps the placement it was exported with, which — because the model
## was built with each origin on its hinge — is measured from the house's origin.
## This node sits at that same origin, so the pivot can take the leaf's transform
## unchanged.
func _rig(leaf: Node3D) -> void:
	var pivot := Node3D.new()
	pivot.name = str(leaf.name) + "_Pivot"
	pivot.transform = leaf.transform
	# The extras ride from the leaf to the pivot: the angles were written for
	# this door, and the pivot is now the thing that turns.
	if leaf.has_meta(HingedDoor.EXTRAS_KEY):
		pivot.set_meta(HingedDoor.EXTRAS_KEY, leaf.get_meta(HingedDoor.EXTRAS_KEY))
	pivot.set_script(load("res://scripts/house/hinged_door.gd"))
	add_child(pivot)

	# The leaf keeps its geometry and gives up its placement, which now belongs
	# to the pivot above it.
	leaf.reparent(pivot, false)
	leaf.transform = Transform3D.IDENTITY

	_add_body(pivot)
	# The prompt is hung beside the pivot, not under it: see `_add_prompt`.
	_add_prompt(pivot)


## The collision that swings with the leaf. `AnimatableBody3D` and not
## `StaticBody3D`: this one is moved by a tween every time somebody opens it, and
## a static body moved under the physics server is a body other things tunnel
## through.
func _add_body(pivot: Node3D) -> void:
	var body := AnimatableBody3D.new()
	body.name = "Collision"
	body.collision_layer = SCENERY_LAYER
	body.collision_mask = 0
	body.sync_to_physics = false
	body.add_to_group("scenery")
	pivot.add_child(body)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = LEAF_SIZE
	shape.shape = box
	shape.position = Vector3(LEAF_CENTRE_X, LEAF_SIZE.y * 0.5, 0.0)
	body.add_child(shape)


## The thing the player's ray actually finds. It stays put in the doorway rather
## than swinging with the leaf: a prompt that travelled with an opening door
## would end up in the middle of a room, and a man wanting to shut a door behind
## him would have to chase it.
func _add_prompt(pivot: Node3D) -> void:
	var prompt := Interactable.new()
	prompt.name = str(pivot.name) + "_Use"
	prompt.prompt = PROMPT_OPEN
	prompt.usable_in_house = true
	prompt.collision_layer = INTERACT_LAYER
	prompt.collision_mask = 0
	prompt.monitoring = false
	# Sited in the frame by borrowing the pivot's placement and stepping to the
	# middle of the shut leaf — but parented alongside the pivot rather than
	# under it, so that the swing leaves it where the doorway is.
	prompt.transform = pivot.transform.translated_local(
		Vector3(LEAF_CENTRE_X, REACH_SIZE.y * 0.5, 0.0))
	add_child(prompt)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = REACH_SIZE
	shape.shape = box
	prompt.add_child(shape)

	var door := pivot as HingedDoor
	prompt.used.connect(door.toggle)
	door.swung.connect(func(open: bool) -> void:
		prompt.prompt = PROMPT_CLOSE if open else PROMPT_OPEN)
