class_name ContractBoard
extends Interactable
## The signed job, pinned to the wall of the van where the whole crew can read it
## without picking anything up — and the paperwork behind it, for the man who
## walks up and puts his hands on it.
##
## **Two ranges, one sheet.** From across the van it is a summary read in
## passing: who is paying, where the house is, how bad it is and what the clock
## is. It is worth being a fixture rather than a menu for exactly that reason —
## a crew that has to open a window to remember which house they are driving to
## will not open it. Up close, `E` lets the mouse loose and puts the full
## contract on screen with a box at the bottom of it
## (`scripts/ui/contract_sheet.gd`), because a job is taken by drawing a
## signature and a scrawl needs a cursor.
##
## **A blank wall says it is blank.** Before anything is signed the sheet reads
## that the crew has not picked a job yet, rather than hanging empty. A player
## looking at an empty pin cannot tell "nothing signed" from "the sheet failed to
## draw", and the first of those is a thing he can do something about.
##
## **It reads and it draws, and the wall itself decides nothing.** The signature
## is the sheet's business and the host's; everything on this node comes off
## `ContractManager`, which reads it off `SessionManager`. That is why it needs
## no network code of its own — a job is already replicated by the time the wall
## hears about it.
##
## It is dropped in every scene that wants it. In the van it is on the bulkhead;
## on the road (card 09) the same node goes up beside the map table, and it will
## work there without a line changing, because it asks the autoloads and not the
## van.

## What the on-screen prompt reads at the wall, and what it reads once the
## paperwork is up. The board says what pressing the key would do rather than
## what it is, the way every other station in the van does.
const PROMPT_READ := "read the contract"
const PROMPT_LEAVE := "put the contract down"

## What the sheet reads before the leader has signed anything.
const UNSIGNED := "NO JOB SIGNED"
## And the line under it, telling the crew what to do about it. It names the key
## rather than another piece of furniture: this wall is where a job is taken now,
## so a man reading a blank sheet is already standing at the answer.
const UNSIGNED_HINT := "PRESS E TO SIGN ONE"

## The green a signed sheet is stamped in, matching the clipboard's own stamp.
const COLOR_SIGNED := Color("29c443")
## And what the booked clock is written in as the bet steepens, matching the
## clipboard's own colours — the two sheets say the same thing about the same
## wager, so they had better say it in the same ink.
const COLOR_WAGER := {
	HuntTime.Type.LONG: Color("ffffff"),
	HuntTime.Type.MEDIUM: Color("ffb229"),
	HuntTime.Type.SHORT: Color("ff4b3a"),
}
## And the amber a blank one is written in — not red, because nothing is wrong
## yet, only unfinished.
const COLOR_UNSIGNED := Color("ffb229")

## The rows the sheet is written into, on a `SubViewport` behind the paper.
@export var rows_path: NodePath = ^"Sheet/Viewport/Margin/Rows"
## The floor plan printed on the lower half of the sheet, when the contract
## carries one. Hidden rather than left blank when it does not.
@export var plan_path: NodePath = ^"Sheet/Viewport/Margin/Rows/Plan"
## The paper itself: the quad the writing above is printed onto.
@export var sheet_path: NodePath = ^"Sheet"
## And the viewport the writing is drawn in, behind it.
@export var viewport_path: NodePath = ^"Sheet/Viewport"

@onready var _rows: VBoxContainer = get_node_or_null(rows_path) as VBoxContainer
@onready var _plan: TextureRect = get_node_or_null(plan_path) as TextureRect
@onready var _sheet: MeshInstance3D = get_node_or_null(sheet_path) as MeshInstance3D
@onready var _viewport: SubViewport = get_node_or_null(viewport_path) as SubViewport

## The player holding the paperwork up, or null when nobody is. It is what the
## mouse and the legs are handed back to on the way out, and what stops a second
## man opening a contract somebody else is already reading.
var _reader: Node3D
## The paperwork itself, built the first time anybody asks for it.
var _sheet_ui: ContractSheet


func _ready() -> void:
	add_to_group("contract_board")
	prompt = PROMPT_READ

	_paint_sheet()

	# The signature is the only thing that changes what is on this wall, and the
	# phase is what closes the board. Nothing is polled: a sheet redrawing itself
	# sixty times a second for a line that changes once a lobby is work for
	# nothing.
	ContractManager.contract_signed.connect(_on_contract_signed)
	ContractManager.hunt_time_set.connect(_on_hunt_time_set)
	PhaseManager.phase_changed.connect(_on_phase_changed)

	_redraw()

# --- Picking the paperwork up and putting it down ---------------------------

## Hands on the wall. Unlike most stations, `by` is kept: the paperwork has to
## give the man his mouse and his legs back afterwards, and has to stop him
## walking across the van while he is reading it.
func use(by: Node3D) -> void:
	super.use(by)
	if _reader != null:
		return
	_open(by)


## Puts the contract on screen and lets the mouse loose. `set_ui_open` is what
## does both — the player stops answering to the keys and the cursor comes back —
## and it is the same thing the shop screen does to him, for the same reason: a
## click has to be able to reach a button instead of being spent grabbing the
## camera back.
func _open(by: Node3D) -> void:
	if by == null or not by.has_method("set_ui_open"):
		return
	_reader = by
	_reader.set_ui_open(true)

	if _sheet_ui == null:
		_sheet_ui = ContractSheet.new()
		_hud_layer().add_child(_sheet_ui)
		_sheet_ui.closed.connect(_on_sheet_closed)
	_sheet_ui.open()

	prompt = PROMPT_LEAVE


## Puts it down and hands the man back his eyes, his legs and his cursor.
func _close() -> void:
	if _reader == null:
		return
	if _sheet_ui != null and _sheet_ui.is_open():
		_sheet_ui.close()

	if is_instance_valid(_reader) and _reader.has_method("set_ui_open"):
		_reader.set_ui_open(false)
	_reader = null
	prompt = PROMPT_READ


## Whether somebody on this machine is reading the paperwork. The van asks before
## it does anything that would pull the screen out from under him.
func is_open() -> bool:
	return _reader != null


func _on_sheet_closed() -> void:
	_close()


## The `CanvasLayer` the paperwork is drawn on.
##
## The board is a fixture of more than one scene, and each brings its own HUD.
## Hunting for the layer by name is what lets the same wall hang the same sheet
## in all of them without either scene having to point at it. The layer of last
## resort is a new one: a `Control` parented to this `Area3D` would be in the 3D
## world, where it draws nothing at all. The map table pays this same toll for
## the same reason.
func _hud_layer() -> Node:
	var hud := get_tree().root.find_child("HUD", true, false)
	if hud != null:
		return hud

	var layer := CanvasLayer.new()
	layer.name = "ContractLayer"
	get_tree().root.add_child(layer)
	return layer


## Puts the viewport onto the paper, in code rather than in the scene file.
##
## A `ViewportTexture` saved into a `.tscn` has to find its viewport by a path
## resolved against the scene it is local to, and a material reached through a
## `QuadMesh` that is not itself local to the scene never gets that resolution
## run — which is why the wall was showing the missing-texture checkerboard
## rather than a contract. Asking the viewport for its own texture at run time
## cannot be wrong about which viewport it means.
func _paint_sheet() -> void:
	if _sheet == null or _viewport == null:
		return
	var material := StandardMaterial3D.new()
	# Unshaded and nearest-filtered, like every other printed surface in the van:
	# a lit, smoothed sheet of paper is the one thing that reads as modern in a
	# scene built to look like 1998.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_texture = _viewport.get_texture()
	_sheet.set_surface_override_material(0, material)

# --- What is drawn ----------------------------------------------------------

## The sheet, from scratch — the same bargain the clipboard makes: doing all of
## it is cheaper than working out which half moved, and there is one function to
## read instead of two that have to agree.
func _redraw() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		if child != _plan:
			child.queue_free()

	var contract := ContractManager.current()
	if contract == null:
		_write_blank()
		return
	_write(contract)


## A wall with nothing on it yet, saying so.
func _write_blank() -> void:
	_add(_line(UNSIGNED, COLOR_UNSIGNED))
	_add(_line(UNSIGNED_HINT, COLOR_UNSIGNED))
	if _plan != null:
		_plan.hide()


## The signed job. Short — it is read at a glance from across the van, not
## studied — so it carries the client, the address and the two numbers that
## decide what the crew brings, and leaves the notes to the clipboard.
func _write(contract: Contract) -> void:
	_add(_line("SIGNED", COLOR_SIGNED))
	_add(_line(contract.client_name.to_upper()))
	_add(_line(contract.address))
	_add(_line(""))
	_add(_line("INFESTATION  %d" % contract.infestation))
	_add(_line("PAYS         %d" % contract.reward))
	# The clock the crew booked itself, in the colour of how steep the bet is.
	# It is on the wall and not only on the clipboard because it is the number
	# the crew argues about, and an argument nobody can see the terms of is an
	# argument had four times.
	var booked := ContractManager.hunt_time()
	_add(_line("HUNT TIME    %s" % HuntTime.label_of(booked),
		COLOR_WAGER.get(booked, Color.WHITE)))

	if _plan == null:
		return
	_plan.texture = contract.floor_plan
	_plan.visible = contract.floor_plan != null


## Adds a line above the floor plan rather than below it, so that the writing
## stays at the top of the sheet however many lines there are.
func _add(label: Label) -> void:
	_rows.add_child(label)
	if _plan != null:
		_rows.move_child(label, _rows.get_child_count() - 1)
		_rows.move_child(_plan, _rows.get_child_count() - 1)


## One line of the sheet, in the same bitmap-flat dress the rest of the HUD
## wears — no antialiasing, no gradient, no shadow.
func _line(text: String, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)
	return label

# --- What wakes it up -------------------------------------------------------

func _on_contract_signed(_contract_id: String) -> void:
	_redraw()


## The clock was booked or changed. The sheet redraws for the same reason it does
## on a signature: it is a term of the job the crew is about to walk into.
func _on_hunt_time_set(_hunt_time: HuntTime.Type) -> void:
	_redraw()


## The shift moved on. Anybody still holding the paperwork is handed his eyes
## back — the scene is about to go out from under him — and the wall redraws
## against whatever is signed in the new phase rather than trusting what it drew
## in the last one.
func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_close()
	_redraw()
