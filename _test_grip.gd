extends SceneTree
## Grip bench: the player's own hand has to be *on* the rat he is strangling.
##
## Run headless for the numbers:
##   godot --headless --script _test_grip.gd
## Run with a window to also get pictures of the hand hanging, closing and
## closed, which is the part no assertion can judge:
##   godot --script _test_grip.gd
##
## The bug this was written for is one the numbers had all along and nobody had
## asked for: the rat was held a metre from the lens (`Hands.hands_distance`)
## and the arm rested with its fingertips 38 centimetres out
## (`PlayerViewModel.rest_offset`), so the player strangled an animal floating
## more than half a metre in front of an open hand. On screen it read as the rat
## hanging in mid-air by itself while a hand waved in the corner.
##
## The hand cannot close — `models/hazmat_hand.glb` is 56 rigid triangles with
## no skeleton and no blend shapes, so there are no fingers to curl. What it can
## do is *travel*: a second named pose (`PlayerViewModel.grip_offset`) that puts
## the narrow part of the mesh, the hand as opposed to the sleeve, on the rat's
## neck. With the fist inside the animal's silhouette the eye reads a grip even
## though the geometry never changed shape.
##
## So the questions are about where the hand ends up, and they are asked in the
## order the gesture happens:
##
## - **At rest the hand is nowhere near the rat**, which is the state the rest
##   of the view model bench already checks and is only established here.
## - **The grip travels.** It is a fraction that moves over several frames, not
##   a pose that appears: a hand that teleported onto the animal would read as a
##   cut rather than as a grab.
## - **Closed, the fist is on the rat.** The hand's own geometry overlaps the
##   body the capture point holds — measured in metres against the rat's real
##   size, because that is what "around it" means.
## - **And it is in the middle of the picture**, where the rat is, rather than
##   merely close to it in world space while sitting off in a corner.
## - **The elbow stays out of shot.** This is the failure the whole approach
##   risks: reaching the fist out a metre drags the forearm into the middle of
##   the frame and reads as an arm stretching rather than a hand holding. It is
##   why the rat was brought closer instead of the arm being sent further.
## - **A rat that gets loose leaves an empty hand.** It went under its own
##   power, so the arm opens and returns to the pose the other bench measures.
## - **A rat that is strangled is carried away.** This is the other half of the
##   gesture and the one the numbers above cannot see: the animal dies *in the
##   fist*, the arm goes down with it past the bottom of the frame, and comes
##   back up empty. What used to happen is that the hand opened on the killing
##   squeeze and was back in its resting corner a fifth of a second later, while
##   the body took a whole second longer to drop to the waist under its own steam
##   (`rat.gd: _process_stow`) — so the last thing the player saw of a rat he had
##   just killed was it falling out of shot beside a hand that had already let go
##   of it. The checks are: the fist keeps the body while it goes limp, it is
##   below the picture at the bottom of the travel, and only then does it come
##   back up and open.
##
## The rat is a real one from `rat.tscn` grabbed by the player's real `Hands`,
## so what is measured is the game's own gesture rather than a pose set by hand.

## Frames of slack between one step and the next.
const WAIT := 12
## The step the whole bench counts time in, in seconds. See `_process` for why it
## is a fixed number rather than the frame the engine actually took.
const FRAME := 1.0 / 60.0
## Where the bench stands the player, and the rat, on open floor.
const STATION := Vector3(0.0, 0.1, 4.0)
## How far in front of him the rat is put, so it is inside the hands' cone.
const RAT_AHEAD := 1.2
## Window size for the picture-taking run.
const SIZE := Vector2i(1141, 634)

## How far the fist may sit from the rat's held body and still count as being
## around it, in metres.
##
## It is the animal's own half-width and then some: a rat is roughly 12
## centimetres across the shoulders, so a hand whose centre is within this of
## the body's axis has the body inside its silhouette. Being *exactly* on the
## axis is not wanted and not checked — a fist round a neck sits to one side of
## it, which is where a hand goes.
const GRIP_REACH := 0.22

## How far from the middle of the picture the fist may land, as a fraction of
## the frame. The rat is drawn on the centre of the screen by its capture point,
## so this is the same question as the one above asked in the only space that
## actually decides what the player sees.
const GRIP_SCREEN := 0.22

## How far outside the picture the elbow has to be, as a fraction of the frame,
## and the depth past which where it sits stops mattering. Both are the view
## model bench's numbers and are here for the same reason they are there — see
## `_test_viewmodel.gd: ELBOW_MARGIN`.
const ELBOW_MARGIN := 0.08
const ELBOW_DEPTH := 0.35

## How wide the glove has to be drawn next to the rat's body, as a multiple of
## it. At one they are the same width on screen, which is the least that reads
## as a fist closed around the animal rather than a hand somewhere behind it.
const MIN_GLOVE_WIDTH := 1.0

## How far apart the two fists have to be drawn, as a multiple of the rat's own
## drawn width.
##
## The second hand is the right one mirrored (`PlayerViewModel._place`), and the
## grip's yaw brings each fist from its own corner back towards the middle of
## the screen — so without `grip_spread` holding them apart the two arrive at the
## *same point*, sink into each other and read as one lump with two sleeves. That
## is a failure nothing else in here can see: every check above is about one
## glove and the rat, and both gloves pass all of them while occupying the same
## cubic centimetres.
##
## What it is set against is the animal and not the frame, because a rat's width
## is what "on either side of it" means — and because a fraction of the frame is
## not the same measurement twice. The picture is a different shape with a window
## open than it is headless, and the same pose read 0.16 of a frame in one run and
## 0.09 in another.
##
## Graded on the headless run, which is the one whose timing is its own. With a
## window open the bench walks its counted frames through real seconds, and the
## reading lands on some earlier moment of the travel — a grip still closing,
## with the hands not yet where they are going. The pictures are still worth
## taking there; the numbers are not.
##
## It is the first-person counterpart of `_test_arms.gd: GRIP_REACH`, which asks
## the same question of the body.
const MIN_FIST_GAP := 1.0

## How wide the rat's body is, in metres. Measured across the shoulders, which
## is the part the fist closes on — not the length, which is what fills the
## frame.
const RAT_WIDTH := 0.12

## How much of the rat the glove is allowed to be drawn *behind*, as a fraction
## of the screen cells the two share.
##
## Near zero, because a hand painted behind the animal it is holding is the
## animal sunk into the hand, and that is the whole failure. It is not *exactly*
## zero for two reasons, and it is worth separating them because only one of
## them is the bench's own fault.
##
## The first is aliasing: the comparison is a rasteriser working on cell centres,
## so along the line where the two silhouettes cross there are always a few cells
## whose middle falls on one body and whose depth is taken from the other. That
## edge is a couple of hundred cells long here and a handful of them land the
## wrong way. It is worth about a percent and the player cannot see it.
##
## The second is the rat. It does not merely tremble in the fist, it kicks
## (`rat.gd: KICK_INTERVAL`), and a hard kick swings the body a good five
## centimetres — briefly through the glove, at a pose that clears it the rest of
## the time. Measured over repeated runs this sits at 0.6 to 1.0 per cent of the
## shared area with an occasional moment at 3, which is one sample of eighteen
## catching a kick at its peak.
##
## So the budget is set above that spike rather than below it, and the honest
## reason is that the hand cannot close. `hazmat_hand.glb` is a rigid block, so
## it can be beside the animal or in front of it but never around it, and a pose
## that cleared even the hardest kick would have to sit so far off the body that
## `GRIP_REACH` rejects it — which is exactly what the poses either side of this
## one do. A fraction of a second of contact during a kick reads as an animal
## fighting a grip. The failure this guards against does not look like that at
## all: it is steady, it is most of the overlap, and the bug it was written for
## measured 96 per cent of it.
const MAX_BEHIND := 0.05

## How much of the animal the glove may hide, as a fraction of the rat's own
## drawn silhouette.
##
## The other half of the question above, and the half that was missed the first
## time this was fixed. `MAX_BEHIND` alone says the hand must not be drawn behind
## the rat, and a pose can satisfy that completely by sitting square in front of
## the animal and covering it — which is what the first fix did. It passed every
## check in this file and looked worse than the bug: a fist planted over the rat,
## with the player strangling something he could barely see.
##
## The two together are what "holding" means. The hand has to win the depth test
## where they overlap, *and* the overlap has to stay small: a fist on a neck hides
## the neck, not the animal. The pose this is set for hides about eight per cent,
## which is roughly the head and shoulders; the covering pose hid twenty-one.
const MAX_HIDDEN := 0.14

## How much clearance the glove has to keep, in metres, where it and the rat
## share a cell of the picture.
##
## Being merely in front is not enough. The animal trembles in the fist the whole
## time it is held (`rat.gd: TREMOR`), so a pose that clears by a millimetre in
## the frame this bench measures does not clear in the next one, and what the
## player sees is the rat cutting in and out of the sleeve. This is the margin
## that survives the shaking.
const DEPTH_CLEARANCE := 0.005

## How fine the picture is cut up for that comparison, in cells across the frame.
## Coarser than the screen on purpose: the question is whether the glove reads as
## being in front, not whether some stray pixel of it does.
const OCCLUSION_GRID := 160

## One frame in this many is sampled for that comparison, while the rat is held.
## Every frame would be a good deal of rasterising to say the same thing; this
## still takes in a kick as well as the tremor between kicks.
const OCCLUSION_EVERY := 3

## How far the fist may be from the body at the bottom of the stowing, in metres.
##
## Slacker than `GRIP_REACH`, and on purpose. At the top of the gesture the two
## are being held together in the middle of the screen where the player is
## looking straight at them, and a few centimetres out reads as a hand behind a
## rat. Going down they are both leaving the frame — the body shrinking away at
## the waist (`rat.gd: STOW_VANISH`), the glove past the bottom edge — and what
## has to be true there is the coarser thing the fix is about: that the hand went
## *with* the animal instead of letting it fall on its own. Half a metre apart is
## a hand that left; a hand this close is a hand still carrying.
const STOW_REACH := 0.34

var _world: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _view_model: PlayerViewModel
var _hands: Node3D
var _capture_point: Node3D
var _rat: Node3D

## The running totals of the occlusion comparison, gathered frame by frame while
## the rat is in the hand and read once by .
var _occlusion_shared := 0
var _occlusion_behind := 0
var _occlusion_worst := INF
var _occlusion_rat_cells := 0
var _occlusion_moments := 0
var _occlusion_hidden := 0
## Set once the totals above have been read, which stops them being gathered any
## further. After the kill the body goes limp and is carried off to the belt, and
## whether the hand is in front of it there is the stowing checks question rather
## than this one.
var _occlusion_read := false

var _step := 0
var _clock := 0
var _failures := 0
var _shots := false
## Where the hand sat before the grab, to prove it came back to it afterwards.
var _rest_hand := Vector3.ZERO
## The grip fraction one step after the grab, to prove it travelled rather than
## arriving all at once.
var _mid_grip := 0.0
## The arm on the frame after the killing squeeze: still closed, not yet going
## down. The two readings the old behaviour got wrong.
var _dead_grip := 0.0
var _dead_stow := 0.0
## Where the fist was when the descent began and where it ended up, and how far
## down the screen it got — read while the arm travels rather than after it, so
## that a hand which dipped and came back cannot pass as one that left the frame.
var _falling_from := Vector3.ZERO
var _fallen_to := Vector3.ZERO
var _fallen_stow := 0.0
var _lowest_screen := 0.0
## How far the fist was from the body while it went limp, and the nearest it
## ever got to it on the way down. Both recorded during the walk, because the
## body is freed at the end of its own stowing and is not there to measure
## against afterwards.
var _limp_gap := 0.0
var _fallen_gap := 0.0


func _initialize() -> void:
	Engine.max_fps = 60
	_shots = DisplayServer.get_name() != "headless"
	if _shots:
		DisplayServer.window_set_size(SIZE)
	_world = load("res://scenes/world.tscn").instantiate()
	root.add_child(_world)
	_player = _world.get_node("Player")
	_camera = _player.get_node("Head/Camera")
	_view_model = _player.get_node("Head/Camera/ViewModel")
	_hands = _player.get_node("Head/Hands")
	_capture_point = _player.get_node("Head/CapturePoint")
	# Nothing is typed at him: every step below drives him by hand.
	_player.set_process_unhandled_input(false)
	# And his own frame is switched off with it, so the bench is the only thing
	# advancing the arm.
	#
	# It matters for the stowing and for nothing before it. The player advances
	# the view model once per physics frame (`player.gd`), and this bench
	# advances it again per rendered frame — which for a pose that simply
	# travels to its end and stays there is invisible, because both callers
	# arrive at the same place. The stowing is a *clock*: it holds for a while,
	# goes down, comes back up, and two callers feeding it delta run it at
	# something near double speed, so the frame counts the steps below are
	# written in would measure a gesture half over. One driver, and the seconds
	# in here are the seconds in the game.
	_player.set_physics_process(false)


func _process(_delta: float) -> bool:
	# The hand's travel is advanced by the player every frame in the game
	# (`player.gd`), and his own frame is switched off here, so the bench is the
	# one that does it. It is the call the gesture cannot do without.
	#
	# A fixed step and not the real `delta`, which is the difference between a
	# bench that measures the gesture and one that measures the machine it ran
	# on. Headless, the loop turns over thousands of times a second and `delta`
	# is whatever the last turn happened to take; the poses that only travel to
	# an end and stop do not care, but the stowing is a clock — hold, go down,
	# come back — and the steps below walk it in counted frames. Feeding it real
	# deltas ran a second-and-a-half gesture past its end inside the twelve idle
	# frames between two steps, and every reading afterwards was of an arm that
	# had already finished and gone home.
	_advance(1)
	# Gathered here rather than inside the check that reads it: the rat struggles
	# on the engine's frames, so the moments being compared have to be separated
	# by frames rather than by a loop. Only while it is held, and only while the
	# reading is still wanted — after the kill the body goes limp and is carried
	# off, which is a different question, asked further down.
	if _rat != null and is_instance_valid(_rat) and _hands.is_busy() \
			and _rat.is_in_hand() and not _occlusion_read and _clock % OCCLUSION_EVERY == 0:
		_sample_occlusion()
	_clock += 1
	if _clock < WAIT:
		return false
	_clock = 0
	match _step:
		0: _stand_him_up()
		1: _put_a_rat_in_front_of_him()
		2: _check_open_hand_is_clear()
		3: _shoot("hanging")
		4: _grab()
		5: _check_grip_travels()
		6: _shoot("closing")
		7: _check_fist_on_rat()
		8: _check_fist_centred()
		9: _check_elbow_out_of_shot()
		10: _check_fist_reads_against_the_rat()
		11: _check_the_hand_is_drawn_in_front()
		12: _check_the_arm_reaches_the_shoulder()
		13: _shoot("gripping")
		14: _squeeze()
		15: _check_squeeze_moved_the_arm()
		16: _kill_it_and_watch_it_being_put_away()
		17: _check_fist_keeps_the_dead_rat()
		18: _check_the_rat_went_down_with_the_hand()
		19: _check_the_hand_left_the_frame()
		20: _check_hand_came_back_empty()
		21: _shoot("released")
		_:
			_report()
			return true
	_step += 1
	return false


## Puts him on his mark with a rat in front of him. A step rather than a line in
## `_initialize`, because `global_position` on a node not yet in the tree is an
## error and a no-op.
func _stand_him_up() -> void:
	_player.global_position = STATION
	_rat = load("res://scenes/rat.tscn").instantiate()
	_world.get_node("Rats").add_child(_rat)
	# Straight ahead of the camera, on the floor, inside the hands' cone.
	_rat.global_position = STATION + Vector3(0.0, 0.0, -RAT_AHEAD)


## Turns him to face it, and only then reads the resting pose.
##
## A step of its own because the rat has to be in the tree and in the `rats`
## group before the hands can see it (`weapon.gd: _rat_in_sights`), and because
## turning the player moves his arms — the rest pose has to be read after he has
## stopped moving, not before.
func _put_a_rat_in_front_of_him() -> void:
	_aim_at_the_rat()
	_rest_hand = _hand_centre()


## Stands him behind the rat, looking at it.
##
## The player is moved to the animal rather than the animal to the player, and
## it is done again immediately before the grab, because the rat is a live one:
## it bolts from the man the moment it notices him, and a bench that aimed once
## at where it was spawned swung at empty floor three metres short of it.
func _aim_at_the_rat() -> void:
	var target := _rat.global_position + Vector3.UP * 0.2
	_player.global_position = _rat.global_position + Vector3(0.0, STATION.y, RAT_AHEAD)
	# The body turns to face it, and only the head looks down — the same split
	# the player himself has (`player.gd`), and it is the head's half that
	# matters here: his eyes are 1.6 m up and the animal is on the floor, so a
	# man looking level down the corridor has it outside his cone and swings at
	# nothing (`weapon.gd: angle`).
	_player.look_at(Vector3(target.x, _player.global_position.y, target.z), Vector3.UP)
	_player.rotation.x = 0.0
	_player.rotation.z = 0.0
	var head: Node3D = _player.get_node("Head")
	var eyes := (_player.get_node("Head/Camera") as Camera3D).global_position
	var flat := Vector2(target.x - eyes.x, target.z - eyes.z).length()
	head.rotation.x = atan2(target.y - eyes.y, flat)


## Before anything is grabbed, the hand is where the other bench says it is: out
## in the corner, well short of where a rat is held. It is the state the whole
## fix is measured against, so it is established rather than assumed.
func _check_open_hand_is_clear() -> void:
	var gap := _rest_hand.distance_to(_held_body_point())
	_say("at rest the hand is %.2f m from where a rat would be held" % gap)
	if gap <= GRIP_REACH:
		_fail("the resting hand is already on the rat; there is nothing to travel")
	if not is_zero_approx(_view_model.grip()):
		_fail("the hand starts out gripping (%.2f)" % _view_model.grip())


## The player grabs, through his own weapon rather than by the pose being set.
func _grab() -> void:
	# Aimed again here rather than trusted from the last step: the rat has been
	# running the whole time.
	_aim_at_the_rat()
	_hands.try_use()
	if not _hands.is_busy():
		_fail("the hands did not take the rat; the rest of the bench is moot")
		return
	# Read one frame in, not twelve: the travel takes `grip_time` — about a fifth
	# of a second — and the gap between two steps of this bench is longer than
	# that, so waiting for the next step would find the hand already there and
	# call a perfectly good travel a jump.
	_advance(1)
	_mid_grip = _view_model.grip()


## The grip is a travel and not a jump: one step after the grab it is under way
## and not yet finished. A hand that snapped onto the rat would pass every other
## check here and still read as a cut.
func _check_grip_travels() -> void:
	_say("one frame after the grab the hand is %.0f%% closed" % (_mid_grip * 100.0))
	if is_zero_approx(_mid_grip):
		_fail("the hand never started closing")
	elif is_equal_approx(_mid_grip, 1.0):
		_fail("the hand arrived on the rat in one frame instead of travelling")
	# Let it finish before anything is measured against the closed pose.
	_advance(30)


## Closed, the fist is around the animal: its own geometry sits within a rat's
## half-width of the body being held.
func _check_fist_on_rat() -> void:
	if not is_equal_approx(_view_model.grip(), 1.0):
		_fail("the hand never finished closing (%.2f)" % _view_model.grip())
	var gap := _hand_centre().distance_to(_held_body_point())
	_say("gripping, the fist is %.2f m from the held body" % gap)
	if gap > GRIP_REACH:
		_fail("the fist is %.2f m from the rat; it is not around it" % gap)


## And it is on the rat *on screen*, which is the only space that decides what
## the player actually sees. A fist the right distance away in metres but off in
## a corner would satisfy the check above and look like nothing.
func _check_fist_centred() -> void:
	var where := _screen_position(_hand_centre())
	var rat := _screen_position(_held_body_point())
	_say("gripping, the fist is at (%.2f, %.2f) of the frame, the rat at (%.2f, %.2f)"
		% [where.x, where.y, rat.x, rat.y])
	if where.distance_to(rat) > GRIP_SCREEN:
		_fail("the fist is drawn %.2f of a frame from the rat" % where.distance_to(rat))
	# The other hand, asked in the same breath rather than from a step of its
	# own. The steps are counted frames and the rat is on a clock while they run
	# — it fights its way out of a hand that holds it long enough (`hands.gd`) —
	# so a step added here is a step taken off the end of the hold, and the
	# stowing at the bottom of the list is what runs out of animal.
	_check_the_rat_is_between_the_fists()


## The elbow stays out of the picture. This is the failure reaching the arm out
## risks, and the reason the rat was brought closer rather than the arm sent
## further: a forearm that crosses the middle of the frame reads as an arm
## stretching for something instead of a hand holding it.
func _check_elbow_out_of_shot() -> void:
	# Both of them, because the strangling is drawn with both hands: the left
	# arm is the right one mirrored and it crosses the opposite corner, so it has
	# its own elbow to keep out of the picture. Skipped when it is not drawn,
	# which is every pose but this one (`PlayerViewModel.show_left`).
	for side in ["Right", "Left"]:
		var arm := _view_model.get_node_or_null(side) as Node3D
		if arm == null or not arm.visible:
			continue
		_check_one_elbow(side)


## One elbow, on whichever arm.
func _check_one_elbow(side: String) -> void:
	var ends := _arm_ends(side)
	if ends.is_empty():
		_fail("the %s arm has no mesh to measure" % side.to_lower())
		return
	var elbow: Vector3 = ends[0]
	var depth := -elbow.z
	_say("gripping, the %s elbow is %.2f m in front of the lens" % [side.to_lower(), depth])
	if depth >= ELBOW_DEPTH:
		# Far enough out that the foreshortening is gone: a forearm there is
		# simply a forearm, wherever it sits.
		return
	var where := _screen_position(elbow)
	_say("gripping, the %s elbow is at (%.2f, %.2f) of the frame"
		% [side.to_lower(), where.x, where.y])
	var outside := where.x < -ELBOW_MARGIN or where.x > 1.0 + ELBOW_MARGIN \
		or where.y < -ELBOW_MARGIN or where.y > 1.0 + ELBOW_MARGIN
	if not outside:
		_fail("the %s elbow is close to the lens and inside the picture; the sleeve will fill the screen"
			% side.to_lower())


## The animal is held *between* the two fists, and the two fists are two.
##
## The whole of the second hand is here. It arrives as a mirror of the first
## (`PlayerViewModel._place`), and a mirror alone puts both palms on the middle
## of the screen — the same point, at the same depth, one inside the other. On
## screen that is not two hands holding something: it is one lump with a sleeve
## running out of either side of it, and every other check in this file passes
## while it happens, because every other check is about one glove and the rat.
##
## So it is asked the way a picture asks it: the two palms are far enough apart
## to read as two, and the rat is between them rather than beside them.
func _check_the_rat_is_between_the_fists() -> void:
	var left_arm := _view_model.get_node_or_null("Left") as Node3D
	if left_arm == null or not left_arm.visible:
		_fail("the left hand is not drawn while a rat is being strangled")
		return
	var right := _screen_position(_hand_centre("Right"))
	var left := _screen_position(_hand_centre("Left"))
	var rat := _screen_position(_held_body_point())
	var width := _rat_width_on_screen()
	var gap := absf(right.x - left.x)
	_say("gripping, the fists are %.2f of the animal's width apart, and the rat is between %.2f and %.2f"
		% [gap / width if width > 0.0 else 0.0, minf(left.x, right.x), maxf(left.x, right.x)])
	if gap < width * MIN_FIST_GAP:
		_fail("the two fists are drawn %.2fx the rat's width apart; they will read as one hand"
			% (gap / width if width > 0.0 else 0.0))
	if rat.x < minf(left.x, right.x) or rat.x > maxf(left.x, right.x):
		_fail("both fists are on the same side of the rat; it is beside them rather than between them")


## The fist has to hold its own against the animal it is squeezing.
##
## The failure this catches has nothing to do with where the hand is and is
## invisible to every check above it: with the arm at its resting size, and the
## palm level with the rat rather than in front of it, the glove comes out
## *narrower on screen than the rat is wide*. Everything measures correct — the
## fist is on the neck, dead centre, the elbow is out of shot — and it reads as
## an animal floating in front of a small, far-off hand, because a hand smaller
## than the thing it is gripping is a hand somewhere behind it.
##
## So it is asked in the two ways that matter: the fist is the *nearer* object,
## and it is at least as wide as the body it is closed around.
func _check_fist_reads_against_the_rat() -> void:
	var fist := _hand_centre()
	var body := _held_body_point()
	_say("gripping, the fist is %.2f m from the lens and the rat %.2f m"
		% [-fist.z, -body.z])
	if fist.z <= body.z:
		_fail("the fist is level with or behind the rat; it will read as being behind it")

	# Both widths taken on screen, which is the only place the comparison means
	# anything: the same two objects at different depths are drawn at different
	# sizes, and that is exactly the effect being guarded against.
	var glove := _glove_width_on_screen()
	var rat := _rat_width_on_screen()
	_say("the glove is %.3f of the frame wide, the rat's body %.3f" % [glove, rat])
	if glove < rat * MIN_GLOVE_WIDTH:
		_fail("the glove is drawn %.2fx the rat's width; it is too small to read as gripping"
			% (glove / rat if rat > 0.0 else 0.0))


## The whole of the hand is drawn in front of the whole of the rat, everywhere
## the two are painted on top of each other.
##
## This is the check the bug got past, and it got past because every question
## above it is asked about *points*. `_check_fist_reads_against_the_rat` compares
## the palm to the capture point, finds the palm seven centimetres nearer and
## says the hand is in front — and both of those points stop being true the
## moment they stand in for a body. The rat is nearly a metre of animal hung
## around the capture point and its flank reaches fifteen centimetres nearer the
## lens than the point it hangs from; the arm is seventy centimetres of sleeve
## swung across the frame at `PlayerViewModel.grip_rotation`, so the part of it
## that crosses the animal on screen is the wrist behind the palm, not the palm.
##
## The two solids therefore interpenetrated while both points measured correct,
## and the renderer duly drew the rat over the sleeve — an animal sunk into the
## player's hand, which is the one thing the grip pose exists to prevent and the
## one thing no reading of two points can see.
##
## So it is asked here the way the renderer asks it. Both silhouettes are
## rasterised into a coarse depth buffer, from real triangles through the live
## transforms — so it follows `grip_scale`, `grip_rotation` and the perspective
## at whatever depth the pose ended up — and every cell the two share is
## compared. Where the animal comes out nearer, the player sees it through the
## hand.
func _check_the_hand_is_drawn_in_front() -> void:
	# Sampled over a stretch of the struggle rather than judged on one frame.
	# The animal never stops moving in the fist — a constant tremor, and a kick
	# every second or so (`rat.gd: TREMOR`, `KICK_INTERVAL`) that swings it a
	# good five centimetres. A single frame therefore grades whichever moment of
	# the shaking the bench happened to land on, and it showed: the same pose
	# came back clear on one run and sunk into the hand on the next. What has to
	# hold is the worst moment of the struggle, not a lucky one.
	#
	# The samples are taken by `_sample_occlusion` on the bench's own frames —
	# the rat is stepped by the engine and not by this script, so the moments
	# have to be separated by real frames rather than by a loop here, which would
	# read one pose over and over and call it a struggle.
	_occlusion_read = true
	if _occlusion_shared == 0:
		_fail("the glove and the rat share no part of the picture; the hand is not on the animal")
		return
	var share := float(_occlusion_behind) / float(_occlusion_shared)
	_say("over %d moments the hand and the rat share %d cells, the hand behind on %d (%.1f%%), clearing by %.3f m at worst"
		% [_occlusion_moments, _occlusion_shared, _occlusion_behind, share * 100.0, _occlusion_worst])
	var hidden := float(_occlusion_hidden) / float(maxi(_occlusion_rat_cells, 1))
	_say("the glove covers %.0f%% of the animal" % (hidden * 100.0))
	if hidden > MAX_HIDDEN:
		_fail("the glove hides %.0f%% of the rat; it is planted in front of the animal rather than holding it"
			% (hidden * 100.0))
	if share > MAX_BEHIND:
		_fail("the rat is drawn over the hand on %.0f%% of where they meet; it will read as sinking into it"
			% (share * 100.0))


## One moment of that comparison, folded into the running totals.
##
## Called from `_process` while the rat is being held, so that the moments it
## grades are separated by frames the animal actually moved through.
func _sample_occlusion() -> void:
	# The two hands are read as two different questions, and the split is the
	# whole of what the second hand changes in here.
	#
	# *Behind* is asked of the near hand alone. It is the failure this file was
	# written for — the animal drawn through the fist that is supposed to be
	# closed in front of it — and the far hand is behind the rat *on purpose*:
	# that is what a far hand is, and counting it would be marking the pose wrong
	# for doing the one thing that makes it read as two hands round a neck.
	#
	# *Covering* is asked of both, because covering is about the player's view of
	# the animal and he is looking at the whole picture. Two gloves hide more of
	# a rat than one, and that is exactly the cost `grip_spread` is traded
	# against.
	var glove := _depth_buffer(_view_model.get_node_or_null("Right"))
	var both := glove.duplicate()
	_merge_nearest(both, _depth_buffer(_view_model.get_node_or_null("Left")))
	var rat := _depth_buffer(_rat.get_node_or_null("Model"))
	if glove.is_empty() or rat.is_empty():
		return
	_occlusion_moments += 1
	for cell in rat:
		if not glove.has(cell):
			continue
		_occlusion_shared += 1
		# The camera looks down its own -Z, so a *larger* z is nearer the lens
		# and a positive clearance is the hand being in front.
		var clearance: float = glove[cell] - rat[cell]
		_occlusion_worst = minf(_occlusion_worst, clearance)
		if clearance < DEPTH_CLEARANCE:
			_occlusion_behind += 1
	_occlusion_rat_cells += rat.size()
	for cell in rat:
		if both.has(cell) and both[cell] - rat[cell] >= DEPTH_CLEARANCE:
			_occlusion_hidden += 1




## Folds one depth buffer into another, keeping whichever surface is nearer the
## lens in each cell. It is what the renderer does with two objects, and it is
## how the two gloves become the one silhouette the player is looking at.
func _merge_nearest(into: Dictionary, other: Dictionary) -> void:
	for cell in other:
		# The camera looks down its own -Z, so the larger z is the nearer of two
		# surfaces — the same convention `_sample_occlusion` compares by.
		if not into.has(cell) or other[cell] > into[cell]:
			into[cell] = other[cell]


## A depth buffer of everything drawn under `node`: for each cell of the picture,
## how near the lens the nearest surface covering it is, in camera space.
##
## Built from the meshes' own triangles and not from their bounding boxes. A box
## is no use for this question and would have hidden the bug all over again: the
## arm is swung across the frame, so its box is half a picture of empty air, and
## the rat's box holds a good deal of nothing around a thin animal. What is being
## asked is which surface the player actually sees.
func _depth_buffer(node: Node) -> Dictionary:
	var buffer := {}
	if node == null:
		return buffer
	var into_camera := _camera.global_transform.affine_inverse()
	for mesh in _meshes_under(node):
		if not mesh.visible:
			continue
		var geometry := mesh.mesh
		if geometry == null:
			continue
		var to_camera := into_camera * mesh.global_transform
		for surface in geometry.get_surface_count():
			var arrays := geometry.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var order: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] \
				if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := order.size() if order.size() > 0 else points.size()
			var i := 0
			while i + 2 < count:
				var a := to_camera * points[order[i] if order.size() > 0 else i]
				var b := to_camera * points[order[i + 1] if order.size() > 0 else i + 1]
				var c := to_camera * points[order[i + 2] if order.size() > 0 else i + 2]
				i += 3
				# Anything at or behind the lens has no screen position worth
				# taking: `unproject_position` on it comes back as nonsense.
				if a.z >= 0.0 or b.z >= 0.0 or c.z >= 0.0:
					continue
				_draw_triangle(a, b, c, buffer)
	return buffer


## Rasterises one triangle into `buffer`, keeping in each cell it covers whichever
## surface is nearest the lens.
func _draw_triangle(a: Vector3, b: Vector3, c: Vector3, buffer: Dictionary) -> void:
	var sa := _screen_position(a)
	var sb := _screen_position(b)
	var sc := _screen_position(c)
	var area := (sb - sa).cross(sc - sa)
	if is_zero_approx(area):
		return
	var low := Vector2(minf(sa.x, minf(sb.x, sc.x)), minf(sa.y, minf(sb.y, sc.y)))
	var high := Vector2(maxf(sa.x, maxf(sb.x, sc.x)), maxf(sa.y, maxf(sb.y, sc.y)))
	# Clipped to the picture, which is both correct and what keeps this cheap: an
	# arm swung across the frame has triangles reaching a long way outside it.
	var x0 := maxi(0, int(low.x * OCCLUSION_GRID))
	var x1 := mini(OCCLUSION_GRID - 1, int(high.x * OCCLUSION_GRID))
	var y0 := maxi(0, int(low.y * OCCLUSION_GRID))
	var y1 := mini(OCCLUSION_GRID - 1, int(high.y * OCCLUSION_GRID))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var point := Vector2((x + 0.5) / OCCLUSION_GRID, (y + 0.5) / OCCLUSION_GRID)
			# Barycentric, so a cell counts only where its middle is really
			# covered rather than merely near.
			var wa := (sb - point).cross(sc - point) / area
			var wb := (sc - point).cross(sa - point) / area
			var wc := (sa - point).cross(sb - point) / area
			if wa < 0.0 or wb < 0.0 or wc < 0.0:
				continue
			var depth := a.z * wa + b.z * wb + c.z * wc
			var cell := Vector2i(x, y)
			if not buffer.has(cell) or depth > buffer[cell]:
				buffer[cell] = depth


## The sleeve has to run off the edge of the picture rather than stop in mid-air.
##
## `hazmat_hand.glb` is a forearm and ends in a flat, open cut about seventy
## centimetres from the fingertips. At rest that is behind the lens and nobody
## ever sees it; swung across the frame to grip, it turns to face the camera and
## is drawn as an arm sliced off in mid-air. The upper arm
## (`PlayerViewModel.UPPER_ROTATION`) is a second copy of the same mesh carrying
## the sleeve on past that cut, and this is what says it is doing its job: the
## far end of the whole limb is outside the picture, so wherever the arm ends,
## the player cannot see it end.
func _check_the_arm_reaches_the_shoulder() -> void:
	var upper := _view_model.get_node_or_null("Right/Upper")
	if upper == null:
		_fail("the right arm has no upper arm; its cut end will show")
		return
	if _meshes_under(upper).is_empty():
		_fail("the upper arm has no mesh")
		return

	var far: Variant = _limb_far_end()
	if far == null:
		_fail("the arm has no geometry to measure")
		return
	var point: Vector3 = far
	if point.z >= 0.0:
		_say("the arm runs back behind the lens, which is off screen by itself")
		return
	var where := _screen_position(point)
	_say("the far end of the arm is at (%.2f, %.2f) of the frame" % [where.x, where.y])
	var outside := where.x < -ELBOW_MARGIN or where.x > 1.0 + ELBOW_MARGIN \
		or where.y < -ELBOW_MARGIN or where.y > 1.0 + ELBOW_MARGIN
	if not outside:
		_fail("the arm ends inside the picture; the player will see the cut")


## One squeeze, and the arm has to have felt it.
func _squeeze() -> void:
	_hands.press_secondary()
	_view_model.punch()


## The squeeze drives the fist forward. It is the arm's half of the recoil the
## camera already takes, and without it a squeeze is something the player reads
## in the HUD rather than sees in his hand.
func _check_squeeze_moved_the_arm() -> void:
	# Measured on the frame after the punch, before the damping has spent it.
	var thrust := _hand_centre()
	_view_model.punch()
	_view_model.advance(1.0 / 60.0)
	var moved := thrust.distance_to(_hand_centre())
	_say("a squeeze moves the fist by %.3f m" % moved)
	if is_zero_approx(moved):
		_fail("the squeeze does not reach the arm")


## He strangles it, which is the ordinary way a hold ends.
##
## Squeezed to death rather than cancelled, because the hands have no cancel of
## their own — the whole point of them is that letting go is something the
## player does by *stopping*, and the two endings a hold really has are the
## animal dying and the animal getting loose (`hands.gd: _release`).
func _kill_it_and_watch_it_being_put_away() -> void:
	for i in _hands.squeezes_to_kill + 2:
		_hands.press_secondary()
		if not _hands.is_busy():
			break
	if _hands.is_busy():
		_fail("the rat would not die; there is no gesture to measure")
		return

	# The whole gesture is walked here, in one step, and the checks below only
	# read what this walk wrote down. It is not how the rest of the bench is
	# written and the reason is the clock: everything before this is a pose that
	# travels to its end and stays there, so a check can be its own step and take
	# its reading whenever it happens to run. The stowing has a beginning, a
	# bottom and an end, and it started ticking on the squeeze above — split
	# across four steps with twelve idle frames between each, it was over before
	# the third of them looked at it, and what they measured was an arm already
	# back at rest.
	_dead_grip = _view_model.grip()
	_dead_stow = _view_model.stow()

	# Through the slump, and no further: the fist is still up in the middle of
	# the screen with the dead animal in it.
	var wait: float = _rat.LIMP_TIME if "LIMP_TIME" in _rat else 0.0
	_advance(int(wait / FRAME))
	_limp_gap = _hand_centre().distance_to(_held_body_point())
	_falling_from = _hand_centre()
	# Pictures are taken from inside the walk for the same reason the readings
	# are: the gesture is a clock, and a step of its own would photograph it
	# somewhere it had already been.
	_shoot("dead-in-hand")

	# Down, frame by frame, watching for the bottom of the travel rather than
	# counting to it: what the checks want is the lowest the hand gets and how
	# far it was from the body there, and the fraction is what says when that is.
	_lowest_screen = -INF
	_fallen_stow = 0.0
	_fallen_to = _hand_centre()
	_fallen_gap = INF
	var fall: float = _rat.STOW_TIME if "STOW_TIME" in _rat else 0.0
	var frames := int(fall / FRAME) + 2
	for i in frames:
		_advance(1)
		_lowest_screen = maxf(_lowest_screen, _screen_position(_hand_centre()).y)
		var reached := _view_model.stow()
		if reached < _fallen_stow:
			break
		_fallen_stow = reached
		_fallen_to = _hand_centre()
		# The gap is read here, on the way down, because the rat is only there to
		# be measured against while it is still travelling: it is freed at the
		# end of its own stowing (`rat.gd: _process_stow`), and a check that
		# waited would have nothing left to compare the hand with.
		if is_instance_valid(_rat):
			_fallen_gap = minf(_fallen_gap, _fallen_to.distance_to(_rat_body_centre()))
		if i == int(frames / 2):
			_shoot("going-down")

	# And back up. Generously past the end of the rise, and the grip's own travel
	# home on top of it: the hand only opens at the top.
	_shoot("at-the-belt")
	var rise: float = _hands.RISE_TIME if "RISE_TIME" in _hands else 0.5
	_advance(int(rise / FRAME) + 40)


## The killing squeeze does not open the hand.
##
## This is the check the whole change exists for, and it is about the frame after
## the kill rather than the end of the gesture, because that is the frame the old
## code got wrong: `finished` fired, the grip was aimed back at its resting
## corner, and from there the hand was leaving whatever the body did afterwards.
## The fist has to still be closed, and it has to not have started down yet — the
## rat spends `Rat.LIMP_TIME` going limp in it, and an arm that set off during
## the slump would pull the body out of the frame before the player saw it die.
func _check_fist_keeps_the_dead_rat() -> void:
	_say("on the frame after the kill the hand is %.0f%% closed and %.0f%% stowed"
		% [_dead_grip * 100.0, _dead_stow * 100.0])
	if not is_equal_approx(_dead_grip, 1.0):
		_fail("the hand opened on the killing squeeze; the corpse will drop out of it")
	if not is_zero_approx(_dead_stow):
		_fail("the arm set off before the body had gone limp")
	_say("with the body limp in it the fist is %.2f m from the rat" % _limp_gap)
	if _limp_gap > GRIP_REACH:
		_fail("the fist came off the dead rat while it was going limp (%.2f m)" % _limp_gap)


## The hand went down, and it went down *with the body* rather than away from it.
##
## Both halves matter and only the second is about the fix. An arm that merely
## dropped would pass any check that asked whether it moved — the failure being
## guarded against is precisely a hand that leaves while the rat goes on
## travelling — so what is measured is how near the two ever got on the way down,
## in the same metres `_check_fist_on_rat` uses at the top of the gesture.
func _check_the_rat_went_down_with_the_hand() -> void:
	var dropped := _falling_from.y - _fallen_to.y
	_say("the arm carried the body %.2f m down, and got %.0f%% stowed"
		% [dropped, _fallen_stow * 100.0])
	if dropped <= 0.0:
		_fail("the arm did not go down at all; there is no stowing gesture")
	if _fallen_stow < 0.99:
		_fail("the arm never finished going down (%.2f)" % _fallen_stow)
	if is_inf(_fallen_gap):
		_say("the body was freed before the descent could be measured against it")
		return
	_say("on the way down the fist came within %.2f m of the body" % _fallen_gap)
	if _fallen_gap > STOW_REACH:
		_fail("the hand left the body behind on the way down (%.2f m)" % _fallen_gap)


## And it took it out of the picture. This is what "the player puts it away"
## means on screen: the glove goes past the bottom edge of the frame, so what
## comes back up is unmistakably a hand that stowed something rather than one
## that opened in mid-air.
func _check_the_hand_left_the_frame() -> void:
	_say("at its lowest the fist is drawn at %.2f of the frame" % _lowest_screen)
	if _lowest_screen < 1.0:
		_fail("the hand never left the bottom of the picture (%.2f); the rat vanishes on screen"
			% _lowest_screen)


## The hand comes back to where it hangs, and comes back with nothing in it. It
## is the same pose the view model bench measures standing, so a grip or a stow
## that leaked into the rest pose would break both benches — which is the point
## of asking here as well.
func _check_hand_came_back_empty() -> void:
	_say("at the end of the gesture the hand is %.0f%% closed and %.0f%% stowed"
		% [_view_model.grip() * 100.0, _view_model.stow() * 100.0])
	if not is_zero_approx(_view_model.stow()):
		_fail("the arm never came back up from the belt")
	if not is_zero_approx(_view_model.grip()):
		_fail("the hand stayed closed on a rat that is gone")
	var drift := _rest_hand.distance_to(_hand_centre())
	_say("and it is %.3f m from where it started" % drift)
	if drift > 0.05:
		_fail("the hand did not come back to its resting pose (%.3f m out)" % drift)


# --- Measuring -------------------------------------------------------------

## The middle of the hand — the narrow end of the mesh, as opposed to the sleeve
## — in camera space.
##
## It is read off the drawn geometry rather than computed from the exported
## numbers, so that the bench measures where the hand *is* rather than agreeing
## with the arithmetic that put it there.
func _hand_centre(side := "Right") -> Vector3:
	var ends := _arm_ends(side)
	if ends.is_empty():
		return Vector3.ZERO
	# The far end is the hand; back off a little towards the elbow to land on the
	# palm rather than on the fingertips.
	var elbow: Vector3 = ends[0]
	var tip: Vector3 = ends[1]
	return tip.lerp(elbow, 0.25)


## Where the rat's body is held, in camera space: the capture point itself,
## which is what the animal's middle is pinned to (`rat.gd: _anchor`).
func _held_body_point() -> Vector3:
	return _camera.global_transform.affine_inverse() * _capture_point.global_position


## Where the rat's body actually is, in camera space — the animal's own middle
## rather than the point it hangs from.
##
## `_held_body_point` is the capture point, which is fixed in front of the lens
## and is the right reading while the rat is held there. It is the wrong one once
## the body is being stowed: the carcass travels away from that point down to the
## waist under its own steam, so a bench asking whether the hand followed the rat
## has to ask where the rat went, not where it was picked up.
func _rat_body_centre() -> Vector3:
	var into_camera := _camera.global_transform.affine_inverse()
	var model := _rat.get_node_or_null("Model")
	if model != null:
		return into_camera * (model as Node3D).global_position
	return into_camera * _rat.global_position


## How wide the glove is drawn, as a fraction of the frame.
##
## Taken from the mesh's own bounds through the live transform rather than from
## the exported numbers, so it follows `grip_scale` and the perspective at
## whatever depth the fist ended up — which is the whole point of the check.
func _glove_width_on_screen() -> float:
	var arm := _view_model.get_node_or_null("Right/Hand")
	if arm == null:
		return 0.0
	var meshes := _meshes_under(arm)
	if meshes.is_empty():
		return 0.0
	var mesh := meshes[0]
	var bounds := mesh.get_aabb()
	var middle := bounds.get_center()
	var into_camera := _camera.global_transform.affine_inverse() * mesh.global_transform
	# Across the hand at the palm, which is the part that closes on the animal.
	var left := into_camera * Vector3(bounds.position.x, middle.y, 0.15)
	var right := into_camera * Vector3(bounds.end.x, middle.y, 0.15)
	return absf(_screen_position(right).x - _screen_position(left).x)


## How wide the rat's body is drawn, as a fraction of the frame — the same
## measurement, at the depth the animal is actually held.
##
## `RAT_WIDTH` is the animal's own width, and the animal in a hand is not drawn
## at its own size: it is held at `rat.gd: HELD_SCALE`, which is a scale on the
## whole node and therefore on the width too. Reading the constant alone
## compares the glove against a rat a good deal wider than the one on screen,
## and `MIN_GLOVE_WIDTH` then fails a pose the player would call correct.
func _rat_width_on_screen() -> float:
	var held := _rat.scale.x if _rat != null and is_instance_valid(_rat) else 1.0
	var body := _held_body_point()
	var left := body + Vector3(-RAT_WIDTH * held * 0.5, 0.0, 0.0)
	var right := body + Vector3(RAT_WIDTH * held * 0.5, 0.0, 0.0)
	return absf(_screen_position(right).x - _screen_position(left).x)


## The far end of the whole limb — forearm and upper arm together — in camera
## space, or null with nothing to measure. It is the end the player must never
## see, because it is where the model's cut is.
func _limb_far_end() -> Variant:
	var arm := _view_model.get_node_or_null("Right")
	if arm == null:
		return null
	var meshes := _meshes_under(arm)
	if meshes.is_empty():
		return null
	var furthest: Variant = null
	for mesh in meshes:
		var bounds := mesh.get_aabb()
		var middle := bounds.get_center()
		var into_camera := _camera.global_transform.affine_inverse() * mesh.global_transform
		for z in [bounds.position.z, bounds.end.z]:
			var point := into_camera * Vector3(middle.x, middle.y, z)
			# The far end of the limb is the one nearest the lens: the arm runs
			# from the fingertips out in the screen towards the body behind.
			if furthest == null or point.z > (furthest as Vector3).z:
				furthest = point
	return furthest


## The two ends of the right arm in camera space, elbow first. The same reading
## the view model bench takes, and taken the same way.
func _arm_ends(side := "Right") -> Array:
	# The forearm alone, reached by name rather than by taking the first mesh
	# under the arm: the upper arm hangs under there too, and which of them comes
	# back first is the scene's ordering rather than anything this bench should
	# depend on. The elbow being measured is the forearm's.
	var arm := _view_model.get_node_or_null(side + "/Hand")
	if arm == null:
		return []
	var meshes := _meshes_under(arm)
	if meshes.is_empty():
		return []
	var mesh := meshes[0]
	var bounds := mesh.get_aabb()
	var middle := bounds.get_center()
	var into_camera := _camera.global_transform.affine_inverse() * mesh.global_transform
	var a := into_camera * Vector3(middle.x, middle.y, bounds.position.z)
	var b := into_camera * Vector3(middle.x, middle.y, bounds.end.z)
	# The camera looks down its own -Z, so the *smaller* z is the end further
	# into the screen, and that end is the hand. The elbow is the other one.
	return [a, b] if a.z > b.z else [b, a]


## `frames` frames of the arm's own movement, at the fixed step everything in
## here is counted in.
func _advance(frames: int) -> void:
	if _view_model == null:
		return
	for i in frames:
		_view_model.advance(FRAME)


func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_meshes_under(child))
	return found


## Where a point in camera space lands on screen, from 0 to 1 in each axis.
func _screen_position(local: Vector3) -> Vector2:
	var size := Vector2(_camera.get_viewport().get_visible_rect().size)
	return _camera.unproject_position(_camera.global_transform * local) / size


## A picture, on the runs that have a window. It is the only judge of whether
## the hand *looks* like it is holding the animal, which no number can say.
func _shoot(name: String) -> void:
	if not _shots:
		return
	var image := root.get_texture().get_image()
	var path := "user://grip-%s.png" % name
	image.save_png(path)
	_say("wrote %s" % ProjectSettings.globalize_path(path))


func _say(line: String) -> void:
	print("  ", line)


func _fail(reason: String) -> void:
	_failures += 1
	print("FAIL: ", reason)


func _report() -> void:
	if _failures == 0:
		print("grip bench: all good")
	else:
		print("grip bench: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)
