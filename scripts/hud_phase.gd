extends CanvasLayer
## The shift on screen: which phase the crew is in, how long is left of it, who
## is ready and what colour each of them is wearing.
##
## The same strip in the van, on the road and in the house. It is one scene
## (`scenes/hud_phase.tscn`) dropped into each of them rather than three copies
## of a bar, for the same reason the ready board is one node used three times: a
## second copy is a second place for the answer to be wrong.
##
## **It reads and it draws, and it decides nothing.** Every number here already
## exists on an autoload — the phase and the clock on `PhaseManager`, the crew on
## `SessionManager` — and this only mirrors them. It never counts a second of its
## own, never keeps a copy of the crew and never asks the host anything.
##
## **Nothing is polled.** The strip wakes on the signals that can change what is
## written on it (`phase_changed`, `timer_updated`, and the three the crew fires)
## and sleeps in between. `_process` is turned on for one thing only, and it is
## not state: the blinking of the last ten seconds, which is an animation and has
## to move every frame. The clock itself is not read there — the number comes in
## on `timer_updated`, which the phase machine already fires every frame on the
## host and on the client alike.
##
## **PSX.** The whole HUD is drawn at 640x360, so a letter is 8 px, the colours
## are flat and there is a hard black outline behind every line instead of a
## shadow or a gradient — the same dress the money, the belt and the prompt in
## `world.tscn` already wear.

## The size of a letter on a 640x360 screen, matching the rest of the HUD.
const FONT_SIZE := 8
## The black every line is outlined against, and how thick it is drawn.
const OUTLINE_COLOR := Color(0, 0, 0, 1)
const OUTLINE_SIZE := 5

## The last stretch of a phase, in seconds: the number blinks and a beep goes off
## once a second through it.
const WARNING_TIME := 10.0
## What the clock reads in that stretch — the same red the health bar goes when
## it is nearly out.
const WARNING_COLOR := Color(0.95, 0.32, 0.28)
## And what it reads the rest of the time.
const NORMAL_COLOR := Color(1, 1, 1, 1)
## How many times a second the number blinks while it is warning, and how far
## down the dimmest of them goes. The same breathing the health bar does, so that
## the two urgent things on the screen are urgent in the same language.
const WARNING_BLINKS := 2.0
const WARNING_MIN_ALPHA := 0.35

## What a name in the side column is worth before its player has said he is
## ready — dimmed rather than greyed, so that a crew colour is still a crew
## colour while its man is still deciding.
const WAITING_ALPHA := 0.45
## What the multiplier line reads in, by how steep the bet is — the same three
## colours the clipboard and the wall sheet write it in, because it is the same
## number and a player should recognise it from the van.
const WAGER_COLOR := {
	HuntTime.Type.LONG: Color(1, 1, 1, 1),
	HuntTime.Type.MEDIUM: Color("ffb229"),
	HuntTime.Type.SHORT: Color("ff4b3a"),
}

## The mark beside a name, ready and not. Two characters of the same width, so
## that a man going ready does not shuffle the column he is in.
const READY_MARK := "*"
const WAITING_MARK := "-"

## The beep of the last ten seconds, built rather than loaded: there is no audio
## in the project yet, and a square wave at a few hundred hertz is what a PSX
## countdown sounded like anyway. Hertz, seconds, sample rate and how loud it
## sits against the rest.
const BEEP_HZ := 880.0
const BEEP_TIME := 0.06
const BEEP_RATE := 22050
const BEEP_DB := -14.0

@onready var _phase_label: Label = $Panel/Margin/Rows/Phase
@onready var _clock_label: Label = $Panel/Margin/Rows/Clock
@onready var _wager_label: Label = $Panel/Margin/Rows/Wager
@onready var _ready_label: Label = $Panel/Margin/Rows/Ready
@onready var _crew_rows: VBoxContainer = $Crew/Margin/Rows
@onready var _beep: AudioStreamPlayer = $Beep

## One line per player in the crew, in the order they walked in. Rebuilt only
## when the crew itself changes; a colour or a ready flag repaints the line that
## is already there.
var _crew_labels: Array[Label] = []

## Which whole second the last beep went off on, or -1 for none. It is what keeps
## the beep to one a second rather than one a frame.
var _last_beep := -1

## Whether the clock is in its last ten seconds. Kept because it is what decides
## whether `_process` has anything to do.
var _warning := false


func _ready() -> void:
	_beep.stream = _build_beep()
	_beep.volume_db = BEEP_DB
	set_process(false)

	PhaseManager.phase_changed.connect(_on_phase_changed)
	PhaseManager.timer_updated.connect(_on_timer_updated)
	SessionManager.player_joined.connect(_on_crew_added)
	SessionManager.player_left.connect(_on_crew_removed)
	SessionManager.player_changed.connect(_on_player_changed)

	# The shift started before this scene existed — the van is already parked and
	# the crew is already in it — so what is on screen first is read straight off
	# the autoloads rather than waited for.
	_rebuild_crew()
	_draw_phase()
	_draw_clock(PhaseManager.seconds_left)


## The blink of the last ten seconds, and nothing else. It is off for the whole
## of a phase but its ending, and off entirely in a phase with no clock on it.
func _process(_delta: float) -> void:
	var beat := absf(sin(Time.get_ticks_msec() / 1000.0 * PI * WARNING_BLINKS))
	_clock_label.modulate.a = WARNING_MIN_ALPHA + (1.0 - WARNING_MIN_ALPHA) * beat

# --- The strip --------------------------------------------------------------

## The phase's own name and the show of hands beside it. Both change on the same
## occasions, so they are drawn together.
func _draw_phase() -> void:
	_phase_label.text = Phase.name_of(PhaseManager.current()).to_upper()
	_draw_wager()
	_draw_ready()


## What each rat is worth this shift, shown in the hunt and nowhere else.
##
## In the van it would be noise — the sheet on the wall says it, and says it
## better, with the infestation next to it. In the house it is the one number the
## clock is worth watching for: a man deciding whether to chase the last rat into
## the cellar with forty seconds left is deciding it against this.
##
## Hidden rather than drawn as "x1" on a face-value shift: the line is a warning,
## and a warning that is always there is not one.
func _draw_wager() -> void:
	var booked: HuntTime.Type = SessionManager.hunt_time
	if PhaseManager.current() != Phase.Type.HUNT or HuntTime.multiplier(booked) <= 1.0:
		_wager_label.hide()
		return
	_wager_label.text = "x%d PAY" % int(HuntTime.multiplier(booked))
	_wager_label.add_theme_color_override("font_color",
		WAGER_COLOR.get(booked, NORMAL_COLOR))
	_wager_label.show()


## "2/4 READY". It is the count and not the list, which is what the side column
## is for — a man at the far end of the van reads the number and looks at the
## names only when it is not the one he wanted.
##
## A phase that takes no show of hands has no counter rather than one stuck at
## zero: out in the hunt there is nothing anybody could do to move it.
func _draw_ready() -> void:
	if not ReadyManager.is_active():
		_ready_label.hide()
		return
	var counts := ReadyManager.counts()
	_ready_label.text = "%d/%d READY" % [counts[0], counts[1]]
	_ready_label.show()


## The clock, in `M:SS`. A phase with no clock on it has no line rather than a
## line reading zero — the lobby is not a phase running out of time, it is a
## phase nobody is timing.
func _draw_clock(seconds_left: float) -> void:
	if not PhaseManager.has_timer():
		_stop_warning()
		_clock_label.hide()
		return
	_clock_label.text = _clock_text(seconds_left)
	_clock_label.show()
	_set_warning(seconds_left > 0.0 and seconds_left <= WARNING_TIME, seconds_left)


## Seconds as `M:SS`, rounded up: a clock reading 0:00 while there is still most
## of a second left is a clock that lies about the one moment anybody is watching
## it.
func _clock_text(seconds_left: float) -> String:
	var whole := int(ceil(maxf(0.0, seconds_left)))
	@warning_ignore("integer_division") # Whole minutes: the remainder is the seconds field beside it.
	return "%d:%02d" % [whole / 60, whole % 60]

# --- The last ten seconds ---------------------------------------------------

## Turns the warning on or off, and beeps once for each whole second that goes by
## while it is on. The blink itself is left to `_process`, because it has to move
## on frames where no second changed.
func _set_warning(on: bool, seconds_left: float) -> void:
	if not on:
		_stop_warning()
		return
	if not _warning:
		_warning = true
		_clock_label.add_theme_color_override("font_color", WARNING_COLOR)
		set_process(true)
	var second := int(ceil(seconds_left))
	if second != _last_beep:
		_last_beep = second
		_play_beep()


## Back to an ordinary clock: full brightness, white, no beeping and nothing to
## animate. Run on the way out of a phase as well as at the end of the warning,
## which is what keeps a strip that left a phase mid-blink from staying dim.
func _stop_warning() -> void:
	_last_beep = -1
	if not _warning:
		return
	_warning = false
	set_process(false)
	_clock_label.modulate.a = 1.0
	_clock_label.add_theme_color_override("font_color", NORMAL_COLOR)


## The beep, if there is anybody left to hear it. A strip whose scene has been
## freed under it still gets the phase machine's `timer_updated` for the frame —
## the autoload fires it every frame and this node is not disconnected until it
## is actually gone — and a player asked to play from outside the tree throws.
## It became reachable the moment the hunt grew a clock: the warning of the last
## ten seconds is the one thing here that fires on a phase about to end.
func _play_beep() -> void:
	if _beep.stream != null and _beep.is_inside_tree():
		_beep.play()


## The beep itself: a square wave, eight-bit and mono, which is both what the era
## sounded like and the cheapest thing to hand to the mixer. It is built here
## rather than loaded because there is no audio in the project yet, and a HUD
## that waits for a sound designer is a HUD nobody can test.
func _build_beep() -> AudioStreamWAV:
	var frames := int(BEEP_RATE * BEEP_TIME)
	var data := PackedByteArray()
	data.resize(frames)
	for i in frames:
		var cycle := fmod(float(i) * BEEP_HZ / float(BEEP_RATE), 1.0)
		# Faded out over its own length, or the cut at the end of the wave is a
		# click louder than the beep it ends.
		var fade := 1.0 - float(i) / float(frames)
		data[i] = int(roundf((80.0 if cycle < 0.5 else -80.0) * fade)) & 0xff
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_8_BITS
	wave.mix_rate = BEEP_RATE
	wave.stereo = false
	wave.data = data
	return wave

# --- The crew list ----------------------------------------------------------

## One line per player, from scratch. It is only run when the crew itself grows
## or shrinks — a colour changing repaints the line that is already there instead
## of tearing the column down and building it again.
func _rebuild_crew() -> void:
	for label in _crew_labels:
		label.queue_free()
	_crew_labels.clear()
	for steam_id in SessionManager.players:
		var label := _new_crew_label()
		# Added below the freed ones rather than after them: `queue_free` only
		# takes effect at the end of the frame, and a name left in the column
		# until then would push the new list down the screen and back up again.
		_crew_rows.add_child(label)
		_crew_labels.append(label)
		_paint_crew_line(label, steam_id)


## Repaints one player's line, wherever it is in the column. Falls back to
## rebuilding when the name is not on screen yet, which is the join whose
## `player_changed` beat its `player_joined` in.
func _repaint(steam_id: int) -> void:
	var at := SessionManager.players.keys().find(steam_id)
	if at == -1 or at >= _crew_labels.size():
		_rebuild_crew()
		return
	_paint_crew_line(_crew_labels[at], steam_id)


## A name in its own colour, with a mark for whether its man has said he is
## ready. The colour is read from `SessionManager` every time and never kept
## here: the colour station writes there, and a copy in the HUD would be the one
## place it could go stale.
func _paint_crew_line(label: Label, steam_id: int) -> void:
	var player := SessionManager.player(steam_id)
	var is_ready := bool(player.get("ready", false))
	var player_name := String(player.get("name", "?")).to_upper()
	label.text = "%s %s" % [READY_MARK if is_ready else WAITING_MARK, player_name]
	var color: Color = player.get("color", Color.WHITE)
	color.a = 1.0 if is_ready else WAITING_ALPHA
	label.add_theme_color_override("font_color", color)


## A blank line, dressed the way every other line of this HUD is. The rows are
## built in code rather than in the scene because there is one per player, and
## how many players there are is not known until they walk in.
func _new_crew_label() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_outline_color", OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", OUTLINE_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

# --- What wakes it up -------------------------------------------------------

## A phase change redraws the whole strip: the name, the clock and the show of
## hands all moved, and the ready flags were cleared on the way through — which
## the crew column has to hear about even though no player signal carries it.
func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_stop_warning()
	_draw_phase()
	_draw_clock(PhaseManager.seconds_left)
	var crew := SessionManager.players.keys()
	for i in mini(crew.size(), _crew_labels.size()):
		_paint_crew_line(_crew_labels[i], crew[i])


func _on_timer_updated(seconds_left: float) -> void:
	_draw_clock(seconds_left)


func _on_crew_added(_steam_id: int) -> void:
	_rebuild_crew()
	_draw_ready()


func _on_crew_removed(_steam_id: int) -> void:
	_rebuild_crew()
	_draw_ready()


## Colour, ready, money or bag — one signal for all of them, so the line is
## repainted and the counter asked again whichever of them it was.
func _on_player_changed(steam_id: int) -> void:
	_repaint(steam_id)
	_draw_ready()
