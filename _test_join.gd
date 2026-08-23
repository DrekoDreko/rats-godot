extends SceneTree
## Join bench: the door of the van — who is let in, what he is handed on the way
## through, and what is cleared up behind him when he goes.
##
## Run with: godot --headless --script _test_join.gd
##
## One machine and no wire, which is the honest limit of what can be checked
## here. The card's own acceptance test — an invite going out over the Steam
## overlay to a second account, and that account seeing the colours and the
## contract already settled before it spawns — needs two Steam clients and is
## done by hand (the recipe is in the README).
##
## What *can* be checked on one machine is everything the host decides, and that
## is most of the card: the rules at the door (`is_open`, `refusal_reason`), the
## packet a newcomer is handed (`_snapshot`), what a machine does with one when
## it lands (`_apply_welcome`), and the clean-up after somebody leaves. Those are
## plain functions on the host's side of the wire, so they are called directly —
## the same way the ready bench calls `_handle_request` rather than building a
## peer to send one.
##
## **Nothing in here names a `class_name` of the project, and nothing names an
## autoload by its global name.** A bench is the `MainLoop`, so it is compiled
## before the autoloads are in the tree and before the global class list is
## built. Autoloads are picked up off `root` by node name.

## Scenes that exist today, standing in for the van and the house — the phase
## machine has to be pointed at something loadable or a phase change is an error
## in the log rather than a phase change.
const VAN := "res://scenes/lobby.tscn"
const HOUSE := "res://scenes/ps1.tscn"

## The radio, so that the card's own fitting is exercised and not only the
## autoload under it. It is loaded out of the van rather than from a scene of its
## own, the way the colour panel is.
const LOBBY_VAN := "res://scenes/lobby_van.tscn"

## Stand-in Steam IDs, as in the other benches. Real ones are nineteen digits;
## any distinct non-zero numbers do the same job.
const ANA := 111
const BRUNO := 222
const CARLA := 333
const DANI := 444
const EDU := 555

## Frames of slack for a scene to stand up, or for a phase change to land.
const WAIT := 8

## The phase enum, by value. The bench cannot name `Phase.Type` for the reason in
## the header, and these are the five in `scripts/session/phase.gd`.
const LOBBY := 0
const TRAVEL := 1
const SURVEY := 2

var _session: Node
var _phase: Node
var _gate: Node
var _colors: Node
var _ready_manager: Node

var _admitted: Array[int] = []
var _refusals: Array[String] = []
var _left: Array[int] = []

var _van: Node3D
var _radio: Node3D

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	Engine.max_fps = 60

	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_gate = root.get_node_or_null("JoinGate")
	_colors = root.get_node_or_null("ColorManager")
	_ready_manager = root.get_node_or_null("ReadyManager")
	if _gate == null or _session == null:
		return

	_gate.player_admitted.connect(func(id: int) -> void: _admitted.append(id))
	_gate.refused.connect(func(reason: String) -> void: _refusals.append(reason))
	_session.player_left.connect(func(id: int) -> void: _left.append(id))


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_start()
		1: return _check_the_host_lets_himself_in()
		2: return _check_a_knock_is_let_in()
		3: return _check_the_welcome_carries_the_shift()
		4: return _check_a_full_van_is_refused()
		5: return _check_a_shift_under_way_is_refused()
		6: return _check_a_nameless_knock_is_refused()
		7: return _check_a_welcome_is_written_down()
		8: return _check_a_man_who_leaves_is_cleared_up()
		9: return _check_the_radio()
	return _finish()

# --- Steps -----------------------------------------------------------------

## The door before anybody is at it. An empty van in the lobby phase is open, and
## has nothing to say about why it would not be.
func _check_start() -> bool:
	if _gate == null or _phase == null:
		print("FAIL: the session autoloads are not in the tree")
		return _finish()

	# Pointed at scenes that exist, as in the phase and ready benches.
	_phase.scenes[LOBBY] = VAN
	_phase.scenes[TRAVEL] = VAN
	_phase.set_house(HOUSE)
	_session.reset()

	_expect(_phase.is_host(), "with no wire, the only player is his own host")
	_expect(_phase.current() == LOBBY, "the shift starts in the van")
	_expect(_gate.is_open(), "an empty van in the lobby takes newcomers")
	_expect(_gate.refusal_reason().is_empty(), "and has no reason not to")
	_expect(_session.count() == 0, "with nobody in it yet")
	return _advance()


## The host never knocks — there is nobody to knock at — so `knock()` on his
## machine is where his own crew entry comes from. It is the same entry a client
## gets, made the same way, which is what keeps a solo run from being a second
## set of rules.
func _check_the_host_lets_himself_in() -> bool:
	_gate.admitted = false
	_gate.knock()

	_expect(_gate.admitted, "the host is in the moment he asks")
	_expect(_session.count() == 1, "and is the whole of the crew")
	var host_id: int = _session.host_id()
	_expect(host_id != 0, "somebody in the crew is marked as the host")
	_expect(_session.player(host_id).get("is_host", false), "and it is him")

	# A second knock is not a second man. The packet can genuinely arrive twice.
	_gate.knock()
	_expect(_session.count() == 1, "knocking twice does not fill the van twice")
	return _advance()


## A newcomer at the door, handled the way the host handles one off the wire.
## `_handle_knock` is called directly for the reason the ready bench calls
## `_handle_request` directly: it is the host's decision, and the wire only
## carries it there.
func _check_a_knock_is_let_in() -> bool:
	if _clock == 1:
		_admitted.clear()
		_refusals.clear()
		# Peer zero is a machine with nobody to lie to, which is what the host's
		# own calls arrive as. It is the road a bench has to the handler.
		_gate._handle_knock(BRUNO, "Bruno", 0)
		return false
	if _clock < WAIT:
		return false

	_expect(_session.has_player(BRUNO), "the newcomer is in the crew")
	_expect(_session.player(BRUNO).get("name", "") == "Bruno", "under the name he gave")
	_expect(not _session.player(BRUNO).get("is_host", true), "and not as the host")
	_expect(_admitted.has(BRUNO), "and it was announced")
	_expect(_refusals.is_empty(), "with nobody turned away")

	# The one rule the door has to keep on the way in: no two men in one colour.
	var host_id: int = _session.host_id()
	_expect(_session.color(BRUNO) != _session.color(host_id),
		"the newcomer is not wearing the host's colour")
	return _advance()


## The packet a newcomer is handed. It has to carry the whole shift — the crew
## with their colours, the contract and the phase — because the van reads all
## three the frame it comes up.
func _check_the_welcome_carries_the_shift() -> bool:
	_session.set_contract("test_contract")
	_session.set_money(BRUNO, 250)
	_session.add_item(BRUNO, "broom")

	var snapshot: Dictionary = _gate._snapshot()
	var crew: Array = snapshot.get("crew", [])

	_expect(crew.size() == _session.count(), "the packet holds the whole crew")
	_expect(snapshot.get("contract", "") == "test_contract", "and the contract that was signed")
	_expect(snapshot.get("phase", -1) == LOBBY, "and where the shift is standing")
	_expect(snapshot.has("seed"), "and the number the house is built from")

	var bruno: Dictionary = _entry_for(crew, BRUNO)
	_expect(not bruno.is_empty(), "the newcomer is in the packet")
	_expect(bruno.get("name", "") == "Bruno", "by name")
	_expect(bruno.get("color", Color.WHITE) == _session.color(BRUNO), "in the colour he is wearing")
	_expect(int(bruno.get("money", 0)) == 250, "with the money in his pocket")
	_expect(Array(bruno.get("inventory", [])).has("broom"), "and what is in his bag")
	return _advance()


## Four is the van. Steam turns the fifth away at its own door; this is the check
## for the machine that got through while the crew was still filling up.
func _check_a_full_van_is_refused() -> bool:
	if _clock == 1:
		_refusals.clear()
		_gate._handle_knock(CARLA, "Carla", 0)
		_gate._handle_knock(DANI, "Dani", 0)
		return false
	if _clock < WAIT:
		return false

	_expect(_session.count() == 4, "four men fill the van")
	_expect(not _gate.is_open(), "which closes the door")
	_expect(_gate.refusal_reason() == _gate.REFUSAL_FULL, "and says why")

	_refusals.clear()
	_gate._handle_knock(EDU, "Edu", 0)
	_expect(not _session.has_player(EDU), "the fifth man is not let in")
	_expect(_refusals == [_gate.REFUSAL_FULL], "and is told the van is full, once")

	# Room for him the moment somebody steps out.
	_gate.drop_player(DANI)
	return _advance()


## A shift already on the road does not take passengers. The man is told so in a
## sentence rather than left waiting — the "polite refusal" the card asks for.
func _check_a_shift_under_way_is_refused() -> bool:
	if _clock == 1:
		_phase.go_to(TRAVEL)
		return false
	if _clock < WAIT:
		return false

	_expect(_phase.current() == TRAVEL, "the van has left")
	_expect(not _gate.is_open(), "so the door is shut")
	_expect(_gate.refusal_reason() == _gate.REFUSAL_IN_PROGRESS, "because the shift is under way")

	_refusals.clear()
	var before: int = _session.count()
	_gate._handle_knock(EDU, "Edu", 0)
	_expect(not _session.has_player(EDU), "a man who knocks on the road is not let in")
	_expect(_session.count() == before, "and the crew did not change")
	_expect(_refusals == [_gate.REFUSAL_IN_PROGRESS], "he is told why, in a sentence")

	# Back to the van for the rest of the bench.
	_phase.go_to(LOBBY)
	return _advance()


## A knock with no Steam ID on it is a machine whose introduction never landed.
## Filing a crew entry under zero would be a man nobody can address afterwards,
## so it is refused rather than written.
func _check_a_nameless_knock_is_refused() -> bool:
	if _clock < WAIT:
		return false

	_expect(_phase.current() == LOBBY, "back in the van")
	_expect(_gate.is_open(), "with the door open again")

	_refusals.clear()
	var before: int = _session.count()
	_gate._handle_knock(0, "nobody", 0)
	_expect(_session.count() == before, "a knock with no account behind it adds nobody")
	_expect(_refusals == [_gate.REFUSAL_UNKNOWN], "and is turned away with a sentence")
	return _advance()


## The other half of the handshake: what a *client* does with a welcome when one
## lands. It is the acceptance test of the card as far as one machine can reach
## it — the crew, the colours and the contract are all in place before anything
## is drawn.
func _check_a_welcome_is_written_down() -> bool:
	# A packet as the host would build it, with a crew this machine has never
	# heard of and a man already wearing a colour of his own.
	var welcome := {
		"crew": [
			{
				"steam_id": ANA, "name": "Ana", "color": Color("ff2d2d"),
				"ready": true, "money": 400, "inventory": ["broom"] as Array[String],
				"is_host": true,
			},
			{
				"steam_id": CARLA, "name": "Carla", "color": Color("29c443"),
				"ready": false, "money": 75, "inventory": [] as Array[String],
				"is_host": false,
			},
		],
		# A real job off the board. The welcome is written through
		# `ContractManager`, which refuses an id nobody has — so a made-up
		# string here would test the refusal rather than the welcome.
		"contract": "hallow_street",
		"phase": LOBBY,
		"seed": 4242,
	}

	# The ready system would walk the phase on the moment it saw a crew where
	# everybody is ready, which is not what is under test here.
	_ready_manager.blocked = true
	_gate._apply_welcome(welcome)

	_expect(_session.count() == 2, "the crew is exactly what the host said it was")
	_expect(_session.has_player(ANA) and _session.has_player(CARLA), "both of them by name")
	_expect(not _session.has_player(BRUNO), "and nobody left over from before")
	_expect(_session.color(ANA) == Color("ff2d2d"), "wearing the colour the host gave them")
	_expect(_session.color(CARLA) == Color("29c443"), "each of them")
	_expect(_session.is_ready(ANA), "with the flags they had already raised")
	_expect(not _session.is_ready(CARLA), "and the ones they had not")
	_expect(_session.money(CARLA) == 75, "and the money in their pockets")
	_expect(_session.inventory(ANA).has("broom"), "and what is in their bags")
	_expect(_session.current_contract == "hallow_street", "the contract is settled")
	# Settled means more than copied: a newcomer has to arrive with the house
	# the contract points at, or he stands in a van whose next scene is the
	# placeholder everybody else left behind.
	# The autoload is picked up by node name: in a bench run with `--script` the
	# global names do not exist yet.
	var contracts := root.get_node_or_null("ContractManager")
	var job: Contract = contracts.find("hallow_street") if contracts != null else null
	_expect(job != null and _phase.scene_of(Phase.Type.SURVEY) == job.house_scene,
		"and it brought the house with it")
	_expect(_session.random_seed == 4242, "and the house is the same house")
	_expect(_session.host_id() == ANA, "the host is who the host said he was")
	_expect(_gate.admitted, "and we are in")
	_ready_manager.blocked = false
	return _advance()


## A man who walks out stops being somebody the others are waiting on. His entry
## goes, which is what puts his colour back on the rack, and whoever is left is
## asked again whether they are all ready.
func _check_a_man_who_leaves_is_cleared_up() -> bool:
	if _clock == 1:
		_session.reset()
		_ready_manager.blocked = true
		_gate._handle_knock(ANA, "Ana", 0)
		_gate._handle_knock(BRUNO, "Bruno", 0)
		return false
	if _clock < WAIT:
		return false

	var bruno_color: Color = _session.color(BRUNO)
	_expect(_session.count() == 2, "two men in the van")
	_expect(_session.is_color_taken(bruno_color), "and the second one's colour is spoken for")

	_left.clear()
	_gate.drop_player(BRUNO)

	_expect(not _session.has_player(BRUNO), "the man who left is out of the crew")
	_expect(_left == [BRUNO], "and it was announced, once")
	_expect(_session.count() == 1, "leaving whoever is still here")
	_expect(not _session.is_color_taken(bruno_color), "his colour is back on the rack")

	# And the door is open again, which is the whole reason the count matters.
	_expect(_gate.is_open(), "so there is room for somebody else")
	_ready_manager.blocked = false
	return _advance()


## The radio on the wall of the van: the card's own fitting. What can be checked
## without a second Steam account is that it knows when there is nobody to call
## and says so instead of opening an overlay that leads nowhere.
func _check_the_radio() -> bool:
	if _clock == 1:
		_van = (load(LOBBY_VAN) as PackedScene).instantiate()
		root.add_child(_van)
		return false
	if _clock < WAIT:
		return false
	if _radio == null:
		_radio = _van.get_node_or_null("Stations/Radio") as Node3D
		if _radio == null:
			print("FAIL: there is no radio on the wall of the van")
			return _advance()

	_expect(_radio.is_in_group("radio_station"), "the radio can be found by its group")

	# No lobby is open on a bench, whether or not Steam itself is running, so the
	# line is dead and the radio should say which of the two reasons it is.
	var reason: String = _radio._closed_reason()
	_expect(not reason.is_empty(), "with no lobby open there is nobody to call")
	_expect(reason == _radio.NO_STEAM or reason == _radio.NO_LOBBY,
		"and the radio says which of the two it is")
	_expect(_radio.prompt == _radio.PROMPT_CLOSED, "a dead line offers the prompt that says so")

	# Pressing it is not a crash and not an overlay: it says why and stops.
	_radio.use(null)
	_expect(_radio.prompt == _radio.PROMPT_CLOSED, "and pressing it changes nothing")

	_van.queue_free()
	return _advance()

# --- Plumbing --------------------------------------------------------------

## One man out of a snapshot's crew list, by Steam ID, or an empty dictionary
## when he is not in it.
func _entry_for(crew: Array, steam_id: int) -> Dictionary:
	for entry in crew:
		if int(entry.get("steam_id", 0)) == steam_id:
			return entry
	return {}


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
