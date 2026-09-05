extends Node
## Who has said they are ready, and what happens when the last one does.
##
## The same question is asked three times in a shift — ready to leave the van,
## ready to get off the road, ready to let the rats out — and it is the same
## question every time, so it is answered in one place rather than three. The
## board in the van, the board on the road and the button in the hall are all
## the same node (`scripts/session/ready_station.gd`) talking to this.
##
## **The host holds the flags.** A player who slaps the board does not go ready;
## he *asks* to (`request_toggle`), the host decides, and the host tells
## everybody the answer at once (`_apply`). Nothing is written locally first and
## corrected later. That costs the man who pressed it a round trip before his
## own light turns green, which is the honest price of every board in the game
## reading the same thing — and it means a client that has been tampered with
## can lie about nothing, because it was never the one holding the flag.
##
## **Two things end a phase, and both of them are the host's.** All of the crew
## ready, or the clock running out. This node watches for the first; the second
## already belonged to the phase machine (`PhaseManager._on_timeout`) and is
## left there. Neither one asks the other's permission, and a phase that ends
## both ways at once ends once, because `go_to` refuses the phase it is already
## in.
##
## **A man who left cannot hold the door.** `SessionManager.all_ready()` counts
## only the people actually in the crew, so a player who drops out stops being
## somebody the others are waiting on the moment he is taken out of it. What is
## needed here is only to ask the question again when the crew changes, which is
## what `player_left` is connected for — otherwise the two who are already ready
## would stand there waiting on a name that is gone.
##
## **No flag is carried into the next phase.** `PhaseManager._apply` clears them
## on the way through, so nobody arrives at the next station already ready. It is
## done there rather than in `go_to` on purpose: `_apply` is the part that runs
## on every machine, and a reset the host kept to himself is what left a guest
## on the road looking at a board that was still green.

## Somebody's ready flag moved. `SessionManager.player_changed` says the same
## thing among everything else that can change about a player; this one carries
## the ready and nothing but, and is what the boards light off.
signal ready_changed(steam_id: int, value: bool)

## We asked and were refused. Emitted only on the machine that asked, which is
## what a station plays its buzzer off. `reason` is a sentence.
signal request_refused(reason: String)

## The shift stopped being allowed to walk on, or started being allowed again.
## The boards listen: a plate that is green while the van is held is a plate
## telling the man he has done everything he can, which is a lie he can only find
## out about by standing there watching nothing happen.
signal hold_changed(held: bool)

## The peer that decides. The same 1 the phase machine uses, and for the same
## reason: Godot hands it to the host the moment the wire comes up.
const HOST_PEER := 1

## What the last man ready is told when the crew is all green and the shift still
## does not move. There is only one thing that holds it — `blocked`, which
## `ContractManager` raises while nothing is signed — so the sentence names it
## rather than saying "something".
const REASON_HELD := "No job is signed — the van has nowhere to go."

## The phases in which saying ready means anything. The hunt ends when the house
## is clear and the pay slip ends when it is read; neither is waiting on a show
## of hands, and a board left standing in one of them should refuse out loud
## rather than quietly do nothing.
const PHASES: Array[Phase.Type] = [
	Phase.Type.LOBBY,
	Phase.Type.TRAVEL,
	Phase.Type.SURVEY,
]

## Whether the shift is allowed to walk on when everybody says so. It is here
## for the contract card, which has to hold the van until the host has signed
## something: with this set, the boards still light and the crew still goes
## green, but the last man ready does not take the van away.
var blocked := false:
	set(value):
		if blocked == value:
			return
		blocked = value
		hold_changed.emit(blocked)
		# Unblocking with the crew already all green has to move the shift, or
		# it sits in a lobby everybody has finished with, waiting on a board
		# that has already been pressed.
		if not blocked:
			_check_everybody()


func _ready() -> void:
	# A phase can end while the game is paused, so the packet that says so still
	# has to land. Same as `PhaseManager`, and for the same reason.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# A man who walks out is a man nobody is waiting on any more. Asked again
	# rather than assumed, because he may well have been the only one missing.
	SessionManager.player_left.connect(_on_player_left)


## Whether ready means anything where the shift is standing. The stations ask
## before they draw themselves, so that a board in the wrong phase is dark
## rather than a board that lies.
func is_active() -> bool:
	return PHASES.has(PhaseManager.current())


## Whether a player has said it. A thin way through to `SessionManager`, so a
## station has one autoload to talk to rather than two.
func is_ready(steam_id: int) -> bool:
	return SessionManager.is_ready(steam_id)


## How many have said it, and how many there are — the two numbers the HUD draws
## as "2/4 ready".
func counts() -> Array[int]:
	return [SessionManager.ready_count(), SessionManager.count()]


## Whether everybody the host is waiting on has said it. `steam_id` is the man
## doing the waiting — the host — and he is left out of the count for the reason
## `SessionManager.all_ready_except` gives: in the menu he holds the button
## instead of a board, so his own flag never moves.
##
## It is what the menu's PLAY asks before it starts a shift. The stations in the
## van keep asking `SessionManager.all_ready()`, because out there the host slaps
## a board like everybody else.
func others_ready(steam_id: int) -> bool:
	return SessionManager.all_ready_except(steam_id)


## How many of them have said it, and how many they are — the two numbers the
## host's button draws, with himself out of both.
func others_counts(steam_id: int) -> Array[int]:
	return SessionManager.ready_counts_except(steam_id)


## Asks the host to flip our own flag. **This is the only way in from a
## station** — it never writes anything itself, and what comes back is `_apply`
## on every machine at once, our own included.
func request_toggle(steam_id: int) -> void:
	request_set(steam_id, not SessionManager.is_ready(steam_id))


## The same, to a stated value rather than to the other one. Off the wire (a solo
## game, a bench) an `rpc_id` to peer 1 would be an error in the log for an
## answer that is already here, so the request is handed straight to the host's
## own handler. It is the same code down either road, which is what keeps solo
## from being a second set of rules.
func request_set(steam_id: int, value: bool) -> void:
	if steam_id == 0:
		return
	if PhaseManager.is_host():
		_handle_request(steam_id, value, _our_peer_id())
		return
	_request.rpc_id(HOST_PEER, steam_id, value)

# --- The wire ---------------------------------------------------------------

## A player's request, arriving at the host. `any_peer` because anybody may ask;
## what makes it safe is that the host is the only one who acts on it, and that
## what he does with it is checked below rather than taken on trust.
@rpc("any_peer", "reliable")
func _request(steam_id: int, value: bool) -> void:
	if not PhaseManager.is_host():
		push_warning("ReadyManager: a ready request reached a machine that is not the host.")
		return
	_handle_request(steam_id, value, multiplayer.get_remote_sender_id())


## The host's decision, in one place so that it is the same whether the request
## came off the wire or out of a solo game.
##
## Three things are checked, and each of them is a way a board could otherwise be
## made to lie:
##
## - **The phase.** A board that survived into the hunt is not a vote.
## - **The crew.** A Steam ID nobody has been introduced to is not a player, and
##   filing a flag against one would leave `all_ready` waiting on a ghost.
## - **Whose flag it is.** A peer may only move his own. Without this, any client
##   could mark the whole van ready and take everybody down the road.
func _handle_request(steam_id: int, value: bool, from_peer: int) -> void:
	if not is_active():
		_refuse_to(from_peer, "Nobody is waiting on you here.")
		return
	if not SessionManager.has_player(steam_id):
		push_warning("ReadyManager: ready asked for %d, who is not in the crew." % steam_id)
		return
	if not _may_speak_for(from_peer, steam_id):
		push_warning("ReadyManager: peer %d tried to move %d's flag." % [from_peer, steam_id])
		return
	# Asking for the value it already holds. Nothing to write — but the only way
	# a client gets here is that its copy of the flag disagreed with this one, so
	# it is drawing a board the host would not recognise. Putting the answer back
	# to that peer alone costs one packet and is what stops him pressing twice.
	if SessionManager.is_ready(steam_id) == value:
		_answer_to(from_peer, steam_id, value)
		return
	if multiplayer.has_multiplayer_peer() \
			and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_apply.rpc(steam_id, value)
	else:
		_apply(steam_id, value)
	_check_everybody()
	# Everybody has said it and the shift is still standing. The only way that
	# happens is `blocked`, and the man who just pressed the last board has to be
	# told: without this he is looking at a row of green lights and a van that
	# will not arrive, with nothing on screen to say why.
	if blocked and is_active() and SessionManager.all_ready():
		_refuse_to(from_peer, REASON_HELD)


## Whether a peer is allowed to move a Steam ID's flag: his own only. The host
## calling in from his own game arrives as his own peer id — or as zero with no
## wire at all, which is a machine with nobody to lie to.
func _may_speak_for(from_peer: int, steam_id: int) -> bool:
	if from_peer == 0 or not multiplayer.has_multiplayer_peer():
		return true
	var owner_id := LobbyManager.steam_id_of_peer(from_peer)
	# A peer whose introduction has not landed yet has no Steam ID to check
	# against. Refusing him would mean a board that does nothing for the first
	# second of a lobby, which is a worse bug than the one being guarded
	# against — and the introduction is already on its way.
	return owner_id == 0 or owner_id == steam_id


## The answer, run on every machine at once, the host included (`call_local`).
## The flag is written here and nowhere else — a station reacts to this, it does
## not write ahead of it.
@rpc("authority", "call_local", "reliable")
func _apply(steam_id: int, value: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("ReadyManager: ready change from peer %d, which is not the host — ignored."
			% sender)
		return
	if not SessionManager.has_player(steam_id):
		return
	SessionManager.set_ready(steam_id, value)
	ready_changed.emit(steam_id, value)


## A refusal, landing only on the man who asked. It is a sentence and not a code,
## because the only thing anybody does with it is put it on a screen or play a
## buzzer beside it.
@rpc("authority", "reliable")
func _refuse(reason: String) -> void:
	if multiplayer.get_remote_sender_id() != HOST_PEER:
		return
	request_refused.emit(reason)


## The host turning somebody down, whoever it was. His own refusal never goes on
## the wire — it is already on the machine that has to hear it.
func _refuse_to(peer_id: int, reason: String) -> void:
	if peer_id == 0 or peer_id == _our_peer_id():
		request_refused.emit(reason)
		return
	_refuse.rpc_id(peer_id, reason)


## The host repeating a flag to one peer whose copy had drifted. The same shape
## as `_refuse_to`: nothing goes on the wire for the host's own machine, which
## already holds the answer it just read. `_apply` is what lands, so the board
## is put right by the same road every other change takes.
func _answer_to(peer_id: int, steam_id: int, value: bool) -> void:
	if peer_id == 0 or peer_id == _our_peer_id():
		return
	if not multiplayer.has_multiplayer_peer() \
			or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	_apply.rpc_id(peer_id, steam_id, value)

# --- What ends a phase ------------------------------------------------------

## The whole crew has said it. **Host only** — it is the host who moves the
## shift, and every road into this one is already on his machine.
##
## The crew being empty is not everybody being ready (`all_ready` answers false
## for it on purpose), which is what stops a van whose last player just quit from
## driving itself through the rest of the shift.
func _check_everybody() -> void:
	if not PhaseManager.is_host() or blocked or not is_active():
		return
	if not SessionManager.all_ready():
		return
	PhaseManager.advance()


## Somebody left. Whoever is still here may now be all of the crew there is, and
## the ones already green should not be kept waiting on a name that has gone.
func _on_player_left(_steam_id: int) -> void:
	_check_everybody()


## Our own id on the wire, or zero when there is no wire to have one on — asking
## Godot for an id then is an error in the log for an answer nobody needed. The
## same shape as `LobbyManager._our_peer_id`, and for the same reason.
func _our_peer_id() -> int:
	if not multiplayer.has_multiplayer_peer():
		return 0
	var peer := multiplayer.multiplayer_peer
	if peer is OfflineMultiplayerPeer:
		return 0
	return multiplayer.get_unique_id()
