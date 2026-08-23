class_name StoreItem
extends Resource
## A line on the computer's catalogue: what is for sale, what it costs and how
## many units the money buys.
##
## Each item is a file in `resources/store/`. A new thing on the shelf means
## duplicating one of those and changing the numbers — no code. The shop reads
## the catalogue off the shelf node (`scripts/shop/shop_shelf.gd`), and the
## weapon that spends the item finds it by the same `id`
## (`scripts/weapons/trap_weapon.gd`).
##
## **What it does not carry is any rule.** The `kind` below says what shape of
## thing this is — one hand, two hands, a trap, a bait, a patch — and it is read
## by whoever has a rule about that shape: the hand manager, which will not let
## a two-handed thing out while the torch is up, and the survey phase, which
## bars the ones that kill. A resource that decided any of that itself would be
## a rule written once per `.tres` on disk instead of once in code.

## The key the stock is kept under. It has to match the weapon's `stock_id`.
@export var id := ""
## What the catalogue calls it.
@export var display_name := "Item"
## The line under the name, on the shop screen.
@export var description := ""
## The picture on the shelf. Without one the shop shows only the name, the same
## way the hotbar does.
@export var icon: Texture2D

## What shape of thing this is. It is the whole of what the hand rules read: a
## `TWO_HANDS` item is what takes the torch out of the left hand, and everything
## from `TRAP` down is what stays allowed during the survey, when the weapons
## that kill are barred.
##
## It is deliberately not a guess made from the id or from the scene — a bat and
## a shock stick are both sticks, and only one of them needs two hands.
enum Kind {
	ONE_HAND, ## Swung or fired in one hand, with the torch still up in the other.
	TWO_HANDS, ## Wants both, and the torch goes away while it is out.
	TRAP, ## Set down on the floor and left working while the player walks off.
	BAIT, ## Put down to bring the rats somewhere rather than to hurt them.
	PATCH, ## Nailed over a hole to shut a route rather than to catch anything.
}

## Which of the five this is. See `Kind`.
@export var kind: Kind = Kind.ONE_HAND

## What the player holds once he has bought it: the node on his head that this
## item fills. Empty on an item that is not carried at all.
##
## It is a path into the player scene and not a `PackedScene`, because every
## weapon in the game is already dressed under the head with its own reach,
## recoil and capture point (`scripts/weapons/weapon.gd`) — buying one is
## unlocking the loop of the belt it hangs from, not building it.
@export var weapon_node := ""

@export_group("Price")
## What one purchase costs.
@export var price := 25
## How many units one purchase credits to the stock.
@export var amount := 3
