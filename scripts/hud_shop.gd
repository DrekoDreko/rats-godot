extends Control
## The computer's screen: where the money from the hunt turns into something to
## hunt with.
##
## The shop knows nothing about the machine it is drawn on. It finds the computer
## by its group (`shop_computer`), reads the catalogue off it and opens when the
## machine announces that somebody used it — so moving the desk, or putting a
## second one in another van, changes nothing here. What is on the shelf lives in
## `resources/store/*.tres`: the price leaves the `Wallet` and the units land in
## the `Stock`, and neither of those two ever hears about this screen.
##
## While it is up the player is out of the map (`set_ui_open`): the mouse comes
## loose to reach the buttons and the body stops answering to anything. That is
## not a nicety — the click that buys is the same click that grabs a rat, and
## without the guard it would be spent snatching the camera back instead of
## pressing the button under the cursor.
##
## The rows are built here instead of being dressed in `world.tscn` because there
## is one per item on the shelf, and the shelf is a resource: a line added to the
## catalogue has to show up without anybody opening the editor.

## The whole HUD is drawn at 640x360, where 8 px is the normal size of a letter.
const FONT_SIZE := 8
## Green while the money is there, red while it is not — the two colours the
## health bar already uses.
const AFFORDABLE_COLOR := Color(0.55, 0.85, 0.45)
const DEAR_COLOR := Color(0.95, 0.32, 0.28)
## How faded the line under an item's name is, against the name itself.
const DETAIL_ALPHA := 0.7

## The pieces of the HUD that leave the screen while the shop is up. They are
## paths and not node references: an exported node only wires itself up in a
## scene saved by the editor, and the `world.tscn` HUD is written by hand.
@export var crosshair_path := NodePath("../Crosshair")
@export var hotbar_path := NodePath("../Hotbar")
@export var health_path := NodePath("../Health")
@export var prompt_path := NodePath("../Prompt")

@onready var _money: Label = $Center/Panel/Margin/Rows/Header/Money
@onready var _items: VBoxContainer = $Center/Panel/Margin/Rows/Items
@onready var _close: Button = $Center/Panel/Margin/Rows/Close

var _player: Node3D
var _catalogue: Array[StoreItem] = []
## One entry per row on screen: the item it sells, the line that counts what is
## left of it and the button that buys more.
var _rows: Array[Dictionary] = []

func _ready() -> void:
	hide()
	_close.add_theme_font_size_override("font_size", FONT_SIZE)
	_close.pressed.connect(close)
	# Wait one frame so the player and the computer are already in the tree.
	# Held onto before the wait rather than fetched again after it: a phase can
	# end on the frame this HUD is waiting through — the board in the van does
	# exactly that — and the node then resumes already out of the tree, where
	# `get_tree()` is null and reaching through it throws.
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame

	# Out of the tree while we waited: the scene we belong to was freed, there is
	# nobody left to wire to, and this HUD goes out with the rest of it.
	if not is_inside_tree():
		return
	_player = get_tree().get_first_node_in_group("player") as Node3D
	var computer := get_tree().get_first_node_in_group("shop_computer")
	if computer == null:
		return
	# The shelf is copied item by item instead of taken whole: what comes off the
	# scene is an array of resources, and what is wanted here is a catalogue.
	for entry in computer.catalogue:
		var item := entry as StoreItem
		if item != null:
			_catalogue.append(item)
	_build_rows()
	computer.used.connect(_on_used)
	Wallet.money_changed.connect(_on_money_changed)
	Stock.changed.connect(_on_stock_changed)
	_refresh()

## Esc closes the shop, and the player never sees that key: left to him, his own
## `toggle_mouse` would fight this screen over the cursor.
func _unhandled_key_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("toggle_mouse"):
		return
	close()
	get_viewport().set_input_as_handled()

# --- Opening and closing ---------------------------------------------------

func open() -> void:
	if visible:
		return
	_refresh()
	show()
	if _player != null:
		_player.set_ui_open(true)
	_show_rest_of_hud(false)

func close() -> void:
	if not visible:
		return
	hide()
	if _player != null:
		_player.set_ui_open(false)
	_show_rest_of_hud(true)

## The crosshair, the belt and the health bar have nothing to say while the
## player is standing at a screen. The prompt is the one that does not come back
## on its own account: he is still looking at the computer, and the player
## announces it again on the next frame.
func _show_rest_of_hud(on: bool) -> void:
	for path in [crosshair_path, hotbar_path, health_path]:
		var node := get_node_or_null(path) as CanvasItem
		if node != null:
			node.visible = on
	if not on:
		var prompt := get_node_or_null(prompt_path) as CanvasItem
		if prompt != null:
			prompt.hide()

# --- The shelf -------------------------------------------------------------

func _build_rows() -> void:
	for item in _catalogue:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		info.add_child(_label(item.display_name))
		var detail := _label("")
		detail.modulate.a = DETAIL_ALPHA
		info.add_child(detail)

		var buy := Button.new()
		buy.custom_minimum_size = Vector2(52, 0)
		buy.text = "$%d" % item.price
		buy.add_theme_font_size_override("font_size", FONT_SIZE)
		buy.add_theme_color_override("font_color", AFFORDABLE_COLOR)
		buy.add_theme_color_override("font_hover_color", AFFORDABLE_COLOR)
		buy.add_theme_color_override("font_pressed_color", AFFORDABLE_COLOR)
		buy.add_theme_color_override("font_disabled_color", DEAR_COLOR)
		buy.pressed.connect(_buy.bind(item))

		row.add_child(info)
		row.add_child(buy)
		_items.add_child(row)
		_rows.append({"item": item, "detail": detail, "buy": buy})

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 5)
	return label

## Everything on screen is read from the wallet and the stock, and nothing is
## kept here: the numbers on the shop cannot drift from the ones that survive the
## map.
func _refresh() -> void:
	_money.text = "$ %d" % Wallet.money
	for row in _rows:
		var item: StoreItem = row["item"]
		var detail: Label = row["detail"]
		var buy: Button = row["buy"]
		detail.text = "%s   x%d left" % [item.description, Stock.count(item.id)]
		buy.disabled = Wallet.money < item.price

func _buy(item: StoreItem) -> void:
	if not Wallet.spend(item.price):
		return
	Stock.add(item.id, item.amount)

# --- Signals ---------------------------------------------------------------

func _on_used(_by: Node3D) -> void:
	open()

func _on_money_changed(_total: int, _gain: int) -> void:
	_refresh()

func _on_stock_changed(_id: String, _count: int) -> void:
	_refresh()
