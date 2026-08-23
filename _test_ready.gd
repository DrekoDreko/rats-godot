extends SceneTree
## Ready bench: the show of hands that ends a phase, and the two ways it can end
## without one.
##
## Run with: godot --headless --script _test_ready.gd
##
## One machine and no wire, so `PhaseManager.is_host()` answers true throughout
## and every request goes down the host's own road rather than over `rpc_id` —
## which is the path a solo game takes anyway, and is the one that can be checked
## without two processes. What cannot be checked here is a client's packet being
## refused; that is the acceptance test of the card and is done by hand with two
## instances open. What *can* be checked is everything the refusal is built out
## of: that a flag is only ever written by the host's `_apply`, that a request
## for somebody else's flag is turned down, that the crew being all green moves
## the shift, that the clock moves it anyway, and that a man who walks out stops
## being somebody the others are waiting on.
##
## The van and the house are later cards, so the phase machine is pointed at
## scenes that exist for the length of the bench, exactly as `_test_phase.gd`
## does. What is under test is the show of hands, not the artwork.

## Frames of slack to let a scene change actually happen.
const WAIT := 8

## Stand-in Steam IDs, as in the other benches.
const ANA := 111
const BRUNO := 222
const CARLA := 333

## Scenes that exist today, standing in for the van and the house.
const VAN := "res://scenes/lobby.tscn"
const HOUSE := "res://scenes/ps1.tscn"

## The board itself, so that the card's own node is exercised and not only the
## autoload under it.
const STATION := "res://scenes/ready_station.tscn"

## The autoloads. In a bench run with `--script` the global names do not exist
## yet — the MainLoop script is compiled before the autoloads enter the tree —
## so they are picked up by node name.
var _session: Node
var _phase: Node
var _ready_manager: Node

var _changes: Array[Array] = []
var _flags: Array[Array] = []
var _refusals: Array[String] = []

var _station: Node3D

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	# Headless runs at thousands of frames a second, which would spend a
	# sixty-second phase between two of them. A real frame rate is what makes a
	# clock measurable at all.
	Engine.max_fps = 60

	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_ready_manager = root.get_node_or_null("ReadyManager")
	if _session == null or _phase == null or _ready_manager == null:
		return

	_phase.phase_changed.connect(func(before: int, after: int) -> void:
		_changes.append([before, after]))
	_ready_manager.ready_changed.connect(func(id: int, value: bool) -> void:
		_flags.append([id, value]))
	_ready_manager.request_refused.connect(func(reason: String) -> void:
		_refusals.append(reason))


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_start()
		1: return _check_one_man_does_not_move_the_van()
		2: return _check_the_last_man_moves_it()
		3: return _check_a_flag_does_not_survive_the_phase()
		4: return _check_nobody_speaks_for_anybody_else()
		5: return _check_a_wrong_phase_refuses()
		6: return _check_the_clock_moves_it_anyway()
		7: return _check_a_man_who_leaves_stops_holding_it()
		8: return _check_blocked_holds_the_van()
		9: return _check_the_board()
	return _finish()

# --- Steps -----------------------------------------------------------------

## Nothing has been said yet. The crew is in the van, the board means something
## there, and nobody is ready.
func _check_start() -> bool:
	if _ready_manager == null:
		print("FAIL: ReadyManager is not in the tree")
		return _finish()

	# Pointed at scenes that exist, as in the phase bench.
	_phase.scenes[Phase.Type.LOBBY] = VAN
	_phase.scenes[Phase.Type.TRAVEL] = VAN
	_phase.set_house(HOUSE)

	# A van with nothing signed does not leave (card 08), and every step below
	# is about the show of hands rather than about the contract. So the hold is
	# taken off here, once, as a precondition — `_check_blocked_holds_the_van`
	# is the step that puts it back and measures what it does.
	_ready_manager.blocked = false

	_session.register_player(ANA, "Ana", true)
	_session.register_player(BRUNO, "Bruno")

	_expect(_phase.is_host(), "with no wire, the only player is his own host")
	_expect(_phase.current() == Phase.Type.LOBBY, "the shift starts in the van")
	_expect(_ready_manager.is_active(), "where a show of hands means something")
	_expect(_ready_manager.counts() == [0, 2], "nobody of two has said it")
	_expect(not _ready_manager.is_ready(ANA), "not the host")
	_expect(not _ready_manager.is_ready(BRUNO), "and not the other one")
	return _advance()

## One of two saying it does not take the van anywhere, and the flag that was set
## was written by the host rather than by whoever asked.
func _check_one_man_does_not_move_the_van() -> bool:
	if _clock == 1:
		_flags.clear()
		_changes.clear()
		_ready_manager.request_set(ANA, true)
		return false
	if _clock < WAIT:
		return false

	_expect(_ready_manager.is_ready(ANA), "the man who asked is ready")
	_expect(_flags == [[ANA, true]], "and it was announced once, by the host")
	_expect(_ready_manager.counts() == [1, 2], "one of two")
	_expect(_changes.is_empty(), "which is not enough to move the van")
	_expect(_phase.current() == Phase.Type.LOBBY, "so it is still parked")

	# Asking for the flag it already holds is not a change and should wake
	# nobody: a board pressed twice in a frame is a board pressed once.
	_flags.clear()
	_ready_manager.request_set(ANA, true)
	_expect(_flags.is_empty(), "asking for the flag he already has announces nothing")

	# And the other way, which is what `request_toggle` does off a board.
	_flags.clear()
	_ready_manager.request_toggle(ANA)
	_expect(_flags == [[ANA, false]], "a second press stands him down again")
	_expect(not _ready_manager.is_ready(ANA), "and he is not ready any more")
	return _advance()

## The acceptance test of the card, first half: the phase moves when the last man
## says it, and not before.
func _check_the_last_man_moves_it() -> bool:
	if _clock == 1:
		_changes.clear()
		_ready_manager.request_set(ANA, true)
		_expect(_phase.current() == Phase.Type.LOBBY, "one of two is still one of two")
		_ready_manager.request_set(BRUNO, true)
		return false
	if _clock < WAIT:
		return false

	_expect(_changes.size() == 1, "the van left once and not twice")
	_expect(_phase.current() == Phase.Type.TRAVEL, "with both men ready, it is on the road")
	_expect(_changes[0] == [Phase.Type.LOBBY, Phase.Type.TRAVEL], "and said where it came from")
	return _advance()

## Being ready to leave the van is not being ready to walk into the house. The
## flags are cleared on the way through, or the next phase would end the instant
## it began.
func _check_a_flag_does_not_survive_the_phase() -> bool:
	_expect(not _ready_manager.is_ready(ANA), "nobody arrives on the road already ready")
	_expect(not _ready_manager.is_ready(BRUNO), "neither of them")
	_expect(_ready_manager.counts() == [0, 2], "the count starts over")
	_expect(_ready_manager.is_active(), "and the board on the road means something too")
	return _advance()

## A player may move his own flag and nobody else's. There is no wire here to
## carry somebody else's peer id, so the guard is called with one directly —
## which is the packet the card asks to be sure of.
func _check_nobody_speaks_for_anybody_else() -> bool:
	# Peer 2 is introduced as Bruno, the way a real peer introduces itself the
	# moment the wire comes up (`LobbyManager._introduce`). What must not happen
	# is that peer moving a flag that is not his.
	var lobby: Node = root.get_node_or_null("LobbyManager")
	if lobby == null:
		print("FAIL: LobbyManager is not in the tree")
		return _advance()
	lobby.remember_identity(2, BRUNO, "Bruno")
	_expect(lobby.steam_id_of_peer(2) == BRUNO, "the wire knows peer 2 is Bruno")

	_flags.clear()
	_ready_manager._handle_request(ANA, true, 2)
	_expect(_flags.is_empty(), "a peer known to be Bruno cannot mark Ana ready")
	_expect(not _ready_manager.is_ready(ANA), "so her flag did not move")

	_ready_manager._handle_request(BRUNO, true, 2)
	_expect(_flags == [[BRUNO, true]], "though he can mark himself")
	_ready_manager.request_set(BRUNO, false)
	return _advance()

## A board that survived into the hunt is not a vote. It refuses out loud, so
## that the man who pressed it hears why.
func _check_a_wrong_phase_refuses() -> bool:
	if _clock == 1:
		_phase.go_to(Phase.Type.HUNT)
		return false
	if _clock < WAIT:
		return false
	if _clock == WAIT:
		_expect(not _ready_manager.is_active(), "the hunt is not waiting on a show of hands")
		_flags.clear()
		_refusals.clear()
		_changes.clear()
		_ready_manager.request_set(ANA, true)
		return false
	if _clock < WAIT * 2:
		return false

	_expect(_flags.is_empty(), "so no flag moved")
	_expect(_refusals.size() == 1, "and the man who asked was told why")
	_expect(not _ready_manager.is_ready(ANA), "he is not ready in the hunt")
	_expect(_changes.is_empty(), "and nothing walked the shift on")
	return _advance()

## The other way out of a phase: the clock. It moves the shift with nobody ready,
## which is the rule that stops one player who wandered off from holding the
## others in the van forever. The phase machine already owned this; what is
## checked here is that the ready system did not get in its way.
func _check_the_clock_moves_it_anyway() -> bool:
	if _clock == 1:
		_phase.go_to(Phase.Type.SURVEY)
		return false
	if _clock == WAIT:
		_expect(_ready_manager.is_active(), "the survey takes a show of hands")
		_expect(_ready_manager.counts() == [0, 2], "which nobody has given")
		_changes.clear()
		# A fifth of a second of phase rather than a minute, so the bench does
		# not sit here. What is under test is the timeout, not the number.
		_phase._timer.stop()
		_phase._timer.start(0.2)
		return false
	if _clock < 40:
		return false

	_expect(_changes.size() == 1, "the clock ran out and moved the shift once")
	_expect(_phase.current() == Phase.Type.HUNT, "into the hunt")
	_expect(_ready_manager.counts() == [0, 2], "with nobody having said a word")
	return _advance()

## A man who walks out cannot hold the door. Two in the van, one ready, one
## quits — and the van leaves on the strength of the one who is left.
func _check_a_man_who_leaves_stops_holding_it() -> bool:
	if _clock == 1:
		_phase.go_to(Phase.Type.LOBBY)
		return false
	if _clock == WAIT:
		_session.register_player(CARLA, "Carla")
		_expect(_ready_manager.counts() == [0, 3], "three in the van")
		_ready_manager.request_set(ANA, true)
		_ready_manager.request_set(BRUNO, true)
		_changes.clear()
		_expect(_phase.current() == Phase.Type.LOBBY, "two of three does not move it")
		# Carla shuts the game. Nobody is waiting on her any more.
		_session.remove_player(CARLA)
		return false
	if _clock < WAIT * 2:
		return false

	_expect(_changes.size() == 1, "the van left once the man missing was gone")
	_expect(_phase.current() == Phase.Type.TRAVEL, "and it is on the road")
	return _advance()

## The van held on purpose: a lobby with no contract signed cannot leave, however
## green the crew goes. It is the hook the contract card hangs off, and letting
## it go with everybody already ready has to move the shift there and then.
func _check_blocked_holds_the_van() -> bool:
	if _clock == 1:
		_phase.go_to(Phase.Type.LOBBY)
		return false
	if _clock == WAIT:
		_ready_manager.blocked = true
		_changes.clear()
		_ready_manager.request_set(ANA, true)
		_ready_manager.request_set(BRUNO, true)
		return false
	if _clock == WAIT + 1:
		_expect(_ready_manager.counts() == [2, 2], "both men go green")
		_expect(_changes.is_empty(), "but the van is held")
		_expect(_phase.current() == Phase.Type.LOBBY, "and stays parked")
		_ready_manager.blocked = false
		return false
	if _clock < WAIT * 3:
		return false

	_expect(_changes.size() == 1, "letting it go moves the shift on the spot")
	_expect(_phase.current() == Phase.Type.TRAVEL, "without anybody pressing anything again")
	return _advance()

## The board itself: the node the player actually slaps. What is checked is that
## it reads the crew rather than deciding anything — press it, and the flag it
## moves is the one the host wrote.
##
## The board asks after *our own* Steam ID, so the bench puts whoever is running
## it into the crew rather than pretending to be Ana. With Steam up that is the
## real account; without it, `get_steam_id` answers zero and the board falls back
## to the only man in the van — and `_me()` picks whichever of the two this
## machine is, so the step reads the same either way.
##
## Ana stays in the van beside him for the length of the step, and that is not
## dressing: a crew of one goes all-ready on the first press, which would walk
## the shift on and clear the very flag being looked at.
func _check_the_board() -> bool:
	if _clock == 1:
		_phase.go_to(Phase.Type.LOBBY)
		return false
	if _clock == WAIT:
		# Whoever the board will speak for goes in the crew, and Carla stands
		# beside him so that the van is two men and does not leave on one press.
		# `_me()` is Ana herself when there is no Steam behind the bench, and
		# registering her twice is a name correction rather than a second body —
		# which is exactly why `register_player` was written to allow it.
		_session.register_player(_me(), "the man at the board")
		_session.register_player(CARLA, "Carla")
		_expect(_session.count() >= 2, "two in the van, so one press does not empty it")
		_station = (load(STATION) as PackedScene).instantiate()
		root.add_child(_station)
		return false
	if _clock == WAIT + 1:
		_expect(_station.is_in_group("ready_station"), "a board can be found by its group")
		_expect(_station.prompt == "ready up", "and offers to ready up while it is red")

		_flags.clear()
		_changes.clear()
		_station.use(null)
		return false
	if _clock < WAIT * 2:
		return false

	_expect(_flags == [[_me(), true]], "pressing it asks the host, once, for our own flag")
	_expect(_ready_manager.is_ready(_me()), "and the host is who set it")
	_expect(not _ready_manager.is_ready(CARLA), "nobody else's flag moved with it")
	_expect(_changes.is_empty(), "one of two does not take the van anywhere")
	_expect(_station.prompt == "stand down", "and a green board offers to stand down")

	_flags.clear()
	_station.use(null)
	_expect(_flags == [[_me(), false]], "a second press stands him down")
	_expect(_station.prompt == "ready up", "and the board goes back to red")
	_station.queue_free()
	return _advance()

# --- Plumbing --------------------------------------------------------------

## Whose flag the board would ask after on this machine — the same answer
## `ReadyStation._our_steam_id` works out, and worked out the same way so that
## the bench passes whether or not Steam is running behind it. With Steam up it
## is the real account; without it the board falls back to the only man in the
## crew, who by then is Ana.
func _me() -> int:
	var steam: Node = root.get_node_or_null("SteamManager")
	var steam_id: int = steam.get_steam_id() if steam != null else 0
	return steam_id if steam_id != 0 else ANA


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
