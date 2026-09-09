extends SceneTree

var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var scene := load("res://scenes/van_travel.tscn").instantiate() as Node3D
	root.add_child(scene)
	current_scene = scene
	for frame in 3:
		await process_frame
	for frame in 5:
		await physics_frame
	var player = scene.get_node("Player")
	_check(player.is_seated(), "Direct travel scene launch must start seated.")
	var spawn: Vector3 = player.spawn_point()
	scene.get_node("Players")._stand_apart()
	_check(player.spawn_point().is_equal_approx(spawn), "Network opening overwrote the aisle respawn.")
	for seat in scene.get_node("Spawns").get_children():
		player.set_spawn(seat.standing_position())
		player.sit_at(seat.global_transform)
		var original: Vector3 = player.global_position
		var facing: Basis = player.global_basis
		var look := InputEventMouseMotion.new()
		look.relative = Vector2(100, 0)
		player._unhandled_input(look)
		_check(player.global_basis.is_equal_approx(facing), "Looking turned the body out of its seat.")
		Input.action_press("move_forward")
		Input.action_press("jump")
		for frame in 10:
			await physics_frame
		Input.action_release("move_forward")
		Input.action_release("jump")
		_check(player.global_position.is_equal_approx(original), "Seat %s moved under gravity/input." % seat.seat_number)
		_check(player.animation_state() == PlayerAvatar.State.SITTING, "Missing seated state.")
		_check(player.model.current_animation() == &"seating/SeatedIdle", "Missing dedicated seated animation.")
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = true
		player.set_ui_open(false)
		player._unhandled_input(event)
		_check(not player.is_seated(), "Seat %s cannot stand in the aisle." % seat.seat_number)
		_check(player.global_position.is_equal_approx(seat.standing_position()), "Incorrect exit position.")
		print("SEAT ", seat.seat_number, " cushion=", original, " exit=", player.global_position)
		await physics_frame
		await physics_frame
		_check(not player.collision.disabled, "Standing collision was not restored.")
	print("SEAT PLACEMENT: ", "PASS" if failures == 0 else "FAIL")
	quit(failures)
