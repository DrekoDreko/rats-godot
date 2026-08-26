extends Control
## The lobby browser: where a player finds somebody else's hunt and joins it.
##
## It used to be the screen the game opened on, and it is now a window over the
## top of `menu.tscn`. What lived here has been leaving one piece at a time as
## the menu grew a place for it: the Play button went first, then Create — the
## menu opens a lobby for you the moment it comes up, so a button asking for one
## you already have is a button that can only take it away — and then the guest
## list, because the crew is standing on the floor behind this window with their
## names over their heads. Reading them off a panel on top of that is asking the
## player to look at the worse copy.
##
## What is left is the one thing the menu has no room for: searching. Type an ID
## or pick a row, and join.
##
## It holds no state of its own. Everything on it is drawn from `LobbyManager` —
## the lobby it is in, what is open out there — and every button on it is one
## call into the manager. That is the whole point of the split: the manager is
## testable without a screen, and this file has nothing to get wrong except what
## it puts where.
##
## With Steam closed the window still comes up and says so.

## The player closed the window. The menu behind it is what hides this — a window
## that hides itself is one the menu cannot keep track of.
signal close_requested()

const ERROR_COLOR := Color(0.95, 0.32, 0.28)
const NOTICE_COLOR := Color(0.55, 0.85, 0.45)
const IDLE_COLOR := Color(1, 1, 1, 0.6)

@onready var _rows: VBoxContainer = $Center/Panel/Margin/Rows
@onready var _close: Button = _rows.get_node("TitleRow/Close")
@onready var _code: LineEdit = _rows.get_node("JoinRow/Code")
@onready var _join: Button = _rows.get_node("JoinRow/Join")
@onready var _refresh: Button = _rows.get_node("Refresh")
@onready var _lobbies: ItemList = _rows.get_node("Lobbies")
@onready var _leave: Button = _rows.get_node("Leave")
@onready var _status: Label = _rows.get_node("Status")

## The lobbies the last search turned up, in the order the list shows them, so a
## clicked row can be turned back into an ID.
var _found: Array[Dictionary] = []

## Whether the lobby we are waiting on is one this window asked for.
##
## The window closes itself on a successful join, and this is what stops it
## closing on somebody else's: the menu opens a lobby of its own the moment it
## comes up, and that `lobby_entered` can land while the player is reading this
## list — which without the flag would shut the browser under his hands.
var _we_asked := false


func _ready() -> void:
	_join.pressed.connect(_on_join_pressed)
	_code.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_refresh.pressed.connect(_on_refresh_pressed)
	_lobbies.item_selected.connect(_on_lobby_selected)
	_lobbies.item_activated.connect(_on_lobby_activated)
	_leave.pressed.connect(_on_leave_pressed)
	_close.pressed.connect(func() -> void: close_requested.emit())

	LobbyManager.lobby_entered.connect(_on_lobby_entered)
	LobbyManager.lobby_left.connect(_on_lobby_left)
	LobbyManager.lobby_list_updated.connect(_on_lobby_list_updated)
	LobbyManager.lobby_failed.connect(_on_lobby_failed)

	if SteamManager.is_online:
		# The player should land on a list, not on an empty box asking to be
		# told what to do.
		LobbyManager.refresh_lobbies()
	else:
		_say("Steam is not running.", ERROR_COLOR)

	_refresh_controls()

# --- The buttons ------------------------------------------------------------

func _on_join_pressed() -> void:
	var typed := _code.text.strip_edges()
	if typed.is_empty():
		_say("Paste a lobby ID, or pick one from the list.", ERROR_COLOR)
		return
	if typed.to_int() == LobbyManager.lobby_id:
		_say("That one is yours — you are already in it.", ERROR_COLOR)
		return
	if LobbyManager.join_lobby(typed.to_int()):
		_we_asked = true
		_say("Joining...", IDLE_COLOR)


func _on_refresh_pressed() -> void:
	if LobbyManager.refresh_lobbies():
		_say("Looking for lobbies...", IDLE_COLOR)


## Leaving is the one thing done here that the player watches happen behind the
## window, so the window gets out of the way. The menu seats him back on the
## floor alone on `lobby_left`, and that is what he should be looking at.
func _on_leave_pressed() -> void:
	LobbyManager.leave_lobby()
	close_requested.emit()


## Picking a row fills the ID field, which is what JOIN reads. Our own row is
## shown but not selectable, so there is nothing to guard against here beyond the
## bounds check.
func _on_lobby_selected(index: int) -> void:
	if index < _found.size():
		_code.text = str(_found[index]["lobby_id"])


func _on_lobby_activated(index: int) -> void:
	_on_lobby_selected(index)
	_on_join_pressed()

# --- What the manager says --------------------------------------------------

## Joining is the whole point of the window, so a join closes it: the crew the
## player has just landed among is drawn on the floor behind here.
func _on_lobby_entered(lobby_id: int, _is_host: bool) -> void:
	_code.text = str(lobby_id)
	# Which row is ours has just changed, and the list on screen was drawn
	# before it did.
	_draw_lobbies()
	_refresh_controls()
	if _we_asked:
		_we_asked = false
		close_requested.emit()


func _on_lobby_left() -> void:
	_draw_lobbies()
	_refresh_controls()


func _on_lobby_list_updated(lobbies: Array[Dictionary]) -> void:
	_found = lobbies
	_draw_lobbies()
	if lobbies.is_empty():
		_say("No lobbies open.", IDLE_COLOR)
	else:
		_say("%d lobby(s) open." % lobbies.size(), NOTICE_COLOR)


## Every failure the player is allowed to see comes through here, and it is the
## only thing that paints the status line red.
func _on_lobby_failed(reason: String) -> void:
	_we_asked = false
	_say(reason, ERROR_COLOR)
	_refresh_controls()

# --- Drawing ----------------------------------------------------------------

## The list, from `_found`, with our own lobby drawn differently.
##
## Our own comes back in the search like any other — it is a real open lobby, and
## hiding it would only make the player wonder where the one the menu opened for
## him went. It is greyed and marked instead, and the row is turned off so that
## neither a click nor a double-click can put its ID in the field. That is the
## first of three doors on the same mistake: `_on_join_pressed` refuses a typed
## ID that is ours, and `LobbyManager.join_lobby` refuses it again for callers
## that never came through this window.
##
## Redrawn whenever the answer could change — a new list, or us walking into or
## out of a lobby — because "ours" is a fact about two things and only one of
## them is the list.
func _draw_lobbies() -> void:
	_lobbies.clear()
	for lobby in _found:
		var ours: bool = int(lobby["lobby_id"]) == LobbyManager.lobby_id
		var index := _lobbies.add_item("%s  (%d/%d)%s" % [
			lobby["host_name"], lobby["players"], lobby["max_players"],
			"  - YOURS" if ours else "",
		])
		if ours:
			_lobbies.set_item_disabled(index, true)
			_lobbies.set_item_custom_fg_color(index, IDLE_COLOR)

## Which buttons make sense depends only on whether we are in a lobby and
## whether Steam is up, so it is worked out in one place and never guessed at
## from the button that was just pressed.
##
## Joining while already in a lobby is allowed and is the ordinary way in: the
## menu opens one for every player the moment he arrives, so a browser that
## refused to join until he left it would be a browser nobody could use. It is
## `LobbyManager` that walks him out of the old one on the way into the new.
func _refresh_controls() -> void:
	var online := SteamManager.is_online
	var in_lobby := LobbyManager.lobby_id != 0

	_join.disabled = not online
	_refresh.disabled = not online
	_leave.disabled = not in_lobby


func _say(message: String, color: Color) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", color)
