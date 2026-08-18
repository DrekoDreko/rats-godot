extends CharacterBody3D
## First-person character.
## WASD/arrows move relative to where the player is looking, Shift runs, Space
## jumps, the mouse looks around and the left button uses the current weapon.
##
## The player does not know how to kill a rat: the weapon hanging off his head
## does (`scripts/weapons/`). Today that is the pair of hands, which grabs the
## rat instead of killing it — and from then on the same click that grabbed
## starts strangling, while the player walks slowly, and without jumping, with
## the animal struggling in his hand.

signal attacked(hit: bool)
## Relays from the weapon to the HUD.
signal capture_started(rat: Node3D)
signal capture_progress(fraction: float)
signal capture_finished(killed: bool)

@export_group("Movement")
@export var walk_speed := 6.0
@export var run_speed := 10.5
## Speed with a rat struggling in the hands: enough to walk, not to hunt.
@export var holding_speed := 3.5
@export var acceleration := 52.0
@export var deceleration := 68.0
@export var jump_height := 1.5
@export var gravity := 22.0
@export var mouse_sensitivity := 0.0035

## Vertical pitch limit of the camera (degrees), so it never goes upside down.
const MAX_PITCH := 89.0
## Window in which a jump still works after leaving the ground.
const COYOTE_TIME := 0.12
## Height at which the character is sent back to his starting point.
const MIN_HEIGHT := -20.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var weapon: Weapon = $Head/Hands

var _start_position: Vector3
var _air_time := 0.0

func _ready() -> void:
	_start_position = global_position
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	weapon.used.connect(func(hit: bool) -> void: attacked.emit(hit))
	weapon.caught.connect(func(rat: Node3D) -> void: capture_started.emit(rat))
	weapon.pressure_changed.connect(func(fraction: float) -> void: capture_progress.emit(fraction))
	weapon.finished.connect(func(killed: bool) -> void: capture_finished.emit(killed))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# The whole body turns horizontally; only the head looks up and down.
		rotation.y -= event.relative.x * mouse_sensitivity
		head.rotation.x = clampf(
			head.rotation.x - event.relative.y * mouse_sensitivity,
			deg_to_rad(-MAX_PITCH),
			deg_to_rad(MAX_PITCH)
		)
	elif event.is_action_pressed("toggle_mouse"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# The same click grabs and strangles, so with the hands full this one comes
	# first: there is nothing to grab with a rat already held.
	elif event.is_action_pressed("strangle") and weapon.is_busy():
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			weapon.press_secondary()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("attack"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			weapon.try_use()
		else:
			# Clicking on the window gives camera control back to the mouse.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var busy := weapon.is_busy()

	if is_on_floor():
		_air_time = 0.0
	else:
		_air_time += delta
		velocity.y -= gravity * delta

	# With the hands full there is no jumping: holding the rat is work enough.
	if not busy and Input.is_action_just_pressed("jump") and _air_time <= COYOTE_TIME:
		velocity.y = sqrt(2.0 * gravity * jump_height)
		_air_time = COYOTE_TIME + 1.0

	var direction := _desired_direction()
	var target := direction * _target_speed(busy)
	var rate := acceleration if direction != Vector3.ZERO else deceleration
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)

	move_and_slide()

	if global_position.y < MIN_HEIGHT:
		respawn()

func _target_speed(busy: bool) -> float:
	if busy:
		return holding_speed
	return run_speed if Input.is_action_pressed("run") else walk_speed

## Movement direction on the XZ plane, relative to where the character faces.
func _desired_direction() -> Vector3:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var base := global_basis
	var direction := base.z * input.y + base.x * input.x
	direction.y = 0.0
	return direction.normalized()

func respawn() -> void:
	velocity = Vector3.ZERO
	rotation.y = 0.0
	head.rotation.x = 0.0
	global_position = _start_position
