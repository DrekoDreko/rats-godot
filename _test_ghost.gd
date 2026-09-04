extends SceneTree
## Ghost test bench: the trap-to-be that shows the player where his trap would
## land, and what it looks like while he is pointing at the boards.
##
## Run with: godot --headless --script _test_ghost.gd
##
## What is checked is the one thing the ghost exists for: with the box out and
## the sights on the floor, there is a translucent trap standing on the spot the
## real one would take. It has the shape of the trap it copies, it is off the
## replicated container so nobody else sees it, and it goes away the moment the
## weapon does.

const WAIT := 8
const TRAP_SLOT := 0
const GLUE_SLOT := 1
const FLOOR_STATION := Vector3(0.0, 0.1, 4.0)
const LOOK_DOWN := -0.9

var _world: Node3D
var _player: CharacterBody3D
var _head: Node3D
var _inventory: Node
var _traps: Node
var _stock: Node
var _phase: Node

var _step := 0
var _clock := 0
var _failures := 0
## Carried between the frames of a step that acts on one and measures on another.
var _aim_before := Vector3.ZERO
var _unstretched := 0.0

func _initialize() -> void:
	Engine.max_fps = 60
	_world = load("res://scenes/world.tscn").instantiate()
	root.add_child(_world)
	_player = _world.get_node("Player")
	_head = _player.get_node("Head")
	_inventory = _player.get_node("Head/Inventory")
	_traps = _world.get_node("Traps")
	_stock = root.get_node_or_null("Stock")
	_phase = root.get_node_or_null("PhaseManager")
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)

func _physics_process(_delta: float) -> bool:
	_clock += 1
	match _step:
		0: return _check_enters_the_house()
		1: return _check_setup()
		2: return _check_mousetrap_ghost()
		3: return _check_ghost_follows_aim()
		4: return _check_ghost_hidden_off_floor()
		5: return _check_ghost_goes_with_the_weapon()
		6: return _check_glue_ghost_stretches()
	return _finish()

func _check_enters_the_house() -> bool:
	if _phase == null:
		print("FAIL: the phase machine was not found")
		return _finish()
	if _clock == 1:
		_phase.go_to(2)
		return false
	if _clock < WAIT:
		return false
	return _advance()

func _check_setup() -> bool:
	if _clock < WAIT:
		return false
	_stock.reset()
	_stock.add("mousetrap", 3)
	_stock.add("rat_glue", 2)
	return _advance()

## The box out, the sights on the boards: there is a trap-to-be standing there.
func _check_mousetrap_ghost() -> bool:
	if _clock < WAIT:
		return false
	if _clock == WAIT:
		_stand_on_floor()
		_expect(_inventory.equip(TRAP_SLOT), "the belt should reach the box of traps")
		return false
	# The ghost is built in `_process`, which the bench has to let run.
	if _clock < WAIT + 6:
		return false
	var weapon: Node3D = _player.get_node("Head/Mousetrap")
	var ghost := _ghost_of(weapon)
	if ghost == null:
		print("FAIL: no ghost was built with the box out and the floor in the sights")
		return _finish()
	_expect(ghost.visible, "the ghost should be on screen while the floor is in the sights")
	_expect(ghost.get_parent() == _player.get_parent(),
		"the ghost must hang outside the replicated Traps container")
	# The `Traps` container starts with its `MultiplayerSpawner` in it and
	# nothing else, so what is counted is traps and not children.
	_expect(_placed_count() == 0, "the ghost is not a placed trap")
	_expect(_meshes_of(ghost) > 0, "the ghost should carry the trap's own model")
	for mesh in _mesh_nodes(ghost):
		var material := mesh.material_override as StandardMaterial3D
		_expect(material != null, "every ghost mesh should get a skin of its own")
		if material != null:
			_expect(material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA,
				"the ghost should be see-through")
			_expect(material.albedo_color.a < 1.0, "the ghost should be tinted translucent")
	for shape in _shape_nodes(ghost):
		_expect(shape.disabled, "a ghost should not be a thing in the world")
	print("--- mousetrap ghost at %v ---" % ghost.global_position)
	return _advance()

## It stands where the ray lands, and moves when the player turns.
func _check_ghost_follows_aim() -> bool:
	var ghost := _ghost_of(_player.get_node("Head/Mousetrap"))
	if _clock == 1:
		_aim_before = ghost.global_position
		return false
	# Turned on a frame of its own, after the spot has been read: the ghost is
	# moved from `_process`, and a turn in the same breath as the reading is a
	# turn the ghost has not been given a frame to answer.
	if _clock == 2:
		_player.rotation.y += 0.6
		return false
	if _clock < 20:
		return false
	var moved := ghost.global_position
	print("--- ghost moved %v -> %v ---" % [_aim_before, moved])
	_expect(moved.distance_to(_aim_before) > 0.05,
		"the ghost should follow the sights around the floor")
	_expect(absf(ghost.global_position.y - FLOOR_STATION.y) < 1.0,
		"the ghost should be standing on the boards")
	return _advance()

## Nothing flat in range, nothing on screen.
func _check_ghost_hidden_off_floor() -> bool:
	if _clock < 4:
		return false
	_head.rotation.x = 1.2
	if _clock < 8:
		return false
	var ghost := _ghost_of(_player.get_node("Head/Mousetrap"))
	_expect(not ghost.visible, "aiming at the ceiling should take the ghost off screen")
	_head.rotation.x = LOOK_DOWN
	return _advance()

## Put the box away and the trap-to-be goes with it.
func _check_ghost_goes_with_the_weapon() -> bool:
	var weapon: Node3D = _player.get_node("Head/Mousetrap")
	if _clock == 1:
		_expect(_inventory.equip_hands(), "Q should put the box away")
		return false
	if _clock < 8:
		return false
	_expect(_ghost_of(weapon) == null, "the ghost should die with the weapon that drew it")
	return _advance()

## The glue's ghost is the run itself once the near end is pinned.
func _check_glue_ghost_stretches() -> bool:
	var glue: Node3D = _player.get_node("Head/RatGlue")
	if _clock == 1:
		_stand_on_floor()
		_expect(_inventory.equip(GLUE_SLOT), "the belt should reach the tray of glue")
		return false
	if _clock < 6:
		return false
	var ghost := _ghost_of(glue)
	if ghost == null:
		print("FAIL: the tray of glue drew no ghost")
		return _finish()
	if _clock == 6:
		_expect(ghost.visible, "the tray's ghost should be on screen")
		_unstretched = ghost.scale.z
		glue.try_use()
		_expect(glue.is_placing(), "the first click should pin the near end")
		# Walk away from the pinned end: the strip stretches to follow.
		_player.global_position += Vector3(0.0, 0.0, -1.2)
		return false
	if _clock < 14:
		return false
	var unstretched := _unstretched
	_expect(ghost.scale.z > unstretched + 0.1,
		"a pinned strip should stretch from its anchor to the sights")
	print("--- glue ghost stretched to %.2f (was %.2f) ---" % [ghost.scale.z, unstretched])
	return _advance()

# --- Helpers ---------------------------------------------------------------

## The trap-to-be the weapon is drawing, or null when it is drawing none. It is
## read off the weapon itself rather than hunted for in the tree: the ghost is
## the weapon's own private business and there is nothing else to confuse it
## with.
func _ghost_of(weapon: Node) -> Node3D:
	var ghost: Node3D = weapon.get("_ghost")
	if ghost == null or not is_instance_valid(ghost):
		return null
	return ghost

## How many traps are actually on the floor. The `MultiplayerSpawner` sitting in
## the container is not one of them.
func _placed_count() -> int:
	var count := 0
	for child in _traps.get_children():
		if child is not MultiplayerSpawner:
			count += 1
	return count

func _mesh_nodes(node: Node) -> Array:
	var found := []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_mesh_nodes(child))
	return found

func _shape_nodes(node: Node) -> Array:
	var found := []
	if node is CollisionShape3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_shape_nodes(child))
	return found

func _meshes_of(node: Node) -> int:
	return _mesh_nodes(node).size()

func _stand_on_floor() -> void:
	_player.global_position = FLOOR_STATION
	_player.rotation = Vector3.ZERO
	_head.rotation.x = LOOK_DOWN

func _expect(condition: bool, description: String) -> void:
	if condition:
		print("ok: %s" % description)
	else:
		print("FAIL: %s" % description)
		_failures += 1

func _advance() -> bool:
	_step += 1
	_clock = 0
	return false

func _finish() -> bool:
	if _failures == 0:
		print("--- ghost bench passed ---")
	else:
		print("--- ghost bench: %d failures ---" % _failures)
	quit(1 if _failures > 0 else 0)
	return true
