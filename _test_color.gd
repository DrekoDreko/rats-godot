extends SceneTree
## Colour bench: the one rule of the paint wall — no two men in the same colour —
## and everything that rule is built out of.
##
## Run with: godot --headless --script _test_color.gd
##
## One machine and no wire, so `PhaseManager.is_host()` answers true throughout
## and every request goes down the host's own road rather than over `rpc_id` —
## which is the path a solo game takes anyway, and is the one that can be checked
## without two processes. What cannot be checked here is a client's packet being
## refused; that is the acceptance test of the card and is done by hand with two
## instances open. What *can* be checked is everything the refusal is built out
## of: that a colour is only ever written by the host's `_apply`, that a taken
## one is turned down, that a request for somebody else's overalls is dropped,
## that a man walking in is dressed without asking, that a man walking out puts
## his colour back on the rack, and that what he was wearing in the van is still
## on him in the house.

## Frames of slack to let a request land and a scene change happen.
const WAIT := 8

## Stand-in Steam IDs, as in the other benches.
const ANA := 111
const BRUNO := 222
const CARLA := 333

## Scenes that exist today, standing in for the van and the house.
const VAN := "res://scenes/lobby.tscn"
const HOUSE := "res://scenes/ps1.tscn"

## The menu the palette is actually dressed into, so that the control a player
## presses is exercised where it lives rather than in a scene written for the
## bench. It used to be a panel on the wall of a parked van; the van is gone and
## picking a colour is a popup on the menu now.
const MENU_SCENE := "res://scenes/menu.tscn"

## The autoloads. In a bench run with `--script` the global names do not exist
## yet — the MainLoop script is compiled before the autoloads enter the tree —
## so they are picked up by node name.
var _session: Node
var _phase: Node
var _colors: Node

var _painted: Array[Array] = []
var _refusals: Array[String] = []

var _menu: Node
var _popup: Node

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	# Headless runs at thousands of frames a second. A real frame rate is what
	# makes anything with a clock in it measurable at all.
	Engine.max_fps = 60

	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_colors = root.get_node_or_null("ColorManager")
	if _session == null or _phase == null or _colors == null:
		return

	_colors.color_changed.connect(func(id: int, color: Color) -> void:
		_painted.append([id, color]))
	_colors.request_refused.connect(func(reason: String) -> void:
		_refusals.append(reason))


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_start()
		1: return _check_a_free_colour_is_given()
		2: return _check_a_taken_colour_is_refused()
		3: return _check_his_own_colour_is_not_a_refusal()
		4: return _check_a_swatch_off_the_wall_is_dropped()
		5: return _check_nobody_dresses_anybody_else()
		6: return _check_a_man_who_leaves_frees_his_colour()
		7: return _check_the_host_seats_everybody()
		8: return _check_the_colour_survives_the_house()
		9: return _check_the_palette()
	return _finish()

# --- Steps -----------------------------------------------------------------

## Nobody has picked anything yet, and everybody is already dressed. That is the
## card's fifth point: a man walks into the lobby wearing the first free colour
## rather than wearing nothing.
func _check_start() -> bool:
	if _colors == null:
		print("FAIL: ColorManager is not in the tree")
		return _finish()

	# Pointed at scenes that exist, as in the phase bench.
	_phase.scenes[Phase.Type.LOBBY] = VAN
	_phase.scenes[Phase.Type.TRAVEL] = VAN
	_phase.set_house(HOUSE)

	_session.register_player(ANA, "Ana", true)
	_session.register_player(BRUNO, "Bruno")

	_expect(_phase.is_host(), "with no wire, the only player is his own host")
	_expect(_colors.count() == 8, "eight swatches on the wall")
	_expect(_session.color(ANA) == _colors.color_at(0), "the first man in gets the first colour")
	_expect(_session.color(BRUNO) == _colors.color_at(1), "and the second the second")
	_expect(_session.color(ANA) != _session.color(BRUNO), "which is to say, not the same one")
	_expect(not _colors.is_available(0), "the first swatch is spoken for")
	_expect(_colors.is_available(2), "the third is not")
	_expect(_colors.owner_of_index(1) == BRUNO, "and the wall knows whose the second is")
	return _advance()


## Asking for a colour nobody has takes it, and it was the host who wrote it.
func _check_a_free_colour_is_given() -> bool:
	if _clock == 1:
		_painted.clear()
		_refusals.clear()
		_colors.request_color(BRUNO, 4)
		return false
	if _clock < WAIT:
		return false

	_expect(_session.color(BRUNO) == _colors.color_at(4), "he is wearing what he asked for")
	_expect(_painted == [[BRUNO, _colors.color_at(4)]], "announced once, by the host")
	_expect(_refusals.is_empty(), "and nobody was turned down")
	_expect(_colors.is_available(1), "the one he took off is back on the rack")
	return _advance()


## Asking for one somebody else has is refused, and nothing moves. The rule the
## whole card exists for.
func _check_a_taken_colour_is_refused() -> bool:
	if _clock == 1:
		_painted.clear()
		_refusals.clear()
		# Ana has swatch 0 from the start; Bruno reaches for it.
		_colors.request_color(BRUNO, 0)
		return false
	if _clock < WAIT:
		return false

	_expect(_session.color(BRUNO) == _colors.color_at(4), "he is still in his own colour")
	_expect(_session.color(ANA) == _colors.color_at(0), "and she still has hers")
	_expect(_painted.is_empty(), "nothing was repainted")
	_expect(_refusals.size() == 1, "the man who asked heard why, once")
	_expect(_refusals[0].contains("Ana"), "and was told who has it")
	return _advance()


## Pressing the swatch you are already wearing is a man checking which one is
## his, not a mistake. No buzzer and no packet.
func _check_his_own_colour_is_not_a_refusal() -> bool:
	if _clock == 1:
		_painted.clear()
		_refusals.clear()
		_colors.request_color(BRUNO, 4)
		return false
	if _clock < WAIT:
		return false

	_expect(_session.color(BRUNO) == _colors.color_at(4), "he is wearing what he was wearing")
	_expect(_painted.is_empty(), "nothing was announced")
	_expect(_refusals.is_empty(), "and nothing was refused")
	return _advance()


## A swatch that is not on the wall is a client asking for a colour that does not
## exist. Dropped with a word in the log, not answered.
func _check_a_swatch_off_the_wall_is_dropped() -> bool:
	if _clock == 1:
		_painted.clear()
		_refusals.clear()
		_colors.request_color(BRUNO, 99)
		_colors.request_color(BRUNO, -1)
		return false
	if _clock < WAIT:
		return false

	_expect(_session.color(BRUNO) == _colors.color_at(4), "he is unchanged")
	_expect(_painted.is_empty(), "and nothing was written")
	_expect(not _colors.is_available(99), "a swatch off the end of the wall is not free")
	return _advance()


## A Steam ID nobody has been introduced to is not a player, and dressing one
## would put a colour on the rack that no body is wearing.
func _check_nobody_dresses_anybody_else() -> bool:
	if _clock == 1:
		_painted.clear()
		_colors.request_color(CARLA, 6)
		return false
	if _clock < WAIT:
		return false

	_expect(not _session.has_player(CARLA), "she is not in the crew")
	_expect(_painted.is_empty(), "so nothing was written for her")
	_expect(_colors.is_available(6), "and the colour she was given is still free")
	return _advance()


## A man who walks out takes nothing with him: the colour is back on the wall and
## the panels are told so they can un-cross the square.
func _check_a_man_who_leaves_frees_his_colour() -> bool:
	if _clock == 1:
		_session.register_player(CARLA, "Carla")
		return false
	if _clock == 2:
		_expect(not _colors.is_available(_colors.index_of(_session.color(CARLA))),
			"the colour she was dressed in is spoken for")
		_painted.clear()
		_session.remove_player(CARLA)
		return false
	if _clock < WAIT:
		return false

	_expect(_colors.is_available(1), "her colour is back on the rack")
	_expect(not _painted.is_empty(), "and the panels were told to repaint")
	return _advance()


## The host stating who wears what corrects a machine that guessed differently —
## and, when two men somehow arrived in the same colour, moves the second of them
## rather than leaving the wall lying.
func _check_the_host_seats_everybody() -> bool:
	if _clock == 1:
		# Forced into a clash behind the manager's back, which is the state a
		# second machine's own guess could have left this one in.
		_session.set_color(BRUNO, _session.color(ANA))
		_expect(_session.color(ANA) == _session.color(BRUNO), "two men in one colour, for now")
		_painted.clear()
		_colors.seat_everybody()
		return false
	if _clock < WAIT:
		return false

	_expect(_session.color(ANA) != _session.color(BRUNO), "the host broke the tie")
	_expect(_session.color(ANA) == _colors.color_at(0), "the first man keeps his")
	_expect(not _painted.is_empty(), "and everybody was told what everybody is wearing")
	return _advance()


## The card's own acceptance test, in the half of it one machine can answer: the
## colour picked in the van is still on the man in the house. It survives because
## it was never on a node of the van in the first place.
func _check_the_colour_survives_the_house() -> bool:
	if _clock == 1:
		_colors.request_color(BRUNO, 7)
		return false
	if _clock == WAIT:
		_expect(_session.color(BRUNO) == _colors.color_at(7), "he picked in the van")
		_phase.go_to(Phase.Type.SURVEY)
		return false
	if _clock < WAIT * 3:
		return false

	_expect(_phase.current() == Phase.Type.SURVEY, "the crew is in the house")
	_expect(_session.color(BRUNO) == _colors.color_at(7), "and he is still in the colour he picked")
	_expect(_session.color(ANA) == _colors.color_at(0), "and so is she")
	return _advance()

## The control a player presses, and not only the autoload under it: that the
## palette is eight squares, that pressing one asks for the colour that square is
## painted in, and that a square somebody else has is dead rather than takeable.
##
## The popup is dressed into the menu rather than being a scene of its own, so
## the menu is what is loaded and the popup is found in it by path.
##
## The eighth swatch is pressed by hand rather than clicked: what is under test
## is what a press does, not that Godot delivers mouse events.
func _check_the_palette() -> bool:
	if _clock == 1:
		_phase.go_to(Phase.Type.LOBBY)
		return false
	if _clock == 2:
		_menu = (load(MENU_SCENE) as PackedScene).instantiate()
		root.add_child(_menu)
		return false
	if _clock == 3:
		_popup = _menu.get_node_or_null("UI/ColorPopup")
		if _popup == null:
			_expect(false, "the menu has a colour palette on it")
			return _advance()
		var grid := _popup.get_child(0)
		_expect(grid.get_child_count() == _colors.count(),
			"one square in the palette per colour in the palette")

		# The bench's own man is whoever the popup would speak for, which off
		# Steam is the only one in the crew — so the crew is emptied down to him.
		for steam_id in _session.players.keys():
			_session.remove_player(steam_id)
		_session.register_player(ANA, "Ana", true)
		return false
	if _clock == 4:
		_popup.refresh()
		_painted.clear()
		(_popup.get_child(0).get_child(3) as Button).emit_signal("pressed")
		return false
	if _clock < WAIT + 4:
		return false

	_expect(_painted == [[ANA, _colors.color_at(3)]],
		"pressing a square asks the host, once, for the colour it is painted in")
	_expect(_session.color(ANA) == _colors.color_at(3), "and the host is who wrote it")

	# A second man takes another, and the square he took reads as dead.
	_session.register_player(BRUNO, "Bruno")
	_colors.request_color(BRUNO, 5)
	_popup.refresh()
	var taken := _popup.get_child(0).get_child(5) as Button
	_expect(taken.disabled, "and a square somebody else has cannot be pressed")

	_painted.clear()
	taken.emit_signal("pressed")
	_expect(_session.color(ANA) == _colors.color_at(3), "and we are left in our own colour")

	_menu.queue_free()
	return _advance()

# --- Plumbing --------------------------------------------------------------

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
