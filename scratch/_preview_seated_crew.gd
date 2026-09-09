extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene := load("res://scenes/van_travel.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for frame in 3:
		await process_frame
	scene.get_node("Player").hide()
	for child in scene.get_children():
		if child is CanvasLayer:
			child.hide()
	for seat in scene.get_node("Spawns").get_children():
		var body := Node3D.new()
		scene.add_child(body)
		body.global_transform = seat.global_transform
		var model := load("res://scenes/player_model.tscn").instantiate() as PlayerModel
		body.add_child(model)
		model.set_state(PlayerAvatar.State.SITTING)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 2.25, 2.7)
	camera.look_at(Vector3(0, 1.30, 0.05))
	camera.fov = 75
	camera.current = true
	for frame in 30:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://scratch/seated_crew_preview.png")
	quit()
