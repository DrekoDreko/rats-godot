extends SceneTree
## The store screen has to fit the monitor it is painted on.
##
## Run with: godot --script _test_store_layout.gd --quit-after 240
##
## Run it **with a window**, not `--headless`: the fake text server reports the
## wrong metrics for a font, so a headless run measures a screen nobody will see.
##
## What is checked: the racks are laid out in a viewport the size of the glass
## (`scenes/van_travel.tscn`), and nothing on them reaches past its edge. The
## title, the money and the footer are the three that went off the top and the
## bottom the last time the sizes moved, so they are named one by one.

## The glass on the totem, in its own pixels — kept next to the scene rather
## than read off it so a bench failure says which of the two moved.
const SCREEN_SIZE := Vector2i(640, 507)
## Frames of slack before measuring: the screen waits one for the character and
## the containers need a couple more to settle.
const SETTLE := 10
## How far the picture is shrunk for the film. The game's window is shorter than
## the glass, so an unshrunk frame is filmed with its footer off the bottom. It
## changes the film only: every measurement below is in the viewport's own pixels.
const FILM_SHRINK := 0.88

const STORE := "res://scenes/store_screen.tscn"

var _store: Control
var _clock := 0
var _failures := 0


func _initialize() -> void:
	Engine.max_fps = 60
	# The glass is shown in the window as well as measured, so that the same run
	# can be filmed with `--write-movie` and the racks looked at by eye.
	var frame := SubViewportContainer.new()
	# Shrunk to fit the game's own window, which is shorter than the glass. It
	# only changes the picture the film shows; every measurement below is taken
	# in the viewport's own pixels.
	frame.scale = Vector2.ONE * FILM_SHRINK
	root.add_child(frame)
	var viewport := SubViewport.new()
	viewport.size = SCREEN_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	frame.add_child(viewport)
	_store = (load(STORE) as PackedScene).instantiate() as Control
	viewport.add_child(_store)


func _physics_process(_delta: float) -> bool:
	_clock += 1
	if _clock == SETTLE:
		_store.call("open")
		return false
	if _clock < SETTLE * 2:
		return false
	_measure()
	print("store layout: %d failure(s)" % _failures)
	quit(1 if _failures > 0 else 0)
	return true


func _measure() -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(SCREEN_SIZE))
	var rows := _store.get_node("Root/Margin/Rows") as Control
	_inside("rows", rows, screen)
	for path in [
		"Root/Margin/Rows/Header/Title",
		"Root/Margin/Rows/Header/Money",
		"Root/Margin/Rows/Body/Left/PlayerName",
		"Root/Margin/Rows/Footer/Close",
	]:
		_inside(path.get_file(), _store.get_node(path) as Control, screen)
	var columns := _store.get_node("Root/Margin/Rows/Body/Columns") as Control
	for column in columns.get_children():
		for tile in (column as Control).get_children():
			if tile is Button:
				_inside("tile", tile as Control, screen)
				_whole(tile as Button)


## A tile is wide enough for the name written on it. A frame that trims the name
## to "Taco de Base…" is a frame nobody can shop off, and it is the one thing a
## rect check cannot see: the label stays inside the tile either way.
func _whole(tile: Button) -> void:
	for rows in tile.get_children():
		for label in (rows as Control).get_children():
			if not label is Label:
				continue
			var text := (label as Label).text
			if text.is_empty():
				continue
			var wanted := (label as Label).get_minimum_size().x
			if wanted <= (label as Label).size.x:
				continue
			_failures += 1
			print("  CUT  %-12s needs %d px, has %d" 				% [text, wanted, int((label as Label).size.x)])


func _inside(what: String, node: Control, screen: Rect2) -> void:
	var rect := node.get_global_rect()
	if screen.encloses(rect):
		print("  ok   %-12s %s" % [what, rect])
		return
	_failures += 1
	print("  OUT  %-12s %s is not inside %s" % [what, rect, screen])
