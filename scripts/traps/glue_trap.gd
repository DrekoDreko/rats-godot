class_name GlueTrap
extends Trap
## Reusable capacity, lifetime and escape are owned by the host.

const CAPACITY := 5
const LIFETIME := 40.0
const PLAYER_COST := 10.0
const ESCAPE_PRESSES := 6.0
const DECAY_DELAY := 0.35
const DECAY_RATE := 2.0
const PEEL_TIME := 0.25

var remaining := LIFETIME
var _rats: Dictionary = {}
var _blocked_rats: Array[Node3D] = []
var _players: Dictionary = {}
var _blocked_players: Array[int] = []
var _sync_time := 0.0
var _expired := false

func _ready() -> void:
	super._ready()
	add_to_group("glue_traps")
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if not _host() or not _armed or _rats.size() >= CAPACITY:
		return
	if not body.is_in_group("rats") or _blocked_rats.has(body):
		return
	if body.is_dead() or body.is_captured() or body.is_pinned():
		return
	_rats[_path_of(body)] = 0.0
	body.pin(self)
	caught.emit(body)
	_publish_state()

func _on_body_exited(body: Node3D) -> void:
	_blocked_rats.erase(body)

func released(rat: Node3D) -> void:
	if not _host():
		return
	_rats.erase(_path_of(rat))
	if overlaps_body(rat) and not _blocked_rats.has(rat):
		_blocked_rats.append(rat)
	_publish_state()

func prey() -> Node3D:
	for path: NodePath in _rats:
		return get_node_or_null(path) as Node3D
	return null

func _host() -> bool:
	return not _on_the_wire() or is_multiplayer_authority()

func _physics_process(delta: float) -> void:
	if _expired:
		return
	if _host():
		if SessionManager.phase != Phase.Type.SURVEY:
			remaining = maxf(0.0, remaining - delta)
		for path: NodePath in _rats.keys():
			var rat := get_node_or_null(path)
			if rat == null or rat.is_dead() or rat.is_captured() or not rat.is_pinned():
				_rats.erase(path)
				continue
			_rats[path] += delta
			var escape_time: float = rat.glue_escape_time()
			if escape_time > 0.0 and _rats[path] >= escape_time:
				rat.unpin()
		_update_players(delta)
		if remaining <= 0.0:
			_expire()
			return
		_sync_time += delta
		if _sync_time >= 0.1:
			_sync_time = 0.0
			_publish_state()
	_apply_local_player()
	var model_node := get_node_or_null("Model") as Node3D
	if model_node != null:
		model_node.scale.y = lerpf(0.25, 1.0, remaining / LIFETIME)

func _player_body(peer: int) -> Node3D:
	if not _on_the_wire() or peer == multiplayer.get_unique_id():
		return get_tree().get_first_node_in_group("player") as Node3D
	var avatars := get_tree().get_first_node_in_group("player_avatars_root")
	var avatar: Node3D = avatars.avatar_of(peer) if avatars != null else null
	if avatar is PlayerAvatar and not avatar._seen:
		return null
	return avatar

func _contains_player(body: Node3D) -> bool:
	var shape_node := get_node("Collision") as CollisionShape3D
	var box := shape_node.shape as BoxShape3D
	var point := shape_node.to_local(body.global_position)
	var stretch := shape_node.global_basis.get_scale().abs()
	return absf(point.x) <= box.size.x * 0.5 + 0.3 / stretch.x \
		and absf(point.z) <= box.size.z * 0.5 + 0.3 / stretch.z \
		and absf(point.y) <= 0.15 / stretch.y

func _update_players(delta: float) -> void:
	var peers: Array[int] = [1]
	if _on_the_wire():
		peers.assign(multiplayer.get_peers())
		peers.append(multiplayer.get_unique_id())
	for peer: int in _players.keys():
		if not peers.has(peer):
			_players.erase(peer)
	for peer: int in peers:
		var body := _player_body(peer)
		if body == null or (body.has_method("is_dead") and body.is_dead()) \
				or (body.has_method("is_seated") and body.is_seated()):
			_players.erase(peer)
			continue
		var inside := _contains_player(body)
		if not inside:
			_blocked_players.erase(peer)
			_players.erase(peer)
			continue
		if _players.has(peer):
			var state: Dictionary = _players[peer]
			var previous_idle: float = state.idle
			state.idle += delta
			var decay_delta := maxf(0.0, float(state.idle) - DECAY_DELAY) \
				- maxf(0.0, previous_idle - DECAY_DELAY)
			state.progress = maxf(0.0, float(state.progress) - DECAY_RATE * decay_delta)
			continue
		if _blocked_players.has(peer) or _held_elsewhere(peer):
			continue
		_players[peer] = {"progress": 0.0, "idle": 0.05, "anchor": body.global_position}
		remaining = maxf(0.0, remaining - PLAYER_COST)
		_publish_state()
		if remaining <= 0.0:
			return

func _held_elsewhere(peer: int) -> bool:
	for glue: Node in get_tree().get_nodes_in_group("glue_traps"):
		if glue != self and glue._players.has(peer):
			return true
	return false

func press_escape() -> void:
	if _host():
		_accept_press(multiplayer.get_unique_id() if _on_the_wire() else 1)
	else:
		_request_press.rpc_id(get_multiplayer_authority())

@rpc("any_peer", "reliable")
func _request_press() -> void:
	if _host():
		_accept_press(multiplayer.get_remote_sender_id())

func _accept_press(peer: int) -> void:
	if not _players.has(peer) or _expired:
		return
	var state: Dictionary = _players[peer]
	if float(state.idle) < 0.05:
		return
	state.progress += 1.0
	state.idle = 0.0
	if float(state.progress) >= ESCAPE_PRESSES:
		_players.erase(peer)
		_blocked_players.append(peer)
	_publish_state()
	_apply_local_player()

func _apply_local_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("set_glue_state"):
		return
	var peer := multiplayer.get_unique_id() if _on_the_wire() else 1
	var state: Dictionary = _players.get(peer, {})
	player.set_glue_state(self, not state.is_empty(), float(state.get("progress", 0.0)) / ESCAPE_PRESSES,
		state.get("anchor", player.global_position))

func _publish_state() -> void:
	if _on_the_wire() and _host():
		_receive_state.rpc(remaining, _rats, _players)

@rpc("authority", "call_remote", "reliable")
func _receive_state(time_left: float, rats: Dictionary, players: Dictionary) -> void:
	remaining = time_left
	for path: NodePath in _rats:
		if not rats.has(path):
			var rat := get_node_or_null(path)
			if rat != null and rat.is_pinned_by(self):
				rat.unpin()
	_rats = rats
	_players = players
	for path: NodePath in _rats:
		var rat := get_node_or_null(path)
		if rat != null:
			rat.pin(self)
	_apply_local_player()
	if remaining <= 0.0 and not _expired:
		_expired = true
		_armed = false
		_peel()

func _expire() -> void:
	_expired = true
	_armed = false
	for path: NodePath in _rats.keys():
		var rat := get_node_or_null(path)
		if rat != null and rat.is_pinned_by(self):
			rat.unpin()
	_rats.clear()
	_players.clear()
	_publish_state()
	_apply_local_player()
	_peel()

func _peel() -> void:
	set_deferred("monitoring", false)
	var tween := create_tween()
	tween.tween_property(self, "scale:y", 0.02, PEEL_TIME)
	if _host():
		tween.tween_callback(queue_free)

func _exit_tree() -> void:
	for path: NodePath in _rats.keys():
		var rat := get_node_or_null(path)
		if rat != null and not rat.is_queued_for_deletion() and rat.is_pinned_by(self):
			rat.unpin()
	_players.clear()
	_apply_local_player()

func status_text() -> String:
	return "%ds · %d/%d" % [ceili(remaining), _rats.size(), CAPACITY]

func escape_urgency(rat: Node3D) -> float:
	var duration: float = rat.glue_escape_time()
	if duration <= 0.0:
		return 0.0
	return clampf((float(_rats.get(_path_of(rat), 0.0)) - duration + 5.0) / 5.0, 0.0, 1.0)
