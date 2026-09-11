extends SceneTree
## Verify inward doors and bidirectional rat routes on the imported two-floor house.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	get_tree_timeout()
	var world := (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	await physics_frame
	await physics_frame
	await process_frame
	var inward := {
		"Door_Entrada_Pivot": Vector3.BACK,
		"Door_Sala_Pivot": Vector3.BACK,
		"Door_Cozinha_Pivot": Vector3.BACK,
		"Door_Banheiro_Pivot": Vector3.BACK,
		"Door_SalaCoz_Pivot": Vector3.RIGHT,
		"Door_Upper_Entrance_Pivot": Vector3.LEFT,
		"Door_Upper_Bedroom_Access_Pivot": Vector3.LEFT,
		"Door_Upper_Bathroom_Pivot": Vector3.LEFT,
	}
	for door_name in inward:
		var door := world.find_child(door_name, true, false) as HingedDoor
		assert(door != null)
		door.toggle()
	await create_timer(0.6).timeout
	for door_name in inward:
		var door := world.find_child(door_name, true, false) as HingedDoor
		assert(door.global_basis.x.dot(inward[door_name]) > 0.99,
			"Door must open into its room: " + door_name)
	var rat := (load("res://scenes/rat.tscn") as PackedScene).instantiate()
	world.add_child(rat)
	rat.set_physics_process(false)
	rat.set_process(false)
	await physics_frame
	var map: RID = rat.agent.get_navigation_map()
	assert(NavigationServer3D.map_get_iteration_id(map) > 0)
	var vertical_ends := 0
	var holes := get_nodes_in_group("rat_holes")
	assert(holes.size() == 8)
	for hole in holes:
		var other: Node3D = hole.linked()
		assert(other != null and other.linked() == hole, "Routes must be reciprocal")
		var mouth: Vector3 = hole.mouth()
		var floor_point := NavigationServer3D.map_get_closest_point(map, mouth)
		assert(floor_point.distance_to(mouth) < 0.25, "Mouth must be on walkable floor: " + hole.name)
		# The slit faces the room, with a solid wall directly behind it.
		var ray := PhysicsRayQueryParameters3D.create(mouth + Vector3.UP * 0.15,
			hole.global_position + hole.global_basis.z * 0.15 + Vector3.UP * 0.15)
		assert(not world.get_world_3d().direct_space_state.intersect_ray(ray).is_empty())
		if absf(mouth.y - other.mouth().y) > 3.0:
			vertical_ends += 1
		rat.global_position = mouth
		rat._dive_into(hole)
		assert(rat.global_position.distance_to(other.mouth()) < 0.25,
			"Rat must arrive at paired mouth: " + hole.name)
		assert(rat.velocity == Vector3.ZERO)
		assert(rat.agent.target_position.is_equal_approx(rat.global_position))
	assert(vertical_ends == 6, "Three vertical routes must work in both directions")
	var upper := world.get_node("RatHoles/HoleUpperBedroom")
	rat.global_position = upper.mouth() - Vector3.UP * 3.2
	var before: Vector3 = rat.global_position
	rat._dive_into(upper)
	assert(rat.global_position.is_equal_approx(before), "Rat cannot enter through the floor below a hole")
	print("PASS: eight inward doors, four reciprocal hole pairs, six inter-floor transfers and floor guard")
	world.queue_free()
	await process_frame
	quit()

func get_tree_timeout() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(1))
