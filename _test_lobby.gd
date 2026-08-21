extends SceneTree
## Lobby test bench: opening a lobby on Steam, the guest list that comes back
## from it, and the wire that comes up underneath.
##
## Run with: godot --headless --script _test_lobby.gd
##
## It needs the Steam client running and signed in — there is no pretending at
## this layer, the whole point is that Valve answers. What it cannot do on one
## machine is the other half of the acceptance test: a second account walking
## in. So it checks everything up to the doorway — that the lobby opens, that it
## is stamped where the browser can find it, that we come out of it as peer 1
## with the authority the synchronisation will need, that the screen draws the
## name that is in it, and that the three ways of getting it wrong (no Steam, a
## number that is not a lobby, a lobby that is not there) each come back as a
## sentence instead of a crash.
##
## Nothing here is instant: every step waits on Steam and gives up after
## `PATIENCE` frames rather than hanging a test run forever.

## Frames of slack between one step and the next.
const WAIT := 8
## How long any one answer from Steam is given before the step is called lost.
const PATIENCE := 900
## How often the browser is asked again while it has not caught up yet.
const SEARCH_EVERY := 120
## How far back to reach for a lobby ID that is certainly dead. Steam hands
## these out in order across every game sharing the app ID, so a number near our
## own belongs to somebody else's lobby opened seconds later — which would come
## back as a real refusal for a real reason and prove nothing.
const LONG_GONE := 100000000

## The autoloads. In a bench run with `--script` their global names do not exist
## yet — the MainLoop script is compiled before they enter the tree — so they
## are picked up by node name instead.
var _steam: Node
var _lobby: Node
var _screen: Control

## What the manager has said so far, so a step can wait on an answer that landed
## while it was not looking.
var _entered: Array[Dictionary] = []
var _failures_said: Array[String] = []
var _listings: Array[Array] = []
var _left := 0

var _created_id := 0
var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0

func _initialize() -> void:
	# Without a screen the loop would run at thousands of frames per second, and
	# Steam would be given no real time at all to answer.
	Engine.max_fps = 60
	_steam = root.get_node_or_null("SteamManager")
	_lobby = root.get_node_or_null("LobbyManager")
	if _lobby == null:
		return
	_lobby.lobby_entered.connect(_on_entered)
	_lobby.lobby_left.connect(func() -> void: _left += 1)
	_lobby.lobby_failed.connect(func(reason: String) -> void: _failures_said.append(reason))
	_lobby.lobby_list_updated.connect(func(found: Array) -> void: _listings.append(found))

func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_start()
		1: return _check_refuses_without_a_lobby()
		2: return _check_opens_a_lobby()
		3: return _check_we_are_the_host()
		4: return _check_the_screen_draws_it()
		5: return _check_the_browser_finds_it()
		6: return _check_leaving()
		7: return _check_a_lobby_that_is_not_there()
	return _finish()

# --- Steps -----------------------------------------------------------------

## Nothing has happened yet: Steam is up, the manager is in the tree and there
## is no lobby to speak of.
func _check_start() -> bool:
	if _clock < WAIT:
		return false
	if _steam == null or _lobby == null:
		print("FAIL: the autoloads are not in the tree")
		return _finish()
	if not _steam.is_online:
		print("--- Steam is not running: this bench needs the client signed in ---")
		return _finish()
	print("--- signed in as %s ---" % _steam.get_persona_name())
	_expect(_lobby.lobby_id == 0, "the game should start outside any lobby")
	_expect(not _lobby.is_host, "nobody hosts before there is a lobby")
	_expect(_lobby.list_players().is_empty(), "there is no guest list without a lobby")
	return _advance()

## The two refusals that cost no round trip: a number that is not a lobby, and
## an invite with nowhere to send anybody.
func _check_refuses_without_a_lobby() -> bool:
	_failures_said.clear()
	_expect(not _lobby.join_lobby(123), "123 is not a lobby ID")
	_expect(not _lobby.join_lobby(0), "zero is not a lobby ID")
	_expect(not _lobby.invite_friends(), "there is nobody to invite to no lobby")
	_expect(_failures_said.size() == 3, "each refusal should say why, and %d did" % _failures_said.size())
	for reason in _failures_said:
		_expect(not reason.is_empty(), "a refusal should not be an empty sentence")
	print("--- refused: %s ---" % "; ".join(_failures_said))
	return _advance()

## The lobby itself. `create_lobby` only means the request went out; the lobby
## arrives on `lobby_entered`, some way down the wire.
func _check_opens_a_lobby() -> bool:
	if _clock == 1:
		_failures_said.clear()
		_expect(_lobby.create_lobby(_lobby.MAX_PLAYERS), "the request should go out")
		return false
	if not _failures_said.is_empty():
		print("FAIL: Steam refused the lobby — %s" % _failures_said[0])
		_failures += 1
		return _finish()
	if _entered.is_empty():
		return _lost("Steam never answered createLobby")
	_created_id = _entered[0]["lobby_id"]
	print("--- lobby %d open ---" % _created_id)
	return _advance()

## Out of our own lobby we come as its owner, as peer 1 on Godot's side, and as
## the only name on the guest list.
func _check_we_are_the_host() -> bool:
	_expect(_lobby.lobby_id == _created_id, "the manager should be holding the lobby it opened")
	_expect(_lobby.is_host, "whoever opens the lobby hosts it")
	_expect(_entered[0]["is_host"], "and says so on the way out")
	_expect(_lobby.owner_id == _steam.get_steam_id(), "Steam should call us the owner")

	var api := get_multiplayer()
	_expect(api.has_multiplayer_peer(), "the wire should be up with the lobby")
	_expect(api.is_server(), "the host should be the network authority")
	_expect(api.get_unique_id() == 1, "the authority is peer 1, and is %d" % api.get_unique_id())

	var players: Array = _lobby.list_players()
	_expect(players.size() == 1, "one player in a fresh lobby, and there are %d" % players.size())
	if not players.is_empty():
		_expect(players[0]["steam_id"] == _steam.get_steam_id(), "and that player is us")
		_expect(players[0]["name"] == _steam.get_persona_name(), "under our own Steam name")
		_expect(players[0]["is_host"], "marked as the host")

	# The stamp is what keeps our lobbies apart from every other lobby sharing
	# Spacewar's app ID, so it is worth checking that it actually landed.
	_expect(Steam.getLobbyData(_created_id, _lobby.GAME_KEY) == _lobby.GAME_VALUE,
		"the lobby should be stamped for the browser's filter")
	_expect(Steam.getLobbyData(_created_id, _lobby.HOST_KEY) == _steam.get_persona_name(),
		"and carry the host's name for the row")
	_expect(Steam.getLobbyMemberLimit(_created_id) == _lobby.MAX_PLAYERS,
		"the van holds %d" % _lobby.MAX_PLAYERS)
	return _advance()

## The screen is checked for the one thing that can silently rot: the paths it
## reaches its own nodes through, and the row it puts a player's name on.
func _check_the_screen_draws_it() -> bool:
	if _clock == 1:
		_screen = load("res://scenes/lobby.tscn").instantiate()
		root.add_child(_screen)
		return false
	if _clock < WAIT:
		return false
	var rows := _player_rows()
	_expect(rows.size() == 1, "the screen should draw one row, and drew %d" % rows.size())
	if not rows.is_empty():
		_expect(rows[0].contains(_steam.get_persona_name()),
			"the row should carry our name, and says \"%s\"" % rows[0])
	print("--- on screen: %s ---" % "; ".join(rows))
	return _advance()

## The browser: the lobby we just opened should come back out of Steam's search,
## through the filter that keeps every other 480 lobby out of it. Steam takes a
## few seconds to put a brand new lobby into its index, so the search is made
## again until it turns up — an empty browser right after `create_lobby` is the
## normal thing to see, not a broken one.
func _check_the_browser_finds_it() -> bool:
	if _clock % SEARCH_EVERY == 1:
		_listings.clear()
		_expect(_lobby.refresh_lobbies(), "the search should go out")
		return false
	if _listings.is_empty():
		return _lost("Steam never answered requestLobbyList")
	var found: Array = _listings[0]
	var ours := {}
	for lobby in found:
		if lobby["lobby_id"] == _created_id:
			ours = lobby
	if ours.is_empty():
		return _lost("the lobby we opened never turned up in the browser")

	print("--- the browser found %d lobby(s), ours among them ---" % found.size())
	for lobby in found:
		# The filter is what keeps the strangers testing their own games on
		# Spacewar's app ID off this list.
		_expect(Steam.getLobbyData(lobby["lobby_id"], _lobby.GAME_KEY) == _lobby.GAME_VALUE,
			"every row should be a RATS lobby, and %d is not" % lobby["lobby_id"])
	_expect(ours["host_name"] == _steam.get_persona_name(), "our row should carry our name")
	_expect(ours["players"] == 1, "our row should count one player")
	_expect(ours["max_players"] == _lobby.MAX_PLAYERS, "and %d seats" % _lobby.MAX_PLAYERS)
	return _advance()

## Leaving puts everything back where it was: no lobby, no guest list, no wire.
func _check_leaving() -> bool:
	if _clock == 1:
		_left = 0
		_lobby.leave_lobby()
		return false
	if _clock < WAIT:
		return false
	_expect(_left == 1, "leaving should be announced once, and was %d time(s)" % _left)
	_expect(_lobby.lobby_id == 0, "the lobby should be let go of")
	_expect(not _lobby.is_host, "and the host role with it")
	_expect(_lobby.list_players().is_empty(), "the guest list should be empty again")
	_expect(not get_multiplayer().has_multiplayer_peer(), "the wire should come down too")
	_expect(_player_rows() == ["nobody yet"], "and the screen should say so")
	return _advance()

## A lobby that is not there. The ID is well formed, so it gets past `isLobby`
## and costs a real round trip — which is the path a stale ID pasted by a friend
## goes down, and the one that has to come back as a sentence.
func _check_a_lobby_that_is_not_there() -> bool:
	if _clock == 1:
		_failures_said.clear()
		_expect(_lobby.join_lobby(_created_id - LONG_GONE),
			"a well-formed ID should be worth asking Steam about")
		return false
	if _failures_said.is_empty():
		return _lost("Steam never turned down the lobby that is not there")
	print("--- turned down: %s ---" % _failures_said[0])
	_expect(_failures_said[0].contains("no longer exists"),
		"a dead lobby should be named as one, and came back as \"%s\"" % _failures_said[0])
	_expect(_lobby.lobby_id == 0, "a refused join should leave us outside")
	_expect(not get_multiplayer().has_multiplayer_peer(), "and off the wire")
	return _advance()

# --- Plumbing --------------------------------------------------------------

func _on_entered(lobby_id: int, is_host: bool) -> void:
	_entered.append({"lobby_id": lobby_id, "is_host": is_host})

## What the right-hand panel is showing, one string per row.
func _player_rows() -> Array[String]:
	var rows: Array[String] = []
	if _screen == null:
		return rows
	var column := _screen.get_node("Margin/Rows/Body/Right/Margin/Column/Players")
	for row in column.get_children():
		var label := row as Label
		if label != null:
			rows.append(label.text.strip_edges())
	return rows

func _expect(condition: bool, what: String) -> void:
	if condition:
		return
	print("FAIL: %s" % what)
	_failures += 1

## A step that is still waiting keeps waiting, until it has waited too long.
func _lost(what: String) -> bool:
	if _clock < PATIENCE:
		return false
	print("FAIL: %s (gave up after %d frames)" % [what, _clock])
	_failures += 1
	return _finish()

func _advance() -> bool:
	_step += 1
	_clock = 0
	return false

func _finish() -> bool:
	# The lobby outlives the bench otherwise, and Steam keeps it on the browser.
	if _lobby != null:
		_lobby.leave_lobby()
	print("--- %d frames, %d failure(s) ---" % [_frames, _failures])
	return true
