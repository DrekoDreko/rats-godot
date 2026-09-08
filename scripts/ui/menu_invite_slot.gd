class_name MenuInviteSlot
extends VBoxContainer
## The `+` floating over an empty seat on the menu: press it and Steam's own
## friends window opens with an invite to this lobby already loaded.
##
## It is the empty half of `menu_player_card.gd`, and deliberately the same shape
## and size — the two hang over the same row of seats, so a slot that sat at a
## different height or width would make the row look broken rather than partly
## filled. `menu_screen.gd` instances one per empty seat and pins it exactly the
## way it pins a card.
##
## **It decides nothing.** Pressing it says so and no more; `LobbyManager`
## is what opens the overlay and what refuses when there is no Steam to open it
## with. The only judgement here is whether the button can be pressed at all, and
## that is read fresh on every refresh rather than remembered — a lobby can go
## away under a slot that is already on screen.

## The `+` was pressed. `menu_screen.gd` is what turns it into an invite.
signal invite_pressed()

@onready var _invite: Button = $Invite


func _ready() -> void:
	_invite.pressed.connect(func() -> void: invite_pressed.emit())
	refresh()


## Whether there is anybody to invite to. Steam has to be up — the overlay is
## Valve's window and there is nothing to open without it — and there has to be a
## real Steam lobby, which the local `--host` wire is not.
##
## A slot that cannot be pressed is greyed rather than hidden. The empty seat is
## still empty and still worth showing as a gap in the row; what has gone is only
## the ability to do anything about it, and hiding the slot would read as a van
## that seats two.
func refresh() -> void:
	if not is_node_ready():
		return
	_invite.disabled = not SteamManager.is_online \
		or LobbyManager.lobby_id == 0 \
		or LobbyManager.is_local
