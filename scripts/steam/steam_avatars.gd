extends Node
## The players' Steam pictures, fetched once and kept.
##
## Steam does not hand a picture over on request: `getMediumFriendAvatar` either
## returns a handle it already had in memory, or returns zero and goes looking —
## and the answer arrives later, on a callback, for a player who may by then have
## left the lobby. That shape is the same one `LobbyManager` already deals with
## for names that come back as "[unknown]" until `persona_state_change` fires, so
## this file follows it: ask, draw what you have, and repaint when the rest lands.
##
## **Nothing here is required for the game to run.** A picture that never arrives
## leaves a grey square where a face would be, which is a screen a player can
## still use. Steam being shut, a local-wire session with made-up account numbers,
## a solo run with no account at all — all three are ordinary states in
## development, and all three get the placeholder rather than an error.
##
## The cache lives as long as the lobby does. Faces are small, there are at most
## four of them, and a picture that is already in memory is worth more than the
## bytes it costs — but a lobby left is a crew gone, so that is where it empties.

## A picture is ready to be drawn. Carries the texture so that a listener which
## asked for one player is not made to look it up again, and is emitted for a
## request that was already in cache too, so that `request` has one answer and
## not two.
signal avatar_ready(steam_id: int, texture: ImageTexture)

## Which of Steam's three sizes we ask for. 64x64 is the one the cards want: the
## small one (32) is soft at the size it is drawn, and the large one (184) is
## four times the memory for a picture nothing shows that big.
const SIZE := Steam.AVATAR_MEDIUM

## The side of the placeholder, in pixels — the same 64 the medium avatar is, so
## that a face arriving later does not resize the box it lands in.
const PLACEHOLDER_SIZE := 64

## The grey a player without a picture is drawn in. Dark enough to read as an
## empty frame rather than as a photograph that failed to load.
const PLACEHOLDER_COLOR := Color(0.18, 0.18, 0.2, 1.0)

## The pictures we have, by account. Emptied when the lobby is left.
var _cache: Dictionary[int, ImageTexture] = {}

## Who we are still waiting on, so that a second ask while Steam is fetching does
## not send a second request — and so that a callback for somebody nobody asked
## about is dropped rather than cached.
var _waiting: Dictionary[int, bool] = {}

## The grey square, built once and shared. Every caller gets the same texture,
## which is safe because nothing ever writes to it.
var _placeholder: ImageTexture = null


func _ready() -> void:
	# A face can land while the tree is paused — the pause menu draws the crew,
	# and a player looking at it is exactly the one waiting to see who is here.
	# Same reason `SteamManager` keeps its callbacks running.
	process_mode = Node.PROCESS_MODE_ALWAYS

	if SteamManager.is_online:
		Steam.avatar_loaded.connect(_on_avatar_loaded)

	# The crew is gone; so are its faces. Nothing else clears this, on purpose:
	# a player who leaves and comes back inside one lobby keeps his picture.
	LobbyManager.lobby_left.connect(_forget_everything)


## The picture for an account, or the grey square while there is not one. Never
## null, so that whoever is drawing a face never has to check first — and calling
## it is enough to start the fetch, so a caller that only draws once still ends
## up with a face by way of `avatar_ready`.
func texture_of(steam_id: int) -> ImageTexture:
	if _cache.has(steam_id):
		return _cache[steam_id]
	request(steam_id)
	return placeholder()


## Asks Steam for an account's picture. Answers on `avatar_ready`, immediately
## for one already in hand and whenever Steam gets round to it for one that is
## not. Cheap to call again with the same account.
func request(steam_id: int) -> void:
	if _cache.has(steam_id):
		avatar_ready.emit(steam_id, _cache[steam_id])
		return
	if _waiting.has(steam_id):
		return
	if not _has_a_picture(steam_id):
		return

	# Zero means Steam has not got it yet and has gone to fetch it; anything else
	# is a handle to a picture already in memory. Both are normal.
	var handle := Steam.getMediumFriendAvatar(steam_id)
	if handle > 0:
		_keep(steam_id, _texture_from_handle(handle))
		return
	_waiting[steam_id] = true


## The grey square shown in place of a face. Built on first use rather than at
## `_ready`, so that a session which never draws a card never builds it.
func placeholder() -> ImageTexture:
	if _placeholder == null:
		var image := Image.create_empty(
			PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, false, Image.FORMAT_RGBA8)
		image.fill(PLACEHOLDER_COLOR)
		_placeholder = ImageTexture.create_from_image(image)
	return _placeholder


## Whether we have a picture for an account already, without asking for one. What
## a card checks before deciding it needs to listen for `avatar_ready`.
func has(steam_id: int) -> bool:
	return _cache.has(steam_id)

# --- What Steam says back ---------------------------------------------------

## Steam finished fetching a picture. It arrives for every account the client is
## watching, not only the ones we asked about, so anybody not on the waiting list
## is dropped — the callback is Valve's and its guest list is wider than ours.
func _on_avatar_loaded(user_id: int, avatar_size: int, buffer: PackedByteArray) -> void:
	if not _waiting.has(user_id):
		return
	_waiting.erase(user_id)
	if buffer.is_empty() or avatar_size <= 0:
		return
	_keep(user_id, _texture_from_buffer(avatar_size, avatar_size, buffer))

# --- Turning Steam's bytes into something drawable --------------------------

## The picture behind a handle. Steam hands back raw RGBA and the size separately,
## which is everything `Image` needs.
func _texture_from_handle(handle: int) -> ImageTexture:
	var size: Dictionary = Steam.getImageSize(handle)
	var width := int(size.get("width", 0))
	var height := int(size.get("height", 0))
	if width <= 0 or height <= 0:
		return null
	var pixels: Dictionary = Steam.getImageRGBA(handle)
	var buffer: PackedByteArray = pixels.get("buffer", PackedByteArray())
	return _texture_from_buffer(width, height, buffer)


## Raw RGBA into a texture, or null for a buffer that is not the size it claims.
## The length check is not paranoia: `Image.create_from_data` on a short buffer
## brings the process down rather than failing, and a picture is not worth that.
func _texture_from_buffer(width: int, height: int, buffer: PackedByteArray) -> ImageTexture:
	if width <= 0 or height <= 0:
		return null
	if buffer.size() < width * height * 4:
		return null
	var image := Image.create_from_data(
		width, height, false, Image.FORMAT_RGBA8, buffer)
	return ImageTexture.create_from_image(image)


## Files a picture and tells whoever was waiting. A null texture — a buffer that
## did not add up — is filed as nothing, so that the next ask tries again rather
## than handing back a broken face forever.
func _keep(steam_id: int, texture: ImageTexture) -> void:
	if texture == null:
		return
	_cache[steam_id] = texture
	avatar_ready.emit(steam_id, texture)


## Whether an account can have a picture at all. Three cannot, and each one is a
## state the game is meant to run in:
##
## - Steam shut, so there is nobody to ask.
## - The local wire (`--host` / `--join`), whose account numbers are invented in
##   `LobbyManager._local_steam_id` and belong to nobody.
## - A solo run with Steam shut, filed under `SOLO_STEAM_ID`.
##
## Asking Steam about any of them is a request that can only fail, so it is not
## made and the placeholder stands in.
func _has_a_picture(steam_id: int) -> bool:
	if not SteamManager.is_online:
		return false
	if steam_id <= 0 or steam_id == LobbyManager.SOLO_STEAM_ID:
		return false
	if LobbyManager.is_local:
		return false
	return true


## The crew is gone. Faces go with it — the next lobby is a different four people
## and a cache that outlives its lobby is a cache nobody empties.
func _forget_everything() -> void:
	_cache.clear()
	_waiting.clear()
