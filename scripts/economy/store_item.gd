class_name StoreItem
extends Resource
## A line on the computer's catalogue: what is for sale, what it costs and how
## many units the money buys.
##
## Each item is a file in `resources/store/`. A new thing on the shelf means
## duplicating one of those and changing the numbers — no code. The shop reads
## the catalogue off `ShopManager`, which scans that folder, and the
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

@export_group("Preview")
## The model the shop stands in the man's hand while this item is selected, and
## nothing else. It is a scene of its own rather than the one the weapon carries
## because those live in two different places and neither is reusable here: a
## trap's model hangs inside a whole `Area3D` with its collision and its
## interaction handle on it, and a club's is dressed under the arms of the view
## model, which the shop's preview does not have.
##
## Empty is an item the shop shows empty-handed. That is the honest state of an
## item nobody has modelled yet, and it is what keeps a new `.tres` from needing
## art before it can go on the rack.
@export var preview_model: PackedScene
## Where that model sits beside his hand, in metres, on axes that are square to
## the world rather than to the wrist: `+X` is off to the man's right as the
## shopper sees him, `+Y` is up and `+Z` is out towards the shopper. The shop
## squares them itself (`StoreScreen._build_preview_hand`) so that these numbers
## mean the same thing in every frame of the idle he stands in.
@export var preview_offset := Vector3.ZERO
## How that model is turned before it is put there, in degrees. It is only ever
## the model's own quirk being corrected — which way its exporter called up.
@export var preview_rotation := Vector3.ZERO
## **How big it should read, in metres along its longest side** — not a
## multiplier. The shop measures the model and scales it to this, because a
## scale of 1 means one thing on a model authored in metres and quite another on
## one authored in centimetres, and the five in this folder are not agreed. What
## a person setting this up actually knows is how big the thing should look in a
## man's hand, so that is what is written.
@export var preview_height := 0.4

@export_group("Price")
## What one purchase costs.
@export var price := 25
## How many units one purchase credits to the stock.
@export var amount := 3
