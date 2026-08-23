extends SceneTree
## Capture test bench: walks the player up to a rat, grabs it and follows the
## rise frame by frame — how far it still is from the hand, what phase it is in
## and how the model's scale is doing. Then it runs two outcomes: a rat hammered
## until it dies — which has to be stowed at the waist, with no carcass on the
## ground — and a rat left alone, which has to get loose and go back to fleeing.
##
## Run with: godot --headless --script _test_capture.gd
##
## The third rat covers the case of the player who hammers too fast and kills the
## animal before it has finished rising.
##
## On top of that the bench checks the wallet in all three outcomes: the money
## must not land on the squeeze that kills, only when the body reaches the waist
## — and a rat that escapes pays nothing.

## Frames of slack between one step and the next.
const WAIT := 8
## Frames of patience before giving up on a step.
const LIMIT := 240
## Where the player grabs from: behind the rat, within reach of the hands.
const STATION := Vector3(0.0, 0.0, 1.6)
## Height of the aim point on the rat — the same one the weapon uses.
const TARGET_HEIGHT := 0.2

var _world: Node3D
var _player: CharacterBody3D
var _head: Node3D
var _hands: Node3D
var _point: Node3D
var _prompt: Control
var _crosshair: Control
var _frames := 0
var _step := 0
var _clock := 0
var _squeezes := 0
var _rat: Node3D
var _previous_distance := INF
var _failures := 0
## The body left the hand before finishing being stowed. It is only worth
## complaining once: without this the failure would come out repeated on every
## frame of the gesture.
var _dropped_early := false
## Rats already used by an earlier step; the freshly escaped one is still immune,
## and re-grabbing it would give a failure that belongs to the test, not the game.
var _used: Array[StringName] = []
## How the wallet stood when the current rat was grabbed, and what it is worth
## strangled — as a range, because the species may roll each animal's size.
var _money_before := 0
var _catches_before := 0
var _price: Vector2i
## The wallet comes through the tree, and not through the global name `Wallet`:
## running via `--script` the autoload enters after this script is compiled, and
## the global name does not exist yet when the bench is read.
var _wallet: Node

func _initialize() -> void:
	# Without a screen the loop would run at thousands of frames per second and
	# the whole rise would pass between two physics frames.
	Engine.max_fps = 60
	_world = load("res://scenes/world.tscn").instantiate()
	root.add_child(_world)
	_seed_rats(6)
	_player = _world.get_node("Player")
	_head = _player.get_node("Head")
	_hands = _player.get_node("Head/Hands")
	_point = _player.get_node("Head/CapturePoint")
	_prompt = _world.get_node("HUD/Strangle")
	_crosshair = _world.get_node("HUD/Crosshair")
	# The player is driven from here: no input and no gravity.
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)

func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	# The wallet is an autoload, and there is no guarantee it is already in the
	# tree during `_initialize`. Taking it here, on the first frame, is what is
	# safe.
	if _frames == 1:
		_wallet = root.get_node_or_null("Wallet")
		if _wallet == null:
			print("FAIL: the Wallet autoload is not in the tree")
			return _finish()
		_wallet.reset()
	match _step:
		0: return _grab("first")
		1: return _follow_rise()
		2: return _hammer()
		3: return _confirm_stow()
		4: return _grab("second")
		5: return _drop()
		6: return _grab("third")
		7: return _strangle_midair()
		8: return _confirm_stow()
	return _finish()

# --- Steps -----------------------------------------------------------------

func _grab(which: String) -> bool:
	if _clock < WAIT:
		return false
	# The HUD only hooks up to the player's signals after one idle frame, and
	# startup swallows several physics frames at once while the mesh bakes:
	# without this wait the first grab happened with the prompt still unhooked.
	if _player.capture_started.get_connections().is_empty():
		return false
	_rat = _closest()
	if _rat == null:
		print("FAIL: no loose rat for the %s test" % which)
		return _finish()

	_aim_at(_rat)
	_hands.try_use()
	if not _rat.is_captured():
		print("FAIL: the %s rat was not captured" % which)
		return _finish()
	_price = _price_range(_rat)
	print("--- %s rat (%s, %s, worth $%d strangled) grabbed ---" % [
		which, _rat.name, _rat.species.display_name, _price.x
	])
	_check_hud(true, "with the rat in hand")
	_used.append(_rat.name)
	_previous_distance = INF
	_squeezes = 0
	_dropped_early = false
	_money_before = _wallet.money
	_catches_before = _wallet.catches
	return _advance()

## The point of the test: the rise has to shorten the distance to the hand
## without backtracking and end with the middle of the rat's body exactly on the
## capture point — it is its middle, and not the origin down at its feet, that
## sits in the middle of the screen.
func _follow_rise() -> bool:
	var center: Vector3 = _rat.body_center()
	var distance := center.distance_to(_point.global_position)
	print("frame %2d: to the hand %.3f m, height %.2f, in hand=%s, scale %.2v" % [
		_clock, distance, _rat.global_position.y, _rat.is_in_hand(), _rat.get_node("Model").scale
	])
	# The distance may only grow during the pounce, while it is still on the
	# ground.
	if _clock > 12 and distance > _previous_distance + 0.001:
		print("FAIL: the rise backtracked (%.3f -> %.3f)" % [_previous_distance, distance])
		_failures += 1
	_previous_distance = distance

	if _rat.is_in_hand():
		if distance > 0.05:
			print("FAIL: reached the hand %.3f m off the point" % distance)
			_failures += 1
		if _rat.get_parent() != _point:
			print("FAIL: the rat did not become a child of the capture point")
			_failures += 1
		print("reached the hand in %d physics frames" % _clock)
		return _advance()
	if _clock > LIMIT:
		print("FAIL: the rise did not end within %d frames" % LIMIT)
		return _finish()
	return false

func _hammer() -> bool:
	if not _hands.is_busy():
		print("let go of the rat after %d squeezes" % _squeezes)
		return _advance()
	if _squeezes > _hands.squeezes_to_kill * 3:
		print("FAIL: %d squeezes and the rat is still in hand" % _squeezes)
		_failures += 1
		return _finish()
	_hands.press_secondary()
	_squeezes += 1
	return false

## Strangled, the rat dies on the squeeze and vanishes with the player: it goes
## limp in the hand, drops to the waist and is freed there, never going back to
## the ground.
func _confirm_stow() -> bool:
	if _clock == 1:
		# The death counts on the last squeeze, not at the end of the gesture:
		# the scoreboard must not keep counting a dead rat while the arm comes
		# down.
		if not _rat.is_dead():
			print("FAIL: the last squeeze did not kill the rat")
			_failures += 1
		if _rat.is_in_group("rats"):
			print("FAIL: the rat died but is still in the group of the living")
			_failures += 1
		# The money belongs to whoever stows it, not to whoever kills it: while
		# the arm comes down the player can still lose the body, and the wallet
		# has to sit still.
		if _wallet.money != _money_before:
			print("FAIL: the wallet went up on the death, before the rat was stowed")
			_failures += 1
		_check_hud(false, "after the death")

	if not is_instance_valid(_rat):
		var gain: int = _wallet.money - _money_before
		if gain < _price.x or gain > _price.y:
			print("FAIL: stowing paid $%d, outside the range of $%d to $%d" % [
				gain, _price.x, _price.y
			])
			_failures += 1
		if _wallet.catches != _catches_before + 1:
			print("FAIL: the rat was stowed but did not enter the catch tally")
			_failures += 1
		print("stowed %.2f s after the last squeeze, +$%d (total $%d)" % [
			_clock / 60.0, gain, _wallet.money
		])
		return _advance()

	if _rat.get_parent() != _point and not _dropped_early:
		_dropped_early = true
		print("FAIL: the body was dropped in %s instead of being stowed" % _rat.get_parent().name)
		_failures += 1
	if _clock > LIMIT:
		print("FAIL: the rat never finished being stowed")
		_failures += 1
		return _finish()
	return false

## The player who hammers too fast: every squeeze on the frame right after the
## grab, with the rat still in the air. It has to die all the same.
func _strangle_midair() -> bool:
	if _rat.is_in_hand():
		print("FAIL: the rat had already reached the hand; the tested case did not happen")
		_failures += 1
	for i in _hands.squeezes_to_kill + 2:
		_hands.press_secondary()
	if _hands.is_busy():
		print("FAIL: squeezes to spare and the rat is still in hand")
		_failures += 1
		return _finish()
	print("strangled still in the air, without ever reaching the hand")
	return _advance()

## With nothing being squeezed, the rat has to get loose on its own and go back
## to fleeing.
func _drop() -> bool:
	if _hands.is_busy():
		if _clock > LIMIT:
			print("FAIL: the rat never escaped")
			_failures += 1
			return _finish()
		return false
	if _rat.is_captured():
		print("FAIL: escaped but is still captured")
		_failures += 1
	if _rat.get_parent() == _point:
		print("FAIL: escaped but is still a child of the hand")
		_failures += 1
	if not _rat.is_in_group("rats"):
		print("FAIL: escaped but left the group of the living")
		_failures += 1
	if _wallet.money != _money_before:
		print("FAIL: the rat escaped and paid $%d all the same" % [_wallet.money - _money_before])
		_failures += 1
	_check_hud(false, "after the escape")
	print("escaped in %.2f s, back in the world under %s" % [_clock / 60.0, _rat.get_parent().name])
	return _advance()

# --- Utilities -------------------------------------------------------------

## Between what values this rat can pay, strangled. It is a range and not a
## number because the species may roll each individual's size; with the variation
## at zero both ends are the same number.
func _price_range(rat: Node3D) -> Vector2i:
	var species: RatSpecies = rat.species
	return Vector2i(
		species.value(Death.Type.STRANGULATION, 1.0 - species.variation),
		species.value(Death.Type.STRANGULATION, 1.0 + species.variation)
	)

## Puts the player behind the rat and points body and head at it, so the rat
## falls inside the reach and the cone of the hands.
func _aim_at(rat: Node3D) -> void:
	var target := rat.global_position + Vector3.UP * TARGET_HEIGHT
	_player.global_position = rat.global_position + STATION
	_player.look_at(Vector3(target.x, _player.global_position.y, target.z), Vector3.UP)
	_player.rotation.x = 0.0
	_player.rotation.z = 0.0
	var eye := _head.global_position
	_head.rotation.x = atan2(target.y - eye.y, Vector2(target.x - eye.x, target.z - eye.z).length())

## The strangling prompt and the crosshair take turns: one appears exactly when
## the other goes away. It also checks that the `crosshair` exported in
## `world.tscn` arrived hooked up.
func _check_hud(holding: bool, when: String) -> void:
	if _prompt.visible != holding:
		print("FAIL: the strangling prompt should be %s %s" % ["visible" if holding else "hidden", when])
		_failures += 1
	if _crosshair.visible == holding:
		print("FAIL: the crosshair should be %s %s" % ["hidden" if holding else "visible", when])
		_failures += 1

func _advance() -> bool:
	_step += 1
	_clock = 0
	return false

func _finish() -> bool:
	print("--- %d frames, %d failure(s) ---" % [_frames, _failures])
	return true

func _closest() -> Node3D:
	var best: Node3D = null
	var smallest := INF
	for node in get_nodes_in_group("rats"):
		var rat := node as Node3D
		if rat.name in _used:
			continue
		var distance := _flat(rat.global_position, _player.global_position)
		if distance < smallest:
			smallest = distance
			best = rat
	return best

func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The world scene is the survey/hunt map now, so it ships with no rats: the host
## spawns them from the contract when the hunt starts. A bench that needs loose
## rats to grab puts its own out, which is also what keeps it from depending on
## where the level dressing happened to leave them.
func _seed_rats(count: int) -> void:
	var packed := load("res://scenes/rat.tscn") as PackedScene
	if packed == null:
		return
	var rats := _world.get_node_or_null("Rats")
	if rats == null:
		rats = Node3D.new()
		rats.name = "Rats"
		_world.add_child(rats)
	for i in count:
		var rat := packed.instantiate() as Node3D
		rats.add_child(rat)
		rat.name = "TestRat_%d" % (i + 1)
		rat.global_position = Vector3(-2.0 + float(i) * 2.0, 0.1, 12.0)
