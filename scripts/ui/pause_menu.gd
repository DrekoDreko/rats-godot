extends CanvasLayer
## The pause menu: the one screen a player can always get to, and the only one
## that stops him without stopping anybody else.
##
## **The pause is local, and it is never anything else.** This is an online game.
## `get_tree().paused` is a flag on *this* machine's scene tree — it travels
## nowhere, and that is exactly what is wanted: a man who opens this menu to
## answer the door does not put three other people's shift on hold. The game
## keeps running for everybody, his own body keeps standing in the van where he
## left it, and what he has bought himself is a loose mouse and a set of buttons.
##
## That is also the whole of the danger in it. A paused tree stops `_process` and
## `_physics_process` on everything under it, and two of the things it would
## otherwise stop are the ones that keep this player *visible* to the others:
## the avatar that reads his character and the `MultiplayerSynchronizer` that
## puts the reading on the wire (`scripts/steam/player_avatar.gd`). Stop those
## and he does not merely stand still on their screens — he stops sending, and
## what they see is a man frozen mid-stride, which is indistinguishable from a
## man whose connection has died. So the avatar and its synchronizer are set to
## `PROCESS_MODE_ALWAYS` in `player_avatar.tscn`, and they go on saying "here I
## am, standing still" for as long as this menu is up. Standing still is the
## truth; silence is not.
##
## The session autoloads were already set the same way and their comments say so
## by name — `JoinGate`, `PhaseManager`, `ReadyManager`, `ColorManager`,
## `SteamManager` and the rest. The wire does not stop for a menu: invites still
## land, the phase still turns, the host still counts ready boards, and a man who
## pauses through the end of a phase comes back to find the van has moved on
## without him. That is the correct behaviour and not a bug to be papered over.
##
## **Esc had three owners before this file.** The `cancel` action carries Esc
## *and* the right mouse button, which is why the menu is not on it: right-click
## is a mouse gesture and opening a pause menu with it would be absurd. The
## `toggle_mouse` action carries Esc too, and both `player.gd` and `store_screen.gd`
## already answer to it. So the menu is on a `pause` action of its own — Esc
## alone — and it takes the key before anybody else can by sitting on
## `_input` with a `PROCESS_MODE_ALWAYS` node, marking the event handled and
## leaving nothing for the rest of them to find. That is also what makes closing
## work: with the tree paused, a menu on `PROCESS_MODE_PAUSABLE` could never hear
## the key that would let it go.
##
## **It is also where a player finds out who else is still here.** A man who has
## just watched somebody stop moving has one question, and it is not answered by
## the game carrying on around him: is that player gone, or is his line simply
## bad? So the menu carries the crew with a round trip against each name — see
## the section at the foot of this file, and `LobbyManager.ping_of_peer`, which
## is the one place that knows what wire is underneath.

## The lobby *screen*, one step before the van. It is where "Sair da partida"
## goes, and it is the same path `NetworkGuard` sends a stranded client to.
const LOBBY_SCENE := "res://scenes/menu.tscn"

## How often the crew list is rebuilt while the menu is up, in seconds. A ping
## is a number that wanders by a few milliseconds between one reading and the
## next, and redrawing it sixty times a second would make it unreadable as well
## as wasteful — half a second is fast enough that a man who has just walked out
## is gone before it is noticed, and slow enough to read.
const CREW_REFRESH := 0.5

## The dot in front of each name, drawn in that player's colour. A filled circle
## is the one glyph that reads as a colour swatch at eight points.
const CREW_SWATCH := "●"

## What marks the host in the list. It goes after the name rather than before,
## so that the names still line up under each other.
const CREW_HOST_MARK := " (host)"

## What a row says where a ping would go when there is none to show — solo, or a
## peer who has not answered his first probe. An em dash and not "0 ms", which
## would be a lie of exactly the kind a player would believe.
const CREW_NO_PING := "—"

## Font size for a crew row. The same eight points the hint under the title
## uses: this is a footnote to the menu, not the menu.
const CREW_FONT_SIZE := 8

@onready var _resume: Button = $Center/Panel/Margin/Rows/Resume
@onready var _leave: Button = $Center/Panel/Margin/Rows/Leave
@onready var _quit: Button = $Center/Panel/Margin/Rows/Quit
## Where the crew rows are put. It is emptied and refilled rather than kept in
## step row by row: four rows is nothing to build, and a list that is rebuilt
## whole can never be a list that quietly disagrees with the crew.
@onready var _crew: VBoxContainer = $Center/Panel/Margin/Rows/Crew
@onready var _crew_title: Label = $Center/Panel/Margin/Rows/CrewTitle
@onready var _crew_separator: HSeparator = $Center/Panel/Margin/Rows/CrewSeparator
@onready var _how_to: Button = $Center/Panel/Margin/Rows/HowTo
## The controls page. It lives beside the buttons rather than on top of them, so
## the panel takes the size of whichever of the two is showing and the menu never
## has a page floating over a set of buttons that are still there underneath.
@onready var _help: VBoxContainer = $Center/Panel/Margin/Help
@onready var _rows: VBoxContainer = $Center/Panel/Margin/Rows
@onready var _help_back: Button = $Center/Panel/Margin/Help/Back

## Whether the menu is up. Kept rather than read off `visible`, because the two
## can part company for one frame while a scene is being changed under us.
var _open := false

## What is left of the wait before the crew list is rebuilt. Counted down in
## `_process`, which only runs while the menu is up (see `open` and `close`), so
## a closed menu costs nothing at all.
var _crew_countdown := 0.0


func _ready() -> void:
	# The menu itself must keep running while it holds the tree paused —
	# otherwise the button that would unpause never hears the click, and the key
	# that would close it never arrives. It is the same reason every session
	# autoload is set this way, and the one node where getting it wrong is
	# immediately fatal rather than merely wrong.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	# Nothing to redraw while the menu is down, and `PROCESS_MODE_ALWAYS` would
	# otherwise have this ticking through every frame of a shift for no reason.
	# `open` turns it back on.
	set_process(false)

	_resume.pressed.connect(close)
	_how_to.pressed.connect(_show_help)
	_help_back.pressed.connect(_show_menu)
	_leave.pressed.connect(_leave_match)
	_quit.pressed.connect(_quit_game)

	# A host that goes down while the menu is up would otherwise leave the tree
	# paused under a lobby screen: `NetworkGuard` changes the scene, this node
	# goes with it, and nobody is left to lower the flag. The signal exists for
	# exactly this — its comment names the pause menu.
	NetworkGuard.host_disconnected.connect(_on_host_disconnected)


## Esc, taken before anybody else can have it.
##
## `_input` and not `_unhandled_input`, deliberately. With the menu up the mouse
## is loose and its buttons have the focus, and an unhandled-input handler would
## be the last to hear about a key that a focused `Button` may well have eaten
## first. Sitting at the front and marking the event handled is also what keeps
## the same press from reaching `player.gd`, which would otherwise read Esc as
## `toggle_mouse` and grab the cursor back out from under the menu that had just
## opened.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	# A screen already has the player — the shop is the one that does today. It
	# owns the cursor and it owns its own way out, and a pause menu opening on
	# top of it would be two screens fighting over one mouse. Esc is left for it.
	if not _open and _player_is_busy():
		return
	get_viewport().set_input_as_handled()
	# Esc on the controls page is a step back and not a way out: a man who opened
	# a page to read it should not have to lose the whole menu to leave it again.
	if _open and _help.visible:
		_show_menu()
		return
	toggle()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## Up: the tree stops for us alone and the mouse comes loose to click with.
func open() -> void:
	if _open:
		return
	_open = true
	show()
	# Always up on the buttons, whatever page was last read.
	_show_menu()
	# Built once on the way up, so the list is right in the first frame the
	# player sees rather than half a second into it.
	_refresh_crew()
	_crew_countdown = CREW_REFRESH
	set_process(true)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Focused so the menu can be driven from the keyboard, and so that a
	# controller has somewhere to start.
	_resume.grab_focus()


## Down: the tree runs again and the camera gets the mouse back.
##
## The cursor is only recaptured when the player is actually in the map. Closing
## the menu over a screen that wanted the mouse — or on a machine that has just
## been sent back to the lobby — would take the cursor away from whoever is
## properly holding it.
func close() -> void:
	if not _open:
		return
	_open = false
	hide()
	set_process(false)
	get_tree().paused = false
	if not _player_is_busy():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Out of the shift and back to the lobby screen.
##
## The tree is unpaused *first*, and it matters: `change_scene_to_file` builds
## the next scene under the same tree, and a lobby screen that came up with the
## flag still set would be a menu whose buttons do not answer. The mouse is left
## visible on purpose — the lobby screen is a screen, and it wants a cursor.
##
## `LobbyManager.leave_lobby()` is the one call needed. Everything behind it is
## already wired: it emits `lobby_left`, which `JoinGate._on_lobby_left` hears
## (putting `admitted` back to false) and `NetworkGuard._on_lobby_left` hears
## (wiping the crew, the wallet, the stock and the pins, and changing the
## scene). Doing any of that again here would be a second opinion about state
## that already has an owner.
##
## **Nothing may be read off this node after that call.** `NetworkGuard` answers
## `lobby_left` in the same breath, and its answer is `change_scene_to_file`,
## which tears down the scene this menu is a child of — the map, the van and the
## travel scene each carry their own copy. So the moment `leave_lobby` returns
## we are a node with no tree under us, and the `get_tree().current_scene` that
## used to stand here found `get_tree()` null and took the game down with it.
## That is why the question "was there a lobby at all?" is asked *first*, off
## `LobbyManager`, and the answer kept in a local: a local survives its node
## being freed, and a road decided beforehand needs nothing looked up after.
func _leave_match() -> void:
	_open = false
	hide()
	set_process(false)
	var tree := get_tree()
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# A solo run never had a lobby, so `leave_lobby` will return without a word
	# and nobody will move us — the scene change is ours to make in that case, and
	# only in that case. Asked before the call, because after it there is no
	# `LobbyManager.lobby_id` worth reading and no `self` left to read it from.
	var was_solo := LobbyManager.lobby_id == 0

	LobbyManager.leave_lobby()

	if was_solo:
		SessionManager.reset()
		Wallet.reset()
		Stock.reset()
		MapManager.clear_all_pins()
		ReadyManager.blocked = false
		JoinGate.admitted = false
		tree.change_scene_to_file(LOBBY_SCENE)


## Out of the game altogether. The lobby is left on the way out rather than being
## dropped on the floor: the other players get a clean departure instead of a
## peer that stops answering, and Steam is told before the process goes.
##
## The tree is taken hold of before the lobby is left, for the reason
## `_leave_match` gives at length: leaving the lobby sends `NetworkGuard` off to
## change the scene, which frees this node, and a `get_tree()` asked afterwards
## comes back null. Here that would have been a quit button that does not quit.
func _quit_game() -> void:
	var tree := get_tree()
	tree.paused = false
	LobbyManager.leave_lobby()
	tree.quit()


## The host went down while the menu was up. The scene is being changed out from
## under us, so the only thing worth doing is making sure the flag does not
## travel with it.
func _on_host_disconnected(_reason: String) -> void:
	if not _open:
		return
	_open = false
	hide()
	set_process(false)
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Whether some other screen already has the player. It is asked of the player
## himself rather than kept here, because he is the one who was handed over
## (`player.gd: set_ui_open`) and a second record of it would be one that could
## disagree.
func _player_is_busy() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	return player.is_ui_open()

# --- Who else is in the shift ------------------------------------------------
# The list is drawn off `SessionManager.players` and not off
# `LobbyManager.list_players()`, and the difference is the whole point of it.
# The guest list is Valve's answer to "who is in this lobby"; the crew is the
# game's answer to "who is actually in this shift", which is the question a man
# is asking when he opens a menu to see whether the others are still there. They
# part company exactly when it matters — a player who joined the lobby but never
# got through `JoinGate`, a player whose game died without Steam noticing yet.
#
# Nothing here is polled off a signal. `player_joined` and its brothers would
# redraw the list on a machine whose menu is closed, and the list is worthless
# then; the countdown below only runs while the menu is up.


## Ticks the crew list along. Runs only while the menu is open — `open` and
## `close` are what turn it on and off — so this is not a cost the rest of the
## game pays.
func _process(delta: float) -> void:
	_crew_countdown -= delta
	if _crew_countdown > 0.0:
		return
	_crew_countdown = CREW_REFRESH
	_refresh_crew()


## Throws the rows away and builds them again from the crew as it stands.
##
## An empty crew hides the whole section, heading and rule and all, rather than
## leaving a labelled hole. That is the state a bench or a half-loaded scene is
## in; a solo player is a crew of one and gets his own row, with no ping, which
## is the truth about a man with no wire.
func _refresh_crew() -> void:
	for row in _crew.get_children():
		row.queue_free()

	var crew := SessionManager.players
	var has_crew := not crew.is_empty()
	_crew.visible = has_crew
	_crew_title.visible = has_crew
	_crew_separator.visible = has_crew
	if not has_crew:
		return

	# Sorted, and by Steam ID rather than by name: the crew is a dictionary and
	# its order is whatever order people happened to arrive in on this machine,
	# which is not the same order on the next one. A man should not find himself
	# in a different place in the list on his friend's screen — and a list that
	# reshuffles as somebody leaves is one nobody can read.
	var ids := crew.keys()
	ids.sort()
	for steam_id in ids:
		_crew.add_child(_crew_row(steam_id))


## One line of the list: a dot in the player's colour, his name, the host mark
## if it is his, and his ping pushed out to the right.
##
## The dot is a `Label` of its own so that only it carries the colour — a whole
## row tinted red would be a row that reads as an error rather than as a man in
## a red suit.
func _crew_row(steam_id: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var swatch := Label.new()
	swatch.text = CREW_SWATCH
	swatch.add_theme_font_size_override("font_size", CREW_FONT_SIZE)
	swatch.add_theme_color_override("font_color", SessionManager.color(steam_id))
	swatch.add_theme_color_override("font_outline_color", Color.BLACK)
	swatch.add_theme_constant_override("outline_size", 4)
	row.add_child(swatch)

	var player := SessionManager.player(steam_id)
	var name_label := Label.new()
	name_label.text = String(player.get("name", "..."))
	if bool(player.get("is_host", false)):
		name_label.text += CREW_HOST_MARK
	name_label.add_theme_font_size_override("font_size", CREW_FONT_SIZE)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 4)
	# The name takes whatever width is going, which is what pins the ping to the
	# right-hand edge however long or short the names turn out to be.
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var ping := Label.new()
	ping.text = _ping_text(steam_id)
	ping.add_theme_font_size_override("font_size", CREW_FONT_SIZE)
	ping.add_theme_color_override("font_color", _ping_color(steam_id))
	ping.add_theme_color_override("font_outline_color", Color.BLACK)
	ping.add_theme_constant_override("outline_size", 4)
	ping.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(ping)

	return row


## The ping as a player reads it. Our own row and a solo run both come back
## without a number: asking a man how far he is from himself is not a question,
## and answering "0 ms" would suggest a wire that is not there.
func _ping_text(steam_id: int) -> String:
	if steam_id == LobbyManager.our_steam_id():
		return CREW_NO_PING
	var ping := LobbyManager.ping_of_steam_id(steam_id)
	if ping < 0:
		return CREW_NO_PING
	return "%d ms" % ping


## Green, yellow or red, at the two thresholds a player would draw them at
## himself. Grey for a row with no number, so that "we do not know" never looks
## like "this is fine".
func _ping_color(steam_id: int) -> Color:
	if steam_id == LobbyManager.our_steam_id():
		return Color(0.72, 0.72, 0.72)
	var ping := LobbyManager.ping_of_steam_id(steam_id)
	if ping < 0:
		return Color(0.72, 0.72, 0.72)
	if ping < 80:
		return Color(0.42, 0.86, 0.42)
	if ping < 180:
		return Color(0.95, 0.83, 0.35)
	return Color(0.95, 0.42, 0.42)


# --- The two pages -----------------------------------------------------------
# One panel, two contents, never both. The crew list and its countdown belong to
# the buttons page, so the countdown is left running either way: it costs a
# subtraction a frame and it means the list is current the moment the page comes
# back rather than up to half a second stale.


## The controls page, and the mouse on the way out of it.
func _show_help() -> void:
	_rows.hide()
	_help.show()
	_help_back.grab_focus()


## Back to the buttons.
func _show_menu() -> void:
	_help.hide()
	_rows.show()
	_resume.grab_focus()
