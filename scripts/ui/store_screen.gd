class_name StoreScreen
extends CanvasLayer
## The store the crew shops at on the road: the man himself on the left, his
## name and his money over him, and the racks of weapons he can buy on the
## right.
##
## **It is a screen, not a fitting.** The shop used to be a cabinet bolted to the
## wall of the van (`shop_shelf.gd`), and a man bought things by walking up to it
## and looking at the right box. That is gone. `E` opens this from anywhere in
## the back of the van, which is what the van is *for* on the road — two minutes
## of driving is shopping time, and making it a place in the room meant one man
## standing in the corner while the other three waited for the wall.
##
## **Only while the wheels are turning.** `ShopManager.is_open()` is the one
## answer, and it is the phase and nothing else: the lobby has not left yet and
## the house has no van in it. The key does nothing in either, the hint does not
## show, and a screen that is up when the phase turns is shut by the phase rather
## than left standing over a van that has parked.
##
## **The rack is drawn from the catalogue, not from the scene.** Everything in
## `resources/store/` is on sale, grouped into columns by its `kind`, and every
## column is padded out to `SLOTS_PER_COLUMN` with empty frames. That padding is
## the point: the weapons are being written one at a time, and a rack that shows
## where the next three are going is a rack nobody has to redraw when they
## arrive. Dropping a `.tres` in the folder fills the next empty frame on every
## machine at once.
##
## **It decides nothing about money.** Pressing a tile asks `ShopManager`, the
## host answers, and the tile is redrawn off what came back — the same round trip
## the shelf took, and for the same reason: a screen that debits its own purse
## and is corrected a moment later is worse than one that takes a beat to be
## right.

## The whole HUD is drawn at 640x360, where 8 px is the normal size of a letter.
const FONT_SIZE := 8
## The size the column headers and the store's own title are set in.
const HEADING_SIZE := 8

## Green while the money is there, red while it is not — the two colours the
## health bar and the old shelf already use.
const AFFORDABLE_COLOR := Color(0.55, 0.85, 0.45)
const DEAR_COLOR := Color(0.95, 0.32, 0.28)
## The blue the headings and the frames are drawn in, off the same palette as
## the rest of the screen.
const ACCENT_COLOR := Color(0.45, 0.72, 0.9)
## And what an empty frame is written in: present, but plainly nothing yet.
const EMPTY_COLOR := Color(0.5, 0.56, 0.62)

## What an empty frame reads.
const EMPTY_TEXT := "—"

## The racks, and which kinds of thing stand on each. The columns are fixed and
## the items find their way into them, rather than the other way round: a column
## per kind would be five narrow strips at this resolution, and a column that
## appears when its first item is written would move every other one sideways.
const COLUMNS: Array[Dictionary] = [
	{"title": "TRAPS", "kinds": [StoreItem.Kind.TRAP]},
	{"title": "WEAPONS", "kinds": [StoreItem.Kind.ONE_HAND, StoreItem.Kind.TWO_HANDS]},
	{"title": "SUPPLIES", "kinds": [StoreItem.Kind.BAIT, StoreItem.Kind.PATCH]},
]

## How many frames each rack shows at the least. Anything the catalogue does not
## fill is drawn empty and waiting — see the note at the top.
const SLOTS_PER_COLUMN := 5

## How tall one frame on the rack is, and how far the writing on it stands off
## the frame's own edge.
const TILE_HEIGHT := 30
const TILE_INSET := Vector2(4, 2)

## How long a refused tile flashes for, and how many times. A blink and not a
## colour change, so that a man who pressed twice sees the second refusal as
## well as the first — the same shape the old shelf's price card used.
const FLASH_TIME := 0.1
const FLASH_COUNT := 3

## What the man on the left is doing while he shops: standing still.
const PREVIEW_STATE := PlayerAvatar.State.IDLE

## The body on the left, and the PS1 dressing that makes it match the one in the
## van. The preview renders in a world of its own, where the van's own applier
## cannot reach it.
const MODEL_SCENE := preload("res://scenes/player_model.tscn")
const PS1_SCENE := preload("res://scenes/ps1.tscn")

## The pieces of the van's HUD that leave the screen while the store is up. They
## are paths and not node references because this scene is instanced into the
## van beside that HUD rather than inside it.
@export var crosshair_path := NodePath("../HUD/Crosshair")
@export var prompt_path := NodePath("../HUD/Prompt")

@onready var _root: Control = $Root
@onready var _hint: Label = $Hint
@onready var _money: Label = $Root/Margin/Rows/Header/Money
@onready var _player_name: Label = $Root/Margin/Rows/Body/Left/PlayerName
@onready var _columns: HBoxContainer = $Root/Margin/Rows/Body/Columns
@onready var _notice: Label = $Root/Margin/Rows/Footer/Notice
@onready var _preview: SubViewport = $Root/Margin/Rows/Body/Left/Preview/View
@onready var _preview_seat: Node3D = $Root/Margin/Rows/Body/Left/Preview/View/Seat

## Our own character, so the store can take him over while it is up and hand him
## back when it goes. Found by group, like every other piece of the HUD.
var _player: Node3D
## The body in the preview, built once and repainted as the colour changes.
var _model: PlayerModel
## One entry per frame on the racks that has something in it: the item it sells,
## the button that buys it and the two labels on it.
var _tiles: Array[Dictionary] = []
## What we last asked the host for, so that a refusal flashes the tile the man
## actually pressed. The refusal comes back off the wire without the item on it.
var _pending_id := ""
## Whether the screen is up. Kept rather than read off `visible`, because the two
## can part company for a frame while a scene is being changed under us.
var _open := false


func _ready() -> void:
	_root.hide()
	_hint.hide()

	_build_racks()
	_build_preview()

	ShopManager.item_bought.connect(_on_item_bought)
	ShopManager.request_refused.connect(_on_refused)
	SessionManager.player_changed.connect(_on_player_changed)
	ColorManager.color_changed.connect(_on_color_changed)
	PhaseManager.phase_changed.connect(_on_phase_changed)

	# Wait one frame so the character is already in the tree. Held onto before
	# the wait rather than fetched again after it: a phase can end on the frame
	# this is waiting through — the ready board in the van does exactly that —
	# and the node then resumes already out of the tree, where `get_tree()` is
	# null and reaching through it throws.
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	if not is_inside_tree():
		return

	_player = get_tree().get_first_node_in_group("player") as Node3D
	if _player != null:
		# The hint has to come and go as he looks from a station to the floor,
		# and that is the one thing here that changes without anything in the
		# game changing. The character already announces it, so the corner is
		# rewritten off his announcement rather than off a frame of its own.
		_player.interactable_changed.connect(_on_interactable_changed)
	_refresh()


## `E` opens the store and `E` closes it again, and Esc closes it too for the
## man who reaches for that first. One press is one of those and never both: the
## screen is either up or it is not when the event arrives.
##
## The press is spent here so that it does not go on to be read as reaching for
## something. The character below swallows `E` itself when he is looking at a
## station, which is what keeps the map table and the ready board from opening
## the store instead of themselves — and `_can_open` checks the same thing, so
## that the answer does not depend on which of us the viewport asks first.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _open:
			close()
		elif _can_open():
			open()
		else:
			return
	elif _open and event.is_action_pressed("toggle_mouse"):
		close()
	else:
		return
	get_viewport().set_input_as_handled()

# --- Opening and closing ----------------------------------------------------

## Whether `E` means the store right now: the van is on the road, there is a man
## to take over, and he is not already busy with a screen, a station or a rat in
## his hands.
func _can_open() -> bool:
	if _open or _player == null or not ShopManager.is_open():
		return false
	if _player.is_ui_open() or _player.focused() != null:
		return false
	var inventory: Node = _player.inventory
	return inventory == null or not inventory.is_busy()


func open() -> void:
	if _open:
		return
	_open = true
	_notice.text = ""
	_refresh()
	_root.show()
	_hint.hide()
	if _player != null:
		_player.set_ui_open(true)
	_show_rest_of_hud(false)


func close() -> void:
	if not _open:
		return
	_open = false
	_root.hide()
	if _player != null:
		_player.set_ui_open(false)
	_show_rest_of_hud(true)
	_update_hint()


## The crosshair and the prompt have nothing to say while a man is shopping. The
## prompt is the one that does not come back on its own account: he may still be
## standing at a station, and the character announces it again on the next frame.
func _show_rest_of_hud(on: bool) -> void:
	var crosshair := get_node_or_null(crosshair_path) as CanvasItem
	if crosshair != null:
		crosshair.visible = on
	if not on:
		var prompt := get_node_or_null(prompt_path) as CanvasItem
		if prompt != null:
			prompt.hide()


## The line in the corner that says the key is there at all. It is up whenever
## the store could be opened and nothing else is in the way, which is the same
## question `_can_open` asks — a hint offering a key that would do nothing is
## worse than no hint.
func _update_hint() -> void:
	_hint.visible = _can_open()

# --- The racks --------------------------------------------------------------

## The three racks, built once. The catalogue is read off `ShopManager`, which
## scanned the folder on the way up, so every machine builds the same racks in
## the same order without anybody keeping a second list.
func _build_racks() -> void:
	var catalogue := ShopManager.catalogue()
	for column in COLUMNS:
		var kinds: Array = column["kinds"]
		var items: Array[StoreItem] = []
		for item in catalogue:
			if kinds.has(item.kind):
				items.append(item)
		_columns.add_child(_build_column(String(column["title"]), items))


## One rack: its heading, what is on it, and the empty frames under that.
func _build_column(title: String, items: Array[StoreItem]) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)

	var heading := _label(title, HEADING_SIZE)
	heading.add_theme_color_override("font_color", ACCENT_COLOR)
	column.add_child(heading)

	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 2)
	column.add_child(rule)

	for item in items:
		column.add_child(_build_tile(item))
	for _i in range(maxi(SLOTS_PER_COLUMN - items.size(), 0)):
		column.add_child(_build_empty_tile())
	return column


## One thing for sale: its name, and under it what it costs and how many of it
## the man already has. The button is the whole tile rather than a corner of it,
## so the mouse only has to land somewhere on the thing being bought.
func _build_tile(item: StoreItem) -> Button:
	var button := _frame()
	button.tooltip_text = item.description
	button.pressed.connect(_buy.bind(item))

	var rows := VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = TILE_INSET.x
	rows.offset_top = TILE_INSET.y
	rows.offset_right = -TILE_INSET.x
	rows.offset_bottom = -TILE_INSET.y
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 0)

	var name_label := _label(item.display_name, FONT_SIZE)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var price_label := _label("", FONT_SIZE)
	rows.add_child(name_label)
	rows.add_child(price_label)
	button.add_child(rows)

	_tiles.append({"item": item, "button": button, "price": price_label})
	return button


## A frame with nothing in it yet. It is a dead button and not a panel, so that
## the rack keeps one shape as the weapons are written into it one at a time.
func _build_empty_tile() -> Button:
	var button := _frame()
	button.disabled = true
	button.focus_mode = Control.FOCUS_NONE
	button.text = EMPTY_TEXT
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	button.add_theme_color_override("font_disabled_color", EMPTY_COLOR)
	return button


## The frame a slot is drawn in, whether or not there is anything in it: a dark
## panel with a stripe of the store's blue down its left edge, brighter under the
## mouse. Every slot is the same frame so that the empty ones read as *waiting*
## rather than as gaps in the rack — which is the whole reason they are drawn.
func _frame() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, TILE_HEIGHT)
	button.add_theme_stylebox_override("normal", _frame_style(0.06, 0.4))
	button.add_theme_stylebox_override("hover", _frame_style(0.16, 0.9))
	button.add_theme_stylebox_override("pressed", _frame_style(0.24, 1.0))
	button.add_theme_stylebox_override("focus", _frame_style(0.16, 0.9))
	button.add_theme_stylebox_override("disabled", _frame_style(0.03, 0.18))
	return button


## One of those frames, at a given strength: how much light is in the panel and
## how much is in the stripe.
func _frame_style(fill: float, stripe: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(ACCENT_COLOR, fill)
	style.border_width_left = 2
	style.border_color = Color(ACCENT_COLOR, stripe)
	return style


func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)
	return label

# --- The man on the left ----------------------------------------------------

## The body in the preview. It renders in a world of its own inside the
## `SubViewport`, so it is lit by that scene's own lamps rather than by whatever
## corner of the van the player happens to be standing in — a shop window and
## not a mirror.
func _build_preview() -> void:
	if _preview_seat == null:
		return
	_model = MODEL_SCENE.instantiate() as PlayerModel
	_preview_seat.add_child(_model)
	# The van dresses its models from an applier at the root of the scene, and
	# that applier cannot see into another world. This one carries its own.
	_model.add_child(PS1_SCENE.instantiate())
	# The pose is set after the model is in the tree: `set_state` reaches for the
	# `AnimationPlayer` through an `@onready`, which is not resolved before then.
	_model.set_state(PREVIEW_STATE)


## Repaints the man and rewrites his name. Both live on `SessionManager`, put
## there by the host, so there is nothing decided here — only redrawn.
func _refresh_player() -> void:
	var us := _our_steam_id()
	var color := SessionManager.color(us)
	if _model != null:
		_model.set_tint(color)
	var entry := SessionManager.player(us)
	_player_name.text = String(entry.get("name", "PLAYER")).to_upper()
	_player_name.add_theme_color_override("font_color", color)

# --- What is written --------------------------------------------------------

## The whole screen, from the purse and the catalogue and nothing kept here: the
## numbers on the store cannot drift from the ones that survive the van.
func _refresh() -> void:
	var us := _our_steam_id()
	_money.text = "$ %d" % ShopManager.money(us)
	_refresh_player()
	for tile in _tiles:
		var item: StoreItem = tile["item"]
		var price: Label = tile["price"]
		var button: Button = tile["button"]
		# The count is what a man wants off a rack he has already bought from:
		# the price tells him what it costs and the count whether he needs
		# another one.
		var held := Stock.count(item.id)
		price.text = "$%d" % item.price if held <= 0 else "$%d   x%d" % [item.price, held]
		var afford := ShopManager.can_afford(us, item)
		price.add_theme_color_override("font_color",
			AFFORDABLE_COLOR if afford else DEAR_COLOR)
		button.disabled = not afford
	_update_hint()


## A refused tile, blinking red. It is the whole of the feedback for an empty
## pocket, and it is the tile the man actually pressed rather than a guess: the
## id was remembered on the way out in `_buy`.
func _flash_refused() -> void:
	for tile in _tiles:
		var item: StoreItem = tile["item"]
		if item.id != _pending_id:
			continue
		var button: Button = tile["button"]
		var tween := create_tween()
		for _i in FLASH_COUNT:
			tween.tween_property(button, "modulate", DEAR_COLOR, 0.0)
			tween.tween_interval(FLASH_TIME)
			tween.tween_property(button, "modulate", Color.WHITE, 0.0)
			tween.tween_interval(FLASH_TIME)
		return

# --- Buying -----------------------------------------------------------------

## Asks the host for one of something. Nothing is written here and nothing is
## drawn ahead of the answer — see the note at the top.
func _buy(item: StoreItem) -> void:
	_pending_id = item.id
	_notice.text = ""
	ShopManager.request_buy(_our_steam_id(), item.id)

# --- What wakes it up -------------------------------------------------------

## Somebody bought something. Everybody's screen redraws and not only the
## buyer's: what changed for the others is nothing, and the guard would cost more
## than the redraw.
func _on_item_bought(_steam_id: int, _item_id: String) -> void:
	_refresh()


## The host turned us down — an empty pocket, or the van already off the road
## while our packet was in the air. Only heard on the machine that asked.
func _on_refused(reason: String) -> void:
	_notice.text = reason
	_flash_refused()


## A purse moved, or a name arrived. Only our own matters to what is written
## here, since every price is set against our own pocket.
func _on_player_changed(steam_id: int) -> void:
	if steam_id == _our_steam_id():
		_refresh()


## He looked at a station, or away from one. The key means that station while he
## is on it, so the corner stops offering the store.
func _on_interactable_changed(_interactable: Interactable) -> void:
	_update_hint()


func _on_color_changed(steam_id: int, _color: Color) -> void:
	if steam_id == _our_steam_id():
		_refresh_player()


## The van left the road with the store still up. It is shut here rather than
## left standing, for the same reason the shelf went dark: a screen offering
## goods the host will refuse is a screen that lies.
func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	if not ShopManager.is_open():
		close()
	_update_hint()

# --- Odds and ends ----------------------------------------------------------

## Whose money this store spends. Ours, always. Falls back to the only man in the
## crew when Steam is not running, which is what makes the store work on a bench
## and in a solo game where `get_steam_id` answers zero — the same answer
## `ShopManager.is_ours` works out, and worked out the same way.
func _our_steam_id() -> int:
	var steam_id := LobbyManager.our_steam_id()
	if steam_id != 0 and SessionManager.has_player(steam_id):
		return steam_id
	var crew := SessionManager.players.keys()
	return crew[0] if crew.size() == 1 else steam_id
