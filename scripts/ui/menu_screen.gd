extends Node3D
## The screen the game opens on: the crew, the job, and the button that starts
## the shift.
##
## It replaces two screens that used to be one thing split in half — a text list
## of names (`lobby.tscn`) followed by a parked van the player had to walk around
## to pick a colour and read a contract. Here the crew stands in front of the
## camera and everything that used to be a panel on a wall is a control on the
## glass.
##
## **It holds no state.** Every autoload it talks to already owns its own
## decision: `LobbyManager` owns the guest list, `ColorManager` the palette,
## `ReadyManager` the flags, `ContractManager` the board, and `PhaseManager` the
## move out of here. This file listens to all five and redraws. That is the same
## split `lobby_screen.gd` was written to, and it is why none of the networking
## had to change to put a menu in front of it.
##
## **The lobby opens itself.** A crew that only appears after somebody presses
## "create" is a screen with nothing on it, so the menu asks for a lobby the
## moment it comes up — but only if there is not one already, because coming back
## from a shift, being redirected by `NetworkGuard`, and accepting an invite from
## outside the game all arrive here with one in hand.


## The colours the status line reads in, matching `lobby_screen.gd` so that the
## same kind of news is the same colour on both screens.
const ERROR_COLOR := Color(0.95, 0.32, 0.28)
const NOTICE_COLOR := Color(0.55, 0.85, 0.45)
const IDLE_COLOR := Color(1, 1, 1, 0.6)

## How high above a man's feet his card floats, in metres. Just over head height
## on a crouched body, so the picture sits above him rather than on him.
const CARD_HEIGHT := 1.62

## The card itself, dressed in its own scene so the font and the sizes are set
## where they can be seen.
const CARD_SCENE := preload("res://scenes/menu_player_card.tscn")

@onready var _crew: MenuCrew = $Crew
@onready var _camera: Camera3D = $Camera
@onready var _cards: Control = $UI/Cards
@onready var _photo: TextureRect = $UI/LocalPlayer/Photo
@onready var _name: Label = $UI/LocalPlayer/Name
@onready var _play: Button = $UI/Center/Play
@onready var _public: Button = $UI/Center/PublicLobbies
@onready var _settings: Button = $UI/Center/Settings
@onready var _status: Label = $UI/Status
@onready var _color_popup: ColorPopup = $UI/ColorPopup
@onready var _contracts: ContractPanel = $UI/ContractPanel
@onready var _modal: Control = $UI/LobbyModal

## The floating cards, by account, so that a crew that changed by one man does
## not rebuild all four.
var _card_of: Dictionary[int, MenuPlayerCard] = {}


func _ready() -> void:
	# The player may be arriving from a hunt, where the mouse was captured.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	_play.pressed.connect(_on_play_pressed)
	_public.pressed.connect(_on_public_pressed)
	_settings.disabled = true

	_modal.hide()
	if _modal.has_signal("close_requested"):
		_modal.close_requested.connect(_modal.hide)

	LobbyManager.lobby_entered.connect(_on_lobby_entered)
	LobbyManager.lobby_left.connect(_on_lobby_left)
	LobbyManager.members_changed.connect(_on_members_changed)
	LobbyManager.lobby_failed.connect(_on_lobby_failed)
	NetworkGuard.host_disconnected.connect(_on_host_disconnected)
	LobbyManager.peer_identified.connect(_on_peer_identified)

	ColorManager.request_refused.connect(_on_refused)
	ReadyManager.request_refused.connect(_on_refused)
	ContractManager.request_refused.connect(_on_refused)
	SessionManager.player_changed.connect(_on_player_changed)
	SessionManager.player_joined.connect(_on_player_changed)
	SessionManager.player_left.connect(_on_player_changed)
	SteamAvatars.avatar_ready.connect(_on_avatar_ready)

	_draw_local_player()
	_open_a_lobby()

	_seat_the_solo_player()

	# A redirect from `NetworkGuard` — the host dropped mid-shift and we have
	# been sent home. The reason replaces the welcome line, and is cleared so a
	# second visit does not show yesterday's complaint.
	if not NetworkGuard.pending_reason.is_empty():
		_say(NetworkGuard.pending_reason, ERROR_COLOR)
		NetworkGuard.pending_reason = ""

	_refresh()


## The cards are pinned to bodies in the world, so they are placed after the
## camera has settled for the frame rather than on a signal.
func _process(_delta: float) -> void:
	for steam_id in _card_of:
		_place_card(steam_id)

# --- The lobby --------------------------------------------------------------

## Opens a lobby to put a crew in, unless there is one already.
##
## The guard is the whole of it. Coming back from a shift, being redirected by
## `NetworkGuard`, or arriving on `+connect_lobby` from a Steam invite all land
## here holding a lobby, and creating a second would walk the player out of the
## first — out of the very lobby his friends are sitting in.
##
## With Steam shut there is nothing to create and nothing to say about it: the
## screen draws one body, the player's own, and Play still starts a solo shift.
## That is the ordinary state in development and is not worth an error line.
func _open_a_lobby() -> void:
	if not SteamManager.is_online:
		_say("Steam is not running — solo only.", IDLE_COLOR)
		return
	if LobbyManager.lobby_id != 0:
		return
	if LobbyManager.create_lobby(LobbyManager.MAX_PLAYERS):
		_say("Opening a lobby...", IDLE_COLOR)


## Puts the one man who is here on the crew, when there is no lobby to seat him
## off. `seat_the_crew` files him under `SOLO_STEAM_ID` and gives him a colour,
## which is what puts a body on the floor and a card over it.
##
## It refuses to run in two cases, and both are ones where a man was seated who
## should not have been:
##
## - **A crew already exists.** A player just sent home by `NetworkGuard` holds
##   the crew he was hunting with for the moment it takes the wipe to happen, and
##   seating a solo player over it leaves a menu showing bodies for players who
##   are on no wire — plus one for himself, under a second account number.
## - **A wire is a frame away** (`--host`, `--join`, a Steam invite). The solo
##   man would be registered first and take the first colour off the palette, and
##   the real player arriving behind him would be handed the second — which is
##   how a host ends up wearing a colour he never picked.
func _seat_the_solo_player() -> void:
	if LobbyManager.lobby_id != 0 or LobbyManager.wire_is_coming:
		return
	if not SessionManager.players.is_empty():
		return
	LobbyManager.seat_the_crew()

# --- The buttons ------------------------------------------------------------

## Play for the host, Ready for everybody else. The host is not made to wait on
## the crew — he can pull off with men still un-ready, the same way the ready
## boards in the van never blocked him — so the count on his button is news and
## not a lock.
func _on_play_pressed() -> void:
	if _we_are_the_host():
		LobbyManager.start_game()
		return
	ReadyManager.request_toggle(LobbyManager.our_crew_id())



func _on_public_pressed() -> void:
	_modal.show()

# --- Drawing ----------------------------------------------------------------

## Everything that depends on who is here and what they have chosen. Cheap
## enough to call from any signal, which is what every listener below does
## rather than each working out its own slice.
func _refresh() -> void:
	var crew := _crew_on_screen()
	_crew.rebuild(crew)
	_refresh_cards(crew)
	_refresh_play()
	_contracts.refresh()


## Who to draw. Over Steam it is the lobby's guest list, which is Valve's and is
## the one that can have somebody on it this machine has not seated yet. Alone it
## is the shift's own crew — a solo player has no guest list, and reading one
## would leave him looking at an empty floor.
##
## The two agree whenever both exist: `seat_the_crew` copies the first into the
## second every time the guest list moves.
func _crew_on_screen() -> Array[Dictionary]:
	var crew := LobbyManager.list_players()
	if not crew.is_empty():
		return crew
	for steam_id in SessionManager.players:
		var player := SessionManager.player(steam_id)
		crew.append({
			"steam_id": steam_id,
			"name": String(player.get("name", "")),
			"is_host": bool(player.get("is_host", false)),
		})
	return crew


## Our own name and picture, in the corner. It is drawn once and then only when
## Steam has more to say — the local player's name does not change while he is
## looking at it.
func _draw_local_player() -> void:
	_name.text = LobbyManager.our_name()
	_photo.texture = SteamAvatars.texture_of(LobbyManager.our_steam_id())


## One card per body on screen. Cards for men who left are freed; men who stayed
## keep the card they had, so a photograph that has arrived is not thrown away
## because somebody else knocked.
func _refresh_cards(crew: Array[Dictionary]) -> void:
	var seen: Dictionary[int, bool] = {}
	for player in crew:
		var steam_id := int(player["steam_id"])
		if steam_id == 0 or _crew.seat_of(steam_id) == null:
			continue
		seen[steam_id] = true
		var card: MenuPlayerCard = _card_of.get(steam_id)
		if card == null:
			card = CARD_SCENE.instantiate()
			_card_of[steam_id] = card
			_cards.add_child(card)
			card.setup(steam_id, String(player["name"]))
			card.color_pressed.connect(_on_card_color_pressed)
		else:
			card.set_player_name(String(player["name"]))
		# Written every time and not only on the way in: which crew entry is ours
		# is a question whose answer moves when the crew changes shape.
		card.is_ours = steam_id == LobbyManager.our_crew_id()
		card.refresh()
		_place_card(steam_id)

	for steam_id in _card_of.keys():
		if not seen.has(steam_id):
			_card_of[steam_id].queue_free()
			_card_of.erase(steam_id)


## Puts one card over the body it belongs to. A seat behind the camera would
## project to a point in front of it — `unproject_position` has no opinion about
## what is behind you — so it is hidden instead.
func _place_card(steam_id: int) -> void:
	var card: MenuPlayerCard = _card_of.get(steam_id)
	var seat := _crew.seat_of(steam_id)
	if card == null or seat == null:
		return
	var head := seat.global_position + Vector3.UP * CARD_HEIGHT
	if _camera.is_position_behind(head):
		card.hide()
		return
	card.show()
	var at := _camera.unproject_position(head)
	card.position = at - Vector2(card.size.x * 0.5, card.size.y)


## What the big button says. The host reads how many of his crew are ready; a
## client reads what pressing it would do.
func _refresh_play() -> void:
	if _we_are_the_host():
		var counts := ReadyManager.counts()
		_play.text = "PLAY  %d/%d" % [counts[0], counts[1]]
		return
	var ours := LobbyManager.our_crew_id()
	_play.text = "CANCEL" if ReadyManager.is_ready(ours) else "READY"


## Whether this machine decides. A solo player with no lobby is his own host,
## the same way `PhaseManager.is_host()` already treats him.
func _we_are_the_host() -> bool:
	return LobbyManager.lobby_id == 0 or LobbyManager.is_host


## A line in the footer. The one place this screen says anything in words.
func _say(message: String, color: Color) -> void:
	_status.text = message
	_status.add_theme_color_override("font_color", color)

# --- What the autoloads say -------------------------------------------------

func _on_lobby_entered(_lobby_id: int, is_host: bool) -> void:
	# The crew entries are what the colour and the ready flag are written
	# against, and in the menu both are chosen before anybody presses Play. So
	# the host seats his crew on the way *in* to the lobby rather than on the way
	# out of it. A client's crew still comes off the wire, through `JoinGate`.
	LobbyManager.seat_the_crew()
	_draw_local_player()
	_say("Hosting a lobby." if is_host else "Joined a lobby.", NOTICE_COLOR)
	_refresh()


## The lobby is gone, by our own hand or because it fell apart. `NetworkGuard`
## has wiped the crew that went with it by the time this runs, so what is left is
## to put ourselves back on the floor alone.
func _on_lobby_left() -> void:
	_say("Left the lobby.", IDLE_COLOR)
	_seat_the_solo_player()
	_refresh()


## The host dropped and we were sent home — to this screen, which is no longer
## reloaded for the occasion because it is where the player already was. The
## crew has been wiped; the man looking at the screen has not gone anywhere.
func _on_host_disconnected(_reason: String) -> void:
	_seat_the_solo_player()
	_refresh()


func _on_members_changed(_players: Array[Dictionary]) -> void:
	LobbyManager.seat_the_crew()
	_refresh()


## A lobby could not be opened or joined. Whatever this window was going to be,
## it is a solo game now, so somebody is put on the floor — `_seat_the_solo_player`
## is the one that decides whether that is true.
func _on_lobby_failed(reason: String) -> void:
	_say(reason, ERROR_COLOR)
	_seat_the_solo_player()
	_refresh()


## A peer introduced itself, which is how a name that came back "[unknown]"
## finally arrives.
func _on_peer_identified(_peer_id: int) -> void:
	_refresh()


func _on_player_changed(_steam_id: int) -> void:
	_refresh()


## A picture landed. It may be ours, one of the crew's, or both.
func _on_avatar_ready(steam_id: int, texture: ImageTexture) -> void:
	# The corner portrait is keyed off the Steam account and not off the crew
	# entry: a picture only ever exists for a real account, so `our_steam_id` is
	# the one that can match here.
	if steam_id == LobbyManager.our_steam_id():
		_photo.texture = texture
	var card: MenuPlayerCard = _card_of.get(steam_id)
	if card != null:
		card.set_photo(texture)


## The host turned a request down — a colour already worn, a signature from
## somebody who may not sign. It is shown rather than swallowed: a button that
## does nothing and says nothing is indistinguishable from a broken one.
func _on_refused(reason: String) -> void:
	_say(reason, ERROR_COLOR)


func _on_card_color_pressed() -> void:
	_color_popup.open()
