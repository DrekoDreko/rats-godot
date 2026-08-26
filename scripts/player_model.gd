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

## How long one animation takes to give way to the next. Long enough that a stop
## is a settle rather than a snap, short enough that the body is never caught
## visibly between two poses.
const BLEND_TIME := 0.15
## The blend into a jump, which is shorter than the rest. Leaving the ground is
## the one change a player *feels* in his own hands, and a body that takes an
## eighth of a second to agree that it jumped reads as lag in the controls.
const JUMP_BLEND_TIME := 0.05

## How far towards white a player's colour is pulled before it is multiplied
## into the suit. Half keeps the palette telling four men apart while leaving
## enough of the texture to still read as a hazmat suit.
const TINT_WHITENING := 0.5

## What each state looks like. Two of them are borrowed, and it is worth saying
## which and why rather than letting the next reader work it out:
##
## - **WALKING borrows `Running`.** There is no walk cycle in the model. Running
##   at a walk is wrong, but it is wrong in the way a placeholder is wrong — the
##   legs move, and the alternative is a man sliding across the floor.
## - **HOLDING borrows `Idle`.** There is no animation of carrying anything. A
##   man walking slowly with a rat in his hands looks like a man standing still,
##   which at least is not a lie about the rat.
##
## Both go the moment there is art for them, and neither needs anything else in
## the game to change when it does.
const ANIMATIONS := {
	PlayerAvatar.State.IDLE: &"Idle",
	PlayerAvatar.State.WALKING: &"Running",
	PlayerAvatar.State.RUNNING: &"Running",
	PlayerAvatar.State.AIRBORNE: &"Jump",
	PlayerAvatar.State.HOLDING: &"Idle",
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


func _ready() -> void:
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
## The colour is mixed with white on the way in. `albedo_color` multiplies the
## texture, and the suit's own yellow is already dark enough that a full-strength
## swatch from the palette comes out nearly black — which would tell the players
## apart by making three of them invisible.
func set_tint(color: Color) -> void:
	if _mesh == null:
		return
	var tint := color.lerp(Color.WHITE, TINT_WHITENING)
	for surface in _mesh.get_surface_override_material_count():
		var material := _mesh.get_active_material(surface)
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter(&"albedo_color", tint)
		elif material is BaseMaterial3D:
			# The imported material is baked into the mesh, which every instance
			# of the model shares: painting it in place would dress the whole van
			# in one man's colour. The applier already duplicates per surface, so
			# this only bites when the PS1 look is off.
			var own := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
			own.albedo_color = tint
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


## The animation itself. `Jump` is the one that does not loop, and that is on
## purpose rather than an oversight in the import: it is three-quarters of a
## second long and a fall is however long the fall is, so it plays once and
## holds its last frame — which is a landing pose — for as long as the man is off
## the ground.
func _play(state: PlayerAvatar.State) -> void:
	var animation: StringName = ANIMATIONS.get(state, &"Idle")
	var blend := JUMP_BLEND_TIME if state == PlayerAvatar.State.AIRBORNE else BLEND_TIME
	_animation.play(animation, blend)
