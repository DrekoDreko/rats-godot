extends SceneTree
## The wall sheet in the van: `E` opens the paperwork, the mouse comes loose, and
## the job is taken by a signature drawn in the box rather than by a keypress.
##
## Run with: godot --headless --script _test_contract_sign.gd
##
## One machine and no wire, so `PhaseManager.is_host()` answers true throughout —
## which is the path a solo game takes anyway. What is measured here is the road
## from the press to the signature: that the board hands the player his cursor,
## that the pad refuses to call a dot a signature, that the pen will not go down
## on an empty box, and that a drawn name reaches `ContractManager` and comes
## back as a taken job.

const ANA := 111
const WAIT := 8

## Frames after which the bench gives up rather than spinning. A script error
## aborts the step it happened in without advancing anything, and a bench that
## repeats the same broken frame forever tells you less than one that stops.
const STUCK := 600

## The board's two prompts, spelled out rather than read off `ContractBoard`.
##
## Nothing in this file may name one of the game's own classes. A bench is
## compiled by `--script` before the autoloads exist, and naming a type drags its
## script into that compile — where `ContractManager` is not a word yet, and the
## whole bench fails to load. Everything below reaches for nodes and members by
## name for the same reason.
const PROMPT_READ := "read the contract"
const PROMPT_LEAVE := "put the contract down"

## Where the paperwork and the box come from, loaded rather than named.
const SHEET_SCRIPT := "res://scripts/ui/contract_sheet.gd"
const PAD_SCRIPT := "res://scripts/ui/signature_pad.gd"
const BOARD_SCRIPT := "res://scripts/session/contract_board.gd"

var _contract: Node
var _session: Node
var _phase: Node

var _board: Node
var _sheet: Node
var _player: Node

var _frames := 0
var _clock := 0
var _step := 0
var _failures := 0


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	if _frames > STUCK:
		print("  FAIL the bench stopped moving at step %d" % _step)
		_failures += 1
		return _finish()
	if _frames < 3:
		return false
	match _step:
		0: return _boot()
		1: return _step_pad_measures_ink()
		2: return _step_press_opens()
		3: return _step_empty_box_signs_nothing()
		4: return _step_a_drawn_name_signs()
		5: return _step_close()
	return _finish()


## Stands a wall board and a player up by hand. The point is the road from the
## press to the signature, not the van: a bare `ContractBoard` in the tree
## answers `use()` exactly as the one bolted to the bulkhead does, and draws
## nothing because it has no sheet nodes under it.
func _boot() -> bool:
	if _clock < WAIT:
		return false

	_contract = root.get_node_or_null("ContractManager")
	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	if _contract == null or _session == null or _phase == null:
		print("FAIL: an autoload is missing")
		_failures += 1
		return _finish()

	_session.register_player(ANA, "Ana", true)

	var board := Area3D.new()
	board.set_script(load(BOARD_SCRIPT))
	root.add_child(board)
	_board = board

	var player := Node3D.new()
	player.set_script(_stub_player_script())
	root.add_child(player)
	_player = player

	_ok(_contract.count() > 0, "there are jobs on the board (%d)" % _contract.count())
	_ok(_contract.is_open(), "the board is open in the lobby")
	_ok(not _board.is_open(), "the wall starts closed")
	_ok(_board.prompt == PROMPT_READ, "and reads as the read prompt")
	return _next()


## The box itself, on its own: it counts ink and nothing else, so a dot is not a
## signature and a scrawl is.
func _step_pad_measures_ink() -> bool:
	var pad := Control.new()
	pad.set_script(load(PAD_SCRIPT))
	pad.size = Vector2(276, 54)
	root.add_child(pad)

	_ok(not pad.is_signed(), "an empty box is not a signature")

	pad.set_strokes(_one(PackedVector2Array([Vector2(10, 20)])))
	_ok(not pad.is_signed(), "and neither is a single dot")

	pad.set_strokes(_one(_scrawl()))
	_ok(pad.is_signed(), "a drawn name is (ink %.0f)" % pad.ink())

	pad.clear()
	_ok(not pad.is_signed(), "and CLEAR wipes it off again")

	pad.queue_free()
	return _next()


## The press. `use()` is what the player calls on `interact`; after it the
## paperwork must be on screen, the man must have his cursor, and the prompt must
## have turned into the way out.
func _step_press_opens() -> bool:
	if _clock == 1:
		_board.use(_player)
		return false
	if _clock < 4:
		return false

	_sheet = _find_sheet()
	_ok(_board.is_open(), "E opened the contract and it stayed open")
	_ok(_player.ui_open, "the player was handed the screen and the mouse")
	_ok(_board.prompt == PROMPT_LEAVE, "prompt turned into the leave line")
	_ok(_sheet != null and _sheet.is_open(), "the paperwork is up")
	return _next()


## The pen will not go down on an empty box. It is the whole reason the box is
## there: a job the crew walks into should cost a deliberate movement.
func _step_empty_box_signs_nothing() -> bool:
	if _sheet == null:
		return _next()
	var pad := _find_pad()
	_ok(pad != null, "the sheet carries a signature box")
	if pad == null:
		return _next()

	pad.clear()
	_sheet._press_pen()
	_ok(_session.current_contract.is_empty(),
		"an empty box signs nothing (%s)" % _session.current_contract)
	return _next()


## And a drawn name does. The scrawl is local flourish; what travels is the id,
## and what comes back is a job every machine reads as taken.
func _step_a_drawn_name_signs() -> bool:
	if _sheet == null:
		return _next()
	var pad := _find_pad()
	if pad == null:
		return _next()

	var job: Resource = _contract.at(0)
	_sheet._page = 0
	pad.set_strokes(_one(_scrawl()))
	_ok(pad.is_signed(), "there is a name in the box")

	_sheet._press_pen()
	_ok(_session.current_contract == job.id,
		"the drawn name took the job (%s)" % _session.current_contract)
	_ok(_contract.current() != null and _contract.current().id == job.id,
		"and it reads back off the board")
	_ok(pad.locked, "the box locks once the job is taken")
	return _next()


## The way out: the sheet comes down and the man gets his legs and his camera
## back. A cursor left loose in the van is the bug this guards.
func _step_close() -> bool:
	if _clock == 1:
		_board._close()
		return false
	if _clock < 4:
		return false

	_ok(not _board.is_open(), "the wall closed")
	_ok(_sheet == null or not _sheet.is_open(), "the paperwork came down with it")
	_ok(not _player.ui_open, "the player got himself back")
	_ok(_board.prompt == PROMPT_READ, "prompt went back to the read line")
	return _next()

# --- Odds and ends ----------------------------------------------------------

## A scrawl long enough to pass `SignaturePad.MIN_INK` — a zig-zag across the
## box, which is what a hurried signature is anyway.
func _scrawl() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 12:
		points.append(Vector2(10.0 + i * 20.0, 20.0 + (10.0 if i % 2 == 0 else -10.0)))
	return points


## One stroke in the typed array the pad asks for. Godot will not narrow an
## untyped literal on the way in, and the bench cannot name the pad's type to get
## one for free — see `PROMPT_READ`.
func _one(stroke: PackedVector2Array) -> Array[PackedVector2Array]:
	var strokes: Array[PackedVector2Array] = []
	strokes.append(stroke)
	return strokes


## The paperwork, wherever the board hung it. It goes on the scene's `HUD` layer
## when there is one and on a layer of its own when there is not, and a bench van
## has neither — so it is hunted for by type from the root.
func _find_sheet() -> Node:
	return _with_script(root, SHEET_SCRIPT)


## And the box inside it.
func _find_pad() -> Node:
	return _with_script(_sheet, PAD_SCRIPT) if _sheet != null else null


## The first node under `from` carrying a given script, by path. Types cannot be
## named here — see `PROMPT_READ` — so the script's own path is the identity.
func _with_script(from: Node, path: String) -> Node:
	for node in from.find_children("*", "Control", true, false):
		var script: Script = node.get_script()
		if script != null and script.resource_path == path:
			return node
	return null


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


func _finish() -> bool:
	if _failures == 0:
		print("\ncontract signing bench: all good.")
	else:
		print("\ncontract signing bench: %d failure(s)." % _failures)
	quit(1 if _failures > 0 else 0)
	return true
