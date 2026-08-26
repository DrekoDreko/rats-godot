extends Control
## The strangling prompt: it shows up when the player grabs a rat, showing the
## button that kills it and how far its neck has already been squeezed.
##
## Meanwhile the crosshair leaves the screen — there is nothing to aim at with
## your hands full.

## The pressure turns red and the prompt starts blinking when the rat is about
## to get loose.
const DANGER_PRESSURE := 0.12
const NORMAL_COLOR := Color(0.94, 0.86, 0.36)
const DANGER_COLOR := Color(0.95, 0.32, 0.28)
## Blinks per second of the prompt, when the pressure is running out.
const BLINKS := 6.0

## The crosshair, which leaves the screen while the hands are busy. It is a path
## and not a direct node reference: an exported node only wires itself up in a
## scene saved by the editor, and the `world.tscn` HUD is written by hand.
@export var crosshair_path := NodePath("../Crosshair")

@onready var button: Label = $VBoxContainer/Button
@onready var bar: ProgressBar = $VBoxContainer/Bar
@onready var crosshair: Control = get_node_or_null(crosshair_path)

var _pressure := 0.0

func _ready() -> void:
	hide()
	set_process(false)
	# Wait one frame so the player is already in the tree.
	# Held onto before the wait rather than fetched again after it: a phase can
	# end on the frame this HUD is waiting through — the board in the van does
	# exactly that — and the node then resumes already out of the tree, where
	# `get_tree()` is null and reaching through it throws.
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

func _process(_delta: float) -> void:
	if _pressure > DANGER_PRESSURE:
		button.modulate.a = 1.0
		return
	# Nearly escaping: the prompt blinks so the player hammers faster.
	button.modulate.a = 0.35 + 0.65 * absf(sin(Time.get_ticks_msec() / 1000.0 * PI * BLINKS))

func _on_capture_started(_rat: Node3D) -> void:
	_pressure = 0.0
	_update_colors()
	show()
	set_process(true)
	if crosshair != null:
		crosshair.hide()

func _on_progress(fraction: float) -> void:
	_pressure = fraction
	bar.value = fraction
	_update_colors()

func _on_finished(_killed: bool) -> void:
	hide()
	set_process(false)
	if crosshair != null:
		crosshair.show()

func _update_colors() -> void:
	var danger := _pressure <= DANGER_PRESSURE
	var color := DANGER_COLOR if danger else NORMAL_COLOR
	button.add_theme_color_override("font_color", color)
	bar.modulate = color
