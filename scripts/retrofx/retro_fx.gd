extends Node
## Every knob of the Saturn-era render pipeline, in one place.
##
## The look is built out of four shaders that have to agree with each other —
## the world's surfaces, the colour quantisation, the CRT filter and the fog —
## and none of them can be tuned by staring at a `.tres` file. So this autoload
## holds the values, the effects read them from here, and the debug panel writes
## them while the game runs.
##
## Nothing here is stored per-player: these are calibration numbers, not
## settings. `SettingsManager` owns what the player chooses (including whether
## the CRT filter runs at all); this owns what the look *is*.

## A parameter of any effect changed. The nodes that own a material listen for
## this and push the whole block down, rather than each subscribing to its own
## signal — there are forty of these and one repaint costs nothing.
signal changed

## The rendering resolution every part of the look is tuned against. The vertex
## snap grid, the dither cell and the UI's pixel size are all derived from it,
## so they stay in step if it ever moves.
const GAME_RESOLUTION := Vector2i(480, 270)


# --- Quantisation and dithering (Section 6) ---------------------------------

## Levels per colour channel. 32 is the Saturn's 5 bits; the console could also
## run 8-bit paletted modes, which is roughly what the low end of this range
## reads as.
var levels := 32.0: set = _set_levels

## How much of the Bayer pattern is mixed into the quantisation. At zero the
## colours simply snap to the nearest level and the banding is hard-edged; at
## one the checkerboard carries the transition, which is the look. Above one it
## over-shoots into visible texture, which is occasionally what a scene wants.
var dither_strength := 1.0: set = _set_dither_strength

## Whether the quantisation runs at all.
var dither_enabled := true: set = _set_dither_enabled

## Whether the HUD passes through the quantisation with the world.
##
## Parking Garage Rally Circuit keeps its UI in the same buffer, so its text is
## dithered exactly like the track behind it, and that shared treatment is a
## good part of why the image reads as one screen rather than as sprites over a
## render. The alternative — UI above the dither, drawn in exact palette colours
## — is a legitimate look too, and this is the toggle that compares them.
var ui_dithered := true: set = _set_ui_dithered


# --- Vertex snapping (Section 8) --------------------------------------------

## How much of the vertex snap to apply, zero (smooth) to one (full grid).
##
## Full strength is a PlayStation's wobble rather than a Saturn's. The Saturn
## had the same integer vertex pipeline, but its higher transform precision and
## quad-based drawing made the crawl far subtler, so this wants to sit low.
var snap_amount := 0.35: set = _set_snap_amount


# --- Fog (Section 4) --------------------------------------------------------

var fog_enabled := true: set = _set_fog_enabled
## Distance where the fog starts taking the surface over.
var fog_start := 8.0: set = _set_fog_start
## Distance where nothing but fog is left. Draw distance ends here, which is
## the point: the era hid its geometry budget behind exactly this.
var fog_end := 34.0: set = _set_fog_end
## Fog colour. It has to match the background, or the horizon reads as a wall.
var fog_color := Color(0.16, 0.17, 0.22): set = _set_fog_color


# --- Procedural surface detail (Section 5) ----------------------------------

## Whether the stand-in surface pattern is drawn at all. Turning this off is
## what happens when real textures arrive.
var surface_detail_enabled := true: set = _set_surface_detail_enabled
## World-space size of one cell of the grid layer, in metres.
var grid_scale := 1.0: set = _set_grid_scale
var grid_strength := 0.18: set = _set_grid_strength
## World-space size of one cell of the value-noise layer, in metres.
var noise_scale := 0.5: set = _set_noise_scale
var noise_strength := 0.12: set = _set_noise_strength
## How much each of the three world axes shifts a surface's brightness, so a
## wall facing north reads differently from one facing east even in flat light.
var face_variation := 0.10: set = _set_face_variation


# --- Lighting (Section 3) ---------------------------------------------------

## Direction the sun points, as pitch and yaw in degrees.
var light_pitch := -48.0: set = _set_light_pitch
var light_yaw := -35.0: set = _set_light_yaw
var light_energy := 1.15: set = _set_light_energy
var light_color := Color(1.0, 0.96, 0.88): set = _set_light_color
## Ambient level. Well below the flat fill the scene used to run on: the whole
## point of Section 3 is that an unlit face is visibly darker than a lit one.
var ambient_energy := 0.22: set = _set_ambient_energy
var ambient_color := Color(0.42, 0.46, 0.62): set = _set_ambient_color


# --- CRT filter (Section 9) -------------------------------------------------

## Every one of these sits low on purpose.
##
## The reference look is a *sharp* image with artefacts on top: pixels stay hard
## and readable, scanlines are a faint modulation across the bright areas, and
## the colour fringe shows on HUD text and hard edges rather than over the whole
## screen. Values high enough to be obvious in a still are far too high in
## motion — the first calibration of this pipeline was unreadable for exactly
## that reason.
var crt_enabled := true: set = _set_crt_enabled
var scanline_strength := 0.08: set = _set_scanline_strength
var aberration_strength := 0.30: set = _set_aberration_strength
var bleed_strength := 0.15: set = _set_bleed_strength
var vignette_strength := 0.12: set = _set_vignette_strength
var curvature := 0.0: set = _set_curvature


## The named CRT looks, after Parking Garage Rally Circuit's own filter menu.
## A slice of every audience wants none of this, so "Off" is a first-class
## preset rather than a checkbox hidden elsewhere.
const PRESETS := {
	"off": {
		"crt_enabled": false,
		"scanline_strength": 0.0,
		"aberration_strength": 0.0,
		"bleed_strength": 0.0,
		"vignette_strength": 0.0,
		"curvature": 0.0,
	},
	"original_hardware": {
		"crt_enabled": true,
		"scanline_strength": 0.14,
		"aberration_strength": 0.45,
		"bleed_strength": 0.30,
		"vignette_strength": 0.18,
		"curvature": 0.03,
	},
	"modern_emulator": {
		"crt_enabled": true,
		"scanline_strength": 0.08,
		"aberration_strength": 0.30,
		"bleed_strength": 0.15,
		"vignette_strength": 0.10,
		"curvature": 0.0,
	},
	"modern_handheld": {
		"crt_enabled": true,
		"scanline_strength": 0.0,
		"aberration_strength": 0.0,
		"bleed_strength": 0.05,
		"vignette_strength": 0.14,
		"curvature": 0.0,
	},
	"pc_port": {
		"crt_enabled": true,
		"scanline_strength": 0.0,
		"aberration_strength": 0.12,
		"bleed_strength": 0.0,
		"vignette_strength": 0.0,
		"curvature": 0.0,
	},
}

## Which preset was applied last. Moving any CRT slider by hand clears it to an
## empty string, so the panel can show "custom" honestly.
var crt_preset := "modern_emulator"

## Set while `apply_preset` writes, so the individual setters do not each clear
## `crt_preset` and emit `changed` on the way past.
var _applying_preset := false


func _ready() -> void:
	# Nothing to load: these are calibration values compiled into the build, not
	# player settings. The defaults above are the look.
	apply_preset(crt_preset)


## Applies one of `PRESETS` by name. Unknown names are ignored rather than
## raising: the panel builds its list from the same dictionary, so a bad name
## here can only come from a typo in code.
func apply_preset(name: String) -> void:
	var preset: Dictionary = PRESETS.get(name, {})
	if preset.is_empty():
		push_warning("RetroFX: unknown CRT preset %s" % name)
		return
	_applying_preset = true
	for key in preset:
		set(key, preset[key])
	_applying_preset = false
	crt_preset = name
	changed.emit()


## The sun's direction as a basis, built from the two angles the panel exposes.
## Pitch first, then yaw, so the yaw slider swings the light around the world
## rather than around its own tilted axis.
func light_basis() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(light_pitch), deg_to_rad(light_yaw), 0.0))


func _touch() -> void:
	if not _applying_preset:
		changed.emit()


## A CRT slider moved by hand, so the look is no longer any named preset.
func _touch_crt() -> void:
	if not _applying_preset:
		crt_preset = ""
		changed.emit()


func _set_levels(value: float) -> void:
	levels = clampf(value, 2.0, 256.0)
	_touch()


func _set_dither_strength(value: float) -> void:
	dither_strength = clampf(value, 0.0, 2.0)
	_touch()


func _set_dither_enabled(value: bool) -> void:
	dither_enabled = value
	_touch()


func _set_ui_dithered(value: bool) -> void:
	ui_dithered = value
	_touch()


func _set_snap_amount(value: float) -> void:
	snap_amount = clampf(value, 0.0, 1.0)
	_touch()


func _set_fog_enabled(value: bool) -> void:
	fog_enabled = value
	_touch()


func _set_fog_start(value: float) -> void:
	fog_start = maxf(value, 0.0)
	_touch()


func _set_fog_end(value: float) -> void:
	# The shaders divide by `fog_end - fog_start`, so the two may never meet.
	fog_end = maxf(value, fog_start + 0.1)
	_touch()


func _set_fog_color(value: Color) -> void:
	fog_color = value
	_touch()


func _set_surface_detail_enabled(value: bool) -> void:
	surface_detail_enabled = value
	_touch()


func _set_grid_scale(value: float) -> void:
	grid_scale = maxf(value, 0.01)
	_touch()


func _set_grid_strength(value: float) -> void:
	grid_strength = clampf(value, 0.0, 1.0)
	_touch()


func _set_noise_scale(value: float) -> void:
	noise_scale = maxf(value, 0.01)
	_touch()


func _set_noise_strength(value: float) -> void:
	noise_strength = clampf(value, 0.0, 1.0)
	_touch()


func _set_face_variation(value: float) -> void:
	face_variation = clampf(value, 0.0, 1.0)
	_touch()


func _set_light_pitch(value: float) -> void:
	light_pitch = clampf(value, -89.0, 89.0)
	_touch()


func _set_light_yaw(value: float) -> void:
	light_yaw = value
	_touch()


func _set_light_energy(value: float) -> void:
	light_energy = maxf(value, 0.0)
	_touch()


func _set_light_color(value: Color) -> void:
	light_color = value
	_touch()


func _set_ambient_energy(value: float) -> void:
	ambient_energy = maxf(value, 0.0)
	_touch()


func _set_ambient_color(value: Color) -> void:
	ambient_color = value
	_touch()


func _set_crt_enabled(value: bool) -> void:
	crt_enabled = value
	_touch_crt()


func _set_scanline_strength(value: float) -> void:
	scanline_strength = clampf(value, 0.0, 1.0)
	_touch_crt()



func _set_aberration_strength(value: float) -> void:
	aberration_strength = clampf(value, 0.0, 1.0)
	_touch_crt()


func _set_bleed_strength(value: float) -> void:
	bleed_strength = clampf(value, 0.0, 1.0)
	_touch_crt()


func _set_vignette_strength(value: float) -> void:
	vignette_strength = clampf(value, 0.0, 1.0)
	_touch_crt()


func _set_curvature(value: float) -> void:
	curvature = clampf(value, 0.0, 0.5)
	_touch_crt()
