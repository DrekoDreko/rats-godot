extends SceneTree
## Creeping: what a man on his knees is worth to a rat, and what the rat's own
## dinner is worth to the man creeping up on it.
##
## Run with: godot --headless --script tests/stealth.gd
##
## Two things are measured, and they are not the same claim:
##
## - **The numbers.** How much notice one animal takes of one man — walking,
##   running, kneeling — and how much less of anything at all while it is eating
##   (`rat.gd: _notice`). This is arithmetic and is checked as arithmetic.
## - **That it buys ground.** A man who would have been heard through a wall is
##   not heard through it once he kneels, and kneels at the food closer still.
##   That is the whole of the feature and it is checked end to end, through
##   `_scared_by_anybody`, which is what the fear machine actually calls.
##
## The wall is not decoration. With nothing between them the rat sees the man
## from sixteen metres and the sight alone settles every question, so the ear —
## the sense that decides whether a man can get within reach — would never be
## the thing under test.
##
## Nothing here names a `class_name` or an autoload by its global name: a bench
## is the `MainLoop` and is compiled before either exists.

const RAT_SCENE := "res://scenes/rat.tscn"

## Frames to let the physics server take the wall before anything is cast at it.
const SETTLE := 4

## Far enough behind the wall to be out of earshot of a kneeling man and well
## inside a standing one's. Read against `panic_radius`, which the common rat
## has at six metres.
const HEARD_STANDING := 5.0
## And inside a kneeling man's, but only while the animal is eating.
const HEARD_KNEELING := 3.0

var _rat: Node3D
var _man: CharacterBody3D
var _lure: Node3D
var _frames := 0
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
	_the_numbers()
	_it_buys_ground()
	return _finish()


## A rat, a man, a wall between them, and a heap of food at the rat's feet.
##
## The rat is stopped the moment it is up. What is under test is what it *would*
## decide, asked directly; left running it would talk itself into a flight on the
## first frame and walk out of every distance the bench sets up.
func _boot() -> bool:
	var world := Node3D.new()
	root.add_child(world)

	var scene := load(RAT_SCENE) as PackedScene
	if scene == null:
		return _fail("the rat scene did not load")
	_rat = scene.instantiate() as Node3D
	world.add_child(_rat)
	_rat.global_position = Vector3.ZERO
	_rat.set_physics_process(false)
	_rat.set_process(false)
	if _rat.species == null:
		return _fail("the rat came up with no species, so it has no habits to read")

	# The man is a `CharacterBody3D` with a crouch, which is the whole of what a
	# rat asks of a hunter (`rat.gd: _notice`). The player's own script is not on
	# him on purpose: it would drag in the camera, the belt and the arms to
	# measure a pair of knees with.
	_man = CharacterBody3D.new()
	_man.set_script(_hunter_script())
	_man.add_to_group("player")
	world.add_child(_man)

	# Head high and wide enough to shut the sight out at any of the distances
	# below, so that only the ear is left to answer.
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 4.0, 0.4)
	shape.shape = box
	wall.add_child(shape)
	world.add_child(wall)
	wall.global_position = Vector3(0.0, 2.0, 1.0)

	# The food the animal has its nose in. A bare `Node3D` in the `lures` group
	# is the whole contract (`rat.gd: _at_food`); it is put a stride off the rat
	# rather than on top of it so that moving it out of reach is one line.
	_lure = Node3D.new()
	_lure.add_to_group("lures")
	world.add_child(_lure)
	_away_from_food()
	return false


# --- The numbers -------------------------------------------------------------

func _the_numbers() -> void:
	var species = _rat.species
	_calm()
	_away_from_food()

	_stand()
	_close(_rat._notice(_man), 1.0, "A man walking about is the number everything else is measured against")
	_close(_rat._alert_radius_for(_man), _rat.alert_radius,
		"And he is seen from exactly the radius the rat was written with")

	_crouch()
	_close(_rat._notice(_man), species.crouch_notice, "A man on his knees is noticed less")
	_close(_rat._alert_radius_for(_man), _rat.alert_radius * species.crouch_notice,
		"And the sight shrinks with him")

	_run()
	_close(_rat._notice(_man), 1.4, "A man running past is noticed from further off")

	# Eating. It is the rat's own distraction, so it multiplies with whatever the
	# man is doing rather than replacing it.
	_at_food()
	_stand()
	_close(_rat._notice(_man), species.feeding_notice, "A rat with its nose in the food takes less notice")
	_crouch()
	_close(_rat._notice(_man), species.crouch_notice * species.feeding_notice,
		"And creeping up on one that is eating is worth both together")

	# Frightened, it is not eating: it is standing on the food on its way
	# somewhere else. A flight that went deaf over a bin bag would be an animal
	# the crew could walk up to and take mid-run.
	_rat._state = 2  # FLEEING
	_close(_rat._notice(_man), species.crouch_notice,
		"A fleeing rat gets no dinner and no distraction with it")
	_calm()

	# Whatever a breed is given, it is never given deafness.
	_check(species.crouch_notice > 0.0 and species.feeding_notice > 0.0,
		"Creeping buys ground; it never buys invisibility")


# --- That it buys ground -----------------------------------------------------

func _it_buys_ground() -> void:
	_calm()
	_away_from_food()

	# Out of sight, so every answer below is the ear's.
	_stand()
	_place_man(HEARD_STANDING)
	_check(not _rat._sees(_man), "The wall is not shutting the sight out, so nothing below is about hearing")

	_check(_rat._scared_by_anybody(_rat.panic_radius),
		"A man walking up to five metres is heard through the wall")
	_crouch()
	_check(not _rat._scared_by_anybody(_rat.panic_radius),
		"The same man on his knees is not: the crouch is what buys the ground")

	# Closer still, and now only the dinner covers the difference.
	_place_man(HEARD_KNEELING)
	_check(_rat._scared_by_anybody(_rat.panic_radius),
		"Three metres is inside a kneeling man's reach while the rat is watching")
	_at_food()
	_check(not _rat._scared_by_anybody(_rat.panic_radius),
		"But not while it is eating: the bait is what makes the last stride")

	# And none of it survives the animal looking up. A rat already running is
	# frightened at its full radius, food or no food.
	_rat._state = 2  # FLEEING
	_check(_rat._scared_by_anybody(_rat.panic_radius),
		"A rat that has already bolted is not crept up on over its dinner")
	_calm()


# --- Poking the two of them --------------------------------------------------

func _calm() -> void:
	_rat._state = 0  # WANDERING

func _at_food() -> void:
	_lure.global_position = _rat.global_position + Vector3(0.5, 0.0, 0.0)

func _away_from_food() -> void:
	_lure.global_position = _rat.global_position + Vector3(60.0, 0.0, 0.0)

## Standing still, on the far side of the wall.
func _stand() -> void:
	_man.crouching = false
	_man.velocity = Vector3.ZERO

func _crouch() -> void:
	_man.crouching = true
	_man.velocity = Vector3.ZERO

func _run() -> void:
	_man.crouching = false
	_man.velocity = Vector3(0.0, 0.0, 9.0)

func _place_man(distance: float) -> void:
	_man.global_position = Vector3(0.0, 0.0, distance)

## The smallest body a rat will read: one that moves and one that kneels.
func _hunter_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends CharacterBody3D\nvar crouching := false\nfunc is_crouching() -> bool:\n\treturn crouching\n"
	script.reload()
	return script


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _close(got: float, want: float, message: String) -> void:
	if absf(got - want) > 0.001:
		_fail("%s (got %.3f, wanted %.3f)" % [message, got, want])


func _fail(message: String) -> bool:
	push_error("FAIL: " + message)
	print("FAIL: " + message)
	_failures += 1
	return false


func _finish() -> bool:
	if _failures > 0:
		print("FAILED: %d" % _failures)
		quit(1)
		return true
	print("OK: the crouch and the dinner both shorten what a rat notices, and neither empties it")
	quit()
	return true
