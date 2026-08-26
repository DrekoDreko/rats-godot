class_name PlayerViewModel
extends Node3D
## The player's own arms, hanging off his camera: the only part of his body he
## is allowed to see.
##
## He is standing inside `PlayerModel` and looking out of it, so that model is
## drawn as a shadow and nothing else (`PlayerModel.set_shadows_only`). Without
## something to put in its place his hands are not in the world at all — and
## every gesture the game grows from here, a trap going down, a rat being
## squeezed, an arm going out, would happen off screen on the one machine that
## most needs to see it.
##
## This is that something. It is the *same scene* as the body everybody else
## sees, played by the same `AnimationPlayer` off the same states, with the
## torso, legs and head cut out of the mesh. That the animation is shared is the
## whole reason it is built this way rather than as a separate pair of hands: a
## swing animated once shows up in the third person and in the first, and
## neither `player.gd` nor anything in `scripts/weapons/` has to know there are
## two bodies.
##
## ## Why the mesh is cut rather than the bones hidden
##
## The obvious move is to scale the unwanted bones to nothing and let the arms
## stay. It does not work, and it is worth writing down why so that nobody
## spends an afternoon rediscovering it: a bone's transform is inherited by its
## children, and both `set_bone_pose_scale` and `set_bone_global_pose_override`
## collapse the whole chain below them. The arms hang off `Spine2`, which hangs
## off `Hips` — flattening the torso takes the arms down with it. There is no
## per-bone visibility in a `Skeleton3D`, because a skinned mesh has no such
## thing: the torso and the arms are one surface of one mesh, and a vertex
## belongs to bones by weight, not to a bone by name.
##
## So the cut is made where the difference actually lives — in the vertices. On
## the way up, the surface is rebuilt keeping only the triangles whose three
## corners are weighted to the arm chain (`ARM_BONES`), and the result is handed
## to a `MeshInstance3D` that shares the original's `Skin`. The skeleton still
## animates every bone; the torso's bones simply have nothing left attached to
## them.
##
## It is done once, at load, over 907 vertices and 400 triangles. There is no
## per-frame cost at all, and nothing in `models/hazmat.glb` had to be touched —
## which matters, because the same file is what dresses the four men in the van.
##
## ## Where it is drawn
##
## In the world, by the player's own camera, and not in a viewport of its own.
## That keeps the PS1 shader and the full-screen post-process working on the
## arms exactly as they work on everything else — a second camera compositing
## over the first would have to be taught both. The price is that an arm can
## clip into a wall the player is pressed against, which is what nearly every
## game of this vintage did too.

## The bones the arms are made of, and the cut is made at the *elbow* rather than
## at the shoulder: forearms, hands and fingers are kept, and the upper arms and
## shoulders go with the torso.
##
## That is not a detail, it is the difference between arms and a mess. The rig
## has to be pushed close enough to the lens for the hands to be in the frame, and
## at that distance an upper arm ends up four centimetres from it — near enough
## that the sleeve is drawn as a wall of flat yellow across a quarter of the
## screen, and near enough to straddle the near plane and be torn in half by it.
## It also happens to be what nearly every first-person game shows: a forearm
## coming in from the corner, never a shoulder. Cutting at the elbow leaves the
## upper arm to hold the geometry up out of sight while the visible part is only
## ever the half that reads properly this close.
##
## The names are Mixamo's, with the colon the exporter uses turned into an
## underscore on import. They are matched by name rather than by index because
## an index is whatever the importer felt like that day, and a rig swapped for
## another one should fail loudly here rather than quietly cut the wrong half of
## the man off.
const ARM_BONES: Array[StringName] = [
	&"mixamorig_LeftForeArm",
	&"mixamorig_LeftHand",
	&"mixamorig_LeftHandIndex1",
	&"mixamorig_LeftHandIndex2",
	&"mixamorig_LeftHandIndex3",
	&"mixamorig_LeftHandIndex4",
	&"mixamorig_LeftHandThumb1",
	&"mixamorig_LeftHandThumb2",
	&"mixamorig_LeftHandThumb3",
	&"mixamorig_LeftHandThumb4",
	&"mixamorig_RightForeArm",
	&"mixamorig_RightHand",
	&"mixamorig_RightHandIndex1",
	&"mixamorig_RightHandIndex2",
	&"mixamorig_RightHandIndex3",
	&"mixamorig_RightHandIndex4",
	&"mixamorig_RightHandThumb1",
	&"mixamorig_RightHandThumb2",
	&"mixamorig_RightHandThumb3",
	&"mixamorig_RightHandThumb4",
]

## How much of a vertex has to belong to the arms for it to be kept, out of the
## four influences it carries.
##
## The hazmat rig turns out not to need a considered number — the seam at the
## shoulder is clean enough that everything from a fifth to two thirds cuts the
## same 235 vertices — so this is set where it says what it means: a vertex that
## is more arm than not is an arm. It is here as a knob for the day the model is
## replaced by one with a softer seam, where a threshold too low drags a collar
## of torso along and one too high opens a hole at the shoulder.
const ARM_WEIGHT := 0.5

## How many influences the importer packs per vertex. Godot's skinned formats
## are four or eight, and eight only when a mesh needs it; the hazmat is four,
## and reading the arrays is what settles it rather than this constant — this is
## only the fallback for a mesh with no weights at all, where the arithmetic
## must not divide by nothing.
const INFLUENCES := 4

## Where the arms sit relative to the camera, and how big they are.
##
## The model is a man about 1.8 metres tall and his arms are drawn at the scale
## of the rest of him. Seen from inside his own head at 80 degrees of field of
## view they would be enormous and, worse, they would begin behind the near
## plane: the shoulder is level with the eye. So the whole rig is pushed down
## and back until the arms enter the frame from the bottom the way a first
## person game's do.
##
## The height was found by sweeping it against where the hands land on screen,
## along with the arm angles it works with (`scripts/view_model_arms_pose.gd`) —
## the two are one setting in two files, and moving either alone moves the hands.
##
## **`x` is not zero, and that is the model rather than a mistake.** The hazmat
## rig is not built symmetrically about its own origin: the head sits at -0.04
## and the two shoulders at +0.16 and -0.20, so a rig hung straight off the
## camera puts the man's centre line to one side of the player's. Both hands then
## crowd the left of the frame however the arms are angled — which is exactly
## what happens, and no amount of swinging an arm outwards fixes it, because
## rotating a bone moves one hand and the problem is that *both* are off centre.
## Sliding the whole rig back the other way is the one correction that moves
## them together, and it is a translation, so it costs nothing in the pose.
##
## These are exported rather than fixed because they are the numbers most likely
## to want an eye on them once there are gestures to watch, and moving them in
## the editor with the game running is the only sane way to find them.
@export var offset := Vector3(0.54, -1.52, 0.0):
	set(value):
		offset = value
		_apply_placement()

## The arms' size relative to the body's. Slightly under one: a man's own arms
## fill less of his view than a stranger's arms would at the same distance,
## because he is looking down the length of them rather than at them.
@export_range(0.1, 2.0, 0.01) var scale_factor := 0.95:
	set(value):
		scale_factor = value
		_apply_placement()

## How far down the player is, from 0 standing to 1 on his knees. It is the same
## fraction `player.gd` moves his capsule and his head by, handed over rather
## than read back, because the arms have to travel with the crouch and not
## behind it.
var _crouch := 0.0

## How far the arms lag behind the camera when the player turns, in seconds to
## cover the gap. It is the one thing here that is not a still pose: a rig
## welded to the camera reads as a decal on the screen, while one that swings a
## little behind a fast turn reads as arms attached to a man.
##
## Zero switches it off entirely, which is what the benches use — a pose that is
## still settling cannot be measured.
@export_range(0.0, 0.3, 0.005) var sway_lag := 0.06

## How far the arms are allowed to swing out on a turn, in radians. Without a
## ceiling a spin on the spot would throw them across the whole frame.
const MAX_SWAY := 0.09

## How far the rig is lifted when the player is all the way down on his knees,
## in metres.
##
## The crouch animations lower the arms on their own — `CrouchIdle` and
## `CrouchedWalking` bend the whole body forward and down, which is right for a
## man seen from across the room and puts his hands below the bottom of his own
## screen. Meanwhile the camera has come down too, so nothing about the offset
## catches it: measured standing the hands sit at four fifths of the way down the
## frame, and crouched the same rig puts them half a frame below it.
##
## So the arms are lifted by exactly what the crouch takes off them, and it turns
## out to be most of a metre's worth of animation: without it the right hand sits
## at 1.56 of the way down a frame that ends at 1.0, and with it at 0.84 —
## roughly where it sits standing up. It is the one number here that is a
## *correction* rather than a placement, which is why it is separate from
## `offset`: mixing the two would mean re-finding the standing pose every time
## the crouch was adjusted.
const CROUCH_LIFT := 0.55

## The model the arms are cut from, and whose animation they follow. It is the
## same scene as the body — `PlayerModel` — so everything the third person view
## learns, the first person view learns with it.
@onready var _model: PlayerModel = $Model

## The rebuilt surface: the arms alone, sharing the original's skeleton and skin.
var _arms: MeshInstance3D
## What bends the arms up into the frame, on this copy of the body and no other.
var _pose: ViewModelArmsPose
## Where the camera was pointing last frame, for the sway.
var _sway := Vector2.ZERO


func _ready() -> void:
	_cut_arms()
	_apply_placement()


## What the body is doing, handed straight on to the model underneath. The
## player calls this with the same state he sends over the wire, so his own arms
## and the arms his colleagues see him wave are playing the same frame of the
## same animation.
func set_state(state: PlayerAvatar.State) -> void:
	_model.set_state(state)


## The suit's colour, so a man's own sleeves match the ones the others see on
## him. Handed on for the same reason `set_state` is.
func set_tint(color: Color) -> void:
	_model.set_tint(color)
	# The tint lands on the model's own mesh, which is the one hidden behind these
	# arms. They are a separate instance with a material of their own, so the
	# repaint has to be picked up rather than waited for.
	refresh_material()


## The animation now running, by name. It is here for the benches, and it is the
## sharpest thing they can ask: that the arms on the player's own screen are
## playing what his body is playing.
func current_animation() -> StringName:
	return _model.current_animation()


## How far down the player is, from 0 standing to 1 on his knees. Called every
## frame by the player, whose crouch this follows.
##
## It is set rather than read because the crouch is his: he is the one who works
## out whether there is room to stand up, and a second reading of the same
## question in here could disagree with his by a frame.
func set_crouch(fraction: float) -> void:
	if is_equal_approx(_crouch, fraction):
		return
	_crouch = fraction
	_apply_placement()


## The arms, swung a little behind where the camera is pointing.
##
## `delta` is the frame, and `look` is how far the head turned this frame in
## radians — yaw in `x`, pitch in `y`. The player hands it over because he is the
## one who moved the head; reading it back off the camera here would be a frame
## late and, with the head under a body that also turns, would have to
## reconstruct which half of the turn was his.
func sway(delta: float, look: Vector2) -> void:
	if is_zero_approx(sway_lag):
		if not _sway.is_zero_approx():
			_sway = Vector2.ZERO
			_apply_placement()
		return
	# The turn pushes the arms out, and they come back on their own. Written as a
	# rate rather than a spring because a spring would overshoot, and arms that
	# overshoot a mouse flick read as a camera fault rather than as weight.
	var wanted := Vector2(
		clampf(-look.x, -MAX_SWAY, MAX_SWAY),
		clampf(-look.y, -MAX_SWAY, MAX_SWAY)
	)
	var weight := clampf(delta / sway_lag, 0.0, 1.0)
	_sway = _sway.lerp(wanted, weight)
	if absf(_sway.x) < 0.0005 and absf(_sway.y) < 0.0005:
		_sway = Vector2.ZERO
	_apply_placement()


## Cuts the arms out of the imported mesh and puts them up as a mesh of their
## own, leaving the original hidden behind them.
##
## The original is hidden rather than removed: it owns the `Skin` the new mesh
## borrows, and `PlayerModel.set_tint` reaches for it by name. A hidden
## `MeshInstance3D` costs nothing to keep.
func _cut_arms() -> void:
	var source := _model.mesh_instance()
	if source == null:
		push_warning("PlayerViewModel: the model has no mesh to cut arms out of.")
		return
	var skeleton := source.get_parent() as Skeleton3D
	if skeleton == null:
		push_warning("PlayerViewModel: the mesh is not under a Skeleton3D.")
		return
	var mesh := source.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		push_warning("PlayerViewModel: the model's mesh is not an ArrayMesh.")
		return

	var cut := _arms_only(mesh, skeleton)
	if cut == null:
		return

	# Drawn from the same skeleton as the body it was cut from, so the one
	# `AnimationPlayer` moves both. The new instance is a sibling of the original
	# under the skeleton, which is what makes `skeleton_path` and the shared
	# `Skin` line up.
	_arms = MeshInstance3D.new()
	_arms.name = "Arms"
	_arms.mesh = cut
	skeleton.add_child(_arms)
	_arms.transform = source.transform
	_arms.skeleton = _arms.get_path_to(skeleton)
	_arms.skin = source.skin
	# Nothing in here casts a shadow. The body still standing in the world is the
	# one that throws the player's shadow on the floor (`player.gd`), and a second
	# pair of arms an arm's length from the camera would throw a second one across
	# everything he looks at.
	_arms.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The arms sit inches from the near plane, where the engine's own culling has
	# nothing to work with: a skinned mesh's bounds are the rest pose's, and an
	# arm thrown forward leaves them. The margin is generous because the whole
	# thing is 116 triangles — cheaper to always draw than to ever wrongly cull.
	_arms.extra_cull_margin = 4.0
	# The material comes from the surface the arms were cut out of, whatever it
	# is by then: `PS1MaterialApplier` may already have swapped the imported
	# `StandardMaterial3D` for the shader, and it is `_ready` order that decides.
	# Copying at this moment would freeze whichever one happened to be there, so
	# the look is taken from the source every time it can change instead
	# (`refresh_material`), and once here to cover the case where it never does.
	refresh_material()
	# The body the arms were cut from is not drawn at all on this copy — the whole
	# model hangs off the camera, so its torso would be the inside of the player's
	# own head, and it is precisely what the cut exists to remove.
	source.visible = false
	# And the arms are bent up into the frame, which the animations do not do on
	# their own (`scripts/view_model_arms_pose.gd`). It goes up here rather than
	# in the scene for the same reason the cut does: the skeleton lives inside the
	# imported GLB, where nothing in the editor can reach it.
	_pose = ViewModelArmsPose.new()
	_pose.name = "ArmsPose"
	skeleton.add_child(_pose)


## Takes the arms' look from the model's own surface. Called on the way up, and
## worth calling again after anything that repaints the suit — the applier's
## material and the tint both land on the source mesh, and the arms are a
## separate instance that has to be told.
func refresh_material() -> void:
	var source := _model.mesh_instance()
	if _arms == null or source == null:
		return
	var material := source.get_active_material(0)
	if material != null:
		_arms.set_surface_override_material(0, material)


## The surface with everything that is not an arm thrown away.
##
## A triangle is kept when all three of its corners are arm; a triangle with one
## corner on the torso is the seam at the shoulder, and dropping it is what
## leaves a clean edge rather than a stretched flap of suit reaching towards the
## middle of the man.
##
## The vertices themselves are kept whole and in place, indices and all. It costs
## a few hundred unused vertices in the buffer and buys the one thing worth
## having here: the skin weights, the bone indices and the UVs stay exactly as
## the importer wrote them, so nothing has to be renumbered and nothing can be
## renumbered wrongly.
func _arms_only(mesh: ArrayMesh, skeleton: Skeleton3D) -> ArrayMesh:
	var arrays: Array = mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if bones.is_empty() or weights.is_empty() or indices.is_empty():
		push_warning("PlayerViewModel: the mesh carries no skin weights to cut by.")
		return null

	var arm_bones := _arm_bone_ids(skeleton)
	if arm_bones.is_empty():
		push_warning("PlayerViewModel: none of the arm bones are in this rig.")
		return null

	# How many bones pull on each vertex. Read off the arrays rather than assumed,
	# because Godot writes eight for a mesh that needs eight.
	var influences := INFLUENCES
	if vertices.size() > 0:
		influences = bones.size() / vertices.size()

	var is_arm := PackedByteArray()
	is_arm.resize(vertices.size())
	for vertex in vertices.size():
		var pull := 0.0
		for i in influences:
			if arm_bones.has(bones[vertex * influences + i]):
				pull += weights[vertex * influences + i]
		is_arm[vertex] = 1 if pull >= ARM_WEIGHT else 0

	var kept := PackedInt32Array()
	for triangle in indices.size() / 3:
		var a := indices[triangle * 3]
		var b := indices[triangle * 3 + 1]
		var c := indices[triangle * 3 + 2]
		if is_arm[a] == 1 and is_arm[b] == 1 and is_arm[c] == 1:
			kept.append_array([a, b, c])

	if kept.is_empty():
		push_warning("PlayerViewModel: the cut left no arms behind.")
		return null

	arrays[Mesh.ARRAY_INDEX] = kept
	var cut := ArrayMesh.new()
	# Built with the source's own format so the skin stays a skin: without
	# `ARRAY_FORMAT_BONES` and `ARRAY_FORMAT_WEIGHTS` surviving the round trip the
	# new mesh would be rigid geometry welded to the rest pose, which looks like
	# arms until the moment they are supposed to move.
	cut.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mesh.surface_get_format(0)
	)
	return cut


## The arm bones this rig actually has, by index. A name that is not in the
## skeleton is said out loud rather than skipped: it means the model was swapped
## for one on a different rig, and the cut that follows would be silently wrong.
func _arm_bone_ids(skeleton: Skeleton3D) -> Dictionary[int, bool]:
	var ids: Dictionary[int, bool] = {}
	for bone_name in ARM_BONES:
		var id := skeleton.find_bone(bone_name)
		if id < 0:
			push_warning("PlayerViewModel: no bone named %s in this rig." % bone_name)
			continue
		ids[id] = true
	return ids


## Puts the rig where the offsets say, sway included. One place does it so that
## the exported knobs, the sway and `_ready` cannot disagree about where the
## arms are.
func _apply_placement() -> void:
	if _model == null:
		return
	position = offset + Vector3(0.0, CROUCH_LIFT * _crouch, 0.0)
	rotation = Vector3(_sway.y, _sway.x, 0.0)
	scale = Vector3.ONE * scale_factor
