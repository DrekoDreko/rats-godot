extends HBoxContainer
## The belt on screen: three squares at the foot of the screen, in the shape
## everybody already knows from Minecraft — a dark cell each, and a bright frame
## around whichever one is in hand.
##
## It only mirrors the player's `Inventory`. A slot with a weapon in it shows
## that weapon's icon, or its name while no art has arrived for it yet; an empty
## slot is an empty square, which is the whole of what it has to say — there is
## no number under it, and no dash inside it.
##
## A weapon that comes out of a box (`scripts/weapons/trap_weapon.gd`) also
## carries how many are left, in the corner of its square. That number is not the
## same thing as an empty slot: the loop on the belt has something hanging from
## it, the box is just empty, and the square goes dim to say so.
##
## The two frames are built here instead of being dressed in `world.tscn`
## because they are a pair: the picked one has to grow *outwards*
## (`expand_margin`) by exactly what its border gained, or whatever sits inside
## the square would shift a pixel every time the player swapped slots.

## The cell: dark and see-through, the way it has to sit over any scene.
const SLOT_COLOR := Color(0, 0, 0, 0.55)
## The edge of a cell waiting its turn, and of the one in hand.
const BORDER_COLOR := Color(0.55, 0.55, 0.55, 0.75)
const PICKED_BORDER_COLOR := Color(1, 1, 1, 1)
const BORDER := 1
const PICKED_BORDER := 2
## How faded a square whose box has run out looks.
const EMPTY_ALPHA := 0.4

## The cells, in the order they sit on the belt.
@onready var _slots: Array[PanelContainer] = _gather_slots()

var _normal: StyleBoxFlat
var _picked: StyleBoxFlat
## The belt being mirrored. Null until the player is found.
var _inventory: Inventory

func _ready() -> void:
	_build_frames()
	# Wait one frame so the player is already in the tree.
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	player.weapon_changed.connect(_on_weapon_changed)
	player.capture_started.connect(_on_capture_started)
	player.capture_finished.connect(_on_capture_finished)
	# The counts change without anybody swapping slots: buying at the computer
	# fills a box, and using one empties it.
	_inventory = player.inventory
	Stock.changed.connect(_on_stock_changed)
	# The belt equipped its first slot before anyone could be listening, so the
	# starting state is read straight from it instead of waited for.
	_fill(_inventory)
	_highlight(_inventory.index())

func _build_frames() -> void:
	_normal = StyleBoxFlat.new()
	_normal.bg_color = SLOT_COLOR
	_normal.border_color = BORDER_COLOR
	_normal.set_border_width_all(BORDER)
	_picked = _normal.duplicate()
	_picked.border_color = PICKED_BORDER_COLOR
	_picked.set_border_width_all(PICKED_BORDER)
	# What the thicker border took from the inside, the expansion gives back
	# from the outside: the square keeps the same room in it either way.
	_picked.set_expand_margin_all(PICKED_BORDER - BORDER)

## Puts in each square what its slot is carrying, once.
func _fill(inventory: Inventory) -> void:
	for i in _slots.size():
		var slot := _slots[i]
		if i >= inventory.slot_count():
			slot.hide()
			continue
		var weapon := inventory.weapon_in(i)
		var icon: TextureRect = slot.get_node("Icon")
		var label: Label = slot.get_node("Name")
		var count: Label = slot.get_node("Count")
		icon.texture = null if weapon == null else weapon.icon
		icon.visible = icon.texture != null
		# No picture for this weapon yet: its name stands in for one. An empty
		# slot gets neither — being an empty square is what it has to say.
		label.text = "" if weapon == null else weapon.display_name
		label.visible = weapon != null and icon.texture == null
		_fill_count(count, weapon)
		# A box with nothing left is still a weapon on the belt, only there is
		# none of it to take out.
		slot.modulate.a = EMPTY_ALPHA if weapon != null and not weapon.available() else 1.0
		slot.show()

## The corner number of a square. Only a weapon that comes out of a box has one;
## the hands are the hands, and there is no counting them.
func _fill_count(label: Label, weapon: Weapon) -> void:
	var trap := weapon as TrapWeapon
	if trap == null or trap.stock_id.is_empty():
		label.text = ""
		label.hide()
		return
	label.text = str(Stock.count(trap.stock_id))
	label.show()

func _highlight(index: int) -> void:
	for i in _slots.size():
		_slots[i].add_theme_stylebox_override("panel", _picked if i == index else _normal)

func _gather_slots() -> Array[PanelContainer]:
	var found: Array[PanelContainer] = []
	for child in get_children():
		var slot := child as PanelContainer
		if slot != null:
			found.append(slot)
	return found

func _on_weapon_changed(index: int, _weapon: Weapon) -> void:
	_highlight(index)

func _on_stock_changed(_id: String, _count: int) -> void:
	if _inventory == null:
		return
	_fill(_inventory)

func _on_capture_started(_rat: Node3D) -> void:
	hide()

func _on_capture_finished(_killed: bool) -> void:
	show()
