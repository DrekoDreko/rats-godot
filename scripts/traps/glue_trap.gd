class_name GlueTrap
extends Trap
## Reusable capacity, lifetime and escape are owned by the host. The aim of the
## local player's own escape is the exception: the timing bar is beaten on the
## machine holding the mouse, and only the hits it lands are sent on.

const CAPACITY := 5
const LIFETIME := 40.0
const PLAYER_COST := 10.0
## Clicks that have to land in the green before the boot comes off the glue.
##
## Three and not the six presses this used to ask for, because each one now has
## to be *timed*: the player is not hammering a key, he is waiting for a pointer
## to cross a target that moves every go. Six of those is most of a minute stood
## still while the rats get on with their lives, which is a punishment rather
## than a struggle.
const ESCAPE_HITS := 3.0
## How long the pointer takes to cross the track, by hits already landed. It
## speeds up as the boot comes loose: the last pull is the quick one.
const SWEEP_SECONDS := [1.6, 1.2, 0.8]
## Width of the green, as a fraction of the track.
const ZONE_WIDTH := 0.22
## How far the green has to move between one go and the next, so the rhythm that
## landed the last hit is never the one that lands this one.
const MIN_ZONE_SHIFT := 0.18
## The shortest gap between two presses the host will count. The client is the
## one judging its own aim now, and this is what a peer claiming three hits in a
## single frame runs into. No honest hit can arrive faster: the green never
## reaches the end of the track the pointer starts from.
const PRESS_INTERVAL := 0.05
const PEEL_TIME := 0.25

var remaining := LIFETIME
var _rats: Dictionary = {}
var _blocked_rats: Array[Node3D] = []
var _players: Dictionary = {}
var _blocked_players: Array[int] = []
var _sync_time := 0.0
var _expired := false
## The timing bar the *local* player beats to pull free, and nobody else's: the
## aim is judged on the machine whose mouse it is, and only a hit that lands
## crosses the wire. The HUD reads these to draw the track (`glue_hud.gd`);
## everyone else's escape is the progress in `_players` and nothing more.
var sweep_pointer := 1.0
var sweep_zone_start := 0.0
var sweep_zone_width := ZONE_WIDTH
var _previous_zone_center := -1.0
var _sweeping := false

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
	_advance_sweep(delta)
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
			# The clock is kept only to rate-limit the presses (`PRESS_INTERVAL`).
			# Standing still costs nothing now: the pointer has to be beaten, and
			# progress that drained between two sweeps would make a hit worth
			# less than the wait it took to land.
			_players[peer].idle += delta
			continue
		if _blocked_players.has(peer) or _held_elsewhere(peer):
			continue
		_players[peer] = {"progress": 0.0, "idle": PRESS_INTERVAL, "anchor": body.global_position}
		remaining = maxf(0.0, remaining - PLAYER_COST)
		_publish_state()
		if remaining <= 0.0:
			return

func _held_elsewhere(peer: int) -> bool:
	for glue: Node in get_tree().get_nodes_in_group("glue_traps"):
		if glue != self and glue._players.has(peer):
			return true
	return false

## The local player clicked. Only a click with the pointer inside the green is
## worth anything, and either way the green moves: a miss costs a whole sweep.
func press_escape() -> void:
	if _local_state().is_empty():
		return
	var zone_end := sweep_zone_start + sweep_zone_width
	var hit := sweep_pointer >= sweep_zone_start and sweep_pointer <= zone_end
	_start_sweep()
	if not hit:
		return
	if _host():
		_accept_press(_local_peer())
	else:
		_request_press.rpc_id(get_multiplayer_authority())

func _local_peer() -> int:
	return multiplayer.get_unique_id() if _on_the_wire() else 1

func _local_state() -> Dictionary:
	return _players.get(_local_peer(), {})

## The pointer runs down the track and falls off the end as a miss, which is the
## whole of the pressure in it: nothing is lost by missing except the sweep, and
## the sweep is time spent stood on glue in a house full of rats.
func _advance_sweep(delta: float) -> void:
	if _local_state().is_empty():
		_sweeping = false
		return
	if not _sweeping:
		# Caught this frame: the first sweep starts whole rather than wherever
		# the last player's left the pointer.
		_sweeping = true
		_start_sweep()
		return
	# Read every frame rather than latched at the restart, so a hit confirmed by
	# the host a moment late still speeds up the sweep it belongs to.
	var hits := clampi(int(_local_state().get("progress", 0.0)), 0, SWEEP_SECONDS.size() - 1)
	sweep_pointer -= delta / SWEEP_SECONDS[hits]
	if sweep_pointer <= 0.0:
		_start_sweep()

## A fresh green, somewhere else along the track. Both ends are left clear so a
## target is never a reflex away from the instant the pointer sets off.
func _start_sweep() -> void:
	sweep_pointer = 1.0
	sweep_zone_width = ZONE_WIDTH
	var min_center := 0.08 + sweep_zone_width * 0.5
	var max_center := 0.92 - sweep_zone_width * 0.5
	var excluded_start := clampf(_previous_zone_center - MIN_ZONE_SHIFT, min_center, max_center)
	var excluded_end := clampf(_previous_zone_center + MIN_ZONE_SHIFT, min_center, max_center)
	var left_span := excluded_start - min_center
	var offset := randf_range(0.0, left_span + max_center - excluded_end)
	var center := min_center + offset if offset < left_span else excluded_end + offset - left_span
	sweep_zone_start = center - sweep_zone_width * 0.5
	_previous_zone_center = center

@rpc("any_peer", "reliable")
func _request_press() -> void:
	if _host():
		_accept_press(multiplayer.get_remote_sender_id())

func _accept_press(peer: int) -> void:
	if not _players.has(peer) or _expired:
		return
	var state: Dictionary = _players[peer]
	if float(state.idle) < PRESS_INTERVAL:
		return
	state.progress += 1.0
	state.idle = 0.0
	if float(state.progress) >= ESCAPE_HITS:
		_players.erase(peer)
		_blocked_players.append(peer)
	_publish_state()
	_apply_local_player()

func _apply_local_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("set_glue_state"):
		return
	var state := _local_state()
	player.set_glue_state(self, not state.is_empty(), float(state.get("progress", 0.0)) / ESCAPE_HITS,
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
