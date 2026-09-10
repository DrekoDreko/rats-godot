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
## belt (`scripts/hud_health.gd`) hears about it by signal. When it runs out,
## the player stays down until a later revive mechanic brings him back.
##
## And he has hands for things that are not rats: a short ray out of the camera
## (`Head/Camera/Interact`) looks for whatever he could put them on, and `E` uses
## it (`scripts/interaction/interactable.gd`). What that opens — the computer's
## shop, for now — takes the player over while it is on screen: `set_ui_open()`
## lets the mouse loose to click with and stops the body from answering to
## anything, which is the only way a click can reach a button instead of being
## spent grabbing the camera back.
##
## What he sees sways a little while he walks (`_update_bob`): the camera rides
## up and down on a sine wave scaled by how fast he is actually moving, and comes
## back to rest the moment he stops. It is drawn on the camera alone, so nothing
## that aims — the ray out of it, the weapon on the head — is
## moved by it.
##
## And he is being watched. In a lobby, everything the other players see of him
## is read off four things — `animation_state()` and `arms_state()` for what he
## is, the `attacked` and `squeezed` signals for what he does — by
## the avatar that stands for him on their screens
## (`scripts/steam/player_avatar.gd`). Nothing in this file knows that the wire
## exists: somebody else reads him and puts him on it.

signal attacked(hit: bool)
## Squeezed the neck of a rat already in his hands. It is relayed from the
## weapon and goes out to everybody watching, which is the whole of why it
## exists: the strangling is several seconds of deliberate work and, until this,
## not one frame of it was visible from outside his own screen.
signal squeezed()
## Relays from the weapon to the HUD.
signal capture_started(rat: Node3D)
signal capture_progress(fraction: float)
signal capture_finished(killed: bool)
## Swapped slots. `weapon` comes in null on an empty slot, and `index` comes in
## `Inventory.HANDS_INDEX` with the hands out — no square to frame. It is what
## the hotbar listens to.
signal weapon_changed(index: int, weapon: Weapon)
## Something got him in the face. It is not a wound — the wound comes through
## `damaged` like every other — it is what the wound was *by*, and the only thing
## that listens is the splatter on the lens (`scripts/hud_splatter.gd`).
##
## Bare, like `squeezed`: there is one thing in the game that sprays and one thing
## that draws it, and a strength nobody varies is a parameter nobody reads.
signal splashed()

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
## The rat the weapon in hand would act on if he clicked now, or null with
## nothing in his sights. It is what tells the player he may grab — the line
## round the animal is drawn off it, and so is the prompt that says so.
##
## It carries the animal and not merely a yes or no, because the two listeners
## want different halves of it: the outline has to know *which* rat to light up,
## and the prompt only that there is one.
signal target_changed(rat: Node3D)
## Hands on something slow. Not everything answers to a tap: a fouled trap has to
## be stood over and cleaned out, and while that is going on there is a bar on
## screen instead of a prompt (`scripts/hud_hold.gd`).
signal hold_started(interactable: Interactable)
signal hold_progress(fraction: float)
## Finger up, eyes away, or the job done. `completed` tells the two apart.
signal hold_finished(completed: bool)
## Entered or left a fixed seat. The van sets the opening state; only this
## character decides when local input releases it.
signal seated_changed(seated: bool)

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

@export_group("Camera")
## How far the camera travels from its resting height, in metres, at a full run.
## Small on purpose: this is a sway to walk to, not a shake.
@export var bob_amount := 0.045
## Steps per second at a full run. Slower gaits use the same rhythm scaled down,
## so the sway keeps time with the legs instead of running away from them.
@export var bob_frequency := 1.9

## How far the view is thrown by a shake of strength 1, in metres to the side
## and up. It is small because it is multiplied by a trauma that starts at one
## and falls away in a fraction of a second: what the eye reads is the *speed*
## of the throw, not how far it went, and a camera that travels far enough to
## see it travel reads as a camera coming loose rather than as a jolt.
@export var shake_amount := 0.055
## How far the view rolls with the same shake, in degrees. The roll is what
## makes a shake read as the whole head being knocked rather than as the picture
## sliding, and it is the part a player notices without being able to name.
@export var shake_roll := 2.4
## How fast the shake rattles, in shakes per second. Fast enough not to read as
## a sway, slow enough that a 30 fps frame still catches the wave rather than
## sampling noise out of it.
@export var shake_frequency := 26.0

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
## How fast the sway settles back to nothing once he stops, in fractions of the
## way per second. Quick enough not to be a drift, slow enough not to be a snap.
const BOB_SETTLE := 8.0
## Eye height while riding, relative to the standing head. The body animation
## bends the visible legs; this moves the first-person view to the same height.
const SEATED_HEAD_SCALE := 0.44
## Third-person death camera orbit.
const DEATH_CAMERA_DISTANCE := 5.5
const DEATH_CAMERA_HEIGHT := 2.6
const DEATH_CAMERA_MIN_PITCH := deg_to_rad(-8.0)
const DEATH_CAMERA_MAX_PITCH := deg_to_rad(42.0)
const DEATH_FALL_TIME := 0.45

## How much of a shake is left after one second. A shake is a thing that happened
## and is over: at this rate a full one is imperceptible inside a third of a
## second, which is about as long as a jolt survives in the neck.
const SHAKE_DAMPING := 0.0006
## Below this much trauma there is nothing left to draw, and the camera is put
## back exactly where it belongs rather than left a thousandth off it forever.
const SHAKE_EPSILON := 0.002
## The length of the whole rattle, in radians of its base wave.
##
## The shake is several sines of different rates read off one phase, and the
## phase has to be folded somewhere or it grows all session. Folding it at `TAU`
## would be right for the base wave and wrong for every other one — they would
## jump mid-stride on each fold — so it is folded where all of them come round
## together instead: ten turns covers the 1.3, 1.7 and 2.1 multiples below at
## whole numbers of their own turns (13, 17 and 21).
const SHAKE_PERIOD := TAU * 10.0
## The knock of landing, per metre per second of the fall that was stopped.
## Stepping off a kerb is nothing; coming off the top of a crate is felt.
const LAND_SHAKE_PER_SPEED := 0.055
## Below this landing speed nothing is felt at all: walking down a slope stops
## and starts a fall many times a second, and a camera that jolted on each one
## would rattle for the whole walk.
const LAND_MIN_SPEED := 3.5
## The most a landing can shake, however far the fall was.
const LAND_MAX_SHAKE := 1.0
## How much the view dips into the knees on landing, in metres per unit of the
## landing's own strength, and how fast it comes back up. It is the half of a
## landing the shake cannot draw: a shake is symmetrical and a landing is not —
## the body goes *down* and comes back.
const LAND_DIP := 0.085
const LAND_DIP_RECOVERY := 7.0
## The lift the view gets as he leaves the ground, in metres, and how fast it
## settles. It is the same dip run the other way: the head lags behind the feet
## on the way up, so the camera is left low for an instant and rises into place.
const JUMP_DIP := -0.06

## The footfall. `step_rock` is a bright 0.19s crack recorded near unity, so it
## is pitched down a little to give the step some weight, then spread either
## side of that so a run is not the same click repeated. The volume gets a
## narrower spread of its own, which keeps the two from lining up into an
## audible pattern.
const STEP_PITCH := 0.92
const STEP_PITCH_SPREAD := 0.12
const STEP_VOLUME_DB := -6.0
const STEP_VOLUME_SPREAD_DB := 2.0

## How much of the animal's own fighting the hands follow, and how far they are
## allowed to be carried by it, in metres.
##
## A rat in the fist trembles and kicks against the point it hangs from
## (`rat.gd: TREMOR`, `_kick`), and it does it in the middle of the screen where
## every centimetre of it is visible. Until this the hands did not move with it
## at all, which is what made a fist buried in a thrashing animal read as a
## picture pasted over one.
##
## A fraction rather than the whole of it, and that is the number that matters.
## Following it completely welds the glove to the animal and nothing looks
## difficult any more — the pair go about the screen together like one object.
## Following a little is a man keeping hold of something that is trying to get
## away, which is what is being drawn. The cap is what stops a good kick
## throwing the arm off the pose it was solved in.
const GRIP_FOLLOW := 0.7
const GRIP_DRIFT := 0.04

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var audio_listener: AudioListener3D = $Head/Camera/AudioListener3D
@onready var inventory: Inventory = $Head/Inventory
## Where a rat he has caught is held, in front of his own camera. It is the same
## node `Hands` hangs the animal off (`hands.gd: capture_point`), and it is read
## here for the other half of that: how far the thing has dragged his hands.
@onready var capture_point: Node3D = $Head/CapturePoint
@onready var collision: CollisionShape3D = $Collision
## The room over his head, asked only when he wants it back: it is the standing
## capsule put where the standing capsule would go, and anything it touches is a
## ceiling he cannot get up through.
@onready var ceiling: ShapeCast3D = $Ceiling
## The reach of the hands for things that are not rats. It only sees the
## interactable layer, so it never trips over the scenery or over an animal.
@onready var interact_ray: RayCast3D = $Head/Camera/Interact
## The body he is wearing. He never sees it — he is inside it — but it is what
## casts his shadow on the floor, and the same scene the other players are drawn
## with (`scripts/player_model.gd`), so his walk on their screens and his shadow
## on his own come off one animation.
@onready var model: PlayerModel = $Model
## His own arms, hanging off his camera: a pair of `models/hazmat_hand.glb`
## posed by hand rather than a cut of the body (`scripts/player_view_model.gd`).
## It is fed his step, his turn and his crouch, which is everything that moves
## them — there is no animation on them to feed.
@onready var view_model: PlayerViewModel = $Head/Camera/ViewModel

var _start_position: Vector3
var _air_time := 0.0
## Where the camera is in the walking cycle, in radians. It keeps running while
## he walks and is left where it stopped when he stands still — picked back up
## from there on the next step, so setting off again does not jerk the view.
var _bob_phase := 0.0
## Accumulated walking phase used to emit one footstep every half cycle.
var _step_phase := 0.0
## How much of the sway is being applied, from 0 standing still to 1 at a full
## run. It travels rather than switching so that stopping eases the camera back
## to its resting height instead of dropping it there.
var _bob_weight := 0.0
## Initialized true so spawning on the floor is not mistaken for a landing.
var _was_on_floor := true
## The camera's height in the head, read once off the scene: the sway is drawn
## around it, never away from it.
var _camera_rest_y := 0.0
## How badly the view is shaking, from 0 at rest to 1 on the hardest jolt the
## game asks for. Everything that wants to shake the camera adds to this and
## nothing reads it back: the drawing (`_update_shake`) is the only thing that
## cares how much there is, and it spends it.
var _shake := 0.0
## Where the shake is in its own rattle, in radians. It is kept rather than read
## off the clock so that two shakes running into each other carry on the same
## wave instead of jumping to wherever the global time happens to be.
var _shake_phase := 0.0
## How far the view is dipped into the knees, in metres, from a landing (down)
## or a jump (up). It is the one part of both gestures that is not a shake, and
## it eases back to nothing on its own.
var _dip := 0.0
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
## The rat in his sights, or null. Held so the outline can be taken off the one
## he stops pointing at — the animal has no way of knowing it was dropped.
var _target_rat: Node3D
## The slow thing he is working on, and how long he has been at it. Null with his
## finger off the key, and null the instant he looks away — there is no such thing
## as half a cleaned trap waiting for him to come back to it.
var _hold_target: Interactable
var _hold_time := 0.0
## A screen has the player: the mouse is loose on it and the body is out of the
## game until it closes.
var _ui_open := false
## How far the head turned since the arms were last moved, in radians — yaw in
## `x`, pitch in `y`. The mouse writes into it and `_physics_process` spends it,
## which is what keeps a flick reported over four events worth as much swing as
## the same flick reported over one.
var _look := Vector2.ZERO
## The rat in his own hands, or null. It is kept for one purpose — reading how
## far the animal has fought its way off the point it hangs from, so his hands
## can go with it (`_grip_drift`) — and it is dropped the moment the hands are
## free, killed or escaped: a dead rat on its way to his belt travels the whole
## height of the frame, and hands that followed *that* would be dragged down by
## the body instead of putting it away.
var _held_rat: Node3D
## How much longer his arms are still busy with a rat he has already killed, in
## seconds. It is what keeps the body holding the animal for as long as it takes
## to come apart — see `_on_weapon_bursting` and `arms_state`.
var _arms_busy := 0.0
## Fixed to a van bench. Looking remains available, but movement, weapons and
## world interaction wait until the player presses Interact to stand.
var _seated := false
var _glue: GlueTrap
var glue_progress := 0.0
var _glue_anchor := Vector3.ZERO
var _glue_jump_block := false
var _dead_camera_center := Vector3.ZERO
var _dead_camera_yaw := 0.0
var _dead_camera_pitch := deg_to_rad(14.0)
var _death_started := false
var _model_rest_transform := Transform3D.IDENTITY

func _ready() -> void:
	_start_position = global_position
	_health = max_health
	# The player scene is mounted in the gameplay SubViewport. Wait until that
	# mount has completed before selecting its listener; otherwise the main
	# viewport has no current 3D listener and positional sounds are inaudible.
	call_deferred(&"_make_audio_listener_current")
	# The shape is duplicated before a single frame is drawn: the one in the scene
	# is shared with the ceiling cast — and with every other player in a lobby —
	# and shrinking it in place would crouch all of them at once.
	var shape := collision.shape as CapsuleShape3D
	collision.shape = shape.duplicate()
	_stand_height = shape.height
	_stand_collision_y = collision.position.y
	_stand_head = head.position.y
	_camera_rest_y = camera.position.y
	_model_rest_transform = model.transform
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# He is inside his own body, so the mesh would be the inside of his own head.
	# The shadow it throws is still his and still worth having, and his arms come
	# back to him separately (`view_model`).
	model.set_shadows_only(true)
	_dress_view_model()
	# Every weapon on the belt is wired up once, and not the one in hand at each
	# swap: a weapon that is put away never reaches `_use()`, so it never has
	# anything to announce.
	for weapon in inventory.weapons():
		weapon.used.connect(func(hit: bool) -> void: attacked.emit(hit))
		weapon.caught.connect(_on_weapon_caught)
		weapon.pressure_changed.connect(func(fraction: float) -> void: capture_progress.emit(fraction))
		weapon.finished.connect(_on_weapon_finished)
		weapon.squeezed.connect(_on_weapon_squeezed)
		# Only the hands hold a body while it comes apart, and the day another
		# weapon does it will say so with the same signal. Asked for rather than
		# assumed: the belt holds weapons that settle everything in one blow, and
		# they have no such moment.
		if weapon.has_signal(&"bursting"):
			weapon.connect(&"bursting", _on_weapon_bursting)
	inventory.equipped.connect(_on_inventory_equipped)


func _make_audio_listener_current() -> void:
	if audio_listener != null and audio_listener.is_inside_tree():
		audio_listener.make_current()


func _on_inventory_equipped(slot: int, weapon: Weapon) -> void:
	weapon_changed.emit(slot, weapon)
	AudioManager.play_networked_3d("item_equip", global_position, -6.0, 1.0, self)


## A weapon has taken hold of a rat.
##
## Two things happen, and they are separate on purpose: the world hears about it
## through `capture_started`, and the player's own hand closes on the animal.
## The second is the only one that is his alone — nobody else's screen has his
## arms on it — which is why it is done here rather than by whatever listens to
## the signal.
func _on_weapon_caught(rat: Node3D) -> void:
	view_model.set_gripping(true)
	_held_rat = rat
	capture_started.emit(rat)


## The rat is out of the hand, dead or gone — the hands are free either way, and
## the screen is told so here: the pressure bar goes, the crosshair comes back,
## and the click means grab again.
##
## The arm is a separate question, and the two used to be the same one. It opens
## on a rat that got loose, because the animal took itself out of the fist and
## there is nothing left in it. On a rat that was strangled it does not: the body
## is dead *in the hand*, and what happens next is the fist closing the rest of
## the way on it — which `_on_weapon_bursting` has already started by the time
## this runs, and which leaves the hand closed for as long as it takes.
func _on_weapon_finished(killed: bool) -> void:
	if not killed:
		view_model.set_gripping(false)
	_held_rat = null
	capture_finished.emit(killed)


## The rat is dying in the fist and about to come apart. The hand stays closed on
## it for the length of it and opens on nothing.
##
## It is his alone, like the grip and for the same reason — nobody else's screen
## has his arms on it — so it goes no further than the view model. What the rest
## of the world sees of the same moment is the spray, which the rat throws into
## the world on every machine (`rat.gd: _burst`).
func _on_weapon_bursting(windup: float) -> void:
	view_model.hold_burst(windup)
	# His body keeps hold of the animal for as long as his arm does. The two
	# would otherwise part company here: `is_busy()` goes false on the killing
	# squeeze, so to everybody watching him his arms would drop on the instant
	# while the rat was still being crushed in them.
	_arms_busy = windup


## One squeeze of the neck of a rat he is holding.
##
## It goes two ways from here, and they are separate calls because they are
## separate bodies. His own hazmat suit is told directly — he cannot see it, but
## it is what throws his shadow. And `squeezed` goes out for the avatars that
## stand for him on the other players' screens, which is the half this was
## written for.
##
## His *own* arm is not told here. It is driven straight off the click
## (`_unhandled_input`), and deliberately so: the recoil in the sleeves has to
## land on the frame the button went down, not one relay later.
func _on_weapon_squeezed() -> void:
	model.squeeze()
	squeezed.emit()


## Paints the player's own sleeves in the colour the crew says he is wearing,
## and keeps them painted when he picks another one.
##
## It exists because until the arms did, a player never saw a stitch of his own
## suit: only the avatars standing for the *other* players were ever tinted
## (`scripts/steam/player_avatar.gd`), which was right when his own body was a
## shadow on the floor. Now that his sleeves are in front of him, a man who
## picked blue and sees yellow arms would reasonably think the pick did not take.
##
## The autoloads are reached through the tree rather than by their global names,
## the same way `player_avatar.gd` reaches them and for the same reason: a bench
## run with `--script` has no autoloads, and a global name that is not a name
## fails the whole class to compile. Here it also covers the plainer case of a
## solo game with no Steam behind it, where there is no crew to ask — and the
## honest answer to "what colour is this man" is then the one the model was
## built in.
func _dress_view_model() -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	var colors := loop.root.get_node_or_null(^"ColorManager")
	if colors != null:
		colors.color_changed.connect(_on_crew_color_changed)
	_repaint_view_model()


## Somebody's colour was settled. Only ours changes what is in front of us.
func _on_crew_color_changed(changed_id: int, _color: Color) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	var lobby := loop.root.get_node_or_null(^"LobbyManager") if loop != null else null
	if lobby == null or changed_id != lobby.our_steam_id():
		return
	_repaint_view_model()


## The sleeves, in whatever colour the crew has us down for. A player the crew
## has never heard of — a solo run, a bench — keeps the suit's own yellow.
func _repaint_view_model() -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	var lobby := loop.root.get_node_or_null(^"LobbyManager")
	var session := loop.root.get_node_or_null(^"SessionManager")
	if lobby == null or session == null:
		return
	var steam_id: int = lobby.our_steam_id()
	if steam_id == 0 or not session.has_player(steam_id):
		return
	view_model.set_tint(session.color(steam_id))


func _unhandled_input(event: InputEvent) -> void:
	if is_dead():
		if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var motion := (event as InputEventMouseMotion).relative
			_dead_camera_yaw -= motion.x * mouse_sensitivity
			_dead_camera_pitch = clampf(
				_dead_camera_pitch - motion.y * mouse_sensitivity,
				DEATH_CAMERA_MIN_PITCH, DEATH_CAMERA_MAX_PITCH)
			get_viewport().set_input_as_handled()
		return
	# With a screen open the player is not in the map: the mouse belongs to the
	# buttons, and neither the camera nor the belt hears anything. The key that
	# closes it is the screen's own business, and it never reaches this far.
	if _ui_open:
		return
	if is_glued() and event.is_action_pressed("jump"):
		_glue_jump_block = true
		_glue.press_escape()
		get_viewport().set_input_as_handled()
		return
	# In either house phase, world stations, including their held jobs, are
	# unavailable.
	if event.is_action_pressed("interact") and not _can_interact(_focused):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ready") and ReadyManager.is_active():
		get_viewport().set_input_as_handled()
		ReadyManager.request_toggle(LobbyManager.our_crew_id())
		return
	if _seated and event.is_action_pressed("interact"):
		set_seated(false)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# The whole body turns horizontally; only the head looks up and down.
		var motion := (event as InputEventMouseMotion).relative
		var yaw := -motion.x * mouse_sensitivity
		var before := head.rotation.x
		if _seated:
			head.rotation.y = clampf(head.rotation.y + yaw, -PI * 0.42, PI * 0.42)
		else:
			rotation.y += yaw
		head.rotation.x = clampf(
			head.rotation.x - motion.y * mouse_sensitivity,
			deg_to_rad(-MAX_PITCH),
			deg_to_rad(MAX_PITCH)
		)
		# Kept for the arms, which swing a little behind a turn. Added up rather
		# than written down, because the mouse can report several times between
		# two frames and the arms are moved once per frame — taking the last event
		# alone would throw away most of a fast flick.
		#
		# The pitch is the movement the head actually made and not the one that
		# was asked for: against the limit, looking further up is no turn at all,
		# and arms that swung anyway would drift while the view stood still.
		_look += Vector2(yaw, head.rotation.x - before)
	elif _seated:
		return
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
			# The squeeze is felt in the arm as well as in the camera. It is
			# driven from the click rather than from the pressure the squeeze
			# adds, because pressure also drains on its own while nobody is
			# clicking (`hands.gd: decay`) — an arm following that would creep
			# backwards through the whole hold instead of thrusting on each go.
			view_model.punch()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("interact") and _focused != null:
		# The slow ones are not used on the press: the press is only the start of
		# the holding, and the holding is counted where the frames are
		# (`_update_hold`).
		if not _focused.is_held_work():
			_focused.use(self)
			# The press is spent here. A station that opens a screen off `use()`
			# listens for the same key to close it again, and the player sits
			# below those in the tree: without this the one press would reach
			# them too and shut what it had just opened.
			#
			# Asked for rather than assumed, because `use()` can end the phase.
			# The board in the moving van is the case: the last man to slap it
			# takes the crew to the survey, and `change_scene_to_file` pulls this
			# body out of the tree before the call even returns — so by here
			# there is no viewport left to hand the press back to. There is also
			# nothing left to swallow it on behalf of: the listeners that would
			# have seen it went out with the same scene.
			var viewport := get_viewport()
			if viewport != null:
				viewport.set_input_as_handled()
	elif event.is_action_pressed("interact") and _open_terminal():
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("attack"):
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			inventory.try_use()
		else:
			# Clicking on the window gives camera control back to the mouse.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		_handle_slot_input(event)

## `1`, `2` and `3`: the belt. `Q`: the hands, which are on no slot and are
## always there to come back to. Unlike the click, these work with the mouse
## loose too — they are keys, and they are not fighting anybody over the camera.
## The belt itself is what turns the swap down with a rat in hand.
## The mouse wheel cycles the slots while the mouse is captured.
func _handle_slot_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		var direction := 0
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			direction = -1
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			direction = 1
		var count := inventory.slot_count()
		if direction != 0 and count > 0:
			var current := inventory.index()
			# From the hands, enter the belt at the end matching the scroll direction.
			if current == Inventory.HANDS_INDEX:
				current = count if direction < 0 else -1
			inventory.equip(posmod(current + direction, count))
		return
	if event.is_action_pressed("hands"):
		inventory.equip_hands()
		return
	for i in inventory.slot_count():
		if event.is_action_pressed("slot_%d" % (i + 1)):
			inventory.equip(i)
			return


## The terminal is a full-screen sibling in every gameplay scene. It is only
## offered when the interaction ray found nothing, so E continues to operate
## the object the player is deliberately looking at.
func _open_terminal() -> bool:
	var scene := get_parent()
	if scene == null:
		return false
	var terminal := scene.get_node_or_null(^"TerminalUI/TerminalScreen") as TerminalScreen
	return terminal != null and terminal.open(self)

func _physics_process(delta: float) -> void:
	if not Input.is_action_pressed("jump"):
		_glue_jump_block = false
	if is_dead():
		_update_dead_camera()
		return
	_update_focus()
	_update_target()
	_update_hold(delta)
	_update_crouch(delta)
	var busy := inventory.is_busy()

	if _seated:
		velocity = Vector3.ZERO
		_air_time = 0.0
	elif is_on_floor():
		_air_time = 0.0
	else:
		_air_time += delta
		velocity.y -= gravity * delta

	# With the hands full there is no jumping: holding the rat is work enough. Nor
	# from down on his knees — pressing jump while crouched only lets go of the
	# crouch, and the jump belongs to whoever is standing when he presses it.
	if not busy and not _seated and not _ui_open and not is_crouching() \
			and not is_glued() and not _glue_jump_block \
			and Input.is_action_just_pressed("jump") and _air_time <= COYOTE_TIME:
		velocity.y = sqrt(2.0 * gravity * jump_height)
		_air_time = COYOTE_TIME + 1.0
		# The head lags behind the feet on the way up: the camera is left low for
		# an instant and rises into place. Assigned rather than added, because a
		# jump is a fresh gesture and whatever the last one left is not part of
		# it.
		_dip = JUMP_DIP

	var direction := _desired_direction()
	var target := direction * _target_speed(busy)
	var rate := acceleration if direction != Vector3.ZERO else deceleration
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)
	if is_glued():
		global_position = _glue_anchor
		velocity = Vector3.ZERO

	if not _seated:
		# Read before the move, because the move is what stops the fall:
		# afterwards the body is already resting on the floor and the speed that
		# hit it is gone.
		var fall_speed := maxf(-velocity.y, 0.0)
		move_and_slide()
		var landed := not _was_on_floor and is_on_floor()
		_was_on_floor = is_on_floor()
		if landed:
			_step_phase = 0.0
			_land(fall_speed)

	# The tail of a kill: his arms are still carrying the body down to his belt
	# for a moment after the hands report themselves free (`arms_state`).
	_arms_busy = maxf(_arms_busy - delta, 0.0)

	# After the move, not before: `animation_state()` reads what the body did
	# this frame, and asking it beforehand would draw him doing what he was doing
	# a frame ago — walking into a wall included.
	#
	# The body he casts a shadow with and the arms he sees are told the same
	# thing, in the same breath. Two calls rather than one because the arms are
	# not under the body — they hang off the camera — but there is only ever one
	# state, and it is read here once. The arms have nothing to do with it today
	# and are told anyway: the day the hands carry clips, the two are already in
	# step (`PlayerViewModel.set_state`).
	var state := animation_state()
	model.set_state(state)
	# His hands are a separate question from his legs, and his own body is told
	# it for the same reason the avatars are: the shadow he throws on the floor
	# is the one part of himself he can see, and a shadow with its arms down
	# while it strangles something is the bug this fixes, seen from inside.
	model.set_arms(arms_state())
	view_model.set_state(state)
	# The arms lag a little behind the turn. The reading is spent as it is used,
	# so a frame in which the mouse did not move is a frame in which the arms
	# settle back rather than one in which they hold the last flick.
	view_model.sway(delta, _look)
	_look = Vector2.ZERO
	# The hand's own travel — closing on a rat, opening off one, and settling
	# after a squeeze. Apart from the sway because that one is switched off
	# whenever `sway_lag` is zero, and a hand still has to close when it is.
	view_model.advance(delta)
	# And how far the animal has pulled them off it. After `advance`, because
	# that is what moves the hand between hanging and gripping, and the drift is
	# something that happens to a hand already on its way.
	view_model.set_grip_drift(_grip_drift())
	# After the move as well, and for the same reason: the sway is drawn from the
	# ground he actually covered this frame, not from the keys he was holding.
	_update_bob(delta)
	# And after the sway, because the two are drawn on the same camera and this
	# one is written on top of the height that one just set.
	_update_shake(delta)

	if global_position.y < MIN_HEIGHT:
		take_damage(max_health)


func _update_dead_camera() -> void:
	var horizontal := cos(_dead_camera_pitch) * DEATH_CAMERA_DISTANCE
	var offset := Vector3(
		-sin(_dead_camera_yaw) * horizontal,
		sin(_dead_camera_pitch) * DEATH_CAMERA_DISTANCE + DEATH_CAMERA_HEIGHT,
		cos(_dead_camera_yaw) * horizontal)
	camera.global_position = _dead_camera_center + offset
	camera.look_at(_dead_camera_center + Vector3.UP * 0.75, Vector3.UP)

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
	if is_glued():
		return Vector3.ZERO
	if _ui_open or _seated:
		return Vector3.ZERO
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input == Vector2.ZERO:
		return Vector3.ZERO
	var base := global_basis
	var direction := base.z * input.y + base.x * input.x
	direction.y = 0.0
	return direction.normalized()


func is_glued() -> bool:
	return is_instance_valid(_glue) and not is_dead()


func set_glue_state(glue: GlueTrap, stuck: bool, progress: float, anchor: Vector3) -> void:
	if stuck and not is_dead() and not _seated:
		if is_instance_valid(_glue) and _glue != glue:
			return
		_glue = glue
		glue_progress = progress
		_glue_anchor = anchor
		velocity = Vector3.ZERO
	elif _glue == glue:
		_glue = null
		glue_progress = 0.0

# --- The sway ---------------------------------------------------------------

## The camera rides a sine wave while he walks. Both how far it travels and how
## fast are scaled by the ground he is covering, measured against his run: a walk
## sways less and slower than a run, and a crouch-crawl barely at all, without
## any of the three being written down anywhere here.
##
## Off the floor there is no sway — nothing is stepping — and it eases out rather
## than cutting, so a jump does not chop the view in half.
##
## It moves the camera and nothing else. The ray out of it and
## the weapon on the head all hang from the head, or from the camera's rest, so
## what he is aiming at does not sway with what he is seeing.
func _update_bob(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := is_on_floor() and speed >= IDLE_SPEED
	var gait := clampf(speed / run_speed, 0.0, 1.0) if moving else 0.0
	_bob_weight = move_toward(_bob_weight, gait, BOB_SETTLE * delta)
	if moving:
		var phase_delta := TAU * bob_frequency * gait * delta
		_bob_phase = fposmod(_bob_phase + phase_delta, TAU)
		_step_phase += phase_delta
		while _step_phase >= PI:
			_step_phase -= PI
			if not _ui_open:
				_play_step()
	# The arms ride the same step the view does, and they are handed the phase
	# rather than left to find it: an arm counting its own steps off the velocity
	# would drift a frame from the camera it is drawn in front of, and the two
	# would visibly beat against each other.
	if view_model != null:
		view_model.bob(_bob_phase, _bob_weight)
	if is_zero_approx(_bob_weight):
		camera.position.y = _camera_rest_y
		return
	camera.position.y = _camera_rest_y + sin(_bob_phase) * bob_amount * _bob_weight


# --- The shake --------------------------------------------------------------

## Knocks the view about. `strength` is 1 for the hardest jolt in the game and
## fractions of it for everything smaller; anything above 1 is clamped, so no
## caller can throw the camera off the man's shoulders however much it asks for.
##
## It *adds*, and that is what makes two shakes landing in the same breath read
## as one bigger knock instead of the second one cancelling the first. The
## trauma it adds is spent by `_update_shake` and by nothing else.
##
## It is his own camera and nobody else's, so it is not sent anywhere: what the
## other players see of the same moment is whatever the thing that shook him is
## drawing on every machine — the blood, the body, the trap going off.
func shake(strength: float) -> void:
	_shake = clampf(_shake + strength, 0.0, 1.0)

## He hit the floor. How hard it is felt comes off the fall that was stopped:
## stepping off a kerb is nothing, coming off the top of a crate is felt in the
## knees, and the sound is pitched and mixed to match rather than being the same
## thud for both.
func _land(fall_speed: float) -> void:
	if fall_speed < LAND_MIN_SPEED:
		# A step down, not a landing. The sound still plays — his boots did touch
		# the floor — but nothing is felt.
		AudioManager.play_networked_3d("landing_rock", global_position, -8.0, 1.1, self)
		return
	# From nothing at the threshold up to the cap: a fall twice as long lands
	# twice as hard, and past a point it lands as hard as it ever will.
	var force := minf((fall_speed - LAND_MIN_SPEED) * LAND_SHAKE_PER_SPEED, LAND_MAX_SHAKE)
	shake(force)
	# And the knees go with it. Down, where the shake is symmetrical: this is the
	# half of a landing that has a direction.
	_dip = LAND_DIP * force
	# A heavier landing is a louder and deeper thud, for the same reason a
	# footstep pitched down reads as a heavier boot (`_play_step`).
	AudioManager.play_networked_3d("landing_rock", global_position,
		-6.0 + force * 4.0, 1.05 - force * 0.2, self)

## Draws the shake and the dip on the camera, and spends both.
##
## It writes the camera's sideways offset and its roll, and neither of those is
## anybody else's: the height is the sway's (`_update_bob`), the pitch is the
## mouse's and lives on the head, and the screen-space offsets belong to the
## weapon's own recoil (`weapon.gd`). So the four can all be on at once — a rat
## exploding in the fist while he lands from a jump, mid-swing — and none of
## them overwrite each other.
##
## The rattle is two sines whose periods do not divide each other, the same
## trick the rat's tremor uses: added together they do not repeat closely enough
## for the eye to find the pattern, which is what keeps a shake from reading as
## a vibration.
func _update_shake(delta: float) -> void:
	_dip = move_toward(_dip, 0.0, absf(_dip) * LAND_DIP_RECOVERY * delta + 0.001)
	camera.position.y += _dip

	if _shake <= SHAKE_EPSILON:
		if _shake != 0.0:
			_shake = 0.0
			camera.position.x = 0.0
			camera.position.z = 0.0
			camera.rotation.z = 0.0
		return
	# Wrapped on the whole rattle rather than on a single turn. The waves below
	# run at 1.7 and 2.1 times this phase, so folding it at `TAU` would land them
	# mid-stride and put a visible step in the shake every fortieth of a second;
	# `SHAKE_PERIOD` is a turn for every one of them at once. It is wrapped at all
	# only so the number cannot grow without bound through a long session.
	_shake_phase = fposmod(_shake_phase + TAU * shake_frequency * delta, SHAKE_PERIOD)
	var t := _shake_phase
	# Squared, so that the tail of a shake dies away faster than its middle: a
	# jolt that faded linearly reads as a rattle that will not stop.
	var force := _shake * _shake
	camera.position.x = (sin(t) * 0.7 + sin(t * 1.7 + 1.1) * 0.3) * shake_amount * force
	camera.position.z = (sin(t * 1.3 + 2.4) * 0.6 + sin(t * 2.1) * 0.4) * shake_amount * force
	camera.rotation.z = sin(t * 0.9 + 0.5) * deg_to_rad(shake_roll) * force
	_shake *= pow(SHAKE_DAMPING, delta)

## One footfall. The sample is a single short crack, so a fixed pitch turns a
## walk into a machine gun of identical clicks — thin, and audibly looped. Two
## things break that up: a pitch a little under unity, which gives the step some
## body rather than the bright top-end of the raw sample, and a random spread
## either side of it so no two footfalls are the same sound. The volume moves
## with it, because a step that is pitched down reads as heavier and a step
## pitched up reads as lighter.
func _play_step() -> void:
	var pitch := STEP_PITCH * randf_range(1.0 - STEP_PITCH_SPREAD, 1.0 + STEP_PITCH_SPREAD)
	var volume := STEP_VOLUME_DB + randf_range(-STEP_VOLUME_SPREAD_DB, STEP_VOLUME_SPREAD_DB)
	AudioManager.play_networked_3d("step_rock", global_position, volume, pitch, self)

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
	var wanted := not _seated and not _ui_open and Input.is_action_pressed("crouch")
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
	var head_scale := SEATED_HEAD_SCALE if _seated else lerpf(1.0, CROUCH_SCALE, _crouch)
	head.position.y = _stand_head * head_scale
	# And the arms travel with it. They hang off the camera, which the line above
	# has just brought down, but the crouch *animation* lowers them a second time
	# on top of that — so without this they leave the bottom of his own screen
	# exactly when he ducks behind something to look at it.
	#
	# Guarded because the crouch is applied once from `_ready`, before the
	# `@onready` variables further down the file have been filled in.
	if view_model != null:
		view_model.set_crouch(_crouch)

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


## Places the character in, or releases it from, a fixed seat. Seating is an
## opening condition supplied by the travel scene, not a general interaction:
## after standing, the player cannot sit back down during the same trip.
func set_seated(seated: bool) -> void:
	if _seated == seated:
		return
	if _seated and not seated:
		# The standing spawn belongs to this bench and lies in the aisle.
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = ceiling.shape
		query.transform = Transform3D(Basis.IDENTITY, _start_position + Vector3.UP * _stand_collision_y)
		query.collision_mask = collision_mask
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return
		global_position = _start_position
		rotation.y += head.rotation.y
		head.rotation.y = 0.0
	_seated = seated
	collision.set_deferred("disabled", seated)
	velocity = Vector3.ZERO
	_crouch = 0.0
	_apply_crouch()
	model.set_state(animation_state())
	seated_changed.emit(_seated)


## The marker lies on the cushion, independently of the standing respawn point.
func sit_at(seat: Transform3D) -> void:
	global_transform = seat.orthonormalized()
	head.rotation = Vector3.ZERO
	set_seated(true)


func is_seated() -> bool:
	return _seated

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
	_glue = null
	glue_progress = 0.0
	_glue_jump_block = false
	_death_started = false
	_dead_camera_center = Vector3.ZERO
	camera.top_level = false
	view_model.visible = true
	model.set_shadows_only(true)
	model.transform = _model_rest_transform
	velocity = Vector3.ZERO
	rotation.y = 0.0
	head.rotation.x = 0.0
	# On his feet again. Waking up back at the van still folded in half — because
	# the ceiling he died under is nowhere near him now — would leave him low
	# until he thought to press Ctrl and let go of it.
	_seated = false
	collision.set_deferred("disabled", false)
	head.rotation.y = 0.0
	seated_changed.emit(false)
	_crouch = 0.0
	_apply_crouch()
	# And with the camera where the scene put it. Waking up mid-step would leave
	# the view a finger off its resting height until he walked again.
	_bob_phase = 0.0
	_bob_weight = 0.0
	camera.position.y = _camera_rest_y
	# And with nothing left of whatever knocked him down still knocking the view
	# about. He fell a long way to get here, and the landing that killed him is
	# the last thing that should be shaking the camera he wakes up behind.
	_shake = 0.0
	_dip = 0.0
	camera.position.x = 0.0
	camera.position.z = 0.0
	camera.rotation.z = 0.0
	# And on his feet in the drawing too, not only in the collision. A man who
	# died falling would otherwise stand at the van still folded into the pose of
	# the jump, until the next physics frame thought better of it.
	model.set_state(PlayerAvatar.State.IDLE)
	# Empty-handed too. Dying mid-kill leaves the carcass behind and the clock
	# still running, and a man who respawned with his arms still round a rat he
	# no longer has is the one pose nobody could explain.
	_arms_busy = 0.0
	_held_rat = null
	model.set_arms(PlayerAvatar.Arms.FREE)
	# And the arms in front of him with it, still swung out from whatever turn he
	# was making on the way down.
	view_model.set_state(PlayerAvatar.State.IDLE)
	_look = Vector2.ZERO
	view_model.sway(1.0, Vector2.ZERO)
	global_position = _start_position

## What he looks like he is doing, for the benefit of the other players' screens
## (`scripts/steam/player_avatar.gd`). It is read off what the body actually did
## this frame and not off what was pressed: a player walking into a wall is
## standing still, whatever his keyboard says, and that is what the man watching
## him should see.
##
## The order is the order of what wins. Being off the ground beats being on it;
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
	if _seated:
		return PlayerAvatar.State.SITTING
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


## What his *hands* look like they are doing, which is asked separately from the
## rest of him and read the same way — by the avatars on the other players'
## screens, and by his own body for the shadow it throws.
##
## It used to be one question with the one above, and `HOLDING` beat every other
## answer: a man with a rat in his hands was drawn standing perfectly still,
## whatever his legs were up to. That is two bugs in one line — his arms hung at
## his sides through the whole strangling, and his feet stayed nailed to the
## floor while he walked off with the animal — and splitting the question is
## what fixes both.
##
## It stays true a little past the kill. The hands are free the moment the last
## squeeze lands (`Hands._release`), but the body is still in them and is
## travelling down to his belt for a second afterwards, and arms that dropped on
## the instant would leave the carcass flying to his waist on its own.
func arms_state() -> PlayerAvatar.Arms:
	if inventory.is_busy() or _arms_busy > 0.0:
		return PlayerAvatar.Arms.HOLDING
	return PlayerAvatar.Arms.FREE

## How far the rat has fought its way off the point it hangs from, in the
## camera's own axes, and how much of that his hands should go with.
##
## The whole of the movement is the animal's: `rat.gd` writes the tremor and the
## kicks against the capture point, and this only reads the result — one
## subtraction rather than a second wander rolled here, so the hand is provably
## following the thing it is holding and cannot drift off on its own.
##
## `body_center` and not the origin, because the origin of a rat is on the floor
## between its feet and the thing his fist is closed on is the middle of it.
## Asked for rather than assumed, the way `Hands` asks before it trusts an
## animal to answer.
func _grip_drift() -> Vector3:
	if _held_rat == null or not is_instance_valid(_held_rat) 			or not _held_rat.has_method("body_center"):
		return Vector3.ZERO
	var travelled: Vector3 = _held_rat.body_center() - capture_point.global_position
	# Into the camera's coordinates, which is where the arms are posed. The
	# basis is turned rather than inverted properly on purpose — it carries no
	# scale, and for a rotation the transpose *is* the inverse.
	var local := camera.global_basis.transposed() * travelled
	return (local * GRIP_FOLLOW).limit_length(GRIP_DRIFT)


# --- Hands on --------------------------------------------------------------

## House fixtures may be used during survey and hunt; road stations stay blocked.
func _can_interact(target: Interactable = null) -> bool:
	var phase := PhaseManager.current()
	if phase == Phase.Type.SURVEY or phase == Phase.Type.HUNT:
		return target != null and target.usable_in_house
	return true


## What the ray out of the camera is on, if anything. With a rat in hand, or with
## a screen already open, there is nothing to reach for: the prompt goes off the
## screen the same way the crosshair does.
func _update_focus() -> void:
	var found: Interactable = null
	if not _seated and not _ui_open and not inventory.is_busy():
		found = interact_ray.get_collider() as Interactable
		if not _can_interact(found):
			found = null
	if found == _focused:
		return
	_focused = found
	interactable_changed.emit(_focused)

## The rat the click would land on, tracked frame by frame so the animal can be
## lit up before the player commits to anything.
##
## It asks the weapon rather than working it out here, and that is the point:
## reach and cone belong to whatever is in his hands (`weapon.gd:
## target_in_sights`), so the bat lights up rats at its own longer reach and a
## box of traps lights up none at all — without this file knowing that either
## kind of weapon exists.
##
## Nothing is in the sights while a screen is open or a rat is already in the
## hand, for the same reason the prompt and the crosshair go: with your hands
## full there is nothing to aim at, and the animal you are strangling should not
## be wearing the line that means *you may grab this*.
func _update_target() -> void:
	var found: Node3D = null
	if not _ui_open and not inventory.is_busy():
		var weapon := inventory.current()
		# A weapon on cooldown is one the click cannot reach either — the hands
		# hold the belt for the whole of the gesture that ends a rat
		# (`hands.gd: _release`), and a rat lit up through it would be inviting a
		# grab that gets swallowed.
		if weapon != null and weapon.is_ready():
			found = weapon.target_in_sights()
	if found == _target_rat:
		return
	# The old one goes dark first, and it is checked for validity because a rat
	# can be freed between two frames — killed and cleared out — while still
	# being the one we were pointing at.
	if _target_rat != null and is_instance_valid(_target_rat) \
			and _target_rat.has_method("highlight"):
		_target_rat.highlight(false)
	_target_rat = found
	if _target_rat != null and _target_rat.has_method("highlight"):
		_target_rat.highlight(true)
	target_changed.emit(_target_rat)

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
	if target == null or _ui_open or not _can_interact(target) \
			or not Input.is_action_pressed("interact"):
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
## closes it (`scripts/ui/store_screen.gd`): the mouse comes loose to click with, and
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

## Caught a faceful. Said rather than done: what it means is the HUD's business
## (`scripts/hud_splatter.gd`), and the wound that comes with it arrives
## separately through `take_damage` — a spray is a hit and a mess, and the two are
## not the same event.
##
## Guarded on death the same way `take_damage` is: a corpse takes no more piss.
func splash() -> void:
	if is_dead():
		return
	splashed.emit()

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

## Dying leaves the player in the world. The body falls, the first-person view is
## replaced by a controllable third-person death camera, and a later revive
## mechanic will decide when `respawn()` is called.
func _die() -> void:
	if _death_started:
		return
	_death_started = true
	died.emit()
	velocity = Vector3.ZERO
	collision.set_deferred("disabled", true)
	_focused = null
	_cancel_hold()
	model.set_shadows_only(false)
	model.set_arms(PlayerAvatar.Arms.FREE)
	view_model.visible = false
	_dead_camera_center = global_position
	_dead_camera_yaw = rotation.y
	camera.top_level = true
	_update_dead_camera()
	var fall := create_tween()
	fall.tween_property(model, "rotation:x", deg_to_rad(82.0), DEATH_FALL_TIME)
