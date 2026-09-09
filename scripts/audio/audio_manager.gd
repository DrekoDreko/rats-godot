extends Node
## Runtime audio service. WAV files are loaded once and players are created only
## for the sound that is currently needed.

const AUDIO_FOLDER := "res://audio"
const WRAPPER_GROUP := &"game_post_process_wrapper"
const HOST_PEER := 1
const MAX_NETWORK_EVENTS_PER_SECOND := 40
const NETWORKED_SOUNDS := {
	"step_rock": true,
	"landing_rock": true,
	"item_equip": true,
	"step_grass": true,
	# A rat being strangled and the moment it gives. Both belong on the wire for
	# the same reason the footsteps do: they say where somebody is and what he is
	# doing, and a hunt in which you cannot hear a colleague working in the next
	# room is a hunt happening on four separate screens.
	"rat_hurt": true,
	"rat_death": true,
}

var _streams: Dictionary[String, AudioStream] = {}
var _loops: Dictionary[int, AudioStreamPlayer3D] = {}
var _event_times: Dictionary = {}
var _music_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_audio(AUDIO_FOLDER)


## Plays a one-shot sound in the local UI mix.
func play_ui(sound_id: String, pitch_scale := 1.0, volume_db := 0.0) -> void:
	var stream := _stream(sound_id)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.bus = "SFX"
	player.stream = stream
	player.pitch_scale = clampf(pitch_scale, 0.1, 4.0)
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Plays a one-shot sound at a world position or on an optional world anchor.
func play_3d(sound_id: String, position: Vector3, volume_db := 0.0,
		pitch_scale := 1.0, anchor: Node3D = null) -> void:
	_play_3d_local(sound_id, position, volume_db, pitch_scale, anchor)


## Plays a world sound locally and relays it to the other peers. The originating
## client is excluded from the relay because it already played the sound.
func play_networked_3d(sound_id: String, position: Vector3, volume_db := 0.0,
		pitch_scale := 1.0, local_anchor: Node3D = null) -> void:
	if not _valid_network_event(sound_id, position, volume_db, pitch_scale):
		return
	_play_3d_local(sound_id, position, volume_db, pitch_scale, local_anchor)
	if not _on_wire():
		return
	if _is_host():
		_relay_to_peers(sound_id, position, volume_db, pitch_scale, -1)
		return
	_request_3d.rpc_id(HOST_PEER, sound_id, position, volume_db, pitch_scale)


## Starts or keeps alive a looping spatial sound attached to an anchor.
func play_loop_3d(sound_id: String, anchor: Node3D, volume_db := 0.0,
		pitch_scale := 1.0) -> void:
	if anchor == null or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	var stream := _loop_stream(sound_id)
	if stream == null:
		return
	var key := anchor.get_instance_id()
	var player := _loops.get(key) as AudioStreamPlayer3D
	if player != null and is_instance_valid(player):
		if not player.playing:
			player.play()
		return

	player = AudioStreamPlayer3D.new()
	player.name = "Audio_%s" % sound_id
	player.bus = "SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch_scale, 0.1, 4.0)
	player.unit_size = 3.0
	player.max_distance = 20.0
	anchor.add_child(player)
	_loops[key] = player
	player.tree_exited.connect(_forget_loop.bind(key))
	player.play()


func stop_loop_3d(anchor: Node3D) -> void:
	if anchor == null:
		return
	var key := anchor.get_instance_id()
	var player := _loops.get(key) as AudioStreamPlayer3D
	_loops.erase(key)
	if player == null or not is_instance_valid(player):
		return
	player.stop()
	player.queue_free()


## Starts the one music loop owned by the manager. Starting another track stops
## the previous one.
func play_music(sound_id: String, volume_db := 0.0, pitch_scale := 1.0) -> AudioStreamPlayer:
	var stream := _loop_stream(sound_id)
	if stream == null:
		return null
	stop_music()
	var player := AudioStreamPlayer.new()
	player.bus = "Music"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch_scale, 0.1, 4.0)
	add_child(player)
	_music_player = player
	player.play()
	return player


func stop_music() -> void:
	if _music_player == null or not is_instance_valid(_music_player):
		_music_player = null
		return
	_music_player.stop()
	_music_player.queue_free()
	_music_player = null


@rpc("any_peer", "unreliable")
func _request_3d(sound_id: String, position: Vector3, volume_db: float,
		pitch_scale: float) -> void:
	if not _is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not _valid_network_event(sound_id, position, volume_db, pitch_scale):
		return
	if not _within_rate_limit(sender):
		return
	_play_3d_local(sound_id, position, volume_db, pitch_scale)
	_relay_to_peers(sound_id, position, volume_db, pitch_scale, sender)


@rpc("authority", "unreliable")
func _receive_3d(sound_id: String, position: Vector3, volume_db: float,
		pitch_scale: float) -> void:
	if multiplayer.get_remote_sender_id() != HOST_PEER:
		return
	if not _valid_network_event(sound_id, position, volume_db, pitch_scale):
		return
	_play_3d_local(sound_id, position, volume_db, pitch_scale)


func _load_audio(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		push_warning("AudioManager: audio directory not found: %s" % path)
		return
	for file_name in directory.get_files():
		if not file_name.to_lower().ends_with(".wav"):
			continue
		var stream := ResourceLoader.load(path.path_join(file_name)) as AudioStream
		if stream == null:
			push_warning("AudioManager: could not load %s" % file_name)
			continue
		var sound_id := file_name.get_basename()
		if _streams.has(sound_id):
			push_warning("AudioManager: duplicate sound id: %s" % sound_id)
			continue
		_streams[sound_id] = stream
	for directory_name in directory.get_directories():
		_load_audio(path.path_join(directory_name))


func _stream(sound_id: String) -> AudioStream:
	var stream := _streams.get(sound_id) as AudioStream
	if stream == null:
		push_warning("AudioManager: unknown sound id: %s" % sound_id)
	return stream


func _loop_stream(sound_id: String) -> AudioStream:
	var stream := _stream(sound_id)
	if stream is AudioStreamWAV:
		var looped := stream.duplicate() as AudioStreamWAV
		looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
		return looped
	return stream


func _play_3d_local(sound_id: String, position: Vector3, volume_db: float,
		pitch_scale: float, anchor: Node3D = null) -> void:
	var stream := _stream(sound_id)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.name = "Audio_%s" % sound_id
	player.bus = "SFX"
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = clampf(pitch_scale, 0.1, 4.0)
	player.unit_size = 3.0
	player.max_distance = 20.0
	var parent := anchor if anchor != null and anchor.is_inside_tree() else _world_parent()
	if parent == null:
		return
	parent.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()


## Anchorless world sounds need a node inside the gameplay SubViewport, because
## that is the only viewport with a current 3D listener. The gameplay scene root
## is not always a Node3D (the lobby is a Control), so the viewport itself is the
## parent: it accepts Node3D children and outlives every scene swap.
func _world_parent() -> Node:
	var wrapper := _wrapper()
	if wrapper == null:
		return null
	var scene := wrapper.current_game_scene() as Node
	if scene is Node3D:
		return scene
	return scene.get_viewport() if scene != null else null


func _wrapper() -> GamePostProcessWrapper:
	var tree := get_tree()
	if tree == null:
		return null
	for node in tree.get_nodes_in_group(WRAPPER_GROUP):
		var wrapper := node as GamePostProcessWrapper
		if wrapper != null:
			return wrapper
	return tree.root.get_node_or_null(^"GamePostProcessWrapper") as GamePostProcessWrapper


func _relay_to_peers(sound_id: String, position: Vector3, volume_db: float,
		pitch_scale: float, excluded_peer: int) -> void:
	for peer_id in multiplayer.get_peers():
		if peer_id != excluded_peer:
			_receive_3d.rpc_id(peer_id, sound_id, position, volume_db, pitch_scale)


func _valid_network_event(sound_id: String, position: Vector3, volume_db: float,
		pitch_scale: float) -> bool:
	return NETWORKED_SOUNDS.has(sound_id) and _streams.has(sound_id) \
		and position.is_finite() and maxf(absf(position.x), maxf(absf(position.y), absf(position.z))) <= 1000.0 \
		and is_finite(volume_db) and volume_db >= -60.0 and volume_db <= 6.0 \
		and is_finite(pitch_scale) and pitch_scale >= 0.1 and pitch_scale <= 4.0


func _within_rate_limit(peer_id: int) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var events: Array = _event_times.get(peer_id, [])
	while not events.is_empty() and now - events[0] > 1.0:
		events.pop_front()
	if events.size() >= MAX_NETWORK_EVENTS_PER_SECOND:
		_event_times[peer_id] = events
		return false
	events.append(now)
	_event_times[peer_id] = events
	return true


func _forget_loop(key: int) -> void:
	_loops.erase(key)


func _is_host() -> bool:
	return not _on_wire() or multiplayer.get_unique_id() == HOST_PEER


func _on_wire() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer
