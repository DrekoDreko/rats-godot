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
## - The transition plays the rat screech; nothing about how the house is drawn
##   changes, since the PS1 shader draws every surface unshaded.
## - Host spawns rats based on `SessionManager.random_seed` and the contract's
##   infestation level in nests far from player front-door spawns.
## - Visual highlights on rat holes are extinguished.
## - Attack weapons unlocked in the inventory belt.
## - Trap installation takes longer arming cooldown.
## - The phase ends on whichever comes first: the last rat cleared out of the
##   house, or the clock the crew booked in the van running out (`HuntTime` —
##   ten minutes at face value, five at double, two at five times). Either way
##   the shift advances to RESULT, and whatever is still loose stays in the
##   walls unpaid for.

@export var traps_root_path: NodePath = ^"Traps"
@export var rats_root_path: NodePath = ^"Rats"
@export var geometry_root_path: NodePath = ^"Geometry"

@export_group("Audio")
@export var screech_audio_path: NodePath = ^"Audio/Screech"

const DEFAULT_INFESTATION := 6
const RAT_SCENE_PATH := "res://scenes/rat.tscn"
## The peer that thinks for every rat on the map. It is the same 1 that
## `PhaseManager` uses, written out again rather than reached through the
## autoload: an autoload has no global *name* until it is in the tree, so a
## bench that loads this file early would fail to compile it — and the failure
## shows up as a house with no script rather than as a missing constant.
const HOST_PEER := 1

@onready var _traps_root: Node3D = get_node_or_null(traps_root_path) as Node3D
@onready var _rats_root: Node3D = get_node_or_null(rats_root_path) as Node3D
# No `_holes_root`: the holes are found by their `rat_holes` group instead, which
# picks them up wherever the level put them rather than only under one node.
@onready var _geometry_root: Node3D = get_node_or_null(geometry_root_path) as Node3D

@onready var _screech_audio: AudioStreamPlayer = get_node_or_null(screech_audio_path) as AudioStreamPlayer

var _loaded_house_path := ""
var _rats_spawned := false
var _hunt_completed := false


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
	# Counted by what a child *is* rather than by how many there are: the
	# container also holds the `MultiplayerSpawner` that replicates the rats, and
	# that is not an animal.
	var count := 0
	for child in _rats_root.get_children():
		if child is CharacterBody3D:
			count += 1
	return count


## Total number of active (alive, non-captured/unvanished) rats in the house.
func active_rat_count() -> int:
	if _rats_root == null:
		return 0
	var count := 0
	for child in _rats_root.get_children():
		var rat := child as CharacterBody3D
		if rat != null and is_instance_valid(rat):
			if rat.has_method("is_dead") and rat.is_dead():
				continue
			count += 1
	return count


## Rats the shift has not finished with: the ones still running, and the dead
## ones nobody has been paid for yet.
##
## **The second half is what keeps the pay slip honest.** A rat strangled in the
## hand dies at the last squeeze and only turns into money at the end of the
## gesture, when the body reaches the waist (`rat.gd::_pay_reward`). A hunt that
## ended the moment the animal stopped moving would end while its own catch was
## still in mid-air — and `ShiftReport` files nothing outside the hunt, so the
## last rat of the shift would be caught, paid for, and missing off the slip.
## So the house waits for the money, not only for the death.
func pending_rat_count() -> int:
	if _rats_root == null:
		return 0
	var count := 0
	for child in _rats_root.get_children():
		var rat := child as CharacterBody3D
		if rat == null or not is_instance_valid(rat):
			continue
		var dead: bool = rat.has_method("is_dead") and rat.is_dead()
		if not dead:
			count += 1
			continue
		if rat.has_method("is_paid") and not rat.is_paid():
			count += 1
	return count


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
		if is_transition and _screech_audio != null:
			_screech_audio.play()
		# Opened before the rats are put in, and on every machine rather than
		# only on the host: the guest spawns nothing — the `MultiplayerSpawner`
		# brings him his animals — but he still has a pay slip to fill in, and
		# it needs to know how many rats the house was let with.
		if is_transition:
			ShiftReport.begin(_contract_infestation())
		_spawn_rats_if_needed()


## How many rats this contract puts in the walls. Asked in two places — by the
## host that spawns them and by every machine's pay slip — so the fallback for a
## contract that names none is written once and both get the same answer.
func _contract_infestation() -> int:
	var contract := ContractManager.current()
	var infestation: int = contract.infestation if contract != null else DEFAULT_INFESTATION
	return infestation if infestation > 0 else DEFAULT_INFESTATION


## Spawns the rats authoritative on the host using SessionManager.random_seed and Contract.infestation.
func _spawn_rats_if_needed() -> void:
	if _rats_spawned:
		return
	if not PhaseManager.is_host():
		return

	_rats_spawned = true
	var infestation := _contract_infestation()

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
				# Everything that has to be true of a rat *before* it is in the
				# tree is settled here, and the order is not cosmetic. The
				# `MultiplayerSpawner` over this container replicates the animal
				# the moment it is added, and what it sends is what it finds at
				# that moment:
				#
				# - The name, or the guest builds a rat called `@CharacterBody3D@12`
				#   while the host has `Rat_3`, and two nodes that do not share a
				#   path never hear each other again.
				# - The authority, so that the rat wakes up on the guest already
				#   knowing it is not the one doing the thinking (`rat.gd::_ready`).
				# - The position, or the rat is replicated at the origin and walks
				#   to its nest on the guest's screen.
				rat.name = "Rat_%d" % (i + 1)
				rat.set_multiplayer_authority(HOST_PEER)
				rat.position = base_pos + offset
				_rats_root.add_child(rat)
				if rat.has_signal("died"):
					rat.died.connect(_on_rat_died)


## Deferred, and that is the whole of it: `died` is emitted *before* the rat
## pays out (`rat.gd::_die`), so a check run on the spot would end the hunt one
## line before the last catch was recorded. A frame later the money has landed.
func _on_rat_died(_rat: Node3D, _type: int) -> void:
	if PhaseManager.current() == Phase.Type.HUNT and PhaseManager.is_host():
		_check_hunt_completion.call_deferred()


## Whether the house is clear, and if it is, on to the pay slip. This is one of
## the two ways the hunt ends; the other is the booked clock running out, which
## is the phase machine's own timer and needs nothing from here — the guard above
## sees the phase has already moved and this stops asking.
func _check_hunt_completion() -> void:
	if _hunt_completed or not _rats_spawned:
		return
	if PhaseManager.current() != Phase.Type.HUNT or not PhaseManager.is_host():
		return

	if pending_rat_count() == 0:
		_hunt_completed = true
		PhaseManager.advance()


func _on_phase_changed(previous: Phase.Type, current: Phase.Type) -> void:
	# The house is announced to after the scene change has already happened
	# (`PhaseManager._change_scene`), so a house on its way out still hears the
	# phase that replaced it — out of the tree, one frame from being freed, and
	# every `get_tree()` below it null. There is nothing left here worth doing
	# for a scene nobody is standing in.
	if not is_inside_tree():
		return
	# The hunt is over however it ended. Latched here as well as in the check
	# above, because a hunt the clock ended leaves rats alive and would otherwise
	# never set this — and a `_process` still asking after the house is clear is
	# a question with no phase left to answer it.
	if previous == Phase.Type.HUNT:
		_hunt_completed = true
		# The clock on the slip is stopped here rather than when the screen is
		# drawn: the pay slip can sit unread for as long as the crew likes, and
		# a shift that goes on counting while nobody is playing it is not the
		# length of the hunt.
		ShiftReport.finish()
	var is_survey_to_hunt := previous == Phase.Type.SURVEY and current == Phase.Type.HUNT
	_update_phase_state(is_survey_to_hunt)
