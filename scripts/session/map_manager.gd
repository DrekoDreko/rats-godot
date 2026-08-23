extends Node
## The table where the plan of the house is spread out, and the markers the crew
## sticks into it before walking through the door.
##
## Four men walking into an unknown house in the dark is four men working
## at cross purposes unless they agreed beforehand: who takes the kitchen, who
## watches the cellar stairs, and where the first traps are laid. The map table
## is where that agreement is hammered out.
##
## **The host holds the board.** A man pressing the map does not plant a pin on
## his own say-so; he asks for one (`request_place_pin`), the host checks the
## coordinates and the limit, and either broadcasts the new marker to everybody
## (`_apply_place_pin`) or turns him down (`_refuse`). That is the same round trip
## the shelf and the colour panel make, and for the same reason: two men
## planting a pin on the same doorway in the same frame both get their mark down
## if either writes locally, and the host's answer is what keeps all four screens
## showing the exact same strategy.
##
## **Three pins per man.** A plan covered in fifty pins is no plan at all. Each
## player is allowed at most three markers on the sheet. When a man reaches for a
## fourth, his oldest marker is lifted and moved to the new spot — FIFO, so he
## never has to stop and clear the board before pointing at something new.
##
## **Coloured by jumpsuit.** Every marker is painted in the colour of the man who
## planted it (`SessionManager.color`), so the team can tell who volunteered for
## what without reading initials or asking over the radio.
##
## **Wiped with the contract.** A new job is a new house: when the leader signs a
## fresh sheet (`ContractManager.contract_signed`) or the shift resets, the old
## pins come off the board. When a man walks out of the van
## (`SessionManager.player_left`), his pins go with him so the crew is not left
## relying on a man who is not there.

## A marker was placed or moved on the board.
signal pin_placed(steam_id: int, pos: Vector2, color: Color)
## A marker was pulled up.
signal pin_removed(steam_id: int, pin_index: int)
## A man cleared all his markers off the board.
signal pins_cleared(steam_id: int)
## The whole set of pins moved or was re-synced. Listeners redraw their pins off this.
signal pins_updated()
## A placement or removal was refused. Emitted only on the asking machine.
signal request_refused(reason: String)

## The peer that decides. Peer 1, the same host peer used across the session.
const HOST_PEER := 1

## How many pins each player may keep on the board at once.
const MAX_PINS_PER_PLAYER := 3

## What a client is told when his request cannot be honoured.
const REFUSAL_NOT_IN_CREW := "You are not registered in this crew."
const REFUSAL_OUT_OF_BOUNDS := "That point is off the edge of the plan."
const REFUSAL_NO_CONTRACT := "No contract has been signed yet."

## Every pin currently on the board.
## Each entry is a Dictionary:
## {
##   "steam_id": int,
##   "pos": Vector2,  # Normalized (0.0 .. 1.0, 0.0 .. 1.0)
##   "color": Color,
## }
var pins: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# When a player drops out, clear their markers.
	SessionManager.player_left.connect(_on_player_left)
	# When a new contract is signed, wipe the previous house's pins.
	ContractManager.contract_signed.connect(_on_contract_signed)


## How many total markers are stuck in the board right now.
func count() -> int:
	return pins.size()


## How many pins a specific player currently has on the board.
func count_for(steam_id: int) -> int:
	var total := 0
	for pin in pins:
		if pin.get("steam_id", 0) == steam_id:
			total += 1
	return total


## All markers belonging to a given player, in placement order.
func pins_for(steam_id: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pin in pins:
		if pin.get("steam_id", 0) == steam_id:
			result.append(pin.duplicate())
	return result


## All pins on the board as a duplicate list.
func all_pins() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pin in pins:
		result.append(pin.duplicate())
	return result


## Asks the host to place a pin at normalized position (0..1, 0..1).
## If the player already has 3 pins, the oldest is replaced.
func request_place_pin(steam_id: int, pos: Vector2) -> void:
	if steam_id == 0:
		return
	if PhaseManager.is_host():
		_handle_place(steam_id, pos, _our_peer_id())
		return
	_request_place.rpc_id(HOST_PEER, steam_id, pos)


## Asks the host to remove a specific pin by index among that player's pins (0..2).
func request_remove_pin(steam_id: int, pin_index: int) -> void:
	if steam_id == 0:
		return
	if PhaseManager.is_host():
		_handle_remove(steam_id, pin_index, _our_peer_id())
		return
	_request_remove.rpc_id(HOST_PEER, steam_id, pin_index)


## Asks the host to remove all pins belonging to a player.
func request_clear_pins(steam_id: int) -> void:
	if steam_id == 0:
		return
	if PhaseManager.is_host():
		_handle_clear(steam_id, _our_peer_id())
		return
	_request_clear.rpc_id(HOST_PEER, steam_id)


## Clears all pins from the board immediately. Host only or local reset.
func clear_all_pins() -> void:
	pins.clear()
	pins_updated.emit()


## A serializable snapshot of all pins for a newcomer joining the shift.
func state() -> Array[Dictionary]:
	return all_pins()


## Adopts pin state from the host packet.
func adopt(pins_data: Array) -> void:
	pins.clear()
	for item in pins_data:
		if item is Dictionary:
			pins.append({
				"steam_id": int(item.get("steam_id", 0)),
				"pos": Vector2(item.get("pos", Vector2.ZERO)),
				"color": Color(item.get("color", Color.WHITE)),
			})
	pins_updated.emit()

# --- The Wire ---------------------------------------------------------------

@rpc("any_peer", "reliable")
func _request_place(steam_id: int, pos: Vector2) -> void:
	if not PhaseManager.is_host():
		push_warning("MapManager: place pin request reached a non-host peer.")
		return
	_handle_place(steam_id, pos, multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func _request_remove(steam_id: int, pin_index: int) -> void:
	if not PhaseManager.is_host():
		push_warning("MapManager: remove pin request reached a non-host peer.")
		return
	_handle_remove(steam_id, pin_index, multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func _request_clear(steam_id: int) -> void:
	if not PhaseManager.is_host():
		push_warning("MapManager: clear pins request reached a non-host peer.")
		return
	_handle_clear(steam_id, multiplayer.get_remote_sender_id())


func _handle_place(steam_id: int, pos: Vector2, from_peer: int) -> void:
	if not _may_speak_for(from_peer, steam_id):
		push_warning("MapManager: peer %d tried to place a pin for %d." % [from_peer, steam_id])
		return
	if not SessionManager.has_player(steam_id):
		_refuse_to(from_peer, REFUSAL_NOT_IN_CREW)
		return
	if pos.x < 0.0 or pos.x > 1.0 or pos.y < 0.0 or pos.y > 1.0:
		_refuse_to(from_peer, REFUSAL_OUT_OF_BOUNDS)
		return

	# Clamp to safety
	var safe_pos := Vector2(clampf(pos.x, 0.0, 1.0), clampf(pos.y, 0.0, 1.0))
	var player_color := SessionManager.color(steam_id)

	_apply_place.rpc(steam_id, safe_pos, player_color)


func _handle_remove(steam_id: int, pin_index: int, from_peer: int) -> void:
	if not _may_speak_for(from_peer, steam_id):
		push_warning("MapManager: peer %d tried to remove a pin for %d." % [from_peer, steam_id])
		return
	if not SessionManager.has_player(steam_id):
		_refuse_to(from_peer, REFUSAL_NOT_IN_CREW)
		return

	_apply_remove.rpc(steam_id, pin_index)


func _handle_clear(steam_id: int, from_peer: int) -> void:
	if not _may_speak_for(from_peer, steam_id):
		push_warning("MapManager: peer %d tried to clear pins for %d." % [from_peer, steam_id])
		return
	if not SessionManager.has_player(steam_id):
		_refuse_to(from_peer, REFUSAL_NOT_IN_CREW)
		return

	_apply_clear.rpc(steam_id)


func _may_speak_for(from_peer: int, steam_id: int) -> bool:
	if from_peer == 0 or not multiplayer.has_multiplayer_peer():
		return true
	var owner_id := LobbyManager.steam_id_of_peer(from_peer)
	return owner_id == 0 or owner_id == steam_id


@rpc("authority", "call_local", "reliable")
func _apply_place(steam_id: int, pos: Vector2, color: Color) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("MapManager: pin placement from peer %d (not host) — ignored." % sender)
		return

	# Count existing pins for this player
	var player_pin_indices: Array[int] = []
	for i in pins.size():
		if pins[i].get("steam_id", 0) == steam_id:
			player_pin_indices.append(i)

	# If already at max (3), remove the oldest pin (FIFO)
	if player_pin_indices.size() >= MAX_PINS_PER_PLAYER:
		var oldest_idx: int = player_pin_indices[0]
		pins.remove_at(oldest_idx)

	# Add new pin
	var new_pin := {
		"steam_id": steam_id,
		"pos": pos,
		"color": color,
	}
	pins.append(new_pin)

	pin_placed.emit(steam_id, pos, color)
	pins_updated.emit()


@rpc("authority", "call_local", "reliable")
func _apply_remove(steam_id: int, pin_index: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("MapManager: pin removal from peer %d (not host) — ignored." % sender)
		return

	var player_pin_indices: Array[int] = []
	for i in pins.size():
		if pins[i].get("steam_id", 0) == steam_id:
			player_pin_indices.append(i)

	if pin_index >= 0 and pin_index < player_pin_indices.size():
		var actual_idx: int = player_pin_indices[pin_index]
		pins.remove_at(actual_idx)
		pin_removed.emit(steam_id, pin_index)
		pins_updated.emit()


@rpc("authority", "call_local", "reliable")
func _apply_clear(steam_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("MapManager: pin clear from peer %d (not host) — ignored." % sender)
		return

	var kept: Array[Dictionary] = []
	for pin in pins:
		if pin.get("steam_id", 0) != steam_id:
			kept.append(pin)
	pins = kept

	pins_cleared.emit(steam_id)
	pins_updated.emit()


@rpc("authority", "reliable")
func _refuse(reason: String) -> void:
	if multiplayer.get_remote_sender_id() != HOST_PEER:
		return
	request_refused.emit(reason)


func _refuse_to(peer_id: int, reason: String) -> void:
	if peer_id == 0 or peer_id == _our_peer_id() or not multiplayer.has_multiplayer_peer():
		request_refused.emit(reason)
		return
	_refuse.rpc_id(peer_id, reason)

# --- Reactions --------------------------------------------------------------

func _on_player_left(steam_id: int) -> void:
	# When a player leaves, clean up his pins
	var kept: Array[Dictionary] = []
	for pin in pins:
		if pin.get("steam_id", 0) != steam_id:
			kept.append(pin)
	if kept.size() != pins.size():
		pins = kept
		pins_updated.emit()


func _on_contract_signed(_contract_id: String) -> void:
	# A new contract was chosen, clear markers
	clear_all_pins()


func _our_peer_id() -> int:
	if not multiplayer.has_multiplayer_peer():
		return 0
	var peer := multiplayer.multiplayer_peer
	if peer is OfflineMultiplayerPeer:
		return 0
	return multiplayer.get_unique_id()
