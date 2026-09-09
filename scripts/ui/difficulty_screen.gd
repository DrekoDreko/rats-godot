class_name DifficultyScreen
extends Control
## The third page in the terminal: what the signed contract says about the
## house, read-only.
##
## Everything here already exists somewhere else — the infestation and the
## rat-type dots are the same numbers `MapViewer`'s header and
## `ContractVoteCard` already draw, and the booked length is the same table
## `contract_vote_screen.gd` reads off `HuntTime`. This page only puts them
## together in one place so a man who has already left the van can still be
## told what he signed up for. Nothing here is pressable — there is nothing to
## decide once the crew is on the road.

## What is shown before any contract is signed.
const NO_CONTRACT_TITLE := "NO CONTRACT SIGNED"
const NO_CONTRACT_SUB := "NOTHING TO SHOW YET"

## The size a rat-type dot is drawn at, and the blue every line on this page
## shares with the rest of the terminal.
const DOT_SIZE := 10.0
const ACCENT_COLOR := Color(0.45, 0.72, 0.9)

@onready var _title: Label = $Root/Margin/Rows/Title
@onready var _address: Label = $Root/Margin/Rows/Address
@onready var _rule: HSeparator = $Root/Margin/Rows/Rule
@onready var _infestation: Label = $Root/Margin/Rows/Infestation
@onready var _dots: HBoxContainer = $Root/Margin/Rows/TypesRow/Dots
@onready var _hunt_length: Label = $Root/Margin/Rows/HuntLength
@onready var _close: Label = $Root/Margin/Rows/Close


## Refreshes and shows the page. Called by the terminal every time it is
## turned to, so what it reads is never a beat behind whichever contract is
## current.
func open() -> void:
	_refresh()
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


func _ready() -> void:
	visible = false
	ContractManager.contract_signed.connect(_on_contract_changed)
	ContractManager.hunt_time_set.connect(_on_contract_changed)


func _refresh() -> void:
	var contract := ContractManager.current()
	if contract == null:
		_title.text = NO_CONTRACT_TITLE
		_address.text = NO_CONTRACT_SUB
		_infestation.text = ""
		_hunt_length.text = ""
		_build_dots([])
		return

	_title.text = contract.client_name.to_upper()
	_address.text = contract.address
	_infestation.text = "INFESTATION: %d RATS" % contract.infestation
	var hunt_time := ContractManager.hunt_time()
	_hunt_length.text = "HUNT LENGTH: %s   $%d/RAT" \
		% [HuntTime.clock_of(hunt_time), HuntTime.reward(hunt_time)]
	_build_dots(contract.rat_types)


## One hollow dot per rat type on the contract, the same placeholder
## `ContractVoteCard` draws until the breeds have icons of their own — laid out
## in a row here rather than a column, since the terminal has the width for it.
func _build_dots(types: Array[String]) -> void:
	for dot in _dots.get_children():
		dot.queue_free()
	var shown := types if not types.is_empty() else [""]
	for _type in shown:
		_dots.add_child(_make_dot())


func _make_dot() -> Panel:
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(DOT_SIZE, DOT_SIZE)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = ACCENT_COLOR
	var radius := int(DOT_SIZE / 2.0)
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	dot.add_theme_stylebox_override("panel", style)

	return dot


func _on_contract_changed(_value: Variant = null) -> void:
	if visible:
		_refresh()
