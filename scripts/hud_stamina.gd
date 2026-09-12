extends ProgressBar
## The sprint reserve over the health bar. The player owns the value and this
## node only reflects it, so every way a run can stop recovers in one place.
##
## It reflects two things and not one. The length of the bar is what is left,
## and its colour is whether that is enough to run on — which are not the same
## question, because an emptied reserve stays unusable while it fills back up
## (`player.gd: _exhausted`). Without the colour the player watches a bar that
## is visibly no longer empty and a Shift key that still does nothing, and there
## is nothing on screen to tell him why.

## The fill while the reserve can be run on, and while it cannot. The red is
## drained-and-locked, and it holds until enough has come back to sprint again
## rather than clearing the instant the bar starts moving.
const READY_COLOR := Color(1, 1, 1, 1)
const SPENT_COLOR := Color(0.78, 0.24, 0.2, 1)
## How long the fill takes to cross between the two. Short enough to read as the
## same gesture as running out, long enough not to be a flash.
const FADE_TIME := 0.18

var _fill: StyleBoxFlat
var _fade: Tween

func _ready() -> void:
	# Duplicated before anything is drawn: the style comes from the scene and is
	# shared, and tinting it in place would recolour every bar that uses it.
	var style := get_theme_stylebox(&"fill") as StyleBoxFlat
	if style != null:
		_fill = style.duplicate()
		add_theme_stylebox_override(&"fill", _fill)
	# The player is mounted into the game viewport during the first frame.
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.stamina_changed.connect(_on_stamina_changed)
	player.exhaustion_changed.connect(_on_exhaustion_changed)
	player.capture_started.connect(_on_capture_started)
	player.capture_finished.connect(_on_capture_finished)
	_on_stamina_changed(player.stamina(), player.max_stamina)
	_tint(player.is_exhausted(), false)


func _on_stamina_changed(current: float, maximum: float) -> void:
	value = 0.0 if maximum <= 0.0 else current / maximum


func _on_exhaustion_changed(exhausted: bool) -> void:
	_tint(exhausted, true)


## Straight to the colour at load, and eased into it afterwards: the first frame
## has nothing to animate from.
func _tint(exhausted: bool, animate: bool) -> void:
	if _fill == null:
		return
	var target := SPENT_COLOR if exhausted else READY_COLOR
	if _fade != null and _fade.is_running():
		_fade.kill()
	if not animate:
		_fill.bg_color = target
		return
	_fade = create_tween()
	_fade.tween_property(_fill, "bg_color", target, FADE_TIME)


func _on_capture_started(_rat: Node3D) -> void:
	hide()


func _on_capture_finished(_killed: bool) -> void:
	show()
