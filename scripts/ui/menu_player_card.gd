class_name MenuPlayerCard
extends VBoxContainer
## The label over a man's head on the menu: his Steam picture, his name, whether
## he is ready, and — on his own card only — the swatch that opens the palette.
##
## It is dressed in `menu_player_card.tscn` and instanced per player by
## `menu_screen.gd`: the font, the sizes and the colours are the scene's to set,
## and this file only writes what changes while the screen is up.
##
## It draws and it decides nothing. The picture comes from `SteamAvatars`, the
## colour and the ready flag from `SessionManager`, and pressing the swatch only
## says so — `menu_screen.gd` is what opens the palette, and `ColorManager` is
## what answers it.

## The swatch was pressed. Only ever emitted by the local player's own card,
## which is the only one that has one.
signal color_pressed()

## Whether this card belongs to the player looking at it — which decides whether
## it carries the swatch that opens the palette.
##
## It is not settled once and kept. `LobbyManager.our_crew_id()` can change its
## answer under a card that is already up: a man alone in the crew is himself by
## the rule that a crew of one is us, and a second man arriving takes that rule
## away. So the screen writes this on every refresh and the swatch follows it.
var is_ours := false

var _steam_id := 0

@onready var _photo: TextureRect = $Photo
@onready var _name: BigFontOutlinedLabel = $Name
@onready var _swatch: Button = $Swatch


func _ready() -> void:
	_swatch.pressed.connect(func() -> void: color_pressed.emit())


## Fills the card in for a player. Called by the screen straight after the
## instance is in the tree — `setup` and not `_ready` because the account has to
## be known before anything can be drawn, and a node cannot be handed an
## argument on the way in.
func setup(steam_id: int, player_name: String) -> void:
	_steam_id = steam_id
	_name.text = player_name
	_photo.texture = SteamAvatars.texture_of(steam_id)
	refresh()


## Redraws what may have changed since the last look: the colour on the swatch
## and whether the man has said he is ready. The picture and the name arrive on
## their own signals and are written by the two setters below.
func refresh() -> void:
	if not is_node_ready():
		return

	if ReadyManager.is_ready(_steam_id):
		_name.modulate = Color.GREEN

	# Only our own card offers the palette. Somebody else's colour is his to
	# change and nobody else's, which `ColorManager` refuses on the wire anyway —
	# this is the half of it the player can see.
	_swatch.visible = is_ours
	var style := StyleBoxFlat.new()
	style.bg_color = SessionManager.color(_steam_id)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.75)
	# All four states carry the same box: a swatch is read as a colour, and a
	# hover that changes the colour is a hover that lies about it.
	for state in ["normal", "hover", "pressed", "focus"]:
		_swatch.add_theme_stylebox_override(state, style)


## A name that arrived late — Steam answering `requestUserInformation` after the
## row was already drawn, which `LobbyManager` documents as the usual case.
func set_player_name(player_name: String) -> void:
	if is_node_ready() and _name.text != player_name:
		_name.text = player_name


## A picture that arrived late, which is every picture that was not already in
## Steam's memory when it was asked for.
func set_photo(texture: ImageTexture) -> void:
	if is_node_ready() and texture != null:
		_photo.texture = texture
