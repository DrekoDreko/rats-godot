extends CharacterBody3D
## First-person character.
## WASD/arrows move relative to where the player is looking, Shift runs, Ctrl
## crouches, Space jumps, the mouse looks around and the left button uses the
## current weapon.
##
## The player does not know how to kill a rat: the weapon hanging off his head
## does (`scripts/weapons/`). Today that is the pair of hands, which grabs the
## rat instead of killing it — and from then on the same click that grabbed
## starts strangling, while the player walks slowly, and without jumping, with
## the animal struggling in his hand.
##
## Which weapon that is, is the belt's business (`scripts/weapons/inventory.gd`):
## `1`, `2` and `3` swap slots, `Q` puts the hands back — they take no slot,
## because they were never bought — and the player talks to the belt instead of
## to any one weapon, so a slot with nothing in it is a click that finds nothing
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
##
## And he is being watched. In a lobby, everything the other players see of him
## is read off two things — `animation_state()` and the `attacked` signal — by
## the avatar that stands for him on their screens
## (`scripts/steam/player_avatar.gd`). Nothing in this file knows that the wire
## exists: somebody else reads him and puts him on it.

signal attacked(hit: bool)
## Relays from the weapon to the HUD.
signal capture_started(rat: Node3D)
signal capture_progress(fraction: float)
signal capture_finished(killed: bool)
## Swapped slots. `weapon` comes in null on an empty slot, and `index` comes in
## `Inventory.HANDS_INDEX` with the hands out — no square to frame. It is what
## the hotbar listens to.
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
## Hands on something slow. Not everything answers to a tap: a fouled trap has to
## be stood over and cleaned out, and while that is going on there is a bar on
## screen instead of a prompt (`scripts/hud_hold.gd`).
signal hold_started(interactable: Interactable)
signal hold_progress(fraction: float)
## Finger up, eyes away, or the job done. `completed` tells the two apart.
signal hold_finished(completed: bool)

@export_group("Movement")
@export var walk_speed := 6.0
@export var run_speed := 10.5
## Speed with a rat struggling in the hands: enough to walk, not to hunt.
@export var holding_speed := 3.5
## Speed crouched. Slower than a rat's wander, which is the point of it: it buys
## quiet, not ground.
@export var crouch_speed := 2.8
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
## Below this much horizontal speed he is standing still as far as anybody
## watching him is concerned — a hair of drift after a stop is not a walk.
const IDLE_SPEED := 0.3
## Window in which a jump still works after leaving the ground.
const COYOTE_TIME := 0.12
## How much of his height is left when he is down: the capsule and the head both
## come to this fraction of what they are standing up.
const CROUCH_SCALE := 0.55
## How fast he goes down and comes back up, in fractions of the way per second.
## Fast enough to duck under something on the move, slow enough to be a movement
## and not a change of camera.
const CROUCH_SPEED := 9.0
## Height at which the character is sent back to his starting point.
const MIN_HEIGHT := -20.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var inventory: Inventory = $Head/Inventory
@onready var collision: CollisionShape3D = $Collision
## The room over his head, asked only when he wants it back: it is the standing
## capsule put where the standing capsule would go, and anything it touches is a
## ceiling he cannot get up through.
@onready var ceiling: ShapeCast3D = $Ceiling
## The reach of the hands for things that are not rats. It only sees the
## interactable layer, so it never trips over the scenery or over an animal.
@onready var interact_ray: RayCast3D = $Head/Camera/Interact
@onready var flashlight: SpotLight3D = get_node_or_null(^"Head/Camera/Flashlight") as SpotLight3D
## The body he is wearing. He never sees it — he is inside it — but it is what
## casts his shadow on the floor, and the same scene the other players are drawn
## with (`scripts/player_model.gd`), so his walk on their screens and his shadow
## on his own come off one animation.
@onready var model: PlayerModel = $Model

var _start_position: Vector3
var _air_time := 0.0
## How far down he is, from 0 standing to 1 fully crouched. It is a fraction and
## not a flag because the body moves through it: everything that depends on his
## height is read off this and follows it down.
var _crouch := 0.0
## Standing height of the capsule and of the head, read once off the scene so
## that moving either in the editor moves the crouch with it.
var _stand_height := 0.0
var _stand_head := 0.0
var _stand_collision_y := 0.0
## What is left of `max_health`. Zero is a dead player, and only for the instant
## it takes to send him back to the start.
var _health := 0
## What is in front of him, or null. Only what changes is announced.
var _focused: Interactable
## The slow thing he is working on, and how long he has been at it. Null with his
## finger off the key, and null the instant he looks away — there is no such thing
## as half a cleaned trap waiting for him to come back to it.
var _hold_target: Interactable
var _hold_time := 0.0
## A screen has the player: the mouse is loose on it and the body is out of the
## game until it closes.
var _ui_open := false

func _ready() -> void:
	_start_position = global_position
	_health = max_health
	# The shape is duplicated before a single frame is drawn: the one in the scene
	# is shared with the ceiling cast — and with every other player in a lobby —
	# and shrinking it in place would crouch all of them at once.
	var shape := collision.shape as CapsuleShape3D
	collision.shape = shape.duplicate()
	_stand_height = shape.height
	_stand_collision_y = collision.position.y
	_stand_head = head.position.y
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# He is inside his own body, so the mesh would be the inside of his own head.
	# The shadow it throws is still his and still worth having.
	model.set_shadows_only(true)
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
	# Before the mouse toggle, because the two share Esc: a strip of glue half
	# laid is the first thing Esc can mean, and only once there is none of it
	# does the key go back to meaning what it usually means. The belt answers
	# whether there was in fact anything to call off, so nothing is swallowed on
	# a weapon that had nothing going on.
	elif event.is_action_pressed("cancel") and inventory.cancel():
		pass
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
		# The slow ones are not used on the press: the press is only the start of
		# the holding, and the holding is counted where the frames are
		# (`_update_hold`).
		if not _focused.is_held_work():
			_focused.use(self)
	elif event.is_action_pressed("attack"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			inventory.try_use()
		else:
			# Clicking on the window gives camera control back to the mouse.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_handle_slot_keys(event)

## `1`, `2` and `3`: the belt. `Q`: the hands, which are on no slot and are
## always there to come back to. Unlike the click, these work with the mouse
## loose too — they are keys, and they are not fighting anybody over the camera.
## The belt itself is what turns the swap down with a rat in hand.
func _handle_slot_keys(event: InputEvent) -> void:
	if event.is_action_pressed("hands"):
		inventory.equip_hands()
		return
	for i in inventory.slot_count():
		if event.is_action_pressed("slot_%d" % (i + 1)):
			inventory.equip(i)
			return

func _physics_process(delta: float) -> void:
	_update_focus()
	_update_hold(delta)
	_update_crouch(delta)
	var busy := inventory.is_busy()

	if is_on_floor():
		_air_time = 0.0
	else:
		_air_time += delta
		velocity.y -= gravity * delta

	# With the hands full there is no jumping: holding the rat is work enough. Nor
	# from down on his knees — pressing jump while crouched only lets go of the
	# crouch, and the jump belongs to whoever is standing when he presses it.
	if not busy and not _ui_open and not is_crouching() and Input.is_action_just_pressed("jump") and _air_time <= COYOTE_TIME:
		velocity.y = sqrt(2.0 * gravity * jump_height)
		_air_time = COYOTE_TIME + 1.0

	var direction := _desired_direction()
	var target := direction * _target_speed(busy)
	var rate := acceleration if direction != Vector3.ZERO else deceleration
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)

	move_and_slide()

	# After the move, not before: `animation_state()` reads what the body did
	# this frame, and asking it beforehand would draw him doing what he was doing
	# a frame ago — walking into a wall included.
	model.set_state(animation_state())

	if global_position.y < MIN_HEIGHT:
		respawn()

## How fast he is trying to go. The order is the order of what wins: a rat in the
## hands is the slowest thing there is, and being down beats wanting to run —
## there is no sprinting on your knees, and holding Shift while crouched does
## nothing at all.
##
## Between standing and crouched it is not one speed or the other but the way
## from one to the other, because that is what his body is doing: going down
## slows him as he goes down, and standing up gives it back as he comes up.
func _target_speed(busy: bool) -> float:
	if busy:
		return holding_speed
	var upright := run_speed if Input.is_action_pressed("run") else walk_speed
	return lerpf(upright, crouch_speed, _crouch)

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

# --- Down on his knees ------------------------------------------------------

## Ctrl held is the whole of the asking, and the answer is not always yes: what
## he wants goes one way, and what there is room for goes the other. Under a
## table there is no standing up, so letting go of Ctrl leaves him down until he
## walks out from under it — which is the one rule here that is not simply
## following the key.
##
## The crouch travels rather than switching, and everything that reads off his
## height reads off the travel: the capsule, the head the camera hangs from and
## the speed all follow the same fraction, so at no point is he a short body
## with a tall head or a crouching body running.
func _update_crouch(delta: float) -> void:
	var wanted := not _ui_open and Input.is_action_pressed("crouch")
	if not wanted and _crouch > 0.0 and _is_blocked_above():
		wanted = true
	var target := 1.0 if wanted else 0.0
	if is_equal_approx(_crouch, target):
		# Already all the way there. Snapped rather than left a hair off, so that
		# a body which is standing is standing exactly as the scene drew him.
		_crouch = target
	else:
		_crouch = move_toward(_crouch, target, CROUCH_SPEED * delta)
	_apply_crouch()

## Puts the fraction on the body. The capsule shrinks from the top down — its
## middle comes down by half of what its height loses — because his feet stay on
## the floor: growing it about its own centre would push him through it.
func _apply_crouch() -> void:
	var height := lerpf(_stand_height, _stand_height * CROUCH_SCALE, _crouch)
	var shape := collision.shape as CapsuleShape3D
	shape.height = height
	collision.position.y = _stand_collision_y - (_stand_height - height) * 0.5
	head.position.y = lerpf(_stand_head, _stand_head * CROUCH_SCALE, _crouch)

## Is there a ceiling in the way of standing back up? The cast is the standing
## capsule put where the standing capsule would sit, asked once and only when he
## is trying to get up — a shape cast left running every frame is a cost paid for
## an answer nobody wanted.
func _is_blocked_above() -> bool:
	ceiling.position.y = _stand_collision_y
	ceiling.force_shapecast_update()
	return ceiling.is_colliding()

## Down, or on his way down. Anything asking whether he is crouched wants this
## and not the fraction: halfway to the floor is already too low to jump from.
func is_crouching() -> bool:
	return _crouch > 0.0

## Where the shift starts, and where a respawn brings him back to. The map puts
## him on his spot once, on the way in — with three other people pressing PLAY on
## the same starting point, somebody has to (`scripts/steam/player_avatars.gd`)
## — and moving him without moving this would send him back inside a colleague
## the first time he falls off the world.
func set_spawn(spot: Vector3) -> void:
	global_position = spot
	_start_position = spot

## The spot a respawn brings him back to. Worth asking for rather than assuming
## where he stood at load: the map moves it on the way in.
func spawn_point() -> Vector3:
	return _start_position

func respawn() -> void:
	velocity = Vector3.ZERO
	rotation.y = 0.0
	head.rotation.x = 0.0
	# On his feet again. Waking up back at the van still folded in half — because
	# the ceiling he died under is nowhere near him now — would leave him low
	# until he thought to press Ctrl and let go of it.
	_crouch = 0.0
	_apply_crouch()
	# And on his feet in the drawing too, not only in the collision. A man who
	# died falling would otherwise stand at the van still folded into the pose of
	# the jump, until the next physics frame thought better of it.
	model.set_state(PlayerAvatar.State.IDLE)
	global_position = _start_position

## What he looks like he is doing, for the benefit of the other players' screens
## (`scripts/steam/player_avatar.gd`). It is read off what the body actually did
## this frame and not off what was pressed: a player walking into a wall is
## standing still, whatever his keyboard says, and that is what the man watching
## him should see.
##
## The order is the order of what wins. A rat in the hands is the whole of what
## he is doing, however he is moving; being off the ground beats being on it;
## being down on his knees beats being on his feet; and the difference between
## walking and running is drawn halfway between the two speeds, so the moment he
## crosses it is the moment he looks like it.
##
## Down on his knees he is told apart moving from still, which he was not while
## the body was a capsule. The reasoning then was that the two look the same
## across a dark room, and they did, because a capsule had no legs to show the
## difference with. The model does, and a man creeping towards you is worth
## telling from a man sitting still — so the same `IDLE_SPEED` that separates
## standing from walking separates kneeling from creeping.
func animation_state() -> PlayerAvatar.State:
	if inventory.is_busy():
		return PlayerAvatar.State.HOLDING
	if not is_on_floor():
		return PlayerAvatar.State.AIRBORNE
	var speed := Vector2(velocity.x, velocity.z).length()
	if is_crouching():
		return PlayerAvatar.State.CROUCH_WALKING if speed >= IDLE_SPEED \
			else PlayerAvatar.State.CROUCHING
	if speed < IDLE_SPEED:
		return PlayerAvatar.State.IDLE
	if speed > (walk_speed + run_speed) * 0.5:
		return PlayerAvatar.State.RUNNING
	return PlayerAvatar.State.WALKING

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

## The slow jobs: the ones he has to stand there and do. He keeps the key down
## and the work goes up; he lets go, looks away, opens a screen or gets a rat in
## his hands, and it is all thrown away.
##
## Only one of those endings is written out below. The rest arrive for free
## through `_focused`, which `_update_focus` has already cleared this frame for
## every one of those reasons — which is why this runs immediately after it.
func _update_hold(delta: float) -> void:
	var target := _focused
	if target != null and not target.is_held_work():
		target = null
	if target == null or _ui_open or not Input.is_action_pressed("interact"):
		_cancel_hold()
		return

	# Looking from one slow thing straight to another starts the second from
	# nothing: what he did to the first buys him no time on it.
	if _hold_target != target:
		_cancel_hold()
		_hold_target = target
		hold_started.emit(target)

	_hold_time += delta
	var fraction := clampf(_hold_time / target.hold_time, 0.0, 1.0)
	hold_progress.emit(fraction)
	if fraction < 1.0:
		return

	# Done. The counter is cleared before the thing is told, because being told
	# is very often the last moment it exists (`scripts/traps/mousetrap.gd`).
	_hold_target = null
	_hold_time = 0.0
	hold_finished.emit(true)
	_announce_focus()
	target.use(self)

## Drops whatever slow job was going, if there was one. Saying so twice would put
## the bar back on screen after it had already left.
func _cancel_hold() -> void:
	if _hold_target == null:
		return
	_hold_target = null
	_hold_time = 0.0
	hold_finished.emit(false)
	_announce_focus()

## Says again what is in front of him, unchanged. The prompt is drawn only when
## what he is looking at *changes* (`scripts/hud_prompt.gd`), and letting go of a
## slow job halfway is not a change — he is still standing over the same trap.
## Without this the line he needs in order to start again would stay off the
## screen for as long as he kept looking at it.
func _announce_focus() -> void:
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

## Toggles the player's flashlight on or off.
func toggle_flashlight() -> void:
	if flashlight != null:
		flashlight.visible = not flashlight.visible

## Enables or disables the player's flashlight.
func set_flashlight(enabled: bool) -> void:
	if flashlight != null:
		flashlight.visible = enabled

