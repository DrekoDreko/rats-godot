extends SceneTree
## Dinner: that a rat put down by a heap of rubbish stays at it, and that a man
## walking up is what takes it off.
##
## Run with: godot --headless --script tests/feeding.gd
##
## The claim under test is the one the heaps exist for. A rat that reached the
## food, sniffed once and strolled off again was not something the crew could
## ever be said to have caught eating, and the notice it gives up while it feeds
## (`species.feeding_notice`, measured in `tests/stealth.gd`) was being paid out
## over a moment too short to walk a room in. So this counts frames: how much of
## a quarter of a minute an undisturbed animal spends on the rubbish, and how
## much of it standing still — and, the sharper reading, how long its longest
## unbroken stop at the rubbish was. A meal and a sniff are told apart by the
## clock alone: nothing on open floor stands still for as long as the shortest
## meal (`rat.gd: IDLE_TIME` against `FEEDING_TIME`), so a stop past that mark is
## an animal eating and nothing else.
##
## **The house is loaded rather than faked.** A rat with no navigation mesh under
## it never picks a destination at all (`rat.gd: _map_ready`), so it would sit
## exactly where it was put and pass this bench by doing nothing. What is being
## measured is where it *chooses* to be, which needs real floor to walk away
## across.
##
## Nothing here names an autoload by its global name: a bench is the `MainLoop`
## and is compiled before they exist.

const WORLD := "res://scenes/world.tscn"
const RAT_SCENE := "res://scenes/rat.tscn"

## Frames to let the navigation mesh bake and the rat settle onto the boards
## before anything is counted.
const SETTLE := 40
## How long the animal is watched, in physics frames. Fifteen seconds: long
## enough to hold several of its own meals (`rat.gd: FEEDING_TIME`) and several
## of the walks between them.
const WATCH := 900
## How long the man is given to shift it once he is standing over it.
const SCARE := 120

## The shortest stop that can only be a meal, in seconds. Between the longest
## sniff on open floor (2.4 s) and the shortest meal (5 s), so neither the wrong
## side of the change can be mistaken for the other.
const A_MEAL := 4.0

## How far from the heap still counts as being at it — the circle the animals
## mill about in (`rat.gd: LURE_SPREAD`), plus the heap's own reach.
const AT_FOOD := 2.5

var _world: Node3D
var _rat: Node3D
var _pile: Node3D
var _man: CharacterBody3D
var _frames := 0
var _near := 0
var _still := 0
var _meal := 0
var _longest := 0
var _bolted := false
var _failures := 0


func _initialize() -> void:
	Engine.max_fps = 60


func _process(_delta: float) -> bool:
	return false


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		return _boot()
	if _frames < SETTLE:
		return false
	if _frames == SETTLE:
		_rat.global_position = _pile.global_position
		return false
	if _frames <= SETTLE + WATCH:
		_count()
		if _frames == SETTLE + WATCH:
			_the_meal()
			_send_the_man_in()
		return false
	if _frames <= SETTLE + WATCH + SCARE:
		_bolted = _bolted or _rat._state == 2  # State.FLEEING
		return false
	_the_flight()
	return _finish()


func _boot() -> bool:
	var packed := load(WORLD) as PackedScene
	if packed == null:
		return _fail("the house did not load")
	_world = packed.instantiate() as Node3D
	root.add_child(_world)

	var scene := load(RAT_SCENE) as PackedScene
	if scene == null:
		return _fail("the rat scene did not load")
	_rat = scene.instantiate() as Node3D
	_world.add_child(_rat)

	var piles := get_nodes_in_group("garbage")
	if piles.is_empty():
		return _fail("the house has no rubbish in it to eat")
	_pile = piles[0] as Node3D
	return false


## One frame of watching: where it is standing, whether it is standing, and how
## long it has been standing there.
##
## Stillness is read off the state and not off the velocity. A rat threading a
## doorway is slow without having stopped, and what is being counted here is the
## animal deciding to stay put — which is the state itself.
func _count() -> void:
	var at_food := _flat_distance(_rat.global_position, _pile.global_position) <= AT_FOOD
	var eating: bool = at_food and _rat._state == 1  # State.IDLE
	if at_food:
		_near += 1
	if eating:
		_still += 1
		_meal += 1
		_longest = maxi(_longest, _meal)
	else:
		_meal = 0


func _the_meal() -> void:
	var still := float(_still) / float(WATCH)
	var longest := float(_longest) / Engine.physics_ticks_per_second
	_expect(longest > A_MEAL,
		"it settles on the rubbish and eats, longest stop %.1f s" % longest)
	_expect(still > 0.25,
		"and a quarter of the watch at least goes on that, %d%%"
			% roundi(still * 100.0))
	# Not an assertion, because how much of a quarter of a minute one animal
	# spends at one heap is a die roll and not a promise: it is printed so that a
	# run where the rats stopped going to the food at all is readable here.
	print("  note it was at the rubbish for %d%% of the watch"
		% roundi(float(_near) / float(WATCH) * 100.0))


## The other half of the claim: the meal is a preference and not a spell. A man
## walking up takes the animal off the food, exactly as he takes it off anything
## else it was doing.
##
## **The house's own player is the man, and not one the bench makes.** A rat asks
## the `player` group for the nearest hunter and takes the *first* answer it gets
## (`rat.gd: _hunters`), which in a loaded level is the crew member standing on
## the doorstep — a second body added to the group is never looked at, and a
## bench that added one measured a rat that could not see it.
func _send_the_man_in() -> void:
	_man = get_first_node_in_group("player") as CharacterBody3D
	if _man == null:
		_fail("the house came up with nobody in it to frighten the rat")
		return
	_man.global_position = _rat.global_position + Vector3.FORWARD * 0.5


## Whether the man shifted it. Both halves are read over the whole window rather
## than at the end of it: a rat that bolted, reached ground it liked and calmed
## down again (`safe_radius`) is a rat that was frightened off its dinner, which
## is the claim — it is only standing still again because it is somewhere else.
func _the_flight() -> void:
	_expect(_bolted, "a man walking up takes it off the food")
	_expect(_flat_distance(_rat.global_position, _man.global_position) > 1.0,
		"and it puts ground between them, %.1f m"
			% _flat_distance(_rat.global_position, _man.global_position))


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _expect(condition: bool, what: String) -> void:
	if condition:
		print("  ok   %s" % what)
		return
	_failures += 1
	print("  FAIL %s" % what)


func _fail(what: String) -> bool:
	_failures += 1
	print("  FAIL %s" % what)
	return _finish()


func _finish() -> bool:
	if _failures == 0:
		print("feeding: every check passed")
	else:
		print("feeding: %d failed" % _failures)
	quit(1 if _failures > 0 else 0)
	return true
