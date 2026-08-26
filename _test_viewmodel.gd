extends SceneTree
## View model bench: the player's own arms, in front of his camera.
##
## Run headless for the numbers:
##   godot --headless --script _test_viewmodel.gd
## Run with a window to also get pictures of the arms standing, walking and
## crouched, which is the part no assertion can make a judgement about:
##   godot --script _test_viewmodel.gd
##
## What it is here to catch is the whole reason the arms are cut out of the mesh
## rather than hidden by bone, so it asks the questions in that order:
##
## - **There are arms at all.** The cut kept triangles, and the surface it built
##   is still a skinned one — a mesh that lost `ARRAY_WEIGHTS` on the round trip
##   looks like arms right up until they are supposed to move.
## - **There is nothing but arms.** Every vertex left is weighted to the arm
##   chain. This is the assertion that fails the day somebody swaps the model for
##   one on a different rig, which would otherwise show up in the game as a torso
##   filling the screen.
## - **The player cannot see his own body.** Standing, crouched and looking
##   straight down — the three cases the arms were asked for — nothing of the
##   body model is drawn, because the whole of it is a shadow.
## - **The arms are playing what the body is playing.** One state goes to both,
##   so a gesture animated once is seen from inside and from outside.
##
## - **The hands are in the frame.** Standing, crouched and looking down, both
##   hands are in front of the near plane, inside the picture, and one to each
##   side of it. The last of those is not padding: the two shoulders come off the
##   exporter on different rest orientations, so a pose mirrored from one side to
##   the other puts both hands on the same side of the screen.
##
## The crouch is the case worth the bench on its own. The animation lowers the
## body by a third of a metre and pushes the head forward, and the arms hang off
## the camera rather than off the body — so this is where a rig welded to the
## body's shoulder would put a shoulder through the middle of the frame.

## Frames of slack between one step and the next. The crouch travels over
## several frames and an animation blend takes an eighth of a second.
const WAIT := 12
## Where the bench stands the player: the map's own starting point, which is
## open floor by construction.
const STATION := Vector3(0.0, 0.1, 4.0)
## Window size for the picture-taking run.
const SIZE := Vector2i(1141, 634)
## How far in front of the lens an elbow has to stay, in metres. Nearer than this
## and the forearm behind it is drawn as a wall of sleeve rather than as an arm —
## it is comfortably outside the near plane at three centimetres, because what is
## being avoided is not the clipping but the foreshortening in front of it.
const ELBOW_CLEARANCE := 0.22

var _world: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _view_model: Node3D
var _model: Node3D
var _arms: MeshInstance3D

## Where the hands were when the modifier last ran, in camera space. Read from
## inside the skeleton's own update, because there is no reading it from
## outside: a `SkeletonModifier3D` writes into the buffer the skin is built from,
## and `get_bone_global_pose` asked from another node hands back the pose the
## `AnimationPlayer` left — the arms as they hang, not the arms as they are
## drawn.
var _right_hand := Vector3.ZERO
var _left_hand := Vector3.ZERO
## And the elbows, which are what actually crowd the frame. A hand can sit
## comfortably in the corner of the picture while the forearm behind it has come
## through the near plane and filled half the screen with a slab of sleeve —
## which is precisely what the first crouch correction did, and what no
## measurement of the hands alone could have caught.
var _right_elbow := Vector3.ZERO
var _left_elbow := Vector3.ZERO
var _pose: ViewModelArmsPose

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
	_player.global_position = STATION


func _process(_delta: float) -> bool:
	_clock += 1
	if _clock < WAIT:
		return false
	_clock = 0
	match _step:
		0: _check_arms_exist()
		1: _check_arms_only()
		2: _check_body_hidden()
		3: _check_state_shared()
		4: _check_hands_in_frame("standing")
		5: _shoot("standing")
		6: _crouch()
		7: _check_crouch_clear()
		8: _shoot("crouched")
		9: _look_down()
		10: _check_looking_down()
		11: _shoot("looking-down")
		_:
			_report()
			return true
	_step += 1
	return false


## The cut produced a mesh, and it is still a skinned one.
func _check_arms_exist() -> void:
	var skeleton: Skeleton3D = _view_model.get_node_or_null(
		"Model/Hazmat/Armature/Skeleton3D"
	)
	if skeleton == null:
		_fail("the view model has no skeleton under it")
		return
	_arms = skeleton.get_node_or_null("Arms") as MeshInstance3D
	if _arms == null:
		_fail("the cut left no Arms mesh behind")
		return
	var mesh := _arms.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		_fail("the Arms mesh is empty")
		return
	var triangles: int = (mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	_say("arms: %d triangles" % triangles)
	if triangles < 20:
		_fail("only %d triangles survived the cut — that is not a pair of arms" % triangles)
	# The weights are the whole point: without them the arms are welded to the
	# rest pose and never move, which no picture of a still frame would show.
	var format := mesh.surface_get_format(0)
	if (format & Mesh.ARRAY_FORMAT_BONES) == 0 or (format & Mesh.ARRAY_FORMAT_WEIGHTS) == 0:
		_fail("the cut mesh lost its skin — the arms will not animate")
	if _arms.skin == null:
		_fail("the Arms mesh has no skin, so it is not bound to the skeleton")
	if _arms.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		_fail("the arms cast a shadow, which the body is already doing")
	# The pose that bends the arms into the frame, and the only place the bent
	# arms can be read from.
	_pose = skeleton.get_node_or_null("ArmsPose") as ViewModelArmsPose
	if _pose == null:
		_fail("the arms were never bent up into the frame — no ArmsPose modifier")
		return
	_pose.probed = _on_posed


## Nothing but arms survived: every vertex the cut kept belongs to the arm chain.
## This is the assertion that catches a rig swapped underneath the cut.
func _check_arms_only() -> void:
	if _arms == null:
		return
	var skeleton := _arms.get_parent() as Skeleton3D
	var arrays: Array = (_arms.mesh as ArrayMesh).surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var influences: int = bones.size() / maxi(vertices.size(), 1)

	var arm_ids := {}
	for bone_name in PlayerViewModel.ARM_BONES:
		var id := skeleton.find_bone(bone_name)
		if id < 0:
			_fail("no bone named %s in this rig" % bone_name)
		else:
			arm_ids[id] = true

	# Only the vertices the indices actually reach are checked: the cut keeps the
	# vertex buffer whole on purpose, so the torso's vertices are still in it —
	# unreferenced, unrendered, and not what this is asking about.
	var used := {}
	for i in indices:
		used[i] = true
	var strays := 0
	for vertex in used:
		var pull := 0.0
		for i in influences:
			if arm_ids.has(bones[vertex * influences + i]):
				pull += weights[vertex * influences + i]
		if pull < PlayerViewModel.ARM_WEIGHT:
			strays += 1
	_say("drawn vertices: %d, none-arm among them: %d" % [used.size(), strays])
	if strays > 0:
		_fail("%d drawn vertices are not weighted to the arms" % strays)


## The body the player is standing in is drawn as a shadow and nothing else, and
## the copy the arms were cut from is not drawn at all.
func _check_body_hidden() -> void:
	var body: MeshInstance3D = _model.mesh_instance()
	if body == null:
		_fail("the body model has no mesh")
		return
	if body.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
		_fail("the player's own body is drawn, not just its shadow")
	var source: MeshInstance3D = _view_model.get_node("Model").mesh_instance()
	if source != null and source.visible:
		_fail("the view model still draws the whole body behind its arms")


## One state reaches both bodies, so the arms play what the body plays.
func _check_state_shared() -> void:
	var body: PlayerModel = _model
	var arms_animation: StringName = _view_model.current_animation()
	_say("standing: body plays %s, arms play %s" % [body.current_animation(), arms_animation])
	if arms_animation != body.current_animation():
		_fail("the arms and the body are playing different animations")
	if arms_animation == &"":
		_fail("the arms are playing nothing at all")


func _crouch() -> void:
	Input.action_press("crouch")


## Crouched, the animation drops the body and pushes the head forward — the case
## the arms were asked for. Nothing of the body may reach the frame, and since
## the body is shadows-only that is asked of the arms instead: they are what is
## drawn, and they must still be in front of the camera rather than behind it.
func _check_crouch_clear() -> void:
	if not _player.is_crouching():
		_fail("the player did not crouch")
		return
	_say("crouched: body plays %s, arms play %s"
		% [_model.current_animation(), _view_model.current_animation()])
	if _view_model.current_animation() != _model.current_animation():
		_fail("crouched, the arms and the body are playing different animations")
	_check_hands_in_frame("crouched")


func _look_down() -> void:
	# Straight down: the one angle at which a first person body, if there were
	# one, would fill the screen with its own chest.
	var head: Node3D = _player.get_node("Head")
	head.rotation.x = deg_to_rad(-89.0)


func _check_looking_down() -> void:
	_check_hands_in_frame("looking down")


## The hands are where a pair of hands belongs: in front of the camera, below
## its middle, and one to each side of it.
##
## The numbers come from `_on_posed`, which the pose modifier calls with the
## skeleton once it has bent the arms — the only moment the reading is the one
## that will be drawn. Asked from out here it would be the animation's pose, in
## which both hands hang below and behind the head in every one of the five
## clips: a bench measuring that would report the hands off screen while the
## player could plainly see them, which is a worse failure than no bench at all.
func _check_hands_in_frame(where: String) -> void:
	if _right_hand.is_zero_approx() and _left_hand.is_zero_approx():
		_fail("%s: the pose modifier never reported where the hands are" % where)
		return
	_say("%s: right hand at %.2v, left at %.2v (camera space)" % [where, _right_hand, _left_hand])
	# Negative Z is forward in Godot's camera space, and the near plane is at
	# three centimetres — a hand closer than that is a hand not drawn at all.
	for hand in [["right", _right_hand], ["left", _left_hand]]:
		var name: String = hand[0]
		var at: Vector3 = hand[1]
		if at.z > -_camera.near:
			_fail("%s: the %s hand is behind the near plane" % [where, name])
			continue
		var on_screen := _screen_position(at)
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
	# And the elbows are behind the hands rather than through the lens. An elbow
	# that comes closer to the camera than the near plane is not clipped away
	# tidily: the triangles that straddle the plane are, and the sleeve behind
	# them is drawn enormous, filling a quarter of the screen with flat yellow.
	# `ELBOW_CLEARANCE` is where a slab of sleeve starts to be a slab rather than
	# an arm.
	for elbow in [["right", _right_elbow], ["left", _left_elbow]]:
		var name: String = elbow[0]
		var at: Vector3 = elbow[1]
		_say("%s: %s elbow %.2f m from the lens" % [where, name, -at.z])
		if at.z > -ELBOW_CLEARANCE:
			_fail("%s: the %s elbow is %.2f m from the lens — the sleeve will fill the frame"
				% [where, name, -at.z])
	# One hand to each side. Both on the same side is what a mirrored pose does
	# on a rig whose shoulders are not mirrors of each other, and it is the exact
	# mistake the separate left and right angles exist to prevent.
	if _right_hand.x <= 0.0 or _left_hand.x >= 0.0:
		_fail("%s: both hands are on the same side of the screen" % where)


## Where a point in camera space lands on screen, from 0 to 1 in each axis.
func _screen_position(local: Vector3) -> Vector2:
	var size := Vector2(_camera.get_viewport().get_visible_rect().size)
	return _camera.unproject_position(_camera.global_transform * local) / size


## Called by the pose modifier, from inside the skeleton's update.
func _on_posed(skeleton: Skeleton3D) -> void:
	var into_camera := _camera.global_transform.affine_inverse() * skeleton.global_transform
	_right_hand = into_camera * skeleton.get_bone_global_pose(
		skeleton.find_bone(&"mixamorig_RightHand")).origin
	_left_hand = into_camera * skeleton.get_bone_global_pose(
		skeleton.find_bone(&"mixamorig_LeftHand")).origin
	_right_elbow = into_camera * skeleton.get_bone_global_pose(
		skeleton.find_bone(&"mixamorig_RightForeArm")).origin
	_left_elbow = into_camera * skeleton.get_bone_global_pose(
		skeleton.find_bone(&"mixamorig_LeftForeArm")).origin


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
