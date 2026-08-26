class_name SignaturePad
extends Control
## The box at the bottom of a contract, and the only place in the game where the
## player draws something rather than presses something.
##
## A contract is signed by hand: the mouse is let loose, the crew leader drags it
## across the paper and what he scrawls is what goes on the sheet. That is why
## the pen is a pad and not a button — a job the crew is about to walk into
## should cost a deliberate movement, not a click that can be made by accident
## on the way past.
##
## **It measures ink, not shape.** Nothing here reads what was drawn: it adds up
## how far the pen travelled and calls anything past `MIN_INK` a signature. A
## scribble counts, a name counts, a single dot does not — which is the whole of
## the rule, because the point is that somebody meant it.
##
## **It decides nothing about the contract.** The pad says whether there is a
## signature on it (`is_signed`) and announces that the drawing changed; whether
## that signature is worth anything is the sheet's business
## (`scripts/ui/contract_sheet.gd`), and whether the job is actually taken is the
## host's (`ContractManager`).

## The drawing changed — a stroke was added to, finished, or wiped off. The sheet
## listens so the SIGN button lights the moment there is enough ink for it.
signal changed()

## How far the pen has to travel, in pixels, before it counts as a signature. Low
## enough that a short scrawl passes, high enough that a click and a twitch does
## not.
const MIN_INK := 90.0
## How far the mouse has to move before a new point is kept. It thins the stroke
## out to something worth storing without any of it being visible on screen.
const MIN_STEP := 1.5

## The paper, the ink and the rule the signature sits on — the same bone-white
## the sheets in the van are printed on, so the box reads as part of the
## contract rather than as a widget dropped on top of it.
const COLOR_PAPER := Color("d3d2bf")
const COLOR_INK := Color("14161c")
const COLOR_RULE := Color(0.35, 0.35, 0.32, 1)
const COLOR_BORDER := Color(0.08, 0.08, 0.09, 1)
## What a locked pad is edged in once the job is taken.
const COLOR_SIGNED := Color("29c443")

## How thick the ink is laid down, and how wide the "X" beside the rule is drawn.
const INK_WIDTH := 1.6
const MARK_MARGIN := 6.0

## What a locked pad reads when the signature on it is somebody else's — the
## host signed on his own machine and his scrawl never crossed the wire, so there
## is nothing to draw and the stamp says so instead.
const STAMP := "SIGNED"

## Whether the pen is down. A locked pad is a signed one, or one this machine was
## never allowed to sign on; either way it draws what it has and refuses the
## mouse.
var locked := false:
	set(value):
		if locked == value:
			return
		locked = value
		_pen = PackedVector2Array()
		queue_redraw()

## Everything drawn so far, one entry per stroke. Local pixels, clamped to the
## box, so a hand that runs off the paper stops at the edge instead of writing on
## the table.
var _strokes: Array[PackedVector2Array] = []
## The stroke being drawn right now, empty between them.
var _pen := PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS


func _gui_input(event: InputEvent) -> void:
	if locked:
		return

	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index != MOUSE_BUTTON_LEFT:
			return
		if button.pressed:
			_pen = PackedVector2Array([_clamped(button.position)])
		else:
			_finish_stroke()
		accept_event()
		queue_redraw()
		changed.emit()
		return

	if event is InputEventMouseMotion and not _pen.is_empty():
		var motion := event as InputEventMouseMotion
		var point := _clamped(motion.position)
		if point.distance_to(_pen[_pen.size() - 1]) >= MIN_STEP:
			_pen.append(point)
			queue_redraw()
			changed.emit()
		accept_event()


## Whether there is enough ink on the paper to call it a signature.
func is_signed() -> bool:
	return ink() >= MIN_INK


## How far the pen has travelled across every stroke, in pixels. The unfinished
## stroke counts too, so the SIGN button lights while the hand is still moving
## rather than on the release.
func ink() -> float:
	var total := 0.0
	for stroke in _strokes:
		total += _length_of(stroke)
	return total + _length_of(_pen)


## Wipes the paper. The pen is dropped with it, so a CLEAR pressed mid-stroke
## does not leave half a scrawl waiting to be finished.
func clear() -> void:
	if _strokes.is_empty() and _pen.is_empty():
		return
	_strokes.clear()
	_pen = PackedVector2Array()
	queue_redraw()
	changed.emit()


## The drawing, for a sheet that wants to put it away and bring it back when the
## reader leafs round to the signed job again.
func strokes() -> Array[PackedVector2Array]:
	_finish_stroke()
	return _strokes.duplicate(true)


## Puts a drawing back on the paper. Used to restore the signature the leader
## already made rather than to hand one machine another's scrawl — a signature
## never crosses the wire.
func set_strokes(value: Array[PackedVector2Array]) -> void:
	_strokes = value.duplicate(true)
	_pen = PackedVector2Array()
	queue_redraw()
	changed.emit()


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	draw_rect(box, COLOR_PAPER)
	draw_rect(box, COLOR_SIGNED if locked else COLOR_BORDER, false, 1.0)

	# The rule the name goes on, with the "X" every form in the world puts at
	# the start of it.
	var baseline := size.y - MARK_MARGIN
	draw_line(Vector2(MARK_MARGIN, baseline), Vector2(size.x - MARK_MARGIN, baseline),
		COLOR_RULE, 1.0)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(MARK_MARGIN, baseline - 1.0), "X",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_RULE)

	for stroke in _strokes:
		_draw_stroke(stroke)
	_draw_stroke(_pen)

	# A pad locked with nothing on it is a job somebody else signed. Say so,
	# rather than showing blank paper that reads as a signature that failed to
	# draw.
	if locked and _strokes.is_empty():
		draw_string(font, Vector2(MARK_MARGIN + 10.0, baseline - 1.0), STAMP,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 8, COLOR_SIGNED)


## One stroke. A stroke of a single point is a dot rather than a line, because
## `draw_polyline` draws nothing at all for one point and a pen put down and
## lifted should still leave a mark.
func _draw_stroke(stroke: PackedVector2Array) -> void:
	if stroke.size() >= 2:
		draw_polyline(stroke, COLOR_INK, INK_WIDTH)
	elif stroke.size() == 1:
		draw_circle(stroke[0], INK_WIDTH * 0.5, COLOR_INK)


## Puts the pen down and keeps whatever it drew. Called on the mouse release and
## again by anything that reads the drawing, so a stroke still in the hand is
## never lost or counted twice.
func _finish_stroke() -> void:
	if _pen.is_empty():
		return
	_strokes.append(_pen)
	_pen = PackedVector2Array()


## How long a polyline is, end to end.
func _length_of(stroke: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, stroke.size()):
		total += stroke[i - 1].distance_to(stroke[i])
	return total


## A point pulled back inside the paper. A hand that runs off the edge stops at
## it instead of drawing across the rest of the sheet.
func _clamped(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x, 0.0, size.x), clampf(point.y, 0.0, size.y))
