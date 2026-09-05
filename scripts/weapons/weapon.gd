class_name Weapon
extends Node3D
## Base class for the player's weapons.
##
## Every weapon lives under the player's head, looks for the rat in the sights
## the same way — the closest one inside a cone around the centre of the screen,
## with no wall in between — and decides on its own what to do with it. What
## changes from one weapon to the next is `_use()`.
##
## A weapon can be *busy*: while it is, the player cannot use another one nor
## move freely. The hands stay busy holding the rat; a hammer, for instance,
## never would. Busy is also what keeps it on the player's belt: there is no
## swapping weapons with a rat kicking in your hand (see
## `scripts/weapons/inventory.gd`).
##
## Every weapon also declares *what death* it kills with (a `Death.Type`, see
## `scripts/economy/death.gd`) and passes that type to the rat when killing it —
## the rat is the one that decides how much the body will pay. Whoever delivers
## the whole animal gets more; whoever takes it apart, less.

## One use of the weapon. `hit` is false when there was no rat in the sights.
@warning_ignore("unused_signal") # Emitted by subclasses (see hands.gd, glue_weapon.gd).
signal used(hit: bool)

# The three signals of a weapon that *holds* a rat instead of settling it in one
# blow. A weapon that never occupies the player simply does not emit them, and
# the HUD never opens.
## Caught the rat and is busy with it from now on.
@warning_ignore("unused_signal") # Emitted by subclasses (see hands.gd, glue_weapon.gd).
signal caught(rat: Node3D)
## How far along the job is, from 0 to 1.
@warning_ignore("unused_signal") # Emitted by subclasses (see hands.gd, glue_weapon.gd).
signal pressure_changed(fraction: float)
## Let go of the rat: `killed` says whether it died or got away.
@warning_ignore("unused_signal") # Emitted by subclasses (see hands.gd, glue_weapon.gd).
signal finished(killed: bool)
## One squeeze of a rat already held: the player pressed again and the weapon
## did something to the animal in its grip.
##
## It is separate from `used` and carries nothing, and both of those are on
## purpose. `used` is the swing that goes looking for a rat — it can miss, which
## is what its `hit` says — and this one cannot: there is already an animal in
## the hand or this would not have been called. What wants it is everybody
## *else's* screen, where the whole of a strangling was invisible until the
## squeezes crossed the wire (`PlayerAvatar.Action.SQUEEZE`); the pressure it
## adds is a different signal (`pressure_changed`) because that one drains on
## its own and this one is a thing the player did.
@warning_ignore("unused_signal") # Emitted by subclasses (see hands.gd).
signal squeezed()

## What the weapon is called on the player's belt.
@export var display_name := "Weapon"
## The picture that stands for it in the belt's square. While a weapon has none,
## the belt writes its name in the square instead.
@export var icon: Texture2D

@export_group("Reach")
@export var reach := 2.6
## Spread (degrees) of the cone around the sights.
@export var angle := 50.0
@export var cooldown := 0.4

@export_group("Recoil")
## Maximum offset (camera units) of the view shake.
@export var max_recoil := 0.035
## How much of the recoil is left after one second.
@export var recoil_damping := 0.0008

## Height of the aim point on the rat, level with its body.
const RAT_TARGET_HEIGHT := 0.2
## Only the scenery blocks the sights (layer 1).
const SCENERY_LAYER := 1

var _cooldown_left := 0.0
var _recoil := Vector2.ZERO
var _initial_rotation: Vector3
var _swing_tween: Tween

@onready var camera: Camera3D = get_parent().get_node("Camera")
## The player's body: the wall checks start from it, and it is the one that has
## to be left out of them.
@onready var player: CharacterBody3D = get_parent().get_parent() as CharacterBody3D

func _ready() -> void:
	_initial_rotation = rotation

func _process(delta: float) -> void:
	_cooldown_left = maxf(0.0, _cooldown_left - delta)
	_damp_recoil(delta)

## Tries to use the weapon. Nothing happens while it is cooling down.
func try_use() -> void:
	if _cooldown_left > 0.0:
		return
	_cooldown_left = get_cooldown()
	_use()

## Puts the weapon on cooldown without using it. It keeps the click that ended
## one job from running straight into the next, now that grabbing and strangling
## share the same button.
##
## `seconds` is for the weapon that has some reason of its own to be held off
## longer than its cadence — the hands, whose kill is followed by a gesture the
## next grab would cut in half (`hands.gd: _release`). It never shortens one: the
## cadence is the floor, and a weapon asking for less than its own cooldown is
## asking for something it does not get.
func start_cooldown(seconds := 0.0) -> void:
	_cooldown_left = maxf(get_cooldown(), seconds)

## Current cooldown duration, which can vary by weapon type and phase.
func get_cooldown() -> float:
	return cooldown

## Whether a click would reach the weapon right now, or be swallowed by the
## cadence. It is what `try_use` asks itself, asked from outside: the hands hold
## the belt for the whole of the gesture that puts a dead rat away
## (`hands.gd: _release`), which is a good deal longer than the usual cooldown,
## and anything that means to grab the next rat has to be able to tell "not yet"
## from "nothing there".
func is_ready() -> bool:
	return _cooldown_left <= 0.0

## Taken out of the belt: from here on it is the one the click reaches.
func equip() -> void:
	visible = true
	set_process(true)

## Put away. Everything the weapon was doing on screen stops here — the swing
## halfway through, the shake it left in the camera — because from now on nobody
## is going to run its `_process` to finish any of it. The cooldown stays where
## it is on purpose: swapping slots is no way around the weapon's cadence.
func unequip() -> void:
	set_process(false)
	if _swing_tween != null and _swing_tween.is_running():
		_swing_tween.kill()
	rotation = _initial_rotation
	_clear_recoil()
	visible = false

## True while the weapon is in the middle of something that ties the player
## down. Weapons that settle everything in one blow leave this as it is.
func is_busy() -> bool:
	return false

## True while the weapon will not be put away, whether or not it is holding the
## player down. The two come apart for the first time with the glue: laying a
## strip of it is something the player does *while walking*, so he is not busy —
## but he cannot reach for another weapon halfway through either, because a strip
## abandoned between its two clicks is neither on the floor nor back in the box.
##
## Being busy is always reason enough; a weapon that wants the belt for some
## other reason of its own says so here.
func holds_belt() -> bool:
	return is_busy()

## Calls off whatever the weapon had started and not finished. Returns whether
## there was in fact anything to call off, so whoever asked — the key that could
## just as well have meant something else — knows whether it was spent here.
func cancel() -> bool:
	return false

## Whether the weapon can be taken out at all. The hands always can; a weapon
## that runs out — a box of traps — says no once it is empty, and the belt then
## treats its slot as the empty loop it has become
## (`scripts/weapons/inventory.gd`).
func available() -> bool:
	return true

## Whether this weapon is an attack weapon (used to damage or kill rats).
## Attack weapons are barred during the SURVEY phase (Card 12), while non-attack
## utilities (traps, baits, patches, map, flashlight) remain available.
func is_attack_weapon() -> bool:
	return true

## Relay of the secondary action (the click, with the hands full) while the
## weapon is busy.
func press_secondary() -> void:
	pass

## What the weapon does. Every weapon overrides this.
func _use() -> void:
	pass

# --- Sights ----------------------------------------------------------------

## Closest rat within reach, inside the cone and with no wall in the way.
func _rat_in_sights() -> Node3D:
	var origin := camera.global_position
	var forward := -camera.global_basis.z
	var limit := cos(deg_to_rad(angle))
	var best: Node3D = null
	var closest_distance := INF

	for node in get_tree().get_nodes_in_group("rats"):
		var rat := node as Node3D
		if rat == null or not rat.has_method("take_damage"):
			continue
		# A rat already in someone's hand does not count as a target.
		if rat.has_method("is_captured") and rat.is_captured():
			continue
		var point := rat.global_position + Vector3.UP * RAT_TARGET_HEIGHT
		var to_rat := point - origin
		var distance := to_rat.length()
		if distance > reach or distance >= closest_distance:
			continue
		if distance > 0.05 and forward.dot(to_rat / distance) < limit:
			continue
		if _wall_between(origin, point):
			continue
		best = rat
		closest_distance = distance

	return best

func _wall_between(from: Vector3, to: Vector3) -> bool:
	var params := PhysicsRayQueryParameters3D.create(from, to, SCENERY_LAYER, [player.get_rid()])
	return not get_world_3d().direct_space_state.intersect_ray(params).is_empty()

# --- On-screen feedback ----------------------------------------------------

## The weapon's thrust. While there is no model at all under this node it runs
## invisibly; the day the hands arrive, the gesture is already there.
func _animate_swing() -> void:
	if _swing_tween != null and _swing_tween.is_running():
		_swing_tween.kill()
	rotation = _initial_rotation
	_swing_tween = create_tween()
	_swing_tween.tween_property(self, "rotation", _initial_rotation + Vector3(deg_to_rad(-80.0), 0.0, 0.0), 0.09) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_property(self, "rotation", _initial_rotation, 0.22) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)

## Shakes the view. It moves the camera's offset, not the head's rotation, which
## belongs to the mouse — the two would fight over the same value.
func _add_recoil(strength: float) -> void:
	_recoil += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized() * max_recoil * strength
	_recoil = _recoil.limit_length(max_recoil)

func _damp_recoil(delta: float) -> void:
	if _recoil.is_zero_approx():
		# An imperceptible remainder is left: zero it in one go and put the
		# camera back in place, instead of leaving the view crooked forever over
		# a thousandth.
		if _recoil != Vector2.ZERO:
			_clear_recoil()
		return
	_recoil = _recoil.lerp(Vector2.ZERO, 1.0 - pow(recoil_damping, delta))
	camera.h_offset = _recoil.x
	camera.v_offset = _recoil.y

## Ends the shake right where it is and gives the camera back straight.
func _clear_recoil() -> void:
	_recoil = Vector2.ZERO
	camera.h_offset = 0.0
	camera.v_offset = 0.0
