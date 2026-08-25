class_name Hands
extends Weapon
## The hands: the game's first weapon, and the only one that does not kill in
## one go.
##
## The click grabs the rat in the sights. It is torn off the ground, rises to the
## hand and stays in the middle of the screen struggling. From then on the same
## click is what kills: each one squeezes its neck a little harder, and the
## pressure drains on its own while the player does not click again. Stopping
## the hammering means losing the rat.
##
## What this node controls is the *rule* of the strangling — how much each
## squeeze is worth, when the rat dies, when it gets loose. How the rat rises,
## struggles and dies is `rat.gd`'s business. The capture signals are the ones
## from `Weapon`.

@export_group("Strangling")
## Squeezes to kill a rat, if the player hammers without stopping. Hammering
## slowly takes more, because the pressure drains between one click and the next.
@export var squeezes_to_kill := 12
## How much of the pressure drains per second with the player standing still.
@export var decay := 0.32
## Time with the pressure at zero before the rat gets loose from the hand.
@export var time_to_escape := 1.6

@export_group("Hand")
## Distance from the rat to the camera. It is what decides its size on screen:
## the animal is nearly a metre from snout to hip, and standing at this distance
## it takes up a little over half the height of the frame, with its tail hanging
## all the way down.
@export var hands_distance := 0.95
## Height of the middle of its body relative to the centre of the screen. It
## sits below centre on purpose: held by the neck it stretches its head upwards,
## and it is the body — not the animal's geometric middle — that has to land in
## the middle of the frame.
@export var hands_height := -0.1

## Strength of the shake from the grab, and from each squeeze.
const GRAB_RECOIL := 1.0
const SQUEEZE_RECOIL := 0.45
## What death these hands kill with. Strangled, the rat arrives whole, without a
## hole in its fur, and that is why the hands are the ones that pay most — no
## weapon will ever earn more than they do.
const DEATH_TYPE := Death.Type.STRANGULATION

@onready var capture_point: Node3D = get_parent().get_node("CapturePoint")

## How long the hands wait to be told a grab worked before giving up on it.
##
## A guest's grab is a request, and it is answered optimistically so the hand
## does not go dead for a round trip (`rat.gd: capture`). This is the other half
## of that bargain: if the rat has not come back as ours within this, the host
## said no — somebody else got to it first, or it was already dead when we swung
## — and the hands quietly let go of a rat they never had. It is generous on
## purpose. A grab lost to a hiccup in the wire is worse than one that hangs a
## moment longer than it should.
const CLAIM_TIMEOUT := 0.6

var _rat: Node3D
var _pressure := 0.0
var _empty_time := 0.0
## How long we have been holding a rat the host has not yet confirmed is ours.
## Negative once it is confirmed, which is the ordinary case within a frame or
## two and for the whole of a solo hunt.
var _claim_time := 0.0
## How much of the usual strangling this rat is worth, read at the moment of the
## grab. It is latched and not asked for again on purpose: taking the animal off
## the glue is what un-sticks it, so by the time it is in the hand it no longer
## remembers having been stuck (`rat.gd: capture()`).
var _effort := 1.0

func _ready() -> void:
	super()
	capture_point.position = Vector3(0.0, hands_height, -hands_distance)

func _process(delta: float) -> void:
	super(delta)
	if not _is_holding():
		return
	if _forget_lost_rat(delta):
		return

	_set_pressure(_pressure - decay * delta)

	# While the rat is still rising it does not count as dropped: the escape
	# clock only starts once it reaches the hand.
	if _pressure > 0.0 or not _rat.is_in_hand():
		_empty_time = 0.0
		return
	_empty_time += delta
	if _empty_time >= time_to_escape:
		_release(false)

func is_busy() -> bool:
	return _is_holding()

## The grab.
func _use() -> void:
	if _is_holding():
		return
	var target := _rat_in_sights()
	_animate_swing()
	used.emit(target != null)
	if target == null:
		return
	# Read *before* the grab: the capture is what tears the rat off the glue, and
	# after it the animal has no memory of having been stuck.
	var effort: float = target.effort() if target.has_method("effort") else 1.0
	if not target.capture(capture_point):
		return

	_rat = target
	_effort = effort
	_pressure = 0.0
	_empty_time = 0.0
	_claim_time = 0.0
	_add_recoil(GRAB_RECOIL)
	caught.emit(_rat)
	pressure_changed.emit(0.0)

## One squeeze of the neck.
##
## How many it takes is the hands' rule, but the animal gets a say in it: one
## that was already caught when it was picked up — stuck on the glue, and
## tomorrow whatever else holds a rat down — gives in in a fraction of the
## squeezes. The hands never learn what glue is; they only ask the rat how much
## of the usual work it is worth (`rat.gd: effort()`).
func press_secondary() -> void:
	if not _is_holding():
		return
	_rat.squeeze()
	_add_recoil(SQUEEZE_RECOIL)
	var goes := maxf(1.0, float(squeezes_to_kill) * _effort)
	_set_pressure(_pressure + 1.0 / goes)
	if _pressure >= 1.0:
		_release(true)

## Whether the rat in these hands is really in them.
##
## Solo, and on the host, it always is: `capture` there does the whole job before
## it answers, so the animal is ours from the frame we clicked. On a guest the
## grab crossed the wire as a request, and the answer comes back as the rat
## saying whose it is — so for the first fraction of a second the hands are
## holding something that may turn out to belong to somebody else, or to nobody.
##
## Returns true when it has given up, having already put the player back to
## normal. Everything the hands do afterwards is skipped on that frame: squeezing
## a rat we do not have would be pressure spent on nothing.
func _forget_lost_rat(delta: float) -> bool:
	if _rat.has_method("is_held_by_me") and _rat.is_held_by_me():
		# Confirmed ours. The clock is wound right back rather than merely
		# stopped: a rat can be lost and re-grabbed inside one hunt and each grab
		# gets its own grace.
		_claim_time = 0.0
		return false
	_claim_time += delta
	if _claim_time < CLAIM_TIMEOUT:
		return false
	# Never ours. Nothing is asked of the rat on the way out — it is not ours to
	# release, and whoever does have it is holding it perfectly happily.
	_rat = null
	_pressure = 0.0
	_empty_time = 0.0
	_effort = 1.0
	_claim_time = 0.0
	pressure_changed.emit(0.0)
	finished.emit(false)
	return true

func _is_holding() -> bool:
	if _rat != null and not is_instance_valid(_rat):
		# The rat vanished behind the scenes (scene reload, `queue_free`): drop
		# the reference and give the player back to normal.
		_rat = null
		finished.emit(false)
	return _rat != null

func _set_pressure(value: float) -> void:
	var new_value := clampf(value, 0.0, 1.0)
	if is_equal_approx(new_value, _pressure):
		return
	_pressure = new_value
	pressure_changed.emit(_pressure)

func _release(killed: bool) -> void:
	var rat := _rat
	_rat = null
	_pressure = 0.0
	_empty_time = 0.0
	_effort = 1.0
	_claim_time = 0.0
	if killed:
		rat.die_in_hands(DEATH_TYPE)
		# The rat died mid-hammering and more clicks are still coming in behind:
		# without this pause they would grab the next rat without the player
		# meaning to.
		start_cooldown()
	else:
		# It got away precisely because nobody was clicking; there is nothing to
		# hold on to.
		rat.escape()
	pressure_changed.emit(0.0)
	finished.emit(killed)
