extends Interactable
## The computer in the back of the van: the one place in the game where the
## money earned on the hunt turns into something to hunt with.
##
## The machine does not sell anything by itself. It carries the catalogue — the
## `StoreItem` files it has on the shelf — and announces that somebody sat in
## front of it; the screen that opens is on the HUD (`scripts/hud_shop.gd`),
## which finds this node by the group and reads the catalogue off it. The van can
## be moved, the desk can be redressed, and the shop on screen does not notice.
##
## The group is what keeps the two apart: the HUD looks for `shop_computer` the
## same way every other piece of it looks for `player`.

## What is on the shelf, in the order it shows up on screen.
@export var catalogue: Array[StoreItem] = []

func _ready() -> void:
	add_to_group("shop_computer")
