extends Node
## The game's only door to Steam: it brings the Steamworks API up at boot and
## keeps its callbacks flowing for the rest of the session.
##
## Steam is optional here, and on purpose. The game has to open the same way
## when it is launched from the client, from the editor with the client closed,
## or on a machine that has never heard of Steam — so nothing in this file is
## fatal: an initialization that fails becomes a logged warning and `is_online`
## staying false. Whoever asks something of Steam asks it here and gets an
## honest answer when it is not there (see `get_persona_name`).
##
## The Steamworks API does not push anything by itself: `run_callbacks()` in
## `_process` is what makes the answers to any request (achievements, overlay,
## lobbies) arrive. That is why this node keeps processing even with the tree
## paused — a callback that lands during the shop screen still has to be read.

## Steam answered and the session belongs to a real account. Whoever might
## arrive after this has been emitted should check `is_online` instead.
signal steam_ready(steam_id: int, persona_name: String)
## Steam did not answer, and the game carries on without it. `reason` is
## Steamworks' own text ("Steam client not running", and the like).
signal steam_unavailable(reason: String)

## Valve's Spacewar, the app ID everyone borrows for testing until the game has
## one of its own. When RATS gets its ID on Steam, this number and the one in
## `steam_appid.txt` at the project root are the two places to change — the file
## is what the client reads when the game is started outside of it, and this
## constant is what gets handed to `steamInitEx()` when the file is not there.
const APP_ID := 480

## The name `get_persona_name()` answers with when there is no Steam. It exists
## so that a screen showing the player's name never has to check a flag first.
const OFFLINE_PERSONA_NAME := "Player"

## Whether the Steamworks API came up. False in offline/dev mode, and the only
## thing anyone needs to look at before asking Steam for something.
var is_online := false

## The account's SteamID64, read once at boot: it does not change during a
## session. Zero while offline (see `get_steam_id`).
var _steam_id := 0


func _ready() -> void:
	# Callbacks have to keep arriving with the tree paused, and there is nothing
	# to process until Steam is actually up.
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_initialize()


func _process(_delta: float) -> void:
	Steam.run_callbacks()


## The account's SteamID64, or zero with no Steam.
func get_steam_id() -> int:
	return _steam_id


## The account's Steam name. Asked fresh every time because the player can
## rename themselves mid-session; `OFFLINE_PERSONA_NAME` with no Steam.
func get_persona_name() -> String:
	if not is_online:
		return OFFLINE_PERSONA_NAME
	return Steam.getPersonaName()


## Brings the API up. The app ID goes in as an argument so that it works even
## without `steam_appid.txt` next to the executable — Steamworks only needs to
## learn the number from one of the two.
func _initialize() -> void:
	var response: Dictionary = Steam.steamInitEx(APP_ID)
	var status: int = response.get("status", Steam.STEAM_API_INIT_RESULT_FAILED_GENERIC)
	if status != Steam.STEAM_API_INIT_RESULT_OK:
		_stay_offline(status, str(response.get("verbal", "no answer from Steamworks")))
		return

	is_online = true
	_steam_id = Steam.getSteamID()
	set_process(true)

	var persona := get_persona_name()
	print("Steam ready — %s (SteamID %d), app ID %d" % [persona, _steam_id, APP_ID])
	steam_ready.emit(_steam_id, persona)


## The failure path, which is a normal path: the client closed during
## development lands here every time. It says what went wrong and gets out of
## the way — a client that is not running is a warning, anything else is an
## error worth looking at, and neither one stops the game.
func _stay_offline(status: int, reason: String) -> void:
	is_online = false
	_steam_id = 0
	set_process(false)

	# Steamworks' own text already ends in a period; trimming it keeps the log
	# line from reading "... not running.. Running in offline mode."
	var message := "Steam unavailable (%s): %s. Running in offline mode." % [
		_status_name(status), reason.strip_edges().trim_suffix("."),
	]
	if status == Steam.STEAM_API_INIT_RESULT_NO_STEAM_CLIENT:
		push_warning(message)
	else:
		push_error(message)
	steam_unavailable.emit(reason)


## Reads a `SteamAPIInitResult` back as something a person can read in a log.
func _status_name(status: int) -> String:
	match status:
		Steam.STEAM_API_INIT_RESULT_NO_STEAM_CLIENT:
			return "client not running"
		Steam.STEAM_API_INIT_RESULT_VERSION_MISMATCH:
			return "client out of date"
		_:
			return "generic failure"
