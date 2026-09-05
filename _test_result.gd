extends SceneTree
## The end of a shift: the tally the pay slip is drawn from, and the road home.
##
## Run with: godot --headless --script _test_result.gd
##
## One machine and no wire, so `PhaseManager.is_host()` answers true throughout —
## which is the solo game anyway, and the only version of this a bench can drive:
## whether four machines all leave the pay phase at the same moment is the
## acceptance test of the card and is done by hand with two instances open.
##
## What is checked here is everything that answer is built out of:
##
## 1. The slip is empty before a hunt and starts counting when one opens.
## 2. A catch during the hunt lands on the slip — the count, the money, the way
##    it died and what it was.
## 3. A house emptied reads as cleared and pays the contract on top; one left
##    with rats in the walls reads as time up and pays nothing extra.
## 4. Money paid outside a hunt is the player's but is not on the shift's slip.
## 5. The pay slip's button puts the crew back in the van: the job is cleared —
##    the slip, the signature — and the money and the crates they earned are not.
## 6. The road home to the lobby still takes the whole shift with it: the money,
##    the crates and the signature are all cleared, and the crew is not.
## 7. The bank pays the crew out on the doorstep: the house opens on the balance
##    the shop closed on, and not on nought.
## 8. The pay slip banks it again — what is left in the wallet plus the client's
##    bonus — and a slip settled twice does not pay twice.
## 9. Two houses in a row: the money carries down the road, the shelf spends it,
##    and the next house opens on what is left.
## 10. And the road home puts every purse back to the first day's hundred.
##
## The autoloads are picked up by node name rather than by their global names,
## which do not exist in a bench run with `--script`. For the same reason the
## phase and death types are written out as the integers they are.

const LOBBY := 0
const TRAVEL := 1
const SURVEY := 2
const HUNT := 3
const RESULT := 4

## `Death.Type`, written out for the same reason as the phases above.
const STRANGULATION := 1
const CRUSHING := 6

## Frames of slack for a scene change to actually happen.
const WAIT := 8

## What a man is worth before anything is earned — `SessionManager.STARTING_MONEY`,
## written out for the same reason the phases above are.
const STARTING_MONEY := 100

## What the bank is seeded with for the checks below. A round number that is
## neither the starting hundred nor anything a rat pays, so a figure that turns up
## in the wrong place is obvious.
const BANKED := 250

## The price of one thing off the shelf, for the check that shopping comes out of
## the same purse the house pays into.
const SPENT := 25

## Stood in for the house, so that a bench about money does not also load and
## light a whole map. What is under test is the phase the wallet is filled on, not
## the room it is filled in.
const EMPTY_SCENE := "res://_test_empty.tscn"

const ANA := 111
const BRUNO := 222

## A species built here rather than loaded off the shelf: what is under test is
## the tally, and a bench that also depended on which `.tres` files ship would
## fail for a reason that has nothing to do with the pay slip.
const SPECIES_NAME := "Bench Rat"
const SPECIES_VALUE := 100

var _session: Node
var _phase: Node
var _wallet: Node
var _stock: Node
var _report: Node
var _contract_mgr: Node
var _bank: Node

## What the bank held when the last check left it, carried between two steps.
var _banked := 0

var _species: Resource

var _failures := 0
var _frames := 0
var _step := 0
var _clock := 0


func _initialize() -> void:
	# Headless runs at thousands of frames a second, and the slip carries a clock.
	Engine.max_fps = 60

	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_wallet = root.get_node_or_null("Wallet")
	_stock = root.get_node_or_null("Stock")
	_report = root.get_node_or_null("ShiftReport")
	_contract_mgr = root.get_node_or_null("ContractManager")
	_bank = root.get_node_or_null("Bank")


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_an_empty_slip()
		1: return _check_a_hunt_opens_the_slip()
		2: return _check_a_catch_lands_on_it()
		3: return _check_a_cleared_house_pays_the_bonus()
		4: return _check_rats_left_in_the_walls()
		5: return _check_money_outside_a_hunt()
		6: return _check_the_road_back_to_the_van()
		7: return _check_the_way_home()
		8: return _check_the_bank_pays_out_on_the_doorstep()
		9: return _check_the_slip_banks_the_shift()
		10: return _check_two_houses_in_a_row()
		11: return _check_the_way_home_empties_the_purse()
	return _finish()

# --- Steps ------------------------------------------------------------------

## Nothing has happened yet. A slip nobody has worked a shift for is empty, and
## an empty slip is not a cleared house — there was no house.
func _check_an_empty_slip() -> bool:
	if _report == null or _phase == null or _session == null or _wallet == null:
		print("FAIL: the autoloads are not in the tree")
		return _finish()

	_species = _build_species()

	_session.reset()
	_session.register_player(ANA, "Ana", true)
	_session.register_player(BRUNO, "Bruno")
	_wallet.reset()
	_report.reset()

	_expect(_report.caught == 0, "a fresh slip has caught nothing")
	_expect(_report.earned == 0, "and been paid nothing")
	_expect(_report.total() == 0, "which is what it comes to")
	_expect(_report.infestation == 0, "and it does not know of a house")
	_expect(_report.escaped() == 0, "so nothing was let go")
	return _advance()

## The hunt opens. `House` calls `begin` with what the contract put in the walls,
## and from there the slip knows what it is counting towards.
func _check_a_hunt_opens_the_slip() -> bool:
	_session.phase = HUNT
	_report.begin(3)

	_expect(_report.infestation == 3, "the slip is opened with the house it was let")
	_expect(_report.caught == 0, "with nothing in the bag yet")
	_expect(_report.escaped() == 3, "and everything still in the walls")
	_expect(not _report.is_clear(), "so the house is not clear")
	return _advance()

## A rat is paid for while the hunt is on. The money is the player's and the rat
## is on the slip: how many, what it paid, what it was and how it died.
func _check_a_catch_lands_on_it() -> bool:
	var paid: int = _wallet.collect(_species, STRANGULATION)
	_expect(paid > 0, "a rat pays something")

	_expect(_report.caught == 1, "one rat on the slip")
	_expect(_report.earned == paid, "and what it paid is what the wallet paid")
	_expect(_report.escaped() == 2, "two still in the walls")
	_expect(_report.species.get(SPECIES_NAME, 0) == 1, "the breed is named on the slip")
	_expect(_report.deaths.get(STRANGULATION, 0) == 1, "and so is what killed it")

	# A second, killed another way, so the slip has to keep the two apart rather
	# than only count to two.
	_wallet.collect(_species, CRUSHING)
	_expect(_report.caught == 2, "two rats on the slip")
	_expect(_report.deaths.get(STRANGULATION, 0) == 1, "one strangled")
	_expect(_report.deaths.get(CRUSHING, 0) == 1, "one crushed")
	_expect(_report.species.get(SPECIES_NAME, 0) == 2, "both of them the same breed")

	var rows: Array = _report.death_rows()
	_expect(rows.size() == 2, "and the slip lists the two ways and no others")
	_expect(rows[0][0] == STRANGULATION,
		"best paid first, so the rows do not reshuffle between two shifts")
	return _advance()

## The last one. An emptied house is a job finished, and the client pays for it
## on top of what the rats were worth.
func _check_a_cleared_house_pays_the_bonus() -> bool:
	_wallet.collect(_species, STRANGULATION)

	_expect(_report.caught == 3, "the third rat is the house")
	_expect(_report.escaped() == 0, "with nothing left in the walls")
	_expect(_report.is_clear(), "so the house reads as cleared")

	var contract: Resource = _contract_mgr.current()
	var reward: int = 0 if contract == null else int(contract.reward)
	_expect(_report.bonus() == reward,
		"and the client pays the contract on top — %d" % reward)
	_expect(_report.total() == _report.earned + reward,
		"which is the whole slip: the rats and the client")

	# The clock is stopped on the way out of the hunt, and stays stopped. A bench
	# hunt is over in a handful of frames, so the length itself is measured in
	# milliseconds and is not worth asserting a floor on; what matters is that
	# the number is settled at that moment and does not move afterwards.
	_session.phase = RESULT
	_report.finish()
	var stopped: float = _report.elapsed
	_expect(stopped >= 0.0, "the hunt has a length")
	_expect(_report.clock() == "0:00", "a hunt over in three frames reads as no time at all")
	_report.finish()
	_expect(is_equal_approx(_report.elapsed, stopped),
		"and a slip read twice does not go on counting")
	return _advance()

## The other way a hunt ends: the clock runs out with rats still loose. The
## client pays nothing for most of a house.
func _check_rats_left_in_the_walls() -> bool:
	_session.phase = HUNT
	_report.begin(4)
	_wallet.collect(_species, STRANGULATION)

	_expect(_report.caught == 1, "one of the four")
	_expect(_report.escaped() == 3, "three left in the walls")
	_expect(not _report.is_clear(), "so the house is not clear")
	_expect(_report.bonus() == 0, "and there is no bonus for most of a house")
	_expect(_report.total() == _report.earned, "the slip is what the rats paid, and no more")
	return _advance()

## Money paid outside a hunt — a bench, or a rat dying on the way out of the
## phase. It is the player's money and the wallet keeps it; the shift's slip is
## not where it belongs.
func _check_money_outside_a_hunt() -> bool:
	_session.phase = RESULT
	_report.finish()

	var before_caught: int = _report.caught
	var before_earned: int = _report.earned
	var before_money: int = _wallet.money

	_wallet.collect(_species, STRANGULATION)

	_expect(_wallet.money > before_money, "the wallet still takes the money")
	_expect(_report.caught == before_caught, "but the slip does not count the rat")
	_expect(_report.earned == before_earned, "nor the money")
	return _advance()

## OK, and back on the road. The pay slip's button is what the crew presses, and
## what it does is `advance()` — so the shift comes round to the van rather than
## to the menu: the job goes in the bin, and the money and the crates the crew
## worked for stay on the books for the next one.
func _check_the_road_back_to_the_van() -> bool:
	if _clock == 1:
		_report.begin(2)
		_wallet.collect(_species, CRUSHING)
		_stock.add("mousetrap", 2)
		_session.set_contract("bench-contract")
		_phase.go_to(RESULT)
		return false
	if _clock == 2:
		_expect(_phase.next_phase() == TRAVEL, "the road out of the pay slip is the van")
		_phase.advance()
		return false
	if _clock < WAIT:
		return false

	_expect(_phase.current() == TRAVEL, "the shift is back on the road")
	_expect(current_scene != null and current_scene.scene_file_path == "res://scenes/van_travel.tscn",
		"and the van is what is on screen")

	_expect(_wallet.money > 0, "the money the crew made is still theirs")
	_expect(_stock.count("mousetrap") == 2, "and so is what is left in the crates")
	_expect(_report.caught == 0, "the slip is wiped for the next job")
	_expect(_report.infestation == 0, "house and all")
	_expect(_session.current_contract == "", "and the signature with it — nothing is signed yet")
	return _advance()

## OK, and home. The pay phase walks back round to the lobby, the menu is what
## is on screen, and everything the shift piled up goes out with it — except the
## crew, who have not gone anywhere.
func _check_the_way_home() -> bool:
	if _clock == 1:
		_stock.add("mousetrap", 2)
		_session.set_contract("bench-contract")
		_expect(_wallet.money > 0, "there is money on the books before we go home")
		_phase.go_to(LOBBY)
		return false
	if _clock < WAIT:
		return false

	_expect(_phase.current() == LOBBY, "the shift is home")
	_expect(current_scene != null and current_scene.scene_file_path == "res://scenes/menu.tscn",
		"and the menu is what is on screen")

	_expect(_wallet.money == 0, "the shift's money went out with the shift")
	_expect(_stock.count("mousetrap") == 0, "and so did what was left in the crates")
	_expect(_report.caught == 0, "the slip is wiped for the next job")
	_expect(_report.infestation == 0, "house and all")
	_expect(_session.current_contract == "", "the signature is gone")

	_expect(_session.count() == 2, "the crew is still here — they finished a job, they did not leave")
	_expect(_session.has_player(ANA) and _session.has_player(BRUNO), "both of them")
	return _advance()

## The doorstep. The shelf in the van spends `SessionManager`'s purse and the
## house spends the `Wallet`, and the bank is what makes those one number: on the
## way in from the road it pays the man out of the bank, so the HUD opens on what
## the shop closed on rather than on nought.
##
## The crew is cut to one man on purpose. `LobbyManager.our_crew_id` falls back to
## the only member of a one-man crew when Steam is not running, which is the only
## way a bench can be somebody.
func _check_the_bank_pays_out_on_the_doorstep() -> bool:
	if _clock == 1:
		_session.reset()
		_session.register_player(ANA, "Ana", true)
		_session.set_money(ANA, BANKED)
		_wallet.reset()
		_report.reset()
		# Both the survey and the hunt, in one call, the way a signature does it.
		_phase.set_house(EMPTY_SCENE)
		_phase.go_to(TRAVEL)
		return false
	if _clock == WAIT:
		_expect(_wallet.money == 0, "on the road the wallet is empty — the bank holds the money")
		_expect(_session.money(ANA) == BANKED, "and the bank holds all of it")
		_phase.go_to(SURVEY)
		return false
	if _clock < WAIT * 2:
		return false

	_expect(_phase.current() == SURVEY, "the crew is in the house")
	_expect(_wallet.money == BANKED, "and the house opened on what the shop closed on")
	_expect(_session.money(ANA) == BANKED, "the bank still says the same number — it was copied, not moved")
	return _advance()

## The pay slip. What is left in the wallet, plus what the client pays for a clear
## house, goes back to the bank — and because the wallet was seeded from the bank,
## what is written is the whole balance and not an addition to it. That is what
## makes settling twice harmless, which is the second half of this check.
func _check_the_slip_banks_the_shift() -> bool:
	if _clock == 1:
		_phase.go_to(HUNT)
		_report.begin(2)
		_wallet.collect(_species, STRANGULATION)
		_wallet.collect(_species, STRANGULATION)
		return false
	if _clock == 2:
		_expect(_wallet.money > BANKED, "the rats paid on top of what was carried in")
		_phase.go_to(RESULT)
		return false
	if _clock < WAIT:
		return false

	_expect(_report.is_clear(), "the house came out clear")
	var banked: int = _session.money(ANA)
	_expect(banked == _wallet.money,
		"the bank holds what the wallet closed on — %d" % banked)
	_expect(banked == BANKED + _report.earned + _report.bonus(),
		"which is what was carried in, what the rats paid and what the client paid")

	_bank.settle()
	_expect(_session.money(ANA) == banked, "and a slip settled twice does not pay twice")
	return _advance()

## Two houses in a row, which is the whole point of the loop: the money rides the
## van to the next job, the shelf takes its cut out of the same purse, and the
## house after that opens on what is left.
func _check_two_houses_in_a_row() -> bool:
	if _clock == 1:
		_banked = _session.money(ANA)
		_phase.advance()
		return false
	if _clock == WAIT:
		_expect(_phase.current() == TRAVEL, "the pay slip let the crew back onto the road")
		_expect(_session.money(ANA) == _banked, "with the money it made")
		# What a purchase does, without standing the shelf up for it: `ShopManager`
		# debits this same field, and what is under test here is the doorstep
		# reading it afterwards.
		_session.set_money(ANA, _banked - SPENT)
		_phase.go_to(SURVEY)
		return false
	if _clock < WAIT * 2:
		return false

	_expect(_wallet.money == _banked - SPENT,
		"and the next house opens on what was left after the shopping")
	return _advance()

## The end of the run. Going home to the menu is not the end of a job but the end
## of an evening, so every purse goes back to the hundred a man is registered
## with — a fresh crew in a fresh van, not one still carrying last night's takings.
func _check_the_way_home_empties_the_purse() -> bool:
	if _clock == 1:
		_expect(_session.money(ANA) > STARTING_MONEY, "there is more than a hundred on the books")
		_phase.go_to(LOBBY)

		# Read on the spot rather than after the menu has loaded. `_clear_shift`
		# runs inside the phase change, so the purse is already back; what happens
		# over the frames after it is that the menu rebuilds the crew off the real
		# lobby, and this bench's stand-in men are not in that one. Waiting would
		# be asking after a man who has gone home.
		_expect(_session.money(ANA) == STARTING_MONEY, "and the purse is back to the first day")
		_expect(_wallet.money == 0, "with nothing left in the wallet either")
		return false
	if _clock < WAIT:
		return false

	_expect(_phase.current() == LOBBY, "the crew is home")
	return _advance()

# --- Plumbing ----------------------------------------------------------------

## A species with a round number on it, so the arithmetic in the checks above is
## legible. Built rather than loaded: see the note at the top.
func _build_species() -> Resource:
	var script: Script = load("res://scripts/economy/rat_species.gd")
	var species: Resource = script.new()
	species.display_name = SPECIES_NAME
	species.base_value = SPECIES_VALUE
	species.variation = 0.0
	return species


func _expect(condition: bool, what: String) -> void:
	if condition:
		return
	print("FAIL: %s" % what)
	_failures += 1


func _advance() -> bool:
	_step += 1
	_clock = 0
	return false


func _finish() -> bool:
	print("--- %d frames, %d failure(s) ---" % [_frames, _failures])
	return true
