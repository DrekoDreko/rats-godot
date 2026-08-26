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
## This is that something: `models/hazmat_hand.glb` held up in the corner of the
## frame. There are two of them in the scene, the left being the right one
## mirrored, and only the right is drawn — see `show_left` for why, and for what
## turning the other one back on costs.
##
## ## Why a model of its own rather than the body's arms
##
## Because the body's arms were never arms. What stood here before was
## `player_model.tscn` — the same suit everybody else sees — pushed up against
## the lens with everything that was not a forearm cut out of the mesh at load,
## triangle by triangle, by skin weight. It worked, and it cost a rig-shaped
## dependency for every part of it: the cut was keyed to Mixamo bone names, the
## pose that bent the hands into frame was a `SkeletonModifier3D` fighting five
## third-person clips for control of the same bones, and the crouch needed a
## correction on top because the clip lowered arms the camera had already
## lowered. Three mechanisms, all of them there to undo an animation meant for
## somebody else's screen.
##
## The hand model is the arm alone, exported from Blender at the length it
## should read at, pointing down its own +Z. Nothing has to be cut off it and
## nothing has to be bent back into frame, so there is no rig to match and no
## clip to argue with — which is the whole reason it replaced the cut.
##
## ## Where the movement comes from
##
## From this file, and from nowhere else. The model carries no skeleton and no
## animation, so the arms are moved the way a first-person game moves them: as
## rigid objects, offset from a rest pose by what the player is doing.
##
## - **The walk** rides the same phase `player.gd` swings the camera on, handed
##   over rather than re-derived, so a hand rises on the step the view rises on
##   instead of a beat off it (`bob`).
## - **The turn** swings them behind the camera (`sway`), which is what makes
##   them read as arms attached to a man rather than as a decal on the screen.
## - **The crouch** pulls them back and down a little, on the same fraction the
##   capsule shrinks by (`set_crouch`).
##
## What is deliberately *not* here is a pose per animation state. `set_state` is
## still taken and still ignored, because the player has one to give and the day
## there are first-person clips is the day it becomes useful — see there.
##
## ## Where it is drawn
##
## In the world, by the player's own camera, and not in a viewport of its own.
## That keeps the PS1 shader and the full-screen post-process working on the
## arms exactly as they work on everything else — a second camera compositing
## over the first would have to be taught both. The price is that an arm can
## clip into a wall the player is pressed against, which is what nearly every
## game of this vintage did too.

## Where each arm rests relative to the camera, before anything moves it: the
## right one's offset, with the left one taking it mirrored in `x`.
##
## `z` is negative because the camera looks down its own -Z, so this is how far
## in front of the lens the arm's origin sits. The model runs from its elbow at
## -Z to its fingertips at +Z over about 70 centimetres, and it is turned to face
## the camera's forward by `ARM_FACING` — so the origin being *behind* the lens
## is right: what is in the frame is the far half of the arm, and the near half
## is off screen behind the near plane where an elbow this close to a lens
## belongs.
@export var rest_offset := Vector3(0.26, -0.22, -0.20):
	set(value):
		rest_offset = value
		_apply()

## How each arm is turned at rest, in degrees, before the mirror.
##
## `x` tips the fingertips down towards the floor, `y` swings the arm in
## towards the middle of the frame, `z` rolls it about its own length. They are
## added to `ARM_FACING`, which is the fixed half-turn that takes the model's
## own +Z onto the camera's forward — so these read as a pose rather than as a
## coordinate correction.
@export var rest_rotation := Vector3(-12.0, 20.0, 0.0):
	set(value):
		rest_rotation = value
		_apply()

## The hand's size relative to the model's own.
##
## Under one, and it is the model rather than the taste: the arm was exported at
## the length it has on the body, about seventy centimetres from the shoulder's
## cut to the fingertips, and at eighty degrees of field of view the whole of
## that length is more arm than a man sees of his own.
##
## This and `rest_offset.z` are one setting in two numbers, and pulling them the
## same way is what fixes the arm reading as *long*: a hand further off has to
## be drawn bigger to stay legible, and a bigger hand further off is exactly the
## silhouette of a stretched arm. Bringing it in and growing it together keeps
## the hand the size it was on screen while the sleeve behind it shortens, which
## is the whole difference between a hand held up and an arm reaching out.
##
## Found by photographing the sweep rather than by arithmetic, because what is
## being judged is whether it reads as a hand.
@export_range(0.1, 2.0, 0.01) var scale_factor := 0.74:
	set(value):
		scale_factor = value
		_apply()

## The half-turn that takes the model's own forward onto the camera's.
##
## The mesh points down +Z — elbow at the back, fingers at the front, measured
## off the exported bounds — and a Godot camera looks down -Z. Without this the
## player would be shown the backs of two arms walking away from him.
##
## It is a constant rather than baked into `rest_rotation` so that the exported
## angles stay readable as a pose: dragging `rest_rotation.y` in the editor
## swings the arm in and out from the body, and it would read as neither if it
## were 180 degrees away from where it looked.
const ARM_FACING := Vector3(0.0, 180.0, 0.0)

## Whether the left hand is drawn at all.
##
## Off, and one hand is what the player sees. That is not a stand-in for the
## second one being unfinished — it is what the game asks for today: a rat is
## held in one hand and a trap set with the other, and until there is a gesture
## that needs both at once, a second hand riding the corner of the screen is a
## thing to look at rather than a thing doing anything. One hand also reads
## better this close, where two crowd the bottom of the frame between them.
##
## It is a knob rather than a deleted node because the left hand costs nothing
## while it is hidden and everything to rebuild: the mirror, the pose and the
## tint all already work on it (`_place`), so the day a gesture wants both hands
## this is the whole of turning it back on.
@export var show_left := false:
	set(value):
		show_left = value
		_apply()

## How far the arms swing on a step, in metres, at a full run.
##
## The vertical is twice the horizontal because that is what a walk looks like
## from inside it: an arm rises and falls with the shoulder it hangs off far
## more than it crosses the body. Both are small — this is a sway to walk to,
## not a shake, and it is drawn on top of a camera that is already swaying by
## `player.gd:bob_amount`.
@export var bob_amount := Vector2(0.012, 0.024):
	set(value):
		bob_amount = value
		_apply()

## How far the arms roll on a step, in degrees at a full run. It is what stops
## the bob reading as the whole rig being winched up and down: a real arm tips
## as it rises.
@export_range(0.0, 20.0, 0.5) var bob_roll := 3.5:
	set(value):
		bob_roll = value
		_apply()

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

## How far a turn moves the arms sideways as well as turning them, in metres per
## radian of swing. Rotation alone pivots them about the camera, which from
## inside the camera is barely visible; the slide is what actually reads.
const SWAY_SLIDE := 0.5

## Where the arms are pulled to when the player is all the way down on his
## knees, in metres — in towards his chest, and *up*.
##
## Up is the part that reads wrong until it is measured. The camera has already
## come down with the head, so an offset that is a fixed distance below the lens
## comes down with it and nothing needs correcting — except that crouching also
## brings the head forward over the knees, which shortens the arms' reach and
## drops the hands towards the bottom edge. Measured, they leave the frame
## entirely: standing they sit at 0.85 of the way down the picture, and crouched
## the same offset puts them at 1.01, which is off the bottom of it.
##
## So they are lifted by what the crouch takes off them, and pulled back towards
## the chest, which is what a man does with his arms when he folds up.
const CROUCH_PULL := Vector3(0.0, 0.05, 0.09)

## The two arms, right and left. The left one is the right one with its `x`
## mirrored — offset, rotation and mesh alike — which the hand model allows
## because it was exported as one arm rather than as a pair.
@onready var _right: Node3D = $Right
@onready var _left: Node3D = $Left

## How far down the player is, from 0 standing to 1 on his knees.
var _crouch := 0.0
## Where the camera was pointing last frame, for the sway: yaw in `x`, pitch in
## `y`, in radians.
var _sway := Vector2.ZERO
## Where the player is in his walking cycle, in radians, and how much of the
## step is being applied — both handed over by `player.gd` rather than counted
## again in here. See `bob`.
var _bob_phase := 0.0
var _bob_weight := 0.0


func _ready() -> void:
	# The mesh flags are set here rather than in the scene because both arms are
	# instances of an imported GLB, whose inner nodes the editor cannot reach.
	for mesh in _meshes():
		# Nothing in here casts a shadow. The body still standing in the world is
		# the one that throws the player's shadow on the floor (`player.gd`), and
		# a second pair of arms an arm's length from the camera would throw a
		# second one across everything he looks at.
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The arms sit inches from the near plane, where the engine's own culling
		# has little to work with once the rig swings on a turn. The margin is
		# generous because the whole thing is 56 triangles an arm — cheaper to
		# always draw than to ever wrongly cull.
		mesh.extra_cull_margin = 4.0
	_apply()


## What the body is doing. Taken and ignored, and it is worth saying why rather
## than dropping the call: the player has exactly one state for the body and the
## arms, and handing it to both of them is what will make a first-person clip
## line up with the third-person one the day there is art for either. Until then
## the arms are moved by what the player is doing rather than by what he looks
## like doing, and there is nothing here for a state to change.
func set_state(_state: PlayerAvatar.State) -> void:
	pass


## The suit's colour, so a man's own sleeves match the ones the others see on
## him.
##
## It has to cope with two different materials for the same reason
## `PlayerModel.set_tint` does — `PS1MaterialApplier` may have swapped the
## imported `StandardMaterial3D` for the shader by now, and on that one the
## colour is a shader parameter rather than a property. Writing to the wrong one
## fails silently and looks like a bug in `ColorManager`.
func set_tint(color: Color) -> void:
	for mesh in _meshes():
		for surface in mesh.get_surface_override_material_count():
			var material := mesh.get_active_material(surface)
			if material is ShaderMaterial:
				var shader_material := material as ShaderMaterial
				shader_material.set_shader_parameter(&"recolor_target", color)
				shader_material.set_shader_parameter(&"recolor_strength", 1.0)
			elif material is BaseMaterial3D:
				# The imported material is baked into the mesh, which both arms
				# share with every other instance of the model: painting it in
				# place would dress the whole van in one man's colour.
				var own := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
				own.albedo_color = color.lerp(Color.WHITE, PlayerModel.TINT_WHITENING)
				mesh.set_surface_override_material(surface, own)


## The animation now running, by name. There is none — the arms are posed rather
## than animated — and the empty name is the honest answer rather than a lie
## about a clip that is not playing.
##
## It stays because the benches ask it of both bodies, and because the day the
## hands carry clips of their own this is where the answer comes from.
func current_animation() -> StringName:
	return &""


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
	_apply()


## Where the player is in his step, handed over by `player.gd`.
##
## `phase` is the same angle his camera rides its sine on and `weight` the same
## fraction of a full run it is scaled by. Both are taken rather than worked out
## again in here, and that is the point of the call: an arm counting its own
## steps off the velocity would drift a frame from the view it is drawn in
## front of, and the two would visibly beat against each other.
func bob(phase: float, weight: float) -> void:
	if is_equal_approx(_bob_phase, phase) and is_equal_approx(_bob_weight, weight):
		return
	_bob_phase = phase
	_bob_weight = weight
	_apply()


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
			_apply()
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
	_apply()


## Puts both arms where everything above says they are. One place does it so
## that the exported knobs, the sway, the bob, the crouch and `_ready` cannot
## disagree about where the arms are.
##
## The right hand is placed and the left is the same placement mirrored in `x`:
## the offset's `x` flips, and so do the two rotations that read as handedness —
## the yaw that swings a hand in towards the middle and the roll about its own
## length. The pitch does not, because tipping the fingers at the floor is the
## same tip on both hands.
##
## The left is placed whether or not it is drawn (`show_left`), which costs a
## transform on a hidden node and buys the mirror staying correct for free.
func _apply() -> void:
	if _right == null or _left == null:
		return
	scale = Vector3.ONE * scale_factor

	var step := sin(_bob_phase) * _bob_weight
	# The horizontal rides at half the rate, so a full stride is one sideways
	# sweep across two vertical ones — which is what a stride is: two steps.
	var swing := sin(_bob_phase * 0.5) * _bob_weight

	var offset := rest_offset
	offset += CROUCH_PULL * _crouch
	offset.y += step * bob_amount.y
	offset.x += swing * bob_amount.x
	# The turn slides the arms as well as turning them. Yaw moves them sideways
	# and pitch moves them up, both against the turn, which is the direction the
	# lag is already rotating them in.
	offset.x += _sway.x * SWAY_SLIDE
	offset.y += _sway.y * SWAY_SLIDE

	var angles := rest_rotation + ARM_FACING
	angles.y += rad_to_deg(_sway.x)
	angles.x += rad_to_deg(_sway.y)
	angles.z += step * bob_roll

	_place(_right, offset, angles, 1.0)
	# The left hand is placed even while it is hidden, so that turning it back on
	# shows a hand that is already where it belongs rather than one that snaps
	# into place on the next step.
	_place(_left, offset, angles, -1.0)
	_left.visible = show_left


## One arm, put down at `offset` turned to `angles`, mirrored when `side` is -1.
##
## The mirror is a negative `x` scale on the node rather than a second model:
## the hand was exported once, and scaling it through zero is what turns a right
## arm into a left one without a second file to keep in step with the first.
## It flips the winding of every triangle with it, which is why the imported
## material is double-sided — the exporter wrote it that way, and it has to stay
## that way for this to work.
func _place(arm: Node3D, offset: Vector3, angles: Vector3, side: float) -> void:
	arm.position = Vector3(offset.x * side, offset.y, offset.z)
	arm.rotation_degrees = Vector3(angles.x, angles.y * side, angles.z * side)
	arm.scale = Vector3(side, 1.0, 1.0)


## Every surface of both arms. Small and walked rather than cached because the
## imported scene's shape is the importer's business, and a cached path is a
## thing that breaks silently the day the model is re-exported.
func _meshes() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for arm in [_right, _left]:
		if arm != null:
			_collect(arm, found)
	return found


func _collect(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		into.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect(child, into)
