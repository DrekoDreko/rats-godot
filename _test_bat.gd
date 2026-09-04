extends SceneTree
## Bat bench: the player swings on the click, whether or not there is anything
## in front of him, and what he hits dies of it.
##
## Run headless for the numbers:
##   godot --headless --script _test_bat.gd
## Run with a window to also get pictures of the bat carried, mid-swing and
## after the blow, which is the part no assertion can judge:
##   godot --script _test_bat.gd
##
## The bat is the first weapon the player *carries* — the hands were a pose and
## the traps go on the floor — so it is the first one that can be in the wrong
## place. Two different things have to be true at once and they are easy to get
## separately: the model has to be in the fist and travel with it, and the blow
## has to land on the animal in front of him.
##
## The questions, in the order the gesture happens:
##
## - **Taking it out puts it in the hand**, and putting it away takes it out
##   again. A bat left in the fist across a swap is a bat the player strangles
##   the next rat with.
## - **The bat is in the fist and not beside it.** It hangs off the forearm, so
##   this is measured against where the hand actually is rather than against the
##   camera — a model parented to the arm but posed in screen coordinates would
##   pass one and fail the other.
## - **It travels with the arm.** Turning the player moves the bat, which is the
##   whole reason it hangs off the arm rather than off the head with the weapon
##   node.
## - **A swing at nothing still swings.** This is the requirement the weapon is
##   written around: the miss is the game, and an arm that only moved when it was
##   going to connect would tell the player he had missed before he swung.
## - **A swing at a rat kills it**, and kills it *crushed* — the bat is the
##   opposite trade from the hands, and what it hands over is a body worth 40% of
##   the same animal (`scripts/economy/death.gd`).
## - **And the arm comes home.** A swing that left the arm cocked would be a
##   player permanently mid-blow.

## Frames of slack between one step and the next.
const WAIT := 12
## The step the bench counts time in. Fixed rather than the frame the engine
## actually took, for the reason `_test_grip.gd` gives at length: headless the
## loop turns over thousands of times a second, and the swing is a clock.
const FRAME := 1.0 / 60.0
## Where the bench stands the player, on open floor.
const STATION := Vector3(0.0, 0.1, 4.0)
## How far in front of him the rat is put. Inside the bat's reach with room to
## spare, and far enough that it is a swing rather than a nudge.
const RAT_AHEAD := 1.4
## Window size for the picture-taking run.
const SIZE := Vector2i(1141, 634)

## How far the bat's handle may sit from the middle of the fist and still count
## as being held, in metres.
##
## A hand is about ten centimetres across, so this is a palm's width and a
## little: near enough that the handle is inside the glove's silhouette, which is
## what "holding" means on screen. It is not asked to be exactly on the hand's
## centre — a fist wraps a handle off to one side of its own middle, which is
## where a hand goes.
const HELD_REACH := 0.16

## How near the middle of the frame the carried bat may come, as a fraction of
## it, measured from the centre out.
##
## The crosshair is what the player aims with and a weapon drawn across it is a
## weapon he cannot see past. It is the failure the pose went through twice — the
## first roll leaned the bat up and to the *left*, straight through the sights —
## and it is invisible to every other check here: a bat over the crosshair is
## still in the fist, still travels with the arm, and still kills what it hits.
const SIGHTS_CLEAR := 0.16

## How much of the frame the carried bat has to span sideways, as a fraction.
##
## It is the check against the bat pointing down the line of sight, where it is
## drawn end-on — a stick seen down its own length, a few percent of the frame
## wide, which reads as a smear rather than as a bat. Nothing about where it sits
## catches that: end-on and side-on put the handle in the same fist.
const MIN_WIDTH := 0.12

## Which way up and across the frame the bat has to run, from handle to head: up
## the screen, and to the right. Both are what a club looks like carried at rest,
## and the sign of the second is the one that was wrong to begin with.
const RISE := 0.15
const RIGHTWARD := 0.05

## How far the bat has to move when the player turns, in metres. A bat bolted to
## the world would not move at all, and one parented to the head would move
## differently from the hand it is supposed to be in.
const TRAVEL := 0.05

## How far into the swing the arm has to get for it to count as having swung, as
## a fraction. Well under one because the reading is taken a fixed number of
## frames in rather than at the peak, and the point is to tell a gesture from no
## gesture at all.
const SWUNG := 0.3

var _world: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _view_model: PlayerViewModel
var _bat: Node3D
var _inventory: Node
var _rat: Node3D

var _step := 0
var _clock := 0
var _failures := 0
var _shots := false

## Where the bat sat before the player turned, to prove it moved with him.
var _bat_before := Vector3.ZERO
## How far into the swing the arm got on the swing at nothing, and on the one
## that landed. Both recorded during the gesture, because an arm that swung and
## came home looks exactly like one that never swung once it is back.
var _miss_swing := 0.0
var _hit_swing := 0.0
## Whether the weapon said it had swung, on each of the two, and what it said
## about the blow. The miss has to fire the signal too — saying it missed — since
## it is the one the HUD beeps off.
var _miss_reported := false
var _miss_hit := false
var _hit_reported := false
var _hit_hit := false
## Whether the arm is being held at the top of its swing for the picture.
var _holding_peak := false


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
	_bat = _player.get_node("Head/BaseballBat")
	_inventory = _player.get_node("Head/Inventory")
	# Nothing is typed at him: every step below drives him by hand, and his own
	# frame is off so the bench is the only thing advancing the arm — see
	# `_test_grip.gd` for why both halves of that matter.
	_player.set_process_unhandled_input(false)
	_player.set_physics_process(false)
	_bat.used.connect(_on_used)


func _process(_delta: float) -> bool:
	if _holding_peak:
		# Re-swung and re-advanced to the same point rather than let run on: the
		# settle would carry the arm home between this step and the one that
		# takes the picture, and it is the peak that has to be photographed.
		_view_model.swing()
		_advance(_peak_frames())
	else:
		_advance(1)
	_clock += 1
	if _clock < WAIT:
		return false
	_clock = 0
	match _step:
		0: _stand_him_up()
		1: _check_empty_hand_carries_nothing()
		2: _put_the_bat_in_his_hand()
		3: _check_the_bat_came_out()
		4: _check_the_bat_is_in_the_fist()
		5: _check_the_bat_is_out_of_the_sights()
		6: _check_the_bat_reads_as_a_bat()
		7: _shoot("carried")
		8: _turn_him()
		9: _check_the_bat_went_with_him()
		10: _swing_at_nothing()
		11: _check_he_swung_anyway()
		12: _hold_the_peak()
		13: _shoot("swinging")
		14: _let_the_arm_come_home()
		15: _check_the_arm_came_home()
		16: _put_a_rat_in_front_of_him()
		17: _swing_at_the_rat()
		18: _check_the_rat_died_crushed()
		19: _shoot("landed")
		20: _put_the_bat_away()
		21: _check_the_hand_is_empty_again()
		_:
			_report()
			return true
	_step += 1
	return false


## Puts him on his mark. A step rather than a line in `_initialize`, because
## `global_position` on a node not yet in the tree is an error and a no-op.
func _stand_him_up() -> void:
	_player.global_position = STATION


## Before anything is taken out, the fist is empty. It is the state everything
## below is measured against, and it is also the belt's own starting position:
## the shift begins on the hands, and the hands carry nothing.
func _check_empty_hand_carries_nothing() -> void:
	var item := _view_model.held_item()
	if item != &"":
		_fail("the fist starts with '%s' in it, and should start empty" % item)
	else:
		_say("empty hand carries nothing")


## Hangs the bat on the belt and takes it out.
##
## Put on a loop by hand rather than bought, the way `_test_survey_house.gd`
## does: what is being measured is the weapon, and routing it through the shop
## would drag the wallet and the catalogue into a bench about a swing.
func _put_the_bat_in_his_hand() -> void:
	_inventory.slots[0] = _inventory.get_path_to(_bat)
	if not _inventory.equip(0):
		_fail("the belt would not give out the bat")


func _check_the_bat_came_out() -> void:
	if _inventory.current() != _bat:
		_fail("the bat is not the weapon in hand")
		return
	var item := _view_model.held_item()
	if item != &"BaseballBat":
		_fail("taking the bat out put '%s' in the fist" % item)
	else:
		_say("taking it out puts it in the hand")


## The handle has to be inside the glove. Both are read in world space off their
## own meshes, so this is the real distance between the two models rather than
## the offset that was asked for.
func _check_the_bat_is_in_the_fist() -> void:
	var grip := _bat_grip()
	var fist := _hand_centre()
	if grip == Vector3.INF or fist == Vector3.INF:
		_fail("could not find the bat or the hand in the view model")
		return
	var gap := grip.distance_to(fist)
	if gap > HELD_REACH:
		_fail("the bat's handle is %.3f m from the fist, past %.3f" % [gap, HELD_REACH])
	else:
		_say("the handle is %.3f m from the middle of the fist" % gap)


## The bat stays out of the crosshair.
##
## Asked of every corner of the model rather than of the handle and the head,
## because the fat end of a bat is what would cover the sights and it is neither
## of the two points the other checks read. The whole box has to clear the
## middle; the nearest corner to it is what is reported, so a pose that is
## creeping in says so before it arrives.
func _check_the_bat_is_out_of_the_sights() -> void:
	var box := _bat_on_screen()
	if box == Rect2():
		_fail("could not put the bat on the screen")
		return
	var sights := Rect2(Vector2(0.5, 0.5) - Vector2.ONE * SIGHTS_CLEAR,
			Vector2.ONE * SIGHTS_CLEAR * 2.0)
	if box.intersects(sights):
		_fail("the carried bat crosses the sights: it spans x %.2f..%.2f y %.2f..%.2f, and the crosshair needs %.2f clear"
				% [box.position.x, box.end.x, box.position.y, box.end.y, SIGHTS_CLEAR])
	else:
		_say("the bat clears the sights, spanning x %.2f..%.2f y %.2f..%.2f"
				% [box.position.x, box.end.x, box.position.y, box.end.y])


## It reads as a bat: broad enough on screen to have a silhouette, and running up
## and to the right the way a club is carried.
##
## The width is the check against the bat pointing away down the line of sight,
## where it is drawn end-on and a third of the frame of bat becomes a smudge a
## few pixels across. The direction is the one the first pose got backwards.
func _check_the_bat_reads_as_a_bat() -> void:
	var box := _bat_on_screen()
	if box == Rect2():
		_fail("could not put the bat on the screen")
		return
	if box.size.x < MIN_WIDTH:
		_fail("the bat is %.0f%% of the frame wide, under %.0f%% — it is drawn end-on"
				% [box.size.x * 100.0, MIN_WIDTH * 100.0])
	else:
		_say("the bat spans %.0f%% of the frame sideways" % (box.size.x * 100.0))

	var handle := _on_screen(_bat_grip())
	var head := _on_screen(_bat_tip())
	if handle == Vector2.INF or head == Vector2.INF:
		_fail("the bat's ends are not both on screen")
		return
	# Screen y grows downwards, so the head being *up* is a smaller y.
	var rise := handle.y - head.y
	var across := head.x - handle.x
	if rise < RISE:
		_fail("the bat rises %.2f of the frame from handle to head, under %.2f" % [rise, RISE])
	elif across < RIGHTWARD:
		_fail("the bat leans %.2f across, and should run up and to the right by %.2f"
				% [across, RIGHTWARD])
	else:
		_say("it runs up %.2f and right %.2f of the frame, handle to head" % [rise, across])


## Turns him. It is the head that turns and not the body, because the arms hang
## off the camera and it is the camera the bat has to follow.
func _turn_him() -> void:
	_bat_before = _bat_grip()
	_player.get_node("Head").rotation.y += deg_to_rad(35.0)
	_advance(2)


## A bat in the hand goes where the hand goes. It is the whole reason the model
## hangs off the forearm rather than off the head with the weapon node.
func _check_the_bat_went_with_him() -> void:
	var moved := _bat_grip().distance_to(_bat_before)
	if moved < TRAVEL:
		_fail("the bat moved %.3f m when he turned, under %.3f — it is not in his hand" % [moved, TRAVEL])
	else:
		_say("the bat travelled %.3f m with the turn" % moved)


## The swing the whole weapon is written around: nothing in front of him, and he
## swings all the same.
func _swing_at_nothing() -> void:
	_miss_reported = false
	_bat.try_use()
	# Read part way through the gesture rather than at its end: an arm that swung
	# and came home reads exactly like one that never moved.
	_advance(6)
	_miss_swing = _view_model.swing_progress()


func _check_he_swung_anyway() -> void:
	if not _miss_reported:
		_fail("swinging at nothing said nothing — the HUD would never hear the miss")
	elif _miss_hit:
		_fail("swinging at nothing reported a hit")
	elif _miss_swing < SWUNG:
		_fail("the arm got %.2f into a swing at nothing, under %.2f" % [_miss_swing, SWUNG])
	else:
		_say("swinging at nothing swings: %.2f through, reported as a miss" % _miss_swing)


## Swings, and leaves the arm parked at the far end of the follow-through so the
## next step can photograph it.
##
## The picture is a step later rather than the last line of this one because the
## texture read back is the frame the engine has *already drawn*: posing the arm
## and shooting in the same breath photographs the pose before it, which is how
## an arc that took the bat clean off the screen came back looking like a bat
## that had not moved.
##
## Parking it is what makes that safe. `_process` advances the arm a frame at a
## time and the settle would carry it home inside the twelve idle frames between
## two steps, so the clock is wound back to the peak on every one of them until
## the picture has been taken.
func _hold_the_peak() -> void:
	_wait_out_the_cadence()
	_bat.try_use()
	_advance(_peak_frames())
	_holding_peak = true


## Lets the whole gesture run out — the wind-up, the blow and the settle back.
func _let_the_arm_come_home() -> void:
	_holding_peak = false
	_advance(60)


func _check_the_arm_came_home() -> void:
	var left := _view_model.swing_progress()
	if not is_zero_approx(left):
		_fail("the arm is still %.2f into a swing a second after it" % left)
	else:
		_say("the arm comes home")


## Stands a live rat in front of him and turns him onto it.
##
## The player is moved to the animal rather than the other way about, and it is a
## live rat rather than a target: it bolts from the man the moment it notices
## him, and what is being measured is a swing at the thing the game actually puts
## in front of the player.
func _put_a_rat_in_front_of_him() -> void:
	_rat = load("res://scenes/rat.tscn").instantiate()
	_world.get_node("Rats").add_child(_rat)
	_rat.global_position = STATION + Vector3(0.0, 0.0, -RAT_AHEAD)
	_advance(1)
	_aim_at_the_rat()


func _aim_at_the_rat() -> void:
	var target := _rat.global_position + Vector3.UP * 0.2
	_player.global_position = _rat.global_position + Vector3(0.0, STATION.y, RAT_AHEAD)
	# The body turns to face it and only the head looks down — the same split the
	# player himself has (`player.gd`), and it is the head's half that matters
	# here: his eyes are 1.6 m up and the animal is on the floor, so a man looking
	# level down the corridor has it outside his cone and swings at nothing
	# (`weapon.gd: angle`).
	_player.look_at(Vector3(target.x, _player.global_position.y, target.z), Vector3.UP)
	_player.rotation.x = 0.0
	_player.rotation.z = 0.0
	var head: Node3D = _player.get_node("Head")
	# The head is put back level as well as pitched, because the step that turned
	# him to prove the bat travels left a yaw on it that nothing else undoes.
	head.rotation = Vector3.ZERO
	var eyes := _camera.global_position
	var flat := Vector2(target.x - eyes.x, target.z - eyes.z).length()
	head.rotation.x = atan2(target.y - eyes.y, flat)
	_advance(2)


func _swing_at_the_rat() -> void:
	_hit_reported = false
	if not _wait_out_the_cadence():
		_fail("the bat never came off its cadence")
		return
	_aim_at_the_rat()
	_bat.try_use()
	_advance(6)
	_hit_swing = _view_model.swing_progress()


## The blow lands, and it lands as a *crushing*. The death is what the carcass is
## worth, and it is the whole trade the bat is: one click against the hands' slow
## job, and a body worth 40% of the same animal.
func _check_the_rat_died_crushed() -> void:
	if not _hit_reported:
		_fail("the swing that landed said nothing")
		return
	if not _hit_hit:
		_fail("swinging at a rat in reach reported a miss")
		return
	if _hit_swing < SWUNG:
		_fail("the arm got %.2f into the swing that landed, under %.2f" % [_hit_swing, SWUNG])
	if not _rat.is_dead():
		_fail("the rat took a bat to the head and is still alive")
		return
	var death: int = _bat.death_type
	if death != Death.Type.CRUSHING:
		_fail("the bat kills with '%s', and should crush" % Death.name_of(death))
		return
	_say("the rat died of %s, worth %d%% of the animal"
			% [Death.name_of(death), int(Death.multiplier(death) * 100.0)])


func _put_the_bat_away() -> void:
	_inventory.equip_hands()


## Putting it away empties the fist. Without this the bat rides into the next
## grab and the player strangles a rat with a club still in his hand.
func _check_the_hand_is_empty_again() -> void:
	var item := _view_model.held_item()
	if item != &"":
		_fail("putting the bat away left '%s' in the fist" % item)
	else:
		_say("putting it away empties the hand")


## The weapon reporting a swing. Which of the two it was is read off the step
## rather than kept as a flag on the weapon: the bench is the one that knows
## which swing it just asked for.
func _on_used(hit: bool) -> void:
	if _step <= 11:
		_miss_reported = true
		_miss_hit = hit
	else:
		_hit_reported = true
		_hit_hit = hit


# --- Reading the models ----------------------------------------------------

## Where the bat's handle is, in world space: the end of the model the hand
## closes on.
##
## The mesh runs up its own +Y with the grip at the bottom (`min.y` of the
## exported bounds), so the handle is the low end of the AABB taken through the
## node's own transform. Read off the mesh rather than off the node's origin
## because the origin is the exporter's business and the handle is the model's.
func _bat_grip() -> Vector3:
	var bat := _view_model.get_node_or_null("Right/Hold/BaseballBat")
	if bat == null:
		return Vector3.INF
	var meshes := _meshes_under(bat)
	if meshes.is_empty():
		return Vector3.INF
	var mesh := meshes[0]
	var bounds := mesh.get_aabb()
	var handle := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	return mesh.global_transform * handle


## The middle of the palm, in world space. The forearm alone, reached by name
## rather than by taking the first mesh under the arm: the upper arm hangs under
## there too, and which comes back first is the scene's ordering rather than
## anything this bench should depend on.
func _hand_centre() -> Vector3:
	var arm := _view_model.get_node_or_null("Right/Hand")
	if arm == null:
		return Vector3.INF
	var meshes := _meshes_under(arm)
	if meshes.is_empty():
		return Vector3.INF
	var mesh := meshes[0]
	var bounds := mesh.get_aabb()
	# The model runs from its elbow at -Z to its fingertips at +Z. The far end is
	# the hand; back off towards the elbow to land on the palm.
	var elbow := Vector3(bounds.get_center().x, bounds.get_center().y, bounds.position.z)
	var tip := Vector3(bounds.get_center().x, bounds.get_center().y, bounds.end.z)
	return mesh.global_transform * tip.lerp(elbow, 0.25)


## The far end of the bat — the head, the part that hits things — in world space.
## It is the end whose travel across the screen is what a swing actually looks
## like: the handle barely moves, being in the fist the arm turns about.
func _bat_tip() -> Vector3:
	var bat := _view_model.get_node_or_null("Right/Hold/BaseballBat")
	if bat == null:
		return Vector3.INF
	var meshes := _meshes_under(bat)
	if meshes.is_empty():
		return Vector3.INF
	var mesh := meshes[0]
	var bounds := mesh.get_aabb()
	var head := Vector3(bounds.get_center().x, bounds.end.y, bounds.get_center().z)
	return mesh.global_transform * head


## The box the carried bat covers on screen, as fractions of the frame.
##
## Every corner of the model's bounds is projected rather than the two ends,
## because the fat end of the bat is off the axis the ends sit on and it is the
## part that would cover the sights. An empty rect is a bat that is not on the
## screen at all.
func _bat_on_screen() -> Rect2:
	var bat := _view_model.get_node_or_null("Right/Hold/BaseballBat")
	if bat == null:
		return Rect2()
	var meshes := _meshes_under(bat)
	if meshes.is_empty():
		return Rect2()
	var mesh := meshes[0]
	var bounds := mesh.get_aabb()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for corner in 8:
		var point := _on_screen(mesh.global_transform * bounds.get_endpoint(corner))
		if point == Vector2.INF:
			continue
		lo = Vector2(minf(lo.x, point.x), minf(lo.y, point.y))
		hi = Vector2(maxf(hi.x, point.x), maxf(hi.y, point.y))
	if lo.x == INF:
		return Rect2()
	return Rect2(lo, hi - lo)


## A world point as a fraction of the frame, or `Vector2.INF` for one behind the
## lens — where `unproject_position` gives an answer that looks like a position
## and is not one.
func _on_screen(world: Vector3) -> Vector2:
	if world == Vector3.INF:
		return Vector2.INF
	var local: Vector3 = _camera.global_transform.affine_inverse() * world
	if -local.z <= _camera.near:
		return Vector2.INF
	var frame := Vector2(_camera.get_viewport().get_visible_rect().size)
	if frame.x <= 0.0 or frame.y <= 0.0:
		return Vector2.INF
	return _camera.unproject_position(world) / frame


func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child in node.get_children():
		found.append_array(_meshes_under(child))
	return found


# --- Bench plumbing --------------------------------------------------------

## Runs the bat's cadence down until it will take another click, and says whether
## it got there.
##
## Waited out rather than cleared by hand: the cooldown is the weapon's own
## business, and a bench that zeroed it would be one that never noticed the day
## the cadence stopped working. Its clock is counted in `Weapon._process`, and
## the player's frame is switched off in here — so the bench is the one that has
## to turn it, exactly as it is the one that turns the arm.
func _wait_out_the_cadence() -> bool:
	var waited := 0
	while not _bat.is_ready() and waited < 240:
		_bat._process(FRAME)
		waited += 1
	return _bat.is_ready()


## How many frames it takes to reach the far end of the follow-through, which is
## where the bat is furthest across the frame and the only point of the gesture
## worth a picture.
func _peak_frames() -> int:
	return int((_view_model.swing_wind_time + _view_model.swing_follow_time) / FRAME)


func _advance(frames: int) -> void:
	if _view_model == null:
		return
	for i in frames:
		_view_model.advance(FRAME)


func _shoot(shot_name: String) -> void:
	if not _shots:
		return
	var image := root.get_texture().get_image()
	var path := "user://bat-%s.png" % shot_name
	image.save_png(path)
	_say("wrote %s" % ProjectSettings.globalize_path(path))


func _say(line: String) -> void:
	print("  ", line)


func _fail(reason: String) -> void:
	_failures += 1
	print("FAIL: ", reason)


func _report() -> void:
	if _failures == 0:
		print("bat bench: all good")
	else:
		print("bat bench: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)
