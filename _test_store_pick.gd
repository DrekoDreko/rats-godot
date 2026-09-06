extends SceneTree
## Store screen test bench: taking a thing off the rack, seeing it in the man's
## hand, and the button that is the only thing which spends money.
##
## Run with: godot res://_test_empty.tscn --script _test_store_pick.gd
##
## The empty scene and not the van: the bench stands its own van up, and booting
## into a second one leaves two stores in the tree for the group lookup below.
##
## It needs the van and a real viewport, unlike `_test_van_shop.gd`, which is
## about the till and runs headless. What is being checked here is the *screen*,
## and a screen with no viewport under it has no preview to put anything in.
##
## The four rules that make the rack two clicks deep, and which would each be
## invisible in play until somebody lost money to one of them:
##
## - **A tile spends nothing.** Pressing one puts the thing in his hand and
##   leaves the purse exactly where it was. This is the whole point of the
##   change: a man whose finger slipped on the rack has not bought anything.
## - **The thing he picked up is the thing he is holding.** The preview is
##   dressed from the item's own model, and picking a second thing puts the
##   first one back rather than leaving two in his fist.
## - **`BUY` is the only thing that spends, and it knows what it costs.** It is
##   dead with nothing chosen, dead on a thing he cannot afford, and live and
##   priced on one he can.
## - **The hand empties on the way out.** The store is opened and shut a dozen
##   times over two minutes of road, and a rack that remembered would open on a
##   thing he chose four stops ago.

## Frames of slack between one step and the next. The preview builds a model and
## a bone attachment, which want a frame to settle.
const WAIT := 10
## The phase the van is on the road in — copied rather than read off `Phase`,
## for the reason `_test_van_shop.gd` gives.
const PHASE_TRAVEL := 1
## The scene the store lives in.
const TRAVEL := "res://scenes/van_travel.tscn"
## Whose money this is, off Steam or made up when Steam is not running.
const FALLBACK_ID := 111
const OUR_NAME := "Us"
## The cheapest thing on the rack and the dearest. Looked up by id rather than
## by index so the bench does not go stale when a price moves.
const CHEAP_ID := "broom"
const DEAR_ID := "explosive_cheese"

var _us := 0
var _van: Node3D
var _store: Node
var _shop: Node
var _session: Node
var _phase: Node
var _stock: Node
var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _stand_the_van_up()
		1: return _check_rack_spends_nothing()
		2: return _check_one_thing_at_a_time()
		3: return _check_buy_button()
		4: return _check_closing_empties_the_hand()
	return _finish()

# --- Steps -----------------------------------------------------------------

## The van on the road with a man in it and the store open.
func _stand_the_van_up() -> bool:
	if _clock < 2:
		return false
	_shop = root.get_node_or_null("ShopManager")
	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_stock = root.get_node_or_null("Stock")
	if _shop == null or _session == null or _phase == null or _stock == null:
		print("FAIL: the autoloads are not in the tree")
		return _finish()

	_session.reset()
	_stock.reset()
	var steam: Node = root.get_node_or_null("SteamManager")
	_us = steam.get_steam_id() if steam != null else 0
	if _us == 0:
		_us = FALLBACK_ID
	_session.register_player(_us, OUR_NAME, true)

	# The phase is set with the scene path blanked so that `PhaseManager` does
	# not change scenes under us: the van is put up by hand instead, which is
	# what lets the bench hold on to it.
	_phase.scenes[PHASE_TRAVEL] = ""
	_phase.go_to(PHASE_TRAVEL)
	_phase.scenes[PHASE_TRAVEL] = TRAVEL
	_van = (load(TRAVEL) as PackedScene).instantiate() as Node3D
	root.add_child(_van)
	return _advance()


## Pressing a tile picks the thing up and spends nothing.
func _check_rack_spends_nothing() -> bool:
	if _clock < WAIT:
		return false
	# By group and not by path: the screen lives inside the monitor's own
	# viewport on the totem now (`scripts/session/store_terminal.gd`).
	_store = get_first_node_in_group("store_screen")
	if _store == null:
		print("FAIL: the van has no store screen in it")
		return _finish()
	_store.open()

	var before: int = _shop.money(_us)
	_store._select(_shop.find(CHEAP_ID))
	_expect(_shop.money(_us) == before,
		"picking a thing off the rack should spend nothing, and $%d went" % \
			[before - _shop.money(_us)])
	var empty: int = _stock.count(CHEAP_ID)
	_expect(empty == 0,
		"and it should put nothing in his bag either")
	_expect(_store._selected != null and _store._selected.id == CHEAP_ID,
		"the thing he pressed should be the thing that is chosen")
	_expect(_store._preview_item != null,
		"and it should be in his hand")
	return _advance()


## One thing at a time in the fist, and pressing the same tile puts it back.
func _check_one_thing_at_a_time() -> bool:
	if _clock < WAIT:
		return false
	_store._select(_shop.find(DEAR_ID))
	_expect(_store._selected.id == DEAR_ID,
		"picking a second thing should choose that one instead")
	_expect(_hand_holds() == 1,
		"and he should be holding one thing, not %d" % _hand_holds())

	# The same tile again is him putting it back.
	_store._select(_shop.find(DEAR_ID))
	_expect(_store._selected == null,
		"pressing the chosen tile again should put it back on the rack")
	_expect(_hand_holds() == 0,
		"and empty his hand, which is holding %d" % _hand_holds())
	return _advance()


## The button is the only thing that spends, and it says what it costs.
func _check_buy_button() -> bool:
	if _clock < WAIT:
		return false
	var button: Button = _store._buy_button
	_expect(button != null, "there should be a buy button")
	if button == null:
		return _finish()

	_expect(button.disabled, "it should be dead with nothing chosen")

	# Something he cannot afford: chosen, held, and still unbuyable.
	var dear: Resource = _shop.find(DEAR_ID)
	var dear_price: int = dear.price
	var purse: int = _shop.money(_us)
	var poor := purse < dear_price
	if poor:
		_store._select(dear)
		_expect(button.disabled,
			"it should stay dead on a thing he cannot afford")
		_expect(_store._preview_item != null,
			"but he should still be able to hold it and look")

	# And something he can.
	var cheap: Resource = _shop.find(CHEAP_ID)
	var cheap_price: int = cheap.price
	var cheap_amount: int = cheap.amount
	_store._select(cheap)
	_expect(not button.disabled, "it should come alive on a thing he can afford")
	_expect(button.text.contains(str(cheap_price)),
		"and say the price: '%s' does not mention $%d" % [button.text, cheap_price])

	var before: int = _shop.money(_us)
	_store._buy_selected()
	_expect(_shop.money(_us) == before - cheap.price,
		"pressing it should spend $%d, and $%d went" % \
			[cheap.price, before - _shop.money(_us)])
	var bag: int = _stock.count(CHEAP_ID)
	_expect(bag == cheap_amount,
		"and put %d in his bag, which holds %d" % [cheap_amount, bag])
	# The selection survives the purchase: a man buying traps usually wants three.
	_expect(_store._selected != null and _store._selected.id == CHEAP_ID,
		"and leave the thing in his hand for the next one")
	return _advance()


## Shutting the store empties his hand, so that it does not open on a thing he
## chose four stops ago.
func _check_closing_empties_the_hand() -> bool:
	if _clock < WAIT:
		return false
	_store.close()
	_expect(_store._selected == null, "shutting the store should choose nothing")
	_expect(_hand_holds() == 0,
		"and empty his hand, which is holding %d" % _hand_holds())

	_store.open()
	_expect(_store._buy_button.disabled,
		"and opening it again should find the button dead")
	return _advance()

# --- Tools -----------------------------------------------------------------

## How many things are hanging off the preview's hand. It is counted off the
## tree rather than read off `_preview_item`, because the thing this is guarding
## against is precisely a model that was left behind when that variable moved on
## — `queue_free` is not immediate, so the freed one is not counted.
func _hand_holds() -> int:
	var hand: Node3D = _store._preview_hand
	if hand == null:
		return 0
	var held := 0
	for child in hand.get_children():
		if not child.is_queued_for_deletion():
			held += 1
	return held


func _expect(condition: bool, what: String) -> void:
	if condition:
		return
	print("FAIL: %s" % what)
	_failures += 1


func _advance() -> bool:
	_step += 1
	_clock = 0
	return false


func _finish() -> bool:
	print("--- %d frames, %d failure(s) ---" % [_frames, _failures])
	return true
