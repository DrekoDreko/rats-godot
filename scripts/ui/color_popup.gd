class_name ColorPopup
extends PopupPanel
## The palette, as a small window: the eight swatches from the wall of the van,
## on the menu screen instead.
##
## It is `color_station.gd` without the raycast. Everything below the button is
## identical, and deliberately so — a man does not take a colour, he *asks* the
## host for one, and either it is written on every machine at once or he is told
## no. That rule is what keeps two players from wearing the same colour when both
## reach for it in the same frame, and it lives in `ColorManager` where both the
## panel and this can lean on it.
##
## **The refusal is visible.** A swatch somebody else is wearing is drawn dark
## and disabled, so the usual case never reaches the host at all; but a colour
## taken between the popup opening and the button being pressed still can, and
## what comes back is a sentence in the footer rather than nothing.

## The names on the swatches, in the order they hang. The same list
## `color_station.gd` keeps, for the same eight colours in
## `SessionManager.COLORS`.
const COLOR_NAMES: Array[String] = [
	"red", "blue", "green", "yellow", "orange", "purple", "cyan", "pink",
]

## Four across, two down — the arrangement on the van's wall.
const COLUMNS := 4

## The side of a swatch.
const SWATCH_SIZE := 26

## How far a taken colour is darkened. Enough to read as unavailable without
## becoming a different colour.
const TAKEN_DIM := 0.35

var _grid: GridContainer


func _ready() -> void:
	# A colour can be settled while the tree is paused, so the redraw has to be
	# able to run then too — the same reason `ColorManager` keeps processing.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	add_child(_grid)

	for index in SessionManager.COLORS.size():
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(SWATCH_SIZE, SWATCH_SIZE)
		swatch.tooltip_text = COLOR_NAMES[index] if index < COLOR_NAMES.size() else ""
		swatch.pressed.connect(_on_swatch_pressed.bind(index))
		_grid.add_child(swatch)

	ColorManager.color_changed.connect(_on_color_changed)
	SessionManager.player_joined.connect(_on_crew_changed)
	SessionManager.player_left.connect(_on_crew_changed)


## Shows the palette, drawn as it stands right now. Anything could have changed
## since it was last looked at, so it is redrawn on the way up rather than kept
## in step while it is hidden.
func open() -> void:
	refresh()
	popup_centered()


## Repaints every swatch: taken ones dark and dead, ours ringed in white, free
## ones in their own colour.
func refresh() -> void:
	var ours := LobbyManager.our_crew_id()
	var mine := SessionManager.color(ours)
	for index in _grid.get_child_count():
		var swatch := _grid.get_child(index) as Button
		if swatch == null:
			continue
		var color := ColorManager.color_at(index)
		var free := ColorManager.is_available(index, ours)
		var is_mine := free and color.is_equal_approx(mine)
		swatch.disabled = not free
		_paint(swatch, color if free else color.darkened(1.0 - TAKEN_DIM), is_mine)


## Dresses one swatch. All four states get the same box on purpose: a swatch is
## read as a colour, and a hover that repaints it is a hover that lies.
func _paint(swatch: Button, color: Color, ringed: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	var border := 2 if ringed else 1
	style.border_width_left = border
	style.border_width_top = border
	style.border_width_right = border
	style.border_width_bottom = border
	style.border_color = Color(1, 1, 1, 0.9) if ringed else Color(0, 0, 0, 0.6)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		swatch.add_theme_stylebox_override(state, style)


func _on_swatch_pressed(index: int) -> void:
	ColorManager.request_color(LobbyManager.our_crew_id(), index)


## The colour was settled. Our own request going through closes the popup — the
## man got what he came for; somebody else's only repaints it, since he may
## still be choosing.
func _on_color_changed(steam_id: int, _color: Color) -> void:
	refresh()
	if steam_id == LobbyManager.our_crew_id():
		hide()


func _on_crew_changed(_steam_id: int) -> void:
	refresh()
