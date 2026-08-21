extends Node3D
## Everybody in the map, one capsule per player on the wire — ours included.
##
## Up to here the map drew the *guest list*: `LobbyManager.members_changed` said
## who was in the lobby and a capsule went up for each name, parked on a spot in
## a ring. Now it draws the *wire*, which is a different list and a better one:
## `multiplayer.get_peers()` is who can actually be heard from, and an avatar
## for anybody else would be a body nothing could ever move.
##
## Our own is on the list too, and that is not an accident. Godot replicates a
## node onto the node at the same path on the other machine, so the only way our
## position reaches anybody is for there to be a node here that stands for us —
## the same node they have for us. So every peer gets one, every avatar is named
## `Player<peer id>` on every machine, and the authority of each is set to the
## peer it stands for *before* it enters the tree, which is what makes the whole
## thing line up: everybody owns his own body and writes to it, nobody writes to
## anybody else's.
##
## That is the authority model of the game, in one line: **client-authoritative,
## nobody is the host of anybody's movement**. The host is peer 1 and holds the
## lobby (`lobby_manager.gd`), but his machine has no more say over where you
## are standing than yours has over where he is. Our own capsule is never drawn,
## for the plain reason that we are inside it (see `player_avatar.gd`).
##
## Names do not come from Steam's guest list here — they come from the peer
## himself, over the wire, and `LobbyManager` is what holds them
## (`name_of_peer`). One that lands after the capsule is already up lands on it
## through `peer_identified`, which is the same "correct it in place, do not
## take it down and put it back up" the waiting room already lives on.
##
## Nothing here is up in a solo hunt. With no peer at all there is no wire, no
## capsule and no work: the game runs exactly as it did before any of this.

const AVATAR_SCENE := preload("res://scenes/player_avatar.tscn")

## How far from the map's starting point the standing spots are, one per player
## in a ring around it.
@export var spawn_radius := 2.0

## The character this machine's own player drives. It is what our avatar reads
## and puts on the wire. A path and not a group lookup, because a group is
## tree-wide and a test bench that runs two of these worlds at once would find
## the wrong one.
@export var player_path: NodePath = ^"../Player"

## The capsules that are up, by the peer id of whoever they stand for.
var _avatars: Dictionary[int, PlayerAvatar] = {}


func _ready() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return

	multiplayer.peer_connected.connect(_add)
	multiplayer.peer_disconnected.connect(_remove)
	multiplayer.server_disconnected.connect(_clear)
	LobbyManager.peer_identified.connect(_on_peer_identified)
	LobbyManager.lobby_left.connect(_clear)

	# A client that is still dialling has no id of its own yet, and an avatar
	# named after peer zero would be a node nobody else has. It waits.
	if multiplayer.get_unique_id() == 0:
		multiplayer.connected_to_server.connect(_open)
	else:
		_open()


## The capsule standing for a peer, or null. It is the door anything wanting
## somebody else's body comes knocking on.
func avatar_of(peer_id: int) -> PlayerAvatar:
	return _avatars.get(peer_id)


## Our own, the invisible one the wire reads us off. Null in a solo hunt.
func local_avatar() -> PlayerAvatar:
	return avatar_of(multiplayer.get_unique_id())


## How many are up, ours counted.
func count() -> int:
	return _avatars.size()

# --- Putting them up and taking them down -----------------------------------

## Everybody who is already on the wire when the map opens — which, the lobby
## having closed on the way in, is everybody there will ever be. Ours goes up
## first, so that the first packet out of this machine is not waiting on
## anybody.
func _open() -> void:
	_stand_apart()
	_add(multiplayer.get_unique_id())
	for peer_id in multiplayer.get_peers():
		_add(peer_id)


## Everybody pressed PLAY on the same starting point, so everybody would wake up
## inside everybody else. Each machine steps its own character aside instead: the
## peers sorted, ours found among them, and the spot that falls to it taken —
## the same ring the placeholder capsules used to be parked on, except that this
## moves the character himself, once, and the bodies on the other screens follow
## it over the wire like any other step he takes.
##
## Two machines can pick the same spot when one of them worked its list out
## before the other had finished arriving. That is worth no more than it costs:
## nobody is moving anybody but himself, so the worst of it is two people
## standing together for as long as it takes one of them to walk.
func _stand_apart() -> void:
	var peers := multiplayer.get_peers()
	peers.append(multiplayer.get_unique_id())
	peers.sort()
	var seat := peers.find(multiplayer.get_unique_id())
	var angle := TAU * float(seat) / float(peers.size())
	var player := get_node(player_path)
	player.set_spawn(player.global_position + Vector3(sin(angle), 0.0, cos(angle)) * spawn_radius)


func _add(peer_id: int) -> void:
	if peer_id == 0 or _avatars.has(peer_id):
		return

	var avatar: PlayerAvatar = AVATAR_SCENE.instantiate()
	# The name is the address. Every machine names this same player the same
	# way, which is how a packet written here finds the right body there.
	avatar.name = "Player%d" % peer_id
	avatar.peer_id = peer_id
	# Before `add_child`, so that the synchronizer under it is in the tree with
	# its authority already settled and never sends a frame under the wrong one.
	avatar.set_multiplayer_authority(peer_id)
	avatar.player_name = LobbyManager.name_of_peer(peer_id)
	avatar.steam_id = LobbyManager.steam_id_of_peer(peer_id)
	if peer_id == multiplayer.get_unique_id():
		avatar.follow(get_node(player_path))
	_avatars[peer_id] = avatar
	add_child(avatar)


func _remove(peer_id: int) -> void:
	var avatar := avatar_of(peer_id)
	if avatar == null:
		return
	avatar.queue_free()
	_avatars.erase(peer_id)


## The wire went down under us — the host closed it, or Steam said the lobby has
## fallen apart and `LobbyManager` walked out of it. Either road ends here, and
## nothing should be left standing about: a body whose player cannot be heard
## from any more is a body that will never move again.
func _clear() -> void:
	for peer_id in _avatars.keys():
		_remove(peer_id)


## A name arrived after the capsule did — the usual case for a peer whose
## introduction crossed with the map opening.
func _on_peer_identified(peer_id: int) -> void:
	var avatar := avatar_of(peer_id)
	if avatar == null:
		return
	avatar.player_name = LobbyManager.name_of_peer(peer_id)
	avatar.steam_id = LobbyManager.steam_id_of_peer(peer_id)
