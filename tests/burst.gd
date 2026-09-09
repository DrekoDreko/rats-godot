extends SceneTree
## The kill as the player actually meets it: a rat grabbed, hammered until it
## gives, and coming apart in the fist instead of being carried to a belt.
##
## Run with: godot --headless --script tests/burst.gd
##
## What is checked here is the shape of the gesture rather than how it looks:
## that the strangling still ends in a death, that the death is a *burst* and
## reaches it inside the beat the hands promised, that the money lands on the
## kill rather than a gesture later, that the animal leaves the tree instead of
## lingering, and that the spray it throws is a real thing in the world with a
## life of its own and an end to it.
##
## The looks are the player's to judge and he has said he will. What a bench can
## hold is that nothing in the chain is left hanging: no rat that never dies, no
## body that never frees, no blood that never clears.
##
## **Nothing here names a `class_name` or an autoload by its global name** — a
## bench is the `MainLoop` and is compiled before either exists.

const RAT_SCENE := "res://scenes/rat.tscn"
const BURST_SCRIPT := "res://scripts/fx/blood_burst.gd"

## Frames of slack for a gesture to run out. The burst is a sixth of a second
## and the physics ticks sixty times in one, so this is several times what the
## whole thing needs — a bench that fails by being impatient teaches nothing.
const PATIENCE := 60

var _world: Node3D
var _rats: Node3D
var _hand: Node3D
var _rat: Node3D

var _frames := 0
var _step := 0
var _waited := 0
var _failures := 0

## What the rat was worth, read off the wallet the moment before the kill and
## again after it. The bench does not care how much a rat pays — that is the
## economy's business and it has its own tests — only that it is paid, once, and
## on the burst.
var _paid_before := 0


func _initialize() -> void:
	Engine.max_fps = 60


## The bench drives itself off the physics tick, but the gesture it is watching
## does not: the capture runs in `_process` (`rat.gd`), because a body held
## against the camera has to move on the screen's beat rather than the 60 Hz one.
## Overriding this is what lets the idle frame through — without it the rat
## hangs at the start of its rise forever and the bench is measuring a tree that
## is only half running.
func _process(_delta: float) -> bool:
	return false


func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		return _boot()
	match _step:
		0: return _step_grab()
		1: return _step_kill()
		2: return _step_it_comes_apart()
		3: return _step_the_blood_clears()
		4: return _step_a_blow_bleeds_too()
	return _finish()


## A room with a rat in it and a hand to hold it with.
##
## The hand is not a bare `Node3D` floating in the room, and it took a failing
## bench to learn why: a held rat asks every frame *whose* hand it is in and
## looks the man up by his peer (`rat.gd: _follow_holder`), and a catch whose
## holder cannot be found is a catch the animal gets out of — which is right, and
## is what happens when somebody drops off the wire mid-grab. So the bench builds
## the smallest thing that answers that question: a body in the `player` group
## with a `Head/CapturePoint` under it, which is the shape `player.tscn` has and
## the only part of it the rat ever reads.
##
## The player's *script* is deliberately not on it. What is being measured is the
## rat's end of the gesture, and a real player would drag in the camera, the
## belt and the arms to measure it with.
func _boot() -> bool:
	_world = Node3D.new()
	root.add_child(_world)
	_rats = Node3D.new()
	_rats.name = "Rats"
	_world.add_child(_rats)

	var man := Node3D.new()
	man.name = "Player"
	man.add_to_group("player")
	_world.add_child(man)
	var head := Node3D.new()
	head.name = "Head"
	man.add_child(head)
	_hand = Node3D.new()
	_hand.name = "CapturePoint"
	head.add_child(_hand)
	_hand.global_position = Vector3(0.0, 1.5, 0.0)

	var scene := load(RAT_SCENE) as PackedScene
	if scene == null:
		return _fail("the rat scene did not load")
	_rat = scene.instantiate() as Node3D
	_rats.add_child(_rat)
	_rat.global_position = Vector3(0.0, 0.0, -1.0)
	return false


func _step_grab() -> bool:
	if not _rat.capture(_hand):
		return _fail("the rat refused a grab it should have taken")
	if not _rat.is_captured():
		return _fail("the rat took the grab without counting itself caught")
	_step = 1
	_waited = 0
	return false


## Hammered until it gives. The rise has to finish first — a rat killed mid-air
## reaches the hand in one go (`die_in_hands`), which is a case worth having but
## not the one this bench is measuring.
func _step_kill() -> bool:
	_waited += 1
	if not _rat.is_in_hand():
		if _waited > PATIENCE:
			return _fail("the rat never finished rising into the hand")
		return false

	_paid_before = _wallet_total()
	_rat.die_in_hands()
	if not _rat.is_dead():
		return _fail("the rat survived the killing squeeze")
	if not _rat.is_paid():
		return _fail("the kill paid nothing: the money should land on the burst")
	if _wallet_total() <= _paid_before:
		return _fail("the wallet did not move on a kill that says it paid")
	_step = 2
	_waited = 0
	return false


## It comes apart, inside the beat the hands were promised, and leaves a spray
## behind it.
func _step_it_comes_apart() -> bool:
	_waited += 1
	if is_instance_valid(_rat) and _rat.is_inside_tree():
		if _waited > PATIENCE:
			return _fail("the body never came apart: it is still in the tree")
		return false

	# The animal is gone. What should be standing where it was is the blood.
	var sprays := _sprays()
	if sprays.is_empty():
		return _fail("the rat burst and threw no blood")
	if sprays[0].get_child_count() == 0:
		return _fail("the spray went up with no shards in it")
	_step = 3
	_waited = 0
	return false


## And the blood clears on its own. It is the half of a burst nothing else in
## the game is watching: the rat that threw it is long gone, so a spray that
## never freed itself would pile one dead rat's worth of meshes onto the next
## for the whole of a shift.
func _step_the_blood_clears() -> bool:
	_waited += 1
	if not _sprays().is_empty():
		# A shard lives up to `LIFETIME.y` and the burst outlives its longest by
		# a hair, so a second of physics is several times over.
		if _waited > PATIENCE * 2:
			return _fail("the blood never cleared: the spray is still in the tree")
		return false
	_step = 4
	_waited = 0
	return false


## And a rat killed from a distance bleeds as well.
##
## It is a smaller thing than the burst — a blow landing rather than a body
## coming apart (`rat.gd: HIT_SPRAY`) — but it goes down the same road, and the
## road is what this checks: a second rat, killed where it stands rather than in
## a fist, still throws blood into the world.
func _step_a_blow_bleeds_too() -> bool:
	if _rat == null or not is_instance_valid(_rat):
		var scene := load(RAT_SCENE) as PackedScene
		_rat = scene.instantiate() as Node3D
		_rats.add_child(_rat)
		_rat.global_position = Vector3(2.0, 0.0, -1.0)
		return false
	_waited += 1
	# One frame of slack for the new animal to stand up before it is hit.
	if _waited < 2:
		return false
	if _waited == 2:
		_rat.take_damage(1, Vector3(4.0, 0.0, -1.0))
		if not _rat.is_dead():
			return _fail("the rat survived a blow that should have killed it")
		return false
	if _sprays().is_empty():
		return _fail("a rat killed at a distance threw no blood")
	_step = 5
	return false


## Every blood burst currently standing in the world.
##
## Found by its script rather than by a group or a name, because the burst joins
## nothing and is named nothing: it is added to the world, it runs and it frees
## itself (`blood_burst.gd`), and a bench is the only thing that ever needs to
## find one.
func _sprays() -> Array[Node]:
	var found: Array[Node] = []
	var script := load(BURST_SCRIPT)
	for child in _rats.get_children():
		if child.get_script() == script:
			found.append(child)
	return found


## What the crew is holding, in whatever the wallet counts.
##
## Reached through the tree rather than by its global name, like everything else
## a bench touches: the autoload does not exist while this file is compiled. A
## run with no wallet at all answers zero and the money checks quietly pass —
## which is right, because a bench without an economy is not the place to find
## out the economy is missing.
func _wallet_total() -> int:
	var wallet := root.get_node_or_null(^"Wallet")
	if wallet == null:
		return 0
	if wallet.has_method("balance"):
		return int(wallet.balance())
	if "money" in wallet:
		return int(wallet.money)
	return 0


func _fail(reason: String) -> bool:
	print("FAIL: %s" % reason)
	_failures += 1
	return _finish()


func _finish() -> bool:
	if _failures == 0:
		print("OK: strangled it bursts and pays, struck it bleeds, and the blood clears")
	quit(1 if _failures > 0 else 0)
	return true
