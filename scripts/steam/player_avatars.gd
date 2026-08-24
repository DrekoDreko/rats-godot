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
##
## **Nobody's body goes up before he says he is standing.** The synchronizer
## under an avatar starts sending the moment it is in the tree, and it sends to
## the node at the same path on the far machine. Two machines never load the van
## on the same frame — a client is welcomed into it seconds after the host is
## already in it — so a capsule put up on sight of a peer id writes to a path
## that does not exist yet on the other end. Godot answers a packet addressed to
## a missing node by dropping the peer that sent it, which reads as the host
## kicking a player the instant he arrives. So each machine says `_here` when
## its own van is standing, and a body goes up only for a peer that has said it.

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

## Who has said his van is standing, peer id by peer id. A body is only put up
## for somebody on this list, which is what keeps a packet from being addressed
## to a node the far machine has not built yet.
var _standing: Dictionary[int, bool] = {}

## The `MultiplayerAPI` whose signals we are already on. Held so that `_listen`
## can tell "the wire I am watching" from "a wire that has just been put here",
## and connect once to each rather than once a frame to the same one.
var _listening_to: MultiplayerAPI = null


func _ready() -> void:
	# The crowd keeps working while this machine sits in its pause menu. The
	# pause is local and the wire is not: peers still arrive, still say their
	# van is standing and still drop, and a crowd node that stopped with the
	# tree would answer none of it — a man who joined while somebody was paused
	# would simply have no body on that machine when it came back. The avatars
	# themselves are set the same way in `player_avatar.tscn`, so that our own
	# pose keeps going out and we stand still on their screens rather than
	# falling silent. See `scripts/ui/pause_menu.gd`.
	process_mode = Node.PROCESS_MODE_ALWAYS

	LobbyManager.peer_identified.connect(_on_peer_identified)
	LobbyManager.lobby_left.connect(_clear)
	# The wire is watched rather than asked once. `_listen` is what binds this
	# node to a `MultiplayerAPI`, and the API a node answers to is not
	# necessarily the one it had when it woke up: a van can stand before anybody
	# has dialled, and the peer under it can be replaced wholesale afterwards.
	# Asking once and returning — which is what this did — left such a map a solo
	# hunt for good, with no avatar however many people joined later.
	_listen()


## Watches for the wire arriving, or being swapped, under a van that is already
## standing. It is one comparison a frame and it stops for good once there is a
## peer and our own body is up, which is the ordinary case within a frame or two
## of the map opening.
##
## A poll and not a signal because there is no signal to use: `connected_to_server`
## is the client's alone — a host never fires it — and both of them are emitted
## by whichever `MultiplayerAPI` this node answered to at the time, which is the
## very thing that may be replaced.
func _process(_delta: float) -> void:
	_listen()
	if _on_the_wire() and _avatars.has(multiplayer.get_unique_id()):
		set_process(false)


## Binds to whatever multiplayer this node currently answers to, and opens the
## map as soon as that wire can say who we are. Safe to call every frame: the
## connections are made once per API and `_open` returns on its own once our own
## body is up.
func _listen() -> void:
	if not _on_the_wire():
		return
	var api := multiplayer
	if api != _listening_to:
		_listening_to = api
		# Not `_add` on `peer_connected`: a peer coming up on the wire has not
		# said his van is standing, and a body put up on the strength of the
		# connection alone is the packet to a missing node this whole dance is
		# here to avoid. He is added when he says `_here`.
		#
		# Checked rather than connected blind: the same API can come back round
		# after a `_clear`, and connecting a second time would answer every peer
		# twice.
		if not api.peer_connected.is_connected(_greet):
			api.peer_connected.connect(_greet)
			api.peer_disconnected.connect(_remove)
			api.server_disconnected.connect(_clear)
	# A client still dialling has no id of its own yet, and an avatar named after
	# peer zero would be a node nobody else has. It waits — for the next frame,
	# which is the whole reason this is a poll.
	if api.get_unique_id() != 0:
		_open()


## Whether there is a wire under us at all. A solo hunt has none — no peer, or
## the offline stand-in Godot leaves in its place — and everything below this
## node does is answered by that one question.
func _on_the_wire() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not peer is OfflineMultiplayerPeer


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

## Our own van is standing. Ours goes up first — it is the one node the wire
## reads this machine off, and nobody else's packet can be addressed to it until
## they know it is there — and then we say so to everybody, which is what lets
## them put ours up and us theirs.
##
## The peers already on the wire are not added here. They are added when they
## answer `_here`, or immediately if they have already said it, which is the
## ordinary case for a client walking into a van the host has been standing in
## for some time.
func _open() -> void:
	# `connected_to_server` and the `_ready` road can both reach this — a client
	# that was already on the wire when its van came up is opened by `_ready`,
	# and the signal still fires afterwards on a reconnect. Ours being up is the
	# whole of the question: it goes up here and nowhere else.
	var us := multiplayer.get_unique_id()
	if us == 0 or _avatars.has(us):
		return
	_stand_apart()
	_standing[us] = true
	_add(us)
	# Everybody already on the wire is told, one at a time rather than in one
	# broadcast: at the moment the first van comes up the peer may be open but
	# not yet connected to anybody, and a broadcast then is a packet with
	# nowhere to go. Whoever arrives after this is told by `_greet`.
	for peer_id in multiplayer.get_peers():
		_here.rpc_id(peer_id)
	# Somebody may have said it before our van was standing, in which case the
	# body was held back until there was something to hang it on.
	for peer_id in _standing.keys():
		_add(peer_id)


## A peer came up on the wire while our own van was already standing. This is the
## case `_open` cannot cover: it announces to whoever was there when it ran, and
## anybody arriving afterwards would otherwise hear nothing.
##
## It is sent even though his van may still be loading, and that is deliberate.
## The worst it can cost is a line in his log — this is the crowd node's own
## RPC, and a packet for a node that is not up yet is dropped and complained
## about, nothing more. What must never go early is a *synchronizer* frame, and
## that is what `_standing` holds back: his body does not go up here, it goes up
## when he answers. Trading one log line for a body that is certain to appear is
## the right way round.
func _greet(peer_id: int) -> void:
	if not _avatars.has(multiplayer.get_unique_id()):
		return
	_here.rpc_id(peer_id)


## Somebody's van is standing, and his body may go up. It carries nothing: the
## peer id is the whole message and `get_remote_sender_id` already has it.
##
## `any_peer` because it is not a decision and there is nothing to trust in it —
## a peer saying where his own scene is up is the only machine that could know.
## It is not `call_local`; `_open` writes our own entry itself, in the one order
## that is safe.
@rpc("any_peer", "reliable")
func _here() -> void:
	var peer_id := multiplayer.get_remote_sender_id()
	if peer_id == 0:
		return
	# A man who has already said it is a man we have already answered. Without
	# this the two machines answer each other's answer for as long as they are
	# both up.
	var first_time := not _standing.has(peer_id)
	_standing[peer_id] = true
	# Only once our own van is up. Before that there is nothing to hang a body
	# on, and `_open` will add him off `_standing` when it gets there.
	if _avatars.has(multiplayer.get_unique_id()):
		_add(peer_id)
	# He may have missed our own announcement — a client welcomed into a van the
	# host has been standing in for a minute was not on the wire when the host
	# said it. So the first time we hear from somebody we say it back, once, and
	# only if we have something to tell him about.
	if first_time and _avatars.has(multiplayer.get_unique_id()):
		_here.rpc_id(peer_id)


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
	# `_or_null`, and the reason is the whole crowd rather than this one step.
	# This runs first in `_open`, so a `get_node` that threw here would take the
	# avatars down with it — no body for us, none for anybody, and the wire
	# reading this machine off nothing at all. A scene whose player sits
	# somewhere else, or has none, is a scene where nobody needs standing aside;
	# it is not a reason for the map to have no people in it.
	var player := get_node_or_null(player_path)
	if player == null:
		push_warning("PlayerAvatars: no player at '%s' — nobody stood aside." % player_path)
		return
	player.set_spawn(player.global_position + Vector3(sin(angle), 0.0, cos(angle)) * spawn_radius)


func _add(peer_id: int) -> void:
	if peer_id == 0 or _avatars.has(peer_id):
		return
	# Ours is put up by `_open` before anybody has said anything; everybody
	# else's waits for him to say his van is standing.
	if not _standing.has(peer_id):
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
		# `_or_null` for the same reason as `_stand_apart`, and with more riding
		# on it: this is our *own* body, the one node the wire reads this machine
		# off. A `get_node` that threw here would leave it un-parented, so no
		# `sync_*` would ever be written and no packet would ever leave — which
		# is precisely "the others cannot see me walking", and it would be a
		# silent failure on every screen but this one.
		var player := get_node_or_null(player_path)
		if player != null:
			avatar.follow(player)
		else:
			push_warning("PlayerAvatars: no player at '%s' — our own body will not move."
				% player_path)
	_avatars[peer_id] = avatar
	add_child(avatar)


func _remove(peer_id: int) -> void:
	_standing.erase(peer_id)
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
	_standing.clear()
	# Our own body went with the rest, so the watch goes back on: a wire that
	# comes back — a host reopening, a bench dialling again — finds a map ready
	# to put everybody up rather than one that stopped looking.
	_listening_to = null
	set_process(true)


## A name arrived after the capsule did — the usual case for a peer whose
## introduction crossed with the map opening.
func _on_peer_identified(peer_id: int) -> void:
	var avatar := avatar_of(peer_id)
	if avatar == null:
		return
	avatar.player_name = LobbyManager.name_of_peer(peer_id)
	avatar.steam_id = LobbyManager.steam_id_of_peer(peer_id)
