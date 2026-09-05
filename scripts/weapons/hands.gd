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
## Distance from the rat to the camera. It decides two things at once, and they
## pull the same way: how big the animal is on screen, and whether the player's
## own hand can reach it.
##
## It used to be 0.95, chosen for the size alone — the rat is nearly a metre
## from snout to hip, and at that distance it took up a little over half the
## height of the frame. What nobody had measured was the hand. The arm is about
## seventy centimetres from the elbow's cut to the fingertips and is drawn at
## `PlayerViewModel.scale_factor`, so its fingers reach 38 centimetres past the
## lens: the player was strangling an animal floating more than half a metre in
## front of an open hand, which on screen read as a rat hanging in mid-air by
## itself.
##
## Bringing it in is the half of the fix that costs nothing, because the two
## wants do not fight. Closer, the rat is *bigger*, not smaller. And it is near
## enough that the fist can be put on its neck without the forearm having to
## reach so far out that the elbow lands in the middle of the picture.
##
## ## Why it cannot simply keep coming
##
## Because the hand is nearer the lens than the rat is, so perspective grows the
## glove faster than the animal. Walking this in from 0.55 with the grip pose
## following it, the rat gained a fifth of its width on screen and the glove
## gained half again as much: at 0.42 the fist covered a fifth of the animal and
## the resting hand was already touching it, which leaves no grab to make.
##
## So closing the distance only helps while `PlayerViewModel.grip_scale` comes
## down to pay for it, and the two were solved together — the glove shrank from
## 1.17 to 1.05 as this came from 0.55 to here. That buys the rat about fifteen
## per cent more of the frame with the hand covering no more of it than before.
##
## Nearer than this stops paying. The margin against the animal's own kicking is
## what runs out first: at 0.46 the rat was drawn through the glove on a twentieth
## of their overlap and the reading swung by four points between runs, where here
## it stays under one per cent of it and only a hard kick moves it
## (`_test_grip.gd: MAX_BEHIND`).
##
## Bound to `PlayerViewModel.grip_offset`, `grip_rotation` and `grip_scale`: the
## four were solved together, and `_test_grip.gd` is what says the fist is still
## on the animal after any of them moves.
##
## ## Why it came in past the fist anyway
##
## Everything above solves for the glove being drawn *in front of* the animal,
## and at 0.48 it was: the fist sat at about 0.33 from the lens and the rat two
## thirds of a hand behind it, so the sleeves closed over the animal and the
## player's own arms were the thing he was watching. Brought inside the fist, to
## 0.26, the rat is the near body and the gloves close behind it — the hand still
## reads as holding the neck, because it is drawn either side of it and a tenth
## of a frame above the body, but it no longer hides what it is holding.
##
## The size it gains by coming in is paid back in `rat.gd: FIRST_PERSON_SCALE`
## rather than in `grip_scale`: the glove's own pose is what the arithmetic above
## solved and it is left where it was.
##
## This inverts what `_test_grip.gd` measures. `MAX_BEHIND` and `MAX_HIDDEN` both
## read *hand in front of rat* as the correct picture, so the bench now reports
## the intended pose as three failures — the resting hand having no distance to
## travel, the fist being behind the animal, and the animal covering the whole of
## their overlap. The numbers on those lines are still the ones to read.
@export var hands_distance := 0.26
## Height of the point the animal's middle is pinned to, relative to the centre
## of the screen.
##
## Below centre, and for the reason it always was: held by the neck the rat
## stretches its head upwards, so the point it hangs from has to sit under the
## middle of the frame for the *body* to land in the middle of it.
##
## It used to be 0.1, which is more than twice this, and it was too much of that
## good thing. The held point came out twelve per cent of the frame below the
## crosshair, and the animal hung on downwards from there: its body sat in the
## bottom half of the picture and its tail crossed the strangling prompt, so the
## player was hammering at a rat that had dropped out of his own aim and into the
## HUD. Here the point sits five per cent below centre, the drawn body straddles
## the middle of the frame, and the tail ends above the prompt.
##
## `PlayerViewModel.grip_offset` has to come up with it, and not by this many
## metres: the fist is held about 30 centimetres from the lens and the rat at
## `hands_distance`, so the same distance on screen is a shorter one in metres
## for whichever of the two is nearer. What has to be held constant is the gap
## between them *on screen* — the fist about a tenth of a frame above the held
## point, which is where a neck is — and `_test_grip.gd` prints both readings
## every run.
##
## It came up from -0.04 when the animal came in past the fist: nearer the lens,
## the same drop in metres is a longer one on screen, and at the old value the
## body hung a seventh of a frame under the gloves instead of in them. It is
## above centre now rather than below, which is the second half of the same
## move: the drawn body is longer on screen at this distance, so the point it
## hangs from has to rise for the *body* to straddle the middle of the frame.
## The bench reads the drawn rat at 0.43 of the frame and the fist at 0.41.
@export var hands_height := 0.030
## How far the point the animal's middle is pinned to sits to the side of the
## centre of the screen, in the same units as `hands_distance`. Negative is left.
##
## It is off centre because the gloves are. Both fists come from the right of the
## frame — `PlayerViewModel.grip_offset.x` is positive and the far hand is the
## near one mirrored and nudged, not a second arm — so the pair closes a little
## right of the crosshair. A rat hung exactly on the crosshair is held by its
## left-hand side, and this is what puts its neck back between the two fists.
##
## Small, and it stays small: this moves the *animal*, not the hands, so a large
## value buys a rat off to one side of a grip that stayed where it was.
@export var hands_side := -0.02

## The rat died in the hand and the player is putting it away: the arm holds the
## body for `wait` seconds, takes `fall` to carry it down out of the frame, and
## `rise` to come back up empty.
##
## It is separate from `finished` because the two say different things and used
## to be conflated. `finished` is *the hands are free* — the bar comes off the
## screen, the crosshair comes back, the click means grab again — and it is true
## the instant the last squeeze lands. This one is *the arm is still busy with the
## body*, which goes on for a second longer, and is the only thing that has any
## business knowing it. Sent for a kill and not for an escape: a rat that got
## loose left under its own power and there is nothing left in the hand to carry.
signal stowing(wait: float, fall: float, rise: float)

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

## How long the arm comes back up for after it has put the body away.
##
## Slower than the way down, and slower than `PlayerViewModel.grip_time` — which
## is what the hand would otherwise use to return, and which is fast because it
## is the answer to a grab. Coming back is the one part of the gesture with
## nothing chasing it: the rat is gone, the hand is empty, and an arm that
## snapped back to its corner would undo the weight the descent had just put into
## it.
const RISE_TIME := 0.42

## How much of the slump the arm cuts off the front of its own wait, in seconds:
## the hand starts down slightly before the body does.
##
## The body does not hang perfectly still while it goes limp. It slips a little
## way out of the fist as the strength leaves it (`rat.gd: _process_limp` settles
## it about twelve centimetres below where it was held), and then sets off for
## the waist the instant the slump ends. An arm that waited out the whole of
## `LIMP_TIME` and then eased into its descent was behind the animal at both
## moments — the rat sagged out of a hand that stayed up, and then dropped away
## while the arm was still getting going.
##
## Photographed rather than reasoned out: the arithmetic said the two arrived at
## the belt together, which they did, and the pictures said the rat spent the
## first third of the journey below the glove. Leading by this much puts the hand
## on the body through the middle of the gesture, which is the part the player is
## actually watching.
const STOW_LEAD := 0.18

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
	capture_point.position = Vector3(hands_side, hands_height, -hands_distance)

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
	# Announced before the arithmetic, so that a squeeze which happens to be the
	# killing one is still seen as a squeeze: the last click of a strangling is
	# the one a watcher most wants to see land.
	squeezed.emit()
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
		# The body is dead but it is not out of the hand yet: it slumps, and then
		# the player carries it down to his belt. The arm is told to go with it —
		# see `stowing` for why this is not simply the end of the grip.
		#
		# The two counts come off the rat, which is the one that knows how long
		# its own body takes to do either (`rat.gd: LIMP_TIME`, `STOW_TIME`).
		# Asked for rather than reached for: these hands do not know what a rat
		# is beyond what it answers, and a weapon that read another script's
		# constants would break the day something else could be strangled.
		var wait: float = rat.LIMP_TIME if "LIMP_TIME" in rat else 0.0
		var fall: float = rat.STOW_TIME if "STOW_TIME" in rat else 0.0
		stowing.emit(maxf(wait - STOW_LEAD, 0.0), fall + STOW_LEAD, RISE_TIME)
		# The rat died mid-hammering and more clicks are still coming in behind:
		# without this pause they would grab the next rat without the player
		# meaning to.
		#
		# It lasts the whole of the stowing rather than the usual cooldown, and
		# that is the gesture's doing rather than the cadence's: a grab landing
		# while the arm is still on its way down cancels the descent
		# (`PlayerViewModel.set_gripping`), and what the player would see is the
		# body he just killed dropping out of shot on its own while his hand
		# leaves it to snatch the next one — which is the thing the whole stow
		# was written to stop.
		start_cooldown(wait + fall + RISE_TIME)
	else:
		# It got away precisely because nobody was clicking; there is nothing to
		# hold on to.
		rat.escape()
	pressure_changed.emit(0.0)
	finished.emit(killed)
