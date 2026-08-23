class_name CabinShake
extends Node
## The van shaking under the crew's feet: a small, constant tremor on the
## camera for as long as the wheels are turning.
##
## **It shakes the camera and not the head.** The player writes `head.position.y`
## and `head.rotation.x` himself every frame — the crouch and the mouse look both
## live there (`scripts/player.gd`) — so a tremor added to the head would be
## overwritten on the same frame by the crouch, or would fight the mouse and drag
## the aim off. The `Camera3D` hanging under the head is written by nobody, which
## makes it the one free transform in the player, and this node owns it outright.
##
## **It is not an `AnimationPlayer`.** The card asks for one and this is
## deliberately not: an animation is a fixed loop, and a fixed loop of a shake is
## something a player notices the period of inside a minute — two minutes of it
## is a metronome. Sine waves at frequencies that do not divide into each other
## never come back round to the same place, cost less than a track, and can be
## turned down to nothing in one line when the van stops.
##
## **Rotation over position, mostly.** A camera that is moved bodily reads as the
## player bouncing; a camera that is *rolled and pitched* reads as the vehicle
## under him doing it. So the tremor is mostly a few tenths of a degree of pitch
## and roll, with a millimetre or two of lift under it for the potholes.
##
## The node finds the camera itself, off whichever player is standing in the
## scene, and it does it every time it starts rather than once: the van outlives
## a respawn, and a player who fell out of the world comes back as the same node
## but the lookup is cheap and being wrong about it is a camera that stops
## moving for the rest of the shift.

## How far the camera pitches and rolls at full strength, in degrees. Small on
## purpose: a shake big enough to see clearly is a shake that makes people ill
## over two minutes.
@export var tilt_degrees := 0.32

## How far it lifts, in metres. A couple of millimetres — it is the road under
## the tyres, not a kerb.
@export var lift := 0.004

## How quickly the tremor runs, in cycles a second. Three numbers that do not
## divide into each other, so the three waves never come back round together and
## the loop has no period to hear.
@export var pitch_rate := 7.3
@export var roll_rate := 5.1
@export var lift_rate := 11.7

## How long the tremor takes to fade in when it starts and out when it stops, in
## seconds. The van does not go from still to shaking on one frame.
@export var fade_time := 0.6

## Whether the wheels are turning. Setting it false fades the tremor out and puts
## the camera back exactly where it was, rather than leaving it stopped at
## whatever angle the wave happened to be at.
@export var running := true:
	set(value):
		if running == value:
			return
		running = value
		set_process(true)

## Where in the waves we are, in seconds. Its own clock rather than
## `Time.get_ticks_msec`, so that a paused game has a still camera.
var _clock := 0.0

## How much of the tremor is being applied, nought to one. What `fade_time`
## moves, and what makes stopping the van settle rather than snap.
var _strength := 0.0

## The camera being shaken, and the transform it had before this node touched
## it. The rest position is taken once, the first time the camera is found: it
## is what everything is measured from and what is put back on the way out.
var _camera: Camera3D
var _rest := Transform3D.IDENTITY


func _ready() -> void:
	# The tremor is part of the world, not of the UI: a paused game is a game
	# with a still camera, so this stops with everything else.
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	if not _find_camera():
		return

	var target := 1.0 if running else 0.0
	if fade_time > 0.0:
		_strength = move_toward(_strength, target, delta / fade_time)
	else:
		_strength = target

	if _strength <= 0.0:
		# All the way out: the camera goes back to exactly where it started and
		# this node stops costing anything until it is asked to run again.
		_camera.transform = _rest
		set_process(running)
		return

	_clock += delta
	_apply()


## Puts the camera back and lets go of it. The van being unloaded does this
## anyway by taking the whole scene with it, but a player who walks out of a
## still-standing van — or a bench that swaps scenes — should not keep a
## half-tilted camera.
func _exit_tree() -> void:
	if _camera != null and is_instance_valid(_camera):
		_camera.transform = _rest


## One frame of tremor, measured from the rest transform rather than added to
## wherever the camera currently is. Accumulating would drift: two hundred
## frames of "a little more" is a camera looking at the floor.
func _apply() -> void:
	var pitch := sin(_clock * TAU * pitch_rate)
	var roll := sin(_clock * TAU * roll_rate)
	# The lift rides on the two tilts rather than running free, so that the
	# bump felt underfoot and the shake seen through the window are the same
	# bump. `absf` because a wheel goes over a pothole and comes back up, it
	# does not sink below the road and rise above it in equal measure.
	var bump := absf(sin(_clock * TAU * lift_rate))

	var swing := deg_to_rad(tilt_degrees) * _strength
	var basis := Basis.from_euler(Vector3(pitch * swing, 0.0, roll * swing))
	_camera.transform = Transform3D(
		_rest.basis * basis,
		_rest.origin + Vector3(0.0, bump * lift * _strength, 0.0))


## The camera to shake, off whoever is standing in the scene. Found lazily and
## remembered: on the frame the van comes up the player may not have run his own
## `_ready` yet, and a node that gave up looking then would never shake at all.
func _find_camera() -> bool:
	if _camera != null and is_instance_valid(_camera):
		return true
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	_camera = player.camera as Camera3D
	if _camera == null:
		return false
	_rest = _camera.transform
	return true
