extends SceneTree
## Run after importing house.glb: --headless --path . --script tests/house_model.gd.

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var house := (load("res://models/house.glb") as PackedScene).instantiate()
	root.add_child(house)
	var applier := (load("res://scenes/ps1.tscn") as PackedScene).instantiate()
	house.add_child(applier)
	var doors := HouseDoors.new()
	house.add_child(doors)
	await process_frame
	await physics_frame
	var panes := 0
	for node in house.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if "_Glass" in str(mesh.name):
			panes += 1
			var glass := mesh.get_active_material(0) as BaseMaterial3D
			assert(glass != null, "Glass must retain its native material")
			assert(glass.transparency in [BaseMaterial3D.TRANSPARENCY_ALPHA,
				BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS])
			assert(glass.albedo_color.a > 0.0 and glass.albedo_color.a < 0.5)
			assert(glass.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED)
		elif str(mesh.name) == "House_Exterior_Stairs":
			var concrete := mesh.get_active_material(0) as ShaderMaterial
			assert(concrete.get_shader_parameter("albedo") != null)
		elif str(mesh.name) == "House_Walls":
			var wall := mesh.get_active_material(0) as ShaderMaterial
			assert(wall.shader.resource_path == "res://shaders/level.gdshader")
			var environment := load("res://resources/retro_environment.tres") as Environment
			assert(environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR)
			assert(environment.ambient_light_energy >= 1.0,
				"Ambient light must keep the ground floor visible below the slab")
	assert(panes == 10, "All ten windows must be imported")
	assert(house.find_children("*_Pivot", "Node3D", true, false).size() == 8)
	assert(house.find_child("House_Stair_Ramp", true, false) is StaticBody3D)
	assert(house.find_children("House_Stair_Ramp*", "MeshInstance3D", true, false).is_empty())
	# The window cutouts must not remove the surrounding exterior walls.
	var space := (house as Node3D).get_world_3d().direct_space_state
	for height in [2.7, 5.8]:
		for offset in [-4.0, -2.0, 0.0, 2.0, 4.0]:
			for side in [-1.0, 1.0]:
				for endpoints in [
					[Vector3(side * 6.6, height, offset), Vector3(side * 6.0, height, offset)],
					[Vector3(offset, height, side * 5.4), Vector3(offset, height, side * 4.6)]
				]:
					var ray := PhysicsRayQueryParameters3D.create(endpoints[0], endpoints[1])
					assert(not space.intersect_ray(ray).is_empty(), "Exterior wall missing at %s" % endpoints[0])
	for node in doors.find_children("*", "CollisionShape3D", true, false):
		if node.get_parent() is AnimatableBody3D:
			assert((node.shape as BoxShape3D).size.is_equal_approx(Vector3(1.0, 2.1, 0.06)))
	# Traverse the exported collision ramp with a player-sized body, without jumping.
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.8
	shape.shape = capsule
	body.add_child(shape)
	root.add_child(body)
	body.position = Vector3(7.05, 1.2, 4.4)
	body.floor_snap_length = 0.3
	for frame in 240:
		await physics_frame
		body.velocity.x = 0.0
		body.velocity.z = -2.0
		if not body.is_on_floor():
			body.velocity.y -= 9.8 / 60.0
		else:
			body.velocity.y = 0.0
		body.move_and_slide()
	assert(body.position.y > 4.0, "Player must reach the upper landing: %s" % body.position)
	assert(body.position.z < -0.65, "Player must pass the last stair: %s" % body.position)
	print("PASS: 10 transparent windows, 8 door colliders, interior material, concrete texture and stair ascent")
	body.queue_free()
	house.queue_free()
	await process_frame
	quit()
