extends SceneTree
## Bench for the new house: the model's doors, the burrows and the rubbish.
##
## Autoloads are fetched off `root` rather than named, and phases are written as
## integers, for the reasons `_test_clues.gd` sets out at its head.

var _frame := 0
var _world: Node
var _failures: Array[String] = []


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_load_world()
		20:
			_check_doors()
			_check_door_interaction()
			_check_clues()
			_check_house_geometry()
		24:
			_swing_a_door()
		60:
			_check_door_swung()
			_check_runs()
			_report()
			quit(1 if not _failures.is_empty() else 0)
	return false


func _load_world() -> void:
	var ps := load("res://scenes/world.tscn") as PackedScene
	if ps == null:
		_fail("world.tscn did not load")
		_report()
		quit(1)
		return
	_world = ps.instantiate()
	root.add_child(_world)


func _check_doors() -> void:
	var doors := _scripted("hinged_door.gd")
	print("\n--- DOORS (%d) ---" % doors.size())
	if doors.size() != 5:
		_fail("expected 5 doors, found %d" % doors.size())
	for d in doors:
		var n3 := d as Node3D
		var body := d.get_node_or_null("Collision") as AnimatableBody3D
		var extras: Dictionary = d.get_meta("extras", {})
		print("  %-24s rot_y=%7.1f  extras=%s  body_layer=%s" % [
			d.name, n3.rotation_degrees.y, extras,
			body.collision_layer if body != null else "MISSING"])
		if body == null:
			_fail("%s has no collision body" % d.name)
		elif body.collision_layer != 1:
			_fail("%s collides on layer %d, not scenery" % [d.name, body.collision_layer])
		if not extras.has("open_deg"):
			_fail("%s carries no open_deg" % d.name)

	var prompts := _prompts()
	print("\n--- PROMPTS (%d) ---" % prompts.size())
	if prompts.size() != 5:
		_fail("expected 5 door prompts, found %d" % prompts.size())
	for p in prompts:
		var n3 := p as Node3D
		print("  %-28s at %s  layer=%d  prompt=%s" % [
			p.name, n3.global_position.snapped(Vector3.ONE * 0.1),
			p.collision_layer, p.get("prompt")])
		if p.collision_layer != 8:
			_fail("%s answers on layer %d, not the interactable one" % [p.name, p.collision_layer])


func _check_door_interaction() -> void:
	var player = _world.get_node("Player")
	var session := root.get_node("SessionManager")
	var previous_phase: int = session.phase
	var station := Interactable.new()
	var prompts := _prompts()
	for phase in [Phase.Type.SURVEY, Phase.Type.HUNT]:
		session.phase = phase
		if player._can_interact(station) or player._can_interact():
			_fail("road stations must remain blocked in house phases")
		for prompt in prompts:
			if not player._can_interact(prompt):
				_fail("door must be usable in house phase %d" % phase)
		if not prompts.is_empty():
			var prompt = prompts[0]
			var door = prompt.used.get_connections()[0].callable.get_object()
			var was_open: bool = door.is_open()
			player._focused = prompt
			var event := InputEventKey.new()
			event.physical_keycode = KEY_E
			event.pressed = true
			player._unhandled_input(event)
			if door.is_open() == was_open:
				_fail("E must toggle the focused door in house phase %d" % phase)
	player._focused = null
	session.phase = Phase.Type.TRAVEL
	if not player._can_interact(station):
		_fail("road stations must remain usable during travel")
	session.phase = previous_phase
	station.free()


func _check_clues() -> void:
	var holes := get_nodes_in_group("rat_holes")
	var garbage := get_nodes_in_group("garbage")
	print("\n--- CLUES ---")
	print("  burrows: %d, rubbish: %d" % [holes.size(), garbage.size()])
	if holes.size() != 3:
		_fail("expected 3 burrows, found %d" % holes.size())
	if garbage.size() != 2:
		_fail("expected 2 rubbish heaps, found %d" % garbage.size())
	# Every burrow's mouth has to be inside the house, or its rats walk out of a wall.
	for h in holes:
		var mouth: Vector3 = h.call("mouth")
		print("    %-30s mouth=%s" % [h.get("hole_name"), mouth.snapped(Vector3.ONE * 0.1)])
		if absf(mouth.x) > 5.0 or absf(mouth.z) > 4.0:
			_fail("burrow '%s' opens outside the house at %s" % [h.get("hole_name"), mouth])


func _check_house_geometry() -> void:
	var house := _world.get_node_or_null("House") as Node3D
	if house == null:
		_fail("no House in the world")
		return
	var aabb := AABB()
	var first := true
	for m in _meshes(house):
		var mi := m as MeshInstance3D
		var box := mi.global_transform * mi.get_aabb()
		if first:
			aabb = box
			first = false
		else:
			aabb = aabb.merge(box)
	print("\n--- HOUSE ---")
	print("  bounds pos=%s size=%s" % [aabb.position.snapped(Vector3.ONE * 0.1),
		aabb.size.snapped(Vector3.ONE * 0.1)])
	if not house.is_in_group("scenery"):
		_fail("the house is not scenery, so nothing navigates it")


func _swing_a_door() -> void:
	var doors := _scripted("hinged_door.gd")
	if doors.is_empty():
		return
	var door: Node = doors[0]
	print("\n--- SWING: %s ---" % door.name)
	door.call("toggle", null)


func _check_door_swung() -> void:
	var doors := _scripted("hinged_door.gd")
	if doors.is_empty():
		return
	var door: Node = doors[0]
	var n3 := door as Node3D
	var extras: Dictionary = door.get_meta("extras", {})
	var want := float(extras.get("open_deg", 0.0))
	print("  after swing: rot_y=%.1f, wanted %.1f, is_open=%s" % [
		n3.rotation_degrees.y, want, door.call("is_open")])
	if not door.call("is_open"):
		_fail("%s did not register as open" % door.name)
	if absf(n3.rotation_degrees.y - want) > 1.0:
		_fail("%s stopped at %.1f, not %.1f" % [door.name, n3.rotation_degrees.y, want])


## The routes the rats have been walking, which is what the droppings and the
## streaks of piss are laid along. A house whose burrows cannot reach its rubbish
## has no readable clues in it at all.
func _check_runs() -> void:
	var clue := root.get_node_or_null("ClueManager")
	if clue == null:
		_fail("no ClueManager")
		return
	var runs: Array = clue.call("rat_runs")
	print("\n--- RAT RUNS (%d) ---" % runs.size())
	for r in runs:
		var path := r as PackedVector3Array
		var length := 0.0
		for i in range(1, path.size()):
			length += path[i - 1].distance_to(path[i])
		print("  %d corners, %.1f m: %s -> %s" % [path.size(), length,
			path[0].snapped(Vector3.ONE * 0.1), path[path.size() - 1].snapped(Vector3.ONE * 0.1)])
	if runs.is_empty():
		_fail("no rat runs: the droppings and streaks would have nowhere to go")
	var droppings := _world.get_node_or_null("Clues/Droppings")
	var piles := droppings.get_child_count() if droppings != null else 0
	print("  dropping piles laid: %d" % piles)
	if piles == 0:
		_fail("no droppings were laid")


func _report() -> void:
	print("\n=== %s ===" % ("FAILURES" if not _failures.is_empty() else "ALL CHECKS PASSED"))
	for f in _failures:
		print("  ✗ " + f)


func _fail(message: String) -> void:
	_failures.append(message)


## Nodes carrying a given script, matched by the script's own resource path. A
## script attached with `set_script` at runtime does not answer to its
## `class_name` here, so the file is what is compared.
func _scripted(script_file: String) -> Array:
	return _walk(_world, func(n: Node) -> bool:
		var sc: Script = n.get_script() as Script
		return sc != null and sc.resource_path.ends_with(script_file))


func _prompts() -> Array:
	return _walk(_world, func(n: Node) -> bool:
		return n is Area3D and str(n.name).ends_with("_Use"))


func _meshes(from: Node) -> Array:
	return _walk(from, func(n: Node) -> bool: return n is MeshInstance3D)


func _walk(n: Node, test: Callable) -> Array:
	var out: Array = []
	if test.call(n):
		out.append(n)
	for c in n.get_children():
		out.append_array(_walk(c, test))
	return out
