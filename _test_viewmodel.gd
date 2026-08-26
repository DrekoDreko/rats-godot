extends SceneTree
## View model bench: the player's own arms, in front of his camera.
##
## Run headless for the numbers:
##   godot --headless --script _test_viewmodel.gd
## Run with a window to also get pictures of the arms standing, walking and
## crouched, which is the part no assertion can make a judgement about:
##   godot --script _test_viewmodel.gd
##
## The arms are two rigid copies of `models/hazmat_hand.glb` posed by hand
## (`scripts/player_view_model.gd`), so what there is to get wrong is placement
## rather than skinning, and the bench asks in that order:
##
## - **There are two arms, and one of them is drawn.** Both meshes are in the
##   scene and neither casts a shadow — the body in the world already casts the
##   player's — and the left is hidden, which is what `PlayerViewModel.show_left`
##   asks for.
## - **They are a mirrored pair.** The left is the right with a negative `x`
##   scale, asked of it while it is hidden because that is the state it has to be
##   correct in: it is placed every frame so that showing it needs nothing else.
## - **The player cannot see his own body.** Nothing of the body model is drawn:
##   the whole of it is a shadow.
## - **The hand is in the frame.** Standing, crouched, looking down and mid-step:
##   in front of the near plane and inside the picture.
## - **The elbows are not through the lens.** A forearm that straddles the near
##   plane is drawn as a slab of sleeve across a quarter of the screen, which no
##   measurement of the hands alone would catch.
## - **The step reaches the arms.** The bob the camera rides is handed to them,
##   and a rig that ignored it would sit dead still over a swaying view.
##
## The crouch is the case worth the bench on its own: the camera comes down with
## the head, and the arms hang off the camera rather than off the body, so it is
## where a rest pose measured standing quietly goes wrong.

## Frames of slack between one step and the next. The crouch travels over
## several frames.
const WAIT := 12
## Where the bench stands the player: the map's own starting point, which is
## open floor by construction.
const STATION := Vector3(0.0, 0.1, 4.0)
## Window size for the picture-taking run.
const SIZE := Vector2i(1141, 634)
## How far outside the picture an elbow that sits close to the lens has to be, as
## a fraction of the frame.
##
## The elbow's place is out of shot: the forearm comes into the frame from a
## bottom corner and the joint is off screen behind it, which is what nearly
## every first-person game draws and what `PlayerViewModel.rest_offset` is set
## for. Being close to the lens is therefore not the failure — being close to
## the lens *and in the middle of the picture* is, because the triangles that
## straddle the near plane are clipped away and the sleeve behind them is drawn
## enormous, filling a quarter of the screen with flat yellow.
##
## So the question is asked in screen space rather than in metres, which is the
## lesson the pose sweep taught: an elbow ten centimetres from the lens looked
## alarming in the numbers and read perfectly in the picture, because it was a
## fifth of a frame outside the bottom corner. Measuring depth alone would have
## failed the pose that was actually right.
const ELBOW_MARGIN := 0.08

## How far in front of the lens an elbow has to be before where it sits on
## screen stops mattering, in metres. Past this the foreshortening is gone and a
## forearm crossing the middle of the picture is simply a forearm.
const ELBOW_DEPTH := 0.35

var _world: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _view_model: PlayerViewModel
var _model: Node3D
var _right: Node3D
var _left: Node3D

var _step := 0
var _clock := 0
var _failures := 0
var _shots := false


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
	_model = _player.get_node("Model")
	# Nothing is typed at him: every step below drives the body by hand.
	_player.set_process_unhandled_input(false)


func _process(_delta: float) -> bool:
	_clock += 1
	if _clock < WAIT:
		return false
	_clock = 0
	match _step:
		0: _stand_him_up()
		1: _check_arms_exist()
		2: _check_arms_mirrored()
		3: _check_body_hidden()
		4: _check_hands_in_frame("standing")
		5: _shoot("standing")
		6: _check_bob_reaches_arms()
		7: _check_hands_in_frame("mid-step")
		8: _shoot("mid-step")
		9: _crouch()
		10: _check_crouch_clear()
		11: _shoot("crouched")
		12: _look_down()
		13: _check_looking_down()
		14: _shoot("looking-down")
		_:
			_report()
			return true
	_step += 1
	return false


## Puts him on his mark. It is a step rather than a line in `_initialize`,
## because `global_position` on a node that is not in the tree yet is an error
## and a no-op — the scene has been instanced by then but not added.
func _stand_him_up() -> void:
	_player.global_position = STATION


## There are two arms, neither throwing a second shadow across everything the
## player looks at, and only the right one drawn.
func _check_arms_exist() -> void:
	_right = _view_model.get_node_or_null("Right")
	_left = _view_model.get_node_or_null("Left")
	if _right == null or _left == null:
		_fail("the view model is missing an arm")
		return
	var meshes := 0
	for arm in [_right, _left]:
		for mesh in _meshes_under(arm):
			meshes += 1
			var triangles := 0
			if mesh.mesh != null:
				triangles = mesh.mesh.get_faces().size() / 3
			_say("%s: %d triangles" % [arm.name, triangles])
			if triangles < 20:
				_fail("%s has only %d triangles — that is not an arm" % [arm.name, triangles])
			if mesh.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				_fail("%s casts a shadow, which the body is already doing" % arm.name)
	if meshes < 2:
		_fail("only %d arm mesh(es) in the view model" % meshes)
	# One hand on screen. Two of them this close crowd the bottom of the frame
	# between them, which is the whole reason the left is off (`show_left`).
	_say("right drawn: %s, left drawn: %s" % [_right.visible, _left.visible])
	if not _right.visible:
		_fail("the right hand is hidden — the player has no hands at all")
	if _left.visible != _view_model.show_left:
		_fail("the left hand is drawn against what show_left asks for")


## The left arm is the right one mirrored: the same mesh, turned inside out by a
## negative `x` scale, sitting the same distance the other side of the middle.
##
## It is asked while the left is hidden on purpose. That is the state it lives in
## today, and a mirror that quietly went wrong there would only be found by
## whoever turned the second hand on — long after whatever broke it.
func _check_arms_mirrored() -> void:
	if _right == null or _left == null:
		return
	_say("right at %.2v scale %.2v, left at %.2v scale %.2v"
		% [_right.position, _right.scale, _left.position, _left.scale])
	if _left.scale.x >= 0.0:
		_fail("the left arm is not mirrored — it will read as a second right hand")
	if not is_equal_approx(_right.position.x, -_left.position.x):
		_fail("the arms are not the same distance either side of the middle")
	if not is_equal_approx(_right.position.y, _left.position.y) \
			or not is_equal_approx(_right.position.z, _left.position.z):
		_fail("the arms are at different heights or depths")


## The body the player is standing in is drawn as a shadow and nothing else.
func _check_body_hidden() -> void:
	var body: MeshInstance3D = _model.mesh_instance()
	if body == null:
		_fail("the body model has no mesh")
		return
	if body.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		_fail("the player's own body is drawn, not just its shadow")


## The step the camera rides reaches the arms. It is asked by driving the bob
## straight rather than by walking the player into it: a bench that had to reach
## a full run first would be measuring the acceleration curve as much as this.
func _check_bob_reaches_arms() -> void:
	_view_model.bob(0.0, 0.0)
	var still := _right.position
	# A quarter through the cycle is the top of the step, which is where the
	# vertical swing is at its largest.
	_view_model.bob(PI * 0.5, 1.0)
	var stepping := _right.position
	_say("bob moves the arm by %.3v" % (stepping - still))
	if stepping.is_equal_approx(still):
		_fail("the step never reaches the arms — they sit dead still over a swaying view")
	if absf(stepping.y - still.y) < 0.001:
		_fail("the step does not lift the arms")


func _crouch() -> void:
	Input.action_press("crouch")


## Crouched, the head comes down and the arms come with it — the case the rest
## pose was not measured in, and the one it is most likely to be wrong in.
func _check_crouch_clear() -> void:
	if not _player.is_crouching():
		_fail("the player did not crouch")
		return
	_check_hands_in_frame("crouched")


func _look_down() -> void:
	# Straight down: the one angle at which a first person body, if there were
	# one, would fill the screen with its own chest.
	var head: Node3D = _player.get_node("Head")
	head.rotation.x = deg_to_rad(-89.0)


func _check_looking_down() -> void:
	_check_hands_in_frame("looking down")


## The hands are where a pair of hands belongs: in front of the camera, inside
## the picture, and one to each side of it.
##
## The reading is taken off the mesh's own bounds rather than off a bone,
## because there are no bones: the model runs from its elbow at -Z to its
## fingertips at +Z, so the two ends of its `AABB` along that axis are the two
## joints this wants. Taken through each arm's own transform, the mirror
## included, so the left hand is measured where the left hand actually is.
func _check_hands_in_frame(where: String) -> void:
	if _right == null or _left == null:
		return
	# Only what is drawn is measured. A hidden hand is allowed to be anywhere —
	# it is placed for the day it is shown (`PlayerViewModel.show_left`), not for
	# the frame it is in now, and failing it for being off screen would be
	# failing it for doing as it was told.
	var drawn := [["right", _right]]
	if _left.visible:
		drawn.append(["left", _left])
	for side in drawn:
		var name: String = side[0]
		var arm: Node3D = side[1]
		var ends := _arm_ends(arm)
		if ends.is_empty():
			_fail("%s: the %s arm has no mesh to measure" % [where, name])
			continue
		var hand: Vector3 = ends[0]
		var elbow: Vector3 = ends[1]
		_say("%s: %s hand at %.2v (camera space)" % [where, name, hand])
		# Negative Z is forward in Godot's camera space, and the near plane is at
		# three centimetres — a hand closer than that is a hand not drawn at all.
		if hand.z > -_camera.near:
			_fail("%s: the %s hand is behind the near plane" % [where, name])
			continue
		var on_screen := _screen_position(hand)
		_say("%s: %s hand at (%.2f, %.2f) of the frame" % [where, name, on_screen.x, on_screen.y])
		# A generous frame: the hands are meant to come in from the bottom
		# corners, so this asks that they are *in* the picture rather than that
		# they are anywhere in particular in it. Tightening it would make the
		# bench fail every time somebody nudged the pose, which is a knob it is
		# supposed to leave alone.
		if on_screen.x < 0.0 or on_screen.x > 1.0:
			_fail("%s: the %s hand is off the side of the frame" % [where, name])
		if on_screen.y < 0.0 or on_screen.y > 1.0:
			_fail("%s: the %s hand is off the top or bottom of the frame" % [where, name])
		# And the elbow is out of the picture rather than across the middle of it.
		# See `ELBOW_MARGIN`: an elbow near the lens is fine where it belongs, off
		# the edge of the frame, and is a slab of sleeve where it does not.
		var depth := -elbow.z
		if depth <= 0.0:
			_say("%s: %s elbow %.2f m behind the lens" % [where, name, -depth])
		elif depth >= ELBOW_DEPTH:
			_say("%s: %s elbow %.2f m in front of the lens" % [where, name, depth])
		else:
			var elbow_screen := _screen_position(elbow)
			_say("%s: %s elbow %.2f m out, at (%.2f, %.2f) of the frame"
				% [where, name, depth, elbow_screen.x, elbow_screen.y])
			var outside := elbow_screen.x < -ELBOW_MARGIN or elbow_screen.x > 1.0 + ELBOW_MARGIN \
				or elbow_screen.y < -ELBOW_MARGIN or elbow_screen.y > 1.0 + ELBOW_MARGIN
			if not outside:
				_fail("%s: the %s elbow is %.2f m from the lens and inside the frame — the sleeve will fill it"
					% [where, name, depth])
	# One hand to each side, asked only when there are two up. Both on the same
	# side is what a mirror applied to the wrong axis does, and it is the exact
	# mistake `_place` exists to avoid — but with the left hidden there is no
	# crowding to catch, and `_check_arms_mirrored` is what guards the mirror.
	if not _left.visible:
		return
	var right_ends := _arm_ends(_right)
	var left_ends := _arm_ends(_left)
	if right_ends.is_empty() or left_ends.is_empty():
		return
	if right_ends[0].x <= 0.0 or left_ends[0].x >= 0.0:
		_fail("%s: both hands are on the same side of the screen" % where)


## The two ends of an arm in camera space, fingertips first and elbow second.
##
## The model points down its own +Z, so the ends are the `AABB`'s two faces on
## that axis, taken at the middle of each. Which of the two comes out in front
## of the camera is the arm's own business — it is turned to face the lens — so
## they are sorted by depth rather than assumed: the far one is the hand.
func _arm_ends(arm: Node3D) -> Array:
	var meshes := _meshes_under(arm)
	if meshes.is_empty():
		return []
	var mesh := meshes[0]
	var bounds := mesh.get_aabb()
	var middle := bounds.get_center()
	var into_camera := _camera.global_transform.affine_inverse() * mesh.global_transform
	var a := into_camera * Vector3(middle.x, middle.y, bounds.position.z)
	var b := into_camera * Vector3(middle.x, middle.y, bounds.end.z)
	# Deeper into the screen is further from the camera, and that is the hand.
	return [a, b] if a.z < b.z else [b, a]


## Every mesh under a node, flattened. The imported scene's shape is the
## importer's business, so it is walked rather than reached into by path.
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


## A picture, on the runs that have a window to draw in. It is the only judge of
## whether the arms *look* right, which is not something a number can say.
func _shoot(name: String) -> void:
	if not _shots:
		return
	var image := root.get_texture().get_image()
	var path := "user://viewmodel-%s.png" % name
	image.save_png(path)
	_say("wrote %s" % ProjectSettings.globalize_path(path))


func _say(line: String) -> void:
	print("  ", line)


func _fail(reason: String) -> void:
	_failures += 1
	print("FAIL: ", reason)


func _report() -> void:
	Input.action_release("crouch")
	if _failures == 0:
		print("view model bench: all good")
	else:
		print("view model bench: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)
