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
## death discount. The HUD, once it exists, only needs to listen to
## `money_changed`.

## The total changed. `gain` is what just came in.
signal money_changed(total: int, gain: int)
## An animal was closed out, with everything known about it. It feeds the
## on-screen notice ("+$10, strangulation") and the end-of-shift summary.
signal catch_recorded(species: RatSpecies, death_type: Death.Type, value: int)

var money := 0
var catches := 0

# While there is no HUD, this terminal notice is what shows the money coming in.
# It goes away once the scoreboard reaches the screen.
const LOG_TO_TERMINAL := true

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

## Wipes everything: the start of a shift, and the start of every test bench.
func reset() -> void:
	money = 0
	catches = 0
	money_changed.emit(0, 0)
