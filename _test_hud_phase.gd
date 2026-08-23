extends SceneTree
## Phase HUD bench: what the strip says about the shift, and that it says it
## without anybody reloading anything.
##
## Run with: godot --headless --script _test_hud_phase.gd
##
## One machine and no wire, so `PhaseManager.is_host()` answers true throughout
## and every change goes down the host's own road — which is the path a solo
## game takes anyway. What cannot be checked here is two screens agreeing; that
## is a matter for two instances open side by side. What *can* be checked is the
## acceptance test of the card, which is a one-machine question: that a change to
## any player reaches the strip without the scene being reloaded, and that it
## reaches it off a signal rather than off a poll.
##
## The van and the house are later cards, so the phase machine is pointed at
## scenes that exist for the length of the bench, exactly as the phase and ready
## benches do. What is under test is the strip, not the artwork.

## Frames of slack to let a scene change actually happen.
const WAIT := 8

## Stand-in Steam IDs, as in the other benches.
const ANA := 111
const BRUNO := 222
const CARLA := 333

## Scenes that exist today, standing in for the van and the house.
const VAN := "res://scenes/lobby.tscn"
const HOUSE := "res://scenes/ps1.tscn"

## The strip itself, so that the card's own scene is exercised and not only the
## script behind it.
const HUD := "res://scenes/hud_phase.tscn"

## The autoloads. In a bench run with `--script` the global names do not exist
## yet — the MainLoop script is compiled before the autoloads enter the tree — so
## they are picked up by node name.
var _session: Node
var _phase: Node
var _ready_manager: Node

var _hud: CanvasLayer

var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	# Headless runs at thousands of frames a second, which would spend a
	# two-minute phase between two of them. A real frame rate is what makes a
	# clock measurable at all.
	Engine.max_fps = 60

	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_ready_manager = root.get_node_or_null("ReadyManager")


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_it_wakes_up_knowing_where_it_is()
		1: return _check_a_phase_with_no_clock_draws_none()
		2: return _check_the_clock_reads_in_minutes()
		3: return _check_a_crew_change_reaches_it()
		4: return _check_a_colour_reaches_it()
		5: return _check_a_ready_flag_reaches_it()
		6: return _check_a_phase_change_redraws_it()
		7: return _check_the_last_ten_seconds()
		8: return _check_the_hunt_takes_no_show_of_hands()
		9: return _check_nothing_is_polled()
	return _finish()

# --- Steps ------------------------------------------------------------------

## The strip is dropped into a shift that is already running. Everything on it
## has to be right on the first frame, because none of the signals it lives off
## will fire again until something moves.
func _check_it_wakes_up_knowing_where_it_is() -> bool:
	if _clock == 1:
		if _session == null or _phase == null or _ready_manager == null:
			print("FAIL: the session autoloads are not in the tree")
			return _finish()

		# Pointed at scenes that exist, as in the phase bench.
		_phase.scenes[Phase.Type.LOBBY] = VAN
		_phase.scenes[Phase.Type.TRAVEL] = VAN
		_phase.set_house(HOUSE)

		# The crew is in the van *before* the strip is, which is the case that
		# matters: a HUD that only listened would show an empty van forever.
		_session.register_player(ANA, "Ana", true)
		_session.register_player(BRUNO, "Bruno")

		_hud = (load(HUD) as PackedScene).instantiate()
		root.add_child(_hud)
		return false
	if _clock < 3:
		return false

	_expect(_phase.is_host(), "with no wire, the only player is his own host")
	_expect(_phase.current() == Phase.Type.LOBBY, "the shift starts in the van")
	_expect(_phase_text() == "LOBBY", "and the strip says so without being told")
	_expect(_ready_text() == "0/2 READY", "two in the van and neither of them ready")
	_expect(_crew_names() == ["- ANA", "- BRUNO"],
		"both names are up, marked as nobody having said it")
	return _advance()

## The lobby is not a phase running out of time — it is a phase nobody is timing.
## A clock reading 0:00 there would be a countdown to nothing.
func _check_a_phase_with_no_clock_draws_none() -> bool:
	_expect(not _phase.has_timer(), "no clock runs in the van")
	_expect(not _clock_label().visible, "so the strip draws none")
	return _advance()

## On the road, where there is one. Two minutes reads as `2:00`, and it counts
## down in minutes and seconds rather than in bare seconds.
func _check_the_clock_reads_in_minutes() -> bool:
	if _clock == 1:
		_phase.go_to(Phase.Type.TRAVEL)
		return false
	if _clock < WAIT:
		return false

	_expect(_phase.current() == Phase.Type.TRAVEL, "the van is on the road")
	_expect(_clock_label().visible, "so there is a clock on the strip")
	_expect(_phase_text() == "TRAVEL", "which knows what phase it is timing")

	# The real countdown is two minutes and the bench is not sitting through it,
	# so the numbers are checked by handing the strip the times it would see.
	_expect(_clock_at(120.0) == "2:00", "two minutes is 2:00")
	_expect(_clock_at(61.0) == "1:01", "and sixty-one seconds is 1:01")
	_expect(_clock_at(9.5) == "0:10", "a part-second is rounded up, not down")
	_expect(_clock_at(0.0) == "0:00", "and nought is 0:00")
	return _advance()

## The acceptance test of the card, first half: somebody walks in, and the strip
## has him without the scene being touched.
func _check_a_crew_change_reaches_it() -> bool:
	if _clock == 1:
		_session.register_player(CARLA, "Carla")
		return false
	if _clock < 3:
		return false

	_expect(_crew_names() == ["- ANA", "- BRUNO", "- CARLA"], "the new name is on the strip")
	_expect(_ready_text() == "0/3 READY", "and the count knows there are three of them")

	_session.remove_player(CARLA)
	_expect(_crew_names() == ["- ANA", "- BRUNO"], "and she is off it again when she quits")
	_expect(_ready_text() == "0/2 READY", "with the count back to two")
	return _advance()

## The colour a player picks in the van is worn on the strip too. It is read from
## `SessionManager` on every repaint and never kept here, which is what the
## colour station (a later card) will rely on.
func _check_a_colour_reaches_it() -> bool:
	# The palette is read off the autoload node rather than through the global
	# name: in a bench run with `--script` that name does not exist yet.
	var palette: Array = _session.COLORS
	var wanted: Color = palette[4]
	_session.set_color(BRUNO, wanted)
	var painted := _crew_color(1)
	_expect(painted.r == wanted.r and painted.g == wanted.g and painted.b == wanted.b,
		"the name is painted in the colour its man picked")
	# Not ready yet, so the line is dimmed rather than full — the colour is still
	# his, the brightness is what says he has not spoken.
	_expect(painted.a < 1.0, "and dimmed while he has not said he is ready")
	return _advance()

## The other half of the acceptance test: a flag moves and the strip moves with
## it, both in the count and beside the name.
func _check_a_ready_flag_reaches_it() -> bool:
	if _clock == 1:
		_ready_manager.request_set(BRUNO, true)
		return false
	if _clock < WAIT:
		return false

	_expect(_ready_text() == "1/2 READY", "one of two has said it")
	_expect(_crew_names() == ["- ANA", "* BRUNO"], "and the mark beside his name says which")
	_expect(_crew_color(1).a == 1.0, "his line comes up to full brightness with it")
	_expect(_crew_color(0).a < 1.0, "while the man who has not spoken stays dim")
	return _advance()

## A phase change redraws all of it. The flags were cleared on the way through —
## `PhaseManager.go_to` does it, and no player signal carries the news — so a
## strip that only listened to players would keep a mark beside a name whose flag
## is gone.
func _check_a_phase_change_redraws_it() -> bool:
	if _clock == 1:
		_phase.go_to(Phase.Type.SURVEY)
		return false
	if _clock < WAIT:
		return false

	_expect(_phase_text() == "SURVEY", "the strip is in the house")
	_expect(_ready_text() == "0/2 READY", "with the flags cleared behind it")
	_expect(_crew_names() == ["- ANA", "- BRUNO"], "and no mark left beside anybody")
	_expect(_clock_label().visible, "the survey is timed, so there is a clock")
	return _advance()

## The last ten seconds: the number goes red and blinks, and a beep goes off once
## a second rather than once a frame. The blink is the one thing on this node
## that runs every frame, and it has to stop when the stretch does.
func _check_the_last_ten_seconds() -> bool:
	if _clock == 1:
		_expect(not _hud.is_processing(), "with most of the phase left, nothing is animating")
		_expect(_clock_label().modulate.a == 1.0, "and the number is at full brightness")
		# The host's own timer is stopped for the length of the step so that the
		# strip keeps the times it is handed. Left running it would put the real
		# minute back on the label on the very next frame, and what is under test
		# here is the warning, not the minute.
		_phase._timer.stop()
		_hud._draw_clock(10.0)
		return false
	if _clock == 2:
		_expect(_hud.is_processing(), "inside ten seconds the number is animating")
		var warning_color: Color = _hud.WARNING_COLOR
		_expect(_clock_color() == warning_color, "and it has gone red")
		var beeps := 0
		# Three seconds of countdown, in the small steps the phase machine
		# actually fires `timer_updated` in. Forty packets from ten seconds down
		# to six carry three crossings of a whole second, and so three beeps — a
		# beep a second and not a beep a packet, which is what is being counted.
		for step in 40:
			var left := 10.0 - float(step) * 0.1
			var was: int = _hud._last_beep
			_hud._draw_clock(left)
			if _hud._last_beep != was:
				beeps += 1
		_expect(beeps == 3, "a beep a second, not a beep a frame")
		return false
	if _clock == 3:
		_expect(_clock_label().modulate.a < 1.0, "the blink has taken the number down")
		# Out the other side: a phase that is not ending is not urgent.
		_hud._draw_clock(30.0)
		_expect(not _hud.is_processing(), "past the warning nothing animates any more")
		_expect(_clock_label().modulate.a == 1.0, "and the number is whole again")
		var normal_color: Color = _hud.NORMAL_COLOR
		_expect(_clock_color() == normal_color, "and white again")
		return false
	return _advance()

## Out in the hunt there is no show of hands to take and no clock to run out, so
## the strip drops both rather than drawing a counter nobody can move and a
## countdown to nothing.
func _check_the_hunt_takes_no_show_of_hands() -> bool:
	if _clock == 1:
		_hud._draw_clock(3.0)
		_expect(_hud.is_processing(), "left in the middle of a warning")
		_phase.go_to(Phase.Type.HUNT)
		return false
	if _clock < WAIT:
		return false

	_expect(_phase_text() == "HUNT", "the rats are out")
	_expect(not _clock_label().visible, "nothing is timing the hunt")
	_expect(not _ready_label().visible, "and nobody is waiting on a show of hands")
	_expect(not _hud.is_processing(), "a phase left mid-blink stops blinking")
	_expect(_clock_label().modulate.a == 1.0, "and does not stay dim into the next one")
	return _advance()

## The card asks for zero polling of state, and this is what that means in
## practice: with nothing changing, the strip does no work at all. The only
## `_process` on it is the blink, which is an animation, and it is off.
func _check_nothing_is_polled() -> bool:
	if _clock == 1:
		_expect(not _hud.is_processing(), "an idle strip is not processing")
		_expect(not _hud.is_physics_processing(), "and not physics-processing either")
		return false
	if _clock < WAIT:
		return false

	# Back to the van, where every part of the strip is drawn, and idle again.
	_phase.go_to(Phase.Type.LOBBY)
	return _advance()

# --- Plumbing ---------------------------------------------------------------

func _phase_text() -> String:
	return (_hud.get_node("Panel/Margin/Rows/Phase") as Label).text


func _ready_label() -> Label:
	return _hud.get_node("Panel/Margin/Rows/Ready") as Label


func _ready_text() -> String:
	return _ready_label().text


func _clock_label() -> Label:
	return _hud.get_node("Panel/Margin/Rows/Clock") as Label


## What the clock reads at a given number of seconds left. It is handed the time
## the way `timer_updated` would, so the formatting is checked through the same
## door the phase machine comes in by.
func _clock_at(seconds_left: float) -> String:
	_hud._draw_clock(seconds_left)
	return _clock_label().text


func _clock_color() -> Color:
	return _clock_label().get_theme_color("font_color")


## The crew column as it reads on screen, top to bottom.
func _crew_names() -> Array[String]:
	var names: Array[String] = []
	for child in _hud.get_node("Crew/Margin/Rows").get_children():
		var label := child as Label
		# A line on its way out is still a child until the end of the frame.
		if label != null and not label.is_queued_for_deletion():
			names.append(label.text)
	return names


## What colour one line of the column is painted, by its place in it.
func _crew_color(index: int) -> Color:
	var rows := _hud.get_node("Crew/Margin/Rows").get_children()
	var line := rows[index] as Label
	return line.get_theme_color("font_color")


func _expect(condition: bool, what: String) -> void:
	if condition:
		return
	print("FAIL: %s" % what)
	_failures += 1


func _advance() -> bool:
	_step += 1
	_clock = 0
	return false


func _finish() -> bool:
	print("--- %d frames, %d failure(s) ---" % [_frames, _failures])
	return true
