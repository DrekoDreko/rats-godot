extends SceneTree
## The map vote as the crew actually meets it: the van pulls off, the sheets are
## already on the screen, and nobody is out of his seat until the job is signed.
##
## Run with: godot --headless --script _test_van_vote.gd
##
## The bench next door (`_test_contract_vote.gd`) checks the tally itself — who
## may vote, which job wins, what settling it signs. What is checked *here* is
## the half of it that lives in the van: that the road brings the screen up on
## its own, that the man holding it cannot walk about while it is there, that
## the HUD goes with it, and that all three come back the moment the host
## settles the room.
##
## One machine and no wire, which is the solo path and also the host's path.
##
## **Nothing here names a `class_name` or an autoload by its global name** — a
## bench is the `MainLoop` and is compiled before either exists. See the note at
## the top of `_test_travel.gd`.

## The phases by their integer value, in the order `phase.gd` declares them.
const TRAVEL_PHASE := 1

## Where the screen hangs in the van, and the HUD it covers.
const SCREEN_PATH := "VoteUI/ContractVoteScreen"
const HUD_PATH := "HUD"

## Frames of slack for the scene to stand up: `PhaseManager` waits for the old
## one to be freed before it says anything, and the van is built after that.
const WAIT := 12

const ANA := 111
const BRUNO := 222

var _session: Node
var _phase: Node
var _contract: Node

var _screen: Control
var _player: Node

var _frames := 0
var _step := 0
var _wait_until := 0
var _failures := 0


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		return _boot()
	if _frames < 3:
		return false
	match _step:
		0: return _step_take_the_road()
		1: return _step_the_sheets_are_waiting()
		2: return _step_the_crew_picks()
		3: return _step_the_crew_gets_its_legs_back()
	return _finish()


func _boot() -> bool:
	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_contract = root.get_node_or_null("ContractManager")
	if _session == null or _phase == null or _contract == null:
		print("FAIL: an autoload is missing.")
		_failures += 1
		return _finish()

	_session.register_player(ANA, "Ana", true)
	_session.register_player(BRUNO, "Bruno")
	return false


func _step_take_the_road() -> bool:
	_wait_until = _frames + WAIT
	_phase.go_to(TRAVEL_PHASE)
	_step += 1
	return false


## The van is on the road and nobody pressed anything: the sheets are up, the
## man is held where he sat, and the HUD is out of the way.
func _step_the_sheets_are_waiting() -> bool:
	if _frames < _wait_until:
		return false

	var van := current_scene
	if van == null:
		print("FAIL: the road never stood up.")
		_failures += 1
		return _finish()

	_screen = van.get_node_or_null(SCREEN_PATH) as Control
	_check(_screen != null, "the van carries the vote screen")
	if _screen == null:
		return _finish()

	_check(_contract.voting_open, "the road opened the vote on its own")
	_check(_screen.visible, "and the sheets are on the screen")

	var hud := van.get_node_or_null(HUD_PATH) as CanvasLayer
	_check(hud != null and not hud.visible, "the HUD is out of the way behind them")

	_player = get_first_node_in_group("player")
	_check(_player != null, "the man is in the van")
	if _player != null:
		_check(bool(_player.is_ui_open()), "and the screen has him: he cannot walk off mid-vote")

	_step += 1
	return false


## Everybody picks, and the host reads the room.
func _step_the_crew_picks() -> bool:
	var job: Resource = _contract.at(0)
	_contract.request_vote(ANA, job.id)
	_check(_player == null or bool(_player.is_ui_open()),
		"one man having voted does not let the crew go")

	_contract.request_vote(BRUNO, job.id)
	_check(_contract.everybody_voted(), "the whole crew has picked")

	_contract.settle_vote()
	_wait_until = _frames + 2
	_step += 1
	return false


func _step_the_crew_gets_its_legs_back() -> bool:
	if _frames < _wait_until:
		return false

	_check(_contract.is_signed(), "the job the room picked is signed")
	_check(not _screen.visible, "the sheets are off the screen")
	if _player != null:
		_check(not bool(_player.is_ui_open()), "and the man has his legs back")

	var hud := current_scene.get_node_or_null(HUD_PATH) as CanvasLayer
	_check(hud != null and hud.visible, "the HUD is back where it was")

	_step += 1
	return false


func _check(condition: bool, what: String) -> void:
	if condition:
		print("  ok   %s" % what)
		return
	print("  FAIL %s" % what)
	_failures += 1


func _finish() -> bool:
	if _failures == 0:
		print("\nvan vote bench: all good.")
	else:
		print("\nvan vote bench: %d failed." % _failures)
	quit(1 if _failures > 0 else 0)
	return true
