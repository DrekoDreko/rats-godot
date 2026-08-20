class_name StoreItem
extends Resource
## A line on the computer's catalogue: what is for sale, what it costs and how
## many units the money buys.
##
## Each item is a file in `resources/store/`. A new thing on the shelf means
## duplicating one of those and changing the numbers — no code. The shop reads
## the catalogue off the computer node (`scripts/shop/shop_computer.gd`), and the
## weapon that spends the item finds it by the same `id`
## (`scripts/weapons/trap_weapon.gd`).

## The key the stock is kept under. It has to match the weapon's `stock_id`.
@export var id := ""
## What the catalogue calls it.
@export var display_name := "Item"
## The line under the name, on the shop screen.
@export var description := ""
## The picture on the shelf. Without one the shop shows only the name, the same
## way the hotbar does.
@export var icon: Texture2D

@export_group("Price")
## What one purchase costs.
@export var price := 25
## How many units one purchase credits to the stock.
@export var amount := 3
