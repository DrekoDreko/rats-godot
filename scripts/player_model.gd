class_name PlayerModel
extends Node3D
## The body a player is seen in: the hazmat suit, animated off what he is doing.
##
## There is one of these per player and it is the *same* scene on both sides of
## the wire — the character in `player.tscn` wears one, and so does every avatar
## in `player_avatar.tscn`. That is the whole point of the file. A man's legs
## have to move the same way on his own screen as on his colleague's, and the
## surest way to get that is for there to be one place where a state becomes an
## animation, rather than two that have to be kept in step by hand.
##
## What it asks of the outside world is one line: `set_state()`, with a
## `PlayerAvatar.State`. Which animation that turns into, how long the blend is,
## and where the mesh lives inside the imported scene are this file's business
## and nobody else's. **Nothing outside here should know that running is called
## `Running`** — that is the test of whether the seam is in the right place, and
## it is what lets the model be swapped for another one without touching a line
## of the game.
##
## It is an `AnimationPlayer` and not an `AnimationTree`, deliberately. A state
## machine here would be a second state machine mirroring the one in
## `player.gd:animation_state()`, which already decides what the body is doing
## and in what order of precedence — two sources of truth about one question,
## and the one downstream would always be the one that was wrong. `play()` takes
## a blend time, which is the only thing a tree would have bought us. The day
## there is something to blend *between* rather than *from* — aiming while
## walking, a strafe that reads off direction as well as speed — is the day this
## is worth revisiting, and not before.
##
## ## The arms are a second question
##
## What his legs are doing and what his hands are doing are asked separately —
## `set_state` and `set_arms` — and that is the one place where the single
## animation above is not the whole story. It has to be, because a man carrying
## a rat can walk, and there is exactly one clip per state: `HOLDING` used to
## borrow `Idle`, so on everybody else's screen a player who picked up an animal
## had his feet nailed to the floor until he put it down.
##
## So the state still picks the clip, and the arms are posed on top of it by
## `PlayerArms` — a `SkeletonModifier3D` this file puts under the imported
## skeleton, because that is the one place in Godot where a pose survives the
## animation being written the next frame. It is still not a state machine and
## still not a tree: it is one layer over one clip, which is the smallest thing
## that answers the question.

## How long one animation takes to give way to the next. Long enough that a stop
## is a settle rather than a snap, short enough that the body is never caught
## visibly between two poses.
const BLEND_TIME := 0.15
## The blend into a jump, which is shorter than the rest. Leaving the ground is
## the one change a player *feels* in his own hands, and a body that takes an
## eighth of a second to agree that it jumped reads as lag in the controls.
const JUMP_BLEND_TIME := 0.05

## How far towards white a player's colour is pulled before it is multiplied
## into the suit. Only the fallback path uses it — see `set_tint` — where
## multiplying is the only tool there is and half keeps the palette telling four
## men apart while leaving enough of the texture to still read as a hazmat suit.
const TINT_WHITENING := 0.5

## What each state looks like. Two of them are borrowed, and it is worth saying
## which and why rather than letting the next reader work it out:
##
## - **WALKING borrows `Running`.** There is no walk cycle in the model. Running
##   at a walk is wrong, but it is wrong in the way a placeholder is wrong — the
##   legs move, and the alternative is a man sliding across the floor.
##
## It goes the moment there is art for it, and nothing else in the game has to
## change when it does.
##
## `HOLDING` is *not* in here any more, and its absence is the point. What a man
## with a rat in his hands is doing with his legs is whatever his legs are doing
## — standing, walking, creeping — and his hands are a separate layer
## (`set_arms`). It stays in `PlayerAvatar.State` because the number crosses the
## wire and the values are not ours to renumber, but nothing produces it.
const ANIMATIONS := {
	PlayerAvatar.State.IDLE: &"Idle",
	PlayerAvatar.State.WALKING: &"Running",
	PlayerAvatar.State.RUNNING: &"Running",
	PlayerAvatar.State.AIRBORNE: &"Jump",
	PlayerAvatar.State.CROUCHING: &"CrouchIdle",
	PlayerAvatar.State.CROUCH_WALKING: &"CrouchedWalking",
}

## The state being shown, so that a state which has not changed is not played
## again — `play()` on the animation already running restarts it, and a body
## whose walk cycle begins afresh every frame never lifts a foot.
var _state := PlayerAvatar.State.IDLE
## Set once the first state has been played, so that the opening `IDLE` is not
## mistaken for "nothing has been asked of us yet" and skipped.
var _started := false

@onready var _animation: AnimationPlayer = $Hazmat/AnimationPlayer
@onready var _mesh: MeshInstance3D = $Hazmat/Armature/Skeleton3D/Hazmat
## The layer that poses the arms over whatever clip is playing. Built here in
## code rather than dropped into `player_model.tscn`, and for the same reason
## `set_shadows_only` reaches for the mesh from here: a `SkeletonModifier3D` has
## to be a child of the `Skeleton3D`, and the skeleton lives inside the imported
## GLB where the editor cannot put anything.
##
## Null on a skeleton that is not the one it was written for, in which case the
## body simply has no arms layer and everything else goes on working — see
## `PlayerArms._measure`.
var _arms: PlayerArms


func _ready() -> void:
	_build_arms()
	_play(_state)
	_started = true


## What the body is doing. Called every frame by whoever owns this model — the
## character on his own machine, the avatar on everybody else's — and cheap to
## call with a state that has not changed, which is the usual case.
func set_state(state: PlayerAvatar.State) -> void:
	if state == _state and _started:
		return
	_state = state
	_play(state)


## Whether his hands are full, which is a different question from what his legs
## are doing and is asked separately for that reason. Called every frame by
## whoever owns this model, and cheap on a value that has not changed.
func set_arms(arms: PlayerAvatar.Arms) -> void:
	if _arms == null:
		return
	_arms.holding = arms == PlayerAvatar.Arms.HOLDING


## One squeeze of whatever is in his hands: a thing that happens rather than a
## thing that is, so it arrives as a call and not as a state. It is what puts a
## rhythm on the strangling for everybody who is only watching it — see
## `PlayerArms.squeeze`.
func squeeze() -> void:
	if _arms == null:
		return
	_arms.squeeze()


## Where this body is holding something, in world space.
##
## It is what a rat in these hands has to hang from, and `PlayerAvatar` moves
## its `CapturePoint` onto it every frame so that the animal is drawn *in* the
## grip rather than beside it. The body decides where its own hands are, so the
## point comes from here rather than being a fixed spot in the avatar's scene —
## which is what it used to be, and which is why the rat used to float next to a
## man whose arms were down.
##
## Falls back to the middle of the body on a model with no arms layer. It is a
## worse answer than the old fixed point, but it is only reached on a skeleton
## this file does not understand, where every other answer would be wrong too.
func grip_point() -> Vector3:
	if _arms == null:
		return global_position
	return _arms.get_skeleton().global_transform * _arms.grip_point()


## The animation now running, by name. It exists for the benches
## (`_test_sync.gd`), which need to see that a state crossed the wire and became
## the right movement — a stronger thing to assert than that something moved.
func current_animation() -> StringName:
	return _animation.current_animation


## Paints the suit in the player's colour. It has to cope with two different
## materials, and which one is on the mesh is not this file's decision:
## `PS1MaterialApplier` swaps the imported `StandardMaterial3D` for a
## `ShaderMaterial` when the PS1 look is on, and on that material the colour is
## a shader parameter rather than a property. Writing to the wrong one of the
## two fails silently and looks like a bug in `ColorManager`, so both are
## handled here, in the one place that can see which is in play.
##
## **On the shader the hue is replaced, not multiplied.** The suit is painted a
## fixed yellow in the texture, and multiplying can only darken: the yellow's
## blue channel sits at 77/255, so a blue swatch lands at a third of that and
## reads as black. The shader instead swaps the hue of anything close enough to
## that yellow and keeps the pixel's own brightness, which is where the fabric's
## folds and shading are — so the gloves, the boots and the face come through
## untouched and only the overalls change colour.
##
## **On the imported material it is still a multiply**, because a
## `StandardMaterial3D` has no such trick, so the colour is washed halfway to
## white first to keep three of the four men from turning black. That path is
## the fallback for the PS1 look being off, and it looks worse — which is the
## honest state of it rather than something to hide.
func set_tint(color: Color) -> void:
	if _mesh == null:
		return
	for surface in _mesh.get_surface_override_material_count():
		var material := _mesh.get_active_material(surface)
		if material is ShaderMaterial:
			var shader_material := material as ShaderMaterial
			shader_material.set_shader_parameter(&"recolor_target", color)
			shader_material.set_shader_parameter(&"recolor_strength", 1.0)
		elif material is BaseMaterial3D:
			# The imported material is baked into the mesh, which every instance
			# of the model shares: painting it in place would dress the whole van
			# in one man's colour. The applier already duplicates per surface, so
			# this only bites when the PS1 look is off.
			var own := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
			own.albedo_color = color.lerp(Color.WHITE, TINT_WHITENING)
			_mesh.set_surface_override_material(surface, own)


## The skinned surface itself, for the one caller that has to reach past the
## seam this file otherwise keeps shut: `PlayerViewModel` cuts the player's own
## arms out of this mesh, and to do that it needs the vertices, the weights and
## the `Skin` — none of which can be described in terms of states and
## animations.
##
## It stays a deliberate exception rather than an invitation. Everything else
## about the body is asked for through `set_state`, `set_tint` and
## `set_shadows_only`, and anything new that wants the mesh should ask itself
## whether it really wants the mesh or only wants the body to look different.
func mesh_instance() -> MeshInstance3D:
	return _mesh


## Draws the body as a shadow and nothing else. It is what the player's own copy
## is set to: he is inside this model looking out of it, so the mesh itself would
## be the inside of his own head, but the shadow he casts on the floor is his and
## should move with him.
##
## It is set from here rather than in the scene because the mesh lives inside the
## imported GLB, where the editor cannot reach it.
func set_shadows_only(enabled: bool) -> void:
	if _mesh == null:
		return
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if enabled \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## Puts the arms layer under the imported skeleton. Quietly does nothing when
## there is no skeleton to put it under, which is every model that is not this
## one and is not an error worth stopping the game for.
func _build_arms() -> void:
	var skeleton := get_node_or_null("Hazmat/Armature/Skeleton3D") as Skeleton3D
	if skeleton == null:
		return
	_arms = PlayerArms.new()
	_arms.name = "Arms"
	skeleton.add_child(_arms)


## The animation itself. `Jump` is the one that does not loop, and that is on
## purpose rather than an oversight in the import: it is three-quarters of a
## second long and a fall is however long the fall is, so it plays once and
## holds its last frame — which is a landing pose — for as long as the man is off
## the ground.
func _play(state: PlayerAvatar.State) -> void:
	var animation: StringName = ANIMATIONS.get(state, &"Idle")
	var blend := JUMP_BLEND_TIME if state == PlayerAvatar.State.AIRBORNE else BLEND_TIME
	_animation.play(animation, blend)
