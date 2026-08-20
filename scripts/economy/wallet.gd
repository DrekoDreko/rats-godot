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

## A rat was delivered. Returns how much it paid.
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
