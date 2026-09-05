extends Node
## The one purse, and the two moments it moves: the money is taken out of the
## bank on the doorstep and put back in on the pay slip.
##
## **There is one balance, and the player sees the same number everywhere.** The
## shop in the van spends `SessionManager.money`, which is per Steam ID and
## written only by the host; the house spends and fills `Wallet`, which is this
## machine's own and is what the HUD and the traps talk to. Those are two
## different purses with two different owners, and before this node existed they
## never spoke: a crew earned all night into the wallet and arrived back at the
## shelf with the hundred dollars it started the evening on.
##
## This is the bridge, and it is deliberately only two calls wide:
##
## - **`withdraw`**, on the way into the house (`TRAVEL -> SURVEY`). The bank
##   balance is copied into `Wallet`, so the number the HUD opens on is the
##   number the shop closed on — and so a trap can be salvaged for its fee in the
##   first minute of the survey, before a single rat has paid for anything.
## - **`settle`**, on the pay slip (`-> RESULT`). What is left in the wallet,
##   plus the contract's bonus, goes back to the bank. From there `_clear_job`
##   drives the crew to the van with it (`PhaseManager`), and the shelf spends
##   the same money the house earned.
##
## **The balance is written absolute, not added.** The wallet was seeded from the
## bank, so what is in it at the end already *is* the new bank balance. That is
## worth more than it looks: an addition that ran twice would pay a shift twice,
## and a phase entered again — a bench, a packet that lands late — is exactly the
## kind of thing that happens. Writing the whole number is idempotent and needs
## no latch to protect it.
##
## **The host writes, everybody asks.** The same round trip the shelf takes
## (`ShopManager.request_buy` -> `_request` -> `_handle_request` -> `_apply`),
## and here for the same reason: a client that never writes its own balance
## cannot write itself a fortune. What it *can* do is report one, and that is not
## guarded — the same trust `Wallet._receive` already places in the peers being
## the players. A man who wanted to cheat here has been able to do worse since
## the first rat was paid for.

## Somebody's balance was written. `steam_id` is whose. Nothing draws off this
## today — the shelf redraws on `SessionManager.player_changed` like everything
## else — but the deposit is the one money event that has no other announcement.
signal balance_settled(steam_id: int, amount: int)

## The peer that decides. Peer 1, the same as everywhere else: Godot hands it to
## the host the moment the wire comes up.
const HOST_PEER := 1


func _ready() -> void:
	# A deposit can land while the game is paused — a man reading the pause menu
	# over a finished hunt is still owed his money. Every session autoload is set
	# this way.
	process_mode = Node.PROCESS_MODE_ALWAYS

	PhaseManager.phase_changed.connect(_on_phase_changed)
	# A newcomer admitted straight into a house missed the phase change that would
	# have paid him out of the bank, and would hunt with an empty wallet and then
	# hand that emptiness back at the slip. `JoinGate` announces the phase he woke
	# up in, which is the only cue there is.
	JoinGate.joined.connect(_on_joined)

# --- The two moments --------------------------------------------------------

## The bank balance into the wallet. Local and nothing else: each machine takes
## its own man's entry, and that entry is already replicated — asking the host for
## a number he has already sent would be a round trip for nothing.
func withdraw() -> void:
	var steam_id := _our_steam_id()
	if steam_id == 0:
		return
	Wallet.set_balance(SessionManager.money(steam_id))


## What the shift closes on: what is left in the wallet, plus what the client pays
## for a house with nothing in the walls.
##
## The bonus is added here rather than paid into `Wallet` as it is earned, because
## it is not earned — it is a term of the contract, settled by whether the house
## came out clear (`ShiftReport.bonus`), and there is no moment during the hunt at
## which it is true yet.
func closing_balance() -> int:
	return maxi(0, Wallet.money + ShiftReport.bonus())


## The wallet back into the bank. The wallet is written first and with the same
## number, so that the pay slip and the HUD behind it are already showing what the
## shelf in the van is about to show — the answer does not wait on the wire.
func settle() -> void:
	var steam_id := _our_steam_id()
	if steam_id == 0:
		return
	var amount := closing_balance()
	Wallet.set_balance(amount)
	request_deposit(steam_id, amount)


## Asks the host to write a balance. **This is the only way in** — nothing is
## written locally and corrected later.
##
## Off the wire (a solo game, a bench) an `rpc_id` to peer 1 would be an error in
## the log for an answer that is already here, so the request goes straight to the
## host's own handler. The same code down either road, which is what keeps solo
## from being a second set of rules.
func request_deposit(steam_id: int, amount: int) -> void:
	if steam_id == 0:
		return
	if PhaseManager.is_host():
		_handle_request(steam_id, amount, _our_peer_id())
		return
	_request.rpc_id(HOST_PEER, steam_id, amount)

# --- The wire ---------------------------------------------------------------

## A player's closing balance, arriving at the host. `any_peer` because anybody
## may report his own; what makes it safe is that the host is the only one who
## writes, and that what he writes is checked below rather than taken on trust.
@rpc("any_peer", "reliable")
func _request(steam_id: int, amount: int) -> void:
	if not PhaseManager.is_host():
		push_warning("Bank: a deposit reached a machine that is not the host.")
		return
	_handle_request(steam_id, amount, multiplayer.get_remote_sender_id())


## The host's decision, in one place so that it reads the same whether the request
## came off the wire or out of a solo game. Two things are checked, and each is a
## way the bank could otherwise be made to lie:
##
## - **The crew.** A Steam ID nobody has been introduced to is not a player, and
##   writing a balance for him would leave money in a pocket no body is wearing.
## - **Whose balance it is.** A peer may only report his own. Without this, any
##   client could empty the whole van's pockets.
##
## The amount itself is floored at zero and otherwise believed, for the reason the
## header gives.
func _handle_request(steam_id: int, amount: int, from_peer: int) -> void:
	if not SessionManager.has_player(steam_id):
		push_warning("Bank: a deposit for %d, who is not in the crew." % steam_id)
		return
	if not _may_speak_for(from_peer, steam_id):
		push_warning("Bank: peer %d tried to write %d's balance." % [from_peer, steam_id])
		return
	if _on_the_wire():
		_apply.rpc(steam_id, maxi(0, amount))
	else:
		_apply(steam_id, maxi(0, amount))


## The balance itself, written on every machine at once, the host included
## (`call_local`). A host who banked his own shift while the crew's slips landed
## nowhere is the same evening-long bug every other manager here guards against.
@rpc("authority", "call_local", "reliable")
func _apply(steam_id: int, amount: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("Bank: a balance from peer %d, which is not the host — ignored." % sender)
		return
	if not SessionManager.has_player(steam_id):
		return
	SessionManager.set_money(steam_id, amount)
	balance_settled.emit(steam_id, amount)

# --- What wakes it up -------------------------------------------------------

## The doorstep and the pay slip, and nothing in between.
##
## The withdrawal is pinned to `TRAVEL -> SURVEY` rather than to "entering the
## survey", because survey and hunt share a house and a shift can be put back into
## the survey by a bench: a withdrawal on the way in from anywhere would overwrite
## a wallet that has already been hunted with.
func _on_phase_changed(previous: Phase.Type, current: Phase.Type) -> void:
	if current == Phase.Type.SURVEY and previous == Phase.Type.TRAVEL:
		withdraw()
		return
	if current == Phase.Type.RESULT:
		settle()


## A newcomer, woken up in a house the crew is already standing in. He takes his
## money out of the bank the same way everybody else did on the doorstep — the
## phase change that would have done it for him happened before he was admitted.
func _on_joined(phase: Phase.Type) -> void:
	if phase == Phase.Type.SURVEY or phase == Phase.Type.HUNT:
		withdraw()

# --- Odds and ends ----------------------------------------------------------

## Whose money this machine holds. `LobbyManager.our_crew_id` is what already
## answers this everywhere it is asked, falling back to the only man in a crew of
## one — which is what makes a solo game and a bench work without Steam running.
func _our_steam_id() -> int:
	return LobbyManager.our_crew_id()


## Whether there is anybody to say it to. An `rpc` with no wire under it is an
## error in the log for a packet that had nowhere to go: solo play never has a
## wire. The same question `PhaseManager._on_the_wire` asks.
func _on_the_wire() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


## Whether a peer is allowed to report a Steam ID's balance: his own only. The
## host calling in from his own game arrives as his own peer id — or as zero with
## no wire at all, which is a machine with nobody to lie to. The same shape as
## `ShopManager._may_speak_for`, and for the same reason.
func _may_speak_for(from_peer: int, steam_id: int) -> bool:
	if from_peer == 0 or not multiplayer.has_multiplayer_peer():
		return true
	if from_peer == _our_peer_id():
		# Ourselves, and asked of the same helper the request was built with
		# (`_our_steam_id`). The two have to be one question or they can answer
		# differently: `steam_id_of_peer` reads the Steam account behind the peer,
		# while `our_crew_id` falls back to the only man in a one-man crew — and a
		# bench, or a game whose introduction has not landed, is exactly where
		# those two part company. Turning our own deposit away over that would
		# cost a shift's pay for a disagreement about a name nobody else uses.
		return steam_id == _our_steam_id()
	var owner_id := LobbyManager.steam_id_of_peer(from_peer)
	# A peer whose introduction has not landed yet has no Steam ID to check
	# against. Refusing him would lose him a shift's pay over a packet that is
	# already on its way, which is a worse bug than the one being guarded against.
	return owner_id == 0 or owner_id == steam_id


## Our own peer id, or zero with no wire to have one on — asking Godot for an id
## then is an error in the log for an answer nobody needed. The same shape as
## `ShopManager._our_peer_id`.
func _our_peer_id() -> int:
	if not multiplayer.has_multiplayer_peer():
		return 0
	var peer := multiplayer.multiplayer_peer
	if peer is OfflineMultiplayerPeer:
		return 0
	return multiplayer.get_unique_id()
