class_name Hands
extends Weapon
## Three timed squeezes kill a held rat. A miss or an expired sweep releases it.
## Rat animation, ownership and payment keep their existing lifecycle.

signal timing_changed(pointer: float, zone_start: float, zone_width: float)

const HITS_TO_KILL := 3
const SWEEP_SECONDS := [1.6, 1.2, 0.8]
const ZONE_WIDTH := 0.22
const MIN_ZONE_SHIFT := 0.18

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
## (`MAX_BEHIND`).
##
## Bound to `PlayerViewModel.grip_offset`, `grip_rotation` and `grip_scale`: the
## four were solved together, and the grip measurements say the fist is still
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
## This inverts the grip measurements. `MAX_BEHIND` and `MAX_HIDDEN` both
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
## point, which is where a neck is — and the grip measurements print both readings
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

## The rat died in the fist and is coming apart: the hand stays closed on it for
## `windup` seconds, and then there is nothing left in it.
##
## It is separate from `finished` because the two say different things. `finished`
## is *the hands are free* — the bar comes off the screen, the crosshair comes
## back, the click means grab again — and it is true the instant the last squeeze
## lands. This one is *the fist is still closed on a body*, which goes on for a
## fraction of a second longer, and is the only thing that has any business
## knowing it. Sent for a kill and not for an escape: a rat that got loose left
## under its own power and opened the hand on the way out.
##
## It replaced a `stowing` that carried three counts — the wait, the fall to the
## waist and the empty arm coming back up — because the gesture it described no
## longer happens. There is no body to carry anywhere.
signal bursting(windup: float)

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
# A guest needs a request to reach the host and the host's synchronised answer
# to return.  The old 0.6-second grace was shorter than that exchange on a
# normal higher-latency Steam connection, so player two released a valid grab
# before `sync_holder` could confirm it.
const CLAIM_TIMEOUT := 2.0

## The cry of a rat being squeezed, and how it climbs.
##
## Every squeeze plays the same sample a little higher than the last, from the
## first go at `HURT_PITCH.x` up to `HURT_PITCH.y` on the one that kills it. That
## climb is the whole of the feedback the strangling has: the bar on screen says
## how far along it is, but the bar is a bar, and what the player actually reads
## is an animal whose voice is going up as it runs out of room. Held at one pitch
## it is the same click twelve times and the hammering feels like nothing.
##
## It is pitch and not volume because a rat does not get *louder* as it dies, it
## gets higher — and because the last squeeze has to be audibly the last one
## without the mix having to swell for it.
const HURT_PITCH := Vector2(0.85, 1.75)
## The spread rolled either side of that ladder, so two rats strangled at the
## same cadence are not the same twelve sounds.
const HURT_PITCH_SPREAD := 0.06

## The beat the hands hold after the animal has come apart, on top of the burst
## itself, before a click can grab again.
##
## It is short — the burst is a fast, brutal thing and the player should be back
## in the hunt right after it — but it is not nothing. Without it the frame the
## spray appears on is a frame the player can already be grabbing the next rat
## through, and the kill he just made lands somewhere behind him.
const BURST_RECOVERY := 0.18

var _rat: Node3D
var _pressure := 0.0
var _hits := 0
var _pointer := 1.0
var _zone_start := 0.0
var _zone_width := ZONE_WIDTH
var _previous_zone_center := -1.0
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

	# The timing window starts once the rat reaches the hand.
	if not _rat.is_in_hand():
		return
	_pointer = maxf(0.0, _pointer - delta / SWEEP_SECONDS[_hits])
	timing_changed.emit(_pointer, _zone_start, _zone_width)
	if _pointer <= 0.0:
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
	_hits = 0
	_claim_time = 0.0
	_add_recoil(GRAB_RECOIL)
	caught.emit(_rat)
	pressure_changed.emit(0.0)
	_start_sweep()

## Only clicks in the target count; trapped rats have a wider timing window.
func press_secondary() -> void:
	if not _is_holding() or not _rat.is_in_hand():
		return
	if _rat.has_method("is_held_by_me") and not _rat.is_held_by_me():
		return
	if _pointer < _zone_start or _pointer > _zone_start + _zone_width:
		_release(false)
		return
	_rat.squeeze()
	_add_recoil(SQUEEZE_RECOIL)
	# Announced before the arithmetic, so that a squeeze which happens to be the
	# killing one is still seen as a squeeze: the last click of a strangling is
	# the one a watcher most wants to see land.
	squeezed.emit()
	_hits += 1
	_set_pressure(float(_hits) / HITS_TO_KILL)
	# The cry, on the pressure *after* this squeeze rather than before it: the
	# click the player just made is the one he should hear, and pitching it off
	# the pressure he had a moment ago is an animal always one squeeze behind
	# its own throat.
	_cry()
	if _hits >= HITS_TO_KILL:
		_release(true)
	else:
		_start_sweep()


func _start_sweep() -> void:
	_pointer = 1.0
	# Glue makes the target wider while preserving the three-hit requirement.
	_zone_width = clampf(ZONE_WIDTH / maxf(_effort, 0.5), ZONE_WIDTH, 0.36)
	var min_center := 0.08 + _zone_width * 0.5
	var max_center := 0.92 - _zone_width * 0.5
	# Sample the full track, excluding nearby positions even across grabs.
	var excluded_start := clampf(_previous_zone_center - MIN_ZONE_SHIFT, min_center, max_center)
	var excluded_end := clampf(_previous_zone_center + MIN_ZONE_SHIFT, min_center, max_center)
	var left_span := excluded_start - min_center
	var offset := randf_range(0.0, left_span + max_center - excluded_end)
	var center := min_center + offset if offset < left_span else excluded_end + offset - left_span
	_zone_start = center - _zone_width * 0.5
	_previous_zone_center = center
	timing_changed.emit(_pointer, _zone_start, _zone_width)

## The rat's own voice, climbing with the pressure on its neck. See `HURT_PITCH`
## for why the climb is the point.
##
## It comes off the *rat* rather than these hands, because that is where the
## sound is coming from and everybody in the house should hear it from there —
## a strangling in the far corner of the map is a thing you can follow with your
## ears.
func _cry() -> void:
	if _rat == null or not is_instance_valid(_rat):
		return
	var pitch := lerpf(HURT_PITCH.x, HURT_PITCH.y, _pressure) \
		* randf_range(1.0 - HURT_PITCH_SPREAD, 1.0 + HURT_PITCH_SPREAD)
	AudioManager.play_networked_3d("rat_hurt", _rat.global_position, -5.0, pitch, _rat)

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
	_hits = 0
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
	_hits = 0
	_effort = 1.0
	_claim_time = 0.0
	if killed:
		rat.die_in_hands(DEATH_TYPE)
		# The rat is dead but it is not gone yet: the fist closes the rest of the
		# way on it and it comes apart. The arm is told to hold the grip for
		# exactly that long — see `bursting`.
		#
		# The count comes off the rat, which is the one that knows how long its
		# own body takes to give. Asked for rather than reached for: these hands
		# do not know what a rat is beyond what it answers, and a weapon that
		# read another script's constants would break the day something else
		# could be strangled.
		var windup: float = rat.BURST_WINDUP if "BURST_WINDUP" in rat else 0.0
		bursting.emit(windup)
		# The rat died mid-hammering and more clicks are still coming in behind:
		# without this pause they would grab the next rat without the player
		# meaning to. It lasts the whole of the burst rather than the usual
		# cadence — a grab landing inside it would open the fist on an animal
		# that is still in it.
		start_cooldown(windup + BURST_RECOVERY)
	else:
		# It got away precisely because nobody was clicking; there is nothing to
		# hold on to.
		rat.escape()
	pressure_changed.emit(0.0)
	finished.emit(killed)
