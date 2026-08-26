class_name ViewModelArmsPose
extends SkeletonModifier3D
## Bends the arms of the player's own copy of the body up into the frame.
##
## The hazmat model is animated for the third person, and every one of its five
## animations is a Mixamo full-body clip with the arms hanging at the sides —
## measured from the head bone, both hands sit below and behind it in all of
## them. That is right for a man seen across a room and useless for a man seen
## from inside his own eyes: no amount of moving the camera brings a hand that is
## behind the head into the frame in front of it.
##
## So the arms are bent here, after the animation has had its say. It is a
## `SkeletonModifier3D`, which is exactly the hook for that: Godot runs it as
## part of the skeleton's own update, once the `AnimationPlayer` has written its
## pose, and whatever this writes on top is what gets skinned. Nothing is fought
## over and nothing has to be re-applied per frame by hand.
##
## **It runs on the view model alone.** The body in the world — the one that
## casts the player's shadow and the one his colleagues see — has no modifier on
## it and is animated exactly as it was. A player waving in the first person is
## still a player with his arms at his sides in the third, and closing that gap
## is a job for animation rather than for this file.
##
## ## What it is and is not
##
## It is a stand-in, and it is written to be thrown away. The day `hazmat.glb`
## carries first-person clips — hands idling, a trap going down, a swing — the
## right thing is to play them and delete this: the offsets below would then be
## fighting an animation that already knows where the hands go. Until that day
## it is what puts hands on screen at all, and everything built on top of it
## (`scripts/weapons/`) works the same either way, because none of it knows the
## arms are posed rather than animated.
##
## ## How the angles are applied
##
## Added to the animated pose rather than replacing it. That is the difference
## between arms that are held up and arms that are *frozen* up: the walk still
## swings them, the crouch still drops them, the jump still throws them — all of
## it just happens around a new resting place. Replacing the rotation outright
## would have cost every one of those for nothing.
##
## What the animation is allowed to move them by is damped first, though, and
## `animation_influence` is where that is argued: a third-person clip swings the
## arms across the body, and across the body is where the other hand is.
##
## The rig is Mixamo's, so each bone points down its own local +Y and the
## rotations mean what they read as: `x` bends the elbow and lifts the arm
## forward, `y` twists along the bone, `z` swings it in and out from the body.

## The bones bent, and by how much, in degrees, added to whatever the animation
## put there.
##
## Left and right are separate rather than mirrored, and that is not a
## convenience: **they are not mirrors of each other**. The two shoulders come out
## of the exporter on different rest orientations, so the same angles on both
## sides put one hand in the middle of the frame and the other out past its edge
## — which is what the first attempt at this did. The numbers below were found by
## sweeping each arm on its own against where its hand lands on screen, which is
## what puts a hand in each bottom corner of the frame rather than both in one.
##
## It suits the game anyway: the two hands do not do the same job — a rat is held
## in one and a trap set with the other — and a mirror would have to be undone
## the first time they part.
##
## They were found by searching all four bones against where the hands land on
## the *screen* — projected through a camera set up as `player.tscn` has it,
## over every frame of all five clips — and the screen is the thing to measure,
## which was learnt the hard way. An earlier pass at this scored the distance
## between the two hand bones in metres, got it from 17 centimetres to 33, and
## changed almost nothing about the picture: most of that distance was one hand
## being *above* the other rather than beside it, and it is only the sideways gap
## that stops them overlapping in the frame. In screen widths that gap was 0.015
## before and 0.29 after, and the second number is the one worth keeping.
##
## The search settles in the same place from most starting poses, which is worth
## knowing before anybody sweeps these by hand again: the angles alone cannot
## bring the hands much past a quarter of the frame apart. What buys the rest is
## `PlayerViewModel.offset.x`, and the reasoning for it lives there.
@export_group("Right arm")
@export var right_shoulder := Vector3(0.0, 0.0, 0.0):
	set(value):
		right_shoulder = value
		_dirty = true
@export var right_arm := Vector3(-45.0, -25.0, -78.0):
	set(value):
		right_arm = value
		_dirty = true
@export var right_forearm := Vector3(-120.0, -40.0, -10.0):
	set(value):
		right_forearm = value
		_dirty = true
@export var right_hand := Vector3(0.0, 0.0, 0.0):
	set(value):
		right_hand = value
		_dirty = true

@export_group("Left arm")
@export var left_shoulder := Vector3(0.0, 0.0, 0.0):
	set(value):
		left_shoulder = value
		_dirty = true
@export var left_arm := Vector3(-25.0, 35.0, 38.0):
	set(value):
		left_arm = value
		_dirty = true
@export var left_forearm := Vector3(-70.0, -20.0, 0.0):
	set(value):
		left_forearm = value
		_dirty = true
@export var left_hand := Vector3(0.0, 0.0, 0.0):
	set(value):
		left_hand = value
		_dirty = true

@export_group("")
## How much of the animation's own arm movement survives, from 0 for arms held
## entirely by the angles above to 1 for arms carried wherever the clip puts
## them.
##
## It exists because the clips are third-person, and a third-person clip moves
## the arms *towards the body's midline* — the crouch folds the man over his own
## knees, the jump throws both arms in, `Running` swings them past each other.
## Seen from across the room that is a man moving. Seen from inside his own head
## the two hands are a forearm's length apart to begin with, so the same
## movement drives them straight through one another, and it is worst in exactly
## the three states the player spends his time in: crouching, crouch-walking and
## airborne.
##
## Damping it is the fix that keeps everything else. The arms still move with the
## clip — the walk still swings them, the jump still throws them — but around a
## quarter of the distance, which is under the gap between the hands. Clamping
## the hands apart afterwards, or nudging the rig sideways per state, would both
## have meant a second thing deciding where the arms are, disagreeing with this
## one by a frame.
##
## A quarter is where the swing is still legible and the fingers no longer meet.
## Zero would be a pair of hands welded to the screen, one a return to the
## crossing hands, and the day there are first-person clips this file goes and
## the question with it.
@export_range(0.0, 1.0, 0.01) var animation_influence := 0.25

## How much of the pose is applied, from nothing to all of it. It is a knob for
## blending the arms down out of the frame — a cutscene, a screen taking the
## player over — and, more usefully today, for a bench that wants to measure the
## animated pose and the posed one against each other.
@export_range(0.0, 1.0, 0.01) var amount := 1.0:
	set(value):
		amount = value
		_dirty = true

## The bones this poses, looked up once. Empty until the skeleton is known — a
## modifier is built before it is parented, and `find_bone` on nothing returns
## -1 for everything.
var _bones: Dictionary[int, Quaternion] = {}
## An angle changed: the lookup has to be rebuilt before the next update. It is
## a flag rather than a rebuild in the setter because the setters run in the
## editor, on a node with no skeleton over it yet.
var _dirty := true
## Bench hook, called with the skeleton once the bend is on it.
##
## It exists because there is no reading this pose from outside. A modifier
## writes into the buffer the skin is built from, and `get_bone_global_pose`
## asked from another node hands back the pose the `AnimationPlayer` left — the
## arms as they hang, not the arms as they are drawn. A bench that measured that
## would report the hands out of frame while the player could plainly see them.
## Inside the update, and only there, the reading is the one that is drawn.
var probed := Callable()
## What this file wrote onto each bone last time round, and the whole difference
## it made to write it — the damping as well as the bend — kept so that both can
## be taken back off before the next pass goes on. See `_animated_rotation`.
var _written: Dictionary[int, Quaternion] = {}
var _applied: Dictionary[int, Quaternion] = {}


## Godot's hook: the animation has written its pose and this is the chance to
## write on top of it.
##
## The engine offers two of these — this one and
## `_process_modification_with_delta`, which is handed the frame. The frame is of
## no use to a pose that is the same every time it is asked for, so this is the
## one overridden, and taking the wrong one is a mistake that shows up as an
## arms-at-the-sides view model with no error printed anywhere: an override whose
## signature does not match is simply never called.
func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _dirty:
		_rebuild(skeleton)
	if is_zero_approx(amount):
		return
	for bone in _bones:
		var offset: Quaternion = _bones[bone]
		if amount < 1.0:
			offset = Quaternion.IDENTITY.slerp(offset, amount)
		# Composed onto the *animation's* pose and not onto whatever is on the
		# bone right now, and the difference is not a nicety: a modifier writes
		# into the same pose it reads from, so the second reading already contains
		# the first frame's bend. Bending that again, sixty times a second, winds
		# the arms round and round the shoulder within a second of the game
		# starting. `get_bone_pose_rotation` is that poisoned reading;
		# `_animated` is the one the `AnimationPlayer` wrote, kept below.
		#
		# Multiplied on the right, so the turn happens in the bone's own space: an
		# elbow bends about the elbow whichever way the shoulder has already swung
		# it. On the left it would be a turn in the parent's space, and the same
		# numbers would throw the arm somewhere different in every animation.
		#
		# The clip's own movement, pulled back towards the rest pose before the
		# bend goes on top of it. `animation_influence` says how much of it
		# survives; the rest pose is the anchor because it is what the bend's
		# angles were found against, so a damped arm settles onto the pose that
		# was measured rather than onto some average of five clips.
		var raw := _animated_rotation(skeleton, bone)
		var animated := raw
		if animation_influence < 1.0:
			animated = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() \
				.slerp(animated, animation_influence)
		var posed := animated * offset
		skeleton.set_bone_pose_rotation(bone, posed)
		_written[bone] = posed
		# The *whole* difference between what was read and what was written, the
		# damping included — not the bend alone. It is what `_animated_rotation`
		# takes back off, and taking off only the bend would leave a bone that
		# nobody animated damped again every frame, creeping towards its rest
		# pose a quarter of the way at a time.
		_applied[bone] = raw.inverse() * posed
	if probed.is_valid():
		probed.call(skeleton)


## The rotation the animation put on this bone, with last frame's bend taken
## back off if it is still there.
##
## A `SkeletonModifier3D` reads and writes one pose, so what is on a bone when
## this runs is whatever was last written to it — by the `AnimationPlayer` if the
## clip has a track for that bone, and by *this file* if it does not. The five
## hazmat clips do animate every arm bone, so in the game the first case is
## always the one that happens; the second is what a bench sees the moment it
## pauses the animation, and what the whole rig would do if a clip were ever
## added that leaves an arm alone. Bending an already-bent arm sixty times a
## second winds it round the shoulder inside of a second, and it would be a bug
## that only ever showed up in the animation somebody added last.
##
## Told apart by comparing against exactly what was written: a bone the animation
## has touched will not match to the last bit, and one it has not will match
## precisely, because nothing else wrote to it in between.
func _animated_rotation(skeleton: Skeleton3D, bone: int) -> Quaternion:
	var current := skeleton.get_bone_pose_rotation(bone)
	if not _written.has(bone):
		return current
	if current.is_equal_approx(_written[bone]):
		# Nobody has written since we did: what is here is our own bend, and the
		# animation's pose is what is left after taking it back off.
		return current * _applied[bone].inverse()
	return current


## The bone-by-bone lookup, from the names and the angles. Rebuilt whenever an
## angle changes, which in the game is never and in the editor is every time
## somebody drags a slider.
func _rebuild(skeleton: Skeleton3D) -> void:
	_dirty = false
	_bones.clear()
	# The record of what was written belongs to the angles that were in force at
	# the time. Keeping it across a change would have the next frame undoing an
	# old bend from a new pose.
	_written.clear()
	_applied.clear()
	var wanted := {
		&"mixamorig_RightShoulder": right_shoulder,
		&"mixamorig_RightArm": right_arm,
		&"mixamorig_RightForeArm": right_forearm,
		&"mixamorig_RightHand": right_hand,
		&"mixamorig_LeftShoulder": left_shoulder,
		&"mixamorig_LeftArm": left_arm,
		&"mixamorig_LeftForeArm": left_forearm,
		&"mixamorig_LeftHand": left_hand,
	}
	for bone_name: StringName in wanted:
		var angles: Vector3 = wanted[bone_name]
		if angles.is_zero_approx():
			continue
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			push_warning("ViewModelArmsPose: no bone named %s in this rig." % bone_name)
			continue
		_bones[bone] = Quaternion.from_euler(
			Vector3(deg_to_rad(angles.x), deg_to_rad(angles.y), deg_to_rad(angles.z))
		)
