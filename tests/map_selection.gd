extends SceneTree
## Verify contract selection, separate maps, and survey-to-hunt continuity.

var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		_failures += 1


func _run() -> void:
	var contracts := root.get_node("ContractManager")
	var phases := root.get_node("PhaseManager")
	var session := root.get_node("SessionManager")
	contracts._settle("hallow_street")
	_check(phases.scene_of(Phase.Type.SURVEY) == "res://scenes/world.tscn",
		"First contract must keep the original map")
	contracts._settle("marrow_lane")
	var map_path: String = phases.scene_of(Phase.Type.SURVEY)
	_check(map_path == "res://scenes/world_2.tscn", "Second contract must select map 2")
	_check(phases.scene_of(Phase.Type.HUNT) == map_path, "Both phases must use map 2")
	session.phase = Phase.Type.SURVEY
	var world := (load(map_path) as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await process_frame
	await physics_frame
	await physics_frame
	_check(world.get_node("House").scene_file_path == "res://models/house_2.glb",
		"Map 2 must load its separate imported model")
	_check(world.get_node("Geometry").get_child_count() == 0,
		"The selected map must not recursively load itself")
	var doors := world.get_node("House/Doors")
	var door_count := 0
	for door in doors.get_children():
		if door is HingedDoor:
			door_count += 1
			var shape: BoxShape3D = door.get_node("Collision").get_child(0).shape
			_check(shape.size.is_equal_approx(Vector3(0.92, 2.03, 0.06)),
				"Map 2 door colliders must match its model")
	_check(door_count == 6, "Map 2 must have six interactive doors")
	_check(get_nodes_in_group("rat_holes").size() == 6, "Map 2 must have six burrows")
	_check(get_nodes_in_group("garbage").size() == 5, "Map 2 must have five garbage piles")
	var marker := Node3D.new()
	world.get_node("Traps").add_child(marker)
	phases.go_to(Phase.Type.HUNT)
	await process_frame
	_check(current_scene == world and is_instance_valid(marker),
		"Starting the hunt must preserve the map and placed objects")
	_check(world.spawned_rat_count() == 12, "Map 2 must spawn the contract infestation")
	world.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: map selection, six doors, burrows, infestation and phase continuity")
	quit(1 if _failures > 0 else 0)
