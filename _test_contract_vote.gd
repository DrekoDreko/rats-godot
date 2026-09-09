extends SceneTree
## The crew's vote for the first job: every man picks a card, the host reads
## the room, and the job with the most hands up is what gets signed.
##
## Run with: godot --headless --script _test_contract_vote.gd
##
## One machine and no wire, so `PhaseManager.is_host()` answers true
## throughout — the path a solo game takes anyway, and the path every host
## takes. What is checked here is everything the vote is built out of: that
## opening it clears the board, that a vote only counts from somebody in the
## crew, that a second vote from the same man replaces his first rather than
## adding a second ballot, that the tally is read correctly, that the job with
## the most votes is the one that gets signed, that settling the vote signs it
## and closes the sheets without moving the shift anywhere, and that the van
## pulling off with a blank board is what puts the sheets up in the first
## place — with the crew held in place until they come down.

const WAIT := 8

## The phases, by their integer value. `Phase.Type` is a `class_name` and a
## bench is compiled before the global class list is built, so the numbers are
## written out here the way the other benches write them — the order is the one
## in `phase.gd`.
const LOBBY_PHASE := 0
const TRAVEL_PHASE := 1

var _session: Node
var _phase: Node
var _contract: Node
var _lobby: Node
var _ready_mgr: Node

const ANA := 111
const BRUNO := 222
const CARLOS := 333

var _signed: Array[String] = []
var _voted: Array[Array] = []
var _opened := 0
var _closed := 0

var _frames := 0
var _step := 0

## The frame a waiting step may look at its answer on. A phase change is not
## finished when `go_to` returns — the scene is swapped first and
## `phase_changed` is only emitted once the old one is actually freed
## (`PhaseManager._change_scene`) — so a step that changes the phase parks the
## deadline here and the next one sits on `_waiting` until the frames have
## really gone by.
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
		0: return _step_opens_clean()
		1: return _step_only_the_crew_votes()
		2: return _step_a_second_vote_replaces_the_first()
		3: return _step_the_most_votes_wins()
		4: return _step_settling_the_vote()
		5: return _step_a_signed_road_stays_quiet()
		6: return _step_the_blank_board_goes_up()
		7: return _step_the_sheets_are_up()
	return _finish()


func _boot() -> bool:
	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_contract = root.get_node_or_null("ContractManager")
	_lobby = root.get_node_or_null("LobbyManager")
	_ready_mgr = root.get_node_or_null("ReadyManager")
	var missing := _contract == null or _session == null or _phase == null
	if missing or _lobby == null or _ready_mgr == null:
		print("FAIL: an autoload is missing — is ContractManager registered?")
		_failures += 1
		return _finish()

	_contract.contract_signed.connect(func(id: String) -> void: _signed.append(id))
	_contract.vote_changed.connect(
		func(steam_id: int, id: String) -> void: _voted.append([steam_id, id]))
	_contract.voting_opened.connect(func() -> void: _opened += 1)
	_contract.voting_closed.connect(func() -> void: _closed += 1)

	_session.register_player(ANA, "Ana", true)
	_session.register_player(BRUNO, "Bruno")
	_session.register_player(CARLOS, "Carlos")
	_check(_session.bank_balance == 300, "the three $100 contributions form one $300 bank")
	return false


## Opening the vote clears whatever was there and lets everybody read it.
func _step_opens_clean() -> bool:
	_check(not _contract.voting_open, "nothing is being voted on before the host opens it")
	_check(not _contract.everybody_voted(), "and nobody has voted on nothing")

	_contract.open_voting()
	_check(_contract.voting_open, "the host opened the vote")
	_check(_opened == 1, "and said so once (%d)" % _opened)
	_check(_contract.votes.is_empty(), "the board starts with no ballots on it")

	_step += 1
	return false


## Only somebody in the crew can vote, and only under his own name.
func _step_only_the_crew_votes() -> bool:
	var job: Contract = _contract.at(0)
	_contract.request_vote(999, job.id)
	_check(not _contract.votes.has(999), "a vote for nobody in the crew is not counted")

	_contract.request_vote(ANA, job.id)
	_check(_contract.votes.get(ANA, "") == job.id, "Ana's vote is on the board")
	_check(_contract.votes_for(job.id) == 1, "and the tally reads one for her job")
	_check(not _contract.everybody_voted(), "the crew has not all voted yet")

	_step += 1
	return false


## Voting again moves the man's own ballot rather than adding a second one.
func _step_a_second_vote_replaces_the_first() -> bool:
	var first: Contract = _contract.at(0)
	var second: Contract = _contract.at(1)

	_contract.request_vote(ANA, second.id)
	_check(_contract.votes_for(first.id) == 0, "Ana's old vote is gone from the first job")
	_check(_contract.votes_for(second.id) == 1, "and counted on the one she switched to")
	_check(_contract.votes.size() == 1, "the board still holds one ballot, not two")

	_step += 1
	return false


## The job with the most votes wins, even against a crew leader who voted for
## something else.
func _step_the_most_votes_wins() -> bool:
	var winner: Contract = _contract.at(1)
	var loser: Contract = _contract.at(0)

	# Ana already voted for `winner` in the step above. Bruno and Carlos back
	# a different job, so the board reads one vote apiece before the third
	# ballot breaks the tie.
	_contract.request_vote(BRUNO, loser.id)
	_contract.request_vote(CARLOS, loser.id)
	_check(_contract.everybody_voted(), "all three have now voted")
	_check(_contract.votes_for(loser.id) == 2, "the split shows two votes for the loser")
	_check(_contract.votes_for(winner.id) == 1, "and one for the winner, before the tie breaks")

	# Carlos changes his mind, which is what actually decides it.
	_contract.request_vote(CARLOS, winner.id)
	_check(_contract.votes_for(winner.id) == 2, "the winner now has two votes")
	_check(_contract.votes_for(loser.id) == 1, "and the loser is back down to one")
	_check(_contract._winning_contract() == winner.id,
		"the job with the most votes is read as the winner (%s)" % _contract._winning_contract())

	_step += 1
	return false


## Settling the vote signs the winner and takes the sheets away. It moves the
## shift nowhere: the van is already on the road by the time anybody votes, and
## what the crew gets back is its legs.
func _step_settling_the_vote() -> bool:
	var winner: Contract = _contract.at(1)
	var was: int = _session.phase
	_signed.clear()

	_check(_ready_mgr.blocked, "the crew is held in place while the sheets are up")

	_contract.settle_vote()
	_check(_signed == [winner.id], "settling the vote signs the job that won %s" % [_signed])
	_check(_session.bank_balance == 100, "the $200 contract leaves $100 in the team bank")
	_check(not _contract.voting_open, "and the vote is closed")
	_check(_closed == 1, "said once (%d)" % _closed)
	_check(not _ready_mgr.blocked, "and the crew is let go again")

	_check(_session.phase == was, "the shift did not move on its own (now %d)" % _session.phase)

	_step += 1
	return false


## The van pulling off is what lays the sheets out — nobody presses anything.
## A road reached with a job already signed to it does not re-open the vote:
## that is a crew being driven to a house it has already chosen.
func _step_a_signed_road_stays_quiet() -> bool:
	_check(_contract.is_signed(), "the job settled above is still signed")
	_phase.go_to(TRAVEL_PHASE)
	return _wait()


## And the same road with the board wiped — which is the state a van rolling
## out of a finished house arrives in (`PhaseManager._clear_job`).
func _step_the_blank_board_goes_up() -> bool:
	if _waiting():
		return false
	_check(not _contract.voting_open, "the road does not re-open a vote on a signed job")

	_session.set_contract("")
	_opened = 0
	_phase.go_to(LOBBY_PHASE)
	return _wait()


func _step_the_sheets_are_up() -> bool:
	if _waiting():
		return false
	if _phase.current() != TRAVEL_PHASE:
		_phase.go_to(TRAVEL_PHASE)
		return _wait_here()
	_check(_contract.voting_open, "reaching the road with a blank board lays the sheets out")
	_check(_opened == 1, "and says so once (%d)" % _opened)
	_check(_ready_mgr.blocked, "and holds the van until they come down")

	_step += 1
	return false


## Parks the deadline and moves to the next step, which will sit on `_waiting`
## until the frames have gone by.
func _wait() -> bool:
	_wait_until = _frames + WAIT
	_step += 1
	return false


## The same, without leaving the step: for a step that has something to do on
## both sides of a wait.
func _wait_here() -> bool:
	_wait_until = _frames + WAIT
	return false


func _waiting() -> bool:
	return _frames < _wait_until


func _check(condition: bool, what: String) -> void:
	if condition:
		print("  ok   %s" % what)
		return
	print("  FAIL %s" % what)
	_failures += 1


func _finish() -> bool:
	if _failures == 0:
		print("\ncontract vote bench: all good.")
	else:
		print("\ncontract vote bench: %d failed." % _failures)
	quit(1 if _failures > 0 else 0)
	return true
