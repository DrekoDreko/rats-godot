extends Node
## The player's wallet: the money from the hunt and the tally of how many
## animals have been delivered.
##
## It is the project's only autoload, and that is on purpose: money is the one
## thing in the game that has to survive a scene change — the map starts over,
## what was earned on it does not. Everything else is handled by signals and
## groups.
##
## The one who credits is always the rat, when its hunt comes to an end (see
## `_pay_reward` in `rat.gd`). The price comes from here: species times the
## death discount. On screen it is `hud_money.gd` that listens.

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

## A rat was delivered by somebody, who may well be sitting at another machine.
##
## Every rat in the hunt is thought for by the host — that is the whole of the
## replication model (see `rat.gd`) — so every death is decided on the host, and
## for a long while every death was also *paid for* there. That was wrong in the
## plainest way: a guest could strangle rats all shift and watch the host's
## wallet fill up while his own stayed empty.
##
## So the rat says who killed it and this puts the money where it belongs. On the
## machine of the man who earned it, it lands; anywhere else it goes out over the
## wire and lands there instead. `peer_id` zero, and a hunt with no wire at all,
## both mean "here" — a solo player is the only pocket there is.
##
## The purse itself stays per-machine, which is what it always was: this is one
## autoload per player holding that player's money, and no attempt is made to
## keep a shared pot. Whoever wants a crew purse later builds it on top of this
## rather than instead of it.
func credit(peer_id: int, species: RatSpecies, death_type: Death.Type, size := 1.0) -> int:
	var api := multiplayer
	var on_the_wire := api != null and api.multiplayer_peer != null \
			and not api.multiplayer_peer is OfflineMultiplayerPeer
	if not on_the_wire or peer_id == 0 or peer_id == api.get_unique_id():
		return collect(species, death_type, size)
	# Somebody else's. The species crosses by its resource path rather than as an
	# object — a `Resource` handed to an RPC would be re-created wholesale on the
	# far side, and what the far side wants is the very `.tres` it already has
	# loaded (`resources/species/`).
	_receive.rpc_id(peer_id, species.resource_path, death_type, size)
	return 0

## Money earned on another machine, landing in the pocket it belongs to.
##
## `any_peer` because the message comes from whichever machine was thinking for
## the rat, and that is not necessarily the host — a bench, or a hunt whose
## authority has been handed about, may send it from anywhere. There is a trust
## question in that and it is worth naming: a peer that lied here would be paying
## somebody money he did not earn. It is not guarded, because the whole game is
## built on the peers being the players and a lying peer can already do far worse
## than gift a friend ten dollars.
@rpc("any_peer", "reliable")
func _receive(species_path: String, death_type: Death.Type, size: float) -> void:
	var species := load(species_path) as RatSpecies
	if species == null:
		push_warning("Wallet: paid for a species this machine cannot load: %s" % species_path)
		return
	collect(species, death_type, size)

## A rat was delivered. Returns how much it paid.
##
## The pocket is this machine's, always. Whoever is not sure the money belongs
## here calls `credit` instead, which asks that question and then comes back to
## this.
func collect(species: RatSpecies, death_type: Death.Type, size := 1.0) -> int:
	if species == null:
		return 0
	var value := species.value(death_type, size)
	money += value
	catches += 1
	if LOG_TO_TERMINAL:
		print("+$%d for %s (%s) — total $%d" % [
			value, species.display_name, Death.name_of(death_type), money,
		])
	catch_recorded.emit(species, death_type, value)
	money_changed.emit(money, value)
	return value

## Pays for something. Returns false when the money is not there, and in that
## case nothing leaves the wallet. The gain goes out negative: whoever is on
## screen only reads the total (`hud_money.gd`), and the notice of what came in
## belongs to the catch, not to the spending.
func spend(amount: int) -> bool:
	if amount <= 0 or money < amount:
		return false
	money -= amount
	if LOG_TO_TERMINAL:
		print("-$%d — total $%d" % [amount, money])
	money_changed.emit(money, -amount)
	return true

## Wipes everything: the start of a shift, and the start of every test bench.
func reset() -> void:
	money = 0
	catches = 0
	money_changed.emit(0, 0)
