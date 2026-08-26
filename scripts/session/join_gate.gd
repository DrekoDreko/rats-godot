extends Node
## The door of the van: who is let in, what he is told on the way through, and
## what is cleared up behind him when he leaves.
##
## Everything else about the lobby was already written — Steam holds the guest
## list (`LobbyManager`), the crew and its colours live on `SessionManager`, the
## host drives the phases (`PhaseManager`). What was missing is the moment
## between those two: a man accepts an invite, his peer comes up on the wire, and
## for a second or two he is *connected but not in the crew*. He does not know
## what colour anybody is wearing, which contract was signed or even which phase
## the shift is in. This node is what fills that second.
##
## **The host is the doorman.** A newcomer's machine knows nothing worth
## trusting, so it asks rather than announces: it sends one knock
## (`_knock`) and waits. The host looks at the phase, counts the crew and either
## sends back the whole shift in one packet (`_welcome`) or a refusal in a
## sentence (`_turn_away`). The newcomer writes nothing about himself until the
## answer lands, which is what stops two machines from disagreeing about who is
## in the van.
##
## **The state goes out before the body does.** The card is explicit about it and
## the reason is visible on screen: a player who spawns first and is told the
## crew afterwards stands in the van for a moment as a grey man among grey men,
## and then everybody flickers into their colours at once. So the welcome carries
## the crew, the contract and the phase, all of it is written on arrival, and the
## van scene is only loaded on the far side of that (`_apply_welcome`).
##
## **Three ways in, one door.** The lobby screen's PLAY, an invite accepted with
## the game running, and an invite accepted with the game closed (Steam's
## `+connect_lobby` on the command line) all end at the same place: a peer
## connected to the host with no crew entry. `LobbyManager` handles the Steam
## half of all three; this handles the second half of all three, so there is one
## set of rules and not three.
##
## **A shift in progress is closed.** The host refuses a knock outside
## `Phase.Type.LOBBY` — politely, with a sentence the newcomer can read — and
## the lobby is also marked unjoinable on Steam the moment the van leaves
## (`LobbyManager.start_game`), so most people never get as far as knocking. The
## check here is what catches the one who was already through the Steam door when
## the van pulled away.
##
## **What leaves has to be cleaned up.** A peer dropping off the wire is a man
## out of the crew: his entry goes (which is what puts his colour back on the
## rack — see `ColorManager`), and whoever is left is asked again whether they
## are all ready, so two men are not held at the door by a third who is gone.
## That last part is already `ReadyManager`'s, listening on `player_left`; all
## this has to do is take the entry out and let the signal do its work.

## We were let in. Carries the phase we arrived in, so that whoever is listening
## knows whether to expect the van or something further along.
signal joined(phase: Phase.Type)

## We knocked and were turned away. `reason` is a sentence meant to be read by a
## player — it goes on the lobby screen's status line.
signal refused(reason: String)

## Somebody was let into the crew, on every machine. `SessionManager.player_joined`
## says the same thing for every road into the crew; this one fires only for a
## man who came through the door, which is what a van full of stations wants to
## know about.
signal player_admitted(steam_id: int)

## The peer that decides. The same 1 the rest of the session autoloads use, and
## for the same reason: Godot hands it to the host the moment the wire comes up,
## and it is a surer answer than a Steam ID that may not have been introduced
## yet.
const HOST_PEER := 1

## How many fit in the van. The same four `LobbyManager` clamps its lobby to —
## Steam turns the fifth away at its own door, and this is the check for the case
## Steam cannot see: a machine that reached the wire while the crew was filling
## up.
const MAX_PLAYERS := 4

## Where a newcomer is put once he has been let in. The lobby phase's own scene,
## which is what card 07 asks for by name: an invite accepted with the game
## closed has to end in the van and not on the waiting-room screen.
const LOBBY_SCENE := "res://scenes/menu.tscn"

## What the host says when he turns somebody away. They are sentences and not
## codes because the only thing done with them is putting them on a screen.
const REFUSAL_IN_PROGRESS := "That shift is already under way — try them next time."
const REFUSAL_FULL := "That van is full."
const REFUSAL_UNKNOWN := "Steam did not say who you are — try joining again."

## How long a knock may go unanswered before it is sent again, in seconds. A
## knock is one reliable packet and the welcome is another, so losing either is
## rare — but "rare" over a session is "eventually", and the cost of being the
## one it happened to is standing outside a van nobody can see you are missing
## from. Three seconds is long enough that a slow host is not knocked at twice
## for no reason, and short enough that a player does not read it as the game
## having hung.
const KNOCK_TIMEOUT := 3.0

## Whether we have been let in and are standing in the crew. It is what keeps a
## second knock from going out when the wire hiccups, and what tells a client
## arriving in an already-loaded van that it has nothing to ask for.
var admitted := false

## A knock is out and has not been answered. Cleared by either answer, and by
## the timeout below, which is what makes it a wait rather than a dead end.
var _knocking := false

## Seconds left on the knock that is out, counted down in `_process`. Zero when
## no knock is waiting on anything.
var _knock_timeout := 0.0

## We wanted to knock but Steam had not said who we are yet, so the knock is
## held until `LobbyManager.peer_identified` says the introduction landed. It is
## a wait and not a refusal: knocking with an ID of zero is the one thing the
## host is certain to turn away (`REFUSAL_UNKNOWN`), and the answer is a moment
## away rather than absent.
var _waiting_for_identity := false


func _ready() -> void:
	# A knock can be answered while the game is paused — a man accepting an
	# invite from a paused game is the ordinary case — so the packet still has
	# to land. The same reason `PhaseManager` and `ReadyManager` are set this
	# way.
	process_mode = Node.PROCESS_MODE_ALWAYS

	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	LobbyManager.lobby_left.connect(_on_lobby_left)
	# The other road to the door: a client whose wire came up before Steam had
	# introduced anybody knocks off this instead (see `knock`).
	LobbyManager.peer_identified.connect(_on_peer_identified)
	PhaseManager.phase_changed.connect(_on_phase_changed)


## Watches the knock that is out. It is the whole of what this node does per
## frame, and it does nothing at all once we are in — `_knocking` is false for
## every machine that has been welcomed, and for the host always.
func _process(delta: float) -> void:
	if not _knocking:
		return
	_knock_timeout -= delta
	if _knock_timeout > 0.0:
		return
	# The knock, or the answer to it, did not arrive. Only worth sending again
	# while the wire that would carry it is still up: a client that has lost the
	# host is `NetworkGuard`'s problem, not this one.
	_knocking = false
	if admitted or PhaseManager.is_host() or not multiplayer.has_multiplayer_peer():
		return
	push_warning("JoinGate: the knock went unanswered for %.0fs — knocking again."
		% KNOCK_TIMEOUT)
	knock()


## Whether the door is open at all: only in the lobby phase, and only while
## there is room. The host asks it before answering a knock, and the lobby
## screen asks it to know whether to grey out its invite button.
func is_open() -> bool:
	if PhaseManager.current() != Phase.Type.LOBBY:
		return false
	return SessionManager.count() < MAX_PLAYERS


## Why the door is shut, or an empty string when it is not. Kept apart from
## `is_open` so that the reason is written once and read both by the host
## answering a knock and by anything that wants to explain itself locally.
func refusal_reason() -> String:
	if PhaseManager.current() != Phase.Type.LOBBY:
		return REFUSAL_IN_PROGRESS
	if SessionManager.count() >= MAX_PLAYERS:
		return REFUSAL_FULL
	return ""


## Knocks on the host's door. Called by a client the moment it is connected, and
## safe to call twice — the second one is dropped rather than sent.
##
## The host has nobody to ask: he is the door. He puts himself in the crew
## directly and is done, which is the same shape every other request in the
## session takes (`ReadyManager.request_set`, `ColorManager.request_color`) and
## is what keeps a solo run from being a second set of rules.
##
## **A man who cannot say who he is does not knock yet.** `our_steam_id()` is
## zero until Steam has answered or, on the local wire, until we have a peer id
## to build a stand-in from. Knocking anyway spends the one packet on a
## certain refusal, so the knock is held and `peer_identified` sends it — which
## is a wait of a moment rather than a trip back to the lobby screen.
func knock() -> void:
	if admitted or _knocking:
		return
	if PhaseManager.is_host():
		_admit_host()
		return

	var steam_id := LobbyManager.our_steam_id()
	if steam_id == 0:
		_waiting_for_identity = true
		return

	_waiting_for_identity = false
	_knocking = true
	_knock_timeout = KNOCK_TIMEOUT
	_knock.rpc_id(HOST_PEER, steam_id, LobbyManager.our_name())


## Takes a player out of the crew and lets the rest of the game know. **Host
## only** in a real game — it is a decision, and it is broadcast — but it is
## written so that a solo machine calling it simply does the local half.
##
## The colour is not touched here: the crew entry is what held it, so removing
## the entry is what frees it (see `ColorManager`), and a second line trying to
## give it back would be a second place for the rack to be wrong.
func drop_player(steam_id: int) -> void:
	if not PhaseManager.is_host() or not SessionManager.has_player(steam_id):
		return
	_remove.rpc(steam_id)

# --- The wire ---------------------------------------------------------------

## A newcomer knocking, arriving at the host. `any_peer` because anybody may
## knock; what makes it safe is that the host is the only one who acts on it, and
## that everything in the packet is checked below rather than taken on trust.
@rpc("any_peer", "reliable")
func _knock(steam_id: int, persona: String) -> void:
	if not PhaseManager.is_host():
		push_warning("JoinGate: a knock reached a machine that is not the host.")
		return
	_handle_knock(steam_id, persona, multiplayer.get_remote_sender_id())


## The host's decision about a newcomer, in one place.
##
## Three things are checked, and each of them is a way the van could otherwise be
## made to hold somebody it should not:
##
## - **He said who he is.** A Steam ID of zero is a machine whose introduction
##   has not landed, and filing a crew entry under zero would be a man nobody can
##   address afterwards.
## - **The phase.** A shift already on the road does not take passengers, and the
##   man is told so rather than left waiting.
## - **The room.** Four is the van. Steam turns the fifth away at its own door,
##   but a machine that got through while the crew was still filling up has to be
##   caught here.
##
## A knock from somebody already in the crew is not a mistake worth refusing: a
## packet can genuinely arrive twice, and the honest answer to "am I in?" from
## somebody who is, is the welcome again.
func _handle_knock(steam_id: int, persona: String, from_peer: int) -> void:
	if steam_id == 0:
		_turn_away(from_peer, REFUSAL_UNKNOWN)
		return
	# The host's own entry, before anybody is told what the crew looks like. He
	# ordinarily has one already — `_enter_game` fills it on the way into the
	# van — but a knock can beat that, and a welcome built from an empty crew is
	# a newcomer standing in a van with no host in it. It costs one dictionary
	# lookup on every knock to make that impossible.
	if not admitted:
		_admit_host()
	if not SessionManager.has_player(steam_id):
		var reason := refusal_reason()
		if not reason.is_empty():
			_turn_away(from_peer, reason)
			return
		SessionManager.register_player(steam_id, persona, false)
		# The men already in the van hear about him here; he hears about them in
		# the welcome below. Two directions, because the two sides start from
		# different places — they have a crew missing one name, he has no crew at
		# all.
		_admitted.rpc(steam_id, persona)
		# The crew has changed shape, so the host says out loud who is wearing
		# what. It is what stops the newcomer — who worked out his own first free
		# colour from a crew list he did not have yet — from arriving in a colour
		# somebody in the van is already wearing. It goes out after the
		# admission, so that every machine has the entry to paint before the
		# colour for it lands.
		ColorManager.seat_everybody()

	_welcome.rpc_id(from_peer, _snapshot())


## The whole shift in one packet, landing on the newcomer before he spawns.
##
## It is deliberately everything at once rather than a handful of smaller
## messages that each announce one thing. Half a crew is worse than no crew: the
## van reads `SessionManager.players` the frame it comes up to work out who
## stands on which spot, and a list still arriving would put two men on one
## marker.
@rpc("authority", "reliable")
func _welcome(state: Dictionary) -> void:
	if multiplayer.get_remote_sender_id() != HOST_PEER:
		return
	_knocking = false
	_knock_timeout = 0.0
	_waiting_for_identity = false
	_apply_welcome(state)


## The host's refusal, landing only on the man who knocked. He is out of the
## lobby afterwards rather than left connected to a game he is not in — a peer
## on the wire with no crew entry is a body nothing will ever draw.
@rpc("authority", "reliable")
func _turn_away_rpc(reason: String) -> void:
	if multiplayer.get_remote_sender_id() != HOST_PEER:
		return
	# A refusal is an answer, and an answer ends the knocking for good: knocking
	# again at a host who has just said no would be the retry turning into a
	# machine that will not take no for an answer.
	_knocking = false
	_knock_timeout = 0.0
	_waiting_for_identity = false
	admitted = false
	refused.emit(reason)
	LobbyManager.leave_lobby()


## Somebody was let in, on every machine at once — the host included
## (`call_local`), because the crew he is announcing is his own and a van that
## drew the newcomer everywhere but on the host's screen is the bug this
## prevents.
##
## It carries the name as well as the ID, and it has to: a machine that was
## already in the van when this man arrived has no entry for him — the welcome
## went to him and not to them — so this is where they build one. The colour is
## not in the packet because it is not settled yet; it follows a moment later on
## `ColorManager.seat_everybody`, and until then he wears whatever
## `SessionManager` handed him at the door.
@rpc("authority", "call_local", "reliable")
func _admitted(steam_id: int, persona: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("JoinGate: an admission from peer %d, which is not the host — ignored."
			% sender)
		return
	# Not a mistake worth a warning when the entry is already there: the host has
	# just made it himself, and `register_player` updates a known man rather than
	# starting his entry over.
	SessionManager.register_player(steam_id, persona, false)
	player_admitted.emit(steam_id)


## A player out of the crew, on every machine at once. It is the one road out:
## a client noticing a peer drop does not remove anybody itself, because two
## machines each removing on their own timing is two machines disagreeing about
## who is still owed a ready flag.
@rpc("authority", "call_local", "reliable")
func _remove(steam_id: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("JoinGate: a removal from peer %d, which is not the host — ignored."
			% sender)
		return
	SessionManager.remove_player(steam_id)

# --- The two sides of the handshake -----------------------------------------

## The host putting himself in the crew. He never knocks — there is nobody to
## knock at — so this is where his own entry comes from, and it is the same entry
## every client gets, made the same way.
func _admit_host() -> void:
	var steam_id := LobbyManager.our_steam_id()
	if steam_id == 0:
		# No Steam at all. `LobbyManager` files the solo player under an ID no
		# real account can have, and it is the same one here so that the two
		# roads into a solo crew do not make two different men.
		steam_id = LobbyManager.SOLO_STEAM_ID
	SessionManager.register_player(steam_id, LobbyManager.our_name(), true)
	admitted = true
	joined.emit(PhaseManager.current())


## Everything about the shift that a newcomer has to have before he is anywhere.
## Built by the host, read by `_apply_welcome`, and deliberately flat — a
## dictionary of plain values goes over the wire without anybody having to keep
## a resource in step on both ends.
func _snapshot() -> Dictionary:
	var crew: Array[Dictionary] = []
	for steam_id in SessionManager.players:
		var entry := SessionManager.players[steam_id]
		crew.append({
			"steam_id": steam_id,
			"name": entry["name"],
			"color": entry["color"],
			"ready": entry["ready"],
			"money": entry["money"],
			"inventory": entry["inventory"],
			"is_host": entry["is_host"],
		})
	return {
		"crew": crew,
		"contract": SessionManager.current_contract,
		"phase": SessionManager.phase,
		"seed": SessionManager.random_seed,
		"pins": MapManager.state(),
	}


## The welcome, written down. The crew first, then the shift's own state, then
## the scene — in that order, because the van reads the crew on the way up and a
## scene loaded before the list arrived would be a van that seats everybody
## wrong.
##
## The crew is rebuilt rather than merged: what the host says is the crew *is*
## the crew, and an entry left over from a previous lobby on this machine would
## be a man in the van that nobody else can see.
func _apply_welcome(state: Dictionary) -> void:
	var crew: Array = state.get("crew", [])
	for steam_id in SessionManager.players.keys():
		SessionManager.remove_player(steam_id)

	for entry in crew:
		var steam_id := int(entry["steam_id"])
		SessionManager.register_player(steam_id, String(entry["name"]), bool(entry["is_host"]))
		SessionManager.set_color(steam_id, entry["color"])
		SessionManager.set_ready(steam_id, bool(entry["ready"]))
		SessionManager.set_money(steam_id, int(entry["money"]))
		for item_id in entry.get("inventory", []):
			SessionManager.add_item(steam_id, String(item_id))

	# Through the contract manager rather than straight onto `SessionManager`,
	# because a signature is more than a string: it also points the phase machine
	# at the house and takes the hold off the ready boards. A newcomer who only
	# copied the id would stand in a van whose boards still refused to leave.
	ContractManager.adopt(String(state.get("contract", "")))
	MapManager.adopt(state.get("pins", []))
	SessionManager.random_seed = int(state.get("seed", 0))
	var phase: Phase.Type = state.get("phase", Phase.Type.LOBBY)
	SessionManager.phase = phase

	admitted = true
	joined.emit(phase)
	_enter_scene(phase)


## Into the scene the shift is standing in. Only when we are not already there —
## the ordinary case for a player who pressed PLAY is that the van is loading
## around him already, and reloading it would take his spawn spot away and put
## it back.
func _enter_scene(phase: Phase.Type) -> void:
	var path := PhaseManager.scene_of(phase)
	if path.is_empty():
		path = LOBBY_SCENE
	var current := get_tree().current_scene
	if current != null and current.scene_file_path == path:
		return
	get_tree().change_scene_to_file(path)


## The host turning somebody down, whoever it was. His own refusal never goes on
## the wire — a host cannot be turned away from his own van, and the only way
## this is reached with his own peer id is a bench.
func _turn_away(peer_id: int, reason: String) -> void:
	if peer_id == 0 or peer_id == HOST_PEER:
		refused.emit(reason)
		return
	_turn_away_rpc.rpc_id(peer_id, reason)

# --- What the wire does under us --------------------------------------------

## Connected to the host. This is a client's cue and nobody else's: the moment
## the wire is up, it knocks.
func _on_connected_to_server() -> void:
	knock()


## An introduction landed. The only thing wanted from it here is the one case
## that held a knock back: our own ID was not known when the wire came up, and
## now it is. Anybody else's introduction is no business of this node's, and a
## knock that is already out is left alone rather than doubled.
func _on_peer_identified(_peer_id: int) -> void:
	if not _waiting_for_identity:
		return
	if LobbyManager.our_steam_id() == 0:
		return
	knock()


## A peer dropped. **The host acts, and only the host** — he is the one who says
## who is in the crew, and a client removing on its own timing would be a second
## opinion about who the ready flags are still owed by.
##
## The crew is keyed by Steam ID and the wire by peer id, so the man has to be
## looked up before he can be taken out. A peer that never introduced itself has
## no Steam ID to look up and leaves nothing behind to clean.
func _on_peer_disconnected(peer_id: int) -> void:
	if not PhaseManager.is_host():
		return
	var steam_id := LobbyManager.steam_id_of_peer(peer_id)
	if steam_id == 0:
		return
	drop_player(steam_id)


## The host is gone and the wire with him. Nothing here is worth keeping: the
## crew belongs to a shift that has ended, and the next lobby fills it again from
## its own welcome.
func _on_server_disconnected() -> void:
	admitted = false
	_knocking = false
	_knock_timeout = 0.0
	_waiting_for_identity = false


## We walked out. Same as above, and it covers the roads that do not go through a
## dropped connection — a player pressing Leave, or Steam saying the lobby has
## fallen apart.
func _on_lobby_left() -> void:
	admitted = false
	_knocking = false
	_knock_timeout = 0.0
	_waiting_for_identity = false


## The shift moved, so the door moves with it: shut once the van pulls away, open
## again if the crew ever comes back to it.
##
## Shutting it at Steam's own door as well as at this one is not doubling up for
## its own sake — it is where the man finds out. Steam turning him away costs him
## nothing; being turned away here costs him a connection to a host who then
## sends him home. **Host only**, because it is his lobby to close.
func _on_phase_changed(_previous: Phase.Type, current: Phase.Type) -> void:
	if not PhaseManager.is_host():
		return
	if current == Phase.Type.LOBBY:
		LobbyManager.open_to_newcomers()
	else:
		LobbyManager.close_to_newcomers()
