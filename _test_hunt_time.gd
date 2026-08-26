extends SceneTree
## The hunt's booked clock: how long the crew gives itself in the house and what
## that hurry is worth per rat.
##
## Run with: godot --headless --script _test_hunt_time.gd
##
## One machine and no wire, so `PhaseManager.is_host()` answers true throughout —
## which is the path a solo game takes anyway, and the path every host takes. The
## agreement between two machines is not testable from here; what is testable is
## everything it is built out of: that the three settings carry the durations and
## multipliers the design asks for, that a booking is refused once the van has
## pulled off, that the phase machine times the hunt off the booking rather than
## off the static table, that the wallet pays at the booked rate, and that a hunt
## whose clock runs out ends the shift with rats still loose.
##
## `HuntTime` is not named as a class anywhere in here on purpose: a bench run
## with `--script` compiles before the project's global classes exist, so the
## three settings are written as the plain integers the enum resolves to.

## Frames of slack to let a phase change and its scene actually land.
const WAIT := 8

## The three settings, as their enum values.
const LONG := 0
const MEDIUM := 1
const SHORT := 2

## What each of them is supposed to be worth, from the design: ten minutes at
## face value, five at double, two at five times.
const EXPECTED := {
	LONG: [600.0, 1.0],
	MEDIUM: [300.0, 2.0],
	SHORT: [120.0, 5.0],
}

## The phases, as their enum values — same reason as above.
const LOBBY := 0
const TRAVEL := 1
const SURVEY := 2
const HUNT := 3
const RESULT := 4

## The death that takes nothing off the price. Strangulation, so that what is
## left moving in the wallet check is the hunt's own multiple and nothing else.
const STRANGULATION := 1

## Stand-in Steam IDs.
const ANA := 111
const BRUNO := 222

## The autoloads, picked up by node name because the global names do not exist
## in a bench.
var _session: Node
var _phase: Node
var _contract: Node
var _wallet: Node

## What the shift did while we watched, so that a phase change can be checked
## after the fact rather than at the instant it happened.
var _changes: Array[Array] = []
var _expired: Array[int] = []

var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	# Headless runs at thousands of frames a second, which would spend a
	# two-minute phase between two of them. A real frame rate is what makes a
	# clock measurable at all.
	Engine.max_fps = 60

	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_contract = root.get_node_or_null("ContractManager")
	_wallet = root.get_node_or_null("Wallet")
	if _phase == null:
		return

	_phase.phase_changed.connect(func(before: int, after: int) -> void:
		_changes.append([before, after]))
	_phase.timer_expired.connect(func(phase: int) -> void: _expired.append(phase))


func _physics_process(_delta: float) -> bool:
	_clock += 1
	match _step:
		0: return _check_table()
		1: return _check_default_and_booking()
		2: return _check_closed_after_lobby()
		3: return _check_phase_clock()
		4: return _check_wallet_pays_at_the_booked_rate()
		5: return _check_clock_ends_the_hunt()
		6: return _check_expired()
	return _finish()

# --- The table --------------------------------------------------------------

## The three settings say what the design says they say. It is the one check that
## would catch somebody tuning the numbers without meaning to.
func _check_table() -> bool:
	if _phase == null or _session == null or _contract == null:
		print("FAIL: autoloads missing")
		return _finish()

	for setting in EXPECTED:
		var want: Array = EXPECTED[setting]
		_session.set_hunt_time(setting)
		var duration: float = _phase.duration_of(HUNT)
		var multiplier: float = _session.hunt_multiplier()
		_expect(is_equal_approx(duration, want[0]),
			"setting %d runs %.0fs, expected %.0fs" % [setting, duration, want[0]])
		_expect(is_equal_approx(multiplier, want[1]),
			"setting %d pays x%.2f, expected x%.2f" % [setting, multiplier, want[1]])
	return _advance()

# --- Booking it -------------------------------------------------------------

## A fresh shift is booked at the long clock, and the host can move it. The van
## is parked, so the board is open and nothing should refuse.
func _check_default_and_booking() -> bool:
	_session.reset()
	_session.register_player(ANA, "Ana", true)
	_session.register_player(BRUNO, "Bruno", false)

	_expect(_session.hunt_time == LONG,
		"a reset shift is booked at %d, expected the long clock" % _session.hunt_time)

	_contract.set_hunt_time(SHORT)
	_expect(_session.hunt_time == SHORT,
		"the host booked the short clock and the shift reads %d" % _session.hunt_time)
	_expect(is_equal_approx(_session.hunt_multiplier(), 5.0),
		"the short clock pays x%.2f, expected x5" % _session.hunt_multiplier())

	# A length nobody has is refused rather than written: everything downstream
	# reads a duration off it, and there is none for a setting that does not
	# exist.
	_contract.set_hunt_time(99)
	_expect(_session.hunt_time == SHORT,
		"a length that does not exist was written anyway: %d" % _session.hunt_time)

	_contract.set_hunt_time(MEDIUM)
	_expect(_session.hunt_time == MEDIUM,
		"booking the middle clock left the shift at %d" % _session.hunt_time)
	return _advance()


## The board closes when the van pulls off, and the clock closes with it: the
## length is what the crew shopped and set traps against, and moving it on the
## doorstep would be moving the bet after the cards are down.
func _check_closed_after_lobby() -> bool:
	if _clock < WAIT:
		return false
	_contract.sign("hallow_street")
	_phase.go_to(TRAVEL)
	_contract.set_hunt_time(SHORT)
	_expect(_session.hunt_time == MEDIUM,
		"the clock was changed on the road: the shift reads %d" % _session.hunt_time)
	return _advance()

# --- The clock the hunt runs on ---------------------------------------------

## The phase machine times the hunt off the booking and not off `Phase.DURATION`,
## which still reads zero for it — and nothing else about the shift moved with it.
func _check_phase_clock() -> bool:
	if _clock < WAIT:
		return false
	_session.reset()
	_session.register_player(ANA, "Ana", true)

	_session.set_hunt_time(SHORT)
	_expect(is_equal_approx(_phase.duration_of(HUNT), 120.0),
		"the short hunt runs %.0fs, expected 120" % _phase.duration_of(HUNT))
	_session.set_hunt_time(LONG)
	_expect(is_equal_approx(_phase.duration_of(HUNT), 600.0),
		"the long hunt runs %.0fs, expected 600" % _phase.duration_of(HUNT))

	# The rest of the shift is untouched by any of this: only the hunt's length
	# is the crew's to set.
	_expect(is_equal_approx(_phase.duration_of(TRAVEL), 120.0),
		"the road stopped running two minutes")
	_expect(is_equal_approx(_phase.duration_of(SURVEY), 60.0),
		"the survey stopped running a minute")
	_expect(is_equal_approx(_phase.duration_of(LOBBY), 0.0),
		"the parked van grew a clock")
	return _advance()

# --- What a rat is worth ----------------------------------------------------

## The same rat, delivered the same way, pays the booked multiple. This is the
## whole economic point of the feature, and it is checked on the wallet rather
## than on the table so that the rounding is checked with it.
func _check_wallet_pays_at_the_booked_rate() -> bool:
	if _wallet == null:
		print("FAIL: the wallet is missing")
		return _advance()

	var species: Resource = load("res://resources/species/common_rat.tres")
	if species == null:
		print("FAIL: no species to price")
		return _advance()

	var paid := {}
	for setting in EXPECTED:
		_session.set_hunt_time(setting)
		_wallet.reset()
		var value: int = _wallet.collect(species, STRANGULATION, 1.0)
		paid[setting] = value
		_expect(_wallet.money == value,
			"the wallet took %d but reads %d" % [value, _wallet.money])

	_expect(int(paid[MEDIUM]) == int(paid[LONG]) * 2,
		"the five-minute rat paid %d, expected twice %d" % [paid[MEDIUM], paid[LONG]])
	_expect(int(paid[SHORT]) == int(paid[LONG]) * 5,
		"the two-minute rat paid %d, expected five times %d" % [paid[SHORT], paid[LONG]])

	_wallet.reset()
	_session.set_hunt_time(LONG)
	return _advance()

# --- The clock ending the hunt ----------------------------------------------

## A hunt that runs out of time ends anyway, with whatever is still loose left in
## the walls. It is the half of the wager that costs something, and without it a
## two-minute booking would be five times the money for nothing.
##
## Wound down rather than waited out: sitting through even the two-minute setting
## at sixty frames a second is two minutes of bench. The `Timer` is restarted at a
## fifth of a second instead, which ends by the same road — what is being checked
## is that running out advances the shift, not that a `Timer` counts.
func _check_clock_ends_the_hunt() -> bool:
	if _clock < WAIT:
		return false
	_session.reset()
	_session.register_player(ANA, "Ana", true)
	_session.set_hunt_time(SHORT)
	_changes.clear()
	_expired.clear()

	_phase.go_to(HUNT)
	_expect(_phase.has_timer(),
		"the hunt started with no clock on it")
	_expect(_phase.seconds_left > 100.0,
		"the hunt started with %.0fs left, expected about 120" % _phase.seconds_left)

	var timer := _host_timer()
	if timer == null:
		print("FAIL: the phase machine has no clock to wind down")
		return _finish()
	timer.start(0.2)
	return _advance()


## The clock has had its fifth of a second. The shift should have walked itself
## on to the pay slip, and said so on the way.
func _check_expired() -> bool:
	if _clock < 30:
		return false
	_expect(_expired.has(HUNT),
		"the hunt's clock ran out and nobody said so: %s" % [_expired])
	_expect(_session.phase == RESULT,
		"the hunt ran out and the shift sits at %d, expected the pay slip" % _session.phase)
	var walked := false
	for change in _changes:
		if change[0] == HUNT and change[1] == RESULT:
			walked = true
	_expect(walked, "nothing announced the hunt ending: %s" % [_changes])
	return _finish()

# --- Odds and ends ----------------------------------------------------------

## The host's own countdown, reached into so the bench can wind it down. It is
## private on purpose and this is the one place worth breaking that, rather than
## spending two minutes of real time on every run.
func _host_timer() -> Timer:
	for child in _phase.get_children():
		var timer := child as Timer
		if timer != null:
			return timer
	return null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	print("FAIL: %s" % message)


## On to the next check, with the per-step clock started over.
func _advance() -> bool:
	_step += 1
	_clock = 0
	return false


func _finish() -> bool:
	if _failures == 0:
		print("PASS: the hunt is booked, timed and paid at the crew's own clock")
	else:
		print("%d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
	return true
