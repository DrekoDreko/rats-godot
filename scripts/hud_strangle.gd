extends Control
## Displays the timing state owned by Hands; input and hit detection stay there.

@export var crosshair_path := NodePath("../Crosshair")

@onready var button: BigFontOutlinedLabel = $VBoxContainer/Button
@onready var bar: Control = $VBoxContainer/Bar
@onready var crosshair: Control = get_node_or_null(crosshair_path)

var _pointer := 1.0
var _zone_start := 0.0
var _zone_width := 0.18
var _hits := 0

func _ready() -> void:
	bar.draw.connect(_draw_bar)
	hide()
	set_process(false)
	# Wait for the player, retaining the tree in case this HUD is removed.
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame

	# Out of the tree while we waited: the scene we belong to was freed, there is
	# nobody left to wire to, and this HUD goes out with the rest of it.
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.capture_started.connect(_on_capture_started)
	player.capture_progress.connect(_on_progress)
	player.capture_finished.connect(_on_finished)

	var hands := player.get_node("Head/Inventory").hands() as Hands
	if hands != null:
		hands.timing_changed.connect(_on_timing_changed)

func _on_capture_started(_rat: Node3D) -> void:
	_hits = 0
	_update_counter()
	show()
	if crosshair != null:
		crosshair.hide()


func _on_progress(fraction: float) -> void:
	_hits = roundi(fraction * Hands.HITS_TO_KILL)
	_update_counter()


func _update_counter() -> void:
	button.text = "%s  %d / %d" % [tr("HUD_STRANGLE_BUTTON"), _hits, Hands.HITS_TO_KILL]


func _on_timing_changed(pointer: float, zone_start: float, zone_width: float) -> void:
	_pointer = pointer
	_zone_start = zone_start
	_zone_width = zone_width
	bar.queue_redraw()


func _draw_bar() -> void:
	var track := Rect2(2.0, 6.0, bar.size.x - 4.0, bar.size.y - 12.0)
	bar.draw_rect(track, Color(0.03, 0.03, 0.03, 0.9))
	bar.draw_rect(Rect2(track.position.x + _zone_start * track.size.x,
		track.position.y, _zone_width * track.size.x, track.size.y), Color(0.3, 0.9, 0.35))
	bar.draw_rect(track, Color.WHITE, false, 2.0)
	var x := track.position.x + _pointer * track.size.x
	bar.draw_line(Vector2(x, 0.0), Vector2(x, bar.size.y), Color.BLACK, 7.0)
	bar.draw_line(Vector2(x, 0.0), Vector2(x, bar.size.y), Color.WHITE, 3.0)


func _on_finished(_killed: bool) -> void:
	hide()
	if crosshair != null:
		crosshair.show()
