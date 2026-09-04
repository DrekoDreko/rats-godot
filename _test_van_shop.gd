extends SceneTree
## Van shop test bench: the store the crew shops at on the road, the money that
## leaves one man's pocket and nobody else's, and the phase that shuts the whole
## thing.
##
## Run with: godot --headless --script _test_van_shop.gd
##
## What is checked here is the card's own acceptance criterion first — two men
## buying at the same shelf keep separate and correct balances — and then the
## four rules around it that could each quietly make the shelf lie:
##
## - **The host holds the till.** A purse is never written by the machine that
##   asked; it is written by `_apply`, which is the host's answer. The bench runs
##   solo, where that road is the short one (`request_buy` hands straight to
##   `_handle_request`), so what is really being checked is that the short road
##   ends in the same place as the long one: the money moves, and it moves once.
## - **Nobody spends what he has not got.** An empty pocket buys nothing and the
##   purse is not touched on the way to being refused.
## - **The shelf is shut off the road.** Buying is a `TRAVEL` thing, and a
##   purchase asked for in the lobby or the house is refused by the host rather
##   than quietly credited.
## - **The box on the belt is our own.** `Stock` is the single-player autoload
##   the weapons in *our* player's hands spend from, so somebody else's purchase
##   must fill his bag and leave our box exactly where it was. That is the one
##   that would be invisible in play until two men bought different things and
##   both found the other's traps on their belt.
##
## What the screen itself draws is not checked here — it is a `CanvasLayer` that
## needs a viewport. What is checked is everything it reads: the catalogue, the
## purses and the phase.

## Frames of slack between one step and the next.
const WAIT := 8
## The other man at the shelf. Any number does — the crew is keyed by Steam ID
## and the bench introduces him itself. *Our* own id is not a constant: it has to
## be the one `SteamManager` actually answers with, or this machine has no man in
## the crew and `ShopManager.is_ours` rightly refuses to credit our belt for
## anybody. It is settled in `_check_shelf`.
const THEM := 222
## What they are called, for the refusal sentences.
const OUR_NAME := "Us"
const THEIR_NAME := "Them"
## Copied instead of read off `Phase`: naming the class from a bench drags its
## script into the compile that happens before the autoloads exist (see
## `_test_traps.gd` and the note in `_test_inventory.gd`).
const PHASE_LOBBY := 0
const PHASE_TRAVEL := 1
const PHASE_SURVEY := 2
## The cheapest thing on the shelf and the dearest, by id. They are looked up
## rather than indexed so the bench does not go stale when a price moves.
const CHEAP_ID := "broom"
const DEAR_ID := "explosive_cheese"

## Our own Steam ID, read off `SteamManager` on the way in — see `THEM`.
var _us := 0
var _shop: Node
var _session: Node
var _phase: Node
var _stock: Node
var _refusals: Array[String] = []
var _bought: Array[Array] = []
var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0


func _initialize() -> void:
	# Without a screen the loop would run at thousands of frames per second.
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_shelf()
		1: return _check_broke()
		2: return _check_buys()
		3: return _check_purses_are_separate()
		4: return _check_our_box_only()
		5: return _check_shut_off_the_road()
	return _finish()

# --- Steps -----------------------------------------------------------------

## The shelf was read off disk, in the order every machine has it, and the crew
## is seated with the money the card gives them.
func _check_shelf() -> bool:
	if _clock < WAIT:
		return false
	# The autoloads are picked up by node name: in a bench run with `--script`
	# their global names do not exist yet.
	_shop = root.get_node_or_null("ShopManager")
	_session = root.get_node_or_null("SessionManager")
	_phase = root.get_node_or_null("PhaseManager")
	_stock = root.get_node_or_null("Stock")
	if _shop == null or _session == null or _phase == null or _stock == null:
		print("FAIL: the autoloads are not in the tree")
		return _finish()

	_shop.item_bought.connect(func(who: int, what: String) -> void: _bought.append([who, what]))
	_shop.request_refused.connect(func(why: String) -> void: _refusals.append(why))

	_session.reset()
	_stock.reset()
	# Whoever this machine is to Steam is the man it plays: registering anybody
	# else under our own name would make every purchase somebody else's, which
	# is exactly what `is_ours` is built to notice. Off Steam entirely the id
	# comes back zero, and a plain number stands in for it.
	var steam: Node = root.get_node_or_null("SteamManager")
	_us = steam.get_steam_id() if steam != null else 0
	if _us == 0:
		_us = 111
	_session.register_player(_us, OUR_NAME, true)
	_session.register_player(THEM, THEIR_NAME)
	_session.phase = PHASE_TRAVEL
	_expect(_shop.is_ours(_us), "the man this machine plays should be ours")
	_expect(not _shop.is_ours(THEM), "and the other one should not be")

	var count: int = _shop.count()
	print("--- the shelf has %d item(s) ---" % count)
	_expect(count == 5, "the rack is stocked with five things, and there are %d" % count)
	_expect(_shop.is_open(), "the shelf should be open on the road")

	# Sorted by price and then by id, which is what makes an index mean the same
	# thing on every machine.
	var sorted := true
	for i in range(1, count):
		var before: Resource = _shop.at(i - 1)
		var after: Resource = _shop.at(i)
		if before.price > after.price:
			sorted = false
	_expect(sorted, "the shelf should read cheapest first")
	_expect(_shop.find(CHEAP_ID) != null, "'%s' should be on the shelf" % CHEAP_ID)
	_expect(_shop.find("nothing_like_this") == null, "a made-up id should be on no shelf")

	var start: int = _session.STARTING_MONEY
	_expect(_shop.money(_us) == start, "a man should start with $%d" % start)
	_expect(_shop.money(THEM) == start, "and so should the other one")
	return _advance()


## A pocket that cannot pay buys nothing, and it is turned down before the money
## is touched.
func _check_broke() -> bool:
	var dear: Resource = _shop.find(DEAR_ID)
	if dear == null:
		print("FAIL: '%s' is not on the shelf" % DEAR_ID)
		return _finish()
	_expect(dear.price > _shop.money(_us), "the bench needs something dearer than a full purse")
	_expect(not _shop.can_afford(_us, dear), "a light pocket should not afford the %s" % dear.display_name)

	var before: int = _shop.money(_us)
	_refusals.clear()
	_shop.request_buy(_us, DEAR_ID)
	_expect(_shop.money(_us) == before, "a refused purchase should leave the purse alone")
	_expect(_session.inventory(_us).is_empty(), "a refused purchase should put nothing in the bag")
	_expect(_refusals.size() == 1, "the man who could not pay should be told once")
	_expect(_refusals.size() > 0 and _refusals[0] == _shop.REFUSAL_POOR,
		"and told it was the money")
	return _advance()


## The purchase: the price leaves the purse, the item lands in the bag and the
## units land in the box on the belt.
func _check_buys() -> bool:
	var item: Resource = _shop.find(CHEAP_ID)
	var before: int = _shop.money(_us)
	_bought.clear()
	_refusals.clear()
	_shop.request_buy(_us, CHEAP_ID)

	_expect(_shop.money(_us) == before - item.price, "the price should leave the purse")
	_expect(_session.inventory(_us).has(CHEAP_ID), "the thing should land in the bag")
	_expect(_refusals.is_empty(), "a purchase that went through should refuse nothing")
	_expect(_bought.size() == 1, "the shelf should announce the purchase once")
	_expect(_stock.count(CHEAP_ID) == item.amount,
		"our own box should hold %d, and holds %d" % [item.amount, _stock.count(CHEAP_ID)])
	return _advance()


## The card's own criterion: two men buying at the same shelf keep separate and
## correct balances. Neither one's purchase moves the other's purse or bag.
func _check_purses_are_separate() -> bool:
	var item: Resource = _shop.find(CHEAP_ID)
	var ours_before: int = _shop.money(_us)
	var theirs_before: int = _shop.money(THEM)

	_shop.request_buy(THEM, CHEAP_ID)

	_expect(_shop.money(THEM) == theirs_before - item.price,
		"his purchase should come out of his own pocket")
	_expect(_shop.money(_us) == ours_before,
		"his purchase should not touch ours: $%d, was $%d" % [_shop.money(_us), ours_before])
	_expect(_session.inventory(THEM).has(CHEAP_ID), "his thing should land in his bag")
	_expect(_session.inventory(_us).size() == 1, "and not a second time in ours")

	# The two of them bought the same thing at the same price, and each is one
	# purchase lighter than he started.
	var start: int = _session.STARTING_MONEY
	_expect(_shop.money(_us) == start - item.price, "our purse should be one broom lighter")
	_expect(_shop.money(THEM) == start - item.price, "and so should his")
	return _advance()


## The box on the belt is our own: his purchase fills his bag and leaves our box
## exactly where it was. `Stock` is what the weapons in our hands spend from, and
## crediting it for somebody else's shopping would hand us the traps he paid for.
func _check_our_box_only() -> bool:
	var item: Resource = _shop.find("mousetrap")
	if item == null:
		print("FAIL: the mousetrap is not on the shelf")
		return _finish()
	var ours_before: int = _stock.count(item.id)
	_expect(ours_before == 0, "the bench should start this step with no mousetraps")

	_shop.request_buy(THEM, item.id)

	_expect(_session.inventory(THEM).has(item.id), "his mousetraps should be in his bag")
	_expect(_stock.count(item.id) == ours_before,
		"his mousetraps should not be on our belt: %d" % _stock.count(item.id))
	return _advance()


## The shelf is shut everywhere but the road. A purchase asked for in the lobby
## or in the house is refused by the host rather than quietly credited.
func _check_shut_off_the_road() -> bool:
	for phase in [PHASE_LOBBY, PHASE_SURVEY]:
		_session.phase = phase
		_expect(not _shop.is_open(), "the shelf should be shut in phase %d" % phase)

		var before: int = _shop.money(_us)
		var bag: int = _session.inventory(_us).size()
		_refusals.clear()
		_shop.request_buy(_us, CHEAP_ID)

		_expect(_shop.money(_us) == before,
			"a purchase in phase %d should leave the purse alone" % phase)
		_expect(_session.inventory(_us).size() == bag,
			"a purchase in phase %d should put nothing in the bag" % phase)
		_expect(_refusals.size() == 1, "and should say so, in phase %d" % phase)
		_expect(_refusals.size() > 0 and _refusals[0] == _shop.REFUSAL_SHUT,
			"and say it was the shelf being shut, in phase %d" % phase)

	# Back on the road, and it works again — a shut shelf is shut, not broken.
	_session.phase = PHASE_TRAVEL
	_expect(_shop.is_open(), "the shelf should open again on the road")
	return _advance()

# --- Tools -----------------------------------------------------------------

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
