extends Node
## The waiting room: where the players find each other before the hunt, and the
## one place that knows who is in the van with you.
##
## Two things are going on here at once, and it helps to keep them apart. The
## Steam lobby is the *guest list* — Valve holds it, it survives the world
## loading, and it is what `list_players()` reads. The `SteamMultiplayerPeer` is
## the *wire* — Godot's own `SceneMultiplayer` running over Steam's P2P, and it
## is what the players in the map are drawn off (`player_avatars.gd`). This node
## opens both at the same moment and closes both at the same moment, so nobody
## else in the game ever has to wonder which of the two is up.
##
## Who hosts is not decided here: it is whoever Steam says owns the lobby. The
## owner calls `host_with_lobby()` and becomes peer 1, everyone else calls
## `connect_to_lobby()` and dials out to them. Being peer 1 is not being in
## charge of anybody: movement is client-authoritative, every player owns his
## own body and nobody else's, and what the host has is the lobby and the say
## over when the hunt starts. That is also why there is no host migration —
## Steam hands a lobby to whoever is left when the owner walks out, but the
## connection does not follow, so the honest answer is to drop everybody back to
## the lobby screen (see `_on_lobby_chat_update`).
##
## Steam answers nothing on the spot. `create_lobby` and `join_lobby` returning
## true only means the request went out; the real answer lands later on
## `lobby_entered` or `lobby_failed`. Whoever is on screen listens; nobody polls.
##
## With no Steam (`SteamManager.is_online` false) every call here fails politely
## with a `lobby_failed` message. The game still runs — solo, which is what
## `start_game()` does when there is no lobby.

## The lobby is up, the wire is up, and `is_host` is settled. Comes for the host
## and for the client alike.
signal lobby_entered(lobby_id: int, is_host: bool)
## We are out, whether by our own hand or because the lobby fell apart.
signal lobby_left()
## Somebody came in or went out. Carries the whole list, already built, because
## every listener wants all of it and none of them should ask Steam twice.
signal members_changed(players: Array[Dictionary])
## The answer to `refresh_lobbies()`: what is open right now.
signal lobby_list_updated(lobbies: Array[Dictionary])
## Something did not work, said in a sentence a player can read. The one signal
## the UI puts straight on screen.
signal lobby_failed(reason: String)
## A peer on the wire said who he is. It comes once per peer, whenever his
## introduction lands, which may well be after the map is already drawing him —
## so whoever shows a name listens to this and corrects it in place (see
## `scripts/steam/player_avatars.gd`).
signal peer_identified(peer_id: int)

## The lobby data that tells our lobbies apart from everybody else's. It matters
## more than it looks: until RATS has an app ID of its own the game borrows
## Spacewar's (480), and a plain public lobby search on 480 comes back full of
## strangers testing their own games. `refresh_lobbies()` filters on this key,
## so the browser only ever shows lobbies this game opened.
const GAME_KEY := "game"
const GAME_VALUE := "rats"
## The host's Steam name, written into the lobby so the browser has something to
## show besides a nineteen-digit number.
const HOST_KEY := "host_name"

## How many fit in the van. `create_lobby` clamps to it.
const MAX_PLAYERS := 4
## How many lobbies the browser asks Steam for at a time.
const MAX_RESULTS := 20
## Where the hunt happens, once the host says go.
const GAME_SCENE := "res://scenes/world.tscn"
## What a peer is called before he has got round to saying. The same three dots
## an unsent Steam persona shows as, and for the same reason: it is a name that
## is on its way, not a name that is missing.
const UNKNOWN_NAME := "..."

## The lobby everyone in it can be reached through, or zero when there is none.
var lobby_id := 0
## Whether we are peer 1 — the one who holds the lobby open and says when the
## hunt starts, not the one who owns anybody's movement. Decided once, on the
## way in, and never changed under anybody.
var is_host := false
## Steam's owner of the lobby. The same as us while `is_host`, and only ever
## read to mark whose name gets the star on the list.
var owner_id := 0

## Public and not friends-only, so that two accounts which have never met can
## still find each other through the browser — which is exactly how this gets
## tested. Set it to `Steam.LOBBY_TYPE_FRIENDS_ONLY` to close it to the friends
## list, and nothing else in this file has to change.
var lobby_type := Steam.LOBBY_TYPE_PUBLIC

var _peer: SteamMultiplayerPeer = null
## A `createLobby`/`joinLobby` is out and has not been answered yet. Keeps a
## player hammering the button from opening four lobbies.
var _pending := false
## Who each peer on the wire is: `steam_id` and `name`, by peer id. Filled in by
## the peers themselves (see `_introduce`) and emptied when the wire goes down.
var _identities: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	# Same reason as `SteamManager`: an answer that lands while the game is
	# paused still has to be read.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# The wire is Godot's own and is listened to whether or not Steam is there:
	# a test bench with the client closed still brings a peer up over ENet, and
	# it should be heard the same way a lobby is.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	if not SteamManager.is_online:
		return

	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_chat_update.connect(_on_lobby_chat_update)
	Steam.lobby_data_update.connect(_on_lobby_data_update)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.lobby_kicked.connect(_on_lobby_kicked)
	Steam.join_requested.connect(_on_join_requested)
	Steam.persona_state_change.connect(_on_persona_state_change)

	_join_from_command_line()


## Closing the window walks out of the lobby first, so the people still in it
## see the name go rather than wait for Steam to notice. Killing the process
## gets there too — Steam drops a member whose game is gone — just later, and
## the wait is what everybody else would be looking at.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		leave_lobby()

# --- What the screen asks for ----------------------------------------------

## Opens a lobby and puts us in it as host. `max_players` is clamped to
## `MAX_PLAYERS`: the van does not grow. Returns whether the request went out —
## the lobby itself arrives later, on `lobby_entered`.
func create_lobby(max_players: int = MAX_PLAYERS) -> bool:
	if not _needs_steam("open a lobby"):
		return false
	if lobby_id != 0:
		lobby_failed.emit("You are already in a lobby.")
		return false
	if _pending:
		return false
	_pending = true
	Steam.createLobby(lobby_type, clampi(max_players, 2, MAX_PLAYERS))
	return true


## Walks into somebody else's lobby. The answer — including "it is full" and "it
## does not exist" — comes back on `lobby_joined` and ends up as a sentence on
## `lobby_failed`.
func join_lobby(id: int) -> bool:
	if not _needs_steam("join a lobby"):
		return false
	# `isLobby` reads the account-type bits of the SteamID, which is enough to
	# catch a mistyped or half-pasted number before it costs a round trip.
	if id == 0 or not Steam.isLobby(id):
		lobby_failed.emit("That is not a lobby ID.")
		return false
	if id == lobby_id:
		return true
	if _pending:
		return false
	if lobby_id != 0:
		leave_lobby()
	_pending = true
	Steam.joinLobby(id)
	return true


## Out of the lobby and off the wire, in that order. Safe to call when there is
## no lobby, which is why every failure path is allowed to end on it.
func leave_lobby() -> void:
	if lobby_id == 0:
		return
	Steam.leaveLobby(lobby_id)
	_close_peer()
	lobby_id = 0
	owner_id = 0
	is_host = false
	_pending = false
	lobby_left.emit()
	members_changed.emit(list_players())


## Who is in the lobby: `steam_id`, `name` and `is_host` for each, in Steam's own
## order, which puts the owner first. Empty outside a lobby.
##
## Read off Steam every time instead of being kept in a list here. The guest
## list is Valve's, not ours, and a copy of it is a copy that can go stale.
func list_players() -> Array[Dictionary]:
	var players: Array[Dictionary] = []
	if lobby_id == 0:
		return players
	for index in Steam.getNumLobbyMembers(lobby_id):
		var member_id := Steam.getLobbyMemberByIndex(lobby_id, index)
		players.append({
			"steam_id": member_id,
			"name": _persona_name(member_id),
			"is_host": member_id == owner_id,
		})
	return players


# --- Who is who on the wire -------------------------------------------------
# The lobby is a list of Steam accounts and the wire is a list of peer ids, and
# nothing in either of them says which is which. The peers themselves do: every
# one of them introduces itself to every other the moment they are connected,
# and what comes back is filed here. It is not asked of Steam and not asked of
# the transport, so nothing above this line has to care what the wire is made
# of — and a name from the horse's mouth is one name that can never come back
# as "[unknown]".

## What a peer is called. Our own name for our own id, whatever the peer said
## for anybody else's, and `UNKNOWN_NAME` for a peer who has not spoken yet.
func name_of_peer(peer_id: int) -> String:
	if peer_id == _our_peer_id():
		return SteamManager.get_persona_name()
	var known: Dictionary = _identities.get(peer_id, {})
	return String(known.get("name", UNKNOWN_NAME))


## The Steam account behind a peer, or zero when it has not said yet. It is what
## ties a body in the map back to a row on the guest list.
func steam_id_of_peer(peer_id: int) -> int:
	if peer_id == _our_peer_id():
		return SteamManager.get_steam_id()
	var known: Dictionary = _identities.get(peer_id, {})
	return int(known.get("steam_id", 0))


## Files who a peer is and says so. Called by the RPC below with what the peer
## sent, and kept out of it so that there is one plain function to test and one
## line of wire on top of it.
func remember_identity(peer_id: int, steam_id: int, persona: String) -> void:
	if peer_id == 0:
		return
	_identities[peer_id] = {"steam_id": steam_id, "name": persona}
	peer_identified.emit(peer_id)


## Our half of the handshake, run on the peer at the other end. It goes out on
## `peer_connected`, which both sides get, so the introduction is mutual without
## anybody having to ask.
##
## It lives on this autoload and not on anything in the map on purpose: this
## node is up from boot on every machine, so there is no window in which the
## message arrives at a path that does not exist yet.
@rpc("any_peer", "reliable")
func _introduce(steam_id: int, persona: String) -> void:
	remember_identity(multiplayer.get_remote_sender_id(), steam_id, persona)


func _on_peer_connected(peer_id: int) -> void:
	_introduce.rpc_id(peer_id, SteamManager.get_steam_id(), SteamManager.get_persona_name())


func _on_peer_disconnected(peer_id: int) -> void:
	_identities.erase(peer_id)


## Our own id on the wire, or zero when there is no wire to have one on — which
## is any moment outside a lobby, and asking Godot for an id then is an error in
## the log for an answer nobody needed.
func _our_peer_id() -> int:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return 0
	return multiplayer.get_unique_id()


## Asks Steam which RATS lobbies are open. The answer lands on
## `lobby_list_updated`.
func refresh_lobbies() -> bool:
	if not _needs_steam("browse lobbies"):
		return false
	Steam.addRequestLobbyListStringFilter(GAME_KEY, GAME_VALUE, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListDistanceFilter(Steam.LOBBY_DISTANCE_FILTER_WORLDWIDE)
	Steam.addRequestLobbyListResultCountFilter(MAX_RESULTS)
	Steam.requestLobbyList()
	return true


## Steam's own invite window, over the game. A friend who accepts arrives on
## `join_requested` when their game is open, and on the launch command line when
## it is not — both roads lead back to `join_lobby`.
func invite_friends() -> bool:
	if not _needs_steam("invite anybody"):
		return false
	if lobby_id == 0:
		lobby_failed.emit("Open a lobby first.")
		return false
	Steam.activateGameOverlayInviteDialog(lobby_id)
	return true


## Into the map. The host says when, and everybody goes at once; with no lobby
## at all this is simply the game starting on its own.
func start_game() -> void:
	if lobby_id == 0:
		_enter_game()
		return
	if not is_host:
		return
	# Nobody walks in halfway through a hunt. The lobby stays alive — it is
	# still the guest list — it just stops taking newcomers.
	Steam.setLobbyJoinable(lobby_id, false)
	_enter_game.rpc()

# --- The lobby coming up and going down ------------------------------------

## Both roads in, kept in one place and made safe to walk twice: the host is
## told about the very same lobby by `lobby_created` and again by `lobby_joined`.
func _enter_lobby(entered_id: int) -> void:
	if lobby_id == entered_id and _peer != null:
		return
	lobby_id = entered_id
	owner_id = Steam.getLobbyOwner(entered_id)
	is_host = owner_id == SteamManager.get_steam_id()
	if not _open_peer():
		leave_lobby()
		return
	print("Lobby %d — %s, %d/%d players" % [
		lobby_id, "hosting" if is_host else "joined",
		Steam.getNumLobbyMembers(lobby_id), Steam.getLobbyMemberLimit(lobby_id),
	])
	lobby_entered.emit(lobby_id, is_host)
	members_changed.emit(list_players())


## Godot's multiplayer, over Steam's P2P. The peer works the other end out from
## the lobby itself: the owner listens, everyone else dials the owner — which is
## why this can only run once `owner_id` and `is_host` are settled.
func _open_peer() -> bool:
	_close_peer()
	var peer := SteamMultiplayerPeer.new()
	var error := peer.host_with_lobby(lobby_id) if is_host else peer.connect_to_lobby(lobby_id)
	if error != OK:
		lobby_failed.emit("Could not open the connection to the lobby (error %d)." % error)
		return false
	_peer = peer
	multiplayer.multiplayer_peer = peer
	return true


func _close_peer() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	# The peer ids go with the wire: the next one hands out its own, and a name
	# filed against an id from the last lobby would be a name on a stranger.
	_identities.clear()


## The end of a lobby that did not end by choice: say why, then get out. The
## `lobby_id` is cleared by `leave_lobby`, and every handler that might fire a
## breath later checks it — so the player reads one sentence, not three.
func _fail_and_leave(reason: String) -> void:
	if lobby_id == 0:
		return
	lobby_failed.emit(reason)
	leave_lobby()


## Runs on every peer at once, host included (`call_local`), because the host
## walking into the map alone is exactly the bug this prevents.
@rpc("authority", "call_local", "reliable")
func _enter_game() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)

# --- What Steam says back ---------------------------------------------------

func _on_lobby_created(result: int, new_lobby_id: int) -> void:
	_pending = false
	if result != Steam.RESULT_OK:
		lobby_failed.emit("Could not open the lobby (%s)." % _result_name(result))
		return
	# Stamped before anybody can find it, so the browser's filter has something
	# to match on and the row has a name on it.
	Steam.setLobbyData(new_lobby_id, GAME_KEY, GAME_VALUE)
	Steam.setLobbyData(new_lobby_id, HOST_KEY, SteamManager.get_persona_name())
	Steam.setLobbyJoinable(new_lobby_id, true)
	_enter_lobby(new_lobby_id)


func _on_lobby_joined(joined_id: int, _permissions: int, _locked: bool, response: int) -> void:
	_pending = false
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_failed.emit(_entry_refusal(response))
		return
	_enter_lobby(joined_id)


## Somebody came in or went out. Steam does not say who is left — it says what
## changed — so the list is read again from scratch.
func _on_lobby_chat_update(updated_id: int, changed_id: int, _by_id: int, state: int) -> void:
	if lobby_id == 0 or updated_id != lobby_id:
		return
	# A name never seen on this machine comes back "[unknown]" until Steam sends
	# it. Asking on the way in means it is usually there by the time the row is
	# drawn, and `persona_state_change` fixes it when it is not. `state` is a
	# bitfield — one callback can carry more than one thing that happened.
	if state & Steam.CHAT_MEMBER_STATE_CHANGE_ENTERED:
		Steam.requestUserInformation(changed_id, true)

	var new_owner := Steam.getLobbyOwner(lobby_id)
	if new_owner != owner_id and not is_host:
		# Steam has handed the lobby to somebody else, which only happens when
		# the owner walked out — and the owner is the server we were talking to.
		# There is no migration to fall back on, so everybody goes home.
		_fail_and_leave("The host left the lobby.")
		return
	owner_id = new_owner
	members_changed.emit(list_players())


func _on_lobby_data_update(_success: int, updated_id: int, _member_id: int) -> void:
	if lobby_id != 0 and updated_id == lobby_id:
		members_changed.emit(list_players())


func _on_lobby_match_list(lobbies: Array) -> void:
	var found: Array[Dictionary] = []
	for entry in lobbies:
		var found_id := int(entry)
		var host_name := Steam.getLobbyData(found_id, HOST_KEY)
		found.append({
			"lobby_id": found_id,
			"host_name": host_name if not host_name.is_empty() else "unnamed",
			"players": Steam.getNumLobbyMembers(found_id),
			"max_players": Steam.getLobbyMemberLimit(found_id),
		})
	lobby_list_updated.emit(found)


func _on_lobby_kicked(kicked_from: int, _admin_id: int, _disconnected: int) -> void:
	if kicked_from == lobby_id:
		_fail_and_leave("You were removed from the lobby.")


## A friend's invite, accepted with the game already running.
func _on_join_requested(requested_id: int, _friend_id: int) -> void:
	join_lobby(requested_id)


## A name has finally arrived from Steam. Only worth a redraw when it belongs to
## somebody standing here — this fires for the whole friends list otherwise.
func _on_persona_state_change(changed_id: int, _flags: int) -> void:
	if lobby_id == 0:
		return
	for player in list_players():
		if player["steam_id"] == changed_id:
			members_changed.emit(list_players())
			return


## The host never answered the wire, though Steam let us into the lobby. Usually
## a host who quit between the two.
func _on_connection_failed() -> void:
	_fail_and_leave("Could not reach the host.")


func _on_server_disconnected() -> void:
	_fail_and_leave("The host closed the lobby.")

# --- Odds and ends ----------------------------------------------------------

## Steam starts the game with `+connect_lobby <id>` when an invite is accepted
## with the game closed. One frame of patience, so that the lobby screen is
## already listening when the answer — or the complaint — comes back.
func _join_from_command_line() -> void:
	var id := _lobby_from_arguments(Steam.getLaunchCommandLine().split(" ", false))
	if id == 0:
		id = _lobby_from_arguments(OS.get_cmdline_args())
	if id == 0:
		return
	await get_tree().process_frame
	join_lobby(id)


func _lobby_from_arguments(arguments: PackedStringArray) -> int:
	var at := arguments.find("+connect_lobby")
	if at == -1 or at + 1 >= arguments.size():
		return 0
	return arguments[at + 1].to_int()


## Our own name comes from `SteamManager`, so that the offline stand-in is the
## same one the rest of the game shows. Anybody else's comes from Steam, and is
## chased up when it has not arrived yet.
func _persona_name(member_id: int) -> String:
	if member_id == SteamManager.get_steam_id():
		return SteamManager.get_persona_name()
	var persona := Steam.getFriendPersonaName(member_id)
	if persona.is_empty() or persona == "[unknown]":
		Steam.requestUserInformation(member_id, true)
		return "..."
	return persona


func _needs_steam(action: String) -> bool:
	if SteamManager.is_online:
		return true
	lobby_failed.emit("Steam is not running — cannot %s." % action)
	return false


## Steam's refusal at the door, in words. The first three are the ones a player
## actually runs into; the rest are here so that the message never comes out as
## a bare number.
func _entry_refusal(response: int) -> String:
	match response:
		Steam.CHAT_ROOM_ENTER_RESPONSE_FULL:
			return "That lobby is full."
		Steam.CHAT_ROOM_ENTER_RESPONSE_DOESNT_EXIST:
			return "That lobby no longer exists."
		Steam.CHAT_ROOM_ENTER_RESPONSE_NOT_ALLOWED:
			return "That lobby is not open to you."
		Steam.CHAT_ROOM_ENTER_RESPONSE_BANNED:
			return "You are banned from that lobby."
		Steam.CHAT_ROOM_ENTER_RESPONSE_LIMITED:
			return "A limited Steam account cannot join lobbies."
		Steam.CHAT_ROOM_ENTER_RESPONSE_RATE_LIMIT_EXCEEDED:
			return "Too many tries in a row — wait a moment."
		_:
			return "Could not enter the lobby (code %d)." % response


func _result_name(result: int) -> String:
	match result:
		Steam.RESULT_NO_CONNECTION:
			return "no connection to Steam"
		Steam.RESULT_TIMEOUT:
			return "Steam took too long"
		Steam.RESULT_LIMIT_EXCEEDED:
			return "too many lobbies open"
		Steam.RESULT_ACCESS_DENIED:
			return "access denied"
		_:
			return "error %d" % result
