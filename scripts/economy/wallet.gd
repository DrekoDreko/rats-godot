extends Node
## The crew wallet inside a house, plus this player's personal catch tally.
##
## It is the project's only autoload, and that is on purpose: money is the one
## thing in the game that has to survive a scene change — the map starts over,
## what was earned on it does not. Everything else is handled by signals and
## groups.
##
## The host credits every rat when its hunt ends (`rat.gd::_pay_reward`) and
## broadcasts the fixed reward selected by `HuntTime`. Every machine mirrors the
## same total; only the killer records the catch for the scoreboard.

## The total changed. `gain` is what just came in.
signal money_changed(total: int, gain: int)
## An animal was closed out, with everything known about it. It feeds the
## on-screen notice ("+$10, strangulation") and the end-of-shift summary.
signal catch_recorded(species: RatSpecies, death_type: Death.Type, value: int)

var money := 0
var catches := 0

# In game the money shows up on the HUD (`hud_money.gd`). This terminal notice
# stays behind as a debug switch, useful in the headless test benches, where
# there is no screen to look at.
const LOG_TO_TERMINAL := false
const HOST_PEER := 1

## A rat was delivered by somebody, who may well be sitting at another machine.
##
## Every rat in the hunt is thought for by the host — that is the whole of the
## replication model (see `rat.gd`) — so every death is decided on the host, and
## for a long while every death was also *paid for* there. That was wrong in the
## plainest way: a guest could strangle rats all shift and watch the host's
## wallet fill up while his own stayed empty.
##
## The reward lands in the shared purse on every machine. `peer_id` only decides
## which machine increments its personal catch statistic.
func credit(peer_id: int, species: RatSpecies, death_type: Death.Type, size := 1.0) -> int:
	var api := multiplayer
	var on_the_wire := api != null and api.multiplayer_peer != null \
			and not api.multiplayer_peer is OfflineMultiplayerPeer
	if not on_the_wire:
		return collect(species, death_type, size)
	# Somebody else's. The species crosses by its resource path rather than as an
	# object — a `Resource` handed to an RPC would be re-created wholesale on the
	# far side, and what the far side wants is the very `.tres` it already has
	# loaded (`resources/species/`).
	if not api.is_server() or species == null:
		return 0
	var value := _rat_value()
	_receive.rpc(species.resource_path, death_type, value, peer_id)
	return value

## A host-approved reward, mirrored into every crew wallet. The exact value
## crosses the wire once so every machine applies the same integer.
@rpc("authority", "call_local", "reliable")
func _receive(
		species_path: String,
		death_type: Death.Type,
		value: int,
		credited_peer: int
) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	var species := load(species_path) as RatSpecies
	if species == null:
		push_warning("Wallet: paid for a species this machine cannot load: %s" % species_path)
		return
	_collect(species, death_type, value, credited_peer == multiplayer.get_unique_id())

## A rat was delivered. Returns how much it paid.
##
## Local/single-player form of a delivered rat.
func collect(species: RatSpecies, death_type: Death.Type, _size := 1.0) -> int:
	if species == null:
		return 0
	# Difficulty owns the complete per-rat value; species and death type remain
	# useful for the catch report but do not alter the crew's pay.
	var value := _rat_value()
	_collect(species, death_type, value, true)
	return value


func _collect(
		species: RatSpecies,
		death_type: Death.Type,
		value: int,
		counts_for_us: bool
) -> void:
	money += value
	if counts_for_us:
		catches += 1
	if LOG_TO_TERMINAL:
		print("+$%d for %s (%s) — total $%d" % [
			value, species.display_name, Death.name_of(death_type), money,
		])
	if counts_for_us:
		catch_recorded.emit(species, death_type, value)
	money_changed.emit(money, value)

## Pays for something. Returns false when the money is not there, and in that
## case nothing leaves the wallet. The gain goes out negative: whoever is on
## screen only reads the total (`hud_money.gd`), and the notice of what came in
## belongs to the catch, not to the spending.
func spend(amount: int) -> bool:
	if amount <= 0 or money < amount:
		return false
	var api := multiplayer
	var on_the_wire := api != null and api.multiplayer_peer != null \
			and not api.multiplayer_peer is OfflineMultiplayerPeer
	if not on_the_wire:
		_apply_spend(amount)
	elif api.is_server():
		_apply_spend.rpc(amount)
	else:
		_request_spend.rpc_id(HOST_PEER, amount)
	return true


@rpc("any_peer", "reliable")
func _request_spend(amount: int) -> void:
	if not multiplayer.is_server() or amount <= 0 or money < amount:
		return
	_apply_spend.rpc(amount)


@rpc("authority", "call_local", "reliable")
func _apply_spend(amount: int) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		return
	if amount <= 0 or money < amount:
		return
	money -= amount
	if LOG_TO_TERMINAL:
		print("-$%d — total $%d" % [amount, money])
	money_changed.emit(money, -amount)

## What the shift's booked length multiplies every rat by.
##
## Asked of `SessionManager` rather than stored, and asked defensively: this
## autoload is older than the shift state and is used by benches that never stand
## one up, so a wallet that cannot find the setting pays face value rather than
## refusing to pay at all.
func _rat_value() -> int:
	var session := get_node_or_null(^"/root/SessionManager")
	if session == null:
		return HuntTime.reward(HuntTime.DEFAULT)
	return HuntTime.reward(session.hunt_time)


## Writes the total outright, without anybody having caught anything.
##
## **This is the bank's door and nobody else's** (`scripts/economy/bank.gd`): the
## balance is taken out of `SessionManager` on the way into the house and put back
## on the pay slip, and both halves of that are a number being copied rather than
## money being earned. Whoever is paying for a rat calls `collect`, which is what
## announces a catch and what the notice on screen is drawn from.
##
## `money_changed` goes out with a gain of nought, so the total on the HUD moves
## and no "+$10" flashes beside it for money that was already the player's.
func set_balance(amount: int) -> void:
	var settled := maxi(0, amount)
	if settled == money:
		return
	money = settled
	money_changed.emit(money, 0)


## Wipes everything: the start of a shift, and the start of every test bench.
func reset() -> void:
	money = 0
	catches = 0
	money_changed.emit(0, 0)
