extends ProgressBar
## The player's flesh on screen: a bar that drains, spanning the belt's three
## slots and sitting right over them.
##
## Like every other piece of this HUD it only mirrors what the player already
## knows (`player.gd`): the count lives there, so a bandage, a bite or a respawn
## cannot leave the screen showing a health nobody has. It reads the starting
## state straight from the player — the shift began before anyone was listening
## — and follows the signals from then on.
##
## With a rat in hand it goes away along with the hotbar and the crosshair: it
## is over the slots that it sits, and it is exactly there that the strangling
## prompt opens.

## What the bar is worth at each stage of the beating. Whole it is the green of
## a full shift; hurt it turns the same amber the strangling prompt uses, and
## about to go out, its red.
const WHOLE_COLOR := Color(0.55, 0.85, 0.45)
const HURT_COLOR := Color(0.94, 0.86, 0.36)
const CRITICAL_COLOR := Color(0.95, 0.32, 0.28)
## Where one stage gives way to the next, as a fraction of the whole flesh.
const HURT_FRACTION := 0.6
const CRITICAL_FRACTION := 0.25
## A wound whitens the bar for an instant before it settles back into its
## colour: with no number beside it, the whitening is what makes a hit read as a
## hit and not as a bar that quietly got shorter.
const FLASH_COLOR := Color(1, 1, 1, 1)
const FLASH_TIME := 0.25
## About to go out, the bar breathes. Blinks per second, and how far down the
## dimmest of them goes.
const CRITICAL_BLINKS := 2.0
const CRITICAL_MIN_ALPHA := 0.4

## What is left of the flash, in seconds. Zero means there is none.
var _flash := 0.0
## The last fraction that came in, which is what the colour is read from.
var _fraction := 1.0

func _ready() -> void:
	set_process(false)
	# Wait one frame so the player is already in the tree.
	await get_tree().process_frame
	# A phase can end on the frame this HUD is waiting through — the board in the
	# van does exactly that — and a node that wakes up under a freed scene has no
	# tree left to look a player up in. There is nobody to wire to in that case,
	# and the HUD is on its way out with the rest of the scene anyway.
	if not is_inside_tree():
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.health_changed.connect(_on_health_changed)
	player.damaged.connect(_on_damaged)
	player.capture_started.connect(_on_capture_started)
	player.capture_finished.connect(_on_capture_finished)
	_on_health_changed(player.health(), player.max_health)

func _process(delta: float) -> void:
	_flash = maxf(0.0, _flash - delta)
	_paint()
	# The flash burns out and the breathing only happens down at the bottom:
	# with neither of them left there is nothing here to animate.
	if _flash == 0.0 and not _is_critical():
		set_process(false)

func _on_health_changed(current: int, maximum: int) -> void:
	_fraction = 0.0 if maximum <= 0 else float(current) / float(maximum)
	value = _fraction
	_paint()
	if _is_critical():
		set_process(true)

func _on_damaged(_amount: int, _remaining: int) -> void:
	_flash = FLASH_TIME
	set_process(true)

func _on_capture_started(_rat: Node3D) -> void:
	hide()

func _on_capture_finished(_killed: bool) -> void:
	show()

## The bar's colour: the stage it is at, whitened by whatever is left of the
## flash and dimmed by the breathing when it is about to go out.
func _paint() -> void:
	var color := _stage_color()
	if _flash > 0.0:
		color = FLASH_COLOR.lerp(color, 1.0 - _flash / FLASH_TIME)
	if _is_critical():
		var beat := absf(sin(Time.get_ticks_msec() / 1000.0 * PI * CRITICAL_BLINKS))
		color.a = CRITICAL_MIN_ALPHA + (1.0 - CRITICAL_MIN_ALPHA) * beat
	modulate = color

func _stage_color() -> Color:
	if _fraction <= CRITICAL_FRACTION:
		return CRITICAL_COLOR
	return HURT_COLOR if _fraction <= HURT_FRACTION else WHOLE_COLOR

func _is_critical() -> bool:
	return _fraction <= CRITICAL_FRACTION
