extends CharacterBody3D
## Rat: a fearful mob. It wanders the map slowly, bolts when the player comes
## close and looks for a spot outside his line of sight to hide in. When the
## player grabs it, it is torn off the ground and ends up in his hand, where it
## struggles until it is strangled — and then stowed at the waist — or until it
## gets loose and goes back to fleeing.
##
## Both the wandering and the fleeing follow the navigation mesh baked in
## `world.tscn`: it only picks destinations it can actually reach, and the path
## to them already comes routed around the walls and the crates.

signal died(rat: Node3D, death_type: Death.Type)

enum State { WANDERING, IDLE, FLEEING, HIDING, CAPTURED, DEAD }

## The beats of the capture, from the grab until the dead body is stowed at the
## waist.
enum Capture { POUNCE, RISING, IN_HAND, GOING_LIMP, STOWING }

@export_group("Species")
## Which rat this is: where its fur and its price come from. See
## `resources/species/`.
@export var species: RatSpecies

@export_group("Movement")
@export var wander_speed := 2.2
## Fleeing speed: slower than the player's run, faster than his walk.
@export var flee_speed := 7.0
## The startled dash, in the first moments of the flight.
@export var burst_speed := 9.5
@export var acceleration := 45.0
@export var gravity := 22.0
@export var turn_speed := 11.0

@export_group("Perception")
## Distance at which the rat flees if it can see the player.
@export var alert_radius := 16.0
## Distance at which it flees even without seeing the player (it heard footsteps).
@export var panic_radius := 6.0
## Hidden, it holds its breath and only bolts if the player nearly steps on it.
@export var hidden_panic_radius := 3.0
## Distance from which it feels safe again.
@export var safe_radius := 26.0

@export_group("Health")
@export var max_health := 1
@export var knockback_force := 5.0

## Height of the rat's eyes, used in the line-of-sight checks.
const EYE_HEIGHT := 0.25
## Height of the player's chest, the point the rat tries to see.
const PLAYER_HEIGHT := 1.2
## Only the scenery takes part in the sight and clearance checks (layer 1).
const SCENERY_LAYER := 1
## Range of the "whiskers" that sniff out walls ahead. They only come into play
## when the rat has no path through the mesh and has to run on instinct.
const WHISKER_RANGE := 2.2
## Angles (degrees) tried when routing around an obstacle, smallest detour first.
const DODGE_ANGLES := [32.0, -32.0, 64.0, -64.0, 100.0, -100.0]
## How long the initial dash of the flight lasts.
const BURST_TIME := 1.2
## How often it reconsiders its hideout while fleeing.
const SEARCH_INTERVAL := 0.6
## Radius in which it looks for obstacles to use as cover.
const COVER_RADIUS := 14.0
## How many obstacles it considers per search.
const MAX_COVERS := 10
## Steps taken behind an obstacle looking for the blind spot.
const COVER_STEPS := 8
const COVER_STEP := 1.5
## Points rolled behind it on each search, on top of the covers.
const CANDIDATES := 10
## Spread (radians) of the flight fan, to each side of "away from the player".
const FAN_SPREAD := 1.8
const MIN_SEARCH_DISTANCE := 3.0
const MAX_SEARCH_DISTANCE := 15.0
## Maximum distance a destination may sit from the navigation mesh. Beyond that
## it landed inside a wall or off the map and is no destination at all.
const MESH_TOLERANCE := 1.5
## Maximum height difference accepted in a destination — the rat does not climb
## crates.
const MAX_HEIGHT_DROP := 1.5
## What vanishing from the player's view is worth in a hideout's score.
const HIDDEN_BONUS := 25.0
## What each free exit around the hideout is worth: a dead end hides well, but
## leaves the rat with nowhere to run afterwards.
const EXIT_BONUS := 3.0
const EXIT_RANGE := 2.5
## Weight of the path length in the score: close beats far.
const PATH_WEIGHT := 0.6
## Penalty for a path that grazes the player.
const NEAR_MISS_PENALTY := 60.0
## Time pushing against a corner before shaking sideways.
const STUCK_TIME := 0.6
## Duration of the sidestep that unwedges the rat from the corner.
const DODGE_TIME := 0.4
## How long the carcass stays on the ground before vanishing.
const CARCASS_TIME := 1.4
## Height at which the rat is sent back to where it was born.
const MIN_HEIGHT := -20.0
## Scale of the model while the rat crouches in its hideout.
const CROUCH_SCALE := Vector3(1.1, 0.6, 1.0)
const INVALID_POINT := Vector3.INF

# --- Capture measurements --------------------------------------------------
## The pounce: the instant it hunches on the ground, before being torn off. It is
## short on purpose — it is only the anticipation that makes the following pull
## read as a pull.
const POUNCE_TIME := 0.1
## How long the rise from the ground to the hand takes.
const RISE_TIME := 0.35
## Height of the arc of the rise over the straight ground-to-hand line: without
## it the rat *slides* into the hand instead of being torn off.
const ARC_HEIGHT := 0.55
## The somersault it turns in the air while rising, unwinding as it arrives.
const FLIP_SPIN := PI
## How the rat sits in the hand: upright, nearly vertical, with its belly and
## snout turned towards the player — the head tips a little forward, and the
## body sits crooked sideways so it is not flat-on to the camera. Its tail and
## hind legs hang below it.
const HELD_POSE := Vector3(66.0, 200.0, 0.0)
## How it sits once dead, before being stowed: the body tips forward and slumps
## sideways, with nothing at all holding the head up.
const LIMP_POSE := Vector3(16.0, 200.0, 28.0)
## How it hangs on the way down as it is stowed: upside down, crooked, the way
## someone already holding the animal by the tail would carry it.
const STOWED_POSE := Vector3(-72.0, 200.0, 24.0)
## The middle of its body, in the rat's own coordinates. The rat's origin sits on
## the ground between its feet, and the trunk (snout to hip) sits ahead of and
## above it — this point, not the origin, is what the hand puts in the middle of
## the screen. Without it the animal is hung by its feet and its body leaves the
## frame; standing, its snout came within a hand's width of the camera.
const BODY_CENTER := Vector3(0.0, 0.2, -0.125)
## Hunched on the ground, in the pounce.
const POUNCE_SCALE := Vector3(1.2, 0.7, 1.2)
## Stretched in the pull — its belly lengthens as it leaves the ground.
const STRETCHED_SCALE := Vector3(0.85, 1.3, 0.85)
## Squashed, on the frame of each squeeze. Held upright, what the camera sees
## shrink is its *length*, not the height of something walking on all fours: the
## squashing happens along the body's axis (Z) and the rest bulges sideways.
const SQUEEZED_SCALE := Vector3(1.2, 1.2, 0.78)
## How long the body takes to go limp in the hand before being stowed.
const LIMP_TIME := 0.5
## How long the stowing lasts: from the hand to the waist. The rat leaves the
## frame in the first half of the gesture; the rest is the arm finishing its
## descent with it.
const STOW_TIME := 0.55
## Where the hand takes the dead rat, in capture-point coordinates: downwards, to
## the hand's side and in close to the player's body, at waist height. It sits
## outside the frame — anyone looking down sees the animal going down, anyone
## looking ahead only sees it leave the scene from below.
const WAIST := Vector3(0.22, -0.68, 0.42)
## How far the path to the waist swings outward before dropping. It is what makes
## the gesture read as a wrist turning to stow something, and not as a body
## falling.
const STOW_OFFSET := Vector3(0.15, 0.05, -0.08)
## From here on, at the end of the stowing, the body has already vanished at the
## waist.
const STOW_VANISH := 0.62
## After escaping, it stays impossible to re-grab for a while.
const IMMUNITY_TIME := 1.5
## The struggle of something held with nobody squeezing. It is never zero: it
## thrashes the whole time.
const BASE_STRUGGLE := 0.35
## How much of a squeeze's struggle is left after one second.
const STRUGGLE_DAMPING := 0.08
## Offset (m) and rotation (degrees) of the constant tremor, at full struggle.
const TREMOR := 0.035
const TREMOR_ANGLE := 9.0
## Interval between one kick and the next, and its strength.
const KICK_INTERVAL := Vector2(0.6, 1.0)
const KICK_FORCE := 0.07
const KICK_FORCE_ANGLE := 22.0
## How much of the jolt is left after one second.
const JOLT_DAMPING := 0.0005
## Chance of a kick turning into a bite.
const BITE_CHANCE := 0.35
## Cadence of the run cycle while it kicks in the air.
const STRUGGLE_CADENCE := 1.8
## The lurch with which it leaps out of the hand when it gets loose.
const ESCAPE_LEAP := 2.5

## Animations that come ready from `mobs/rats/Rat_Fbx.fbx`. (It also brings a
## `Rat|Attack`, which this fearful rat never uses.)
const ANIM_IDLE := "Rat|Idle"
## The pause in which it sniffs the air — used now and then in place of the idle.
const ANIM_SNIFF := "Rat|Idle_Break"
const ANIM_RUN := "Rat|Run"
const ANIM_DEATH := "Rat|Death"
## The bite the fearful rat never uses loose on the map — but does use held in
## the hand of whoever is strangling it.
const ANIM_ATTACK := "Rat|Attack"
## Chance of picking the sniff instead of the plain idle.
const SNIFF_CHANCE := 0.3
## Speed at which the run cycle plays at its natural cadence; slower than that it
## trots, faster and its legs go flying.
const CYCLE_SPEED := 4.5
const MIN_CADENCE := 0.35
const MAX_CADENCE := 2.2
## Below this speed it counts as standing still.
const IDLE_SPEED := 0.35
## Blend time between one animation and the next.
const BLEND := 0.15
## What species a rat is when somebody drops one on the map without saying which.
const DEFAULT_SPECIES := preload("res://resources/species/common_rat.tres")

@onready var agent: NavigationAgent3D = $Navigation
@onready var model: Node3D = $Model
@onready var animator: AnimationPlayer = $Model/Mesh/AnimationPlayer
## A deep path, because it follows the hierarchy that came from the FBX.
@onready var mesh: MeshInstance3D = $"Model/Mesh/Rat/Skeleton3D/Rat Model"

var _state := State.WANDERING
var _health := 1
var _player: Node3D
var _start_position: Vector3
var _target := Vector3.ZERO
var _has_target := false
var _state_time := 0.0
var _target_time := 0.0
var _search_time := 0.0
var _stuck_time := 0.0
var _dodge_time := 0.0
var _dodge_direction := Vector3.ZERO
var _idle_duration := 1.0
var _desired_speed := 0.0
var _previous_position := Vector3.ZERO
var _cover_query := PhysicsShapeQueryParameters3D.new()

var _capture_phase := Capture.POUNCE
var _capture_time := 0.0
var _capture_point: Node3D
var _original_parent: Node
var _original_layer := 0
var _rise_origin := Vector3.ZERO
var _origin_basis := Basis.IDENTITY
## Where the stowing starts from, already in capture-point coordinates: the limp
## body never stops in exactly the same pose, so the gesture starts from wherever
## it ended up.
var _stow_origin := Vector3.ZERO
var _stow_basis := Basis.IDENTITY
var _struggle := 1.0
var _jolt := Vector3.ZERO
var _jolt_spin := Vector3.ZERO
var _kick_time := 0.0
var _immune_time := 0.0

## What it died of, and how big it is for one of its species: the two halves of
## the price. `_paid` is the latch that keeps the reward from landing twice.
var _death_type := Death.Type.UNKNOWN
var _size := 1.0
var _paid := false

func _ready() -> void:
	add_to_group("rats")
	# `_process` belongs to the capture alone; loose on the map the rat lives in
	# physics.
	set_process(false)
	if species == null:
		species = DEFAULT_SPECIES
	_size = species.roll_size()
	_health = max_health
	_prepare_cover_query()
	_start_position = global_position
	_previous_position = global_position
	# Spreads the rats' decisions across different frames.
	_search_time = randf() * SEARCH_INTERVAL
	_pick_fur()
	_play_idle()
	# Each rat enters the animation at a different point of the cycle, otherwise
	# all ten breathe in the same rhythm.
	animator.seek(randf() * animator.current_animation_length, true)
	# It may be too early: the freshly baked mesh has not answered the server's
	# first sync yet. In that case it stays without a destination and the wander
	# tries again on the next frame.
	_pick_wander_target()

func _physics_process(delta: float) -> void:
	_immune_time = maxf(0.0, _immune_time - delta)

	if _state == State.DEAD:
		_apply_gravity(delta)
		move_and_slide()
		return

	# In the player's hand it leaves physics entirely: what rules its body now is
	# `_process`, which runs on the screen's beat and not on the 60 Hz one — held
	# against the camera, any mismatch between the two shows up as jitter.
	if _state == State.CAPTURED:
		return

	_state_time += delta
	_reassess_state()

	match _state:
		State.WANDERING:
			_process_wander(delta)
		State.IDLE:
			_process_idle(delta)
		State.FLEEING:
			_process_flee(delta)
		State.HIDING:
			_process_hide(delta)

	_apply_gravity(delta)
	move_and_slide()
	_update_animation()
	_check_stuck(delta)

	if global_position.y < MIN_HEIGHT:
		global_position = _start_position
		velocity = Vector3.ZERO

## Only runs while the rat is captured — see `set_process` in `_ready`.
func _process(delta: float) -> void:
	_capture_time += delta
	match _capture_phase:
		Capture.POUNCE:
			_process_pounce(delta)
		Capture.RISING:
			_process_rise(delta)
		Capture.IN_HAND:
			_process_in_hand(delta)
		Capture.GOING_LIMP:
			_process_limp(delta)
		Capture.STOWING:
			_process_stow(delta)

## Takes a hit. With `max_health` 1 (the default) any hit kills. `type` is what
## death the weapon kills with, and it is what decides how much the body pays.
func take_damage(amount: int = 1, origin: Vector3 = INVALID_POINT,
		type := Death.Type.UNKNOWN) -> void:
	if _state == State.DEAD or _state == State.CAPTURED:
		return
	_health -= amount
	if _health <= 0:
		_die(origin, 3.0, type)
		return
	_change_state(State.FLEEING)
	if origin != INVALID_POINT:
		velocity += _away_from(origin) * knockback_force

## True as soon as its health runs out, even in the moments when the body is
## still in the player's hand — going limp or dropping to the waist.
func is_dead() -> bool:
	if _state == State.CAPTURED:
		return _capture_phase == Capture.GOING_LIMP or _capture_phase == Capture.STOWING
	return _state == State.DEAD

func is_captured() -> bool:
	return _state == State.CAPTURED

## True only once it has finished rising and is settled in the hand.
func is_in_hand() -> bool:
	return _state == State.CAPTURED and _capture_phase == Capture.IN_HAND

## Where the middle of its body is in the world: the point the hand holds and
## the one the capture carries to the middle of the screen.
func body_center() -> Vector3:
	return global_position + global_basis * BODY_CENTER

# --- Capture ---------------------------------------------------------------
#
# The player grabs the rat, it is torn off the ground in an arc towards `point` —
# a node in the middle of the screen, child of the player's head — and from the
# moment it arrives it becomes a child of that node. Being a child is what keeps
# it *glued* to the middle of the screen no matter how fast the player swings the
# camera: there is no transform being chased frame by frame, it simply comes
# along.
#
# Strangled, it never goes back to the ground: it goes limp in the hand and drops
# to the waist, stowed. A carcass on the ground belongs to a rat killed from a
# distance — whatever dies in the player's hand vanishes with him.

## The player grabbed this rat. Returns false when it cannot be done: dead,
## already in someone's hand or freshly escaped.
func capture(point: Node3D) -> bool:
	if _state == State.DEAD or _state == State.CAPTURED or _immune_time > 0.0:
		return false

	_state = State.CAPTURED
	_capture_phase = Capture.POUNCE
	_capture_time = 0.0
	_capture_point = point
	_original_parent = get_parent()
	_original_layer = collision_layer
	_struggle = 1.0
	_jolt = Vector3.ZERO
	_jolt_spin = Vector3.ZERO
	_kick_time = randf_range(KICK_INTERVAL.x, KICK_INTERVAL.y)

	_clear_target()
	velocity = Vector3.ZERO
	# It leaves every layer so it neither pushes the player nor gets in the way
	# of the other rats' lines of sight while it hangs in the air. The mask stays
	# intact: it is what makes the carcass find the ground if it gets dropped.
	set_deferred("collision_layer", 0)
	# It stays in the `rats` group: for the HUD scoreboard it is still alive, and
	# rightly so — the player can still lose it.
	set_process(true)
	return true

## One squeeze of the neck. Counting the squeezes and deciding when it dies is
## the weapon's job; here the rat only reacts.
func squeeze() -> void:
	if _state != State.CAPTURED:
		return
	_struggle = 1.0
	model.scale = SQUEEZED_SCALE
	_kick(0.6)

## Died in the hand: it goes limp for a moment and is then stowed at the waist.
## `type` comes from the weapon that killed it — today only the hands get here,
## strangling.
func die_in_hands(type := Death.Type.STRANGULATION) -> void:
	if _state != State.CAPTURED or is_dead():
		return
	# Whoever hammered too fast can kill it before it has finished rising. In
	# that case it reaches the hand in one go and goes limp from there — without
	# this the body would go limp in hand coordinates while still hanging in the
	# world.
	if _capture_phase != Capture.IN_HAND:
		_snap_to_hand()
	_capture_phase = Capture.GOING_LIMP
	_capture_time = 0.0
	_struggle = 0.0
	animator.speed_scale = 1.0
	animator.play(ANIM_DEATH, BLEND)
	# For the scoreboard it already died here, on the last squeeze. What comes
	# after — going limp and being stowed — is only the gesture. The money, that
	# one only lands at the end of it: whoever kills and loses the body gets
	# nothing.
	_record_death(type)

## Got loose from the player's hand and bolts.
func escape() -> void:
	if _state != State.CAPTURED:
		return
	# It leaps out in front of the player. The direction comes from his body, not
	# from the rat's position: hanging in his hand the rat is *on top of* him,
	# and the usual "away from him" would have nowhere to point.
	var player := _get_player()
	var flight := -player.global_basis.z if player != null else -global_basis.z
	flight.y = 0.0
	flight = Vector3.FORWARD if flight.is_zero_approx() else flight.normalized()
	_return_to_world()
	_immune_time = IMMUNITY_TIME
	# `_change_state` only works coming from another state, and the flight has to
	# start from scratch for the rat to pick up `burst_speed`.
	_state = State.WANDERING
	_change_state(State.FLEEING)
	velocity = flight * flee_speed + Vector3.UP * ESCAPE_LEAP

## Takes the rat out of the hand and gives it back to the tree and the physics it
## came from.
func _return_to_world() -> void:
	set_process(false)
	if _original_parent != null and is_instance_valid(_original_parent) and get_parent() != _original_parent:
		reparent(_original_parent, true)
	# Straightens the body: it goes back to the ground on its feet, not upside
	# down.
	rotation = Vector3(0.0, rotation.y, 0.0)
	set_deferred("collision_layer", _original_layer)
	_capture_point = null

## The pounce: it hunches on the ground and the hand comes down on it.
func _process_pounce(delta: float) -> void:
	model.scale = model.scale.lerp(POUNCE_SCALE, minf(delta * 22.0, 1.0))
	if _capture_time < POUNCE_TIME:
		return
	_capture_phase = Capture.RISING
	_capture_time = 0.0
	_rise_origin = global_position
	_origin_basis = global_basis.orthonormalized()
	animator.speed_scale = STRUGGLE_CADENCE
	animator.play(ANIM_RUN, BLEND)

## The pull: from the ground to the hand, in an arc and somersaulting.
func _process_rise(_delta: float) -> void:
	var t := clampf(_capture_time / RISE_TIME, 0.0, 1.0)
	# It leaves the ground fast and slows down as it reaches the hand — that is
	# what gives the pull.
	var progress := 1.0 - pow(1.0 - t, 3.0)

	var pose := _capture_point.global_basis.orthonormalized() * Basis.from_euler(_radians(HELD_POSE))

	# The destination is read every frame: if the player walks or turns while the
	# rat is rising, the rat corrects its course in the air. The origin is not:
	# it stays where the rat was, in the world, otherwise it would rise "from
	# nowhere" on every camera swing. What reaches the point is the middle of its
	# body, and not the origin down at its feet — hence the rise aiming with the
	# anchoring it will have in the hand already discounted.
	var destination := _capture_point.global_position + _anchor(pose)
	var middle := (_rise_origin + destination) * 0.5 + Vector3.UP * ARC_HEIGHT
	global_position = _bezier(_rise_origin, middle, destination, progress)

	var spin := _origin_basis.get_rotation_quaternion().slerp(pose.get_rotation_quaternion(), progress)
	# The somersault unwinds as it arrives: at the end only the pose is left.
	var flip := Quaternion(Vector3.RIGHT, FLIP_SPIN * (1.0 - progress))
	global_basis = Basis(spin * flip)

	model.scale = STRETCHED_SCALE.lerp(Vector3.ONE, progress)

	if t >= 1.0:
		_snap_to_hand()

## It arrived: from now on it *is* a child of the point in the middle of the
## screen.
func _snap_to_hand() -> void:
	reparent(_capture_point, true)
	var pose := Basis.from_euler(_radians(HELD_POSE))
	transform = Transform3D(pose, _anchor(pose))
	_capture_phase = Capture.IN_HAND
	_capture_time = 0.0

## Where the rat's origin has to sit, in the `base` pose, for the middle of its
## body to land right on top of the capture point. It is why it struggles
## *around* the middle of the screen instead of sweeping the whole frame on
## every kick.
func _anchor(base: Basis) -> Vector3:
	return -(base * BODY_CENTER)

## Held in the hand: trembling the whole time, kicking now and then and biting
## when it can. All in local coordinates, over the point in the middle of the
## screen.
func _process_in_hand(delta: float) -> void:
	_struggle = lerpf(BASE_STRUGGLE, _struggle, pow(STRUGGLE_DAMPING, delta))
	_damp_jolt(delta)

	_kick_time -= delta
	if _kick_time <= 0.0:
		_kick_time = randf_range(KICK_INTERVAL.x, KICK_INTERVAL.y)
		_kick(1.0)
		if randf() < BITE_CHANCE:
			animator.play(ANIM_ATTACK, BLEND)
			animator.queue(ANIM_RUN)

	# Sine waves whose periods do not line up with each other: added together,
	# they do not repeat closely enough for the eye to catch the pattern.
	var t := _capture_time
	var tremor := Vector3(
		sin(t * 27.0) * 0.6 + sin(t * 41.0) * 0.4,
		sin(t * 33.0 + 1.3) * 0.5 + sin(t * 19.0) * 0.5,
		sin(t * 23.0 + 2.1)
	) * TREMOR * _struggle
	var spin := Vector3(
		sin(t * 21.0) * 0.5,
		sin(t * 17.0 + 0.7),
		sin(t * 29.0 + 2.2) * 0.7
	) * deg_to_rad(TREMOR_ANGLE) * _struggle

	basis = Basis.from_euler(_radians(HELD_POSE) + spin + _jolt_spin)
	position = _anchor(basis) + tremor + _jolt
	model.scale = model.scale.lerp(Vector3.ONE, minf(delta * 9.0, 1.0))

## Died: the body goes limp in the hand before being stowed.
func _process_limp(delta: float) -> void:
	_damp_jolt(delta)
	var t := minf(_capture_time / LIMP_TIME, 1.0)
	var hanging := Basis.from_euler(_radians(LIMP_POSE))
	basis = Basis(basis.get_rotation_quaternion().slerp(hanging.get_rotation_quaternion(), minf(delta * 9.0, 1.0)))
	# It slips out of the hand while going limp — always around the middle of its
	# body, otherwise the limp body would leave the frame mid-slump.
	position = position.lerp(_anchor(basis) + Vector3(0.0, -0.12, 0.05), minf(delta * 6.0, 1.0))
	model.scale = model.scale.lerp(Vector3.ONE, minf(delta * 9.0, 1.0))
	if t < 1.0:
		return

	# With no strength left in the animal at all, the arm goes down with it.
	_capture_phase = Capture.STOWING
	_capture_time = 0.0
	_stow_origin = position - _anchor(basis)
	_stow_basis = basis

## The stowing: the player lowers the dead rat from the middle of the screen to
## his waist, where it leaves the frame. This is where the hunt ends — the body
## does not go back to the world, it vanishes along with whoever killed it.
func _process_stow(_delta: float) -> void:
	var t := clampf(_capture_time / STOW_TIME, 0.0, 1.0)
	# It leaves the hand slowly and slows down at the waist: it is a gesture of
	# stowing something, not a body dropping.
	var progress := t * t * (3.0 - 2.0 * t)

	# The wrist turns before the arm goes down. Out of order, the still-lying
	# body sweeps the whole path with its snout and grazes the camera, swelling
	# on screen at exactly the frame it should be leaving it.
	var stowed := Basis.from_euler(_radians(STOWED_POSE))
	basis = Basis(_stow_basis.get_rotation_quaternion().slerp(
		stowed.get_rotation_quaternion(), smoothstep(0.0, 0.55, t)))

	# What travels the path is the middle of the body, as in the hand: that way
	# it goes down whole instead of pivoting around its feet.
	var middle := (_stow_origin + WAIST) * 0.5 + STOW_OFFSET
	position = _bezier(_stow_origin, middle, WAIST, progress) + _anchor(basis)

	# It vanishes by shrinking at the end of the path, the way the carcass
	# vanishes on the ground: anyone looking down sees the rat being stowed
	# rather than blinking out.
	model.scale = Vector3.ONE.lerp(Vector3(0.02, 0.02, 0.02), smoothstep(STOW_VANISH, 1.0, t))

	if t >= 1.0:
		# It reached the waist: this is where this rat's hunt ends and where it
		# turns into money.
		_pay_reward()
		queue_free()

func _kick(strength: float) -> void:
	_jolt = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-0.5, 0.5)) \
		.normalized() * KICK_FORCE * strength
	_jolt_spin = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) \
		.normalized() * deg_to_rad(KICK_FORCE_ANGLE) * strength

func _damp_jolt(delta: float) -> void:
	var left := pow(JOLT_DAMPING, delta)
	_jolt *= left
	_jolt_spin *= left

func _bezier(from: Vector3, middle: Vector3, to: Vector3, t: float) -> Vector3:
	return from.lerp(middle, t).lerp(middle.lerp(to, t), t)

func _radians(degrees: Vector3) -> Vector3:
	return Vector3(deg_to_rad(degrees.x), deg_to_rad(degrees.y), deg_to_rad(degrees.z))

# --- States ----------------------------------------------------------------

func _reassess_state() -> void:
	var distance := _player_distance()
	# Hidden, it puts up with the player a lot closer before bolting again.
	var hearing_limit := hidden_panic_radius if _state == State.HIDING else panic_radius
	var scared := distance <= hearing_limit or (distance <= _current_alert_radius() and _sees_player())

	match _state:
		State.WANDERING, State.IDLE:
			if scared:
				_change_state(State.FLEEING)
		State.FLEEING:
			if not scared and distance >= safe_radius:
				_change_state(State.WANDERING)
		State.HIDING:
			if scared:
				_change_state(State.FLEEING)
			elif distance >= safe_radius and _state_time > 2.0:
				_change_state(State.WANDERING)

func _change_state(new_state: State) -> void:
	if _state == new_state:
		return
	_state = new_state
	_state_time = 0.0
	match new_state:
		State.WANDERING:
			_pick_wander_target()
		State.IDLE:
			_clear_target()
			_idle_duration = randf_range(0.8, 2.4)
		State.FLEEING:
			_clear_target()
			_search_time = 0.0
		State.HIDING:
			_clear_target()
			velocity.x = 0.0
			velocity.z = 0.0

func _process_wander(delta: float) -> void:
	_target_time += delta
	if not _has_target or _target_time > 6.0 or agent.is_navigation_finished():
		# Now and then it stops to sniff instead of picking another destination.
		if randf() < 0.35:
			_change_state(State.IDLE)
			return
		_pick_wander_target()
	_move(_path_direction(), wander_speed, delta)

func _process_idle(delta: float) -> void:
	_move(Vector3.ZERO, 0.0, delta)
	if _state_time >= _idle_duration:
		_change_state(State.WANDERING)

func _process_flee(delta: float) -> void:
	_search_time -= delta
	if _search_time <= 0.0:
		_search_time = SEARCH_INTERVAL
		_search_hideout()

	if _has_target and agent.is_navigation_finished():
		# It reached the hideout: if the player cannot reach it with his eyes, it
		# keeps still.
		if not _sees_player() and _player_distance() > panic_radius:
			_change_state(State.HIDING)
			return
		_clear_target()
		_search_time = 0.0

	var direction := _path_direction()
	if direction.is_zero_approx():
		# No reachable hideout (or it fell off the mesh): it runs far away on
		# instinct, sniffing out walls ahead.
		direction = _dodge(_away_from(_player_position()))
	var speed := burst_speed if _state_time < BURST_TIME else flee_speed
	_move(direction, speed, delta)

func _process_hide(delta: float) -> void:
	_move(Vector3.ZERO, 0.0, delta)
	model.scale = model.scale.lerp(CROUCH_SCALE, minf(delta * 8.0, 1.0))

# --- Hideout ---------------------------------------------------------------

func _prepare_cover_query() -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = COVER_RADIUS
	_cover_query.shape = sphere
	_cover_query.collision_mask = SCENERY_LAYER
	_cover_query.exclude = [get_rid()]

## Picks where to run: it puts the blind spots behind nearby obstacles together
## with a fan of points behind it and keeps the best-scoring one.
func _search_hideout() -> void:
	var player := _get_player()
	if player == null or not _map_ready():
		_clear_target()
		return

	var player_position := player.global_position
	var player_eyes := player_position + Vector3.UP * PLAYER_HEIGHT
	# Found a good hideout? Then it does not keep changing its mind halfway.
	if _hideout_still_works(player_eyes):
		return
	_clear_target()

	var best := INVALID_POINT
	var best_score := -INF

	for point in _candidates(player_eyes, player_position):
		# The point's score comes first because it is cheap; the path only
		# subtracts, so anything already losing to the leader need not be asked
		# about at all.
		var score := _score_point(point, player_eyes, player_position)
		if score <= best_score:
			continue
		var path := _path_to(point)
		if path.is_empty():
			continue
		score -= _path_cost(path, player_position)
		if score > best_score:
			best_score = score
			best = point

	if best != INVALID_POINT:
		_set_target(best)

## The destinations it considers in this search, all already snapped to the mesh.
func _candidates(player_eyes: Vector3, player_position: Vector3) -> Array[Vector3]:
	var points: Array[Vector3] = []

	_cover_query.transform = Transform3D(Basis(), global_position)
	for found in get_world_3d().direct_space_state.intersect_shape(_cover_query, MAX_COVERS):
		var body := found.get("collider") as Node3D
		if body == null:
			continue
		# Cover is something that stands up in front of the player: the floor and
		# the ramps show up in the query, but they hide nobody.
		if body.global_position.y < global_position.y + 0.5:
			continue
		if _flat_distance(body.global_position, global_position) > COVER_RADIUS:
			continue
		var point := _blind_spot_behind(body.global_position, player_eyes)
		if point != INVALID_POINT:
			points.append(point)

	var flight := _away_from(player_position)
	for i in CANDIDATES:
		var direction := flight.rotated(Vector3.UP, randf_range(-FAN_SPREAD, FAN_SPREAD))
		var raw := global_position + direction * randf_range(MIN_SEARCH_DISTANCE, MAX_SEARCH_DISTANCE)
		var point := _navigable_point(raw)
		if point != INVALID_POINT:
			points.append(point)

	return points

## Walks behind the obstacle, moving away from the player, until it leaves his
## sight.
func _blind_spot_behind(center: Vector3, player_eyes: Vector3) -> Vector3:
	var direction := center - player_eyes
	direction.y = 0.0
	if direction.is_zero_approx():
		return INVALID_POINT
	direction = direction.normalized()
	# It starts from the rat's height, not from the obstacle's centre, which may
	# be quite high up.
	var base := Vector3(center.x, global_position.y, center.z)

	for i in COVER_STEPS:
		var point := _navigable_point(base + direction * (COVER_STEP * (i + 1)))
		if point == INVALID_POINT:
			continue
		if _flat_distance(point, global_position) > MAX_SEARCH_DISTANCE:
			continue
		if _blocked(player_eyes, point + Vector3.UP * EYE_HEIGHT):
			return point
	return INVALID_POINT

## The candidate's score before looking at the path: far from the player is good,
## out of his sight is better still, and a dead end loses points.
func _score_point(point: Vector3, player_eyes: Vector3, player_position: Vector3) -> float:
	var distance := _flat_distance(point, player_position)
	if distance < panic_radius:
		return -INF
	var score := distance
	if _blocked(player_eyes, point + Vector3.UP * EYE_HEIGHT):
		score += HIDDEN_BONUS
	return score + _exits_from_point(point) * EXIT_BONUS

## How many of the four directions around the point are clear. A closed corner
## returns zero or one: it hides well while the player stays away, and turns into
## a trap when he arrives.
func _exits_from_point(point: Vector3) -> int:
	var origin := point + Vector3.UP * EYE_HEIGHT
	var clear := 0
	for i in 4:
		var direction := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 4.0)
		if not _blocked(origin, origin + direction * EXIT_RANGE):
			clear += 1
	return clear

## How much the path subtracts from the score: its length, plus a heavy penalty
## if it grazes the player — a great hideout is no use if the rat has to walk
## past whoever is hunting it.
func _path_cost(path: PackedVector3Array, player_position: Vector3) -> float:
	var flat_player := Vector3(player_position.x, 0.0, player_position.z)
	var length := 0.0
	var closest := INF

	for i in range(1, path.size()):
		var from := Vector3(path[i - 1].x, 0.0, path[i - 1].z)
		var to := Vector3(path[i].x, 0.0, path[i].z)
		length += from.distance_to(to)
		var graze := Geometry3D.get_closest_point_to_segment(flat_player, from, to)
		closest = minf(closest, graze.distance_to(flat_player))

	var cost := length * PATH_WEIGHT
	if closest < panic_radius:
		cost += NEAR_MISS_PENALTY
	return cost

## The current hideout keeps working as long as the player neither reaches it
## with his eyes nor comes too close to it.
func _hideout_still_works(player_eyes: Vector3) -> bool:
	if not _has_target:
		return false
	if _flat_distance(_target, _player_position()) < panic_radius:
		return false
	return _blocked(player_eyes, _target + Vector3.UP * EYE_HEIGHT)

func _pick_wander_target() -> void:
	var direction := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	if direction.is_zero_approx():
		direction = Vector3.FORWARD
	var point := _navigable_point(global_position + direction.normalized() * randf_range(4.0, 12.0))
	if point == INVALID_POINT:
		_clear_target()
		return
	_set_target(point)

# --- Navigation ------------------------------------------------------------

## The mesh is baked when the map opens and only starts answering queries after
## the navigation server's first sync. Until then the rat has nowhere to go, and
## asking before that is an error.
func _map_ready() -> bool:
	var map := agent.get_navigation_map()
	return map.is_valid() and NavigationServer3D.map_get_iteration_id(map) > 0

func _set_target(point: Vector3) -> void:
	_target = point
	_has_target = true
	_target_time = 0.0
	agent.target_position = point

func _clear_target() -> void:
	_has_target = false
	# A target on top of its own body: the agent considers itself arrived and
	# stops asking for a path until the next decision.
	agent.target_position = global_position

## Where to walk now: the next step of the path to the target. While an emergency
## dodge lasts, it overrides the path.
func _path_direction() -> Vector3:
	if _dodge_time > 0.0:
		return _dodge_direction
	if not _has_target or agent.is_navigation_finished():
		return Vector3.ZERO
	var step := agent.get_next_path_position() - global_position
	step.y = 0.0
	return Vector3.ZERO if step.is_zero_approx() else step.normalized()

## Snaps a loose point onto the navigation mesh. Returns `INVALID_POINT` when it
## falls far from it — inside a crate, stuck in a wall, off the map — or on a
## level the rat cannot reach.
func _navigable_point(point: Vector3) -> Vector3:
	if not _map_ready():
		return INVALID_POINT
	var snapped := NavigationServer3D.map_get_closest_point(agent.get_navigation_map(), point)
	if _flat_distance(snapped, point) > MESH_TOLERANCE:
		return INVALID_POINT
	if absf(snapped.y - point.y) > MAX_HEIGHT_DROP:
		return INVALID_POINT
	return snapped

## Path to the point through the mesh. It comes back empty when the destination
## is on a separate island — on top of a platform, on the other side of a wall —
## and the path dies before getting there.
func _path_to(point: Vector3) -> PackedVector3Array:
	var map := agent.get_navigation_map()
	var path := NavigationServer3D.map_get_path(map, global_position, point, true)
	if path.size() < 2 or _flat_distance(path[-1], point) > MESH_TOLERANCE:
		return PackedVector3Array()
	return path

# --- Perception ------------------------------------------------------------

func _get_player() -> Node3D:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D
	return _player

func _player_position() -> Vector3:
	var player := _get_player()
	return player.global_position if player != null else INVALID_POINT

func _player_distance() -> float:
	var player := _get_player()
	if player == null:
		return INF
	return _flat_distance(global_position, player.global_position)

## The rat notices someone running past more than someone walking slowly.
func _current_alert_radius() -> float:
	var player := _get_player()
	if player is CharacterBody3D and (player as CharacterBody3D).velocity.length() > 7.0:
		return alert_radius * 1.4
	return alert_radius

func _sees_player() -> bool:
	var player := _get_player()
	if player == null:
		return false
	return not _blocked(
		global_position + Vector3.UP * EYE_HEIGHT,
		player.global_position + Vector3.UP * PLAYER_HEIGHT
	)

## True if there is scenery between the two points.
func _blocked(from: Vector3, to: Vector3) -> bool:
	var params := PhysicsRayQueryParameters3D.create(from, to, SCENERY_LAYER, [get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(params).is_empty()

# --- Movement --------------------------------------------------------------

## Deflects the requested direction when there is a wall ahead, trying wider and
## wider openings to both sides. It is plan B for a rat with no path through the
## mesh; one that has a path already comes routed around the scenery.
func _dodge(direction: Vector3) -> Vector3:
	if direction.is_zero_approx():
		return direction
	var origin := global_position + Vector3.UP * EYE_HEIGHT
	if not _whisker_hit(origin, direction):
		return direction
	for degrees: float in DODGE_ANGLES:
		var attempt := direction.rotated(Vector3.UP, deg_to_rad(degrees))
		if not _whisker_hit(origin, attempt):
			return attempt
	return -direction

func _whisker_hit(origin: Vector3, direction: Vector3) -> bool:
	return _blocked(origin, origin + direction.normalized() * WHISKER_RANGE)

func _move(direction: Vector3, speed: float, delta: float) -> void:
	direction.y = 0.0
	var standing := direction.is_zero_approx()
	_desired_speed = 0.0 if standing else speed
	var target := Vector3.ZERO if standing else direction.normalized() * speed
	velocity.x = move_toward(velocity.x, target.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, target.z, acceleration * delta)
	_turn_to(Vector3(velocity.x, 0.0, velocity.z), delta)
	model.scale = model.scale.lerp(Vector3.ONE, minf(delta * 8.0, 1.0))

func _turn_to(direction: Vector3, delta: float) -> void:
	if direction.length() < 0.2:
		return
	var angle := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, angle, 1.0 - exp(-turn_speed * delta))

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0)
	else:
		velocity.y -= gravity * delta

## The rat can still get wedged into a corner: pushed by the player, thrown off
## the mesh or squeezed against another rat. If it spends too long wanting to
## walk without going anywhere, it takes a step sideways and looks for another
## path.
func _check_stuck(delta: float) -> void:
	if _dodge_time > 0.0:
		_dodge_time -= delta

	# The maths uses the speed it *asked for*, not `velocity`: something running
	# head-on into a wall has its velocity zeroed by `move_and_slide` and would
	# pass for something that stopped on purpose.
	var expected := _desired_speed * delta * 0.3
	var walked := _flat_distance(global_position, _previous_position)
	if _desired_speed > IDLE_SPEED and walked < expected:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	_previous_position = global_position

	if _stuck_time > STUCK_TIME:
		_stuck_time = 0.0
		_shake_sideways()
		_clear_target()
		_search_time = 0.0
		if _state == State.WANDERING:
			_pick_wander_target()

## Picks a clear side and runs that way for a moment, just long enough to come
## loose from the corner before going back to following the path.
func _shake_sideways() -> void:
	var forward := _direction_to(_target) if _has_target else -global_basis.z
	var origin := global_position + Vector3.UP * EYE_HEIGHT
	# Roll which side to start on, otherwise ten rats stuck in the same corner
	# all leave to the right.
	var sides := [1.0, -1.0] if randf() < 0.5 else [-1.0, 1.0]
	_dodge_time = DODGE_TIME
	for side: float in sides:
		_dodge_direction = forward.rotated(Vector3.UP, side * PI * 0.5)
		if not _whisker_hit(origin, _dodge_direction):
			return
	_dodge_direction = -forward

# --- Looks and animation ---------------------------------------------------

## Gives this rat one of its species' furs, without touching the material the
## others share. A species with no fur at all keeps the model's material.
##
## The material it starts from is whatever is in place: the model's, or the PS1
## one if there is a `PS1MaterialApplier` on the `Mesh`. Since the applier runs
## in its own `_ready` — a child, therefore before the rat's `_ready` — the fur
## swap always happens afterwards, and it is the one that sticks.
func _pick_fur() -> void:
	var fur := species.roll_fur()
	if fur == null:
		return

	var current := mesh.get_surface_override_material(0)
	if current == null:
		current = mesh.mesh.surface_get_material(0)

	var material := current.duplicate()
	if material is ShaderMaterial:
		(material as ShaderMaterial).set_shader_parameter("albedo", fur)
	elif material is BaseMaterial3D:
		(material as BaseMaterial3D).albedo_texture = fur

	mesh.set_surface_override_material(0, material)

## The animation follows the speed, not the state: wandering it trots, fleeing it
## bolts, and standing still or hidden it goes back to the idle.
func _update_animation() -> void:
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	if flat_speed < IDLE_SPEED:
		_play_idle()
		return
	if animator.current_animation != ANIM_RUN:
		animator.play(ANIM_RUN, BLEND)
	animator.speed_scale = clampf(flat_speed / CYCLE_SPEED, MIN_CADENCE, MAX_CADENCE)

## Idle and sniff count as the same thing: while either of the two is playing the
## animation is not swapped. That way the sniff finishes in peace and runs
## straight back into the idle.
func _play_idle() -> void:
	if animator.current_animation == ANIM_IDLE or animator.current_animation == ANIM_SNIFF:
		return
	animator.speed_scale = 1.0
	if randf() < SNIFF_CHANCE:
		animator.play(ANIM_SNIFF, BLEND)
		animator.queue(ANIM_IDLE)
	else:
		animator.play(ANIM_IDLE, BLEND)

# --- Death -----------------------------------------------------------------

## Death on the game's books, whether it happens on the ground or in the player's
## hand: the rat leaves the tally of the living, stops being able to take a hit,
## records what it died of and tells whoever is listening. It pays nothing —
## paying belongs to `_pay_reward`.
func _record_death(type: Death.Type) -> void:
	_death_type = type
	remove_from_group("rats")
	# It leaves the rats' layer so it cannot be hit again. The mask stays: the
	# carcass still needs to find the ground.
	set_deferred("collision_layer", 0)
	died.emit(self, type)

## Closes this rat's account, once and only once. It applies when its hunt has
## ended, and each death ends somewhere: strangled, at the player's waist; killed
## from a distance, where the body fell. Escaping the hand closes no account at
## all.
func _pay_reward() -> void:
	if _paid:
		return
	_paid = true
	Wallet.collect(species, _death_type, _size)

## Drops dead where it stood, upright in the world. `leap` is the little hop the
## body makes as it takes the hit. Whatever dies strangled does not come through
## here: it vanishes at the player's waist, leaving no carcass.
func _die(origin: Vector3, leap := 3.0, type := Death.Type.UNKNOWN) -> void:
	_state = State.DEAD
	_record_death(type)
	# Killed from a distance, the body falls and the job ended right there: it
	# pays on the spot.
	_pay_reward()

	velocity = Vector3.UP * leap
	if origin != INVALID_POINT:
		velocity += _away_from(origin) * knockback_force

	animator.speed_scale = 1.0
	# The death animation does not repeat: it topples the rat and holds the last
	# frame.
	animator.play(ANIM_DEATH, BLEND)

	var tween := create_tween()
	# Undoes the hideout crouch, if it died hidden.
	tween.tween_property(model, "scale", Vector3.ONE, 0.2)
	tween.tween_interval(CARCASS_TIME)
	tween.tween_property(model, "scale", Vector3(0.02, 0.02, 0.02), 0.3).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

# --- Utilities -------------------------------------------------------------

func _direction_to(point: Vector3) -> Vector3:
	var direction := point - global_position
	direction.y = 0.0
	return direction.normalized()

func _away_from(point: Vector3) -> Vector3:
	if point == INVALID_POINT:
		return -global_basis.z
	var direction := global_position - point
	direction.y = 0.0
	if direction.is_zero_approx():
		return -global_basis.z
	return direction.normalized()

func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
