extends CanvasLayer
## The pay slip: what the shift caught, what it left in the walls, and what the
## whole of it came to. Shown when the phase turns to `RESULT`, dismissed with
## one button, and the button is the road back to the van, where the crew keeps
## what it made and signs for the next house.
##
## **Drawn over the house, not instead of it.** `RESULT` has no scene of its own
## (`PhaseManager.scenes`), so the room the crew has just cleared is still
## standing behind this panel. That is deliberate: a slip read in the hallway
## reads as the end of *that* job, where the same numbers on a black screen read
## as a menu.
##
## **The numbers are this player's.** `ShiftReport` tallies each machine's own
## catches, the same way `Wallet` holds each machine's own money, so what a man
## reads here is what his own hands earned. A crew total is a wire problem and
## is not what the shift pays on today.
##
## **One button, and only the host's moves the shift.** Everybody can put his own
## slip down — a man who has read it should not have to keep looking at it — but
## the shift walks on when the host says so, because every other phase change in
## the game is the host's and a slip that let four machines each decide when the
## van loads would be four vans loading at four different moments. What a guest
## sees after he puts it down is the house, and then the van when the host has
## pressed his.

const FONT_SIZE := 8
const OUTLINE_COLOR := Color(0, 0, 0, 1)
const OUTLINE_SIZE := 4

const TITLE_CLEARED := "HOUSE CLEARED"
const TITLE_TIME_UP := "TIME UP"

const CLEARED_COLOR := Color(0.55, 0.85, 0.45)
const TIME_UP_COLOR := Color(0.95, 0.72, 0.32)
const MUTED_COLOR := Color(0.72, 0.72, 0.72)
const ESCAPED_COLOR := Color(0.95, 0.42, 0.42)

## The line under the button on a machine that is not the host's, once the slip
## has been put down and there is nothing to do but wait on the crew leader.
const WAITING_TEXT := "Waiting for the crew leader..."

## The in-game HUD, which has nothing to say once the shift is over: the
## crosshair, the belt, the health bar, the help text and the running rat count
## are all instructions for a hunt that has finished. Named rather than reached
## by group, because it is one `CanvasLayer` in the house scene and hiding the
## layer hides the lot.
@export var hud_path: NodePath = ^"../HUD"

@onready var _title: Label = $Center/Panel/Margin/Rows/Title
@onready var _subtitle: Label = $Center/Panel/Margin/Rows/Subtitle
@onready var _lines: VBoxContainer = $Center/Panel/Margin/Rows/Lines
@onready var _total: Label = $Center/Panel/Margin/Rows/Total
@onready var _ok: Button = $Center/Panel/Margin/Rows/OK
@onready var _waiting: Label = $Center/Panel/Margin/Rows/Waiting

var _player: Node

## What the HUD's visibility was before the slip covered it, so putting the slip
## down gives back what was there rather than turning on a HUD the shop had
## deliberately hidden.
var _hud_was_visible := true


func _ready() -> void:
	# The slip has to be readable and clickable whatever the tree is doing. It is
	# not itself a pause — the shift is over and there is nothing left to pause —
	# but a man who had the pause menu up when the last rat died would otherwise
	# find a button that does not answer.
	process_mode = Node.PROCESS_MODE_ALWAYS

	hide()
	_ok.add_theme_font_size_override("font_size", FONT_SIZE)
	_ok.pressed.connect(_on_ok_pressed)

	PhaseManager.phase_changed.connect(_on_phase_changed)

	# The phase can already be `RESULT` when this node arrives. It does not
	# happen in a played shift — the slip is instanced with the house and the
	# house is entered in survey — but a bench that loads the scene straight
	# into the pay phase should still be shown one.
	if PhaseManager.current() == Phase.Type.RESULT:
		_open()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	# Enter and Esc both put the slip down. Swallowed either way, so the key does
	# not go on to the pause menu or to the player's own mouse toggle.
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("toggle_mouse"):
		get_viewport().set_input_as_handled()
		# Swallowed even with the button already spent, so a guest leaning on Esc
		# while he waits on the host does not fall through to the pause menu.
		if not _ok.disabled:
			_on_ok_pressed()

# --- Opening and putting down -----------------------------------------------

func _open() -> void:
	if visible:
		return
	_draw()
	show()

	# The player is told so that the mouse he is about to need is his to move:
	# the same flag the shop screen raises, and what stops the camera swinging
	# round while the slip is being read.
	_player = get_tree().get_first_node_in_group("player")
	if _player != null and _player.has_method("set_ui_open"):
		_player.set_ui_open(true)
	_show_hud(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ok.grab_focus()


## The slip off the screen altogether, and the house given back: the mouse, the
## HUD and the camera. Called when the pay phase ends, which on the host is the
## moment he presses OK and on a guest is the moment the host's press lands.
func _put_down() -> void:
	if not visible:
		return
	hide()
	if _player != null and _player.has_method("set_ui_open"):
		_player.set_ui_open(false)
	_player = null
	_show_hud(true)


func _on_ok_pressed() -> void:
	if PhaseManager.is_host():
		# Back to the van. The slip is not taken down here: the phase change is
		# what takes it down (`_on_phase_changed`), and it is about to arrive.
		# Hiding it first would only mean a frame of empty house before the road.
		PhaseManager.advance()
		return

	# A guest has read his and has nothing else to say, but he cannot move the
	# shift — that is the host's, the same as every other phase change in the
	# game. So the slip stays up with the button spent, and the line under it
	# says who everybody is waiting on. Taking the whole panel away instead
	# would leave him standing in a finished house with nothing on screen to
	# say why he is still there.
	_ok.disabled = true
	_waiting.text = WAITING_TEXT
	_waiting.show()


func _on_phase_changed(_previous: Phase.Type, current: Phase.Type) -> void:
	if current == Phase.Type.RESULT:
		_open()
		return
	# Out of the pay phase by any road — the host pressed his OK, or the wire
	# went down and `NetworkGuard` sent everybody home. Either way the slip goes.
	_put_down()

# --- The slip ---------------------------------------------------------------

func _draw() -> void:
	var cleared := ShiftReport.is_clear()
	_title.text = TITLE_CLEARED if cleared else TITLE_TIME_UP
	_title.add_theme_color_override("font_color", CLEARED_COLOR if cleared else TIME_UP_COLOR)

	var contract := ContractManager.current()
	_subtitle.text = "" if contract == null else "%s — %s" % [
		contract.client_name, contract.address,
	]
	_subtitle.visible = not _subtitle.text.is_empty()

	for row in _lines.get_children():
		row.queue_free()

	_add_line("Rats caught", "%d / %d" % [ShiftReport.caught, ShiftReport.infestation])
	if ShiftReport.escaped() > 0:
		_add_line("Left in the walls", str(ShiftReport.escaped()), ESCAPED_COLOR)
	_add_line("Time taken", ShiftReport.clock())
	_add_line("Pay rate", "x%d" % int(SessionManager.hunt_multiplier()))

	# What was caught and how it died, each shown only when there is something to
	# say: a shift with nothing in the bag should read as a short slip, not as a
	# column of noughts.
	var species_rows := ShiftReport.species_rows()
	if not species_rows.is_empty():
		_add_separator()
		for row in species_rows:
			_add_line(String(row[0]), "x%d" % int(row[1]), MUTED_COLOR)

	var death_rows := ShiftReport.death_rows()
	if not death_rows.is_empty():
		_add_separator()
		for row in death_rows:
			_add_line(Death.name_of(row[0]).capitalize(), "x%d" % int(row[1]), MUTED_COLOR)

	_add_separator()
	_add_line("Catches", "$ %d" % ShiftReport.earned)
	var bonus := ShiftReport.bonus()
	if bonus > 0:
		_add_line("Contract bonus", "$ %d" % bonus, CLEARED_COLOR)

	_total.text = "TOTAL   $ %d" % ShiftReport.total()

	# Armed again, and the waiting line back down: a second shift draws a fresh
	# slip, and it should not open already spent from the last one.
	_ok.disabled = false
	_waiting.hide()


## The HUD out of the way while the slip is up, and back as it was afterwards.
## A guest who has put his slip down is standing in the house again and wants
## his screen back; on the host there is nothing after this but the road.
func _show_hud(on: bool) -> void:
	var hud := get_node_or_null(hud_path) as CanvasLayer
	if hud == null:
		return
	if not on:
		_hud_was_visible = hud.visible
		hud.visible = false
		return
	hud.visible = _hud_was_visible


func _add_line(label_text: String, value_text: String, color := Color.WHITE) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_label := _label(label_text, color)
	# The name takes whatever width is going, which is what pins every value to
	# the same right-hand edge however long the names turn out to be.
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var value_label := _label(value_text, color)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_label)

	_lines.add_child(row)


func _add_separator() -> void:
	_lines.add_child(HSeparator.new())


func _label(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	return label
