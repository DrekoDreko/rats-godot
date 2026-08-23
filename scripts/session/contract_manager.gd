extends Node
## The board of jobs and the one signature that settles which of them is worked.
##
## Everybody may read the board and everybody may leaf through it — a crew that
## cannot see what it is about to walk into is a crew that cannot argue about
## it. **Only the host signs.** That is the whole of the rule this file exists
## to hold, and it is held the way every other decision in the van is held: a
## client asks, the host decides, and the host's answer is what every machine
## writes down (`request_sign` -> `_handle_request` -> `_apply`).
##
## Leafing is deliberately *not* on the wire. Which sheet a man happens to be
## looking at is his own business and nobody else's — four crew reading four
## different pages at once is the point of a clipboard, and replicating the page
## number would mean the host's thumb dragging everybody else's eyes along with
## it. What is replicated is the signature and nothing but.
##
## **The catalogue is read off disk, not registered.** Every machine scans
## `resources/contracts/` on the way up and sorts what it finds, so all of them
## have the same list in the same order and a contract can travel as its `id`
## alone. Dropping a new `.tres` in that folder puts it on the board on every
## machine at once, which is only true because nothing anywhere holds a second
## list that would have to be kept in step.
##
## **An unsigned board holds the van.** `ReadyManager.blocked` is raised while
## there is no contract, so the crew can go green but the van does not leave
## with nobody knowing where it is going. It is put down again the moment the
## host signs — and if the crew was already all ready, that is what takes them
## down the road (`ReadyManager.blocked` runs the check on its way down).

## The host signed something. `contract_id` is empty when the board was cleared,
## which is what the start of a new shift looks like.
signal contract_signed(contract_id: String)

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
## read-only from the moment the van pulls off.
const REFUSAL_UNDER_WAY := "The job is already signed for."
## An id that is on nobody's board. It should not be reachable from the
## clipboard, which only ever offers what it was handed; it is here for a packet
## that arrived from a machine with a different folder on disk.
const REFUSAL_UNKNOWN := "That job is not on the board."

## Every contract on disk, sorted by difficulty and then by id so that all four
## machines number the pages the same way. Read once on the way up: the folder
## does not change while the game is running.
var contracts: Array[Contract] = []


func _ready() -> void:
	# A signature can land while the game is paused, the same as a phase change
	# can. `PhaseManager` and `ReadyManager` are set this way for the same
	# reason.
	process_mode = Node.PROCESS_MODE_ALWAYS

	contracts = _scan(FOLDER)

	# The van does not leave until something is signed. Raised here rather than
	# by the clipboard, because the rule belongs to the contract and not to the
	# furniture: a van with no clipboard in it should still not leave for
	# nowhere.
	_update_block()


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


## Whether the board can still be changed at all. It is settled once the van
## pulls off: the house is loading by then and a second signature would send
## half the crew to a different one.
func is_open() -> bool:
	return PhaseManager.current() == Phase.Type.LOBBY


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
## - **When.** The board closes when the van pulls off; a signature landing
##   during the survey would point the phase machine at a second house while the
##   crew is standing in the first.
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
	_update_block()
	contract_signed.emit(contract_id)


## Holds the van shut while the board is blank, and lets it go when it is not.
## The check that follows runs on `ReadyManager` rather than here — putting
## `blocked` down with the crew already green is what takes them down the road,
## and that is its own business.
func _update_block() -> void:
	ReadyManager.blocked = not is_signed()

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
