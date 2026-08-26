extends Node
## The shelf in the back of the van, and the one rule about it: nobody spends
## money he does not have, and nobody but the host decides whether he had it.
##
## **The host holds the till.** A player at the shelf does not buy anything; he
## *asks* to (`request_buy`), the host looks at what is in that man's pocket, and
## either the purchase is written on every machine at once (`_apply`) or the man
## who asked hears a buzzer and nobody else hears anything (`_refuse`). It is the
## same round trip the colour panel and the clipboard take, and it is here for a
## sharper reason than either: money is the one thing in the van a tampered
## client would actually want to lie about, and a client that never writes its
## own balance cannot.
##
## **Every purse is its own.** The card asks for money per player, and that is
## what `SessionManager` already holds — one `money` and one `inventory` per
## Steam ID, keyed by the id that survives the scene change. Two men buying in
## the same second are two entries being written, and neither of them can take
## the other's money because the host debits the asker and nobody else.
##
## **The catalogue is read off disk, not registered.** Every machine scans
## `resources/store/` on the way up and sorts what it finds, so all of them have
## the same shelf in the same order and an item can travel as its `id` alone.
## Dropping a new `.tres` in that folder puts it on the shelf on every machine at
## once — the same trick the contract board plays, and true for the same reason:
## nothing anywhere holds a second list that would have to be kept in step.
##
## **The shelf is only open on the road.** Buying is a `TRAVEL` thing: the lobby
## has not left yet and the house has no van in it, and the card says the shelf
## does not even exist in the survey and the hunt. That is checked here rather
## than only on the station, so that a packet arriving late — a man who pressed
## `E` as the van pulled up — is turned down by the host instead of quietly
## crediting a box nobody can carry.
##
## **What it stores is nothing.** The purse and the bag live on `SessionManager`
## like everything else that outlives the van, and the box of traps the weapons
## actually spend from lives on `Stock`. This only decides what goes into them.

## Somebody bought something — after it was written, so a listener that reads
## the purse off `SessionManager` sees the new one. `item_id` is what was bought
## and `steam_id` is who bought it.
signal item_bought(steam_id: int, item_id: String)

## We asked for something and were turned down. Emitted only on the machine that
## asked, which is what the shelf plays its buzzer and flashes its price tag off.
## `reason` is a sentence.
signal request_refused(reason: String)

## The peer that decides. Peer 1, the same as everywhere else: Godot hands it to
## the host the moment the wire comes up, and it is a surer answer than a Steam
## ID that may not have been introduced yet.
const HOST_PEER := 1

## Where the shelf's stock list lives. Everything in here that loads as a
## `StoreItem` is for sale; anything else in the folder is ignored rather than
## complained about, so an `.import` file or a stray note costs nothing.
const FOLDER := "res://resources/store/"

## The phase the shelf is open in. One phase, and it is the whole of the card's
## rule 7: the lobby has not left and the house has no shelf in it.
const OPEN_PHASE: Phase.Type = Phase.Type.TRAVEL

## What a man is told when his pocket is too light. A sentence, because the only
## thing done with it is putting it on a screen and buzzing beside it.
const REFUSAL_POOR := "Not enough money for that."
## And what he is told when the van is not on the road.
const REFUSAL_SHUT := "The store is shut."
## An id that is on nobody's shelf. It should not be reachable from the station,
## which only ever offers what it was handed; it is here for a packet that
## arrived from a machine with a different folder on disk.
const REFUSAL_UNKNOWN := "That is not in the store."

## Everything on the shelf, sorted by price and then by id so that all four
## machines number the shelf the same way. Read once on the way up: the folder
## does not change while the game is running.
var _catalogue: Array[StoreItem] = []


func _ready() -> void:
	# A purchase can land while the game is paused — a pause menu is not a
	# hiding place from the wire — so the packet still has to be read. Same as
	# `PhaseManager`, `ReadyManager` and `ColorManager`.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_catalogue = _scan(FOLDER)

# --- What everybody can ask -------------------------------------------------

## How many things are on the shelf.
func count() -> int:
	return _catalogue.size()


## Everything on the shelf, in the order every machine has it. A copy, so that a
## station sorting or filtering its own view cannot reorder the shelf underneath
## the machine next to it.
func catalogue() -> Array[StoreItem]:
	return _catalogue.duplicate()


## The item at a place on the shelf, or null for an index off the end of it.
func at(index: int) -> StoreItem:
	if index < 0 or index >= _catalogue.size():
		return null
	return _catalogue[index]


## An item by its id, or null for one that is not on the shelf. What a packet off
## the wire is turned back into a thing with a price.
func find(item_id: String) -> StoreItem:
	if item_id.is_empty():
		return null
	for item in _catalogue:
		if item.id == item_id:
			return item
	return null


## Whether the van is somewhere a man may buy things. The station draws itself
## off this — a shelf in the wrong phase is shuttered rather than a shelf that
## takes money and hands back nothing.
func is_open() -> bool:
	return PhaseManager.current() == OPEN_PHASE


## What a player has in his pocket. A thin way through to `SessionManager`, so a
## station has one autoload to talk to rather than two.
func money(steam_id: int) -> int:
	return SessionManager.money(steam_id)


## Whether a player could pay for something right now. It is the *price* only —
## whether the shelf is open is a separate question with a separate refusal, so
## that a man on the road with an empty pocket and a man in the house with a full
## one are told two different things.
func can_afford(steam_id: int, item: StoreItem) -> bool:
	return item != null and SessionManager.money(steam_id) >= item.price

# --- Asking to buy ----------------------------------------------------------

## Asks the host for one of something. **This is the only way in from a
## station** — it never writes anything itself, and what comes back is `_apply`
## on every machine at once, our own included.
##
## Off the wire (a solo game, a bench) an `rpc_id` to peer 1 would be an error in
## the log for an answer that is already here, so the request is handed straight
## to the host's own handler. It is the same code down either road, which is what
## keeps solo from being a second set of rules.
func request_buy(steam_id: int, item_id: String) -> void:
	if steam_id == 0 or item_id.is_empty():
		return
	if PhaseManager.is_host():
		_handle_request(steam_id, item_id, _our_peer_id())
		return
	_request.rpc_id(HOST_PEER, steam_id, item_id)

# --- The wire ---------------------------------------------------------------

## A player's request, arriving at the host. `any_peer` because anybody may ask;
## what makes it safe is that the host is the only one who acts on it, and that
## what he does with it is checked below rather than taken on trust.
@rpc("any_peer", "reliable")
func _request(steam_id: int, item_id: String) -> void:
	if not PhaseManager.is_host():
		push_warning("ShopManager: a purchase reached a machine that is not the host.")
		return
	_handle_request(steam_id, item_id, multiplayer.get_remote_sender_id())


## The host's decision, in one place so that it is the same whether the request
## came off the wire or out of a solo game.
##
## Five things are checked, and each of them is a way the till could otherwise be
## made to lie:
##
## - **The shelf exists.** An id that is on no shelf is a client asking for
##   something nobody is selling.
## - **The crew.** A Steam ID nobody has been introduced to is not a player, and
##   filling his bag would credit a box no body is carrying.
## - **Whose money it is.** A peer may only spend his own. Without this, any
##   client could empty the whole van's pockets.
## - **The phase.** The shelf is shut everywhere but the road.
## - **The price.** The one rule the till exists for.
func _handle_request(steam_id: int, item_id: String, from_peer: int) -> void:
	var item := find(item_id)
	if item == null:
		push_warning("ShopManager: asked for '%s', which is not on the shelf." % item_id)
		_refuse_to(from_peer, REFUSAL_UNKNOWN)
		return
	if not SessionManager.has_player(steam_id):
		push_warning("ShopManager: purchase asked for %d, who is not in the crew." % steam_id)
		return
	if not _may_speak_for(from_peer, steam_id):
		push_warning("ShopManager: peer %d tried to spend %d's money." % [from_peer, steam_id])
		return
	if not is_open():
		_refuse_to(from_peer, REFUSAL_SHUT)
		return
	if not can_afford(steam_id, item):
		_refuse_to(from_peer, REFUSAL_POOR)
		return
	_apply.rpc(steam_id, item_id)


## Whether a peer is allowed to spend a Steam ID's money: his own only. The host
## calling in from his own game arrives as his own peer id — or as zero with no
## wire at all, which is a machine with nobody to lie to.
func _may_speak_for(from_peer: int, steam_id: int) -> bool:
	if from_peer == 0 or not multiplayer.has_multiplayer_peer():
		return true
	var owner_id := LobbyManager.steam_id_of_peer(from_peer)
	# A peer whose introduction has not landed yet has no Steam ID to check
	# against. Refusing him would mean a shelf that does nothing for the first
	# second of a lobby, which is a worse bug than the one being guarded
	# against — and the introduction is already on its way.
	return owner_id == 0 or owner_id == steam_id


## The purchase itself, run on every machine at once, the host included
## (`call_local`). The money is debited here and nowhere else — a station reacts
## to this, it does not write ahead of it.
##
## **The order matters.** The purse is debited and the bag filled before the box
## on the belt is credited, because crediting the box is what puts the weapon in
## the player's hand on the spot (`Inventory._on_stock_changed`), and a weapon
## that arrives before the money has left is a weapon held over a purse that
## still says it can afford another one.
@rpc("authority", "call_local", "reliable")
func _apply(steam_id: int, item_id: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("ShopManager: purchase from peer %d, which is not the host — ignored."
			% sender)
		return
	var item := find(item_id)
	if item == null or not SessionManager.has_player(steam_id):
		return

	SessionManager.set_money(steam_id, SessionManager.money(steam_id) - item.price)
	SessionManager.add_item(steam_id, item_id)

	# The box on the belt is this machine's own, and only this machine's man
	# fills it: `Stock` is a single-player autoload that the weapons in *our*
	# player's hands spend from, and crediting it for somebody else's purchase
	# would hand us the traps he paid for. Everybody else's purchase is written
	# into his `SessionManager` bag above, which is what his own machine reads.
	if is_ours(steam_id):
		Stock.add(item.id, item.amount)

	item_bought.emit(steam_id, item_id)


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

# --- Reading the folder -----------------------------------------------------

## Everything in a folder that loads as a `StoreItem`, sorted so that every
## machine has the shelf in the same order. Price first and id second: the shelf
## reads cheapest to dearest, which is the order a man shops in, and the id
## breaks the tie so that two things at the same price never swap places between
## one machine and the next.
##
## An id that appears twice is said out loud rather than quietly kept: the id is
## what travels on the wire, and two files answering to one string is a purchase
## that credits whichever of them was found first.
func _scan(path: String) -> Array[StoreItem]:
	var found: Array[StoreItem] = []
	var seen: Array[String] = []
	var names := _files_in(path)
	if names.is_empty():
		push_warning("ShopManager: there is nothing on the shelf at %s." % path)
		return found
	for file_name in names:
		var item := ResourceLoader.load(path + file_name) as StoreItem
		if item == null:
			continue
		if item.id.is_empty():
			push_warning("ShopManager: %s has no id and is not for sale." % file_name)
			continue
		if seen.has(item.id):
			push_warning("ShopManager: '%s' is on the shelf twice." % item.id)
			continue
		seen.append(item.id)
		found.append(item)
	found.sort_custom(func(a: StoreItem, b: StoreItem) -> bool:
		if a.price != b.price:
			return a.price < b.price
		return a.id < b.id)
	return found


## The `.tres` files in a folder, by name.
##
## In an exported game the folder is inside the pack and `DirAccess` hands back
## the imported names, so `.remap` is trimmed off rather than skipped — an item
## that only exists in an export is still for sale. Anything that is not a
## resource after that is left alone. The same shape as
## `ContractManager._files_in`, and for the same reason.
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

# --- Odds and ends ----------------------------------------------------------

## Whether a purchase is one this machine's own man made, and so whether the box
## on our belt should be credited for it.
##
## It is asked this way round — "is this ours?" rather than "who are we?" —
## because the two are not the same question when Steam cannot answer. A machine
## whose `get_steam_id` is not in the crew has no man in it: that is a bench, or
## a game started before the introduction landed, and the honest answer for it is
## the *only* member of a one-man crew and nobody at all in a crew of several.
## Guessing a name there is what would hand one player another player's traps.
##
## On the wire, where it matters, `get_steam_id` is in the crew and this is the
## plain identity it looks like.
func is_ours(steam_id: int) -> bool:
	if steam_id == 0:
		return false
	var ours := LobbyManager.our_steam_id()
	if ours != 0 and SessionManager.has_player(ours):
		return steam_id == ours
	# No man of our own that the crew has heard of. A crew of one is a solo game
	# or a bench, and that one man is necessarily the one at the shelf.
	var crew := SessionManager.players.keys()
	return crew.size() == 1 and crew[0] == steam_id


## Our own id on the wire, or zero when there is no wire to have one on — asking
## Godot for an id then is an error in the log for an answer nobody needed. The
## same shape as `ColorManager._our_peer_id`, and for the same reason.
func _our_peer_id() -> int:
	if not multiplayer.has_multiplayer_peer():
		return 0
	var peer := multiplayer.multiplayer_peer
	if peer is OfflineMultiplayerPeer:
		return 0
	return multiplayer.get_unique_id()
