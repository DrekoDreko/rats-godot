extends SceneTree
## The fast breed: an animal a walking man never catches.
##
## Run with: godot --headless --script tests/swift_rat.gd
##
## What is under test is one promise made in three parts:
##
## - **The common rat stays catchable.** It flees at a walking man's own pace, so
##   the crew takes it by cutting corners and spends no stamina doing it.
## - **The swift rat is not.** Its flight is faster than a walk and slower than a
##   sprint, which is the only window in which the sprint key is the answer: any
##   slower and walking would do, any faster and nothing would.
## - **And the speed is the breed's, not the node's.** Two rats out of the same
##   scene, told apart only by the resource on them, run away at different
##   speeds — through `_flight_speed`, which is what the flight actually calls.
##
## The man's numbers are read off `player.gd` rather than written down here, so
## that a walk or a sprint retuned tomorrow fails this bench instead of quietly
## making the fast rat catchable at a stroll.
##
## Nothing here names a `class_name` or an autoload by its global name: a bench
## is the `MainLoop` and is compiled before either exists.

const RAT_SCENE := "res://scenes/rat.tscn"
const PLAYER_SCRIPT := "res://scripts/player.gd"
const COMMON := "res://resources/species/common_rat.tres"
const SWIFT := "res://resources/species/swift_rat.tres"

var _failures := 0


func _initialize() -> void:
	var walk := 0.0
	var sprint := 0.0
	var man := _man()
	if man == null:
		_fail("the player script did not load, so there is nobody to measure the rats against")
	else:
		walk = man.walk_speed
		sprint = man.run_speed
		man.free()
	_check(walk > 0.0 and sprint > walk, "The man walks, and sprints faster than he walks")

	var scene := load(RAT_SCENE) as PackedScene
	if scene == null:
		_fail("the rat scene did not load")
		_finish()
		return

	var common := _rat(scene, COMMON)
	var swift := _rat(scene, SWIFT)
	if common == null or swift == null:
		_finish()
		return

	# The common rat. Level with the walk is the whole of its balance: a man at
	# his ordinary pace stays with it and takes it on a corner.
	var common_flight: float = common._flight_speed(common.flee_speed)
	_close(common_flight, common.flee_speed,
		"A common rat runs at the speed the node was written with and no breed bonus")
	_check(common_flight <= walk,
		"And a walking man keeps up with it (%.2f against %.2f)" % [common_flight, walk])

	# The fast one, inside the window where the sprint is the only answer.
	var swift_flight: float = swift._flight_speed(swift.flee_speed)
	_check(swift_flight > walk,
		"A swift rat outruns a walking man (%.2f against %.2f), so he must spend stamina"
			% [swift_flight, walk])
	_check(swift_flight < sprint,
		"But not a sprinting one (%.2f against %.2f), or nobody could ever take it"
			% [swift_flight, sprint])

	# Same scene, same node, different animal: the difference came off the
	# resource and nowhere else.
	_check(swift_flight > common_flight,
		"Two rats out of one scene run at different speeds, and the breed is the only difference")
	_check(swift.flee_speed == common.flee_speed,
		"The node still owns one flight speed; the breed owns the multiple of it")

	# The startled dash is the breed's too — a fast rat that burst at the common
	# speed would be caught in the first stride and never seen to be fast.
	_check(swift._flight_speed(swift.burst_speed) > common._flight_speed(common.burst_speed),
		"And it bursts faster as well")

	# Neither animal was ever in the tree, so neither one gets freed by it.
	common.free()
	swift.free()
	_finish()


func _process(_delta: float) -> bool:
	return true


## One rat of one breed, out of the tree. Nothing here needs it to think, and a
## rat in the tree would start deciding things on its first frame.
func _rat(scene: PackedScene, species_path: String) -> Node3D:
	var species := load(species_path)
	if species == null:
		_fail("the species did not load: " + species_path)
		return null
	var rat := scene.instantiate() as Node3D
	rat.species = species
	return rat


## A bare man: his script and nothing else. The scene drags in a camera, a belt
## and a pair of arms, and all this bench wants off him is two numbers — and out
## of the tree they are the two the exports were written with, which is the pace
## the rats are balanced against.
func _man() -> Node:
	var script := load(PLAYER_SCRIPT) as GDScript
	if script == null:
		return null
	return script.new() as Node


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func _close(got: float, want: float, message: String) -> void:
	if absf(got - want) > 0.001:
		_fail("%s (got %.3f, wanted %.3f)" % [message, got, want])


func _fail(message: String) -> void:
	push_error("FAIL: " + message)
	print("FAIL: " + message)
	_failures += 1


func _finish() -> void:
	if _failures > 0:
		print("FAILED: %d" % _failures)
		quit(1)
		return
	print("OK: the common rat is caught at a walk, the swift one only at a sprint")
	quit()
