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
##
## **There is a second road in, for developing on one machine.** Steam serves one
## account per computer, so two windows opened side by side are the same person
## as far as Valve is concerned and cannot be two players in one lobby. Testing
## the wire that way needs two machines and two accounts, which is a slow loop to
## be held to for a change to how a body walks. So `--host` and `--join` on the
## command line open the very same `SceneMultiplayer` over plain ENet on the
## loopback instead, with no Steam involved at all (`host_local`, `join_local`).
##
## Nothing downstream knows the difference. `player_avatars.gd` reads
## `multiplayer.get_peers()`, the synchronisers replicate the same properties,
## and the phase, colour and ready managers all identify people through
## `steam_id_of_peer()` — which answers over ENet too, off the numbers the peers
## introduce themselves with. What is genuinely missing is what only Valve can
## provide: real personas, invites, and the lobby browser. Those are for the
## acceptance run on two machines; everything else can be seen here.

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
## Who the man playing on his own is, when Steam is not running to say. A real
## SteamID64 is a 17-digit number starting at 76561..., so a one can never
## collide with one — which is what lets everything downstream treat it as an
## ordinary account without a special case.
const SOLO_STEAM_ID := 1
## What a peer is called before he has got round to saying. The same three dots
## an unsent Steam persona shows as, and for the same reason: it is a name that
## is on its way, not a name that is missing.
const UNKNOWN_NAME := "..."

## Where the local wire listens. Only ever bound on the loopback, and only when
## the game was started with `--host`.
const LOCAL_PORT := 47130
## The lobby id a local session reports. It is not a Steam lobby and there is no
## number Valve would recognise, but the rest of the game asks `lobby_id != 0` to
## mean "there are other people on the wire" — so it needs to be something, and
## something no real lobby can collide with.
const LOCAL_LOBBY_ID := 2
## Where the stand-in account numbers start. A real SteamID64 is seventeen digits
## beginning 765, and `SOLO_STEAM_ID` is already 1 on the same reasoning: a small
## number is one no account can have, which is what makes it safe to file a local
## player under it and let every manager downstream treat him as an ordinary
## member of the crew. The peer id is added to it, so the two windows get two
## different numbers without having to agree on anything first.
const LOCAL_STEAM_BASE := 100

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

## The wire itself. `SteamMultiplayerPeer` on the Steam road and
## `ENetMultiplayerPeer` on the local one, which is the whole of the difference
## between them as far as everything above here is concerned.
var _peer: MultiplayerPeer = null
## This lobby is ENet on the loopback rather than anything of Valve's. It is what
## every call that would otherwise talk to Steam checks before it does.
var is_local := false
## A `createLobby`/`joinLobby` is out and has not been answered yet. Keeps a
## player hammering the button from opening four lobbies.
var _pending := false
## Who each peer on the wire is: `steam_id` and `name`, by peer id. Filled in by
## the peers themselves (see `_introduce`) and emptied when the wire goes down.
var _identities: Dictionary[int, Dictionary] = {}
## A wire is on its way up but is not up yet — `--host` or `--join` was given and
## the peer is opened a frame later, or a Steam invite named a lobby to join.
##
## It exists for the menu, which seats a solo player when there is nobody else
## and would otherwise seat one in the frame before the wire arrives. That man
## takes an account number of his own and the first colour off the palette, and
## the real player then arrives behind him and is handed the second — which is
## how a host ends up wearing a colour he never picked.
##
## Cleared when a lobby is entered, and by `leave_lobby` for an attempt that
## never got there.
var wire_is_coming := false


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

	# Before Steam is asked anything: `--host` and `--join` mean this window is
	# not going down that road at all, and a Steam client that happens to be
	# running should not put it there.
	if _open_from_command_line():
		# The peer opens a frame from now; until it does, the menu must not
		# decide this window is a solo game and seat somebody.
		wire_is_coming = true
		return

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


# --- The local wire, for one machine ---------------------------------------
# Steam is not involved in anything below this line. Both of these answer on the
# spot rather than through a callback, because there is nobody to ask: ENet
# either binds the port or it does not.

## Opens the local wire and holds it. Started by `--host`, and the answer is
## immediate — `lobby_entered` goes out before this returns.
func host_local(port := LOCAL_PORT) -> bool:
	if lobby_id != 0:
		lobby_failed.emit("You are already in a lobby.")
		return false
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		lobby_failed.emit("Could not listen on port %d (error %d)." % [port, error])
		return false
	_enter_local(peer, true)
	return true


## How long the local wire will sit quiet before a client decides the host is
## gone, in milliseconds. ENet's own default is about half a minute of silence,
## and a lobby is exactly that: four men standing in a van with nothing being
## sent because nobody has moved. The stock setting drops them one by one while
## the host, who hears their pings, still sees a full van — which looks like the
## game randomly kicking people. Twelve minutes is longer than any pause worth
## waiting through, and a host who has really gone is still noticed the moment
## the socket closes, which is immediate and does not wait for this at all.
const LOCAL_TIMEOUT_MS := 720000
## The two numbers `set_timeout` wants alongside the limit: how long ENet waits
## before deciding a packet went missing, and how long it keeps doubling that
## before giving up. The minimum is left short — a second — because it is also
## what paces the keepalive, and a quiet lobby needs something on the wire often
## enough that neither end starts wondering. The maximum is the one carrying the
## patience.
const LOCAL_TIMEOUT_MIN_MS := 1000
const LOCAL_TIMEOUT_MAX_MS := 600000


## Dials a local host. `connect_to_host` returning OK only means the socket is
## open; a host that is not there shows up later as `connection_failed`, which is
## the same road a Steam host who quit takes.
func join_local(address := "127.0.0.1", port := LOCAL_PORT) -> bool:
	if lobby_id != 0:
		lobby_failed.emit("You are already in a lobby.")
		return false
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		lobby_failed.emit("Could not reach %s:%d (error %d)." % [address, port, error])
		return false
	_enter_local(peer, false)
	return true


## The local half of `_enter_lobby`, and deliberately the same shape: the wire
## goes up, the flags are settled, and the same two signals go out — so a screen
## listening for a lobby cannot tell which road it came down.
func _enter_local(peer: ENetMultiplayerPeer, hosting: bool) -> void:
	_close_peer()
	_peer = peer
	multiplayer.multiplayer_peer = peer
	is_local = true
	is_host = hosting
	lobby_id = LOCAL_LOBBY_ID
	owner_id = LOCAL_STEAM_BASE + 1 if hosting else 0
	print("Local lobby — %s on port %d" % ["hosting" if hosting else "joined", LOCAL_PORT])
	wire_is_coming = false
	lobby_entered.emit(lobby_id, is_host)
	members_changed.emit(list_players())


## The stand-in for a Steam account on the local wire, and the number every
## manager downstream files this player under.
##
## The host is 1, and everybody else is numbered by where his peer id falls once
## they are sorted. It would be simpler to add the peer id straight on, but ENet
## hands a client a random id in the millions, which would make one man account
## 1955902596 and the next one something else entirely — numbers nobody can read
## in a log, and different every run. Sorting gives 2, 3, 4 instead, which is
## what the men in the van would call each other anyway.
func _local_steam_id(peer_id: int) -> int:
	return LOCAL_STEAM_BASE + _local_seat(peer_id)


## Where a peer falls once everybody on the wire is sorted, counting from one.
## The host is always 1: he is peer 1, and no ENet client is ever given that.
func _local_seat(peer_id: int) -> int:
	if peer_id == 1:
		return 1
	var peers := multiplayer.get_peers()
	if not peers.has(_our_peer_id()):
		peers.append(_our_peer_id())
	peers.sort()
	# Peer 1 is the host and holds seat one whether or not he is on our list.
	var seat := 1
	for id in peers:
		if id == 1:
			continue
		seat += 1
		if id == peer_id:
			return seat
	return seat + 1


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
	if not is_local:
		Steam.leaveLobby(lobby_id)
	_close_peer()
	lobby_id = 0
	owner_id = 0
	is_host = false
	is_local = false
	_pending = false
	wire_is_coming = false
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
	if is_local:
		return _local_players()
	for index in Steam.getNumLobbyMembers(lobby_id):
		var member_id := Steam.getLobbyMemberByIndex(lobby_id, index)
		players.append({
			"steam_id": member_id,
			"name": _persona_name(member_id),
			"is_host": member_id == owner_id,
		})
	return players


## The same list off the wire instead of off Valve. Everybody who can be heard
## from, ourselves included, in a settled order — peer ids sort, and the screens
## that draw this want a list that does not shuffle under them between frames.
func _local_players() -> Array[Dictionary]:
	var players: Array[Dictionary] = []
	var peers := multiplayer.get_peers()
	peers.append(_our_peer_id())
	peers.sort()
	for peer_id in peers:
		if peer_id == 0:
			continue
		players.append({
			"steam_id": _local_steam_id(peer_id),
			"name": name_of_peer(peer_id),
			"is_host": peer_id == 1,
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

## Which crew entry is ours. Almost always `our_steam_id()`, and different from
## it whenever Steam is shut: that answers zero, and the man is on the crew under
## `SOLO_STEAM_ID`, filed there by `_fill_the_crew` because a zero is what
## `SessionManager` refuses as "not a player".
##
## **Anything that looks a player up in the crew should ask this**, and anything
## that talks about him on the wire should ask `our_steam_id`. The two were the
## same question while the crew was only ever built on the way into the van;
## they came apart when the menu started letting a solo player pick a colour
## before there was a wire at all.
##
## The fallback of last resort is the one the stations in the van already used
## (`ColorStation._our_steam_id`, `ReadyStation._our_steam_id`) and is worth
## keeping in one place now rather than three: **a crew of one is us**, whatever
## number he is filed under. It is what makes a bench work, where the crew is
## seeded by hand under invented accounts, and it can never be wrong — a lone man
## in the van has nobody else to be.
func our_crew_id() -> int:
	var steam_id := our_steam_id()
	if steam_id != 0 and SessionManager.has_player(steam_id):
		return steam_id
	var crew := SessionManager.players.keys()
	if crew.size() == 1:
		return crew[0]
	return steam_id


## Who we are, as the crew counts people. **This, and not
## `SteamManager.get_steam_id()`, is what the rest of the game should ask**: the
## answer depends on which wire is up, and this is the one place that knows.
## Over Steam it is the real account; on the local wire it is the stand-in built
## off our peer id; with neither it is zero, and a zero is what `SessionManager`
## already refuses as "not a player".
func our_steam_id() -> int:
	if is_local:
		return _local_steam_id(_our_peer_id())
	return SteamManager.get_steam_id()


## What we are called, by the same reasoning as `our_steam_id`.
func our_name() -> String:
	if is_local:
		return _local_name(_our_peer_id())
	return SteamManager.get_persona_name()


## What a peer is called. Our own name for our own id, whatever the peer said
## for anybody else's, and `UNKNOWN_NAME` for a peer who has not spoken yet.
func name_of_peer(peer_id: int) -> String:
	if peer_id == _our_peer_id():
		return our_name()
	var known: Dictionary = _identities.get(peer_id, {})
	return String(known.get("name", UNKNOWN_NAME))


## What to call somebody with no Steam persona to read. "Player 1" is the host
## and the rest are numbered off the wire — enough to tell two windows apart on
## one desk, which is the whole job.
func _local_name(peer_id: int) -> String:
	return "Player %d" % _local_seat(peer_id)


## The Steam account behind a peer, or zero when it has not said yet. It is what
## ties a body in the map back to a row on the guest list.
func steam_id_of_peer(peer_id: int) -> int:
	if peer_id == _our_peer_id():
		return our_steam_id()
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
	_relax_local_timeout(peer_id)
	_introduce.rpc_id(peer_id, our_steam_id(), our_name())
	# The guest list on the local wire *is* the wire, so somebody arriving is a
	# change to it. On the Steam road this comes from `lobby_chat_update` instead.
	if is_local:
		members_changed.emit(list_players())


func _on_peer_disconnected(peer_id: int) -> void:
	_identities.erase(peer_id)
	_pings.erase(peer_id)
	if is_local:
		members_changed.emit(list_players())


## Loosens ENet's idea of how long a quiet peer may stay quiet. It can only be
## done once the peer exists — before the handshake there is nothing to set it
## on — which is why it hangs off `peer_connected` rather than off the call that
## opened the socket.
##
## Only the local wire needs it. Steam's transport keeps its own connection
## alive underneath and never asked this question.
func _relax_local_timeout(peer_id: int) -> void:
	if not is_local:
		return
	var enet := _peer as ENetMultiplayerPeer
	if enet == null:
		return
	var connection := enet.get_peer(peer_id)
	if connection == null:
		return
	connection.set_timeout(
		LOCAL_TIMEOUT_MIN_MS, LOCAL_TIMEOUT_MAX_MS, LOCAL_TIMEOUT_MS)

# --- How far away a peer is -------------------------------------------------
# Two wires and two answers. ENet measures the round trip itself and has done
# since before the lobby opened, so over the loopback the number is simply read
# off the connection — the same `get_peer` the timeout above is set through.
# Steam's transport keeps no such reading where the game can reach it, so on
# that road the round trip is measured the only way left: a packet is sent out
# with the clock on it and the far end sends it straight back, and half of what
# the clock has moved is the answer.
#
# **Both roads are asked through `ping_of_peer` and nothing else.** Whoever is
# drawing a list of players should not have to know which wire is under him,
# nor be handed a `MultiplayerPeer` to dig around inside; he asks for a number
# of milliseconds and is told `UNKNOWN_PING` when there is not one to give.

## What `ping_of_peer` answers when there is no reading: no wire at all, a peer
## who is not on it, a Steam peer who has not answered his first probe yet. It
## is negative rather than zero, because zero is a real and excellent ping.
const UNKNOWN_PING := -1

## How often a Steam-road probe goes out, in seconds. Once a second is often
## enough that a number on screen is never badly stale and rare enough that it
## costs nothing — a full van is three packets a second, each of them one
## integer long.
const PING_INTERVAL := 1.0

## The last round trip measured for each peer on the Steam road, in ms, by peer
## id. ENet is not in here at all: its own reading is better than ours and is
## already up to date whenever it is asked for.
var _pings: Dictionary[int, int] = {}

## What is left of the wait before the next probe goes out. Counted down in
## `_process` rather than run off a `Timer` so that there is one clock to reason
## about and nothing to remember to start and stop as lobbies come and go.
var _ping_countdown := PING_INTERVAL


## The round trip to a peer in milliseconds, or `UNKNOWN_PING` when there is no
## reading to give. **This is the only way anything above should ask.**
##
## Our own id answers zero: a man is not far from himself, and the alternative
## is every caller having to special-case his own row.
func ping_of_peer(peer_id: int) -> int:
	if peer_id == 0 or not multiplayer.has_multiplayer_peer():
		return UNKNOWN_PING
	if peer_id == _our_peer_id():
		return 0
	if not multiplayer.get_peers().has(peer_id):
		return UNKNOWN_PING
	var enet := _peer as ENetMultiplayerPeer
	if enet != null:
		var connection := enet.get_peer(peer_id)
		if connection != null:
			return int(connection.get_statistic(
				ENetPacketPeer.PEER_ROUND_TRIP_TIME))
	return int(_pings.get(peer_id, UNKNOWN_PING))


## The same question asked about an account rather than a peer, which is the
## form the crew keeps people in — so a list drawn off `SessionManager.players`
## can ask it without first having to work out which peer a man is.
##
## `UNKNOWN_PING` for somebody nobody on the wire answers for, and for the solo
## player, who has no wire and so no round trip to measure.
func ping_of_steam_id(steam_id: int) -> int:
	if steam_id == 0 or not multiplayer.has_multiplayer_peer():
		return UNKNOWN_PING
	if steam_id == our_steam_id():
		return 0
	for peer_id in multiplayer.get_peers():
		if steam_id_of_peer(peer_id) == steam_id:
			return ping_of_peer(peer_id)
	return UNKNOWN_PING


## Paces the Steam-road probe. It does nothing at all on the local wire, where
## ENet has already done the measuring, and nothing with no wire up.
func _process(delta: float) -> void:
	if is_local or not multiplayer.has_multiplayer_peer():
		return
	_ping_countdown -= delta
	if _ping_countdown > 0.0:
		return
	_ping_countdown = PING_INTERVAL
	_send_pings()


## One probe to each peer, carrying our clock. Sent unreliably on purpose: a
## probe that had to be retransmitted would come home carrying the wait for the
## retransmission, which is not the number anybody wanted, and a probe that is
## simply lost costs nothing but one more second of a slightly older reading.
func _send_pings() -> void:
	var now := Time.get_ticks_msec()
	for peer_id in multiplayer.get_peers():
		_ping_probe.rpc_id(peer_id, now)


## The probe, run on the far end. It reads no clock of its own and does no
## thinking: it hands the same stamp straight back, so that what is measured is
## the trip and not the far machine's frame rate.
@rpc("any_peer", "unreliable")
func _ping_probe(stamp: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if from == 0:
		return
	_ping_echo.rpc_id(from, stamp)


## The probe coming home. What our own clock has moved since the stamp was
## written is the whole round trip, and the ping is half of it — the one-way
## time, which is what a game showing a number means by the word.
##
## The stamp is our own and is never read off the far machine's clock, so two
## machines that disagree about what time it is still measure the same trip.
@rpc("any_peer", "unreliable")
func _ping_echo(stamp: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	if from == 0:
		return
	@warning_ignore("integer_division") # Half the round trip is the one-way time we want.
	_pings[from] = maxi(0, Time.get_ticks_msec() - stamp) / 2


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
##
## The lobby is left joinable here, and that is the change card 07 asks for: the
## van *is* the lobby phase, so a friend invited from the radio on its wall has
## to be able to walk in. What closes the door is the shift leaving the van, and
## `close_to_newcomers` is what says so — called off the phase change rather than
## off this button, so the door shuts on the one thing that actually means the
## shift has started.
func start_game() -> void:
	if lobby_id == 0:
		_enter_game()
		return
	if not is_host:
		return
	_enter_game.rpc()


## Stops Steam letting anybody else in. **Host only**, and called when the shift
## leaves the van — the lobby stays alive, because it is still the guest list;
## it just stops taking newcomers.
##
## It is belt and braces over `JoinGate`, which refuses a knock outside the lobby
## phase whatever Steam did. The difference is where the man finds out: this way
## he is told at Steam's own door, before his game has loaded anything, rather
## than after connecting to a host who then turns him around.
func close_to_newcomers() -> void:
	if lobby_id == 0 or not is_host or is_local:
		return
	Steam.setLobbyJoinable(lobby_id, false)


## Lets Steam send people in again. The other half of `close_to_newcomers`, for a
## crew that comes back to the van at the end of a shift.
func open_to_newcomers() -> void:
	if lobby_id == 0 or not is_host or is_local:
		return
	Steam.setLobbyJoinable(lobby_id, true)

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
	# filed against an id from the last lobby would be a name on a stranger. The
	# same goes for a round trip measured to him.
	_identities.clear()
	_pings.clear()
	_ping_countdown = PING_INTERVAL


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
##
## The crew is written into `SessionManager` on the way through, and it has to
## happen here rather than in the van: the van reads the crew the frame it comes
## up — to work out who stands on which spot — so a list that arrived after it
## would put everybody on spot one.
##
## **The host builds the list and the clients are told it.** Up to card 07 every
## machine built its own copy out of Steam's guest list, which worked because
## everybody had the same guest list in the same order. It stops working the
## moment somebody can arrive *after* the van is standing — which is the whole of
## card 07 — because the men already in the van would have to notice him on their
## own, off a guest list that changed under them. So there is one road in for
## everybody now: the host fills his own crew, and each client knocks
## (`JoinGate.knock`) and is handed the crew, the contract and the phase in a
## single packet before it loads anything.
@rpc("authority", "call_local", "reliable")
func _enter_game() -> void:
	if not is_host and lobby_id != 0:
		# A client waits to be welcomed rather than seating itself. The knock has
		# usually gone out already, on `connected_to_server`; this covers the
		# client that was on the wire before there was anything to ask about, and
		# a second knock is dropped rather than sent.
		JoinGate.knock()
		return

	seat_the_crew()
	# The shift moves on by *phase* and not by scene path. It used to be a path,
	# and could be, while the menu and the first phase were two different things:
	# the lobby phase was a parked van, and pressing Play in a screen that was
	# outside the phase machine altogether had to name the scene it wanted.
	#
	# The menu *is* the lobby phase now, so naming a scene would load the van
	# with the shift still reading LOBBY behind it — a van that does not move,
	# with no clock on it and no engine running, because everything in it asks
	# `PhaseManager` what is going on rather than looking at which file it is.
	# Advancing is what puts those two back in step, and `_apply` loads the scene
	# on every machine at once on the way through.
	PhaseManager.advance()


## The guest list, turned into the shift's crew. **Host and solo only.**
##
## It is called twice over, and both times matter. Once on the way into the game
## (`_enter_game`), which is what it has always been for. And once for every
## change to the guest list while the crew is still in the menu — because the
## menu is where a man now picks his colour and says he is ready, and both of
## those are written against a `SessionManager` entry that would not exist yet.
##
## Calling it repeatedly is safe by construction: `register_player` leaves a man
## who is already on the list exactly as he was, colour and ready flag included
## (`SessionManager._new_player` is only reached for somebody new), and
## `seat_everybody` re-states colours that have not changed rather than shuffling
## them.
func seat_the_crew() -> void:
	if not is_host and lobby_id != 0:
		return
	_fill_the_crew()
	_drop_the_departed()
	# The rule that no two men wear one colour is the host's to keep, so he says
	# out loud who is wearing what. It costs a handful of packets once and
	# corrects any machine whose list came out differently.
	ColorManager.seat_everybody()


## The Steam lobby's guest list, copied into the shift's own crew. **Host and
## solo only** — a client's crew comes off the wire in one packet (`JoinGate`)
## and never off its own reading of the guest list, so that there is one list and
## not four that have to agree.
##
## It is a copy and not a reference on purpose: the guest list is Valve's and is
## a list of accounts, while the crew is the game's and carries a colour, a
## purse and a ready flag per man. This is the one place the two meet.
##
## A solo run has no lobby and so no guest list. Whoever is playing is still a
## crew of one — and has to be, or the van has nobody to seat, the board has no
## flag to move and `all_ready()` answers false forever. He is his own host, the
## same way `PhaseManager.is_host()` already says he is.
##
## With Steam shut altogether his account number is zero, which the crew refuses
## as "not a player" — rightly, since a zero off the wire is a peer that never
## introduced itself. So the offline man is filed under `SOLO_STEAM_ID` instead:
## a number no real account can have, which is what makes it safe to tell the
## two apart, and which the board already falls back to finding by being the
## only man in the van.
func _fill_the_crew() -> void:
	var crew := list_players()
	if crew.is_empty():
		var steam_id := our_steam_id()
		SessionManager.register_player(
			steam_id if steam_id != 0 else SOLO_STEAM_ID, our_name(), true)
		return
	for player in crew:
		SessionManager.register_player(
			int(player["steam_id"]), String(player["name"]), bool(player["is_host"]))

## Takes off the crew anybody who is no longer on the guest list. **Host and solo
## only**, and the other half of `_fill_the_crew`: filling only ever adds, which
## was enough when the crew was built once on the way into the van and a man who
## left afterwards was somebody else's problem. In the menu the guest list is
## live, and a body left standing for a player who walked out is a body nobody
## can get rid of — and a colour nobody can wear.
##
## A lobby that has gone (`list_players` empty because we are not in one) clears
## nobody: that is `leave_lobby`'s business, and a crew wiped here would take the
## solo player with it.
func _drop_the_departed() -> void:
	var crew := list_players()
	if crew.is_empty():
		return
	var present: Dictionary[int, bool] = {}
	for player in crew:
		present[int(player["steam_id"])] = true
	for steam_id in SessionManager.players.keys():
		if not present.has(steam_id):
			SessionManager.remove_player(steam_id)


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
##
## Nothing more is needed to land him in the van, and that is worth saying out
## loud because card 07 asks for it as though it were a separate road: joining
## opens the peer, the peer coming up makes `JoinGate` knock, and the welcome
## carries the scene along with the crew. So a man who accepted an invite from
## his desktop walks straight into the back of the van without ever seeing the
## waiting-room screen, down exactly the same code as a man who was already in
## the lobby list.
func _join_from_command_line() -> void:
	var id := _lobby_from_arguments(Steam.getLaunchCommandLine().split(" ", false))
	if id == 0:
		id = _lobby_from_arguments(OS.get_cmdline_args())
	if id == 0:
		return
	# The join is a frame away, and the menu must not seat a solo player in the
	# meantime — the crew this window is about to be handed is somebody else's.
	wire_is_coming = true
	await get_tree().process_frame
	join_lobby(id)


## `--host` and `--join` off the command line, which is how two windows on one
## desk find each other. `--join` takes an optional address, so that a second
## machine on the same desk — or a phone tethered to it — can be dialled without
## a rebuild: `--join 192.168.1.7`.
##
## One frame of patience before the wire opens, for the same reason the Steam
## road waits: whatever is on screen should already be listening when the answer
## comes back.
func _open_from_command_line() -> bool:
	var arguments := OS.get_cmdline_args()
	var hosting := arguments.has("--host")
	var joining := arguments.has("--join")
	if not hosting and not joining:
		return false
	if hosting and joining:
		push_warning("Both --host and --join were given; hosting.")
		joining = false
	_open_local_deferred(hosting, _address_from_arguments(arguments))
	return true


func _open_local_deferred(hosting: bool, address: String) -> void:
	await get_tree().process_frame
	var opened := host_local() if hosting else join_local(address)
	# A wire that could not be brought up is a wire nobody should keep waiting
	# for: the window is a solo game after all, and the menu is entitled to seat
	# somebody on the floor. `_enter_local` clears this on the way through when
	# it does come up.
	if not opened:
		wire_is_coming = false


## The address after `--join`, or the loopback when there is none. Anything
## starting with a dash is the next flag rather than an address.
func _address_from_arguments(arguments: PackedStringArray) -> String:
	var at := arguments.find("--join")
	if at == -1 or at + 1 >= arguments.size():
		return "127.0.0.1"
	var candidate := arguments[at + 1]
	return "127.0.0.1" if candidate.begins_with("-") else candidate


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
