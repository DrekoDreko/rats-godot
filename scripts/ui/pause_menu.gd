extends CanvasLayer
## The pause menu: a local overlay that keeps the online simulation running.
##
## **The pause is only visual.** This is an online game, so the scene tree keeps
## simulating rats and publishing their movement while this overlay is open.
## `get_tree().paused` is deliberately never changed here. A host that opens the
## menu must keep running the rat simulation and synchronizing its results.
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
## work even while the simulation continues underneath.
##
## **It is also where a player finds out who else is still here.** A man who has
## just watched somebody stop moving has one question, and it is not answered by
## the game carrying on around him: is that player gone, or is his line simply
## bad? So the menu carries the crew with a round trip against each name. The
## list itself is `scripts/ui/crew_list.gd` and belongs to nothing here — the
## scoreboard the crew holds Tab for draws the same rows, and a second copy of
## them would be a second place for the crew to look different.

## The lobby *screen*, one step before the van. It is where "Sair da partida"
## goes, and it is the same path `NetworkGuard` sends a stranded client to.
const LOBBY_SCENE := "res://scenes/menu.tscn"

@onready var _resume: Button = $Center/Panel/Margin/Rows/Resume
@onready var _leave: Button = $Center/Panel/Margin/Rows/Leave
@onready var _quit: Button = $Center/Panel/Margin/Rows/Quit
@onready var _crew: CrewList = $Center/Panel/Margin/Rows/Crew
@onready var _crew_title: BigFontOutlinedLabel = $Center/Panel/Margin/Rows/CrewTitle
@onready var _crew_separator: HSeparator = $Center/Panel/Margin/Rows/CrewSeparator
@onready var _how_to: Button = $Center/Panel/Margin/Rows/HowTo
@onready var _settings: Button = $Center/Panel/Margin/Rows/Settings
@onready var _settings_modal: Control = $SettingsMenu
## The controls page. It lives beside the buttons rather than on top of them, so
## the panel takes the size of whichever of the two is showing and the menu never
## has a page floating over a set of buttons that are still there underneath.
@onready var _help: VBoxContainer = $Center/Panel/Margin/Help
@onready var _rows: VBoxContainer = $Center/Panel/Margin/Rows
@onready var _help_back: Button = $Center/Panel/Margin/Help/Back

## Whether the menu is up. Kept rather than read off `visible`, because the two
## can part company for one frame while a scene is being changed under us.
var _open := false


func _ready() -> void:
	# The menu itself must keep running while it holds the tree paused —
	# otherwise the button that would unpause never hears the click, and the key
	# that would close it never arrives. It is the same reason every session
	# autoload is set this way, and the one node where getting it wrong is
	# immediately fatal rather than merely wrong.
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

	# The list keeps its own count of when to redraw and stops dead while it
	# cannot be seen, so a closed menu costs nothing. What is left here is the
	# heading and the rule above it, which are only hidden for a crew of nobody —
	# a bench, or a half-loaded scene. A solo player is a crew of one.
	SessionManager.player_joined.connect(_on_crew_changed)
	SessionManager.player_left.connect(_on_crew_changed)
	_on_crew_changed(0)

	_resume.pressed.connect(close)
	_how_to.pressed.connect(_show_help)
	_settings.pressed.connect(_settings_modal.show)
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


## Up: the overlay appears and the mouse comes loose to click with.
func open() -> void:
	if _open:
		return
	_open = true
	show()
	# Always up on the buttons, whatever page was last read.
	_show_menu()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Focused so the menu can be driven from the keyboard, and so that a
	# controller has somewhere to start.
	_resume.grab_focus()


## Down: the overlay disappears and the camera gets the mouse back.
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
	var tree := get_tree()
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
		var wrapper := tree.current_scene as GamePostProcessWrapper
		if wrapper != null:
			wrapper.change_scene_to_file(LOBBY_SCENE)
		else:
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

## The heading and the rule above the crew, hidden together with an empty crew
## rather than left as a labelled hole. That is the state a bench or a
## half-loaded scene is in; a solo player is a crew of one and gets his own row.
##
## The list under them looks after itself — it rebuilds on its own clock while it
## is on screen — so all that is needed here is the question "is there anybody at
## all", asked when somebody walks in or out.
func _on_crew_changed(_steam_id: int) -> void:
	var has_crew := not SessionManager.players.is_empty()
	_crew.visible = has_crew
	_crew_title.visible = has_crew
	_crew_separator.visible = has_crew


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
