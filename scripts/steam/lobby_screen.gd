extends Control
## The screen the game opens on: the one place a player picks who to hunt with.
##
## It holds no state of its own. Everything on it is drawn from
## `LobbyManager` — the lobby it is in, who is in it, what is open out there —
## and every button on it is one call into the manager. That is the whole point
## of the split: the manager is testable without a screen, and this file has
## nothing to get wrong except what it puts where.
##
## The player rows are built at runtime rather than dressed in the scene because
## there is one per person in the lobby and that number changes while the screen
## is up — which is precisely the thing this is here to show.
##
## With Steam closed the screen still comes up and says so, and `Play` still
## works: a solo hunt is the game's normal state during development.

## The whole game is drawn at 640x360, where 8 px is the normal size of a letter.
const FONT_SIZE := 8
## The star on the host's row, and the colour that goes with it.
const HOST_MARK := "*"
const HOST_COLOR := Color(0.94, 0.86, 0.36)
const ERROR_COLOR := Color(0.95, 0.32, 0.28)
const NOTICE_COLOR := Color(0.55, 0.85, 0.45)
const IDLE_COLOR := Color(1, 1, 1, 0.6)

@onready var _create: Button = $Margin/Rows/Body/Left/Create
@onready var _code: LineEdit = $Margin/Rows/Body/Left/JoinRow/Code
@onready var _join: Button = $Margin/Rows/Body/Left/JoinRow/Join
@onready var _refresh: Button = $Margin/Rows/Body/Left/Refresh
@onready var _lobbies: ItemList = $Margin/Rows/Body/Left/Lobbies
@onready var _header: Label = $Margin/Rows/Body/Right/Margin/Column/Header
@onready var _players: VBoxContainer = $Margin/Rows/Body/Right/Margin/Column/Players
@onready var _copy: Button = $Margin/Rows/Body/Right/Margin/Column/Copy
@onready var _leave: Button = $Margin/Rows/Footer/Leave
@onready var _invite: Button = $Margin/Rows/Footer/Invite
@onready var _play: Button = $Margin/Rows/Footer/Play
@onready var _status: Label = $Margin/Rows/Status

## The lobbies the last search turned up, in the order the list shows them, so a
## clicked row can be turned back into an ID.
var _found: Array[Dictionary] = []


func _ready() -> void:
	# The map takes the mouse away; the lobby needs it back, and the player may
	# well be arriving here from a hunt.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	for button in [_create, _join, _refresh, _copy, _leave, _invite, _play]:
		button.add_theme_font_size_override("font_size", FONT_SIZE)
	_code.add_theme_font_size_override("font_size", FONT_SIZE)
	_lobbies.add_theme_font_size_override("font_size", FONT_SIZE)

	_create.pressed.connect(_on_create_pressed)
	_join.pressed.connect(_on_join_pressed)
	_code.text_submitted.connect(func(_text: String) -> void: _on_join_pressed())
	_refresh.pressed.connect(_on_refresh_pressed)
	_lobbies.item_selected.connect(_on_lobby_selected)
	_lobbies.item_activated.connect(_on_lobby_activated)
	_copy.pressed.connect(_on_copy_pressed)
	_leave.pressed.connect(LobbyManager.leave_lobby)
	_invite.pressed.connect(LobbyManager.invite_friends)
	_play.pressed.connect(LobbyManager.start_game)

	LobbyManager.lobby_entered.connect(_on_lobby_entered)
	LobbyManager.lobby_left.connect(_on_lobby_left)
	LobbyManager.members_changed.connect(_show_players)
	LobbyManager.lobby_list_updated.connect(_on_lobby_list_updated)
	LobbyManager.lobby_failed.connect(_on_lobby_failed)

	if SteamManager.is_online:
		_say("Signed in as %s." % SteamManager.get_persona_name(), NOTICE_COLOR)
		# The player should land on a list, not on an empty box asking to be
		# told what to do.
		LobbyManager.refresh_lobbies()
	else:
		_say("Steam is not running — solo only.", ERROR_COLOR)

	_refresh_controls()
	_show_players(LobbyManager.list_players())

# --- The buttons ------------------------------------------------------------

func _on_create_pressed() -> void:
	if LobbyManager.create_lobby(LobbyManager.MAX_PLAYERS):
		_say("Opening a lobby...", IDLE_COLOR)


func _on_join_pressed() -> void:
	var typed := _code.text.strip_edges()
	if typed.is_empty():
		_say("Paste a lobby ID, or pick one from the list.", ERROR_COLOR)
		return
	if LobbyManager.join_lobby(typed.to_int()):
		_say("Joining...", IDLE_COLOR)


func _on_refresh_pressed() -> void:
	if LobbyManager.refresh_lobbies():
		_say("Looking for lobbies...", IDLE_COLOR)


func _on_lobby_selected(index: int) -> void:
	if index < _found.size():
		_code.text = str(_found[index]["lobby_id"])


func _on_lobby_activated(index: int) -> void:
	_on_lobby_selected(index)
	_on_join_pressed()


## The lobby ID is the whole of what a player has to send a friend who is not on
## their friends list, so it is one click away rather than something to read off
## the screen and type back in.
func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(str(LobbyManager.lobby_id))
	_say("Lobby ID copied — send it to whoever is joining.", NOTICE_COLOR)

# --- What the manager says --------------------------------------------------

func _on_lobby_entered(lobby_id: int, is_host: bool) -> void:
	_code.text = str(lobby_id)
	_say("In lobby %d — %s." % [lobby_id, "hosting" if is_host else "guest"], NOTICE_COLOR)
	_refresh_controls()


func _on_lobby_left() -> void:
	_refresh_controls()
	_show_players([])


func _on_lobby_list_updated(lobbies: Array[Dictionary]) -> void:
	_found = lobbies
	_lobbies.clear()
	for lobby in lobbies:
		_lobbies.add_item("%s  (%d/%d)" % [
			lobby["host_name"], lobby["players"], lobby["max_players"],
		])
	if lobbies.is_empty():
		_say("No lobbies open. Create one.", IDLE_COLOR)
	else:
		_say("%d lobby(s) open." % lobbies.size(), NOTICE_COLOR)


## Every failure the player is allowed to see comes through here, and it is the
## only thing that paints the status line red.
func _on_lobby_failed(reason: String) -> void:
	_say(reason, ERROR_COLOR)
	_refresh_controls()

# --- Drawing ----------------------------------------------------------------

## The list of everyone in the lobby, rebuilt whole. There are at most four of
## them, so keeping rows around to reuse would cost more thought than it saves.
func _show_players(players: Array[Dictionary]) -> void:
	for row in _players.get_children():
		row.queue_free()

	_header.text = "PLAYERS  %d/%d" % [players.size(), LobbyManager.MAX_PLAYERS]
	if players.is_empty():
		var empty := _label("nobody yet")
		empty.modulate.a = 0.55
		_players.add_child(empty)
		return

	for player in players:
		var mark := HOST_MARK if player["is_host"] else " "
		var row := _label("%s %s" % [mark, player["name"]])
		if player["is_host"]:
			row.add_theme_color_override("font_color", HOST_COLOR)
		_players.add_child(row)


## Which buttons make sense depends only on whether we are in a lobby and
## whether we opened it, so it is worked out in one place and never guessed at
## from the button that was just pressed.
func _refresh_controls() -> void:
	var online := SteamManager.is_online
	var in_lobby := LobbyManager.lobby_id != 0

	_create.disabled = not online or in_lobby
	_join.disabled = not online or in_lobby
	_refresh.disabled = not online or in_lobby
	_lobbies.visible = not in_lobby
	_copy.visible = in_lobby
	_leave.disabled = not in_lobby
	_invite.disabled = not in_lobby
	# A guest waits for the host. Alone, or with Steam closed, `Play` is the
	# solo hunt and stays available.
	_play.disabled = in_lobby and not LobbyManager.is_host
	_play.text = "PLAY" if in_lobby else "PLAY SOLO"


func _say(message: String, color: Color) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", color)


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 5)
	return label
