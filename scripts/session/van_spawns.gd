class_name VanSpawns
extends Node3D
## Where each player stands when the van scene opens, and what he is allowed to
## be carrying while he is in it.
##
## Two jobs, and they are one node because they are the same moment: the frame
## the scene comes up, before anybody has had a chance to walk or to press a
## number key.
##
## **The spot.** Four `Marker3D` children, and a player takes the one that falls
## to him by the order the crew went in. Not at random and not by proximity:
## everybody has to work out the *same* seat for the same player, or two people
## spawn inside each other, and the only list every machine already agrees on is
## `SessionManager.players` — which is filled in the order the crew joined and
## is a dictionary, so it keeps that order.
##
## That is a different answer from the one the hunt uses
## (`scripts/steam/player_avatars.gd`, which rings the peers around the map's
## own starting point) and it is the better one here: the van is a room with
## furniture in it, so the spots have to be places somebody put, not points on a
## circle that might land inside a bench.
##
## A player nobody has been introduced to yet — the crew list has not arrived,
## Steam is not running, the bench has registered nobody — still has to stand
## somewhere. He takes the first marker. One man in an empty van standing on
## spot one is right; the same man standing at the origin, halfway through the
## floor, is not.
##
## **The kit.** The lobby is a van with the back open and nothing to kill: the
## card asks for empty hands and interaction, and nothing else. So the belt is
## barred here (`Inventory.bar_slots`) rather than the weapons being taken off
## the player scene — the same player scene is what walks into the house two
## phases later with everything he bought on it, and a van that deleted his
## slots would be a van that took his shopping away.
##
## The lock is set from the *phase* and not from the fact that this scene is
## open, and it is re-read on every phase change for as long as the van stands
## — so the road gets the belt back (card 09), and a van opened outside the
## lobby at all never takes it in the first place. See `_apply_belt_lock`.

## The markers this node hands out, found among its own children on the way up.
## Four of them in the van, which is what the lobby holds.
var _spots: Array[Marker3D] = []


func _ready() -> void:
	for child in get_children():
		var marker := child as Marker3D
		if marker != null:
			_spots.append(marker)

	# A frame of patience: the player is a sibling in the same scene and may not
	# have run his own `_ready` yet, and the crew list can still be arriving off
	# the wire. Standing him somewhere wrong and moving him a frame later is
	# visible; waiting a frame is not.
	await get_tree().process_frame
	# The frame that was waited for is a frame in which the scene can have
	# changed under this node — a phase arriving off the wire as the van comes
	# up. Resuming into a freed node would reach for a tree that is no longer
	# there; there is nobody left to place.
	if not is_inside_tree():
		return
	_place_player()
	_apply_belt_lock()

	PhaseManager.phase_changed.connect(_on_phase_changed)


## `PhaseManager` is an autoload: it outlives every scene, so a connection made
## in `_ready` is still live after this van has been freed. Dropping it here
## keeps a van that is already gone from answering for the one that replaced it.
func _exit_tree() -> void:
	if PhaseManager.phase_changed.is_connected(_on_phase_changed):
		PhaseManager.phase_changed.disconnect(_on_phase_changed)


## How many spots there are.
func count() -> int:
	return _spots.size()


## The spot a Steam ID gets, in world space. Falls back to the first marker for
## anybody the crew has never heard of, and to this node's own position when the
## van was built without any markers at all — a spawn point that answers
## nothing would drop the player through the floor.
func spot_of(steam_id: int) -> Vector3:
	if _spots.is_empty():
		return global_position
	return _spots[_seat_of(steam_id)].global_position


## Which marker falls to a Steam ID: his place in the crew, wrapped round if
## there are somehow more players than markers.
func _seat_of(steam_id: int) -> int:
	var crew := SessionManager.players.keys()
	var seat := crew.find(steam_id)
	if seat == -1:
		return 0
	return seat % _spots.size()


## Puts this machine's own player on his spot. Nobody else's: every other body
## in the van is an avatar driven off the wire by the player it belongs to, and
## moving one from here would be this machine deciding where somebody else is
## standing.
func _place_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	# `set_spawn` and not the position directly, so that a player who falls out
	# of the world comes back to his own spot in the van rather than to wherever
	# the player scene happened to be saved.
	player.set_spawn(spot_of(_our_steam_id()))


## Puts the belt where the phase says it should be: barred in the parked van,
## free anywhere else.
##
## It reads the phase rather than assuming it, and that is not caution for its
## own sake. This scene is the lobby's, but a scene is a file and a file can be
## loaded in any phase — by a bench, by a later card reusing the van's interior
## for the road (card 09 says to), or by somebody testing. A van that barred the
## belt on the way up whatever the phase, and only unbarred it on a *change*,
## would take a player's weapons away for good the moment it was opened outside
## the lobby: the change it is waiting for has already been and gone.
func _apply_belt_lock() -> void:
	var belt := _belt()
	if belt == null:
		return
	if PhaseManager.current() != Phase.Type.LOBBY:
		belt.bar_slots([] as Array[int])
		return
	var all: Array[int] = []
	for index in belt.slot_count():
		all.append(index)
	belt.bar_slots(all)


## The lock follows the phase for as long as this van is standing. It is done
## here and not on the road's own scene because this is the node that put it on,
## and a lock whose key lives in a different scene is a lock that stays on the
## day somebody reorders the phases.
func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_apply_belt_lock()


## This machine's own belt, or null when there is no player in the scene — which
## is every test bench that loads the van on its own to look at it. Read off the
## player's own `inventory` rather than found by name, so that moving the node
## inside `player.tscn` does not quietly stop the lobby locking the belt.
func _belt() -> Inventory:
	# A van on its way out of the tree still gets the phase change that is taking
	# it away — `PhaseManager` is an autoload and outlives the scene, and it
	# announces one frame *after* `change_scene_to_file` has already freed this
	# node. With no tree there is no group to search and no belt to lock, and the
	# player walking into the next scene brings his own.
	if not is_inside_tree():
		return null
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	return player.inventory


## Who this machine is, as the crew counts people. Zero with Steam shut, which
## `_seat_of` reads as "not in the crew" and answers with the first spot — the
## right answer for a solo run, where the first spot is the only one that
## matters.
func _our_steam_id() -> int:
	return SteamManager.get_steam_id()
