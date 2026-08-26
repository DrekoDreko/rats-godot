class_name ContractPanel
extends PanelContainer
## The board of jobs on the menu, in the corner where the crew can read it while
## they get ready.
##
## It takes over from the clipboard that hung by the door of the parked van.
## Leafing through pages made sense when a man had to walk over and pick the
## board up; on a screen the whole list fits, so the whole list is shown.
##
## **The leader signs and nobody else.** That is `ContractManager`'s rule, not
## this file's — everybody presses through `request_sign` and the host either
## writes it on every machine at once or turns the asker down. A client's rows
## are drawn dim and disabled so he reads "only the leader signs" instead of
## pressing a button that was always going to refuse him.
##
## The signed job outlives this screen. It lives on `SessionManager` and the
## sheet pinned in `van_travel.tscn` reads it from there, which is why nothing
## has to be handed over when the shift pulls off.

## Same as everywhere else on the screen.
const FONT_SIZE := 8
const OUTLINE_SIZE := 4

## The green a signed job is stamped in, and the amber an unsigned board is
## written in — the two `contract_board.gd` already uses on the wall of the van,
## so the same job is the same colour wherever it is read.
const COLOR_SIGNED := Color("29c443")
const COLOR_UNSIGNED := Color("ffb229")

## What the panel says when there is no work on the board at all.
const NOTHING := "NO JOBS ON THE BOARD"

var _rows: VBoxContainer
var _header: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.78)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.55, 0.55, 0.75)
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)

	_header = _label("CONTRACT", Color.WHITE)
	column.add_child(_header)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 2)
	column.add_child(_rows)

	ContractManager.contract_signed.connect(_on_contract_signed)
	SessionManager.contract_changed.connect(_on_contract_changed)

	refresh()


## Redraws the board. Rows are rebuilt rather than updated because the list is
## short and fixed — the contracts are scanned off disk once at boot — so there
## is nothing to be gained by being clever about which one moved.
func refresh() -> void:
	if _rows == null:
		return
	for row in _rows.get_children():
		row.queue_free()

	var signed_id := SessionManager.current_contract
	_header.text = "CONTRACT" if signed_id.is_empty() else "CONTRACT — SIGNED"
	_header.add_theme_color_override(
		"font_color", COLOR_UNSIGNED if signed_id.is_empty() else COLOR_SIGNED)

	if ContractManager.count() == 0:
		_rows.add_child(_label(NOTHING, Color(1, 1, 1, 0.6)))
		return

	var may_sign := ContractManager.may_sign() and ContractManager.is_open()
	for index in ContractManager.count():
		var contract := ContractManager.at(index)
		if contract == null:
			continue
		_rows.add_child(_row(contract, contract.id == signed_id, may_sign))


## One job. A button either way — a client's is disabled rather than absent, so
## that the board reads the same on every machine and only the pressing differs.
func _row(contract: Contract, is_signed: bool, may_sign: bool) -> Button:
	var button := Button.new()
	button.text = "%s  $%d" % [contract.client_name, contract.reward]
	button.tooltip_text = contract.address
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = not may_sign
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.add_theme_color_override(
		"font_color", COLOR_SIGNED if is_signed else Color.WHITE)
	button.add_theme_color_override(
		"font_disabled_color", COLOR_SIGNED if is_signed else Color(1, 1, 1, 0.6))
	button.pressed.connect(func() -> void: ContractManager.request_sign(contract.id))
	return button


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	return label


func _on_contract_signed(_contract_id: String) -> void:
	refresh()


func _on_contract_changed(_contract_id: String) -> void:
	refresh()
