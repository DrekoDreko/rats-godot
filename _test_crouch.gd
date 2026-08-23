extends SceneTree
## Crouch test bench: the body going down, staying down under something, and
## coming back up.
##
## Run with: godot --headless --script _test_crouch.gd
##
## Three things are worth checking here and the rest follows from them. That the
## capsule and the head come down together and that his feet stay on the floor
## while they do — a capsule shrunk about its own middle would sink him through
## the boards. That crouched he is slower than he walks and that holding Shift
## crouched buys him nothing. And that a ceiling is the one thing that outranks
## the key: under a table, letting go of Ctrl leaves him down until he walks out
## from under it.
##
## The player is driven by hand: physics is left running (the crouch is counted
## in `_physics_process` and the capsule has to actually rest on the floor), but
## nothing is typed at him except through `Input.action_press`.

## Frames of slack between one step and the next.
const WAIT := 8
## Where the player stands for the open-air part of the bench: the map's own
## starting point, which is open floor by construction.
const FLOOR_STATION := Vector3(0.0, 0.1, 4.0)
## What the crouch leaves of his height (`Player.CROUCH_SCALE`), and how much of
## a gap the comparisons allow — the crouch travels over several frames, so a
## height read a frame early is a hair off.
const CROUCH_SCALE := 0.55
const SLACK := 0.02

var _world: Node3D
var _player: CharacterBody3D
var _head: Node3D
var _collision: CollisionShape3D
## The lid put over his head to check that a ceiling beats the key. It is built
## here rather than looked for in the map, so the bench does not depend on there
## being a low place in it.
var _lid: StaticBody3D

var _stand_height := 0.0
var _stand_head := 0.0
var _stand_feet := 0.0

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0

func _initialize() -> void:
	# Without a screen the loop would run at thousands of frames per second and a
	# whole crouch would pass between two physics frames.
	Engine.max_fps = 60
	_world = load("res://scenes/world.tscn").instantiate()
	root.add_child(_world)
	_player = _world.get_node("Player")
	_head = _player.get_node("Head")
	_collision = _player.get_node("Collision")
	# His own input is left alone: everything here is pressed at him through the
	# `Input` singleton, which is what he reads anyway.
	_player.set_process_unhandled_input(false)

func _physics_process(delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_setup()
		1: return _check_goes_down()
		2: return _check_feet_stay_down()
		3: return _check_crouch_is_slow()
		4: return _check_no_sprint_crouched()
		5: return _check_stands_back_up()
		6: return _check_ceiling_holds_him_down()
		7: return _check_walks_out_and_stands()
		8: return _check_respawn_stands_him_up()
		_: return _finish()

# --- The steps --------------------------------------------------------------

## The standing body, measured before anything is pressed. Everything after this
## is read against these three numbers.
func _check_setup() -> bool:
	_player.global_position = FLOOR_STATION
	var shape := _collision.shape as CapsuleShape3D
	_stand_height = shape.height
	_stand_head = _head.position.y
	_stand_feet = _collision.position.y - shape.height * 0.5
	_expect(_stand_height > 0.0, "the standing capsule has a height")
	_expect(not _player.is_crouching(), "he starts the shift on his feet")
	return _advance()

## Ctrl down: the capsule and the head both come to `CROUCH_SCALE` of what they
## were, and they get there together.
func _check_goes_down() -> bool:
	Input.action_press("crouch")
	if _clock < WAIT * 3:
		return false
	var shape := _collision.shape as CapsuleShape3D
	_expect(_player.is_crouching(), "holding Ctrl puts him down")
	_expect(
		absf(shape.height - _stand_height * CROUCH_SCALE) < SLACK,
		"the capsule came down to %.2f (was %.2f)" % [shape.height, _stand_height]
	)
	_expect(
		absf(_head.position.y - _stand_head * CROUCH_SCALE) < SLACK,
		"the head came down to %.2f (was %.2f)" % [_head.position.y, _stand_head]
	)
	return _advance()

## The one that would be a bug and not a wrong number: he shrinks from the top
## down, so the bottom of the capsule is where it always was and he is standing
## on the floor rather than in it.
func _check_feet_stay_down() -> bool:
	var shape := _collision.shape as CapsuleShape3D
	var feet := _collision.position.y - shape.height * 0.5
	_expect(
		absf(feet - _stand_feet) < SLACK,
		"his feet stayed at %.2f (were %.2f)" % [feet, _stand_feet]
	)
	_expect(_player.is_on_floor(), "and he is still standing on the floor")
	return _advance()

## Crouched he is slower than he walks, which is the whole reason to do it.
func _check_crouch_is_slow() -> bool:
	var speed: float = _player.call("_target_speed", false)
	_expect(
		speed < _player.walk_speed,
		"crouched he wants %.1f, slower than his %.1f walk" % [speed, _player.walk_speed]
	)
	return _advance()

## And Shift buys him nothing down there: there is no sprinting on your knees.
func _check_no_sprint_crouched() -> bool:
	var quiet: float = _player.call("_target_speed", false)
	Input.action_press("run")
	var pressed: float = _player.call("_target_speed", false)
	Input.action_release("run")
	_expect(
		is_equal_approx(quiet, pressed),
		"Shift crouched changes nothing (%.1f either way)" % quiet
	)
	return _advance()

## Ctrl up in the open: he comes all the way back to the body he started with.
func _check_stands_back_up() -> bool:
	Input.action_release("crouch")
	if _clock < WAIT * 3:
		return false
	var shape := _collision.shape as CapsuleShape3D
	_expect(not _player.is_crouching(), "letting go of Ctrl stands him up")
	_expect(
		absf(shape.height - _stand_height) < SLACK,
		"the capsule is back to %.2f" % shape.height
	)
	_expect(absf(_head.position.y - _stand_head) < SLACK, "and so is the head")
	return _advance()

## The rule that is not simply following the key. A lid is put over his head
## while he is down, and letting go of Ctrl under it leaves him down.
func _check_ceiling_holds_him_down() -> bool:
	if _lid == null:
		Input.action_press("crouch")
		_lid = _build_lid(_player.global_position + Vector3(0.0, 1.3, 0.0))
		return false
	if _clock < WAIT * 3:
		return false
	Input.action_release("crouch")
	if _clock < WAIT * 6:
		return false
	_expect(_player.is_crouching(), "under the lid he stays down with Ctrl let go")
	return _advance()

## And out from under it he gets up on his own, without being asked again.
func _check_walks_out_and_stands() -> bool:
	if _clock < WAIT:
		_player.global_position = FLOOR_STATION + Vector3(6.0, 0.0, 0.0)
		return false
	if _clock < WAIT * 4:
		return false
	_expect(not _player.is_crouching(), "out in the open he stands up by himself")
	return _advance()

## A respawn is a body put back where the shift started, and that body is on its
## feet: waking up folded in half under a ceiling that is nowhere near him would
## leave him low until he thought to press Ctrl and let go of it.
func _check_respawn_stands_him_up() -> bool:
	if _clock < WAIT:
		Input.action_press("crouch")
		return false
	if _clock < WAIT * 3:
		return false
	if not _player.is_crouching():
		_expect(false, "he is down before the respawn")
		return _advance()
	_player.respawn()
	Input.action_release("crouch")
	var shape := _collision.shape as CapsuleShape3D
	_expect(not _player.is_crouching(), "the respawn stands him up")
	_expect(
		absf(shape.height - _stand_height) < SLACK,
		"with the capsule he started the shift with (%.2f)" % shape.height
	)
	return _advance()

# --- Tools ------------------------------------------------------------------

## A slab of scenery hanging in the air, low enough that the standing capsule
## would not fit under it. It is on layer 1 because that is the layer the
## player's ceiling cast looks at.
func _build_lid(spot: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.2, 4.0)
	shape.shape = box
	body.add_child(shape)
	_world.add_child(body)
	body.global_position = spot
	return body

func _expect(condition: bool, description: String) -> void:
	if condition:
		print("  ok   %s" % description)
	else:
		print("  FAIL %s" % description)
		_failures += 1

func _advance() -> bool:
	_step += 1
	_clock = 0
	return false

func _finish() -> bool:
	if _lid != null:
		_lid.queue_free()
	Input.action_release("crouch")
	if _failures == 0:
		print("\ncrouch: all checks passed")
	else:
		print("\ncrouch: %d check(s) failed" % _failures)
	quit(0 if _failures == 0 else 1)
	return true
