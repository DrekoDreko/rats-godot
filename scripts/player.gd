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
##
## Which weapon that is, is the belt's business (`scripts/weapons/inventory.gd`):
## `1`, `2` and `3` swap slots, and the player talks to the belt instead of to
## any one weapon — so a slot with nothing in it is a click that finds nothing
## to do, and not a crash.
##
## The player also has flesh to lose (`take_damage`), and it is the only door
## into it: whatever comes to bite him knocks here, and the health bar over the
## belt (`scripts/hud_health.gd`) hears about it by signal. Nothing in the map
## hurts him yet — the rats only run.
##
## And he has hands for things that are not rats: a short ray out of the camera
## (`Head/Camera/Interact`) looks for whatever he could put them on, and `E` uses
## it (`scripts/interaction/interactable.gd`). What that opens — the computer's
## shop, for now — takes the player over while it is on screen: `set_ui_open()`
## lets the mouse loose to click with and stops the body from answering to
## anything, which is the only way a click can reach a button instead of being
## spent grabbing the camera back.

signal attacked(hit: bool)
## Relays from the weapon to the HUD.
signal capture_started(rat: Node3D)
signal capture_progress(fraction: float)
signal capture_finished(killed: bool)
## Swapped slots. `weapon` comes in null on an empty slot. It is what the hotbar
## listens to.
signal weapon_changed(index: int, weapon: Weapon)
## The flesh changed, wound or bandage alike. It is what the health bar listens
## to, and it goes out on the healing at respawn too, so nothing on screen is
## left showing a corpse's health.
signal health_changed(current: int, maximum: int)
## Just took a wound. `remaining` is what was left standing after it — enough
## for the HUD to flash without having to keep a count of its own.
signal damaged(amount: int, remaining: int)
## Ran out of flesh. It goes out before the respawn, so whoever wants to put an
## end-of-shift screen in the way has somewhere to stand.
signal died()
## What the player could put his hands on right now, or null with nothing in
## front of him. It is what the on-screen prompt listens to.
signal interactable_changed(interactable: Interactable)

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

@export_group("Health")
## How much flesh the player has. It is read once, when the shift starts, and
## again at every respawn.
@export var max_health := 100

## Vertical pitch limit of the camera (degrees), so it never goes upside down.
const MAX_PITCH := 89.0
## Window in which a jump still works after leaving the ground.
const COYOTE_TIME := 0.12
## Height at which the character is sent back to his starting point.
const MIN_HEIGHT := -20.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var inventory: Inventory = $Head/Inventory
## The reach of the hands for things that are not rats. It only sees the
## interactable layer, so it never trips over the scenery or over an animal.
@onready var interact_ray: RayCast3D = $Head/Camera/Interact

var _start_position: Vector3
var _air_time := 0.0
## What is left of `max_health`. Zero is a dead player, and only for the instant
## it takes to send him back to the start.
var _health := 0
## What is in front of him, or null. Only what changes is announced.
var _focused: Interactable
## A screen has the player: the mouse is loose on it and the body is out of the
## game until it closes.
var _ui_open := false

func _ready() -> void:
	_start_position = global_position
	_health = max_health
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Every weapon on the belt is wired up once, and not the one in hand at each
	# swap: a weapon that is put away never reaches `_use()`, so it never has
	# anything to announce.
	for weapon in inventory.weapons():
		weapon.used.connect(func(hit: bool) -> void: attacked.emit(hit))
		weapon.caught.connect(func(rat: Node3D) -> void: capture_started.emit(rat))
		weapon.pressure_changed.connect(func(fraction: float) -> void: capture_progress.emit(fraction))
		weapon.finished.connect(func(killed: bool) -> void: capture_finished.emit(killed))
	inventory.equipped.connect(func(index: int, weapon: Weapon) -> void: weapon_changed.emit(index, weapon))

func _unhandled_input(event: InputEvent) -> void:
	# With a screen open the player is not in the map: the mouse belongs to the
	# buttons, and neither the camera nor the belt hears anything. The key that
	# closes it is the screen's own business, and it never reaches this far.
	if _ui_open:
		return
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
	elif event.is_action_pressed("strangle") and inventory.is_busy():
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			inventory.press_secondary()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("interact") and _focused != null:
		_focused.use(self)
	elif event.is_action_pressed("attack"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			inventory.try_use()
		else:
			# Clicking on the window gives camera control back to the mouse.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_handle_slot_keys(event)

## `1`, `2` and `3`: the belt. Unlike the click, this one works with the mouse
## loose too — it is a key, and it is not fighting anybody over the camera. The
## belt itself is what turns the swap down with a rat in hand.
func _handle_slot_keys(event: InputEvent) -> void:
	for i in inventory.slot_count():
		if event.is_action_pressed("slot_%d" % (i + 1)):
			inventory.equip(i)
			return

func _physics_process(delta: float) -> void:
	_update_focus()
	var busy := inventory.is_busy()

	if is_on_floor():
		_air_time = 0.0
	else:
		_air_time += delta
		velocity.y -= gravity * delta

	# With the hands full there is no jumping: holding the rat is work enough.
	if not busy and not _ui_open and Input.is_action_just_pressed("jump") and _air_time <= COYOTE_TIME:
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
	if _ui_open:
		return Vector3.ZERO
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

# --- Hands on --------------------------------------------------------------

## What the ray out of the camera is on, if anything. With a rat in hand, or with
## a screen already open, there is nothing to reach for: the prompt goes off the
## screen the same way the crosshair does.
func _update_focus() -> void:
	var found: Interactable = null
	if not _ui_open and not inventory.is_busy():
		found = interact_ray.get_collider() as Interactable
	if found == _focused:
		return
	_focused = found
	interactable_changed.emit(_focused)

## Hands a screen the player, or gives him back. Whoever opens one is the one who
## closes it (`scripts/hud_shop.gd`): the mouse comes loose to click with, and
## the body stops in place until it is gone.
func set_ui_open(open: bool) -> void:
	if _ui_open == open:
		return
	_ui_open = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	velocity.x = 0.0
	velocity.z = 0.0
	if open and _focused != null:
		_focused = null
		interactable_changed.emit(null)

func is_ui_open() -> bool:
	return _ui_open

## What the player is looking at, or null. The screen that opens off it needs to
## know who called it.
func focused() -> Interactable:
	return _focused

# --- Flesh -----------------------------------------------------------------
# The health bar over the belt does not keep a count of its own: it reads what
# is here at the start and follows the signals from then on.

## Takes a wound. Everything that hurts the player comes through here, and a
## wound bigger than what is left standing kills instead of going negative.
func take_damage(amount: int = 1) -> void:
	if amount <= 0 or is_dead():
		return
	_health = maxi(0, _health - amount)
	damaged.emit(amount, _health)
	health_changed.emit(_health, max_health)
	if _health == 0:
		_die()

## Patches the player back up, never past the flesh he started the shift with.
func heal(amount: int = 1) -> void:
	if amount <= 0 or is_dead():
		return
	var healed := mini(max_health, _health + amount)
	if healed == _health:
		return
	_health = healed
	health_changed.emit(_health, max_health)

func health() -> int:
	return _health

## What is left, from 0 to 1. It is what the bar on screen is drawn from.
func health_fraction() -> float:
	return 0.0 if max_health <= 0 else float(_health) / float(max_health)

func is_dead() -> bool:
	return _health <= 0

## Dying, for now, is what falling off the map already was: the player wakes up
## back where the shift started, whole again, and what he earned stays in the
## wallet. A rat still kicking in his hands comes back with him — nothing kills
## the player yet, so there is no losing a capture to it either.
func _die() -> void:
	died.emit()
	respawn()
	_health = max_health
	health_changed.emit(_health, max_health)
