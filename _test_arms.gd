extends SceneTree
## Arms bench: a man strangling a rat has to *look* like one from across the room.
##
## Run headless for the numbers:
##   godot --headless --script _test_arms.gd
## Run with a window to also get pictures of the body empty-handed, holding, and
## mid-squeeze — which is the part no assertion can judge:
##   godot --script _test_arms.gd
##
## The bug this was written for is the one a player photographed: he watched a
## teammate strangle a rat and saw a man standing perfectly still, arms at his
## sides, with an animal floating in the air beside him. Every part of that was
## a separate fault, and this bench is one check per fault:
##
## - **`HOLDING` played `Idle`.** `models/hazmat.glb` has no animation of a man
##   carrying anything, so the state borrowed the standing one — and because
##   `HOLDING` also beat every other answer in `player.gd: animation_state()`,
##   a player who walked off with a rat slid across the floor with his feet
##   nailed down. The legs and the hands are two questions now, and the checks
##   are that the legs still run while the hands are full, and that the arms
##   come up at all.
## - **The rat hung off a fixed point in the avatar's scene**, guessed at back
##   when there were no hands for it to hang off. It is on the grip now, and the
##   check is that the animal is between the two fists rather than near them.
## - **The squeezes never crossed the wire.** A dozen clicks over several
##   seconds, the most deliberate thing anybody does in a hunt, and not one
##   frame of it was visible from outside. The checks are that the action
##   arrives and that it visibly closes the hands.
##
## Everything is photographed through a real `player_avatar.tscn` following the
## real player, with its drawing half switched on — which is exactly the path a
## watcher's machine takes, run on one machine so a bench can see both ends of
## it. The rat is a real one from `rat.tscn`, grabbed by the real `Hands`, and
## then hung off the avatar's capture point the way a remote holder's catch is.

## Frames of slack between one step and the next.
const WAIT := 12
## Where the bench stands the player, on open floor.
const STATION := Vector3(0.0, 0.1, 4.0)
## How far in front of him the rat is put, so it is inside the hands' cone.
const RAT_AHEAD := 1.2
## Window size for the picture-taking run.
const SIZE := Vector2i(960, 720)

## Where the watching camera stands, in the body's own space: front and to his
## right, at chest height. It is roughly where the player in the photograph was
## standing, and the point of matching it is that the pose has to read from a
## normal angle rather than from the one it was tuned at.
const EYE := Vector3(0.85, 0.85, -1.70)
## And from square on his left, which is the angle a pose either survives or
## does not: a reach that is really a spread reads as a reach from the front and
## as a man being crucified from here.
const SIDE_EYE := Vector3(-1.85, 0.85, -0.35)

## How far a fist may sit from the point the rat hangs at, in metres, and still
## count as being on it.
##
## The two hands are on either side of one neck, so neither is *at* the point —
## `PlayerArms.SPREAD` puts each about six centimetres off it, and a rat is
## roughly twelve across the shoulders. This is that, with room for the animal's
## own kicking and for the solver's own slack on top.
const GRIP_REACH := 0.22

## How straight an elbow may be, in degrees, before the pose reads as a zombie
## rather than as a man holding something.
##
## It is the failure the whole approach risks. `PlayerArms.REACH` is most of the
## length of an arm, and pushing it any further locks both elbows — at which
## point the difference between this and no arms layer at all is that the arms
## are wrong in a new direction.
const MAX_ELBOW := 168.0
## And how bent it may be, at the other end. An elbow folded past this has the
## fist up by the shoulder, which is a man shielding his face.
const MIN_ELBOW := 55.0

## How far a wrist has to be in front of the chest to count as held out, and how
## far it has to have risen from where it hangs empty, both in metres. The two
## together are what says the arms actually changed rather than merely being
## somewhere plausible.
const HELD_AHEAD := 0.20
const RESTING_BELOW := 0.15

## How much further forward his head has to come once there is something in his
## hands, in degrees. Small: he is glancing down at it, not bowing to it.
const LOOK_LEAN := 4.0
## How near an empty hand has to settle to where an empty hand hangs, in metres,
## once the rat is gone.
const RETURNED := 0.06

## How much closer the fists have to come at the peak of a squeeze, in metres.
## Small on purpose — the gesture is a clench and not a clap — but it has to be
## more than the animal's own struggling moves them, or the check would pass on
## a body doing nothing.
const SQUEEZE_CLOSE := 0.02
## And how far the struggle alone moves a hand between two readings a few frames
## apart. Anything less and the pose is a mannequin's.
const STRUGGLE_MIN := 0.002

var _world: Node3D
var _player: Node3D
var _hands: Node
var _rat: Node3D
var _avatar: PlayerAvatar
var _skeleton: Skeleton3D
var _camera: Camera3D

var _step := 0
var _clock := 0
## Frames until the next step. Steps that are watching something happen set it:
## the squeeze peaks in a fifth of a second and a rat takes seconds to wriggle
## loose, and one gap cannot serve both.
var _gap := WAIT
var _failures := 0
var _shots := false
## Pictures still owed, each a name and the place to stand for it.
##
## They are taken one per frame, and always the frame *after* the camera is put
## in place. A viewport holds the last frame it drew, so a picture grabbed in the
## same breath as the camera is moved is a picture from wherever the camera used
## to be — which is how an arms bench came to have four photographs of the same
## angle, two of them of the previous step's pose.
var _owed: Array = []
## Whether the rat should be hung off the avatar rather than off the player's own
## camera — that is, whether the bench is pretending to be somebody else's
## machine yet. See `_grab`.
var _watching := false

## Where the wrists sat with the hands empty, in the body's own frame.
##
## Everything the checks below measure is in that frame — see `_offset` — and
## the reason is that the body does not hold still between two readings. It
## eases towards where the wire says its player is
## (`PlayerAvatar.SMOOTHING`), and the rat it is being aimed at runs, so the man
## is turned to face it again on the way to every grab. Read in world space, a
## resting arm and a held one differ by however far he happened to turn in
## between, which is most of what the first version of this bench was measuring.
var _rest_wrists: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## How far the head was tipped off vertical with the hands empty, in degrees.
## What the lean is measured against — a man looking at something he is holding
## is a man whose head has come *further* forward than it stands.
var _rest_tilt := 0.0
## The gap between the fists while merely holding, and at the peak of a squeeze.
var _held_gap := 0.0
var _squeezed_gap := 0.0
## A wrist read twice a few frames apart while nothing but the rat was moving.
var _still_wrist := Vector3.ZERO
## Whether the avatar heard the squeeze cross as an action.
var _heard_squeeze := false
## Where every bone this bench asks about was, in world space, the last time the
## skeleton finished a frame.
##
## Read off `skeleton_updated` and not on demand, and that distinction cost an
## afternoon. A `SkeletonModifier3D` runs *inside* the skeleton's own update,
## which happens after this bench's frame: asking `get_bone_global_pose()` from
## out here gets the pose the animation wrote and not the one the modifier left,
## so every arm reads as though the layer had never run — the exact shape of the
## bug the layer was written to fix, reported by a bench measuring the wrong
## moment. The signal is the moment the poses are the ones the renderer will
## skin.
var _bones := {}


func _initialize() -> void:
	Engine.max_fps = 60
	_shots = DisplayServer.get_name() != "headless"
	if _shots:
		DisplayServer.window_set_size(SIZE)
		root.size = SIZE
		root.content_scale_size = SIZE
	_world = load("res://scenes/world.tscn").instantiate()
	root.add_child(_world)
	_player = _world.get_node("Player")
	_hands = _player.get_node("Head/Hands")
	# Nothing is typed at him: every step below drives him by hand.
	_player.set_process_unhandled_input(false)


func _process(_delta: float) -> bool:
	if _watching and _rat != null and is_instance_valid(_rat):
		_rat.set("_capture_point", _avatar.capture_point)
	_clock += 1
	if _clock < _gap:
		return false
	_clock = 0
	_gap = WAIT
	if not _owed.is_empty():
		_take_one()
		return false
	match _step:
		0: _stand_him_up()
		1: _put_a_watcher_on_him()
		2: _read_the_empty_hands()
		3: _shoot("empty")
		4: _grab()
		5: _check_the_arms_came_up()
		6: _check_the_elbows_are_bent()
		7: _check_the_elbows_are_out_and_down()
		8: _check_the_rat_is_in_the_grip()
		9: _check_he_is_looking_at_it()
		10: _shoot("holding")
		11: _read_a_still_wrist()
		12: _check_the_hands_are_alive()
		13: _check_the_legs_still_work()
		14: _squeeze()
		15: _read_the_clench()
		16: _check_the_squeeze_crossed()
		17: _check_the_squeeze_closed_the_hands()
		18: _let_go()
		19: _check_the_arms_went_down()
		20: _shoot("released")
		_:
			_report()
			return true
	_step += 1
	return false


# --- Setting it up ----------------------------------------------------------

func _stand_him_up() -> void:
	_player.global_position = STATION
	_rat = load("res://scenes/rat.tscn").instantiate()
	_world.get_node("Rats").add_child(_rat)
	_rat.global_position = STATION + Vector3(0.0, 0.0, -RAT_AHEAD)
	# Held where it was put. A live rat bolts from a man the moment it notices
	# him, and the bench would then be chasing it round the room with the player
	# and the camera in tow — which is a fine thing for the grip bench to do and
	# no use at all here, where what is wanted is one body standing on open floor
	# being looked at. The grab tears it off this the same way it tears one off
	# the glue (`rat.gd: _hold`), so nothing about the capture is faked.
	_rat.pin()


## Puts up the body a watcher would see him in, and stands a camera in front of
## it.
##
## The avatar is the real scene doing the real thing: its owning half reads the
## player every physics frame and writes the `sync_*` variables, and its watching
## half — normally the only one running, on somebody else's machine — is switched
## back on here so that both ends of the wire happen in this one process. That is
## the whole trick of this bench, and it is why what is photographed is what a
## teammate sees rather than an approximation of it.
func _put_a_watcher_on_him() -> void:
	_aim_at_the_rat()
	_avatar = load("res://scenes/player_avatar.tscn").instantiate()
	_world.add_child(_avatar)
	_avatar.follow(_player)
	# The watching half. `_seen` is what it is waiting for: with no wire under it
	# the first packet never lands, and a body that has never been told where its
	# player is stays hidden on purpose (`player_avatar.gd`).
	_avatar.set("_seen", true)
	_avatar.set_process(true)
	_avatar.visible = true
	_skeleton = _avatar.get_node("Model/Hazmat/Armature/Skeleton3D") as Skeleton3D
	if _skeleton == null:
		_fail("no skeleton under the avatar's model; the rest of the bench is moot")
		return
	_skeleton.skeleton_updated.connect(_remember_the_bones)
	# The idle has to have settled before an empty arm can be read. The model
	# blends into it from the rest pose on the way up (`PlayerModel.BLEND_TIME`),
	# and a reading taken during that is of a body halfway out of its T-pose —
	# which then makes every "the arms came up" measurement below a comparison
	# against a pose the game never shows.
	_gap = 40

	_camera = Camera3D.new()
	_world.add_child(_camera)
	_camera.current = true
	_frame_him()
	# The screens belong to the man being watched, not to the man watching, and
	# both of them are in the way of a photograph of a body.
	for name in [
		"HUD", "HUD_Phase", "PS1PostProcess", "Obstacles", "Walls",
		# The player's own sleeves. They hang off *his* camera and are drawn in
		# world space wherever that camera happens to be, so a second camera
		# looking at him from outside catches them hanging in mid-air by his
		# head — which for an hour read as one of the avatar's own arms flung out
		# sideways, and had a perfectly good pose being re-tuned to fix something
		# that was never in it. Nobody watching a teammate ever sees these.
		"Player/Head/Camera/ViewModel",
	]:
		var overlay := _world.get_node_or_null(NodePath(name))
		if overlay != null:
			overlay.visible = false
	# The houses are dark and a dark photograph says nothing about a pose. It is
	# the bench's own light and goes no further than this file.
	var lamp := DirectionalLight3D.new()
	lamp.light_energy = 1.1
	_world.add_child(lamp)
	lamp.global_position = _camera.global_position + Vector3.UP * 3.0
	lamp.look_at(_player.global_position + Vector3.UP, Vector3.UP)


## Puts the camera where a teammate would be standing: off his front quarter, at
## chest height, looking at the point he holds things at.
func _frame_him(eye: Vector3 = EYE) -> void:
	if _camera == null:
		return
	_camera.global_position = _avatar.global_transform * eye
	var model: Node = _avatar.get_node("Model")
	_camera.look_at(model.grip_point(), Vector3.UP)


## Stands him behind the rat, looking at it. The animal is a live one and bolts,
## so this is done again immediately before the grab.
func _aim_at_the_rat() -> void:
	var target := _rat.global_position + Vector3.UP * 0.2
	_player.global_position = _rat.global_position + Vector3(0.0, STATION.y, RAT_AHEAD)
	_player.look_at(Vector3(target.x, _player.global_position.y, target.z), Vector3.UP)
	_player.rotation.x = 0.0
	_player.rotation.z = 0.0
	var head: Node3D = _player.get_node("Head")
	head.rotation.x = -atan2(
		head.global_position.y - target.y,
		Vector2(head.global_position.x - target.x, head.global_position.z - target.z).length()
	)


func _read_the_empty_hands() -> void:
	_rest_wrists = [_offset(PlayerArms.HAND[0]), _offset(PlayerArms.HAND[1])]
	_rest_tilt = _head_tilt()


func _grab() -> void:
	_aim_at_the_rat()
	_hands.try_use()
	if not _hands.is_busy():
		_fail("the hands did not take the rat; the rest of the bench is moot")
		return
	# What a watcher's machine does with a rat somebody else has caught: it hangs
	# it off the avatar's capture point, which is the only body it has for him
	# (`rat.gd: _capture_point_of`). Solo there is no such machine, so the bench
	# is the one that says so — every frame and not once, because the rat is told
	# again where its holder is whenever the wire says the holder changed, and
	# solo that answer is his own head.
	_watching = true
	_avatar.acted.connect(func(action: PlayerAvatar.Action) -> void:
		if action == PlayerAvatar.Action.SQUEEZE:
			_heard_squeeze = true
	)
	# The animal is not allowed to wriggle loose while the pose is being read.
	# The pressure drains on its own and the rat is gone `time_to_escape` later
	# (`hands.gd`), which is a couple of seconds — less than the checks below
	# take, so without this half of them would be measuring an empty pair of
	# hands and saying so in a way that looked like the pose had failed. It is
	# put back at `_let_go`, which is where losing it is the point.
	_hands.time_to_escape = 3600.0
	# Long enough for the animal to be torn off the floor and to reach the hand
	# (`rat.gd`), which every measurement after this assumes has happened.
	_gap = 45


func _squeeze() -> void:
	_held_gap = _wrist(0).distance_to(_wrist(1))
	_hands.press_secondary()
	# The clench is read four frames on and not twelve. `PlayerArms.SQUEEZE_TIME`
	# is a fifth of a second with a fast attack, so a whole step later the hands
	# are already back where they started and the gesture would measure as
	# nothing at all — which is what it used to be, and is the thing being
	# checked. `_shoot` goes with it for the same reason.
	_gap = 4


func _read_the_clench() -> void:
	_squeezed_gap = _wrist(0).distance_to(_wrist(1))
	_shoot("squeezing")


func _read_a_still_wrist() -> void:
	_still_wrist = _wrist(0)


func _let_go() -> void:
	# Left to wriggle loose rather than killed: a strangled rat is carried down to
	# the belt and the arms stay busy through the whole of it on purpose
	# (`player.gd: _arms_busy`), which is a different question from whether they
	# ever come down at all.
	#
	# The wait is what the hands say it is: the pressure has to drain
	# (`Hands.decay`) and then the animal has to sit unheld for `time_to_escape`,
	# and the arms take `PlayerArms.LOWER_TIME` on top of that.
	_hands.time_to_escape = 0.2
	_gap = 180


# --- The checks -------------------------------------------------------------

## The arms came up. Both wrists in front of the chest and above where they were
## hanging — the whole of the original complaint, asked as two numbers.
func _check_the_arms_came_up() -> void:
	for side in 2:
		var wrist := _offset(PlayerArms.HAND[side])
		if -wrist.z < HELD_AHEAD:
			_fail("the %s wrist is only %.3f m in front of the chest, wanted %.2f"
				% [_named(side), -wrist.z, HELD_AHEAD])
		var risen := wrist.y - _rest_wrists[side].y
		if risen < RESTING_BELOW:
			_fail("the %s wrist only came up %.3f m from resting, wanted %.2f"
				% [_named(side), risen, RESTING_BELOW])
	_say("wrists held %.3f m and %.3f m in front of the chest, up %.3f m and %.3f m"
		% [
			-_offset(PlayerArms.HAND[0]).z, -_offset(PlayerArms.HAND[1]).z,
			_offset(PlayerArms.HAND[0]).y - _rest_wrists[0].y,
			_offset(PlayerArms.HAND[1]).y - _rest_wrists[1].y,
		])


## The elbows are bent. Straight arms are the failure this pose risks, and the
## angle is the only thing that says so.
func _check_the_elbows_are_bent() -> void:
	for side in 2:
		var angle := _elbow_angle(side)
		if angle > MAX_ELBOW:
			_fail("the %s elbow is %.1f°, near enough straight (max %.0f)"
				% [_named(side), angle, MAX_ELBOW])
		elif angle < MIN_ELBOW:
			_fail("the %s elbow is folded to %.1f° (min %.0f)"
				% [_named(side), angle, MIN_ELBOW])
	_say("elbows at %.1f° and %.1f°" % [_elbow_angle(0), _elbow_angle(1)])


## And they are out to the sides and below the hands, which is where an elbow
## goes on a man holding something in front of him. It is the difference between
## this pose and a sleepwalker's.
func _check_the_elbows_are_out_and_down() -> void:
	for side in 2:
		var elbow := _offset(PlayerArms.FOREARM[side])
		var wrist := _offset(PlayerArms.HAND[side])
		var out := absf(elbow.x) - absf(wrist.x)
		if out <= 0.0:
			_fail("the %s elbow is not outside its own wrist (%.3f m)" % [_named(side), out])
		if elbow.y >= wrist.y:
			_fail("the %s elbow is not below its own wrist (%.3f m)"
				% [_named(side), elbow.y - wrist.y])
	_say("elbows %.3f m and %.3f m outside their wrists"
		% [
			absf(_offset(PlayerArms.FOREARM[0]).x) - absf(_offset(PlayerArms.HAND[0]).x),
			absf(_offset(PlayerArms.FOREARM[1]).x) - absf(_offset(PlayerArms.HAND[1]).x),
		])


## The animal is *in* the grip. It is the check the whole thing turns on: arms
## posed at a rat that is drawn somewhere else is a worse picture than no arms.
func _check_the_rat_is_in_the_grip() -> void:
	# Against the point the animal hangs from and not against the middle of the
	# animal: a rat held by the neck is most of a metre of body and tail hanging
	# below the grip, so its origin is nowhere near the fists by design.
	var held := _avatar.capture_point.global_position
	for side in 2:
		var gap := _wrist(side).distance_to(held)
		if gap > GRIP_REACH:
			_fail("the %s fist is %.3f m from the rat, wanted within %.2f"
				% [_named(side), gap, GRIP_REACH])
	# And the point the body says it is holding at is the point the animal hangs
	# from, rather than the two merely being near each other by luck.
	var grip: Vector3 = _avatar.get_node("Model").grip_point()
	if grip.distance_to(_avatar.capture_point.global_position) > 0.01:
		_fail("the capture point is not on the grip (%.3f m off)"
			% grip.distance_to(_avatar.capture_point.global_position))
	_say("fists %.3f m and %.3f m from the animal"
		% [_wrist(0).distance_to(held), _wrist(1).distance_to(held)])


## He is looking at what he is doing. A body that holds something at arm's
## length while staring past it reads as a mannequin holding a prop.
func _check_he_is_looking_at_it() -> void:
	var leaned := _head_tilt() - _rest_tilt
	if leaned < LOOK_LEAN:
		_fail("his head came %.1f° further forward, wanted %.1f°" % [leaned, LOOK_LEAN])
	_say("head %.1f° further forward than standing empty-handed" % leaned)


## The pose is not a mannequin's. The rat fights and the hands are moved about
## by it, and without this the whole thing is a better-shaped version of the bug
## it was written to fix — a man frozen, only with his arms up.
func _check_the_hands_are_alive() -> void:
	var moved := _still_wrist.distance_to(_wrist(0))
	if moved < STRUGGLE_MIN:
		_fail("the held hand moved %.4f m in %d frames, wanted %.4f — it is a mannequin"
			% [moved, WAIT, STRUGGLE_MIN])
	_say("the animal moved the hand %.4f m over %d frames" % [moved, WAIT])


## His legs go on being his legs. This is the half of the fix nobody would think
## to look for once the arms are right: `HOLDING` used to beat every other state,
## so a man walking off with a rat had his feet nailed to the floor.
func _check_the_legs_still_work() -> void:
	var standing: StringName = _avatar.get_node("Model").current_animation()
	if standing != &"Idle":
		_fail("standing still with a rat, his legs play %s and not Idle" % standing)
	# Given a walker's velocity and asked in the same breath. `animation_state`
	# reads `velocity` directly, and letting a physics frame pass first would
	# undo it: nothing is pressed, so the player decelerates to a stop
	# (`player.gd: _physics_process`) and the reading would be of a man standing
	# still — which is the exact bug this check is here to catch, passing for the
	# wrong reason.
	_player.velocity = -_player.global_transform.basis.z * _player.walk_speed
	var walking: PlayerAvatar.State = _player.animation_state()
	if walking == PlayerAvatar.State.HOLDING:
		_fail("carrying a rat is still its own state; his legs cannot move")
	elif walking != PlayerAvatar.State.WALKING and walking != PlayerAvatar.State.RUNNING:
		_fail("walking with a rat reads as %d, wanted WALKING or RUNNING" % walking)
	if _avatar.sync_arms != PlayerAvatar.Arms.HOLDING:
		_fail("his hands did not cross the wire as full (%d)" % _avatar.sync_arms)
	_player.velocity = Vector3.ZERO
	_say("walking with a rat reads as %d, hands as %d" % [walking, _avatar.sync_arms])


## The squeeze reached the body a watcher is looking at. Until it did, the
## clicks stopped at the man who made them.
func _check_the_squeeze_crossed() -> void:
	if not _heard_squeeze:
		_fail("the squeeze never reached the avatar as an action")


## And it shows: the fists close on the animal. It is the only part of a
## strangling with a rhythm, and the rhythm is what tells a watcher whether the
## rat is about to die or about to get loose.
func _check_the_squeeze_closed_the_hands() -> void:
	var closed := _held_gap - _squeezed_gap
	if closed < SQUEEZE_CLOSE:
		_fail("the squeeze closed the fists by %.4f m, wanted %.3f"
			% [closed, SQUEEZE_CLOSE])
	_say("the squeeze closed the fists by %.4f m" % closed)


## And they go back down when the animal is gone.
func _check_the_arms_went_down() -> void:
	for side in 2:
		# Back to where an empty hand hangs, give or take the breathing the idle
		# animation does. Against its own resting offset and not against a fixed
		# distance, because a hanging arm is already some way in front of the
		# chest bone — it sits behind the ribs — and a threshold picked without
		# looking would pass or fail on that alone.
		var back := _offset(PlayerArms.HAND[side]).distance_to(_rest_wrists[side])
		if back > RETURNED:
			_fail("the %s wrist settled %.3f m from where an empty hand hangs, wanted %.2f"
				% [_named(side), back, RETURNED])


# --- Reading the body -------------------------------------------------------

func _named(side: int) -> String:
	return "left" if side == 0 else "right"


## Every bone the checks below ask about, put away at the one moment in the
## frame when the poses are the ones that will be drawn. See `_bones`.
func _remember_the_bones() -> void:
	var wanted: Array[StringName] = [PlayerArms.CHEST, PlayerArms.NECK, PlayerArms.HEAD]
	wanted.append_array(PlayerArms.UPPER_ARM)
	wanted.append_array(PlayerArms.FOREARM)
	wanted.append_array(PlayerArms.HAND)
	for name in wanted:
		var index := _skeleton.find_bone(name)
		if index >= 0:
			_bones[name] = _skeleton.global_transform \
				* _skeleton.get_bone_global_pose(index).origin


## Where a bone was, in world space, at the end of the last skeleton frame.
func _bone(name: StringName) -> Vector3:
	return _bones.get(name, Vector3.ZERO)


func _wrist(side: int) -> Vector3:
	return _bone(PlayerArms.HAND[side])


func _chest() -> Vector3:
	return _bone(PlayerArms.CHEST)


## Where a bone sits relative to the chest, in the body's own frame: `x` across
## him, `y` up him, and `-z` out in front of him, which is Godot's forward.
##
## It is the space every check below is written in. Read off the avatar and not
## off the player, because the avatar is deliberately a little behind him
## (`PlayerAvatar.SMOOTHING`) and what is being measured is the drawn body.
func _offset(name: StringName) -> Vector3:
	var body := _avatar.global_transform.affine_inverse()
	return body * _bone(name) - body * _chest()


## How far the head is tipped off vertical, in degrees. It is the neck read as
## a whole — the direction from the neck bone up through the skull — which is
## what tips forward when a man looks down at his own hands.
func _head_tilt() -> float:
	return rad_to_deg(
		Vector3.UP.angle_to(_bone(PlayerArms.HEAD) - _bone(PlayerArms.NECK))
	)


## The angle at one elbow, in degrees: 180 is a straight arm.
func _elbow_angle(side: int) -> float:
	var shoulder := _bone(PlayerArms.UPPER_ARM[side])
	var elbow := _bone(PlayerArms.FOREARM[side])
	var wrist := _wrist(side)
	return rad_to_deg((shoulder - elbow).angle_to(wrist - elbow))


# --- Plumbing ---------------------------------------------------------------

## A picture, on the runs that have a window. It is the only judge of whether
## the body *looks* like it is strangling something, which no number can say.
func _shoot(name: String) -> void:
	if not _shots:
		return
	# Two angles of the same moment, owed rather than taken: see `_owed`. The
	# camera for the first is put in place now, so that the frame drawn between
	# this call and the next one is the one being asked for.
	_owed = [[name, EYE], [name + "-side", SIDE_EYE]]
	_frame_him(EYE)
	_gap = 2


## One owed picture, of the frame that has just been drawn, and the camera put
## where the next one wants it.
func _take_one() -> void:
	var shot: Array = _owed.pop_front()
	var path: String = "user://arms-%s.png" % shot[0]
	root.get_texture().get_image().save_png(path)
	_say("wrote %s" % ProjectSettings.globalize_path(path))
	if not _owed.is_empty():
		_frame_him(_owed[0][1])
	_gap = 2


func _say(line: String) -> void:
	print("  ", line)


func _fail(reason: String) -> void:
	_failures += 1
	print("FAIL: ", reason)


func _report() -> void:
	if _failures == 0:
		print("arms: all checks passed")
	else:
		print("arms: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
