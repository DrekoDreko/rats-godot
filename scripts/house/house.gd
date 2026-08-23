class_name House
extends Node3D
## The House scene controller for SURVEY and HUNT phases (Card 12 & Card 13).
##
## **One scene for Survey and Hunt.** The house does not reload when the minute of
## survey is over: `PhaseManager` changes the phase to `HUNT` while keeping this
## scene on screen. Traps placed during survey remain in the `Traps` node, and
## nobody is teleported back to the doorstep.
##
## **Survey Phase (60s):**
## - Authoritative 60s timer running on the host and synced to all peers.
## - Zero rats spawned in the house.
## - All rat holes and escape routes stand out with visual highlights.
## - Attack weapons barred; only traps, map, bait, patches, flashlight, hands allowed.
## - Ready station at the front door allows the crew to advance early if all ready.
##
## **Hunt Phase (Card 13):**
## - Perceptible transition: 1-second blackout with rat screech audio, followed by
##   dark, atmospheric hunt lighting where flashlights become essential.
## - Host spawns rats based on `SessionManager.random_seed` and the contract's
##   infestation level in nests far from player front-door spawns.
## - Visual highlights on rat holes are extinguished.
## - Attack weapons unlocked in the inventory belt.
## - Trap installation takes longer arming cooldown.
## - No countdown timer: phase ends when all rats are eliminated or captured,
##   advancing to RESULT.

@export var traps_root_path: NodePath = ^"Traps"
@export var rats_root_path: NodePath = ^"Rats"
@export var holes_root_path: NodePath = ^"RatHoles"
@export var geometry_root_path: NodePath = ^"Geometry"

@export_group("Lighting Nodes")
@export var sun_path: NodePath = ^"Sun"
@export var environment_path: NodePath = ^"Environment"
@export var hallway_light_path: NodePath = ^"HallwayLight"
@export var kitchen_light_path: NodePath = ^"KitchenLight"
@export var living_light_path: NodePath = ^"LivingLight"

@export_group("Audio")
@export var screech_audio_path: NodePath = ^"Audio/Screech"

const SURVEY_SUN_ENERGY := 0.65
const SURVEY_AMBIENT_ENERGY := 0.35
const SURVEY_HALLWAY_ENERGY := 1.2
const SURVEY_KITCHEN_ENERGY := 1.1
const SURVEY_LIVING_ENERGY := 1.2

const HUNT_SUN_ENERGY := 0.05
const HUNT_AMBIENT_ENERGY := 0.08
const HUNT_HALLWAY_ENERGY := 0.25
const HUNT_KITCHEN_ENERGY := 0.2
const HUNT_LIVING_ENERGY := 0.25

const BLACKOUT_DURATION := 1.0
const DEFAULT_INFESTATION := 6
const RAT_SCENE_PATH := "res://scenes/rat.tscn"

@onready var _traps_root: Node3D = get_node_or_null(traps_root_path) as Node3D
@onready var _rats_root: Node3D = get_node_or_null(rats_root_path) as Node3D
@onready var _holes_root: Node3D = get_node_or_null(holes_root_path) as Node3D
@onready var _geometry_root: Node3D = get_node_or_null(geometry_root_path) as Node3D

@onready var _sun: DirectionalLight3D = get_node_or_null(sun_path) as DirectionalLight3D
@onready var _environment: WorldEnvironment = get_node_or_null(environment_path) as WorldEnvironment
@onready var _hallway_light: OmniLight3D = get_node_or_null(hallway_light_path) as OmniLight3D
@onready var _kitchen_light: OmniLight3D = get_node_or_null(kitchen_light_path) as OmniLight3D
@onready var _living_light: OmniLight3D = get_node_or_null(living_light_path) as OmniLight3D
@onready var _screech_audio: AudioStreamPlayer = get_node_or_null(screech_audio_path) as AudioStreamPlayer

var _loaded_house_path := ""
var _in_blackout := false
var _hunt_lighting_active := false
var _rats_spawned := false
var _hunt_completed := false
var _blackout_tween: Tween


func _ready() -> void:
	if _traps_root != null:
		_traps_root.add_to_group("traps_root")
	if _rats_root != null:
		_rats_root.add_to_group("rats_root")

	_setup_audio()
	_setup_contract_geometry()
	_update_phase_state(false)

	PhaseManager.phase_changed.connect(_on_phase_changed)


func _process(_delta: float) -> void:
	if PhaseManager.current() == Phase.Type.HUNT and PhaseManager.is_host():
		_check_hunt_completion()


## Persistent traps container node.
func traps_root() -> Node3D:
	return _traps_root


## Persistent rats container node.
func rats_root() -> Node3D:
	return _rats_root


## Total number of traps installed in the house.
func installed_trap_count() -> int:
	if _traps_root == null:
		return 0
	return _traps_root.get_child_count()


## Total number of rats spawned in the house.
func spawned_rat_count() -> int:
	if _rats_root == null:
		return 0
	return _rats_root.get_child_count()


## Total number of active (alive, non-captured/unvanished) rats in the house.
func active_rat_count() -> int:
	if _rats_root == null:
		return 0
	var count := 0
	for child in _rats_root.get_children():
		var rat := child as Node3D
		if rat != null and is_instance_valid(rat):
			if rat.has_method("is_dead") and rat.is_dead():
				continue
			count += 1
	return count


## Whether the house is currently experiencing the 1-second transition blackout.
func is_in_blackout() -> bool:
	return _in_blackout


## Whether the house is currently configured in dark hunt lighting.
func is_hunt_lighting() -> bool:
	return _hunt_lighting_active


## Dynamically loads custom house geometry from the signed contract if specified.
func _setup_contract_geometry() -> void:
	if _geometry_root == null:
		return
	var contract := ContractManager.current()
	if contract == null or contract.house_scene.is_empty():
		return
	var target_scene := contract.house_scene
	# A contract that names the scene already standing would load it inside
	# itself. `world.tscn` is that scene for every contract shipped today, so
	# the guard is what keeps `house_scene` free to name a different one later.
	if target_scene == scene_file_path or target_scene == "res://scenes/world.tscn":
		return
	if _loaded_house_path == target_scene:
		return

	_loaded_house_path = target_scene
	if ResourceLoader.exists(target_scene):
		var packed := ResourceLoader.load(target_scene) as PackedScene
		if packed != null:
			var instance := packed.instantiate()
			_geometry_root.add_child(instance)


func _setup_audio() -> void:
	if _screech_audio == null:
		_screech_audio = AudioStreamPlayer.new()
		_screech_audio.name = "Screech"
		_screech_audio.volume_db = -6.0
		add_child(_screech_audio)
	if _screech_audio.stream == null:
		_screech_audio.stream = _build_rat_screech()


## Generates a classic PSX 8-bit modulated rat screech / squeak sound.
func _build_rat_screech() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.7
	var frames := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(frames)
	var phase := 0.0
	for i in frames:
		var t := float(i) / float(frames)
		var freq := lerpf(2600.0, 1300.0, t) + sin(t * 75.0) * 220.0
		phase += freq / float(sample_rate)
		var saw := fmod(phase, 1.0) * 2.0 - 1.0
		var tremolo := 0.6 + 0.4 * sin(t * 110.0)
		var envelope := (1.0 - t) * (1.0 if t > 0.04 else t / 0.04)
		var sample := int(roundf(saw * tremolo * envelope * 85.0))
		data[i] = sample & 0xff

	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_8_BITS
	wave.mix_rate = sample_rate
	wave.stereo = false
	wave.data = data
	return wave


func _update_phase_state(is_transition: bool = false) -> void:
	var phase := PhaseManager.current()
	var is_survey := phase == Phase.Type.SURVEY
	var is_hunt := phase == Phase.Type.HUNT

	# Rat holes visual highlight (active in SURVEY, extinguished in HUNT)
	var holes := get_tree().get_nodes_in_group("rat_holes")
	for node in holes:
		if node.has_method("set_highlight"):
			node.set_highlight(is_survey)

	if is_hunt:
		if is_transition:
			_start_blackout_transition()
		else:
			_apply_hunt_lighting()
		_spawn_rats_if_needed()
	elif is_survey:
		_apply_survey_lighting()


## Blackout transition: cuts lights for 1 second, plays screech audio, then applies dark hunt lighting.
func _start_blackout_transition() -> void:
	_in_blackout = true
	_hunt_lighting_active = false

	if _blackout_tween != null and _blackout_tween.is_running():
		_blackout_tween.kill()

	# Instant blackout
	_set_light_energies(0.0, 0.0, 0.0, 0.0, 0.0)

	# Play rat screech sound effect
	if _screech_audio != null:
		_screech_audio.play()

	_blackout_tween = create_tween()
	_blackout_tween.tween_interval(BLACKOUT_DURATION)
	_blackout_tween.tween_callback(func() -> void:
		_in_blackout = false
		_apply_hunt_lighting()
	)


func _apply_survey_lighting() -> void:
	_in_blackout = false
	_hunt_lighting_active = false
	_set_light_energies(
		SURVEY_SUN_ENERGY,
		SURVEY_AMBIENT_ENERGY,
		SURVEY_HALLWAY_ENERGY,
		SURVEY_KITCHEN_ENERGY,
		SURVEY_LIVING_ENERGY
	)


func _apply_hunt_lighting() -> void:
	_hunt_lighting_active = true
	_set_light_energies(
		HUNT_SUN_ENERGY,
		HUNT_AMBIENT_ENERGY,
		HUNT_HALLWAY_ENERGY,
		HUNT_KITCHEN_ENERGY,
		HUNT_LIVING_ENERGY
	)


func _set_light_energies(sun_e: float, amb_e: float, hall_e: float, kit_e: float, liv_e: float) -> void:
	if _sun != null:
		_sun.light_energy = sun_e
	if _environment != null and _environment.environment != null:
		_environment.environment.ambient_light_energy = amb_e
	if _hallway_light != null:
		_hallway_light.light_energy = hall_e
	if _kitchen_light != null:
		_kitchen_light.light_energy = kit_e
	if _living_light != null:
		_living_light.light_energy = liv_e


## Spawns the rats authoritative on the host using SessionManager.random_seed and Contract.infestation.
func _spawn_rats_if_needed() -> void:
	if _rats_spawned:
		return
	if not PhaseManager.is_host():
		return

	_rats_spawned = true
	var contract := ContractManager.current()
	var infestation: int = contract.infestation if contract != null else DEFAULT_INFESTATION
	if infestation <= 0:
		infestation = DEFAULT_INFESTATION

	var seed_val: int = SessionManager.random_seed
	if seed_val == 0:
		seed_val = SessionManager.roll_seed()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# Ensure container exists
	if _rats_root == null:
		_rats_root = Node3D.new()
		_rats_root.name = "Rats"
		_rats_root.add_to_group("rats_root")
		add_child(_rats_root)

	# Find candidate nest / burrow spawn points
	var holes := get_tree().get_nodes_in_group("rat_holes")
	var spawn_positions: Array[Vector3] = []

	if holes.is_empty():
		spawn_positions = [
			Vector3(-10.0, 0.1, -10.0),
			Vector3(10.0, 0.1, -10.0),
			Vector3(-10.0, 0.1, -5.0),
			Vector3(10.0, 0.1, -5.0)
		]
	else:
		# Determine player position / front door reference point
		var front_door := Vector3(0.0, 0.0, 10.0)
		var player := get_tree().get_first_node_in_group("player") as Node3D
		var ref_point: Vector3 = player.global_position if player != null else front_door

		# Sort burrows by distance from players descending (placing rats in distant nests)
		var sorted_holes := holes.duplicate()
		sorted_holes.sort_custom(func(a: Node3D, b: Node3D) -> bool:
			return a.global_position.distance_to(ref_point) > b.global_position.distance_to(ref_point)
		)
		for hole in sorted_holes:
			spawn_positions.append(hole.global_position)

	if ResourceLoader.exists(RAT_SCENE_PATH):
		var rat_packed := ResourceLoader.load(RAT_SCENE_PATH) as PackedScene
		if rat_packed != null:
			for i in infestation:
				var rat := rat_packed.instantiate() as CharacterBody3D
				var base_pos: Vector3 = spawn_positions[i % spawn_positions.size()]
				var offset := Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
				_rats_root.add_child(rat)
				rat.global_position = base_pos + offset
				rat.name = "Rat_%d" % (i + 1)
				if rat.has_signal("died"):
					rat.died.connect(_on_rat_died)


func _on_rat_died(_rat: Node3D, _type: int) -> void:
	if PhaseManager.current() == Phase.Type.HUNT and PhaseManager.is_host():
		_check_hunt_completion()


func _check_hunt_completion() -> void:
	if _hunt_completed or not _rats_spawned:
		return
	if PhaseManager.current() != Phase.Type.HUNT or not PhaseManager.is_host():
		return

	if active_rat_count() == 0:
		_hunt_completed = true
		PhaseManager.advance()


func _on_phase_changed(previous: Phase.Type, current: Phase.Type) -> void:
	var is_survey_to_hunt := previous == Phase.Type.SURVEY and current == Phase.Type.HUNT
	_update_phase_state(is_survey_to_hunt)

