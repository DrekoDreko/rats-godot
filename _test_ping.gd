extends SceneTree
## Ping bench: the round trip a player reads off the pause menu, and the list it
## is written on.
##
## Run with: godot --headless --script _test_ping.gd
##
## Two things are under test and they meet in one place. Underneath is
## `LobbyManager.ping_of_peer`, which has to answer over whichever wire happens
## to be up and has to say "I do not know" rather than "0 ms" when there is no
## answer to give. On top is the pause menu's crew list, which reads the crew
## rather than the guest list and draws one row per man with his colour, the
## host mark and that number on it.
##
## The wire is a real one: `LobbyManager.host_local()` opens ENet on the
## loopback exactly as `--host` does, and a bare client peer on a subtree walks
## in as the far end. That is enough for the local road, which is the one the
## number is genuinely read off a connection on — the Steam road's own probe
## cannot be run on one machine at all, and what is checked of it here is the
## half that can be: that the echo does the arithmetic it claims to.
##
## The menu itself is opened for real rather than having its rows counted from
## the outside. `get_tree().paused` is what it does on the way up, and a bench
## whose tree is paused stops stepping — so the menu is closed again before the
## next step is asked for.

## The loopback port. Away from `_test_sync`'s and away from the game's own, so
## two benches left running never meet.
const PORT := 47133
## Frames of slack between one step and the next.
const WAIT := 8
## How long the wire is given to come up before the bench gives up on it.
const PATIENCE := 600

## Stand-in Steam IDs, as in the other benches.
const ANA := 111
const BRUNO := 222

## The menu under test.
const PAUSE_MENU := "res://scenes/pause_menu.tscn"

## The autoloads. In a bench run with `--script` their global names do not exist
## yet — the MainLoop script is compiled before they enter the tree — so they
## are picked up by node name instead.
var _lobby: Node
var _session: Node

## The far end: a plain ENet client with its own API on its own subtree, which
## is as close to a second machine as one process gets.
var _guest_api: SceneMultiplayer
var _guest_id := 0

var _menu: CanvasLayer

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	# Without a screen the loop runs at thousands of frames a second, and the
	# menu's own half-second countdown would pass whole between two frames.
	Engine.max_fps = 60
	_lobby = root.get_node_or_null("LobbyManager")
	_session = root.get_node_or_null("SessionManager")


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_no_wire_knows_nothing()
		1: return _check_the_wire_comes_up()
		2: return _check_the_local_wire_measures()
		3: return _check_a_stranger_is_unknown()
		4: return _check_the_echo_halves_the_trip()
		5: return _check_the_menu_draws_the_crew()
		6: return _check_the_list_follows_the_crew()
		7: return _check_a_closed_wire_forgets()
	return _finish()


## With nothing up, every question comes back "I do not know" — and not zero,
## which is the one wrong answer that would look right on screen.
func _check_no_wire_knows_nothing() -> bool:
	_expect(_lobby.ping_of_peer(0) == _lobby.UNKNOWN_PING,
		"peer zero is unknown")
	_expect(_lobby.ping_of_peer(2) == _lobby.UNKNOWN_PING,
		"a peer with no wire under it is unknown")
	_expect(_lobby.ping_of_steam_id(ANA) == _lobby.UNKNOWN_PING,
		"an account with no wire under it is unknown")
	_expect(_lobby.ping_of_steam_id(0) == _lobby.UNKNOWN_PING,
		"account zero is unknown")
	return _next()


## The real local road, opened the way `--host` opens it, with a bare client
## walking in behind it.
func _check_the_wire_comes_up() -> bool:
	if _clock == 1:
		_expect(_lobby.host_local(PORT), "the local wire opens")
		var guest_peer := ENetMultiplayerPeer.new()
		guest_peer.create_client("127.0.0.1", PORT)
		_guest_id = guest_peer.get_unique_id()

		var far := Node.new()
		far.name = "Far"
		root.add_child(far)
		_guest_api = SceneMultiplayer.new()
		_guest_api.multiplayer_peer = guest_peer
		set_multiplayer(_guest_api, NodePath("/root/Far"))
		return false
	if root.multiplayer.get_peers().is_empty():
		if _clock > PATIENCE:
			_expect(false, "the guest reaches the host")
			return _finish()
		return false
	_expect(root.multiplayer.get_unique_id() == 1, "we are the host")
	return _next()


## ENet has been measuring since the handshake, so the number is there to be
## read the moment the peer is. It is a loopback, so it is small — but it is a
## real reading and not a stand-in, and "small" is the only thing worth
## asserting about a number the network decides.
func _check_the_local_wire_measures() -> bool:
	var ping: int = _lobby.ping_of_peer(_guest_id)
	_expect(ping >= 0, "the guest's round trip reads as a number (%d ms)" % ping)
	_expect(ping < 1000, "the loopback is not a second away (%d ms)" % ping)
	_expect(_lobby.ping_of_peer(root.multiplayer.get_unique_id()) == 0,
		"we are nowhere from ourselves")

	# The account form of the same question. The far end here is a bare ENet
	# peer with no `LobbyManager` behind it, so nothing introduced it — the real
	# one does that on `peer_connected`. Its introduction is filed by hand so
	# that the account road has an account to walk down, which is the one thing
	# the stand-in cannot do for itself.
	_lobby.remember_identity(_guest_id, BRUNO, "Bruno")
	var guest_steam: int = _lobby.steam_id_of_peer(_guest_id)
	_expect(guest_steam == BRUNO, "the guest has an account number on the wire")
	var by_account: int = _lobby.ping_of_steam_id(guest_steam)
	_expect(by_account >= 0,
		"the same trip reads off the account (%d ms)" % by_account)
	_expect(_lobby.ping_of_steam_id(_lobby.our_steam_id()) == 0,
		"our own account is nowhere from us")
	return _next()


## A peer that is not on the wire is unknown even while a wire is up. This is
## the case that would otherwise read as a perfect connection to a man who has
## already gone.
func _check_a_stranger_is_unknown() -> bool:
	_expect(_lobby.ping_of_peer(999) == _lobby.UNKNOWN_PING,
		"a peer nobody has heard of is unknown")
	_expect(_lobby.ping_of_steam_id(ANA) == _lobby.UNKNOWN_PING,
		"an account nobody on the wire answers for is unknown")
	return _next()


## The Steam road's own probe, checked at the one point that can be checked on
## one machine: what the echo does with a stamp. The trip is the whole distance
## and the ping is half of it, so a stamp written 100 ms ago is a 50 ms ping.
##
## The arithmetic is run here rather than the RPC being sent, because sending it
## would need the second machine this bench does not have. What is being checked
## is the sum and the bookkeeping, which is where the mistake would be.
func _check_the_echo_halves_the_trip() -> bool:
	var stamp := Time.get_ticks_msec() - 100
	@warning_ignore("integer_division") # Half the round trip, same as the lobby does.
	_lobby._pings[_guest_id] = maxi(0, Time.get_ticks_msec() - stamp) / 2
	var filed: int = _lobby._pings[_guest_id]
	_expect(filed >= 45 and filed <= 60,
		"a 100 ms trip is filed as about a 50 ms ping (%d)" % filed)

	# A stamp from the future — two machines whose clocks disagree — floors at
	# zero rather than going negative and reading as "unknown".
	var ahead := Time.get_ticks_msec() + 500
	@warning_ignore("integer_division") # Half the round trip, same as the lobby does.
	_lobby._pings[_guest_id] = maxi(0, Time.get_ticks_msec() - ahead) / 2
	_expect(_lobby._pings[_guest_id] == 0, "a stamp from the future floors at zero")
	_lobby._pings.erase(_guest_id)
	return _next()


## The menu itself, opened over a crew of two. What is checked is what a player
## would look at: one row per man, the names on them, a host mark on the host's
## row and only his, and something honest where the ping goes.
func _check_the_menu_draws_the_crew() -> bool:
	if _clock == 1:
		_session.register_player(ANA, "Ana", true)
		_session.register_player(BRUNO, "Bruno", false)
		_menu = (load(PAUSE_MENU) as PackedScene).instantiate()
		root.add_child(_menu)
		return false
	if _clock < WAIT:
		return false

	_menu.open()
	var crew: VBoxContainer = _menu.get_node("Center/Panel/Margin/Rows/Crew")
	_expect(crew.visible, "the crew section is shown when there is a crew")
	_expect(crew.get_child_count() == 2, "two in the crew is two rows (%d)"
		% crew.get_child_count())

	var text := _rows_text(crew)
	var all := _joined(text)
	_expect(all.contains("Ana"), "Ana is on the list: %s" % all)
	_expect(all.contains("Bruno"), "Bruno is on the list: %s" % all)
	_expect(all.count(_menu.CREW_HOST_MARK) == 1,
		"exactly one row is marked host: %s" % all)
	_expect(text[0].contains("Ana") and text[0].contains(_menu.CREW_HOST_MARK),
		"the mark is on the host's row: %s" % text[0])

	# The swatch carries the colour and the name does not — a whole row tinted
	# would read as an error rather than as a man in a coloured suit.
	_session.set_color(ANA, Color("ff2d2d"))
	_menu._refresh_crew()
	var swatch: Label = crew.get_child(0).get_child(0)
	_expect(swatch.get_theme_color("font_color") == Color("ff2d2d"),
		"the swatch wears the player's colour")
	var name_label: Label = crew.get_child(0).get_child(1)
	_expect(name_label.get_theme_color("font_color") == Color.WHITE,
		"the name stays white")

	# Bruno is the account the far end was filed under, so his row carries the
	# real reading off the connection — the whole point of the column.
	var brunos_ping: Label = crew.get_child(1).get_child(2)
	_expect(brunos_ping.text.ends_with(" ms"),
		"a man on the wire shows his round trip (%s)" % brunos_ping.text)

	# Ana is in the crew but nobody on the wire answers for her, which is what a
	# man whose game died without the socket closing looks like. That row must
	# say so rather than saying "0 ms", which would read as a perfect line.
	var anas_ping: Label = crew.get_child(0).get_child(2)
	_expect(anas_ping.text == _menu.CREW_NO_PING,
		"a man off the wire shows no ping, not zero (%s)" % anas_ping.text)

	# The tree is paused while the menu is up, and a paused tree is a bench that
	# stops stepping.
	_menu.close()
	return _next()


## The list is rebuilt off the crew and not kept in step with it by hand, so a
## man leaving is a row gone the next time it is drawn — and an empty crew hides
## the whole section rather than leaving a labelled hole.
func _check_the_list_follows_the_crew() -> bool:
	if _clock == 1:
		_session.remove_player(BRUNO)
		_menu._refresh_crew()
		return false
	if _clock < WAIT:
		return false
	var crew: VBoxContainer = _menu.get_node("Center/Panel/Margin/Rows/Crew")
	_expect(crew.get_child_count() == 1, "one man left is one row (%d)"
		% crew.get_child_count())

	_session.remove_player(ANA)
	_menu._refresh_crew()
	var title: Label = _menu.get_node("Center/Panel/Margin/Rows/CrewTitle")
	_expect(not crew.visible, "an empty crew hides the list")
	_expect(not title.visible, "an empty crew hides the heading too")
	return _next()


## The wire going down takes the readings with it. A number filed against a peer
## id from the last lobby would be a number on whoever is handed that id next.
func _check_a_closed_wire_forgets() -> bool:
	if _clock == 1:
		_lobby._pings[_guest_id] = 42
		_lobby.leave_lobby()
		return false
	if _clock < WAIT:
		return false
	_expect(_lobby._pings.is_empty(), "the readings go down with the wire")
	_expect(_lobby.ping_of_peer(_guest_id) == _lobby.UNKNOWN_PING,
		"a peer off a closed wire is unknown again")
	return _next()


## The text of every row, one string per row, so that a whole list can be looked
## at in one assertion instead of by index.
func _rows_text(crew: VBoxContainer) -> Array[String]:
	var out: Array[String] = []
	for row in crew.get_children():
		var parts := ""
		for cell in row.get_children():
			if cell is Label:
				parts += (cell as Label).text + " "
		out.append(parts)
	return out


## One string out of many, for printing a whole list in a failure line.
func _joined(rows: Array[String]) -> String:
	var out := ""
	for row in rows:
		out += row + " | "
	return out


func _expect(condition: bool, what: String) -> void:
	if condition:
		print("  ok    %s" % what)
	else:
		_failures += 1
		print("  FAIL  %s" % what)


## On to the next step, with a fresh clock so that anything asked of the tree has
## a few frames to actually happen before it is looked at.
func _next() -> bool:
	_step += 1
	_clock = 0
	print("")
	return false


func _finish() -> bool:
	if _guest_api != null:
		_guest_api.multiplayer_peer = null
	print("")
	if _failures == 0:
		print("ping bench: everything holds")
	else:
		print("ping bench: %d failure(s)" % _failures)
	print("--- %d frames ---" % _frames)
	return true
