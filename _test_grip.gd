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

## How wide the rat's body is, in metres. Measured across the shoulders, which
## is the part the fist closes on — not the length, which is what fills the
## frame.
const RAT_WIDTH := 0.12

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
		11: _check_the_arm_reaches_the_shoulder()
		12: _shoot("gripping")
		13: _squeeze()
		14: _check_squeeze_moved_the_arm()
		15: _kill_it_and_watch_it_being_put_away()
		16: _check_fist_keeps_the_dead_rat()
		17: _check_the_rat_went_down_with_the_hand()
		18: _check_the_hand_left_the_frame()
		19: _check_hand_came_back_empty()
		20: _shoot("released")
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


## The elbow stays out of the picture. This is the failure reaching the arm out
## risks, and the reason the rat was brought closer rather than the arm sent
## further: a forearm that crosses the middle of the frame reads as an arm
## stretching for something instead of a hand holding it.
func _check_elbow_out_of_shot() -> void:
	var ends := _arm_ends()
	if ends.is_empty():
		_fail("the arm has no mesh to measure")
		return
	var elbow: Vector3 = ends[0]
	var depth := -elbow.z
	_say("gripping, the elbow is %.2f m in front of the lens" % depth)
	if depth >= ELBOW_DEPTH:
		# Far enough out that the foreshortening is gone: a forearm there is
		# simply a forearm, wherever it sits.
		return
	var where := _screen_position(elbow)
	_say("gripping, the elbow is at (%.2f, %.2f) of the frame" % [where.x, where.y])
	var outside := where.x < -ELBOW_MARGIN or where.x > 1.0 + ELBOW_MARGIN \
		or where.y < -ELBOW_MARGIN or where.y > 1.0 + ELBOW_MARGIN
	if not outside:
		_fail("the elbow is close to the lens and inside the picture; the sleeve will fill the screen")


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
func _hand_centre() -> Vector3:
	var ends := _arm_ends()
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
func _rat_width_on_screen() -> float:
	var body := _held_body_point()
	var left := body + Vector3(-RAT_WIDTH * 0.5, 0.0, 0.0)
	var right := body + Vector3(RAT_WIDTH * 0.5, 0.0, 0.0)
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
func _arm_ends() -> Array:
	# The forearm alone, reached by name rather than by taking the first mesh
	# under the arm: the upper arm hangs under there too, and which of them comes
	# back first is the scene's ordering rather than anything this bench should
	# depend on. The elbow being measured is the forearm's.
	var arm := _view_model.get_node_or_null("Right/Hand")
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
