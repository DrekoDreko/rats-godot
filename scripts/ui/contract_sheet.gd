class_name ContractSheet
extends Control
## The contract held up close: the whole of a job in writing, and the box the
## crew leader signs it in.
##
## It is opened off the sheet pinned to the wall of the van
## (`scripts/session/contract_board.gd`), which is the summary of the job the
## crew took; this is the paperwork behind it. Pressing `E` at the wall lets the
## mouse loose and puts this on screen, because **the signature is drawn rather
## than pressed** (`SignaturePad`) and a scrawl needs a cursor.
##
## **Leafing is local, signing is not.** Which page a man is reading is his own
## business and never touches the wire; the pen asks `ContractManager`, the host
## decides, and what comes back is what every sheet in every van reads. That is
## the same split the van's clipboard was built on, and it is the reason a client
## can read every job on the board while only the leader can take one.
##
## **A client is told before he draws, not after.** The pad is locked and the
## line under it says why on a machine that cannot sign — the rule is something
## the crew reads rather than something they find out by being refused. A refusal
## that comes back from the host anyway is printed on the same line.
##
## **The scrawl never crosses the wire.** What is replicated is the contract id
## and nothing else; the drawing is a local flourish, kept only so that a man who
## leafs away from the job he signed and back again finds his own name still on
## it.

## The reader put the sheet down. The wall board listens, so it can hand the man
## his legs and his mouse back.
signal closed()

## Same dress the rest of the HUD wears: bitmap-flat, hard-outlined, no gradient.
const FONT_SIZE := 8
const OUTLINE_SIZE := 4

## How wide the paperwork is on a 640x360 screen, and how big the box under it
## is. The pad is wide and short on purpose — it is a line to sign on, not a
## canvas to draw on.
const SHEET_WIDTH := 300.0
const PAD_SIZE := Vector2(276, 54)

## The green a taken job is stamped in, the amber of one still open, and the red
## a refusal is printed in — the same three the wall sheet and the menu's board
## already use, so a job is the same colour wherever it is read.
const COLOR_SIGNED := Color("29c443")
const COLOR_OPEN := Color("ffb229")
const COLOR_REFUSED := Color("ff4b3a")

## What the wager line is written in as the bet steepens, matching the wall
## sheet's own ink.
const COLOR_WAGER := {
	HuntTime.Type.LONG: Color("ffffff"),
	HuntTime.Type.MEDIUM: Color("ffb229"),
	HuntTime.Type.SHORT: Color("ff4b3a"),
}

## What the sheet says when there is no work on the board at all. It should not
## happen — jobs ship with the game — but an empty folder must say so rather than
## draw a blank page that reads as a bug.
const NOTHING := "THE BOARD IS EMPTY"

## The line under the box, in each of the situations it can be read in. They are
## sentences rather than "press to sign", because "press to sign" on a sheet this
## machine cannot sign is a lie.
const HINT_SIGN := "DRAW YOUR NAME IN THE BOX, THEN PRESS SIGN"
const HINT_MORE_INK := "KEEP GOING — THAT IS NOT A SIGNATURE YET"
const HINT_TAKEN := "THIS JOB IS SIGNED FOR"
const HINT_NOT_HOST := "ONLY THE CREW LEADER SIGNS"
const HINT_CLOSED := "THE BOARD IS CLOSED — THE JOB IS UNDER WAY"

var _title: Label
var _client: Label
var _address: Label
var _infestation: Label
var _difficulty: Label
var _pays: Label
var _wager: Label
var _notes: Label
var _pad: SignaturePad
var _sign_button: Button
var _clear_button: Button
var _hint: Label

## Which sheet is face up. Local, always — see the note above about leafing.
var _page := 0

## The leader's own scrawl on the job he took, kept so that leafing away and back
## finds it still there. It is never sent anywhere and never received: a sheet
## signed by somebody else's host draws the stamp instead.
var _signed_strokes: Array[PackedVector2Array] = []
## Which job that scrawl belongs to, so it is not put back on the wrong page
## after the crew changes its mind.
var _signed_id := ""

## The frame the sheet was opened on. The player uses a station out of his own
## `_unhandled_input` and leaves the press unhandled, so the very `E` that
## reached for the wall carries on down the list and arrives here a listener
## later — by which time the sheet is up and `E` means "put it down", and the one
## press would open and close it in the same breath. The clipboard in the parked
## van paid this same toll for the same reason.
var _opened_frame := -1


func _ready() -> void:
	# A phase can turn over while this is up, and the pause menu can go over the
	# top of it; neither should leave a sheet that has stopped answering.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Everything under the sheet is out of reach while it is up — a click meant
	# for the pad must never also be a swing at something in the van.
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()

	_build()

	ContractManager.contract_signed.connect(_on_contract_signed)
	ContractManager.hunt_time_set.connect(_on_hunt_time_set)
	ContractManager.request_refused.connect(_on_refused)
	PhaseManager.phase_changed.connect(_on_phase_changed)


## The keys that work while the sheet is up. The buttons carry the mouse; this is
## for the hands that would rather not reach for it, and for the two ways out.
##
## Escape is asked for by its key rather than through `cancel`, which is bound to
## the right mouse button as well — a stray right-click over the paper should not
## put the whole contract down.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# The press that opened the sheet is still travelling. One press is one
	# action, and this one has already been spent.
	if Engine.get_physics_frames() == _opened_frame:
		return

	var closing := event.is_action_pressed("interact")
	if event is InputEventKey and event.is_pressed() \
			and (event as InputEventKey).keycode == KEY_ESCAPE:
		closing = true

	if closing:
		close()
	elif event.is_action_pressed("move_left"):
		_leaf(-1)
	elif event.is_action_pressed("move_right"):
		_leaf(1)
	else:
		return
	get_viewport().set_input_as_handled()


## Puts the sheet up, opened on the job the crew took rather than on page one —
## a man reaching for the paperwork wants to read what he is already committed
## to before he reads what else was on offer.
func open() -> void:
	_opened_frame = Engine.get_physics_frames()
	var signed_page := ContractManager.index_of(SessionManager.current_contract)
	if signed_page != -1:
		_page = signed_page
	_page = clampi(_page, 0, maxi(0, ContractManager.count() - 1))
	show()
	_refresh()


## Puts it down. Quiet about being called twice: the wall board closes it on the
## phase turning over as well as on the reader asking, and those can land in the
## same frame.
func close() -> void:
	if not visible:
		return
	hide()
	closed.emit()


func is_open() -> bool:
	return visible

# --- Leafing and signing ----------------------------------------------------

## Turns a page, wrapping at both ends so the whole board is reachable with one
## key held down.
func _leaf(step: int) -> void:
	var total := ContractManager.count()
	if total <= 1:
		return
	_page = wrapi(_page + step, 0, total)
	_refresh()


## The pen. It writes nothing itself: it asks the host, and what the host answers
## is what every sheet ends up reading.
##
## The scrawl is put away *before* the request goes out rather than after it
## comes back, so that the drawing belongs to the job the man was looking at when
## he signed it, whatever the host does with the request afterwards.
func _press_pen() -> void:
	var contract := ContractManager.at(_page)
	if contract == null or not _pad.is_signed():
		return
	_signed_strokes = _pad.strokes()
	_signed_id = contract.id
	ContractManager.request_sign(contract.id)
	_refresh()

# --- What is drawn ----------------------------------------------------------

## The sheet, from scratch — every line of it, every time. The page is a handful
## of labels; working out which of them moved would cost more than writing all of
## them, and it means there is one function to read rather than six that have to
## agree.
func _refresh() -> void:
	var contract := ContractManager.at(_page)
	if contract == null:
		_title.text = NOTHING
		for label in [_client, _address, _infestation, _difficulty, _pays, _wager, _notes]:
			label.text = ""
		_refresh_pad(null)
		return

	var taken := SessionManager.current_contract == contract.id
	_title.text = "JOB %d/%d" % [_page + 1, ContractManager.count()]
	_title.add_theme_color_override("font_color", COLOR_SIGNED if taken else Color.WHITE)
	_client.text = contract.client_name.to_upper()
	_address.text = contract.address
	_infestation.text = "INFESTATION  %d" % contract.infestation
	_difficulty.text = "DIFFICULTY   %s" % _pips(contract.difficulty)
	_pays.text = "PAYS         %d" % contract.reward

	# The wager is a term of the shift rather than of the job, and it is on every
	# page for that reason: a man weighing two houses wants to read each of them
	# against the clock he is actually going to have.
	var booked := ContractManager.hunt_time()
	_wager.text = "HUNT TIME    %s" % HuntTime.label_of(booked)
	_wager.add_theme_color_override("font_color", COLOR_WAGER.get(booked, Color.WHITE))

	_notes.text = contract.notes
	_notes.visible = not contract.notes.is_empty()

	_refresh_pad(contract)


## The box and the two buttons under it. Four situations and four answers: the
## job is already taken, this machine cannot sign, the board has closed, or there
## is a signature to be drawn.
func _refresh_pad(contract: Contract) -> void:
	var taken := contract != null and SessionManager.current_contract == contract.id
	var allowed := contract != null and ContractManager.may_sign() and ContractManager.is_open()

	# The leader's own scrawl goes back on the job he put it on, and nowhere
	# else. A job taken on somebody else's machine locks an empty pad, which
	# draws its own stamp.
	if taken and contract.id == _signed_id:
		_pad.set_strokes(_signed_strokes)
	elif _pad.locked or not taken:
		_pad.clear()

	_pad.locked = taken or not allowed
	_clear_button.disabled = _pad.locked
	_sign_button.disabled = _pad.locked or not _pad.is_signed()

	_hint.add_theme_color_override("font_color", COLOR_OPEN)
	if taken:
		_hint.text = HINT_TAKEN
		_hint.add_theme_color_override("font_color", COLOR_SIGNED)
	elif not ContractManager.is_open():
		_hint.text = HINT_CLOSED
	elif not ContractManager.may_sign():
		_hint.text = HINT_NOT_HOST
	elif _pad.is_signed():
		_hint.text = HINT_SIGN
		_hint.add_theme_color_override("font_color", Color.WHITE)
	else:
		_hint.text = HINT_MORE_INK


## The difficulty as a row of marks rather than a number, so two jobs can be told
## apart at a glance without reading. Filled and empty are the same width, so the
## row does not shuffle between pages.
func _pips(difficulty: int) -> String:
	var filled := clampi(difficulty, 0, 5)
	return "#".repeat(filled) + ".".repeat(5 - filled)

# --- What wakes it up -------------------------------------------------------

## The pen moved. Only the SIGN button and the line under the box care, so the
## whole sheet is not redrawn under a hand that is still writing.
func _on_pad_changed() -> void:
	if _pad.locked:
		return
	_sign_button.disabled = not _pad.is_signed()
	_hint.text = HINT_SIGN if _pad.is_signed() else HINT_MORE_INK
	_hint.add_theme_color_override("font_color",
		Color.WHITE if _pad.is_signed() else COLOR_OPEN)


## The host took a job. Every sheet turns to it, so a man reading a different
## page is shown what the crew is actually committed to rather than left
## comparing houses nobody is going to.
func _on_contract_signed(contract_id: String) -> void:
	var page := ContractManager.index_of(contract_id)
	if page != -1:
		_page = page
	if visible:
		_refresh()


func _on_hunt_time_set(_hunt_time: HuntTime.Type) -> void:
	if visible:
		_refresh()


## We were turned down. It lands only on the machine that asked, so the sentence
## is printed for the man who drew and for nobody else.
func _on_refused(reason: String) -> void:
	if not visible:
		return
	_hint.text = reason.to_upper()
	_hint.add_theme_color_override("font_color", COLOR_REFUSED)


## The shift moved on. The board closes with it, and anybody still reading the
## paperwork is handed his eyes back — the scene is about to go out from under
## him.
func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	close()

# --- The furniture ----------------------------------------------------------

## Builds the sheet once, on the way up. It is written here rather than laid out
## in a `.tscn` for the reason the menu's contract panel is: every row is a line
## of text in a column, and a scene file would be a second place for the same
## shape to be described.
func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(SHEET_WIDTH, 0)
	panel.add_theme_stylebox_override("panel", _paper_style())
	center.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	margin.add_child(column)

	column.add_child(_header_row())

	_client = _line()
	_address = _line()
	column.add_child(_client)
	column.add_child(_address)
	column.add_child(_spacer())

	_infestation = _line()
	_difficulty = _line()
	_pays = _line()
	_wager = _line()
	for label in [_infestation, _difficulty, _pays, _wager]:
		column.add_child(label)

	_notes = _line()
	_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_spacer())
	column.add_child(_notes)
	column.add_child(_spacer())

	_pad = SignaturePad.new()
	_pad.custom_minimum_size = PAD_SIZE
	_pad.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pad.changed.connect(_on_pad_changed)
	column.add_child(_pad)

	_hint = _line(COLOR_OPEN)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)

	column.add_child(_button_row())


## The strip along the top: an arrow at each end and the page number between
## them, so the board can be leafed with the mouse the same way it can with the
## keys.
func _header_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var previous := _button("<", func() -> void: _leaf(-1))
	row.add_child(previous)

	_title = _line()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_title)

	row.add_child(_button(">", func() -> void: _leaf(1)))
	return row


## The strip along the bottom: wipe the paper, put the pen down, or walk away.
func _button_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	_clear_button = _button("CLEAR", func() -> void: _pad.clear())
	_sign_button = _button("SIGN", _press_pen)
	row.add_child(_clear_button)
	row.add_child(_sign_button)
	row.add_child(_button("CLOSE (E)", close))
	return row


## One line of the sheet, in the same dress the rest of the HUD wears.
func _line(color := Color.WHITE) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## A blank line, used to group the writing rather than to say anything.
func _spacer() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.pressed.connect(pressed)
	return button


## The paper the whole thing is printed on: black, thinly ruled, the same panel
## the menu's contract board and the pause menu wear.
func _paper_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.88)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.55, 0.55, 0.75)
	return style
