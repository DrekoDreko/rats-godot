extends SceneTree

class RatStub extends CharacterBody3D:
	var holder: Node3D
	var escape_seconds := 0.0
	var captured := false
	func is_dead() -> bool: return false
	func is_captured() -> bool: return captured
	func is_pinned() -> bool: return is_instance_valid(holder)
	func is_pinned_by(node: Node3D) -> bool: return holder == node
	func glue_escape_time() -> float: return escape_seconds
	func pin(node: Node3D) -> void: holder = node
	func unpin() -> void:
		var previous := holder
		holder = null
		if is_instance_valid(previous):
			previous.released(self)

class PlayerStub extends CharacterBody3D:
	var holder: Node3D
	var progress := 0.0
	func is_dead() -> bool: return false
	func set_glue_state(glue: Node3D, stuck: bool, fraction: float, _anchor: Vector3) -> void:
		if stuck:
			holder = glue
			progress = fraction
		elif holder == glue:
			holder = null
			progress = 0.0

var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

## Put the pointer in the middle of the green, which is what a well-timed click
## is. The bench has no hands and the sweep would otherwise run past it.
func _aim(glue) -> void:
	glue.sweep_pointer = glue.sweep_zone_start + glue.sweep_zone_width * 0.5

## Just past the green, which is what a mistimed click is. Above it rather than
## below: the first sweep of all starts with the green at the foot of the track,
## where "a little before it" is inside it.
func _miss(glue) -> void:
	glue.sweep_pointer = minf(1.0, glue.sweep_zone_start + glue.sweep_zone_width + 0.05)

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		_failures += 1

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	var session := root.get_node("SessionManager")
	session.phase = Phase.Type.HUNT
	var scene: PackedScene = load("res://scenes/traps/glue_trap.tscn")
	var glue = scene.instantiate()
	world.add_child(glue)
	glue.set_physics_process(false)
	var player := PlayerStub.new()
	player.add_to_group("player")
	world.add_child(player)
	player.position = Vector3(10, 0, 0)
	var rats: Array[RatStub] = []
	for index in 6:
		var rat := RatStub.new()
		rat.add_to_group("rats")
		world.add_child(rat)
		rats.append(rat)
		glue._on_body_entered(rat)
	_check(glue._rats.size() == 5 and not rats[5].is_pinned(), "Five rats maximum")
	rats[0].unpin()
	glue._on_body_entered(rats[5])
	_check(glue._rats.size() == 5 and rats[5].is_pinned(), "Released capacity is reusable")
	rats[1].escape_seconds = 20.0
	glue._physics_process(19.0)
	_check(rats[1].is_pinned(), "Escaper stays pinned before deadline")
	glue._physics_process(1.0)
	_check(not rats[1].is_pinned() and rats[2].is_pinned(), "Only capable rats escape at 20 seconds")
	var other = scene.instantiate()
	world.add_child(other)
	other.set_physics_process(false)
	other._on_body_entered(rats[2])
	_check(other._rats.is_empty(), "Overlapping glue cannot claim a pinned rat")
	glue.remaining = 40.0
	player.position = Vector3.ZERO
	glue._physics_process(0.0)
	_check(player.holder == glue and is_equal_approx(glue.remaining, 30.0), "Player capture costs ten seconds")
	other._physics_process(0.0)
	_check(other._players.is_empty() and is_equal_approx(other.remaining, 40.0), "Only one glue holds each player")
	# The escape is timed now: only a click with the pointer in the green counts,
	# and either way the green moves.
	glue._physics_process(0.2)
	var missed_target: float = glue.sweep_zone_start
	_miss(glue)
	glue.press_escape()
	_check(is_zero_approx(player.progress) and glue.sweep_zone_start != missed_target,
		"A click outside the green is worth nothing and moves the target")
	glue.sweep_pointer = 1.0
	glue._physics_process(0.1)
	var first_sweep: float = 1.0 - glue.sweep_pointer
	_aim(glue)
	glue.press_escape()
	_check(is_equal_approx(player.progress, 1.0 / 3.0), "A click in the green counts")
	glue.sweep_pointer = 1.0
	glue._physics_process(0.1)
	_check(1.0 - glue.sweep_pointer > first_sweep, "Each landed hit speeds the next sweep up")
	glue._physics_process(2.0)
	_check(is_equal_approx(player.progress, 1.0 / 3.0), "Standing still no longer drains progress")
	_check(is_equal_approx(glue.sweep_pointer, 1.0), "An unanswered sweep starts over rather than stopping")
	_aim(glue)
	glue.press_escape()
	_check(is_equal_approx(player.progress, 2.0 / 3.0), "Timed hits accumulate")
	glue._physics_process(0.1)
	_aim(glue)
	glue.press_escape()
	_check(player.holder == null, "Three timed hits release the player")
	var time_after_escape: float = glue.remaining
	glue._physics_process(0.0)
	_check(player.holder == null and glue.remaining == time_after_escape, "No immediate recapture or repeated cost")
	player.position = Vector3(10, 0, 0)
	glue._physics_process(0.0)
	player.position = Vector3.ZERO
	glue._physics_process(0.0)
	_check(player.holder == glue and is_equal_approx(glue.remaining, time_after_escape - 10.0), "Reentry catches and charges again")
	glue.remaining = 0.01
	glue._physics_process(0.02)
	_check(player.holder == null and not rats[2].is_pinned() and not glue.is_armed(), "Expiration releases every occupant")
	player.position = Vector3(10, 0, 0)
	session.phase = Phase.Type.SURVEY
	other._physics_process(50.0)
	_check(other.remaining == 40.0, "Preparation does not consume lifetime")
	session.phase = Phase.Type.HUNT
	other.remaining = 8.0
	player.position = Vector3.ZERO
	other._physics_process(0.0)
	_check(other._expired and player.holder == null, "Player cost can immediately exhaust glue")
	# Compile the actual integration, including the shared-label HUD.
	var player_scene: PackedScene = load("res://scenes/player.tscn")
	_check(player_scene != null, "Player integration loads")
	player.remove_from_group("player")
	var real_player = player_scene.instantiate()
	world.add_child(real_player)
	real_player.set_physics_process(false)
	var fresh = scene.instantiate()
	world.add_child(fresh)
	fresh.set_physics_process(false)
	fresh._physics_process(0.0)
	_check(real_player.is_glued(), "Actual player is immobilized")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	_miss(fresh)
	real_player._unhandled_input(click)
	_check(is_zero_approx(real_player.glue_progress), "A mistimed click does not free the actual player")
	for index in 3:
		fresh._physics_process(0.2)
		_aim(fresh)
		real_player._unhandled_input(click)
	_check(not real_player.is_glued(), "Actual timed clicks free the player")
	var hud := real_player.get_node("GlueHUD")
	hud._process(0.0)
	_check(hud._prompt is BigFontOutlinedLabel and hud._counter is BigFontOutlinedLabel,
		"HUD uses reusable text scene")
	# Exercise actual physics entry/exit, including recapture immunity.
	var physical_glue = scene.instantiate()
	physical_glue.position.x = 25.0
	world.add_child(physical_glue)
	physical_glue.set_physics_process(false)
	var physical_rat := RatStub.new()
	physical_rat.collision_layer = 4
	physical_rat.collision_mask = 0
	physical_rat.position = Vector3(25, 0.05, 0)
	physical_rat.add_to_group("rats")
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.1
	collision.shape = sphere
	physical_rat.add_child(collision)
	world.add_child(physical_rat)
	await physics_frame
	await physics_frame
	_check(physical_rat.is_pinned(), "Physics overlap captures a rat")
	physical_rat.unpin()
	physical_glue._on_body_entered(physical_rat)
	_check(not physical_rat.is_pinned(), "Escaped rat cannot stick again before leaving")
	physical_rat.position.x = 27.0
	await physics_frame
	await physics_frame
	physical_rat.position.x = 25.0
	await physics_frame
	await physics_frame
	_check(physical_rat.is_pinned(), "Rat can be caught again after physical exit and reentry")
	# The green lands all over the track and never twice in the same place.
	seed(38219)
	var thirds := [false, false, false]
	for index in 300:
		var previous: float = other._previous_zone_center
		other._start_sweep()
		var center: float = other._previous_zone_center
		_check(other.sweep_zone_start >= 0.08 - 0.00001
			and other.sweep_zone_start + other.sweep_zone_width <= 0.92 + 0.00001,
			"The green stays on the track")
		_check(previous < 0.0 or absf(center - previous) >= other.MIN_ZONE_SHIFT - 0.00001,
			"The green moves between one go and the next")
		thirds[clampi(int(center * 3.0), 0, 2)] = true
	_check(thirds.all(func(seen: bool) -> bool: return seen),
		"The green reaches every third of the track")
	var common: Resource = load("res://resources/species/common_rat.tres")
	var sprayer: Resource = load("res://resources/species/sprayer_rat.tres")
	_check(common.glue_escape_seconds == 0.0 and sprayer.glue_escape_seconds == 20.0, "Species escape configuration")
	world.queue_free()
	await process_frame
	await process_frame
	if _failures == 0:
		print("OK: glue capacity, timed escape, wear, overlap, reentry, expiration, preparation and integration")
	quit(_failures)
