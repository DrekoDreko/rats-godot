class_name ColorScreen
extends Control
## The palette, as a page of the terminal: the eight colours of the crew,
## picked on the CRT in the back of the van instead of on the menu, with the
## man himself stood beside them wearing the one that is on him now.
##
## It used to be a popup on the menu screen (`color_popup.gd`) and, before
## that, a wall of swatches in the van (`color_station.gd`). Both are gone: a
## colour is chosen where the rest of the crew's bookkeeping is already read,
## and it can be changed on the road as well as in the yard, since the terminal
## is up in both.
##
## **It decides nothing.** A man does not take a colour, he *asks* the host for
## one, and either it is written on every machine at once or he is told no.
## That rule is what keeps two players from wearing the same colour when both
## reach for it in the same frame, and it lives in `ColorManager`.
##
## **The refusal is visible.** A swatch somebody else is wearing is drawn dark
## and dead, so the usual case never reaches the host at all; but a colour
## taken between the page coming up and the button being pressed still can, and
## what comes back is a line in the footer rather than nothing.
##
## **The body is the answer, not the swatch.** A ringed tile says which colour
## was asked for; the suit on the left says what it *looks* like, which is the
## only thing anybody actually chooses on. It is the same preview the shop uses
## (`scripts/ui/store_screen.gd`) — a `PlayerModel` in a world of its own — and
## it is repainted off the host's answer, so what stands there is never a colour
## we merely hoped to be given.

## The names on the swatches, in the order they hang. The same list
## `ColorManager` keeps, for the same eight colours in `SessionManager.COLORS`.
const COLOR_NAMES: Array[String] = [
	"RED", "BLUE", "GREEN", "YELLOW", "ORANGE", "PURPLE", "CYAN", "PINK",
]

## Four across, two down — the arrangement the palette has always had.
const COLUMNS := 4

## The smallest a swatch is drawn. Smaller than it used to be because the man
## now has the left third of the glass: the grid is stretched to whatever is
## left over, and this is only the floor under it.
const SWATCH_SIZE := Vector2(92, 52)

## How far a taken colour is darkened. Enough to read as unavailable without
## becoming a different colour.
const TAKEN_DIM := 0.35

## The body on the left, and the PS1 dressing that makes it match the one in the
## van. The preview renders in a world of its own, where the van's own applier
## cannot reach it.
const MODEL_SCENE := preload("res://scenes/player_model.tscn")
const PS1_SCENE := preload("res://scenes/ps1.tscn")

## What he is doing while he is being dressed: standing still.
const PREVIEW_STATE := PlayerAvatar.State.IDLE

## The snapping grid the preview is pinned to. The PS1 shader reads its grid off
## the viewport it is drawn in, and this one is a 150 px strip rather than the
## game's own 854x480 — left alone the suit would be snapped several times
## harder here than out of the windscreen, which is a different model and not a
## preview of this one. See `StoreScreen.PREVIEW_JITTER_GRID`.
const PREVIEW_JITTER_GRID := 156.0

## How far the man turns per pixel the mouse is dragged across him. A little
## under half a turn for a drag the full width of the frame, which is enough to
## walk around the back of the suit without the pointer leaving the picture.
const DRAG_DEGREES_PER_PIXEL := 0.6

@onready var _grid: GridContainer = $Root/Margin/Rows/Body/Grid
@onready var _status: Label = $Root/Margin/Rows/Status
@onready var _preview: SubViewportContainer = $Root/Margin/Rows/Body/Left/Preview
@onready var _seat: Node3D = $Root/Margin/Rows/Body/Left/Preview/View/Seat
@onready var _player_name: Label = $Root/Margin/Rows/Body/Left/PlayerName

## The body in the preview, built once and repainted as the colour changes.
var _model: PlayerModel
## Whether the man is being turned right now, and where the pointer was when he
## was last turned. The distance is measured here rather than read off the
## event: the monitor these pages are drawn on carries the mouse in by hand and
## zeroes `relative` on the way (`scripts/session/store_terminal.gd`), so the
## only honest delta is the one between two positions we saw ourselves.
var _dragging := false
var _drag_from := Vector2.ZERO


func _ready() -> void:
	visible = false
	_grid.columns = COLUMNS

	for index in SessionManager.COLORS.size():
		var swatch := Button.new()
		swatch.custom_minimum_size = SWATCH_SIZE
		swatch.text = COLOR_NAMES[index] if index < COLOR_NAMES.size() else ""
		# The name is read over eight different backgrounds, one of them yellow.
		# White on a black outline is the only pair that holds on all of them.
		swatch.add_theme_color_override("font_color", Color.WHITE)
		swatch.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.6))
		swatch.add_theme_color_override("font_outline_color", Color.BLACK)
		swatch.add_theme_constant_override("outline_size", 4)
		swatch.pressed.connect(_on_swatch_pressed.bind(index))
		_grid.add_child(swatch)

	_build_preview()
	_preview.gui_input.connect(_on_preview_input)

	ColorManager.color_changed.connect(_on_color_changed)
	ColorManager.request_refused.connect(_on_refused)
	SessionManager.player_joined.connect(_on_crew_changed)
	SessionManager.player_left.connect(_on_crew_changed)
	SettingsManager.streamer_mode_changed.connect(
		func(_enabled: bool) -> void: _refresh_player())


## Shows the page, drawn as it stands right now. Anything could have changed
## since it was last looked at, so it is redrawn on the way up rather than kept
## in step while it is hidden.
func open() -> void:
	_status.text = ""
	refresh()
	visible = true


func close() -> void:
	# A drag left in the air when the page goes is a drag nobody finished:
	# dropped here rather than left to turn the man on the first click of the
	# next visit.
	_dragging = false
	visible = false


func is_open() -> bool:
	return visible


## Repaints every swatch: taken ones dark and dead, ours ringed in white, free
## ones in their own colour — and the suit beside them in whichever one is ours.
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
	_refresh_player()


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

# --- The man on the left ----------------------------------------------------

## The body in the preview. It renders in a world of its own inside the
## `SubViewport`, so it is lit by that scene's own lamps rather than by whatever
## corner of the van the player happens to be standing in — and so that turning
## it turns nothing anybody else can see.
func _build_preview() -> void:
	_model = MODEL_SCENE.instantiate() as PlayerModel
	_seat.add_child(_model)
	# The van dresses its models from an applier at the root of the scene, and
	# that applier cannot see into another world. This one carries its own.
	var applier := PS1_SCENE.instantiate()
	applier.jitter_grid = PREVIEW_JITTER_GRID
	_model.add_child(applier)
	# The pose is set after the model is in the tree: `set_state` reaches for the
	# `AnimationPlayer` through an `@onready`, which is not resolved before then.
	_model.set_state(PREVIEW_STATE)


## Repaints the man and rewrites his name. Both live on `SessionManager`, put
## there by the host, so there is nothing decided here — only redrawn.
func _refresh_player() -> void:
	var us := LobbyManager.our_crew_id()
	var color := SessionManager.color(us)
	if _model != null:
		_model.set_tint(color)
	var entry := SessionManager.player(us)
	_player_name.text = ColorManager.display_name_for(us) if SettingsManager.streamer_mode \
		else String(entry.get("name", "PLAYER")).to_upper()
	_player_name.add_theme_color_override("font_color", color)


## Turns him by dragging on him. The seat is what moves and not the camera, so
## the lamps stay where they are and the suit is lit the same from every side.
##
## Only the picture hears this: the frame is the one thing on the page that
## stops the mouse, and the swatches beside it are plain buttons as before.
func _on_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		_dragging = button.pressed
		_drag_from = button.position
	elif event is InputEventMouseMotion and _dragging:
		var at := (event as InputEventMouseMotion).position
		_seat.rotate_y(deg_to_rad((at.x - _drag_from.x) * DRAG_DEGREES_PER_PIXEL))
		_drag_from = at

# --- What comes back off the wire -------------------------------------------

func _on_swatch_pressed(index: int) -> void:
	_status.text = ""
	ColorManager.request_color(LobbyManager.our_crew_id(), index)


## The colour was settled. Somebody else's only repaints the page, since he may
## have taken what we were about to reach for.
func _on_color_changed(_steam_id: int, _color: Color) -> void:
	if visible:
		refresh()


## The host turned a request down — the colour was taken in the meantime. It is
## shown rather than swallowed: a button that does nothing and says nothing is
## indistinguishable from a broken one.
func _on_refused(reason: String) -> void:
	if not visible:
		return
	_status.text = reason
	refresh()


func _on_crew_changed(_steam_id: int) -> void:
	if visible:
		refresh()
