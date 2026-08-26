extends Node
## The safety net: what happens when the wire goes down in the middle of a shift.
##
## Everything about a disconnect that each machine can handle on its own — the
## avatar disappearing, the colour going back on the rack, the ready flags being
## counted again — is already handled by the nodes that own those things
## (`JoinGate`, `ColorManager`, `ReadyManager`, `PlayerAvatars`). What none of
## them does is the one thing that only matters to a **client who has lost his
## host**: getting out of the scene he is stranded in and back to the lobby
## screen where he can start again.
##
## That is the whole of this file. It listens for the two roads that end in "we
## are no longer in a game" — `server_disconnected` (the host's peer dropped off
## the wire) and `lobby_left` (the lobby itself fell apart, or we walked out of
## it) — and when either one fires while we are standing somewhere that is not
## the lobby screen, it wipes the shift clean and sends us home.
##
## **It fires once.** Both signals can arrive in the same breath — and do, when
## `LobbyManager._fail_and_leave` is the thing that calls `leave_lobby` in
## response to the server going down — so a guard (`_returning`) keeps the scene
## change from running twice, which would be two frames of loading for the same
## door.
##
## **The reason travels with the redirect.** Whatever the lobby manager said on
## its way out — "The host left the lobby.", "Could not reach the host." — is
## kept in `pending_reason` so that the lobby screen can pick it up and put it
## on its status line the moment it opens. It is cleared after being read, so a
## player who walks into a second lobby does not see yesterday's complaint.

## The host went down while we were in a shift. Anybody who wants to know that
## it happened — a HUD that needs to show a message, a pause menu that needs to
## unlock the cursor — listens here.
signal host_disconnected(reason: String)

## The sentence the lobby screen should show when it opens after a redirect. Set
## by this node on the way out, read and cleared by `lobby_screen.gd` on the
## way in. Empty when nobody was sent home.
var pending_reason := ""

## The scene the game starts on, and the one a stranded client is sent back to.
## The same path `LobbyManager` already uses for the van; this one is the lobby
## *screen*, which is one step before it.
const LOBBY_SCENE := "res://scenes/menu.tscn"

## Whether a return is already in flight. Guards against the two signals both
## firing in the same frame and loading the lobby screen twice.
var _returning := false


func _ready() -> void:
	# A disconnect can arrive while the game is paused — a pause menu is not a
	# hiding place from the wire going down — so the packet still has to land.
	# Every other session autoload is set the same way, for the same reason.
	process_mode = Node.PROCESS_MODE_ALWAYS

	multiplayer.server_disconnected.connect(_on_server_disconnected)
	LobbyManager.lobby_left.connect(_on_lobby_left)
	LobbyManager.lobby_failed.connect(_on_lobby_failed)


## The host's peer dropped off the wire. A client receiving this is a client
## whose game has just ended — there is no migration to fall back on and no
## second host to hand the van to. The honest answer is to say so and go home.
func _on_server_disconnected() -> void:
	_return_to_lobby("The host left the lobby.")


## We walked out of the lobby, or Steam said it fell apart. If we are somewhere
## that is not already the lobby screen, we need to get there — a man standing in
## the house with no lobby under him has no crew, no timer and no way forward.
func _on_lobby_left() -> void:
	# Only act when we are not already on the lobby screen.  `lobby_left` fires
	# for the normal "Leave" button on the lobby screen itself, and that is not
	# a redirect — it is a button that keeps us where we already are.
	_return_to_lobby("")


## A lobby operation failed.  If it carries the sentence that explains the
## disconnect, keep it — the redirect has already been triggered by one of the
## two signals above, and the reason is what the lobby screen will show.
func _on_lobby_failed(reason: String) -> void:
	if not reason.is_empty():
		pending_reason = reason


## Wipes the shift and sends us to the lobby screen. Safe to call twice — the
## second call is dropped.
func _return_to_lobby(reason: String) -> void:
	if _returning:
		return

	# Whether we have to load anything, as against merely having to clean up.
	# The scene path is checked rather than a flag, because a flag would have to
	# be set and cleared by the menu itself, and a screen that has to know about
	# this file is a screen with a dependency it does not need.
	#
	# Being already on the menu used to mean there was nothing to do at all. It
	# does not any more: the menu *is* the lobby phase now, so this is where a
	# client is standing when the host drops, and the crew he was standing with
	# still has to be wiped. Returning early here left him looking at bodies for
	# players who were no longer on any wire.
	var current_scene := get_tree().current_scene
	var already_there := current_scene != null \
		and current_scene.scene_file_path == LOBBY_SCENE

	_returning = true

	if not reason.is_empty():
		pending_reason = reason

	# Wipe the shift. The crew, the contract, the phase — all of it belongs to
	# the game that just ended, and a lobby that opens with any of it still
	# standing would be a lobby full of ghosts.
	SessionManager.reset()
	Wallet.reset()
	Stock.reset()
	MapManager.clear_all_pins()
	ReadyManager.blocked = false
	JoinGate.admitted = false

	host_disconnected.emit(reason)

	# Reloading the menu we are already on would throw away a screen that is
	# perfectly good and make the crew flicker; it listens to the same autoloads
	# this just cleared and has already redrawn itself off them.
	if not already_there:
		get_tree().change_scene_to_file(LOBBY_SCENE)

	# One frame of patience, so that the scene is standing before the guard is
	# lowered — a signal that fires in the same frame as the change would find
	# the guard still up and be correctly dropped.
	await get_tree().process_frame
	_returning = false
