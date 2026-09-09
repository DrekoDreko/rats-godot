extends Node
## Every player-facing setting: fullscreen, the three volume buses, the PS1
## post-process effect, streamer mode and the game's language. One autoload owns
## it is the same shape — a value, a place it applies to, and a line in
## `user://settings.cfg` — and a screen only ever needs to read the current
## value or ask for a new one.
##
## Applied immediately on every setter, not batched behind a "confirm"
## button: a fullscreen toggle or a volume slider is expected to take effect
## the moment it moves, the same way it does in any other game's settings
## screen.

const SETTINGS_PATH := "user://settings.cfg"

const BUS_SFX := "SFX"
const BUS_MUSIC := "Music"
const BUS_VOICE := "Voice"

const DEFAULT_LANGUAGE := "en"

## Streamer mode changed. Screens that show a Steam name or a lobby ID and
## are not already on a refresh loop of their own listen for this to redraw.
signal streamer_mode_changed(enabled: bool)
signal ps1_post_process_changed

## The game opens in a window, and stays in one until the player asks for
## anything else on the settings screen. A window is the mode you can get out
## of: a first run that seizes the whole screen at 640x360 on a monitor that
## does not want it is a first run with nowhere to click. The choice is saved
## either way (`user://settings.cfg`), so this default is only ever read once,
## on a machine that has not answered yet.
var fullscreen := false
var sfx_volume := 1.0
var music_volume := 1.0
var voice_volume := 1.0
var ps1_post_process_enabled := true
var streamer_mode := false
var language := DEFAULT_LANGUAGE


func _ready() -> void:
	_load()
	_apply_all()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	_apply_fullscreen()
	_save()


func set_sfx_volume(linear: float) -> void:
	sfx_volume = clampf(linear, 0.0, 1.0)
	_apply_bus_volume(BUS_SFX, sfx_volume)
	_save()


func set_music_volume(linear: float) -> void:
	music_volume = clampf(linear, 0.0, 1.0)
	_apply_bus_volume(BUS_MUSIC, music_volume)
	_save()


func set_voice_volume(linear: float) -> void:
	voice_volume = clampf(linear, 0.0, 1.0)
	_apply_bus_volume(BUS_VOICE, voice_volume)
	_save()


func set_streamer_mode(enabled: bool) -> void:
	if streamer_mode == enabled:
		return
	streamer_mode = enabled
	_save()
	streamer_mode_changed.emit(enabled)


func set_ps1_post_process_enabled(enabled: bool) -> void:
	if ps1_post_process_enabled == enabled:
		return
	ps1_post_process_enabled = enabled
	_save()
	ps1_post_process_changed.emit()


func set_language(code: String) -> void:
	language = code
	TranslationServer.set_locale(language)
	_save()

# --- Loading, saving, applying -----------------------------------------------

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	fullscreen = config.get_value("video", "fullscreen", fullscreen)
	sfx_volume = config.get_value("audio", "sfx_volume", sfx_volume)
	music_volume = config.get_value("audio", "music_volume", music_volume)
	voice_volume = config.get_value("audio", "voice_volume", voice_volume)
	ps1_post_process_enabled = config.get_value(
		"video", "ps1_post_process_enabled", ps1_post_process_enabled
	)
	streamer_mode = config.get_value("privacy", "streamer_mode", streamer_mode)
	language = config.get_value("locale", "language", language)


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "voice_volume", voice_volume)
	config.set_value("video", "ps1_post_process_enabled", ps1_post_process_enabled)
	config.set_value("privacy", "streamer_mode", streamer_mode)
	config.set_value("locale", "language", language)
	config.save(SETTINGS_PATH)


func _apply_all() -> void:
	_apply_fullscreen()
	_apply_bus_volume(BUS_SFX, sfx_volume)
	_apply_bus_volume(BUS_MUSIC, music_volume)
	_apply_bus_volume(BUS_VOICE, voice_volume)
	TranslationServer.set_locale(language)


func _apply_fullscreen() -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	)


func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index < 0:
		return
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear))
