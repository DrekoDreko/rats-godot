class_name BloodBurst
extends Node3D
## A rat coming apart: a fistful of red shards thrown out of one point, each one
## flying its own arc and shrinking away as it goes.
##
## It is meshes and tweens rather than a particle system, and that is the look
## rather than an economy. A `CPUParticles3D` draws soft billboards that always
## face the lens and fade out politely; what a PlayStation drew was a handful of
## flat, hard-edged, unlit polygons tumbling through the air with no blending on
## them at all. Every shard here is a `PlaneMesh` on an unshaded material, spun
## on all three axes as it flies, and it vanishes by *shrinking to nothing* —
## the same way a carcass on the floor vanishes (`rat.gd: _vanish`),
## because that is the vanishing this game does.
##
## It owns nothing but itself: it is added to the world at a point, it runs, and
## it frees itself at the end. Whatever spawned it does not have to hold on to
## it, wait for it, or clean it up — which matters most for the case it was
## written for, where the thing that spawned it (the rat) is deleted on the same
## frame.

## The spread of shards a full burst throws.
##
## It is a range and not a number so that two rats dying in the same corner do
## not come apart in identical sprays. The floor of it is what a burst has to
## have to read as a burst at all; below about a dozen the eye counts them.
const SHARDS := Vector2i(18, 26)
## How big one shard is, in metres. A rat is about twenty centimetres of body,
## so these are chunks of it rather than a mist — and the range is wide on
## purpose: a spray of identically sized quads reads as a pattern, and a few big
## pieces among many small ones is what sells it as something torn apart.
const SHARD_SIZE := Vector2(0.02, 0.075)
## How fast a shard leaves the middle, in metres per second.
const SPEED := Vector2(1.6, 5.2)
## How much of the throw is aimed *up* rather than in the direction it was given.
## Straight out of a fist the spray would be a flat disc; this is what lifts it
## into an arc so it falls back down through the frame.
const UPWARD_BIAS := 0.55
## Gravity on a shard, in metres per second squared. Heavier than the world's
## (the player falls at 22) because a shard has a shorter flight to fall in and
## has to visibly arc within it.
const GRAVITY := 26.0
## How long a shard lives, in seconds. Short: this is a burst, not a fountain,
## and shards still in the air a second later read as litter hanging in the
## room.
const LIFETIME := Vector2(0.35, 0.85)
## How fast a shard tumbles, in turns per second, on each of its three axes.
const SPIN := Vector2(1.5, 6.0)
## The fraction of its life a shard spends at full size before it starts
## shrinking away. It vanishes into the tail of its own flight rather than
## popping out at the end of it.
const SHRINK_AT := 0.55
## The two reds a shard is painted in, rolled between. One dark and one bright,
## so the spray has depth in it without anything having to light it — nothing
## here is lit at all.
const DARK := Color(0.35, 0.02, 0.02)
const BRIGHT := Color(0.72, 0.06, 0.05)
## The cloud left hanging where the body was: a few shards that barely travel,
## as a fraction of the burst. Without them the spray is a hollow shell — every
## piece leaves at once and the middle, which is where the animal actually was,
## is the one place with nothing in it.
const HAZE_SHARE := 0.25
const HAZE_SPEED := 0.35

## How many reds the spray is actually painted in, between `DARK` and `BRIGHT`.
##
## A shard's colour could be rolled freely and given a material of its own, and
## that would be a material per shard — a couple of dozen per kill, each one a
## separate draw. Rolling from a fixed ladder instead means the whole game's
## blood is these few materials, built once and shared by every burst of every
## rat, and at this many steps no eye is going to find the ladder in a spray
## that is in the air for half a second.
const SHADES := 5

## The shared ladder, built on the first burst of the run and kept for the rest
## of it. Unshaded and double-sided because a PlayStation's polygons were both:
## a shard tumbling through its own arc turns its back to the lens for half of
## it, and a single-sided one would blink.
static var _materials: Array[StandardMaterial3D] = []

## Throws a burst at `point`, thrown out along `direction`, and hands back the
## node so a caller with something else to hang on it can. `strength` scales how
## far and how hard the whole thing goes — a rat is 1.
##
## `world` is what it is added to. It is asked for rather than found because the
## one thing that must not happen is a burst parented to the body it came out
## of: that body is freed on the same frame, and the spray would go with it.
static func burst(world: Node, point: Vector3, direction := Vector3.UP,
		strength := 1.0) -> BloodBurst:
	if world == null or not world.is_inside_tree():
		return null
	var node := BloodBurst.new()
	world.add_child(node)
	node.global_position = point
	node._explode(direction, strength)
	return node

func _explode(direction: Vector3, strength: float) -> void:
	var aim := direction.normalized() if not direction.is_zero_approx() else Vector3.UP
	var count := randi_range(SHARDS.x, SHARDS.y)
	var longest := 0.0
	for i in count:
		longest = maxf(longest, _throw_shard(aim, strength, float(i) / float(count)))
	# The node outlives its last shard by a hair and then takes itself out of the
	# tree. One timer for the whole burst rather than a callback on each shard's
	# own tween: whichever shard finished last would otherwise be the one that
	# frees the parent the others are still hanging off.
	var life := create_tween()
	life.tween_interval(longest + 0.05)
	life.tween_callback(queue_free)

## One shard: a flat quad thrown out of the middle on its own arc, tumbling, and
## shrinking away at the end of it. Returns how long it will be in the air, so
## the burst knows when the last of it is gone.
##
## The whole flight is written as a `Tween` on a method rather than as a
## `RigidBody3D`, and that is deliberate: two dozen bodies per kill would go
## through the physics solver, collide with the floor, with the player and with
## each other, and a burst is not worth a solver. It also would not look like
## this — what is wanted is a shard that flies through everything and is gone,
## the way one drawn in 1998 would have.
func _throw_shard(aim: Vector3, strength: float, spread: float) -> float:
	var mesh := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	var size := randf_range(SHARD_SIZE.x, SHARD_SIZE.y) * strength
	# Not square: a shard is a torn piece of something, and a spray of perfect
	# squares reads as confetti.
	quad.size = Vector2(size, size * randf_range(0.5, 1.6))
	# The plane is born lying flat, facing up. Stood on its edge it faces the
	# room, which is what a shard tumbling *through* the air should do.
	quad.orientation = PlaneMesh.FACE_Z
	mesh.mesh = quad
	# One of the few shared reds rather than a red of its own: see `SHADES`.
	mesh.material_override = _shard_material(randi() % SHADES)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)

	# A cone around the direction it was thrown, opened right up: a rat bursting
	# in a fist goes everywhere, and a tight cone reads as a jet. The lift is
	# added afterwards so that even the shards thrown downwards arc.
	var scatter := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)).normalized()
	var throw := (aim + scatter * 1.35).normalized() + Vector3.UP * UPWARD_BIAS

	# A quarter of the spray barely leaves at all and hangs where the body was.
	var haze := spread < HAZE_SHARE
	var speed := HAZE_SPEED if haze else randf_range(SPEED.x, SPEED.y) * strength
	var velocity := throw.normalized() * speed
	var life := randf_range(LIFETIME.x, LIFETIME.y)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)).normalized() * randf_range(SPIN.x, SPIN.y) * TAU
	# Where it starts is not quite the middle: a burst that all comes from one
	# point reads as a firework, and this is a body's worth of volume.
	mesh.position = scatter * size * 1.5
	mesh.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)

	var start := mesh.position
	var start_spin := mesh.rotation
	var start_scale := mesh.scale
	var flight := create_tween()
	flight.tween_method(
		func(t: float) -> void:
			if not is_instance_valid(mesh):
				return
			# Ballistics done in closed form rather than integrated frame by
			# frame: the tween hands out the time, and the position is read
			# straight off it. Nothing accumulates, so a burst looks the same at
			# 30 frames a second as at 200.
			mesh.position = start + velocity * t + Vector3.DOWN * (0.5 * GRAVITY * t * t)
			mesh.rotation = start_spin + spin * t
			# It holds its size for the first half of its flight and shrinks out
			# of existence over the rest of it.
			var shrink := clampf((t / life - SHRINK_AT) / (1.0 - SHRINK_AT), 0.0, 1.0)
			mesh.scale = start_scale * (1.0 - shrink),
		0.0, life, life)
	return life

## One rung of the shared ladder of reds. The whole ladder is built on the first
## shard of the run and every burst after it draws from what is already there.
static func _shard_material(shade: int) -> StandardMaterial3D:
	if _materials.is_empty():
		for i in SHADES:
			var mat := StandardMaterial3D.new()
			# Unlit, opaque, and drawn from both sides: a flat polygon of flat
			# colour, which is the whole of what the console this game is
			# dressed as could do.
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.albedo_color = DARK.lerp(BRIGHT, float(i) / float(SHADES - 1))
			_materials.append(mat)
	return _materials[clampi(shade, 0, SHADES - 1)]
