class_name ContractBoard
extends Node3D
## The signed job, pinned to the wall of the van where the whole crew can read it
## without picking anything up.
##
## The clipboard is where a job is *chosen*; this is where the chosen one lives
## afterwards. The card asks for exactly that split, and it is worth the second
## node: a crew that has to open a menu to remember which house they are driving
## to will not open it, and a sheet on the wall is read in passing by four people
## at once.
##
## **It reads and it draws, and it decides nothing.** The signed job comes off
## `ContractManager`, which reads it off `SessionManager`; nothing here is stored
## and nothing here is asked of the host. That is also why it needs no network
## code of its own — the signature is already replicated by the time this hears
## about it.
##
## **A blank wall says it is blank.** Before anything is signed the sheet reads
## that the crew has not picked a job yet, rather than hanging empty. A player
## looking at an empty pin cannot tell "nothing signed" from "the sheet failed to
## draw", and the first of those is a thing he can do something about.
##
## It is dropped in every scene that wants it. In the van it is on the bulkhead;
## on the road (card 09) the same node goes up beside the map table, and it will
## work there without a line changing, because it asks the autoloads and not the
## van.

## What the sheet reads before the leader has signed anything.
const UNSIGNED := "NO JOB SIGNED"
## And the line under it, telling the crew where the job comes from.
const UNSIGNED_HINT := "READ THE CLIPBOARD"

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

@onready var _rows: VBoxContainer = get_node_or_null(rows_path) as VBoxContainer
@onready var _plan: TextureRect = get_node_or_null(plan_path) as TextureRect


func _ready() -> void:
	add_to_group("contract_board")

	# The signature is the only thing that changes what is on this wall, and the
	# phase is what closes the board. Nothing is polled: a sheet redrawing itself
	# sixty times a second for a line that changes once a lobby is work for
	# nothing.
	ContractManager.contract_signed.connect(_on_contract_signed)
	ContractManager.hunt_time_set.connect(_on_hunt_time_set)
	PhaseManager.phase_changed.connect(_on_phase_changed)

	_redraw()

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


## The shift moved on. The sheet does not change with the phase, but a board that
## survived into the next scene should redraw against whatever is signed there
## rather than trusting what it drew in the van.
func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_redraw()
