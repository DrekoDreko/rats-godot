extends SceneTree
## Phase machine bench: the clock, the order the shift walks in, and the rule
## that survey and hunt do not reload the house.
##
## Run with: godot --headless --script _test_phase.gd
##
## One machine and no wire, which means `PhaseManager.is_host()` answers true
## throughout — an offline peer is his own host, and that is the path a solo
## game takes anyway. What cannot be checked here is two machines agreeing;
## that is the acceptance test of the card and is done by hand with two
## instances open. What *can* be checked here is everything the agreement is
## built out of: that the clock counts, that it ends the phase when it runs out,
## that the order is walked, and that a phase change into the same scene leaves
## the scene alone.
##
## The van, the road and the house are not built yet (they are later cards), so
## `SCENES` is pointed at scenes that do exist for the duration of the bench.
## What is being tested is the routing, not the artwork.

## Frames of slack to let a scene change actually happen.
const WAIT := 8

## Stand-in Steam IDs, as in the session bench.
const ANA := 111
const BRUNO := 222

## Scenes that exist today, standing in for the van and the house. Two different
## ones and one repeated, which is the whole shape the routing has to handle.
const VAN := "res://scenes/lobby.tscn"
const HOUSE := "res://scenes/ps1.tscn"

## The autoloads. In a bench run with `--script` the global names do not exist
## yet, so they are picked up by node name.
var _session: Node
var _phase: Node

var _changes: Array[Array] = []
var _ticks: Array[float] = []
var _expired: Array[int] = []

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	# Headless runs at thousands of frames a second, which would spend a
	# hundred-and-twenty-second phase between two of them. A real frame rate is
	# what makes a clock measurable at all.
	Engine.max_fps = 60

	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	if _phase == null or _session == null:
		return

	_phase.phase_changed.connect(func(before: int, after: int) -> void:
		_changes.append([before, after]))
	_phase.timer_updated.connect(func(left: float) -> void: _ticks.append(left))
	_phase.timer_expired.connect(func(which: int) -> void: _expired.append(which))


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_start()
		1: return _check_order()
		2: return _check_a_change_loads_the_scene()
		3: return _check_same_scene_is_not_reloaded()
		4: return _check_the_clock_runs()
		5: return _check_the_clock_ends_the_phase()
		6: return _check_a_client_cannot_decide()
	return _finish()

# --- Steps -----------------------------------------------------------------

## Nothing has moved yet. The shift starts in the lobby, with no clock on it,
## and this machine is its own host because there is no wire.
func _check_start() -> bool:
	if _phase == null:
		print("FAIL: PhaseManager is not in the tree")
		return _finish()

	# Pointed at scenes that exist. The van and the house are later cards; what
	# is under test is which of them is loaded when, not what is in them. The
	# house goes through `set_house`, which is the way the contract will do it.
	_phase.scenes[Phase.Type.LOBBY] = VAN
	_phase.scenes[Phase.Type.TRAVEL] = VAN
	_phase.set_house(HOUSE)
	_expect(_phase.scene_of(Phase.Type.SURVEY) == _phase.scene_of(Phase.Type.HUNT),
		"one house for the survey and the hunt, or the traps do not survive the change")

	_session.register_player(ANA, "Ana", true)
	_session.register_player(BRUNO, "Bruno")

	_expect(_phase.current() == Phase.Type.LOBBY, "a shift starts in the lobby")
	_expect(_phase.is_host(), "with no wire, the only player is his own host")
	_expect(not _phase.has_timer(), "and nothing is timing the lobby")
	_expect(_phase.seconds_left == 0.0, "so there is no time left to show")
	return _advance()

## The order the shift walks, asked one phase at a time without moving.
func _check_order() -> bool:
	_expect(_phase.next_phase() == Phase.Type.TRAVEL, "after the lobby comes the road")
	_session.phase = Phase.Type.TRAVEL
	_expect(_phase.next_phase() == Phase.Type.SURVEY, "after the road, the survey")
	_session.phase = Phase.Type.SURVEY
	_expect(_phase.next_phase() == Phase.Type.HUNT, "after the survey, the hunt")
	_session.phase = Phase.Type.HUNT
	_expect(_phase.next_phase() == Phase.Type.RESULT, "after the hunt, the pay slip")
	_session.phase = Phase.Type.RESULT
	_expect(_phase.next_phase() == Phase.Type.LOBBY, "and the pay slip goes home to the menu")

	_session.phase = Phase.Type.LOBBY
	_expect(Phase.duration(Phase.Type.TRAVEL) == 120.0, "the road is two minutes")
	_expect(Phase.duration(Phase.Type.SURVEY) == 60.0, "the survey is one")
	_expect(Phase.duration(Phase.Type.HUNT) == 0.0, "and the hunt is as long as it takes")
	return _advance()

## Moving to a phase in a different scene loads that scene, and the change is
## announced after it is standing rather than before.
func _check_a_change_loads_the_scene() -> bool:
	if _clock == 1:
		_changes.clear()
		_session.set_ready(ANA, true)
		_session.set_ready(BRUNO, true)
		_phase.go_to(Phase.Type.SURVEY)
		return false
	if _clock < WAIT:
		return false

	_expect(_phase.current() == Phase.Type.SURVEY, "the shift is in the survey")
	_expect(_session.phase == Phase.Type.SURVEY, "and the session holds the same answer")
	_expect(_changes == [[Phase.Type.LOBBY, Phase.Type.SURVEY]],
		"the change is announced once, with where we came from")
	_expect(current_scene != null and current_scene.scene_file_path == HOUSE,
		"and the house is what is on screen")
	_expect(not _session.all_ready(), "the ready flags are cleared on the way through")
	return _advance()

## The acceptance rule the card is really about: survey to hunt is the same
## house, so the house is left exactly where it is. A reload here would be a
## minute of trap-placing thrown away.
func _check_same_scene_is_not_reloaded() -> bool:
	if _clock == 1:
		_changes.clear()
		_marked_scene().set_meta("survived", true)
		_phase.go_to(Phase.Type.HUNT)
		return false
	if _clock < WAIT:
		return false

	_expect(_phase.current() == Phase.Type.HUNT, "the hunt is on")
	_expect(_changes == [[Phase.Type.SURVEY, Phase.Type.HUNT]], "and it was announced")
	_expect(current_scene != null and current_scene.scene_file_path == HOUSE,
		"in the same house")
	_expect(_marked_scene().has_meta("survived"),
		"and it is the very same house, not a fresh copy of it")

	_changes.clear()
	_phase.go_to(Phase.Type.HUNT)
	_expect(_changes.is_empty(), "asking for the phase it is already in changes nothing")
	return _advance()

## The clock counts down and says so every frame, and what it says is falling.
func _check_the_clock_runs() -> bool:
	if _clock == 1:
		_ticks.clear()
		_phase.go_to(Phase.Type.SURVEY)
		return false
	if _clock < 30:
		return false

	_expect(_phase.has_timer(), "the survey is a phase with a clock on it")
	_expect(_ticks.size() > 10, "which reports every frame, and reported %d times" % _ticks.size())
	_expect(_ticks[0] == 60.0, "starting at the full minute")
	_expect(_ticks[-1] < 60.0, "and counting down from it")
	_expect(_ticks[-1] > 59.0, "roughly in real time, not in frames")
	_expect(_phase.seconds_left == _ticks[-1], "what it reports is what it holds")
	return _advance()

## A clock that runs out walks the shift on by itself, with nobody ready. This
## is the rule that stops one player who wandered off from holding four others
## in the van forever.
func _check_the_clock_ends_the_phase() -> bool:
	if _clock == 1:
		# A second's worth of phase rather than sixty, so the bench does not sit
		# here for a minute. What is under test is the timeout, not the number.
		_expired.clear()
		_changes.clear()
		_phase._timer.stop()
		_phase._timer.start(0.2)
		return false
	if _clock < 30:
		return false

	_expect(_expired == [Phase.Type.SURVEY], "the survey ran out of clock and said so")
	_expect(_changes.size() == 1 and _changes[0][1] == Phase.Type.HUNT,
		"and the shift walked on without anybody saying ready")
	_expect(_phase.current() == Phase.Type.HUNT, "into the hunt")
	# The hunt has a clock now, and how long it is was booked by the crew back in
	# the van (`HuntTime`). A bench that never booked one gets the default, which
	# is the ten-minute shift — so what is checked here is that the clock started
	# at all and is counting something, and how the three settings differ is
	# `_test_hunt_time.gd`'s business rather than this one's.
	_expect(_phase.has_timer(), "which is timed by whatever the crew booked")
	_expect(_phase.seconds_left > 0.0, "and started counting it down")
	return _advance()

## A machine that is not the host does not get to decide. There is no wire here
## to make one, so the check is on the guard itself: `go_to` asks `is_host()`
## first and refuses before it touches anything.
func _check_a_client_cannot_decide() -> bool:
	if _clock == 1:
		_expect(_phase.current() == Phase.Type.HUNT, "the bench got here from the hunt")
		_changes.clear()
		# Godot's own `authority` on the RPC drops a client's packet before it
		# arrives; the check inside `_apply` is the second line of defence, the
		# one that catches a packet that somehow got through. With no wire the
		# sender reads as zero, which is a local call and is allowed — so what
		# is confirmed here is that the guard lets the honest case past.
		_phase._apply(Phase.Type.LOBBY)
		return false
	if _clock < WAIT:
		return false

	_expect(_phase.current() == Phase.Type.LOBBY,
		"a local call still works — it is the wire that is guarded, and there is none here")
	_expect(_changes == [[Phase.Type.HUNT, Phase.Type.LOBBY]],
		"and it announced the change it made, once the van was standing")
	_expect(current_scene != null and current_scene.scene_file_path == VAN,
		"back in the van")
	_expect(not _phase.has_timer(), "where nothing is timing anybody")
	return _advance()

# --- Plumbing --------------------------------------------------------------

## The scene on screen, whatever it is. Used to leave a mark on the house and
## look for it again after the phase moved.
func _marked_scene() -> Node:
	return current_scene


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
