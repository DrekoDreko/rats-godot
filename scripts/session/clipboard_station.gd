class_name ClipboardStation
extends Interactable
## The clipboard hanging by the door of the van: the crew reads the jobs on it,
## leafs through them, and the leader signs one.
##
## **It is a close-up, not a menu.** Pressing `E` does not open a window over the
## world — it moves the view onto the board, the way a man picks a clipboard off
## its hook and holds it up to his face. The sheet is real geometry in the van
## and the camera is a second `Camera3D` parked in front of it, so what is being
## read is the same object everybody else in the van can see somebody standing
## at. That is the whole reason this is not a `Control`: a menu would be on one
## screen only, and the van would show a man staring at a wall.
##
## **Leafing is local, signing is not.** Which page a man is on is his own
## business — four of the crew reading four different jobs at once is the point
## of a clipboard — so the arrows move `_page` and nothing else, and nothing goes
## on the wire. The pen is the one thing that does: it asks `ContractManager`,
## the host decides, and what comes back is what every sheet in every van reads
## (see that file for why the round trip is visible rather than optimistic).
##
## **A client is told before he presses, not after.** The pen reads "only the
## leader signs" and is drawn dim on a machine that is not the host, so that
## the rule is something the crew can see rather than something they find out by
## being refused. Pressing it anyway still gets an honest answer out loud — the
## refusal is played and printed — because a button that silently does nothing
## is indistinguishable from a key that is not working.
##
## **The sheet is drawn from the resource, every time.** Nothing here stores a
## contract: the page is an index, the sheet is redrawn off `ContractManager`,
## and the signed job is read off `SessionManager` through it. That is why the
## contract picked in the van is still the contract in the house — nobody ever
## copied it onto a node the next scene would throw away.

## What the prompt reads, on the hook and in the close-up. The board says what
## pressing it would do rather than what it is, the way the ready board does.
const PROMPT_READ := "read the contract"
const PROMPT_LEAVE := "put the clipboard back"

## The two colours the pen light reads in: amber where a signature is possible,
## near black where it is not. Two flat colours and no in-between, the way a
## panel with two states on it was in 1998.
const COLOR_PEN := Color("ffb229")
const COLOR_PEN_DEAD := Color("140f08")
## And the green a sheet is stamped with once it is the signed one.
const COLOR_SIGNED := Color("29c443")

## How bright the lamp over the board burns while somebody may sign, and what it
## falls to otherwise. Not zero: an unlit board in a dark van is a board nobody
## finds.
const LAMP_ENERGY := 1.2
const LAMP_ENERGY_OFF := 0.3

## How long the camera takes to travel between the player's eyes and the board,
## in seconds. Short enough not to be a wait, long enough that the cut reads as
## a movement rather than a teleport.
const MOVE_TIME := 0.22

## What the sheet says when the folder is empty. It should not happen — the
## three test jobs ship with the game — but a board with nothing on it must say
## so rather than show a blank sheet that looks like a bug.
const NO_JOBS := "THE BOARD IS EMPTY"

## The close-up camera, parked in front of the sheet and made current while the
## board is being read. It is a node in the scene rather than one built here so
## that where the sheet is read from can be nudged in the editor.
@export var camera_path: NodePath = ^"Close/Camera"
## The label carrying the sheet's writing, on a `SubViewport` behind the paper.
@export var sheet_path: NodePath = ^"Close/Sheet/Viewport/Margin/Rows"
## The lamp over the board.
@export var lamp_path: NodePath = ^"Lamp"
## The pen: a small mesh that lights when a signature is possible here.
@export var pen_path: NodePath = ^"Pen"

## The page turning, heard by everybody near the board.
@export var page_sound_path: NodePath = ^"Page"
## The pen going down, likewise.
@export var sign_sound_path: NodePath = ^"Sign"
## The refusal, heard only on the machine that was turned down — it is that
## player's own business and nobody else's.
@export var refused_sound_path: NodePath = ^"Refused"

@onready var _camera: Camera3D = get_node_or_null(camera_path) as Camera3D
@onready var _rows: VBoxContainer = get_node_or_null(sheet_path) as VBoxContainer
@onready var _lamp: OmniLight3D = get_node_or_null(lamp_path) as OmniLight3D
@onready var _pen: MeshInstance3D = get_node_or_null(pen_path) as MeshInstance3D
@onready var _page_sound: AudioStreamPlayer3D = \
	get_node_or_null(page_sound_path) as AudioStreamPlayer3D
@onready var _sign_sound: AudioStreamPlayer3D = \
	get_node_or_null(sign_sound_path) as AudioStreamPlayer3D
@onready var _refused_sound: AudioStreamPlayer3D = \
	get_node_or_null(refused_sound_path) as AudioStreamPlayer3D

## The player standing at the board, or null when nobody is. It is what the view
## is handed back to on the way out, and what stops a second man opening a board
## somebody else is already holding.
var _reader: Node3D

## Which sheet is face up. Local, always — see the note above about leafing.
var _page := 0

## The camera that was current before we took the view, so it can be given back
## exactly as it was rather than guessed at.
var _previous_camera: Camera3D

## The pen's own material, made private on the way up so that lighting this pen
## does not light every mesh sharing the resource.
var _pen_material: StandardMaterial3D

## The frame the board was opened on, or -1 when it is not open. The player uses a
## station out of his own `_unhandled_input` and leaves the event unhandled, so
## the very press that reached for the clipboard carries on down the list and
## arrives here a listener later — by which time the board is open and `E` means
## "put it back", and the one press would open the board and shut it again in the
## same breath.
##
## A frame number and not a flag. A flag has to be cleared by something, and the
## only thing available to clear it is the next event to arrive — which, on a
## board opened without an event behind it, is some innocent key much later that
## gets eaten instead. The frame answers "is this still the press that opened us"
## without needing anything to happen afterwards.
##
## Physics frames rather than process frames: both advance in the game, but only
## physics advances in a `--script` bench, and a guard that silently swallows
## everything under test is worse than no guard.
var _opened_frame := -1


func _ready() -> void:
	add_to_group("clipboard_station")
	_pen_material = _own_material(_pen)

	# The close-up camera must not be current before anybody has asked for it —
	# a clipboard that steals the view on the way up would open the van looking
	# at a sheet of paper.
	if _camera != null:
		_camera.current = false

	# Everything that can change what the sheet says, and nothing that cannot.
	# No `_process`: a board polling the host sixty times a second for an answer
	# that changes once a lobby is work for nothing.
	ContractManager.contract_signed.connect(_on_contract_signed)
	ContractManager.request_refused.connect(_on_refused)
	PhaseManager.phase_changed.connect(_on_phase_changed)

	# Open on the signed job rather than on the first one, so that a man who
	# picks the board up after somebody signed sees what he is going to.
	_page = maxi(0, ContractManager.index_of(SessionManager.current_contract))
	_redraw()


## The keys that work while the board is being held: the arrows leaf, the
## interact key signs, and Esc puts it back.
##
## `_unhandled_input` and not `_input`, so that anything with a stronger claim on
## a key gets it first. The player himself is stopped for the duration
## (`set_ui_open`), so none of this is fighting the camera or the belt.
func _unhandled_input(event: InputEvent) -> void:
	if _reader == null:
		return
	# A board on its way out of the tree — the van being freed under a scene
	# change — still gets the frame's input, and has no viewport to hand it back
	# to. Nothing it could do with a key would outlive the frame anyway.
	if not is_inside_tree():
		return
	# The press that opened the board is still travelling — see `_opened_frame`.
	# One press is one action, and this one has already been spent.
	if Engine.get_physics_frames() == _opened_frame:
		return
	# `E` puts the board back, because that is what the prompt on screen says it
	# does — the same key that picked the clipboard up drops it again, the way
	# every other station in the van answers to one key. Esc does it too, for the
	# hand already reaching there.
	#
	# Which leaves the signature to the click, and that is the better home for it
	# anyway: a man signs by putting the pen to the sheet, and the pen is drawn on
	# the sheet. It also means the key that leaves and the key that commits the
	# crew to a job are not the same key — the old arrangement signed whatever
	# page was face up every time somebody tried to walk away.
	if event.is_action_pressed("cancel") or event.is_action_pressed("interact"):
		_close()
	elif event.is_action_pressed("move_left"):
		_leaf(-1)
	elif event.is_action_pressed("move_right"):
		_leaf(1)
	elif event.is_action_pressed("attack"):
		_press_pen()
	else:
		return
	# Whatever we acted on is ours: the belt and the camera must not see it too.
	# Asked for rather than assumed: a board being taken out from under a scene
	# change is still handed the frame's input and has no viewport left to tell,
	# and there is nothing to swallow the key on behalf of a tree we have left.
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()


## Hands on the board. `by` is the player who reached for it, and unlike every
## other station in the van it is *kept* — the close-up has to give the view
## back to the man it took it from, and has to stop him walking off while he is
## holding a clipboard up to his face.
func use(by: Node3D) -> void:
	super.use(by)
	if _reader != null:
		return
	_open(by)

# --- Picking the board up and putting it down -------------------------------

## Takes the view. The player is stopped where he stands (`set_ui_open`), which
## is the same thing the shop screen does to him and for the same reason: a man
## reading a sheet of paper is not also walking across the van.
##
## The mouse is put back under the game's control straight afterwards. The
## player releases it on the way into a UI because the shop has buttons to click;
## this has none — it is read with the arrow keys — and a loose cursor sitting
## over a close-up of a clipboard is only something to lose track of.
func _open(by: Node3D) -> void:
	if by == null or not by.has_method("set_ui_open"):
		return
	_reader = by
	_opened_frame = Engine.get_physics_frames()
	_reader.set_ui_open(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Open on the signed job when there is one — the board a man picks up should
	# show what the crew agreed to, not page one.
	var signed_page := ContractManager.index_of(SessionManager.current_contract)
	if signed_page != -1:
		_page = signed_page

	# The same care the input path takes: a board reached for on the frame its van
	# is being freed has no viewport to ask, and no camera worth remembering.
	var viewport := get_viewport()
	_previous_camera = viewport.get_camera_3d() if viewport != null else null
	if _camera != null:
		_camera.current = true
	prompt = PROMPT_LEAVE
	_play(_page_sound)
	_redraw()


## Puts the board back on its hook and gives the man his eyes and his legs back.
## The camera he had is made current again rather than the close-up merely
## switched off, because a viewport with no current camera falls back to
## whichever one it finds first — which in a van full of crew is somebody else's.
func _close() -> void:
	if _reader == null:
		return
	if _camera != null:
		_camera.current = false
	if is_instance_valid(_previous_camera):
		_previous_camera.current = true
	_previous_camera = null

	if is_instance_valid(_reader) and _reader.has_method("set_ui_open"):
		_reader.set_ui_open(false)
	_reader = null
	_opened_frame = -1
	prompt = PROMPT_READ
	_redraw()


## Whether somebody on this machine is holding the board. The van asks before it
## does anything that would pull the view out from under him.
func is_open() -> bool:
	return _reader != null

# --- Leafing and signing ----------------------------------------------------

## Turns a page. It wraps at both ends: a board of three jobs read with one hand
## should not need the other one to get back to the first.
func _leaf(step: int) -> void:
	var total := ContractManager.count()
	if total <= 1:
		return
	_page = wrapi(_page + step, 0, total)
	_play(_page_sound)
	_redraw()


## The pen. It never writes anything: it asks, and what the host answers is what
## the sheet ends up reading.
##
## A client is refused here as well as by the host, which is not redundant —
## refusing locally is what plays the buzzer at the moment of the press rather
## than a round trip later, and the host refusing the same thing again is what
## makes the rule true rather than merely displayed.
func _press_pen() -> void:
	var contract := ContractManager.at(_page)
	if contract == null:
		_play(_refused_sound)
		return
	if not ContractManager.may_sign():
		_on_refused(ContractManager.REFUSAL_NOT_HOST)
		return
	if not ContractManager.is_open():
		_on_refused(ContractManager.REFUSAL_UNDER_WAY)
		return
	if SessionManager.current_contract == contract.id:
		# Signing the job already signed is not a refusal, it is a no-op. The pen
		# still makes its noise so the press is acknowledged.
		_play(_sign_sound)
		return
	_play(_sign_sound)
	ContractManager.request_sign(contract.id)

# --- What is drawn ----------------------------------------------------------

## The sheet, from scratch. Cheap enough that working out what exactly changed
## would cost more than doing all of it, and it means there is one function to
## read rather than four that have to agree.
func _redraw() -> void:
	_redraw_pen()
	if _rows == null:
		return
	for child in _rows.get_children():
		child.queue_free()

	var contract := ContractManager.at(_page)
	if contract == null:
		_rows.add_child(_line(NO_JOBS))
		return

	var signed := SessionManager.current_contract == contract.id
	_rows.add_child(_line("JOB %d/%d" % [_page + 1, ContractManager.count()]))
	_rows.add_child(_line(contract.client_name.to_upper()))
	_rows.add_child(_line(contract.address))
	_rows.add_child(_line(""))
	_rows.add_child(_line("INFESTATION  %d" % contract.infestation))
	_rows.add_child(_line("DIFFICULTY   %s" % _pips(contract.difficulty)))
	_rows.add_child(_line("PAYS         %d" % contract.reward))
	_rows.add_child(_line(""))
	if not contract.notes.is_empty():
		var notes := _line(contract.notes)
		notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_rows.add_child(notes)
		_rows.add_child(_line(""))
	_rows.add_child(_line(_footer(signed), COLOR_SIGNED if signed else Color.WHITE))


## The line along the bottom of the sheet: what the reader can do about this
## job, in his own case. Four different sentences for four different situations,
## because "press E" on a sheet a client cannot sign is a lie.
func _footer(signed: bool) -> String:
	if signed:
		return "* SIGNED *"
	if not ContractManager.is_open():
		return "THE JOB IS UNDER WAY"
	if not ContractManager.may_sign():
		return "ONLY THE LEADER SIGNS"
	return "CLICK - SIGN   A/D - LEAF   E - BACK"


## The pen and the lamp over the board: lit where a signature is possible from
## this machine, dark where it is not. It is what says "you are the leader" at a
## glance, from across the van and without picking the board up.
func _redraw_pen() -> void:
	var live := ContractManager.may_sign() and ContractManager.is_open()
	var color := COLOR_PEN if live else COLOR_PEN_DEAD
	if _lamp != null:
		_lamp.light_color = COLOR_PEN
		_lamp.light_energy = LAMP_ENERGY if live else LAMP_ENERGY_OFF
	if _pen_material != null:
		_pen_material.albedo_color = color
		# Unshaded and emissive together are what make a PSX fitting read as lit
		# from inside rather than as a surface somebody is shining a torch on.
		_pen_material.emission = color
		_pen_material.emission_energy_multiplier = 1.0 if live else 0.0


## One line of the sheet. Bitmap-flat and hard-outlined, the same dress the rest
## of the HUD wears — no antialiasing, no gradient, no shadow.
func _line(text: String, color := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)
	return label


## The difficulty as a row of marks rather than a number, so that three jobs can
## be told apart at a glance without reading. Filled and empty are the same
## width, so the row does not shuffle between pages.
func _pips(difficulty: int) -> String:
	var filled := clampi(difficulty, 0, 5)
	return "#".repeat(filled) + ".".repeat(5 - filled)

# --- What wakes it up -------------------------------------------------------

## The host signed something. Everybody's board turns to it, including the boards
## nobody is holding — a man who picks it up next should not have to hunt for
## what the crew agreed to.
func _on_contract_signed(contract_id: String) -> void:
	_play(_sign_sound)
	var page := ContractManager.index_of(contract_id)
	if page != -1:
		_page = page
	_redraw()


## We were turned down. Heard only on the machine that asked, so the buzzer plays
## for the man who pressed and for nobody else.
func _on_refused(reason: String) -> void:
	_play(_refused_sound)
	print("Contract refused: %s" % reason)


## The van pulled off. The board is closed from here on, and anybody still
## holding it up to his face is handed his eyes back — the scene is about to go
## out from under him, and a close-up camera left current through a scene change
## is a black screen nobody can explain.
func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_close()
	_redraw()

# --- Odds and ends ----------------------------------------------------------

## A private copy of a mesh's material, so that lighting this pen does not light
## every mesh sharing the resource. Godot hands out the same `StandardMaterial3D`
## to every instance of a scene otherwise, and the ready board and the colour
## panel pay the same toll for the same reason.
func _own_material(mesh: MeshInstance3D) -> StandardMaterial3D:
	if mesh == null:
		return null
	var source := mesh.get_active_material(0) as StandardMaterial3D
	var copy: StandardMaterial3D = source.duplicate() if source != null \
		else StandardMaterial3D.new()
	copy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.set_surface_override_material(0, copy)
	return copy


## A sound, if the board was built with one. Every one of them is optional, so
## that a clipboard can be dropped into a grey-box van before there is any audio
## in the project at all.
func _play(player: AudioStreamPlayer3D) -> void:
	if player != null and player.stream != null:
		player.play()
