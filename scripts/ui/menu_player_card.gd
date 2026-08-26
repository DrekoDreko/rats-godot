class_name MenuPlayerCard
extends VBoxContainer
## The label over a man's head on the menu: his Steam picture, his name, whether
## he is ready, and — on his own card only — the swatch that opens the palette.
##
## It is built in code rather than dressed in the scene for the reason
## `lobby_screen.gd` gives about its own rows: there is one of these per player,
## and how many there are changes while the screen is up, which is the very thing
## the screen exists to show.
##
## It draws and it decides nothing. The picture comes from `SteamAvatars`, the
## colour and the ready flag from `SessionManager`, and pressing the swatch only
## says so — `menu_screen.gd` is what opens the palette, and `ColorManager` is
## what answers it.

## The swatch was pressed. Only ever emitted by the local player's own card,
## which is the only one that has one.
signal color_pressed()

## The picture, drawn at the size Steam hands it over at.
const PHOTO_SIZE := 64

## The swatch beneath it. Small, because it is a button and not a subject.
const SWATCH_SIZE := 14

## Same as everywhere else on this screen and in the van.
const FONT_SIZE := 8
const OUTLINE_SIZE := 5

## The green a ready man is marked in — `NOTICE_COLOR` from `lobby_screen.gd`,
## the same green a lit ready board burns.
const READY_COLOR := Color(0.55, 0.85, 0.45)

## Whether this card belongs to the player looking at it — which decides whether
## it carries the swatch that opens the palette.
##
## It is not settled once and kept. `LobbyManager.our_crew_id()` can change its
## answer under a card that is already up: a man alone in the crew is himself by
## the rule that a crew of one is us, and a second man arriving takes that rule
## away. So the screen writes this on every refresh and the swatch follows it.
var is_ours := false

var _steam_id := 0
var _photo: TextureRect
var _name: Label
var _swatch: Button
var _ready_mark: Label


## Builds the card for a player. Called once, straight after the node is in the
## tree — `setup` and not `_ready` because the account has to be known before
## anything can be drawn, and a node cannot be handed an argument on the way in.
func setup(steam_id: int, player_name: String) -> void:
	_steam_id = steam_id
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 1)
	# The card floats over a body and is positioned to the pixel by the screen;
	# a mouse-catching rectangle over the crew would eat clicks meant for the
	# buttons behind it. Only the swatch takes the mouse, and it says so itself.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_photo = TextureRect.new()
	_photo.custom_minimum_size = Vector2(PHOTO_SIZE, PHOTO_SIZE)
	_photo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# The game draws with nearest filtering throughout; a smoothed photograph is
	# the one soft thing on the screen.
	_photo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_photo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_photo.texture = SteamAvatars.texture_of(steam_id)
	add_child(_photo)

	_name = _label(player_name, Color.WHITE)
	add_child(_name)

	# The swatch is built whether or not it is ours and shown by `refresh`, so
	# that a card which becomes ours later has one to show rather than having to
	# be rebuilt around it.
	_swatch = Button.new()
	_swatch.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
	_swatch.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_swatch.tooltip_text = "Pick your colour"
	_swatch.pressed.connect(func() -> void: color_pressed.emit())
	add_child(_swatch)

	_ready_mark = _label("READY", READY_COLOR)
	_ready_mark.hide()
	add_child(_ready_mark)

	refresh()


## Redraws what may have changed since the last look: the colour on the swatch
## and whether the man has said he is ready. The picture and the name arrive on
## their own signals and are written by the two setters below.
func refresh() -> void:
	if _ready_mark != null:
		_ready_mark.visible = ReadyManager.is_ready(_steam_id)
	if _swatch != null:
		# Only our own card offers the palette. Somebody else's colour is his to
		# change and nobody else's, which `ColorManager` refuses on the wire
		# anyway — this is the half of it the player can see.
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
	if _name != null and _name.text != player_name:
		_name.text = player_name


## A picture that arrived late, which is every picture that was not already in
## Steam's memory when it was asked for.
func set_photo(texture: ImageTexture) -> void:
	if _photo != null and texture != null:
		_photo.texture = texture


## A line of text in the house style: small, white or coloured, outlined so it
## reads against a body or against the floor behind it.
func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	return label
