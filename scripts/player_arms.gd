class_name PlayerArms
extends SkeletonModifier3D
## The arms of a man holding something, laid over whatever his legs are doing.
##
## It exists because `models/hazmat.glb` has five animations — `Idle`,
## `Running`, `Jump`, `CrouchIdle`, `CrouchedWalking` — and none of them is a
## man holding a rat. Until this file, `PlayerModel` borrowed `Idle` for it
## (`ANIMATIONS`), and the result is the thing this was written to fix: on
## everybody else's screen a player strangling an animal stood perfectly still
## with his arms at his sides while a rat floated in the air beside him. The
## whole of the killing — a dozen squeezes over several seconds, the most
## deliberate thing anyone does in a hunt — was invisible from outside.
##
## The fix is not a sixth animation. It is a *layer*: the legs go on playing
## whatever they were playing, and the arms are posed on top of it, aimed at the
## point where the rat is drawn. That is the right shape for two reasons beyond
## the missing art. A man carrying a rat can walk, and one clip could only ever
## show him walking at one speed — borrowing `Idle` is why he used to slide
## across the floor with his feet nailed down. And the animal is held at a point
## the body computes, so hands that *aim* stay on it when the chest moves,
## which a baked pose could not do.
##
## ## Everything is derived from the skeleton
##
## There is not one hand-written Euler angle in this file, and that is
## deliberate rather than fastidious. `mixamorig_` bones have local axes nobody
## can predict from the outside — the same visible bend is a different
## rotation on the upper arm and on the forearm — so a file full of tuned angles
## is a file that has to be re-tuned the day the model is swapped, by somebody
## reading numbers that mean nothing on their own.
##
## Instead every bone is *aimed*: `_aim` turns a bone so that the direction of
## its own child lands on a point, whatever local axes it happens to have. And
## the points are worked out from the body's own measurements — where the
## shoulders are, how long the arms are, where the chest is — so the pose is
## the same pose on a taller model or a differently rigged one.
##
## Which way the body faces is derived too, from a fact no rig can get wrong: a
## man's left shoulder is on his left, and his head is above his hips. Those two
## give `_side` and `_up`, and their cross product gives `_forward`. See
## `_measure`.
##
## ## What makes it look alive
##
## Three things, and none of them is the pose itself:
##
## - **The rat fights.** `STRUGGLE_*` puts a small, slow wander on the point the
##   hands are aimed at. It is what stops a held rat reading as a prop glued to
##   a mannequin — the man is visibly having to keep hold of something.
## - **Each squeeze shows.** `squeeze()` is called once per click, on every
##   machine, and pulls the hands together and in for a fifth of a second. It is
##   the only part of the strangling with a *rhythm*, and the rhythm is the
##   information: a watcher can see the difference between a player hammering at
##   an animal about to die and one who has stopped and is about to lose it.
## - **He looks at it.** The neck and the chest lean a fraction of the way
##   towards the same point. A body that holds something at arm's length while
##   staring past it reads as a mannequin holding a prop, and the fix is small
##   — a third of the way, not the whole way, or he folds over it.
##
## ## Where it is used
##
## `PlayerModel` puts one of these under the imported skeleton and drives it, so
## it is the same layer on the player's own shadow and on every avatar watching
## him. Nothing outside `PlayerModel` refers to this class.

## Bone names, in the one place that knows them.
##
## They are Mixamo's, with one change nobody made on purpose: the glb calls them
## `mixamorig:Hips` and Godot's importer calls them `mixamorig_Hips`, because a
## colon is not allowed in a name it might have to put in a `NodePath`. Nothing
## in `models/hazmat.glb.import` says so and nothing warns about it — the names
## simply do not match, `find_bone` returns -1 for every one of them, and the
## whole layer stands down quietly. Read them out of a live skeleton with
## `Skeleton3D.get_concatenated_bone_names()` rather than out of the model file.
const UPPER_ARM: Array[StringName] = [&"mixamorig_LeftArm", &"mixamorig_RightArm"]
const FOREARM: Array[StringName] = [&"mixamorig_LeftForeArm", &"mixamorig_RightForeArm"]
const HAND: Array[StringName] = [&"mixamorig_LeftHand", &"mixamorig_RightHand"]
const FINGER: Array[StringName] = [&"mixamorig_LeftHandIndex1", &"mixamorig_RightHandIndex1"]
const SHOULDER: Array[StringName] = [&"mixamorig_LeftShoulder", &"mixamorig_RightShoulder"]
const CHEST := &"mixamorig_Spine2"
const NECK := &"mixamorig_Neck"
const HEAD := &"mixamorig_Head"
const HIPS := &"mixamorig_Hips"

## Which of the two entries in the arrays above is which, and which way that
## side lies along `_side`. The left arm is the one `_side` points at.
const SIDES: Array[float] = [1.0, -1.0]

## How long the arms take to come up, and to go back down.
##
## Up is quicker than down because the two moments are not the same moment. The
## grab is a snatch — the animal is torn off the floor and is in his hands
## within a fifth of a second (`rat.gd`), and arms that took longer than the rat
## did would be reaching for something already held. Letting go is the end of
## the business and has nothing chasing it, so it settles instead of snapping,
## the same reasoning as `Hands.RISE_TIME`.
const RAISE_TIME := 0.16
const LOWER_TIME := 0.30

# --- Where the hands go -----------------------------------------------------
# All of it in multiples of the body's own measurements, so that the pose
# survives a model of a different size. `_measure` takes them off the rest
# skeleton once.

## How far in front of the chest the rat is held, as a fraction of the length of
## one arm (shoulder joint to elbow to wrist, along the bones).
##
## Near enough a whole arm, and the fraction is the whole point of expressing it
## this way: it is close enough to the limit that the elbows are only softly bent
## — a man holding something away from himself, which is what strangling looks
## like — and far enough from it that they never lock straight. Straight arms
## are the failure this number guards against, and they read as a zombie rather
## than as a man doing something difficult.
##
## It is measured from the *chest bone*, which sits well behind and below the
## shoulder joints, so a number close to one arm's length does not mean an arm
## stretched out: at this the elbows sit at about 110°, which is a firm hold
## rather than a reach. It was 0.78 first, and at that the hands came back
## against his ribs and folded the elbows past 70° — the pose of a man cradling
## something, not one throttling it.
const REACH := 0.98
## How far above the chest bone the hands are held, again in arm lengths. A
## little up, because the chest bone sits at the bottom of the sternum and hands
## in front of the *middle* of the chest is what a grip at neck height looks
## like from outside.
const LIFT := 0.00
## Half the gap between the two hands, in arm lengths. They are on either side
## of one neck, so it is small — but not nothing, or the two fists interpenetrate
## and read as one lump.
##
## What lands on screen is wider than what is asked for here, and knowingly so.
## The forearm is *aimed* at this point rather than solved onto it, so a hand
## whose elbow is nearer than the bone is long carries past it — the two fists
## end up about a rat's width apart from a target half that. The animal is
## between them, which is what the number is for; see `_test_arms.gd:
## GRIP_REACH`.
const SPREAD := 0.13

## Which way the elbow is sent, as an offset from the shoulder in arm lengths.
## Out and down, which is where an elbow goes on a man holding something in front
## of him — and the pair of them is what tells this pose apart from arms held
## stiffly forward.
##
## It is a *direction* and not a place: `_pose_arm` solves where the elbow has
## to be for the hand to land on the animal, and all these two decide is which
## way round the arm bends to get there. So they can be read as a preference —
## elbows out, elbows down — rather than as a measurement, and getting them
## slightly wrong tilts the bend rather than moving the fist.
const ELBOW_FLARE := 0.55
const ELBOW_DROP := 0.75

## How far the collarbones turn towards the rat, of the whole way.
##
## A man reaching forward brings his shoulders with him, so it is worth having
## for its own sake — but what it is really here for is evenness. The idle clip
## does not stand square: it leaves one shoulder the better part of a hand's
## breadth ahead of the other, which nobody notices on a body with its arms
## down and which put one elbow at 113° and the other locked straight the moment
## they were both asked to reach the same point. Turning both towards the animal
## takes most of that difference out before the arms are solved.
const SHOULDER_TURN := 0.45

## How much of its own length an arm may be asked to span, at most.
##
## The safety net under `REACH`, and it is a net rather than a belt: `REACH` is
## measured from the chest and says how far out the animal is held, which is a
## decision about the pose; this is measured from each shoulder joint separately
## and says how far that particular arm is being asked to stretch, which is a
## fact about the body. When the second exceeds this the held point is brought
## in until it does not — both hands together, so the rat stays between them.
##
## Nine tenths, because an arm at ten tenths is a straight line and reads as a
## zombie's. What it costs is that a man whose idle happens to stand crookedly
## holds the animal a couple of centimetres nearer than `REACH` asked for, which
## nobody will ever see.
const MAX_EXTENSION := 0.90

## How far the chest and the neck turn towards the rat, of the whole way.
##
## Fractions and not angles, and small ones. Aimed the whole way, the neck bone
## puts the man's face on the animal — which is not attention, it is a headbutt
## — and the chest folds him double. A third is the amount at which he is
## plainly looking at what he is doing and still standing up straight.
const CHEST_TURN := 0.10
const NECK_TURN := 0.22
## How far the wrists turn to face each other, of the whole way. Nearly all of
## it: the hands are on either side of a neck and they point inwards at it, and
## this is the difference between two fists and two hands holding something.
const WRIST_TURN := 0.75

# --- The animal fighting ----------------------------------------------------

## How far the held point wanders, in arm lengths, and how fast.
##
## It is not a jitter and must not become one. A rat being strangled is heavy
## and slow and pulls in long arcs, so this is a slow wander of about two
## centimetres on a man-sized body — visible as effort, never as a shake. Two
## frequencies that do not divide into each other, so it never falls into a
## loop the eye can learn.
const STRUGGLE_SWING := 0.055
const STRUGGLE_RATE := Vector2(1.7, 2.3)

# --- One squeeze ------------------------------------------------------------

## How long a squeeze takes, and how it is shaped: in fast, out slow. The clench
## is the gesture, the release is only getting back to where the next one starts
## from.
const SQUEEZE_TIME := 0.22
const SQUEEZE_ATTACK := 0.3

## How far the hands come together and towards the body at the peak of a
## squeeze, in arm lengths, and how much further the chest leans into it.
##
## The pull towards each other is the one that reads: it is the fists closing on
## the neck. Coming in towards the body is small on purpose — a man does not
## reel the animal in every time he squeezes, he tightens on it where it is.
const SQUEEZE_CLOSE := 0.07
const SQUEEZE_PULL := 0.05
const SQUEEZE_LEAN := 0.35

## What the arms are being asked to do. Set by `PlayerModel`, and the only
## input this file has besides `squeeze()`.
var holding := false

## How much of the pose is in, from 0 to 1. It eases rather than switching, and
## it is also the answer to "is there anything to do this frame" — at zero the
## bones are left exactly as the animation left them, which is what makes this
## free for the ninety-nine per cent of the time nobody is holding anything.
var _weight := 0.0
## How far into the current squeeze, in seconds, or past `SQUEEZE_TIME` when
## there is none going on.
var _squeeze_time := SQUEEZE_TIME
## The clock the struggle is read off. Its own, rather than the engine's, so
## that two bodies raised in the same frame do not wander in step.
var _struggle_time := randf() * TAU
## The point the hands were aimed at this frame, in skeleton space.
##
## Kept rather than worked out again on demand, and that is not only thrift. It
## is computed off the chest *before* the lean is applied to it, so asking again
## afterwards would get a different answer — one that moved every time the man
## leaned further into a squeeze, dragging the rat with it. What is remembered
## here is the point the arms actually went to.
var _centre := Vector3.ZERO

## The body's own measurements, taken once off the rest skeleton. Zero until
## `_measure` has run, which is what `_ready_bones` guards on.
var _up := Vector3.UP
var _forward := Vector3.FORWARD
var _side := Vector3.LEFT
var _upper_length := 0.0
var _fore_length := 0.0
var _arm_length := 0.0

## Bone indices, looked up once. `-1` in any of them means this is not a
## skeleton we know how to pose, and the whole modifier stands down rather than
## posing half a man.
var _upper_arm: Array[int] = [-1, -1]
var _forearm: Array[int] = [-1, -1]
var _hand: Array[int] = [-1, -1]
var _finger: Array[int] = [-1, -1]
var _shoulder: Array[int] = [-1, -1]
var _chest := -1
var _neck := -1
var _head := -1
var _hips := -1
## Set once the bones are found and the body is measured. False leaves every
## bone alone for good — see `_measure`.
var _ready_bones := false


func _ready() -> void:
	_measure()


## One click of the strangling. Called on every machine that can see this body,
## at the moment the click landed on the machine that made it — see
## `PlayerAvatar.act`.
##
## Restarting rather than adding: hammering faster is a faster rhythm, not a
## deeper clench. A squeeze that accumulated would leave a fast hammerer with
## his hands buried in the animal's neck.
func squeeze() -> void:
	_squeeze_time = 0.0


## Where the hands are, in the skeleton's own space, with the struggle and any
## squeeze already in it.
##
## It is public because the rat has to hang where the hands are: `PlayerAvatar`
## moves its `CapturePoint` onto this every frame, so the animal is *in* the
## grip rather than near it. That is a thing worth stating plainly, because it
## is the difference between this working and this being decoration — an arm
## posed at a rat that is drawn somewhere else is a worse picture than no arm at
## all.
##
## Answered even with the arms down, and worked out every frame whether they are
## up or not: the point is "where this body *would* hold something", and
## something being carried has to be somewhere during the fifth of a second the
## arms are still on their way up. It is set from the rest skeleton on the way in
## (`_measure`) so that it is an answer from the first frame rather than the
## second.
func grip_point() -> Vector3:
	return _centre


## The pose. Runs after the animation has been written into the skeleton and
## before the mesh is skinned to it, which is the whole reason this is a
## `SkeletonModifier3D` and not something reaching in from `_process`: bones set
## from outside that ordering are overwritten by the next animation frame, and
## the symptom is a pose that flickers at some frame rates and not others.
func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or not _ready_bones:
		return

	_weight = move_toward(
		_weight, 1.0 if holding else 0.0,
		delta / (RAISE_TIME if holding else LOWER_TIME)
	)
	_struggle_time += delta
	_squeeze_time = minf(_squeeze_time + delta, SQUEEZE_TIME)

	# The chest as the animation left it, and the point in front of it. Both are
	# wanted even with the arms down — `grip_point` is answered from the second
	# one, and something being carried has to hang somewhere during the fifth of
	# a second the arms are still coming up.
	var above := skeleton.get_bone_global_pose(skeleton.get_bone_parent(_chest))
	var chest := above * skeleton.get_bone_pose(_chest)
	_centre = _grip_centre(chest.origin)

	# Nothing in hand and nothing left over from the last thing: the animation
	# owns the arms, untouched.
	if _weight <= 0.0:
		return

	var squeeze := _squeeze()
	# Root to tip, and the order is not a preference: every one of these hangs
	# off the last, so the chest has to have leaned before the collarbones turn
	# on it and the collarbones before the arms are solved off them.
	var lean := _weight * (1.0 + squeeze * SQUEEZE_LEAN)
	chest = _aim(skeleton, _chest, _neck, above, _centre, CHEST_TURN * lean)
	_aim(skeleton, _neck, _head, chest, _centre, NECK_TURN * lean)

	var clavicle: Array[Transform3D] = []
	for side in 2:
		clavicle.append(_aim(
			skeleton, _shoulder[side], _upper_arm[side], chest, _centre,
			SHOULDER_TURN * _weight
		))
	# Only now can the reach be checked, because only now is it known where the
	# shoulders ended up. If either arm is being asked for more than it has, the
	# animal comes in towards him — both hands together, so it stays in the grip.
	_centre = _within_reach(skeleton, clavicle, _centre, squeeze)

	for side in 2:
		_pose_arm(skeleton, side, clavicle[side], _centre, squeeze)


## One arm: upper to elbow, forearm to hand, wrist to the middle.
##
## The elbow is *solved* and not merely placed, and the difference is the whole
## reason the hands are on the animal rather than near it. Aiming the upper arm
## at a guessed elbow and the forearm at the target only works when the guessed
## elbow happens to sit exactly one forearm from the target; every other guess
## leaves the wrist short of it or carried past it, and the error is worst on
## precisely the pose that is wanted — a softly bent arm, where a centimetre of
## elbow is several of fist. Guessed, the two fists sat a third of a metre from
## a rat they were supposed to be strangling.
##
## What is solved is the ordinary two-bone problem: given a shoulder, a target,
## and two bone lengths, there is a circle of elbows that reach both, and the
## pole picks which one. So `ELBOW_FLARE` and `ELBOW_DROP` stop being a place
## the elbow has to be and become the direction it leans — which is what they
## were always for, and is now all they can get wrong.
func _pose_arm(skeleton: Skeleton3D, side: int, shoulder: Transform3D, centre: Vector3,
		squeeze: float) -> void:
	var sign_: float = SIDES[side]
	var hand := _hand_target(centre, side, squeeze)
	var joint := (shoulder * skeleton.get_bone_pose(_upper_arm[side])).origin
	var pole := joint + _side * (sign_ * ELBOW_FLARE * _arm_length) \
		- _up * (ELBOW_DROP * _arm_length)
	var elbow := _solve_elbow(joint, hand, pole)

	var upper := _aim(skeleton, _upper_arm[side], _forearm[side], shoulder, elbow, _weight)
	var fore := _aim(skeleton, _forearm[side], _hand[side], upper, hand, _weight)
	# The fingers point at the middle, which is where the neck is. Aiming them
	# at the hand's own target would be aiming them at themselves; aiming them
	# across is what turns two fists into two hands holding something.
	_aim(skeleton, _hand[side], _finger[side], fore, centre, WRIST_TURN * _weight)


## Where one fist is going, in skeleton space: off to its own side of the held
## point, and closing on it while he squeezes.
##
## The closing is the part of the gesture that reads from across a room, and the
## small pull towards the body is deliberately smaller — a man does not reel the
## animal in every time he tightens, he tightens on it where it is.
func _hand_target(centre: Vector3, side: int, squeeze: float) -> Vector3:
	var sign_: float = SIDES[side]
	var spread := SPREAD - SQUEEZE_CLOSE * squeeze
	return centre + _side * (sign_ * spread * _arm_length) \
		- _forward * (SQUEEZE_PULL * squeeze * _arm_length)


## The held point, brought in far enough that neither arm is stretched past
## `MAX_EXTENSION`.
##
## Both hands move together and along the body's own forward, so the animal
## stays square in front of him and stays between the two fists — which is the
## whole reason this is done here, on the point, rather than by each arm quietly
## giving up on its own target. One pass and no iteration: the pull is along
## `_forward` and the arm is not, so it takes out a little less than it is asked
## to, and `_solve_elbow` clamps whatever is left. The difference is a degree or
## two of elbow.
func _within_reach(skeleton: Skeleton3D, clavicle: Array[Transform3D], centre: Vector3,
		squeeze: float) -> Vector3:
	var limit := MAX_EXTENSION * _arm_length
	var over := 0.0
	for side in 2:
		var joint := (clavicle[side] * skeleton.get_bone_pose(_upper_arm[side])).origin
		over = maxf(over, joint.distance_to(_hand_target(centre, side, squeeze)) - limit)
	if over <= 0.0:
		return centre
	return centre - _forward * over


## Where the elbow has to be for a hand at `joint` to reach `target`, leaning
## the way `pole` says.
##
## The two bones and the straight line from shoulder to target make a triangle
## whose sides are all known, so the angle at the shoulder is the law of cosines
## and nothing more. That fixes the elbow to a circle around the shoulder-to-
## target line; `pole` picks the point on it, by giving the one direction
## perpendicular to that line which the arm should bend towards.
##
## A target further off than the arm is long has no triangle, and a target
## almost inside the shoulder has one that folds the arm through itself. Both
## are clamped rather than refused: the arm straightens at the far end and stops
## short at the near one, which is what a real arm does and is a great deal
## better than a frame in which it disappears.
func _solve_elbow(joint: Vector3, target: Vector3, pole: Vector3) -> Vector3:
	var upper := _upper_length
	var fore := _fore_length
	var to := target - joint
	var reach := clampf(to.length(), absf(upper - fore) + 0.001, upper + fore - 0.001)
	if to.length_squared() < 0.000001:
		return joint
	var along := to.normalized()
	# How far off that line the elbow leans. Whatever component of the pole
	# points along the line says nothing about the bend and is taken out; what is
	# left is the plane the arm folds in.
	var lean := pole - joint
	lean -= along * along.dot(lean)
	if lean.length_squared() < 0.000001:
		# The pole is straight down the arm and picks nothing. Any perpendicular
		# will do rather than none — a body with one arm frozen mid-blend is a
		# worse answer than one whose elbow went somewhere arbitrary for a frame.
		lean = _up - along * along.dot(_up)
		if lean.length_squared() < 0.000001:
			lean = _side - along * along.dot(_side)
	var angle := acos(clampf(
		(upper * upper + reach * reach - fore * fore) / (2.0 * upper * reach), -1.0, 1.0
	))
	return joint + along * (upper * cos(angle)) \
		+ lean.normalized() * (upper * sin(angle))


## The point both hands are working at, in skeleton space: out in front of the
## chest, wandering with whatever the animal is doing.
func _grip_centre(chest: Vector3) -> Vector3:
	# Off the chest bone as the animation left it, so the hands ride the body:
	# he crouches and the rat comes down with him, he breathes and it breathes.
	var centre := chest + _forward * (REACH * _arm_length) + _up * (LIFT * _arm_length)
	# The animal pulling. Only while the hands are actually up — a struggle
	# drawn at full strength under arms that are still on their way up would
	# have the rat fighting a man who has not got hold of it yet.
	var swing := STRUGGLE_SWING * _arm_length * _weight
	return centre \
		+ _side * (sin(_struggle_time * STRUGGLE_RATE.x) * swing) \
		+ _up * (sin(_struggle_time * STRUGGLE_RATE.y) * swing)


## How far into a squeeze we are, from 0 through 1 and back. Fast in, slow out:
## the clench is the gesture and the release is only the way back to the start
## of the next one.
func _squeeze() -> float:
	if _squeeze_time >= SQUEEZE_TIME:
		return 0.0
	var fraction := _squeeze_time / SQUEEZE_TIME
	if fraction < SQUEEZE_ATTACK:
		return ease(fraction / SQUEEZE_ATTACK, 0.6)
	return ease(1.0 - (fraction - SQUEEZE_ATTACK) / (1.0 - SQUEEZE_ATTACK), 2.0)


## Turns one bone so that the direction of `tip` — its own child — points at
## `target`, blends `amount` of the way there from what the animation was doing,
## and hands back where the bone ended up.
##
## The bone's own idea of "along itself" is read from where its child rests
## rather than assumed to be some axis, which is what makes this work on a rig
## whose axes nobody here has looked at. The turn is then the shortest arc from
## where that direction currently points to where it should, applied on the
## *left* of the bone's global basis: rotating in global space and converting
## back means the bone's own roll survives, so an arm being aimed still has the
## twist the animation gave it.
##
## ## The parent is handed in, and the answer handed back
##
## Which looks like ceremony and is the difference between this working and not.
## Asking the skeleton for a global pose inside a modification pass gets the one
## it had when the pass began — the bones written a line ago are not in it. Aim
## the upper arm off that and the forearm reads a shoulder that has not moved,
## turns to suit it, and then finds itself hanging off an arm that *has*: the
## fist ends up a hand's breadth from the animal and half a metre below it,
## which is what the bench measured before the chain was threaded by hand.
##
## So each call is given its parent's real global pose and returns its own, and
## the caller walks root to tip passing them along. Nothing is asked of the
## skeleton that it might answer out of date.
##
## Everything is in the skeleton's space, and `target` has to be too.
func _aim(skeleton: Skeleton3D, bone: int, tip: int, parent: Transform3D, target: Vector3,
		amount: float) -> Transform3D:
	var pose := skeleton.get_bone_pose(bone)
	var here := parent * pose
	var along := skeleton.get_bone_rest(tip).origin
	var to := target - here.origin
	if amount <= 0.0 or along.length_squared() < 0.000001 \
			or to.length_squared() < 0.000001:
		return here

	var from := (here.basis * along).normalized()
	var aimed := Basis(Quaternion(from, to.normalized())) * here.basis
	var wanted := Quaternion((parent.basis.inverse() * aimed).orthonormalized())
	var turned := pose.basis.get_rotation_quaternion().slerp(
		wanted, clampf(amount, 0.0, 1.0)
	)
	skeleton.set_bone_pose_rotation(bone, turned)
	# Rebuilt with the rotation that was actually written, in the order the
	# skeleton composes a pose in — rotation first, then scale on the right
	# (`Basis.set_quaternion_scale`). Getting that backwards is invisible on this
	# model, whose bones are all at scale one, and wrong on the first one that
	# is not.
	return parent * Transform3D(
		Basis(turned) * Basis.from_scale(pose.basis.get_scale()), pose.origin
	)


## The body's own axes and its arm's own length, off the rest skeleton, once.
##
## Which way a man faces cannot be read off a bone basis with any confidence —
## every exporter has its own opinion — so it is read off his shape instead,
## from two facts that hold for any rig anybody would call a humanoid: his left
## shoulder is on his left, and his head is above his hips. `_side` and `_up`
## come straight from those, and `_forward` is their cross product, which comes
## out right whichever way the model was authored.
##
## `_arm_length` is shoulder to wrist along the rest pose, and every distance in
## this file is a multiple of it. That is what lets the numbers up top be read
## as proportions of a body rather than as centimetres that happen to suit this
## one model.
func _measure() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	for side in 2:
		_upper_arm[side] = skeleton.find_bone(UPPER_ARM[side])
		_forearm[side] = skeleton.find_bone(FOREARM[side])
		_hand[side] = skeleton.find_bone(HAND[side])
		_finger[side] = skeleton.find_bone(FINGER[side])
		_shoulder[side] = skeleton.find_bone(SHOULDER[side])
	_chest = skeleton.find_bone(CHEST)
	_neck = skeleton.find_bone(NECK)
	_head = skeleton.find_bone(HEAD)
	_hips = skeleton.find_bone(HIPS)

	var wanted: Array[int] = [_chest, _neck, _head, _hips]
	wanted.append_array(_upper_arm)
	wanted.append_array(_forearm)
	wanted.append_array(_hand)
	wanted.append_array(_finger)
	wanted.append_array(_shoulder)
	for bone in wanted:
		if bone < 0:
			push_warning("PlayerArms: the skeleton is not the one this was written for")
			return

	var left := skeleton.get_bone_global_rest(_shoulder[0]).origin
	var right := skeleton.get_bone_global_rest(_shoulder[1]).origin
	var head := skeleton.get_bone_global_rest(_head).origin
	var hips := skeleton.get_bone_global_rest(_hips).origin
	if left.is_equal_approx(right) or head.is_equal_approx(hips):
		push_warning("PlayerArms: the skeleton has no width or no height")
		return
	_side = (left - right).normalized()
	_up = (head - hips).normalized()
	# Squared off against each other before the third is taken, so that a rig
	# whose shoulders are not perfectly level does not come out with a forward
	# that tilts.
	_side = (_side - _up * _side.dot(_up)).normalized()
	_forward = _side.cross(_up).normalized()

	# The two bones separately, because the solver needs both, and their sum as
	# the arm's length — the straight line from the clavicle to the hand is a
	# quarter longer, since the collarbone never takes part in the reach, and
	# using it put the held point further out than the hand could go.
	_upper_length = skeleton.get_bone_global_rest(_upper_arm[0]).origin.distance_to(
		skeleton.get_bone_global_rest(_forearm[0]).origin)
	_fore_length = skeleton.get_bone_global_rest(_forearm[0]).origin.distance_to(
		skeleton.get_bone_global_rest(_hand[0]).origin)
	_arm_length = _upper_length + _fore_length
	# A point from the rest pose, so that anything asking before the first
	# modification pass — the avatar hangs a rat off `grip_point` in its own
	# `_process`, which may well run first — is answered with a place on this
	# body rather than with the floor under it.
	_centre = _grip_centre(skeleton.get_bone_global_rest(_chest).origin)
	if _arm_length <= 0.0:
		push_warning("PlayerArms: the arms have no length")
		return
	_ready_bones = true
