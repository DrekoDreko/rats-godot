class_name HouseSpawns
extends Node3D
## Spawning and phase-based inventory rules for the house (Card 12 & Card 13).
##
## **The spot.** Four `Marker3D` children positioned by the front door entrance,
## assigned in deterministic order according to `SessionManager.players` (the same
## way `VanSpawns` seats players in the van).
##
## **The kit (Survey vs Hunt).**
## - During **SURVEY** (60s): Attack weapons (weapons that kill) are barred in the
##   player's belt. Only non-attack utilities (traps, baits, patches, flashlight,
##   hands) can be equipped. Attempting to equip barred slots gives refusal
##   feedback. The blueprint is not among them: it stays on the van's map table.
## - During **HUNT**: All weapons are unbarred, letting players equip attack weapons
##   to fight the loose rats.
## - In any other phase the belt is left exactly as it was found: locking it up in
##   the van is `VanSpawns`' job, and this node shares its scene with a world that
##   is also opened outside a shift.

var _spots: Array[Marker3D] = []


func _ready() -> void:
	for child in get_children():
		var marker := child as Marker3D
		if marker != null:
			_spots.append(marker)

	# A frame of delay so siblings have completed initialization. The tree is
	# held across the wait rather than asked for again after it: a phase can
	# arrive off the wire on that very frame and free this scene, and a node
	# resuming out of the tree has no `get_tree()` to reach through.
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame

	# Freed while we waited: there is nobody left to place.
	if not is_inside_tree():
		return
	_place_player()
	_apply_belt_lock()

	PhaseManager.phase_changed.connect(_on_phase_changed)


## How many front door spawn spots are defined.
func count() -> int:
	return _spots.size()


## The front door spawn spot for a given Steam ID.
func spot_of(steam_id: int) -> Vector3:
	if _spots.is_empty():
		return global_position
	return _spots[_seat_of(steam_id)].global_position


func _seat_of(steam_id: int) -> int:
	var crew := SessionManager.players.keys()
	var seat := crew.find(steam_id)
	if seat == -1:
		return 0
	return seat % _spots.size()


func _place_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D
	if player == null:
		return
	player.set_spawn(spot_of(_our_steam_id()))


## Applies the inventory weapon lock according to current phase rules.
func _apply_belt_lock() -> void:
	var belt := _belt()
	if belt == null:
		return

	match PhaseManager.current():
		Phase.Type.SURVEY:
			belt.bar_attack_weapons()
		Phase.Type.HUNT:
			belt.bar_slots([] as Array[int])
		_:
			# LOBBY, TRAVEL and RESULT are the van's business: `VanSpawns` bars
			# the whole belt there. The house never locks a belt it was not
			# asked to lock, so a scene standing outside a shift keeps its own.
			pass


func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	# The phase is announced after the scene change has landed, so a house on its
	# way out still hears the phase that replaced it — already out of the tree,
	# with no tree left to look a player up in.
	if not is_inside_tree():
		return
	_apply_belt_lock()


func _belt() -> Inventory:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not ("inventory" in player):
		return null
	return player.inventory as Inventory


func _our_steam_id() -> int:
	return LobbyManager.our_steam_id()
