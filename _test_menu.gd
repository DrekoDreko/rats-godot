extends SceneTree
## Menu bench: the screen the game opens on, and the things it took over from
## the parked van.
##
## Run with: godot --headless --script _test_menu.gd
##
## It replaces `_test_lobby_van.gd`, which measured a room: that the box was
## closed, that four spots were inside it and apart from each other, that the
## stations were at a height a standing man could look at. None of that survives
## the van, and none of it was ever the point — the point was that the four
## things a crew does before a shift can be done. They are all still here, as
## controls rather than as fittings, and this is where they are checked.
##
## What cannot be checked here is the acceptance test — two players seeing each
## other's bodies and colours — which needs two instances and is done by hand
## with `--host` and `--join`.
##
## One machine and no wire throughout, which is the solo path the game takes
## anyway when Steam is not running.
##
## **Nothing in here names a `class_name` of the project, and nothing names an
## autoload by its global name.** A bench is the `MainLoop`, so it is compiled
## before the autoloads are in the tree and before the global class list is
## built — and a bench that mentions `PlayerModel` does not merely fail itself,
## it takes `player_model.gd` down with it and the menu comes up crippled.
## Autoloads are picked up off `root` by node name, and a type is checked by
## asking the object what its script is rather than by naming the class.

## The screen.
const MENU := "res://scenes/menu.tscn"

## Where the shift goes when the host says go. The parked van used to be a phase
## of its own between the two; it is not any more.
const TRAVEL := "res://scenes/van_travel.tscn"

## The scripts the parts of the screen are expected to be running, by path.
## Compared against `get_script().resource_path` rather than with `is`, for the
## reason in the header.
const CREW_SCRIPT := "res://scripts/ui/menu_crew.gd"
const COLOR_POPUP_SCRIPT := "res://scripts/ui/color_popup.gd"
const CONTRACT_PANEL_SCRIPT := "res://scripts/ui/contract_panel.gd"

## What a man is doing while he waits, which the crouch pose is named as in
## `player_model.gd`.
const SEATED_ANIMATION := "CrouchIdle"

## Stand-in Steam IDs, as in the other benches. Real ones are nineteen digits.
const ANA := 111
const BRUNO := 222
const CARLA := 333
const DANI := 444

## Frames of slack for a scene to stand up, for a model to reach its
## `AnimationPlayer`, and for a request to go round the host and come back.
const WAIT := 8

var _session: Node
var _phase: Node
var _lobby: Node
var _colors: Node
var _ready_manager: Node
var _contracts: Node
var _avatars: Node

var _menu: Node
var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	Engine.max_fps = 60
	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_lobby = root.get_node_or_null("LobbyManager")
	_colors = root.get_node_or_null("ColorManager")
	_ready_manager = root.get_node_or_null("ReadyManager")
	_contracts = root.get_node_or_null("ContractManager")
	_avatars = root.get_node_or_null("SteamAvatars")


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_it_loads()
		1: return _check_the_crew_is_drawn()
		2: return _check_the_bodies_are_seated()
		3: return _check_the_palette()
		4: return _check_the_ready_button()
		5: return _check_the_board()
		6: return _check_a_face_without_steam()
		7: return _check_play_moves_the_shift()
	return _finish()

# --- Steps -----------------------------------------------------------------

## It stands up at all, and the phase machine agrees this is where the lobby is.
## The crew is seeded first, the way it would be by `seat_the_crew` before
## anybody looked at the screen.
func _check_it_loads() -> bool:
	if _clock == 1:
		if _session == null or _phase == null or _lobby == null:
			print("FAIL: the session autoloads are not in the tree")
			return _finish()
		_session.register_player(ANA, "Ana", true)
		_session.register_player(BRUNO, "Bruno")
		_session.register_player(CARLA, "Carla")
		_session.register_player(DANI, "Dani")

		var packed := load(MENU) as PackedScene
		if packed == null:
			print("FAIL: %s does not load" % MENU)
			return _finish()
		_menu = packed.instantiate()
		root.add_child(_menu)
		return false
	if _clock < WAIT:
		return false

	_expect(_menu != null, "the menu stands up")
	if _menu == null:
		return _finish()

	_expect(_menu.get_node_or_null("Camera") != null, "with a camera on the crew")
	_expect(_menu.get_node_or_null("Floor") != null, "and a floor for them to stand on")
	_expect(_menu.get_node_or_null("Crew") != null, "and a crew node")
	_expect(_menu.get_node_or_null("UI/Cards") != null, "and somewhere to hang the cards")
	_expect(_menu.get_node_or_null("UI/Center/Play") != null, "and the button that starts it")

	var crew := _menu.get_node_or_null("Crew")
	if crew != null:
		_expect(_script_of(crew) == CREW_SCRIPT, "the crew node is the menu's own")
		_expect(crew.get_node_or_null("Seats") != null, "with seats in it")

	var lobby_scene: String = _phase.scene_of(Phase.Type.LOBBY)
	_expect(lobby_scene == MENU, "and the phase machine points the lobby at it")

	# The parked van was a phase of its own between the menu and the road. It is
	# not any more, and a lobby still pointing at it would load a scene that has
	# been deleted.
	_expect(_phase.scene_of(Phase.Type.TRAVEL) == TRAVEL,
		"and the shift moves straight on to the moving van")
	return _advance()

## Four men in the crew, four bodies on the floor, four cards over them. There
## are four seats and the game takes four players, so a fifth is not a case the
## screen has to answer for.
func _check_the_crew_is_drawn() -> bool:
	if _clock < WAIT:
		return false

	var crew := _menu.get_node("Crew")
	_expect(crew.get_node("Seats").get_child_count() == 4, "there are four seats")
	_expect(crew.count() == 4, "and a body in each of them")
	_expect(_menu.get_node("UI/Cards").get_child_count() == 4,
		"and a card over each body")

	# A body has to be findable by the man it belongs to, or nothing can be
	# repainted when his colour changes.
	for steam_id in [ANA, BRUNO, CARLA, DANI]:
		_expect(crew.body_of(steam_id) != null, "%d has a body" % steam_id)
		_expect(crew.seat_of(steam_id) != null, "and a seat the card can find" % [])

	# Nobody stands inside anybody else.
	var seen: Array[Vector3] = []
	for steam_id in [ANA, BRUNO, CARLA, DANI]:
		var at: Vector3 = crew.seat_of(steam_id).global_position
		for other in seen:
			_expect(at.distance_to(other) > 0.5,
				"%d does not stand inside a colleague" % steam_id)
		seen.append(at)
	return _advance()

## The men are crouched and in their own colours. Both are things a player reads
## off the screen without being told, and both are drawn by the same model the
## van and the house use.
func _check_the_bodies_are_seated() -> bool:
	if _clock < WAIT:
		return false

	var crew := _menu.get_node("Crew")
	for steam_id in [ANA, BRUNO, CARLA, DANI]:
		var body: Node = crew.body_of(steam_id)
		if body == null:
			continue
		_expect(String(body.current_animation()) == SEATED_ANIMATION,
			"%d is sat waiting, not stood idle" % steam_id)

	# Four men, four different colours — the one rule the palette has.
	var worn: Array[Color] = []
	for steam_id in [ANA, BRUNO, CARLA, DANI]:
		var color: Color = _session.color(steam_id)
		_expect(not worn.has(color), "%d is not wearing somebody else's colour" % steam_id)
		worn.append(color)
	return _advance()

## The palette: eight squares, pressing one asks for the colour it is painted
## in, and one somebody else has cannot be pressed at all.
##
## The bench speaks for whoever `our_crew_id` picks out, which off Steam and
## with a crew of this size is nobody in particular — so the crew is emptied
## down to one man first, which is the rule that answers "a crew of one is us".
func _check_the_palette() -> bool:
	if _clock == 1:
		for steam_id in _session.players.keys():
			_session.remove_player(steam_id)
		_session.register_player(ANA, "Ana", true)
		return false
	if _clock < WAIT:
		return false

	var popup := _menu.get_node_or_null("UI/ColorPopup")
	if popup == null:
		_expect(false, "the menu has a palette on it")
		return _advance()
	_expect(_script_of(popup) == COLOR_POPUP_SCRIPT, "and it is the menu's own")

	var grid := popup.get_child(0)
	_expect(grid.get_child_count() == _colors.count(),
		"one square in the palette per colour in it")

	popup.refresh()
	(grid.get_child(3) as Button).emit_signal("pressed")
	_expect(_session.color(ANA) == _colors.color_at(3),
		"pressing a square puts us in the colour it is painted in")

	# A second man takes another, and the square he took goes dead.
	_session.register_player(BRUNO, "Bruno")
	_colors.request_color(BRUNO, 5)
	popup.refresh()
	var taken := grid.get_child(5) as Button
	_expect(taken.disabled, "and a square somebody else has cannot be pressed")

	taken.emit_signal("pressed")
	_expect(_session.color(ANA) == _colors.color_at(3),
		"so pressing it leaves us in our own colour")

	# Back to one man for the steps below, which speak for him.
	_session.remove_player(BRUNO)
	return _advance()

## The big button. It is Play for the host, with the crew's ready count on it,
## and Ready for everybody else — and off the wire a solo man is his own host,
## which is what the count is drawn from.
func _check_the_ready_button() -> bool:
	if _clock < WAIT:
		return false

	var play := _menu.get_node("UI/Center/Play") as Button
	_expect(play.text.begins_with("PLAY"), "a host reads Play on the button")
	_expect(play.text.contains("0/1"), "with nobody ready out of a crew of one")

	_ready_manager.request_toggle(ANA)
	_expect(_ready_manager.is_ready(ANA), "and saying so is heard")
	return _advance()

## The board of jobs, which the clipboard by the van door used to hold. What is
## checked is that the jobs are on it, that signing one takes, and that the
## signature is what the rest of the game reads.
func _check_the_board() -> bool:
	if _clock == 1:
		# The ready flag from the step before would carry the shift out of the
		# lobby the moment the crew is complete, and the board is only open
		# while it is in it.
		_ready_manager.request_set(ANA, false)
		return false
	if _clock < WAIT:
		return false

	var panel := _menu.get_node_or_null("UI/ContractPanel")
	if panel == null:
		_expect(false, "the menu has a board of jobs on it")
		return _advance()
	_expect(_script_of(panel) == CONTRACT_PANEL_SCRIPT, "and it is the menu's own")

	if _contracts.count() == 0:
		_expect(false, "there are jobs to sign")
		return _advance()

	var job: Object = _contracts.at(0)
	_contracts.request_sign(job.id)
	_expect(_session.current_contract == job.id, "signing a job takes")
	_expect(_contracts.is_signed(), "and the board says a job is signed")
	_expect(_contracts.current() != null, "and it can be read back off it")
	return _advance()

## A face for a man who cannot have one. Steam is shut on a bench, and the three
## account numbers that never have a picture — a shut client, the local wire's
## invented numbers, and the solo man — all have to come back with the grey
## square rather than with nothing.
func _check_a_face_without_steam() -> bool:
	if _avatars == null:
		_expect(false, "the avatar cache is in the tree")
		return _advance()

	_expect(_avatars.placeholder() != null, "there is a grey square to stand in for a face")
	for steam_id in [ANA, _lobby.SOLO_STEAM_ID, _lobby.LOCAL_STEAM_BASE + 1]:
		var texture: Object = _avatars.texture_of(steam_id)
		_expect(texture != null, "%d gets a picture of some kind" % steam_id)
	_expect(not _avatars.has(ANA), "but nothing is cached for a face Steam never sent")
	return _advance()

## Play starts the shift, and starting it is a *phase* change and not a scene
## load. The distinction is the whole of what went wrong when the van stopped
## being the lobby: naming the scene put the crew in a van that did not move,
## with no clock on it and no engine running, because everything in it asks the
## phase machine what is going on rather than looking at which file it is in.
func _check_play_moves_the_shift() -> bool:
	if _clock == 1:
		# The bench's own menu was added to `root` by hand so that it could be
		# read without a phase change in the way. A real change loads a scene of
		# its own as `current_scene`, and two menus in the tree at once is two
		# of everything the step below looks at.
		_menu.queue_free()
		_menu = null
		return false
	if _clock == 2:
		_lobby.start_game()
		return false
	if _clock < WAIT * 3:
		return false

	_expect(_phase.current() == Phase.Type.TRAVEL, "Play carries the shift onto the road")
	var scene := root.get_tree().current_scene
	_expect(scene != null and scene.scene_file_path == TRAVEL,
		"and the moving van is what is loaded")
	if scene != null and scene.has_method("is_moving"):
		_expect(scene.is_moving(), "and it is actually moving")
	_expect(_phase.seconds_left > 0.0, "with a clock running on it")
	_expect(_session.current_contract != "", "and the job signed in the menu still signed")
	return _advance()

# --- Plumbing --------------------------------------------------------------

## What script a node is running, by path. Named this way rather than with `is`
## so that the bench never mentions a `class_name` — see the header.
func _script_of(node: Node) -> String:
	var script := node.get_script() as Script
	return "" if script == null else script.resource_path


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
