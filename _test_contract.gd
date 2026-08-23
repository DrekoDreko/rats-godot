extends SceneTree
## Contract board bench: the jobs on disk, the one signature that settles them,
## and the rule that only the leader may make it.
##
## Run with: godot --headless --script _test_contract.gd
##
## One machine and no wire, which means `PhaseManager.is_host()` answers true
## throughout — an offline peer is his own host, and that is the path a solo
## game takes anyway. What cannot be checked here is a client being turned
## down over the wire; that is the acceptance test of the card and is done by
## hand with two instances open. What *can* be checked here is everything the
## refusal is built out of: that the board is read off disk in an order every
## machine agrees on, that signing points the phase machine at the house, that
## an unsigned board holds the van shut, and that the whole of it survives a
## scene change.

## Stand-in Steam IDs, as in the other benches.
const ANA := 111
const BRUNO := 222

## Frames of slack to let a scene change actually happen.
const WAIT := 8

## Scenes that exist today, standing in for the van and the house.
const VAN := "res://scenes/lobby.tscn"

## The autoloads. In a bench run with `--script` the global names do not exist
## yet, so they are picked up by node name on the first physics frame.
var _session: Node
var _phase: Node
var _ready_manager: Node
var _contract: Node

var _signed: Array[String] = []
var _refusals: Array[String] = []

var _frames := 0
var _step := 0
var _failures := 0


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_frames += 1
	# Everything is done from here rather than `_initialize`, because the
	# autoloads' own `_ready` has not run at that point and anything written
	# then is wiped by it a moment later.
	if _frames == 1:
		return _boot()
	if _frames < 3:
		return false
	match _step:
		0: return _step_board()
		1: return _step_blocks_the_van()
		2: return _step_only_the_leader()
		3: return _step_signing()
		4: return _step_survives_the_scene()
	return _finish()


## Picks the autoloads up and puts a crew in the van.
func _boot() -> bool:
	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_ready_manager = root.get_node_or_null("ReadyManager")
	_contract = root.get_node_or_null("ContractManager")
	if _contract == null or _session == null or _phase == null or _ready_manager == null:
		print("FAIL: an autoload is missing — is ContractManager registered?")
		_failures += 1
		return _finish()

	_contract.contract_signed.connect(func(id: String) -> void: _signed.append(id))
	_contract.request_refused.connect(func(why: String) -> void: _refusals.append(why))

	_session.register_player(ANA, "Ana", true)
	_session.register_player(BRUNO, "Bruno")
	return false


## The board itself: read off disk, in the order every machine will agree on.
func _step_board() -> bool:
	var count: int = _contract.count()
	_check(count >= 3, "the board carries the three test jobs (found %d)" % count)

	var difficulties: Array[int] = []
	var ids: Array[String] = []
	for index in count:
		var job: Contract = _contract.at(index)
		difficulties.append(job.difficulty)
		ids.append(job.id)
	var sorted := difficulties.duplicate()
	sorted.sort()
	_check(difficulties == sorted,
		"the board is sorted easiest first %s" % [difficulties])
	_check(ids.size() == _dedup(ids).size(), "every job has its own id %s" % [ids])

	# Past either end of the board is null and not a crash: the clipboard leafs
	# by index and must be able to ask about a page that is not there.
	_check(_contract.at(-1) == null and _contract.at(count) == null,
		"a page off the end of the board is null")
	_check(_contract.find("no_such_job") == null, "an unknown id finds nothing")
	_check(not _contract.is_signed(), "nothing is signed on the way up")

	_step += 1
	return false


## An unsigned board holds the van shut, however ready the crew says it is.
func _step_blocks_the_van() -> bool:
	_check(_ready_manager.blocked, "an unsigned board holds the ready boards")

	_ready_manager.request_set(ANA, true)
	_ready_manager.request_set(BRUNO, true)
	_check(_session.all_ready(), "the crew can still go green while it is held")
	_check(_phase.current() == Phase.Type.LOBBY,
		"the van does not leave with nothing signed (phase %s)"
			% Phase.name_of(_phase.current()))

	_step += 1
	return false


## Only the leader signs. The host path cannot be refused on one machine, so
## what is checked here is the two refusals that do not depend on a wire: a job
## nobody has, and a board that has closed.
func _step_only_the_leader() -> bool:
	_refusals.clear()
	_contract.request_sign("no_such_job")
	_check(_signed.is_empty(), "a job that is not on the board is not signed")
	_check(_refusals.has(_contract.REFUSAL_UNKNOWN),
		"and the man who asked is told why %s" % [_refusals])

	_check(_contract.may_sign(), "the host may sign")
	_check(_contract.is_open(), "the board is open in the lobby")

	# The crew is stood down again before the next step. The step above proved
	# that a green crew waits on the signature; leaving them green would mean
	# the signature takes the van down the road mid-bench, and what is being
	# measured after this is the signature itself and not what follows it.
	_ready_manager.request_set(ANA, false)
	_ready_manager.request_set(BRUNO, false)
	_check(not _session.all_ready(), "the crew stands down again")

	_step += 1
	return false


## The signature: written down, announced once, and the house pointed at.
func _step_signing() -> bool:
	var job: Contract = _contract.at(0)
	_signed.clear()
	_refusals.clear()
	_contract.request_sign(job.id)

	_check(_signed == [job.id], "signing announces the job once %s" % [_signed])
	_check(_session.current_contract == job.id, "and writes it on the session")
	_check(_contract.current() != null and _contract.current().id == job.id,
		"and it reads back off the board")
	_check(_phase.scene_of(Phase.Type.SURVEY) == job.house_scene,
		"the survey is pointed at the house")
	_check(_phase.scene_of(Phase.Type.HUNT) == job.house_scene,
		"and so is the hunt, at the same path — or the traps go in the bin")
	_check(not _ready_manager.blocked, "and the hold comes off the ready boards")

	# Signing the same job twice is a no-op rather than a second announcement,
	# so that a double press does not repaint every sheet in the van twice.
	_signed.clear()
	_contract.request_sign(job.id)
	_check(_signed.is_empty(), "signing the same job again announces nothing")

	_step += 1
	return false


## The whole point of the autoload: the signature outlives the scene it was made
## in. A van that forgets the contract on the way to the road is the bug this
## card is written to prevent.
func _step_survives_the_scene() -> bool:
	var before: String = _session.current_contract
	var house: String = _phase.scene_of(Phase.Type.SURVEY)
	change_scene_to_file(VAN)
	await_frames()
	_check(_session.current_contract == before,
		"the contract survives a scene change (%s)" % _session.current_contract)
	_check(_phase.scene_of(Phase.Type.SURVEY) == house,
		"and so does the house it points at")
	_check(_contract.current() != null, "and it still reads back off the board")

	_step += 1
	return false


## Waits a handful of frames by counting them out — a bench has no `await`
## without an object to await on, and the frame counter is already here.
func await_frames() -> void:
	var until := _frames + WAIT
	while _frames < until:
		_frames += 1


func _check(condition: bool, what: String) -> void:
	if condition:
		print("  ok   %s" % what)
		return
	print("  FAIL %s" % what)
	_failures += 1


## The unique entries of a list, for the id check above.
func _dedup(items: Array[String]) -> Array[String]:
	var seen: Array[String] = []
	for item in items:
		if not seen.has(item):
			seen.append(item)
	return seen


func _finish() -> bool:
	if _failures == 0:
		print("\ncontract bench: all good.")
	else:
		print("\ncontract bench: %d failed." % _failures)
	quit(1 if _failures > 0 else 0)
	return true
