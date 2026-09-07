extends Control
## The settings screen: fullscreen, the three volume sliders, Streamer Mode
## and the language switch — one popup, instanced identically into the pause
## menu and the main menu, the same way `lobby.tscn` is instanced into
## `menu.tscn` as `LobbyModal`.
##
## It holds no state of its own. Every control reads its starting value off
## `SettingsManager` in `_ready()` and writes straight back to it on change —
## the same "the autoload owns it, the screen only draws it" split every
## other panel in this game already uses.
##
## Closing it is just `hide()`. Unlike the lobby browser it has no side effect
## a parent needs to react to, so there is no `close_requested` signal to wire
## up on either host.

const LANGUAGES := [
	{"code": "en", "label": "English"},
	{"code": "pt_BR", "label": "Português (BR)"},
]

@onready var _close: Button = $Center/Panel/Margin/Rows/TitleRow/Close
@onready var _fullscreen: CheckButton = $Center/Panel/Margin/Rows/FullscreenRow/Fullscreen
@onready var _sound: HSlider = $Center/Panel/Margin/Rows/SoundRow/Sound
@onready var _music: HSlider = $Center/Panel/Margin/Rows/MusicRow/Music
@onready var _voice: HSlider = $Center/Panel/Margin/Rows/VoiceRow/Voice
@onready var _streamer: CheckButton = $Center/Panel/Margin/Rows/StreamerRow/Streamer
@onready var _language: OptionButton = $Center/Panel/Margin/Rows/LanguageRow/Language


func _ready() -> void:
	_close.pressed.connect(hide)

	_fullscreen.button_pressed = SettingsManager.fullscreen
	_sound.value = SettingsManager.sfx_volume
	_music.value = SettingsManager.music_volume
	_voice.value = SettingsManager.voice_volume
	_streamer.button_pressed = SettingsManager.streamer_mode

	for entry in LANGUAGES:
		_language.add_item(entry["label"])
	_language.selected = _index_of_language(SettingsManager.language)

	_fullscreen.toggled.connect(SettingsManager.set_fullscreen)
	_sound.value_changed.connect(SettingsManager.set_sfx_volume)
	_music.value_changed.connect(SettingsManager.set_music_volume)
	_voice.value_changed.connect(SettingsManager.set_voice_volume)
	_streamer.toggled.connect(SettingsManager.set_streamer_mode)
	_language.item_selected.connect(_on_language_selected)


func _index_of_language(code: String) -> int:
	for i in LANGUAGES.size():
		if LANGUAGES[i]["code"] == code:
			return i
	return 0


func _on_language_selected(index: int) -> void:
	SettingsManager.set_language(LANGUAGES[index]["code"])
