extends Node
## The tally of one shift: what was caught, how it died, and what it paid.
##
## **Written as it happens, not counted at the end.** A rat that dies is gone —
## freed out of the tree, its species and its wounds with it — so a screen that
## waited for the hunt to be over would have nothing left to read. `Wallet`
## already announces every catch as it is paid for (`catch_recorded`), and this
## listens to that one signal and keeps the running total. The pay slip is then
## only a drawing of numbers that were already true.
##
## **Each machine tallies its own.** The money on `Wallet` is this player's
## money and nobody else's, and so is this. Nothing here crosses the wire: four
## machines each keep their own slip, and each man is shown what his own hands
## earned. A crew total would need the wire and is not what the shift pays on
## today.
##
## **It survives the scene change.** The house is freed on the way back to the
## lobby and the pay slip is read before that happens, but the shift's opening
## figures — how many rats the contract had, what it promised — are settled at
## the start of the hunt and have to outlive the phase. An autoload is where
## anything that outlives a scene lives here, the same as `Wallet` and `Stock`.

## The slip changed. The screen redraws off this rather than polling.
signal changed()

## What the house held when the hunt opened, so the slip can say six of eight
## rather than only six. Set by `House` at the moment it spawns them.
var infestation := 0

## Rats this player was paid for.
var caught := 0

## What those rats paid, before anything is taken off. The same number `Wallet`
## added up, kept separately because `Wallet.money` also carries what was left
## over from the van and what was spent in it.
var earned := 0

## Seconds the hunt actually took, from the first rat out to the last.
var elapsed := 0.0

## How many died each way: `Death.Type` to a count. Only the deaths that
## happened are keys, which is what the slip lists.
var deaths: Dictionary[int, int] = {}

## How many of each species, by display name. Same rule as `deaths`.
var species: Dictionary[String, int] = {}

## When the hunt started, by `Time.get_ticks_msec`. Zero until it does.
var _started := 0


func _ready() -> void:
	# A rat can be paid for while the game is paused — somebody else's trap
	# springs while this player is reading the menu — and the payment still has
	# to be tallied. The session autoloads are all set this way.
	process_mode = Node.PROCESS_MODE_ALWAYS

	Wallet.catch_recorded.connect(_on_catch_recorded)


## The hunt has opened. Called by `House` when it puts the rats in the walls,
## which is the one moment that knows how many there are.
func begin(rat_count: int) -> void:
	reset()
	infestation = maxi(0, rat_count)
	_started = Time.get_ticks_msec()


## The hunt is over, however it ended. The clock is stopped here rather than
## read at the moment the slip is drawn, because the slip can be read a good
## while after — a man who walks away from the screen should not find the shift
## still counting.
func finish() -> void:
	if _started == 0:
		return
	elapsed = float(Time.get_ticks_msec() - _started) / 1000.0
	_started = 0
	changed.emit()


## Rats still in the walls: what was let go, and what the slip charges nothing
## for. Floored at zero, because a bench can pay for a rat the house never
## spawned and a negative escape count is worse than an unremarkable one.
func escaped() -> int:
	return maxi(0, infestation - caught)


## Whether the house was emptied, which is the difference between a job finished
## and a clock that ran out. A shift with no rats in it counts as clear.
func is_clear() -> bool:
	return escaped() == 0


## What the contract pays on top, or zero if the house was not cleared. The
## bonus is the contract's `reward`, and it is all or nothing: the client is
## paying for a house with no rats in it, not for most of one.
func bonus() -> int:
	if not is_clear() or infestation <= 0:
		return 0
	var contract := ContractManager.current()
	return 0 if contract == null else maxi(0, contract.reward)


## The whole slip: what the rats paid plus what the client paid.
func total() -> int:
	return earned + bonus()


## The hunt's length as a clock, for the slip.
func clock() -> String:
	var whole := int(roundf(maxf(0.0, elapsed)))
	@warning_ignore("integer_division") # Whole minutes; the remainder is the seconds beside it.
	return "%d:%02d" % [whole / 60, whole % 60]


## The deaths in a fixed order — the one `Death.MULTIPLIER` is written in, best
## paid first — so the slip does not reshuffle its own rows between two shifts.
## Only the ways that actually happened come back.
func death_rows() -> Array[Array]:
	var rows: Array[Array] = []
	for type in Death.MULTIPLIER:
		var count: int = deaths.get(type, 0)
		if count > 0:
			rows.append([type, count])
	return rows


## The species caught, most first and then by name, so two species with the same
## count keep the same order on every machine.
func species_rows() -> Array[Array]:
	var rows: Array[Array] = []
	for display_name in species:
		rows.append([display_name, species[display_name]])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if a[1] != b[1]:
			return a[1] > b[1]
		return String(a[0]) < String(b[0]))
	return rows


func reset() -> void:
	infestation = 0
	caught = 0
	earned = 0
	elapsed = 0.0
	deaths.clear()
	species.clear()
	_started = 0
	changed.emit()


func _on_catch_recorded(caught_species: RatSpecies, death_type: Death.Type, value: int) -> void:
	# Paid for outside a hunt — a bench, or a rat that died on the way out of the
	# phase. The money is still the player's; the slip is not the place for it.
	if PhaseManager.current() != Phase.Type.HUNT:
		return
	caught += 1
	earned += value
	deaths[death_type] = deaths.get(death_type, 0) + 1
	if caught_species != null:
		var display_name := caught_species.display_name
		species[display_name] = species.get(display_name, 0) + 1
	changed.emit()
