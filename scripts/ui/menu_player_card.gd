class_name MenuPlayerCard
extends VBoxContainer
## The label over a man's head on the menu: his Steam picture, his name and
## whether he is ready.
##
## It is dressed in `menu_player_card.tscn` and instanced per player by
## `menu_screen.gd`: the font, the sizes and the colours are the scene's to set,
## and this file only writes what changes while the screen is up.
##
## It draws and it decides nothing. The picture comes from `SteamAvatars` and
## the ready flag from `SessionManager`. A colour is picked at the terminal in
## the van (`ColorScreen`), not here.

var _steam_id := 0

@onready var _photo: TextureRect = $PortraitFrame/Photo
@onready var _name: BigFontOutlinedLabel = $Name


## Fills the card in for a player. Called by the screen straight after the
## instance is in the tree — `setup` and not `_ready` because the account has to
## be known before anything can be drawn, and a node cannot be handed an
## argument on the way in.
func setup(steam_id: int, player_name: String) -> void:
    _steam_id = steam_id
    _name.text = player_name
    _photo.texture = SteamAvatars.texture_of(steam_id)
    refresh()


## Redraws what may have changed since the last look: whether the man has said
## he is ready. The picture and the name arrive on their own signals and are
## written by the two setters below.
func refresh() -> void:
    if not is_node_ready():
        return

    if ReadyManager.is_ready(_steam_id):
        _name.modulate = Color.GREEN


## A name that arrived late — Steam answering `requestUserInformation` after the
## row was already drawn, which `LobbyManager` documents as the usual case.
func set_player_name(player_name: String) -> void:
    if is_node_ready() and _name.text != player_name:
        _name.text = player_name


## A picture that arrived late, which is every picture that was not already in
## Steam's memory when it was asked for.
func set_photo(texture: ImageTexture) -> void:
    if is_node_ready() and texture != null:
        _photo.texture = texture
