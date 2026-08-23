extends SceneTree
## Session test bench: the crew that has to survive a scene change, and the
## colours, ready flags and contract kept with it.
##
## Run with: godot --headless --script _test_session.gd
##
## No Steam and no wire here, and that is the point of the card this comes from:
## the autoload stores and announces, and nothing in it touches the network — so
## all of it can be checked on one machine with nobody signed in.
##
## The last step is the acceptance test itself: load a different scene, and look
## at the crew again on the other side of it.

## Frames of slack to let a scene change actually happen.
const WAIT := 8

## Stand-in Steam IDs. Real ones are nineteen digits; any three distinct
## non-zero numbers do the same job here.
const ANA := 111
const BRUNO := 222
const CARLA := 333

## The autoload. In a bench run with `--script` the global name does not exist
## yet — the MainLoop script is compiled before the autoloads enter the tree —
## so it is picked up by node name instead.
var _session: Node

## The ready system, held off for the length of this bench.
##
## It listens for a player leaving and asks whether whoever is left is all
## ready, because a man who walks out must not be able to hold the van at the
## door (`ReadyManager._on_player_left`). That is the right thing in a game and
## the wrong thing here: this bench sets ready flags by hand to look at what
## `SessionManager` does with them, and a phase walking on underneath it would
## clear the very flags being read. Blocking it leaves the flags alone without
## touching what is under test — the ready system has a bench of its own
## (`_test_ready.gd`), and that is where its reaction to a leaver is checked.
var _ready_manager: Node

var _joined: Array[int] = []
var _left: Array[int] = []
var _changed: Array[int] = []
var _contracts: Array[String] = []

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	_session = root.get_node_or_null("SessionManager")
	_ready_manager = root.get_node_or_null("ReadyManager")
	if _session == null:
		return
	_session.player_joined.connect(func(id: int) -> void: _joined.append(id))
	_session.player_left.connect(func(id: int) -> void: _left.append(id))
	_session.player_changed.connect(func(id: int) -> void: _changed.append(id))
	_session.contract_changed.connect(func(id: String) -> void: _contracts.append(id))


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_start()
		1: return _check_joining()
		2: return _check_colors()
		3: return _check_ready()
		4: return _check_money_and_bag()
		5: return _check_contract_and_seed()
		6: return _check_leaving()
		7: return _check_it_survives_a_scene_change()
		8: return _check_reset()
	return _finish()

# --- Steps -----------------------------------------------------------------

## Nothing has happened yet: the autoload is up, the crew is empty and the shift
## has not started.
func _check_start() -> bool:
	if _session == null:
		print("FAIL: SessionManager is not in the tree")
		return _finish()

	# Held off here and not in `_initialize`, where the autoloads are in the tree
	# but their own `_ready` has not run yet and would write over it.
	if _ready_manager != null:
		_ready_manager.blocked = true

	_expect(_session.players.is_empty(), "the crew starts empty")
	_expect(_session.count() == 0, "and counts nobody")
	_expect(_session.current_contract.is_empty(), "no contract is signed yet")
	_expect(_session.phase == Phase.Type.LOBBY, "a shift starts in the lobby")
	_expect(_session.random_seed == 0, "and with no seed rolled")
	_expect(not _session.all_ready(), "an empty crew is not a ready crew")
	_expect(_session.host_id() == 0, "and answers to nobody")
	return _advance()

## Three people walk in. The host is marked on the way, and a name that arrives
## twice corrects the entry instead of starting it over.
func _check_joining() -> bool:
	_session.register_player(ANA, "Ana", true)
	_session.register_player(BRUNO, "Bruno")
	_session.register_player(CARLA, "Carla")
	_expect(_session.count() == 3, "three in the van, and there are %d" % _session.count())
	_expect(_joined == [ANA, BRUNO, CARLA], "each arrival is announced once, in order")
	_expect(_session.has_player(BRUNO), "and can be asked after by name")
	_expect(_session.host_id() == ANA, "the one marked host is the one answered to")
	_expect(_session.player(ANA)["name"] == "Ana", "a player carries the name he came in with")
	_expect(_session.player(999).is_empty(), "and a stranger comes back empty rather than crashing")

	# The introduction genuinely arrives twice on a real wire. It should cost a
	# name correction, not the colour and money already on the entry.
	_session.set_money(BRUNO, 55)
	_joined.clear()
	_session.register_player(BRUNO, "Bruno da Van")
	_expect(_joined.is_empty(), "somebody already in the crew does not join twice")
	_expect(_session.player(BRUNO)["name"] == "Bruno da Van", "his name is corrected in place")
	_expect(_session.money(BRUNO) == 55, "and his money is left where it was")

	# A copy is handed out, so a caller scribbling on it changes nothing.
	var copy: Dictionary = _session.player(ANA)
	copy["name"] = "somebody else"
	_expect(_session.player(ANA)["name"] == "Ana", "what `player()` hands out is a copy")
	return _advance()

## Everybody walked in wearing a different colour, and the ones taken are known
## to be taken.
func _check_colors() -> bool:
	var ana: Color = _session.color(ANA)
	var bruno: Color = _session.color(BRUNO)
	var carla: Color = _session.color(CARLA)
	_expect(ana != bruno and bruno != carla and ana != carla,
		"three players walk in wearing three different colours")
	_expect(ana == _session.COLORS[0], "the first one in gets the first colour")
	_expect(bruno == _session.COLORS[1], "the second one the second")

	_expect(_session.is_color_taken(ana), "a colour somebody is wearing is taken")
	_expect(_session.color_owner(ana) == ANA, "and it is known who is wearing it")
	_expect(not _session.is_color_taken(ana, ANA), "though not taken from the man in it")
	_expect(_session.first_free_color() == _session.COLORS[3],
		"the first free colour is the first nobody is in")

	_changed.clear()
	var wanted: Color = _session.COLORS[6]
	_session.set_color(CARLA, wanted)
	_expect(_session.color(CARLA) == wanted, "a player can be put in another colour")
	_expect(_changed == [CARLA], "and the change is announced once")

	# The same colour again is not a change, and should wake nobody up.
	_changed.clear()
	_session.set_color(CARLA, wanted)
	_expect(_changed.is_empty(), "setting the colour it already is announces nothing")

	_expect(_session.color(999) == Color.WHITE, "a stranger still answers with a colour")
	return _advance()

## The ready flags, and the question the phase machine asks of them.
func _check_ready() -> bool:
	_expect(not _session.all_ready(), "nobody has said ready yet")
	_expect(_session.ready_count() == 0, "so none are counted")

	_session.set_ready(ANA, true)
	_session.set_ready(BRUNO, true)
	_expect(not _session.all_ready(), "two out of three is not everybody")
	_expect(_session.ready_count() == 2, "and counts as two")
	_expect(_session.is_ready(ANA), "the one who said it reads as ready")
	_expect(not _session.is_ready(CARLA), "the one who did not, does not")

	_session.set_ready(CARLA, true)
	_expect(_session.all_ready(), "all three said it, so the shift can move")

	# The man who never says ready is the man who left. Taking him out of the
	# crew is what unblocks the others, and is the whole of the rule.
	_session.set_ready(CARLA, false)
	_expect(not _session.all_ready(), "one man short holds the shift")
	_session.remove_player(CARLA)
	_expect(_session.all_ready(), "but only while he is still in the crew")
	_session.register_player(CARLA, "Carla")

	_changed.clear()
	_session.reset_ready()
	_expect(not _session.all_ready(), "a reset puts everybody back to not ready")
	_expect(_session.ready_count() == 0, "and counts none of them")
	_expect(_changed.size() == 2, "announcing only the two it actually moved, and said %d"
		% _changed.size())
	return _advance()

## The purse and the bag. Nothing writes to these yet — the shop is a later
## card — so what is checked is that they hold what they are given.
func _check_money_and_bag() -> bool:
	_expect(_session.money(ANA) == _session.STARTING_MONEY,
		"a player walks in with the starting money")
	_session.set_money(ANA, 40)
	_expect(_session.money(ANA) == 40, "and can be set to something else")
	_session.set_money(ANA, -10)
	_expect(_session.money(ANA) == 0, "a purse does not go below nothing")

	_expect(_session.inventory(ANA).is_empty(), "the bag starts empty")
	_changed.clear()
	_session.add_item(ANA, "mousetrap")
	_session.add_item(ANA, "mousetrap")
	_session.add_item(ANA, "")
	_expect(_session.inventory(ANA) == ["mousetrap", "mousetrap"],
		"two traps go in the bag and an empty id does not")
	_expect(_changed.size() == 2, "one word said per item that actually went in")

	var bag: Array[String] = _session.inventory(ANA)
	bag.append("shotgun")
	_expect(_session.inventory(ANA).size() == 2, "what `inventory()` hands out is a copy")
	return _advance()

## The contract and the seed: the two things about the shift itself rather than
## about a player.
func _check_contract_and_seed() -> bool:
	_contracts.clear()
	_session.set_contract("house_01")
	_expect(_session.current_contract == "house_01", "the contract is held")
	_expect(_contracts == ["house_01"], "and announced")
	_session.set_contract("house_01")
	_expect(_contracts.size() == 1, "signing the same one twice announces nothing")

	var rolled: int = _session.roll_seed()
	_expect(rolled != 0, "the seed rolls to something")
	_expect(_session.random_seed == rolled, "and is kept where everybody reads it")
	return _advance()

## Somebody walks out. The colour he was wearing goes back on the rack with him.
func _check_leaving() -> bool:
	var freed: Color = _session.color(BRUNO)
	_left.clear()
	_session.remove_player(BRUNO)
	_expect(_left == [BRUNO], "leaving is announced once")
	_expect(not _session.has_player(BRUNO), "and he is out of the crew")
	_expect(_session.count() == 2, "leaving two behind")
	_expect(not _session.is_color_taken(freed), "his colour goes back on the rack")

	_left.clear()
	_session.remove_player(BRUNO)
	_expect(_left.is_empty(), "somebody who already left does not leave twice")
	return _advance()

## The acceptance test of the card: load a different scene and look at the crew
## on the other side of it.
func _check_it_survives_a_scene_change() -> bool:
	if _clock == 1:
		_session.phase = Phase.Type.TRAVEL
		change_scene_to_file("res://scenes/ps1.tscn")
		return false
	if _clock < WAIT:
		return false
	_expect(current_scene != null and current_scene.scene_file_path.ends_with("ps1.tscn"),
		"the bench should be standing in a different scene by now")
	_expect(_session.count() == 2, "the crew is still two after the scene changed")
	_expect(_session.has_player(ANA) and _session.has_player(CARLA), "and it is the same two")
	_expect(_session.player(ANA)["name"] == "Ana", "under the same names")
	_expect(_session.money(ANA) == 0, "with the same money")
	_expect(_session.inventory(ANA) == ["mousetrap", "mousetrap"], "and the same bag")
	_expect(_session.current_contract == "house_01", "the contract came along")
	_expect(_session.random_seed != 0, "so did the seed")
	_expect(_session.phase == Phase.Type.TRAVEL, "and the phase we were in")
	print("--- across the scene change: %s ---" % _crew())
	return _advance()

## The wipe, which is where a shift ends and every bench starts.
func _check_reset() -> bool:
	_left.clear()
	_session.reset()
	_expect(_session.players.is_empty(), "a reset empties the crew")
	_expect(_left.size() == 2, "saying goodbye to each of them")
	_expect(_session.current_contract.is_empty(), "and lets the contract go")
	_expect(_session.phase == Phase.Type.LOBBY, "back to the lobby")
	_expect(_session.random_seed == 0, "with no seed")
	return _advance()

# --- Plumbing --------------------------------------------------------------

## The crew as a line of text, for the log.
func _crew() -> String:
	var rows: Array[String] = []
	for steam_id in _session.players:
		var who: Dictionary = _session.players[steam_id]
		rows.append("%s in #%s" % [who["name"], (who["color"] as Color).to_html(false)])
	return "; ".join(rows)


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
