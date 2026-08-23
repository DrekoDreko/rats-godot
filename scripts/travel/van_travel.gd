class_name VanTravel
extends Node3D
## The van once it has pulled off: what is turning, what is rattling and what is
## switched on, all of it hung off the one question of whether the shift is
## actually on the road.
##
## The scene is the lobby's van with the back shut, but the *state* is not the
## lobby's, and this node is what holds the difference. Four things follow the
## phase together — the world going past the windows (`RoadScroll`), the tremor
## in the camera (`CabinShake`), the trip in the ceiling lamp and the engine on
## the speakers — and they follow it from here rather than each listening on
## their own, so that a van that is not moving is not moving in all four ways at
## once.
##
## **It reads the phase, it does not assume it.** The obvious version of this
## node starts everything in `_ready` and never stops: this scene *is* the road,
## after all. But a scene is a file, and this one is opened by benches, by a
## later card that wants to look at the interior, and — the case that matters —
## by the phase machine, which then changes the phase *after* the scene is
## standing (`PhaseManager._change_scene`). A van that only reacted to
## `phase_changed` would be a van that missed its own arrival. So the state is
## read on the way up and re-read on every change, which is the same shape
## `VanSpawns._apply_belt_lock` uses and for the same reason.
##
## **The belt is somebody else's.** The card says weapons are enabled here, and
## they already are: the lock belongs to `VanSpawns`, which bars the slots in the
## lobby and unbars them everywhere else — including here. Doing it a second time
## from this node would be a second place the answer could be wrong.
##
## **The clock is somebody else's too.** Two minutes on the road is
## `Phase.DURATION[TRAVEL]`, and it is the host's `Timer` in `PhaseManager` that
## runs it and his `advance()` that ends it. Nothing here counts anything: the
## card asks that the timer start when the phase does, and it does that already
## by being the phase's own timer.

## The road and the props going past. Turned off the moment the van is not
## travelling, so a van standing in another phase is a van with a still world
## outside it rather than one quietly driving nowhere.
@export var road_path: NodePath = ^"Road"

## The tremor in the camera.
@export var shake_path: NodePath = ^"CabinShake"

## The ceiling lamp that trips as the van goes over things. Optional — a van
## grey-boxed without one still drives.
@export var lamp_path: NodePath = ^"Van/Lamps/Front"

## The engine and the radio: two loops, both of them running only while the
## wheels are.
@export var engine_path: NodePath = ^"Audio/Engine"
@export var radio_path: NodePath = ^"Audio/Radio"

## How much the ceiling lamp dips and how often, as a fraction of its own
## brightness and in cycles a second. A fluorescent tube in a truck does not
## blink on and off — it browns out as the alternator loads up — so this is a
## dip and not a flicker.
const LAMP_DIP := 0.28
const LAMP_RATE := 8.7
## And an occasional deeper one, slow enough to read as a separate event rather
## than as part of the buzz.
const LAMP_TRIP_RATE := 0.63
const LAMP_TRIP_DIP := 0.22

@onready var _road: RoadScroll = get_node_or_null(road_path) as RoadScroll
@onready var _shake: CabinShake = get_node_or_null(shake_path) as CabinShake
@onready var _lamp: OmniLight3D = get_node_or_null(lamp_path) as OmniLight3D
@onready var _engine: AudioStreamPlayer = get_node_or_null(engine_path) as AudioStreamPlayer
@onready var _radio: AudioStreamPlayer = get_node_or_null(radio_path) as AudioStreamPlayer

## What the ceiling lamp burns at when nothing is dipping it, read off the scene
## so that dimming the van in the editor dims it here too.
var _lamp_energy := 0.0

## Its own clock for the lamp, so a paused game has a steady light.
var _clock := 0.0

## Whether the wheels are turning. One answer, and everything reads it.
var _moving := false


func _ready() -> void:
	if _lamp != null:
		_lamp_energy = _lamp.light_energy

	_apply_state()
	PhaseManager.phase_changed.connect(_on_phase_changed)


func _process(delta: float) -> void:
	_clock += delta
	_flicker_lamp()


## Whether the van is on the road right now. The benches ask; so does anything
## later that wants to know whether it may open a shop hatch.
func is_moving() -> bool:
	return _moving


## Everything that follows the phase, set from the phase. One function, called on
## the way up and on every change, so that there is no state the van can arrive
## in that this has not already handled.
func _apply_state() -> void:
	_moving = PhaseManager.current() == Phase.Type.TRAVEL

	if _road != null:
		_road.running = _moving
	if _shake != null:
		_shake.running = _moving

	_play(_engine, _moving)
	_play(_radio, _moving)

	# The lamp only needs a frame of its own while it is tripping. A parked van
	# gets its steady light back and this node stops costing anything.
	set_process(_moving and _lamp != null)
	if not _moving and _lamp != null:
		_lamp.light_energy = _lamp_energy


## The ceiling lamp browning out as the van works. Two waves at rates that do
## not divide into each other, the same trick the camera tremor uses: a buzz
## underneath and an occasional deeper trip over it, and no period a player can
## hear coming.
func _flicker_lamp() -> void:
	if _lamp == null:
		return
	var buzz := sin(_clock * TAU * LAMP_RATE) * 0.5 + 0.5
	var trip := sin(_clock * TAU * LAMP_TRIP_RATE) * 0.5 + 0.5
	# Multiplied rather than added: two dips at once is darker than either, the
	# way a lamp that is already browning out goes further down over a pothole.
	var factor := (1.0 - LAMP_DIP * buzz) * (1.0 - LAMP_TRIP_DIP * trip * trip)
	_lamp.light_energy = _lamp_energy * factor


## A loop, started or stopped. Every player is optional and so is every stream:
## the van has to drive in a project with no audio in it yet, which is the state
## it is being built in.
func _play(player: AudioStreamPlayer, should_play: bool) -> void:
	if player == null or player.stream == null:
		return
	if should_play == player.playing:
		return
	if should_play:
		player.play()
	else:
		player.stop()


func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_apply_state()
