extends Node
## The board of jobs, the crew's vote on which one goes first, and the one
## signature that settles it.
##
## Everybody may read the board — a crew that cannot see what it is about to
## walk into is a crew that cannot argue about it. Everybody may vote, too:
## the sheets go up on their own the moment the van pulls off
## (`_on_phase_changed`), every man in the crew, leader included, picks a card
## (`request_vote`), and once all of them have, the host reads the room and
## signs whichever job has the most hands up (`settle_vote` ->
## `_winning_contract`). **Only the host settles it** — that is the one rule
## left from the clipboard this replaced, and it is held the way every other
## decision in the van is: a client asks, the host decides, and the host's
## answer is what every machine writes down.
##
## **The vote happens on the road, not in the menu.** The van leaves as soon as
## the host presses PLAY and the crew argues about the house on the way there,
## which is the one stretch of the shift where everybody is sitting down with
## nothing else to do. Until it is settled nobody is out of his seat: the screen
## the vote is drawn on takes the player the same way the shop does
## (`contract_vote_screen.gd`), so a van full of men walking about is a van
## whose job is already chosen.
##
## **The length of the hunt is settled here too**, and by the same rule and the
## same road (`request_hunt_time` -> `_handle_hunt_time` -> `_apply_hunt_time`).
## It sits beside the vote rather than in the phase machine because it is the
## second half of one decision: the sheets say how bad each house is, and the
## booking says how long the crew gives itself in whichever one wins and what
## that is worth (`HuntTime`). A crew voting without knowing the wager is a
## crew betting blind.
##
## **The catalogue is read off disk, not registered.** Every machine scans
## `resources/contracts/` on the way up and sorts what it finds, so all of them
## have the same list in the same order and a contract can travel as its `id`
## alone. Dropping a new `.tres` in that folder puts it on the board on every
## machine at once, which is only true because nothing anywhere holds a second
## list that would have to be kept in step.

## The host signed something. `contract_id` is empty when the board was cleared,
## which is what the start of a new shift looks like.
signal contract_signed(contract_id: String)

## The sheets went up for a vote. Host only, and it is the van pulling off that
## puts them up — see the "Voting" section below.
signal voting_opened()

## Somebody's vote was counted — a fresh one or a switched one.
signal vote_changed(steam_id: int, contract_id: String)

## The vote closed: the job that won is signed and the crew has its legs back.
signal voting_closed()

## The host booked the hunt at a length. Fired on every machine, the host's
## included, so that a clipboard drawing the wager never has to ask who it is.
signal hunt_time_set(hunt_time: HuntTime.Type)

## We asked for something and were turned down. Emitted only on the machine that
## asked — the clipboard plays its buzzer and prints the sentence off this, and
## nobody else's screen hears about it.
signal request_refused(reason: String)

## The peer that decides. Peer 1, the same as everywhere else: Godot hands it to
## the host the moment the wire comes up.
const HOST_PEER := 1

## Where the sheets live. Everything in here that loads as a `Contract` is on
## the board; anything else in the folder is ignored rather than complained
## about, so an `.import` file or a stray note costs nothing.
const FOLDER := "res://resources/contracts/"

## What a client is told when he reaches for the pen. A sentence, because the
## only thing done with it is putting it on a screen.
const REFUSAL_NOT_HOST := "Only the crew leader signs the contract."
## And what anybody is told when the job is already under way — the board is
## read-only from the moment the van reaches the house.
const REFUSAL_UNDER_WAY := "The job is under way."
## An id that is on nobody's board. It should not be reachable from the
## clipboard, which only ever offers what it was handed; it is here for a packet
## that arrived from a machine with a different folder on disk.
const REFUSAL_UNKNOWN := "That job is not on the board."
## And what a client is told for reaching at the hunt length. The same rule as
## the pen and worth the same sentence: how long the crew has in the house is the
## leader's call, because it is the leader who signed for the job.
const REFUSAL_NOT_HOST_TIME := "Only the crew leader sets the hunt time."
## What anybody is told for changing it once the van has pulled off. It closes
## with the board, and for a plainer reason than the signature does: the length
## is what the crew shopped and set traps against, and moving it on the doorstep
## would be moving the bet after the cards are down.
const REFUSAL_TIME_UNDER_WAY := "The hunt time is settled."

## Every contract on disk, sorted by difficulty and then by id so that all four
## machines number the pages the same way. Read once on the way up: the folder
## does not change while the game is running.
var contracts: Array[Contract] = []

## Whether the crew is voting on the next job right now — the stretch between
## the van pulling off and the host settling the show of hands, which replaced
## the old clipboard's single signature. Only ever true on the road.
var voting_open := false

## Who voted for what, by Steam ID. Cleared every time a vote opens, and
## written the same way the signature is: the host counts it and broadcasts
## the count, and nothing here ever writes a ballot twice.
var votes: Dictionary[int, String] = {}


func _ready() -> void:
	# A signature can land while the game is paused, the same as a phase change
	# can. `PhaseManager` and `ReadyManager` are set this way for the same
	# reason.
	process_mode = Node.PROCESS_MODE_ALWAYS

	contracts = _scan(FOLDER)
	PhaseManager.phase_changed.connect(_on_phase_changed)


## The van pulling off is what lays the sheets out. **Host only**, and only for a
## van with no job signed to it: the road is reached with a blank board at the
## start of a shift and again after every house (`PhaseManager._clear_job`), so
## this is the one condition, and a crew that somehow arrives already signed — a
## bench, a lobby set up from a command line — drives straight to it instead of
## voting on a decision that is already made.
##
## It is here and not on the screen because the vote is this autoload's state:
## a screen that opened its own vote would be one machine's UI deciding what
## every machine writes down, and a client's van has no business doing that.
func _on_phase_changed(_previous: Phase.Type, phase: Phase.Type) -> void:
	if phase != Phase.Type.TRAVEL:
		return
	if not PhaseManager.is_host() or voting_open or is_signed():
		return
	open_voting()


## How many jobs are on the board.
func count() -> int:
	return contracts.size()


## The contract at a page number, or null past the end of the board. The
## clipboard leafs by index and asks for the sheet it landed on.
func at(index: int) -> Contract:
	if index < 0 or index >= contracts.size():
		return null
	return contracts[index]


## A contract by its id, or null for one nobody has. This is what the sheet on
## the wall and the map table look the signed job up with.
func find(contract_id: String) -> Contract:
	if contract_id.is_empty():
		return null
	for contract in contracts:
		if contract.id == contract_id:
			return contract
	return null


## Which page a contract sits on, or -1 for one that is not on the board. The
## clipboard opens on the signed job rather than on the first one, and this is
## how it finds it.
func index_of(contract_id: String) -> int:
	for index in contracts.size():
		if contracts[index].id == contract_id:
			return index
	return -1


## The job the crew is working, or null before anything is signed. Read off
## `SessionManager`, which holds the one copy of it — nothing here keeps a
## second that could disagree.
func current() -> Contract:
	return find(SessionManager.current_contract)


## Whether anything has been signed at all. The clipboard and the ready boards
## both ask.
func is_signed() -> bool:
	return current() != null


## Whether this machine may sign. It is asked before the pen is even drawn, so a
## client reads "only the leader signs" on the sheet instead of pressing a
## button that was always going to refuse him.
func may_sign() -> bool:
	return PhaseManager.is_host()


## The phases in which a job can still be signed. The menu is where one is
## normally taken; the road is open too, because the sheet on the wall of the van
## is a station the crew can walk up to and the two minutes of the drive are
## exactly when somebody reads the small print and argues about it.
##
## It stops at the doorstep. From the survey on, the house named by the contract
## is what is being loaded and walked around, and a second signature landing then
## would point half the crew at a different one.
const OPEN_PHASES: Array[Phase.Type] = [Phase.Type.LOBBY, Phase.Type.TRAVEL]

## And the phases in which the wager can. **It is the shorter list, on purpose.**
## The signature says which house; the clock says what the crew is betting on it,
## and by the time the van has pulled off that bet has already been spent — the
## shopping was done against it and the traps were bought against it. Moving it
## on the road would be moving the stake after the cards are down, which is what
## `REFUSAL_TIME_UNDER_WAY` is there to say.
##
## The road is on the list all the same, and `is_time_open` is what makes the
## difference: a paid crew comes back to the van rather than to the menu
## (`PhaseManager.next_phase`), so the road is where the *next* job is taken —
## and until it is signed, nothing has been shopped or trapped against, and there
## is no stake on the table to move.
const OPEN_TIME_PHASES: Array[Phase.Type] = [Phase.Type.LOBBY, Phase.Type.TRAVEL]


## Whether the board can still be signed at all. It closes when the van reaches
## the house: the scene is loading by then and a second signature would send half
## the crew somewhere else.
func is_open() -> bool:
	return PhaseManager.current() in OPEN_PHASES


## Whether the hunt can still be booked at a different length. Asked instead of
## `is_open` by everything that touches the clock — see `OPEN_TIME_PHASES` for
## why the two answers are allowed to differ.
##
## On the road it closes with the signature rather than with the phase: an
## unsigned van is a crew still choosing its next job, and the length is half of
## that choice. The moment a job is signed the bet is down and stays down.
func is_time_open() -> bool:
	var phase := PhaseManager.current()
	if phase == Phase.Type.TRAVEL:
		return not is_signed()
	return phase in OPEN_TIME_PHASES


## How long the hunt is booked for. Read off `SessionManager`, which holds the
## one copy — nothing here keeps a second that could disagree.
func hunt_time() -> HuntTime.Type:
	return SessionManager.hunt_time


## Asks the host to book the hunt at a length. The same road the signature takes,
## and for the same reason: nothing is written locally and corrected later, so
## what a man reads on the sheet is always what the host settled on.
func request_hunt_time(value: HuntTime.Type) -> void:
	if PhaseManager.is_host():
		_handle_hunt_time(value, _our_peer_id())
		return
	_request_hunt_time.rpc_id(HOST_PEER, value)


## Books it outright, without asking. **Host only**, for the shift that is set up
## rather than chosen — a bench, or a lobby entered from a command line.
func set_hunt_time(value: HuntTime.Type) -> void:
	if not PhaseManager.is_host():
		push_warning("ContractManager: only the host sets the hunt time.")
		return
	_handle_hunt_time(value, 0)


## Asks the host to sign a job. **This is the only way in from the clipboard** —
## nothing is written locally and corrected later, so what a man sees on the
## wall is always what the host settled on.
##
## Off the wire (a solo run, a bench) an `rpc_id` to peer 1 would be an error in
## the log for an answer that is already at hand, so the request goes straight
## to the host's own handler. Same code down either road, which is what keeps
## solo from being a second set of rules.
func request_sign(contract_id: String) -> void:
	if PhaseManager.is_host():
		_handle_request(contract_id, _our_peer_id())
		return
	_request.rpc_id(HOST_PEER, contract_id)


## Signs a job outright, without asking. **Host only**, and it is for the shift
## that has to be set up rather than chosen — a test bench, or a lobby entered
## from a command line that already named the house.
func sign(contract_id: String) -> void:
	if not PhaseManager.is_host():
		push_warning("ContractManager: only the host signs the contract.")
		return
	_handle_request(contract_id, 0)


## Everything the host knows about the board, for a player who has just walked
## in. `JoinGate` hands it over with the rest of the shift, so that a newcomer
## sees the signed job before he spawns rather than a blank wall that fills in a
## moment later.
func state() -> String:
	return SessionManager.current_contract


## And the length the hunt is booked at, for the same newcomer. Handed over
## beside `state()` rather than folded into it, so that the packet `JoinGate`
## already sends does not change shape for callers that only wanted the job.
func hunt_time_state() -> int:
	return SessionManager.hunt_time


## Takes a newcomer's copy of the board from the host's packet. It does not go
## through `_apply`: this is not a decision arriving, it is the state of one
## already made, and it lands on one machine rather than all of them.
func adopt(contract_id: String) -> void:
	if contract_id.is_empty():
		return
	if find(contract_id) == null:
		push_warning("ContractManager: the host signed %s, which is not on our board."
			% contract_id)
		return
	_settle(contract_id)


## Takes a newcomer's copy of the booked length, the same way `adopt` takes the
## job. A value this build does not know is left alone rather than written: the
## default is a length that certainly works, and a hunt with no duration would be
## a hunt whose clock never starts.
func adopt_hunt_time(value: int) -> void:
	if not HuntTime.is_valid(value):
		push_warning("ContractManager: the host booked hunt length %d, which we do not have."
			% value)
		return
	_settle_hunt_time(value)


## Takes a newcomer's copy of a vote already under way, the same way `adopt`
## takes a signature. Silently ignored when nobody is voting — a newcomer
## arriving between two shifts has no vote to catch up on.
func adopt_votes(state_votes: Dictionary, is_open: bool) -> void:
	voting_open = is_open
	votes.clear()
	for steam_id in state_votes:
		votes[int(steam_id)] = String(state_votes[steam_id])
	_apply_hold()

# --- Voting -------------------------------------------------------------
#
# The crew's replacement for the clipboard's single signature: every man
# picks a card instead of one of them picking for everybody, and the host —
# same as everywhere else in the van — is the one who counts the room and
# says when it is settled.

## Lays the sheets out for a vote. **Host only** — called by the road itself
## (`_on_phase_changed`) rather than by a button, so the sheets are up before
## anybody is out of his seat.
func open_voting() -> void:
	if not PhaseManager.is_host():
		push_warning("ContractManager: only the host opens the vote.")
		return
	_open_voting.rpc()


## Asks the host to count our vote for a job. **This is the only way in from a
## card** — nothing is written locally and corrected later, so a tally on
## screen is always what the host actually counted.
func request_vote(steam_id: int, contract_id: String) -> void:
	if steam_id == 0:
		return
	if PhaseManager.is_host():
		_handle_vote(steam_id, contract_id, _our_peer_id())
		return
	_vote.rpc_id(HOST_PEER, steam_id, contract_id)


## How many votes a job has, for the tally on its card.
func votes_for(contract_id: String) -> int:
	var total := 0
	for picked in votes.values():
		if picked == contract_id:
			total += 1
	return total


## Whether every man in the crew has picked a job. What the host's START button
## reads before it lights up.
func everybody_voted() -> bool:
	if not voting_open or SessionManager.players.is_empty():
		return false
	for steam_id in SessionManager.players:
		if not votes.has(steam_id):
			return false
	return true


## Signs the job the room picked and takes the sheets away. **Host only**, and
## only once the whole crew has picked — the button that reaches for this is
## disabled until then, and this is the belt-and-braces check for a press that
## somehow beat it.
##
## It moves nothing: the van is already on the road by the time the vote is
## drawn, and what the crew gets back is its legs, not a scene change. The house
## is reached the way it always was — the ready boards, or the host's clock.
func settle_vote() -> void:
	if not PhaseManager.is_host():
		push_warning("ContractManager: only the host settles the vote.")
		return
	if not everybody_voted():
		push_warning("ContractManager: the crew has not all voted yet.")
		return
	var winner := _winning_contract()
	if winner.is_empty():
		return
	_handle_request(winner, 0)
	_close_voting.rpc()


## The job with the most votes. Ties fall to whichever comes first on the
## board — the same order every machine already agrees on — so a crew split
## down the middle always lands on the same house rather than four different
## ones.
func _winning_contract() -> String:
	var best_id := ""
	var best_votes := -1
	for contract in contracts:
		var count := votes_for(contract.id)
		if count > best_votes:
			best_votes = count
			best_id = contract.id
	return best_id


## Holds the shift while the sheets are up, and lets it go when they come down.
##
## The hold is `ReadyManager`'s, not a second one of our own: it is the same
## mechanism the old signing board used, and it is what stops the crew — or the
## host's two-minute clock — taking the van to a house nobody has picked yet.
## Set on every machine, because `voting_open` is on every machine, and a board
## whose light disagreed with the host's would be a board that lies about why
## the van is standing still.
func _apply_hold() -> void:
	ReadyManager.blocked = voting_open


func _handle_vote(steam_id: int, contract_id: String, from_peer: int) -> void:
	if not voting_open:
		return
	if find(contract_id) == null:
		return
	if not SessionManager.has_player(steam_id):
		push_warning("ContractManager: a vote arrived for %d, who is not in the crew." % steam_id)
		return
	if not _may_vote_for(from_peer, steam_id):
		push_warning("ContractManager: peer %d tried to vote for %d." % [from_peer, steam_id])
		return
	if votes.get(steam_id, "") == contract_id:
		return
	_apply_vote.rpc(steam_id, contract_id)


## Whether a peer may cast a vote under a Steam ID: his own only. The same
## shape `ColorManager._may_speak_for` and `ReadyManager._may_speak_for` take,
## kept here rather than shared because each of the three checks a different
## room's worth of state.
func _may_vote_for(from_peer: int, steam_id: int) -> bool:
	if from_peer == 0 or not multiplayer.has_multiplayer_peer():
		return true
	var owner_id := LobbyManager.steam_id_of_peer(from_peer)
	return owner_id == 0 or owner_id == steam_id


@rpc("authority", "call_local", "reliable")
func _open_voting() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		return
	votes.clear()
	voting_open = true
	_apply_hold()
	voting_opened.emit()


@rpc("authority", "call_local", "reliable")
func _close_voting() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		return
	voting_open = false
	_apply_hold()
	voting_closed.emit()


## A client's vote, arriving at the host. `any_peer` because anybody may vote;
## what makes it safe is that the host is the only one who acts on it.
@rpc("any_peer", "reliable")
func _vote(steam_id: int, contract_id: String) -> void:
	if not PhaseManager.is_host():
		push_warning("ContractManager: a vote reached a machine that is not the host.")
		return
	_handle_vote(steam_id, contract_id, multiplayer.get_remote_sender_id())


## The tally, run on every machine at once, the host included (`call_local`) —
## a vote counted only on the host's own screen is a card the rest of the crew
## is looking at wrong.
@rpc("authority", "call_local", "reliable")
func _apply_vote(steam_id: int, contract_id: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("ContractManager: a vote from peer %d, which is not the host — ignored."
			% sender)
		return
	votes[steam_id] = contract_id
	vote_changed.emit(steam_id, contract_id)

# --- The wire ---------------------------------------------------------------

## A client asking for a signature, arriving at the host. `any_peer` because
## anybody may ask; what makes it safe is that the host is the only one who acts
## on it, and that what he does with it is checked below rather than taken on
## trust.
@rpc("any_peer", "reliable")
func _request(contract_id: String) -> void:
	if not PhaseManager.is_host():
		push_warning("ContractManager: a signing request reached a machine that is not the host.")
		return
	_handle_request(contract_id, multiplayer.get_remote_sender_id())


## The host's decision, in one place so that it reads the same whether the
## request came off the wire or out of a solo game.
##
## Three ways it is turned down, and each of them is a way the board could
## otherwise be made to lie:
##
## - **Who asked.** Anybody but the host is refused out loud. This is the rule
##   the card is about, and it is enforced here rather than on the clipboard —
##   a client with a tampered clipboard still cannot sign anything.
## - **When.** The board closes when the van reaches the house; a signature
##   landing during the survey would point the phase machine at a second house
##   while the crew is standing in the first.
## - **What.** An id nobody has is refused rather than written, so that
##   `current()` can never answer null for a contract everybody believes is
##   signed.
func _handle_request(contract_id: String, from_peer: int) -> void:
	if not _may_sign_from(from_peer):
		_refuse_to(from_peer, REFUSAL_NOT_HOST)
		return
	if not is_open():
		_refuse_to(from_peer, REFUSAL_UNDER_WAY)
		return
	if find(contract_id) == null:
		_refuse_to(from_peer, REFUSAL_UNKNOWN)
		return
	if SessionManager.current_contract == contract_id:
		return
	_apply.rpc(contract_id)


## Whether a peer is the host. Zero is the host calling in from his own game
## with no wire at all — a machine with nobody to lie to — and peer 1 is the
## host proper, which is what his own request arrives as once there is a wire.
func _may_sign_from(from_peer: int) -> bool:
	if from_peer == 0 or not multiplayer.has_multiplayer_peer():
		return true
	return from_peer == HOST_PEER


## The host's decision about the hunt length, in one place, the same shape
## `_handle_request` has. Two ways it is turned down and they are the two rules
## the wager has: only the leader books it, and only while the van is parked.
##
## An unknown value is dropped without a sentence rather than refused out loud:
## nothing on the clipboard can produce one, so the only way here is a packet
## from a machine built against a different `HuntTime`, and there is no player to
## explain that to.
func _handle_hunt_time(value: HuntTime.Type, from_peer: int) -> void:
	if not _may_sign_from(from_peer):
		_refuse_to(from_peer, REFUSAL_NOT_HOST_TIME)
		return
	if not is_time_open():
		_refuse_to(from_peer, REFUSAL_TIME_UNDER_WAY)
		return
	if not HuntTime.is_valid(value):
		push_warning("ContractManager: peer %d asked for hunt length %d, which does not exist."
			% [from_peer, value])
		return
	if SessionManager.hunt_time == value:
		return
	_apply_hunt_time.rpc(value)


## A client asking for a length, arriving at the host. `any_peer` for the same
## reason `_request` is: anybody may ask, and the host is the only one who acts.
@rpc("any_peer", "reliable")
func _request_hunt_time(value: HuntTime.Type) -> void:
	if not PhaseManager.is_host():
		push_warning("ContractManager: a hunt-time request reached a machine that is not the host.")
		return
	_handle_hunt_time(value, multiplayer.get_remote_sender_id())


## The booking, run on every machine at once, the host included (`call_local`) —
## a host counting ten minutes while the crew counts two is the same evening-long
## bug the signature guards against, with money on top of it.
@rpc("authority", "call_local", "reliable")
func _apply_hunt_time(value: HuntTime.Type) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("ContractManager: a hunt time from peer %d, which is not the host — ignored."
			% sender)
		return
	if not HuntTime.is_valid(value):
		push_warning("ContractManager: booked hunt length %d, which we do not have." % value)
		return
	_settle_hunt_time(value)


## The signature, run on every machine at once, the host included
## (`call_local`) — a host who signed a job the crew never heard about is
## exactly the bug that costs an evening.
##
## `authority` means Godot itself drops a packet from anybody but peer 1; the
## check below is belt and braces for one that somehow got through, and it is
## the audit the robustness card asks for.
@rpc("authority", "call_local", "reliable")
func _apply(contract_id: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("ContractManager: a signature from peer %d, which is not the host — ignored."
			% sender)
		return
	if find(contract_id) == null:
		push_warning("ContractManager: signed %s, which is not on our board." % contract_id)
		return
	_settle(contract_id)


## A refusal, landing only on the man who asked.
@rpc("authority", "reliable")
func _refuse(reason: String) -> void:
	if multiplayer.get_remote_sender_id() != HOST_PEER:
		return
	request_refused.emit(reason)


## Turns a peer down. The host refusing himself never touches the wire — he is
## the one holding the answer — and off the wire there is nobody to send to
## anyway.
func _refuse_to(peer_id: int, reason: String) -> void:
	if peer_id == 0 or peer_id == _our_peer_id() or not multiplayer.has_multiplayer_peer():
		request_refused.emit(reason)
		return
	_refuse.rpc_id(peer_id, reason)

# --- What a signature actually does -----------------------------------------

## Writes the signed job down and does the two things that follow from it. It is
## reached from the broadcast and from a newcomer's state packet alike, so that
## a man who joined late ends up in exactly the state the others are in.
##
## The house is pointed at here rather than when the van leaves, on purpose: by
## the time the phase changes the scene is already being asked for, and a path
## set at that moment is a race. Signed in the lobby, loaded two phases later.
func _settle(contract_id: String) -> void:
	var contract := find(contract_id)
	if contract == null:
		return
	SessionManager.set_contract(contract_id)
	if not contract.house_scene.is_empty():
		# Survey and hunt both, and in one call — pointing only one of them at
		# the house is what turns the change between the two into a reload, and
		# a reload is a minute of trap-placing in the bin.
		PhaseManager.set_house(contract.house_scene)
	contract_signed.emit(contract_id)


## Writes the booked length down and says so. Reached from the broadcast and
## from a newcomer's state packet alike, so that a man who joined late is
## counting the same clock as everybody else.
##
## Nothing is done to the phase machine here, on purpose: it asks
## `SessionManager` for the hunt's length at the moment it starts the clock
## (`PhaseManager.duration_of`), so a booking changed twice in the van needs no
## undoing — the last one written is the one the house runs on.
func _settle_hunt_time(value: HuntTime.Type) -> void:
	SessionManager.set_hunt_time(value)
	hunt_time_set.emit(value)

# --- Odds and ends ----------------------------------------------------------

## Every contract in a folder, in the order all four machines will agree on.
##
## Sorted by difficulty first, so the board reads easiest-to-worst the way the
## card asks, and by id after it, so that two jobs of the same difficulty do not
## swap places between one machine and the next — a directory listing does not
## promise an order, and a board numbered differently on two machines would mean
## a page number that means two different jobs.
func _scan(path: String) -> Array[Contract]:
	var found: Array[Contract] = []
	var names := _files_in(path)
	if names.is_empty():
		push_warning("ContractManager: there is nothing on the board at %s." % path)
		return found
	for file_name in names:
		var contract := ResourceLoader.load(path + file_name) as Contract
		if contract == null:
			continue
		if contract.id.is_empty():
			push_warning("ContractManager: %s has no id and cannot be signed." % file_name)
			continue
		found.append(contract)
	found.sort_custom(func(a: Contract, b: Contract) -> bool:
		if a.difficulty != b.difficulty:
			return a.difficulty < b.difficulty
		return a.id < b.id)
	return found


## The `.tres` files in a folder, by name.
##
## In an exported game the folder is inside the pack and `DirAccess` hands back
## the imported names, so `.remap` is trimmed off rather than skipped — a
## contract that only exists in an export is still a contract. Anything that is
## not a resource after that is left alone.
func _files_in(path: String) -> PackedStringArray:
	var names := PackedStringArray()
	var dir := DirAccess.open(path)
	if dir == null:
		return names
	for file_name in dir.get_files():
		var trimmed := file_name.trim_suffix(".remap")
		if trimmed.ends_with(".tres"):
			names.append(trimmed)
	return names


## Our own peer id, or zero with no wire up. Used to tell the host's own request
## apart from a client's without asking `is_host()` a second time.
func _our_peer_id() -> int:
	if not multiplayer.has_multiplayer_peer():
		return 0
	return multiplayer.get_unique_id()
