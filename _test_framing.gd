extends SceneTree
## Framing bench: grabs a rat, leaves it in the hand and measures how its body
## falls on screen — how far up, how far down, how far out to each side — as well
## as saving pictures of the resting moment, of a squeeze and of the body going
## limp.
##
## Run with a window (without `--headless`, which draws nothing):
##   godot --script _test_framing.gd
##
## The pictures come out in the project's data folder, whose path is printed at
## the end.

const SIZE := Vector2i(1141, 634)
const STATION := Vector3(0.0, 0.0, 1.6)
const TARGET_HEIGHT := 0.2

var _world: Node3D
var _player: CharacterBody3D
var _head: Node3D
var _hands: Node3D
var _camera: Camera3D
var _rat: Node3D
var _step := 0
var _clock := 0
## The step's clock in seconds. The portraits go by it, and not by frames:
## writing a PNG costs time, and the gesture runs on `delta` as it does in the
## game.
var _time := 0.0

func _initialize() -> void:
	Engine.max_fps = 60
	DisplayServer.window_set_size(SIZE)
	_world = load("res://scenes/world.tscn").instantiate()
	root.add_child(_world)
	_player = _world.get_node("Player")
	_head = _player.get_node("Head")
	_hands = _player.get_node("Head/Hands")
	_camera = _player.get_node("Head/Camera")
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)

func _process(delta: float) -> bool:
	# The player captures the mouse in `_ready`; here it stays free, otherwise
	# the bench would hijack the cursor of whoever is running it.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clock += 1
	_time += delta
	match _step:
		0: return _grab()
		1: return _wait_in_hand()
		2: return _portrait("hand-resting", 0.5)
		3: return _squeeze_and_portrait()
		4: return _kill()
		5: return _portrait("going-limp", 0.12)
		# The stowing: the body leaving the hand for the waist, frame by frame.
		6: return _portrait("stowing-1", 0.45)
		7: return _portrait("stowing-2", 0.12)
		8: return _portrait("stowing-3", 0.12)
	# A breather so the last picture finishes being written.
	return _clock > 10

func _grab() -> bool:
	if _clock < 20 or _player.capture_started.get_connections().is_empty():
		return false
	_rat = _closest()
	if _rat == null:
		print("FAIL: no rat nearby")
		return true
	_aim_at(_rat)
	_hands.try_use()
	if not _rat.is_captured():
		print("FAIL: did not capture")
		return true
	return _advance()

func _wait_in_hand() -> bool:
	if not _rat.is_in_hand():
		return _clock > 300
	return _advance()

## Waits `wait` seconds, measures the framing and saves the picture.
func _portrait(label: String, wait: float) -> bool:
	if _time < wait:
		return false
	if not is_instance_valid(_rat):
		print("%-12s the rat had already been stowed" % label)
		return _advance()
	_measure(label)
	_save(label)
	return _advance()

func _squeeze_and_portrait() -> bool:
	if _clock == 1:
		_hands.press_secondary()
		return false
	return _portrait("squeeze", 0.05)

func _kill() -> bool:
	while _hands.is_busy():
		_hands.press_secondary()
	return _advance()

# --- Measurement -----------------------------------------------------------

## Where the rat's body falls on screen, as a fraction of the frame: 0 is the top
## edge (or the left one), 1 the bottom (or the right one), 0.5 the centre.
func _measure(label: String) -> void:
	var mesh: MeshInstance3D = _rat.get_node("Model/Mesh/Rat/Skeleton3D/Rat Model")
	var aabb := mesh.get_aabb()
	var t := mesh.global_transform
	var minimum := Vector2.INF
	var maximum := -Vector2.INF
	var nearest := INF
	for i in 8:
		var world := t * aabb.get_endpoint(i)
		var screen := _camera.unproject_position(world)
		minimum = minimum.min(screen)
		maximum = maximum.max(screen)
		nearest = minf(nearest, _camera.global_position.distance_to(world))
	var frame := Vector2(root.size)
	var center := (minimum + maximum) * 0.5 / frame
	print("%-12s x %.2f..%.2f  y %.2f..%.2f  center (%.2f, %.2f)  closest tip to the camera: %.2f m" % [
		label, minimum.x / frame.x, maximum.x / frame.x,
		minimum.y / frame.y, maximum.y / frame.y, center.x, center.y, nearest,
	])

	# The AABB is the model's rest pose; what rules the framing is the pose it is
	# really in, and only the bones tell that.
	var skeleton: Skeleton3D = _rat.get_node("Model/Mesh/Rat/Skeleton3D")
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i)
		if bone not in ["Head_end", "Head", "Body_Upper", "Body_Lower", "B_Leg.l", "Tail_2_end"]:
			continue
		var screen := _camera.unproject_position(skeleton.global_transform * skeleton.get_bone_global_pose(i).origin) / frame
		print("    %-12s screen (%.2f, %.2f)" % [bone, screen.x, screen.y])

func _save(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var file := "user://framing-%s.png" % label
	image.save_png(file)
	print("    picture at %s" % ProjectSettings.globalize_path(file))

# --- Utilities -------------------------------------------------------------

func _aim_at(rat: Node3D) -> void:
	var target := rat.global_position + Vector3.UP * TARGET_HEIGHT
	_player.global_position = rat.global_position + STATION
	_player.look_at(Vector3(target.x, _player.global_position.y, target.z), Vector3.UP)
	_player.rotation.x = 0.0
	_player.rotation.z = 0.0
	var eye := _head.global_position
	_head.rotation.x = atan2(target.y - eye.y, Vector2(target.x - eye.x, target.z - eye.z).length())

func _advance() -> bool:
	_step += 1
	_clock = 0
	_time = 0.0
	return false

func _closest() -> Node3D:
	var best: Node3D = null
	var smallest := INF
	for node in get_nodes_in_group("rats"):
		var rat := node as Node3D
		var distance := rat.global_position.distance_to(_player.global_position)
		if distance < smallest:
			smallest = distance
			best = rat
	return best
