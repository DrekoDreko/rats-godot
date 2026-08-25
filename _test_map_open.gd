extends SceneTree
## The E key opens the map table and the plan stays open.
##
## Regression bench for the open/close race: the player sits below the table in
## the tree, so it answered `interact` first and called `use()`; the same press
## then went on to the table's own handler, which read it as "close" and shut
## the viewer in the very frame it had opened. One press, nothing on screen.
##
## Run with: godot --headless --script _test_map_open.gd

const WAIT := 8

var _frames := 0
var _clock := 0
var _step := 0
var _failures := 0

var _table: Node
var _player: Node


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _boot()
		1: return _check_press_opens()
		2: return _check_press_closes()
	return _finish()


func _ok(passed: bool, label: String) -> void:
	if passed:
		print("  ok   %s" % label)
	else:
		print("  FAIL %s" % label)
		_failures += 1


func _next() -> bool:
	_step += 1
	_clock = 0
	return false


## Stands a table and a player up by hand. The point is the input path, not the
## van: a bare `MapTable` in the tree answers `use()` exactly as the real one does.
func _boot() -> bool:
	if _clock < WAIT:
		return false

	var table_script: GDScript = load("res://scripts/map/map_table.gd")
	if table_script == null:
		print("FAIL: map_table.gd did not load")
		_failures += 1
		return _finish()

	_ok(not FileAccess.file_exists("res://scripts/economia/carteira.gd"),
		"no phantom carteira.gd on disk")

	var table := Area3D.new()
	table.set_script(table_script)
	root.add_child(table)
	_table = table

	# The player stands in for the real one: `_open()` only asks for
	# `set_ui_open`, and refuses anything that cannot answer it.
	var player := Node3D.new()
	player.set_script(_stub_player_script())
	root.add_child(player)
	_player = player

	_ok(_table != null and _table.has_method("use"), "map table is in the tree")
	_ok(not _table.is_open(), "table starts closed")
	return _next()


## The press itself. `use()` is what the player calls on `interact`, and after
## it the plan must still be open on the next frame — that is the whole bug.
func _check_press_opens() -> bool:
	if _clock == 1:
		_table.use(_player)
		return false
	if _clock < 4:
		return false

	_ok(_table.is_open(), "E opened the plan and it stayed open")
	_ok(_player.ui_open, "the player was handed the screen")
	_ok(_table.prompt == "step away from the table", "prompt turned into the leave line")
	return _next()


## And the way out still works: the viewer reports `closed` and the table lets go.
func _check_press_closes() -> bool:
	if _clock == 1:
		_table._close()
		return false
	if _clock < 4:
		return false

	_ok(not _table.is_open(), "the table closed")
	_ok(not _player.ui_open, "the player got himself back")
	_ok(_table.prompt == "study the plan", "prompt went back to the read line")
	return _next()


func _stub_player_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends Node3D

var ui_open := false

func set_ui_open(open: bool) -> void:
	ui_open = open
"""
	script.reload()
	return script


func _finish() -> bool:
	if _failures == 0:
		print("\nmap open bench: all good.")
	else:
		print("\nmap open bench: %d failure(s)." % _failures)
	quit(1 if _failures > 0 else 0)
	return true
