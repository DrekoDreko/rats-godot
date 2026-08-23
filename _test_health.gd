extends SceneTree
## Health test bench: the flesh the player carries and the bar over the belt
## that shows it.
##
## Run with: godot --headless --script _test_health.gd
##
## What is checked here is that the two never drift apart — the count lives in
## the player and the bar only mirrors it — and the three things the bar does on
## its own: the colour of each stage of the beating, the whitening of a fresh
## wound, and leaving the screen with the hotbar when there is a rat in hand.
##
## The bar carries no number beside it, so how far it has drained (`value`,
## from 0 to 1) is the whole of what the player is told.

## Frames of slack between one step and the next.
const WAIT := 8
## Frames long enough for the flash of a wound to burn out (0.25 s at 60 fps).
const AFTER_FLASH := 20
## Where the player grabs from: behind the rat, within reach of the hands.
const STATION := Vector3(0.0, 0.0, 1.6)
## Height of the aim point on the rat — the same one the weapon uses.
const TARGET_HEIGHT := 0.2

var _world: Node3D
var _player: CharacterBody3D
var _head: Node3D
var _inventory: Node
var _bar: ProgressBar
var _hotbar: Control
## Where the player was put in the map, which is the spot `respawn()` takes him
## back to. It is read from the scene and not from the running body: in the
## first frames a body settles on the floor, and by the time the bench asks it
## has already sunk a millimetre into it.
var _start: Vector3
var _deaths := 0
var _frames := 0
var _step := 0
var _clock := 0
var _failures := 0

func _initialize() -> void:
	# Without a screen the loop would run at thousands of frames per second and
	# the flash of a wound would pass between two physics frames.
	Engine.max_fps = 60
	_world = load("res://scenes/world.tscn").instantiate()
	root.add_child(_world)
	_seed_rats(4)
	_player = _world.get_node("Player")
	_head = _player.get_node("Head")
	_inventory = _player.get_node("Head/Inventory")
	_bar = _world.get_node("HUD/Health")
	_hotbar = _world.get_node("HUD/Hotbar")
	_start = _player.position
	_player.died.connect(func() -> void: _deaths += 1)
	# The player is driven from here: no input and no gravity.
	_player.set_physics_process(false)
	_player.set_process_unhandled_input(false)

func _physics_process(_delta: float) -> bool:
	_frames += 1
	_clock += 1
	match _step:
		0: return _check_start()
		1: return _check_wound()
		2: return _check_stages()
		3: return _check_heal()
		4: return _check_death()
		5: return _check_hidden_while_busy()
	return _finish()

# --- Steps -----------------------------------------------------------------

## The shift starts whole: the player at his full flesh and the bar reading it
## without anyone having had to announce anything.
func _check_start() -> bool:
	if _clock < WAIT:
		return false
	# The bar only hooks up to the player's signals after one idle frame.
	if _player.health_changed.get_connections().is_empty():
		return false
	print("--- the player starts with %d health ---" % _player.max_health)
	_expect(_player.health() == _player.max_health, "the shift should start at full health")
	_expect(not _player.is_dead(), "a whole player is not a dead one")
	_expect(is_equal_approx(_player.health_fraction(), 1.0), "the whole flesh should read as 1.0")
	_expect(is_equal_approx(_bar.value, 1.0), "the bar should start full")
	_expect(_bar.visible, "the bar should be on screen from the start")
	return _advance()

## A wound: the count drops, the number and the bar follow it in the same frame
## and the bar whitens for an instant.
func _check_wound() -> bool:
	if _clock < WAIT:
		return false
	_player.take_damage(50)
	_expect(_player.health() == 50, "50 damage should leave 50 health")
	_expect(is_equal_approx(_bar.value, 0.5), "the bar should follow the wound at once")
	_expect(_bar.modulate.r > 0.9 and _bar.modulate.g > 0.9, "a fresh wound should whiten the bar")

	_player.take_damage(0)
	_player.take_damage(-10)
	_expect(_player.health() == 50, "a wound of nothing should take nothing")
	return _advance()

## The three stages of the beating: whole, hurt, and about to go out. The colour
## is read after the flash, which is what covers it while it lasts.
func _check_stages() -> bool:
	if _clock < AFTER_FLASH:
		return false
	_expect(_is_color(_bar.modulate, _bar.HURT_COLOR), "half a player should read as hurt")
	_player.take_damage(30)
	_expect(_player.health() == 20, "the wounds should add up")
	_expect(is_equal_approx(_bar.value, 0.2), "a fifth of a player should leave a fifth of a bar")
	_expect(_bar.is_processing(), "about to go out, the bar should breathe")
	return _advance()

## Bandages: they go up to the flesh the shift started with, and no further.
func _check_heal() -> bool:
	if _clock < AFTER_FLASH:
		return false
	_expect(_is_color(_bar.modulate, _bar.CRITICAL_COLOR), "a fifth of a player should read as critical")
	_expect(_bar.modulate.a < 1.0, "the breathing should dim the bar as it goes")

	_player.heal(30)
	_expect(_player.health() == 50, "the bandage should give back what it is worth")
	_player.heal(999)
	_expect(_player.health() == _player.max_health, "healing should stop at the full flesh")
	_expect(is_equal_approx(_bar.value, 1.0), "the bar should follow the bandage")
	_player.heal(10)
	_expect(_player.health() == _player.max_health, "a whole player cannot be healed further")
	return _advance()

## Death: it announces itself, sends the player back to where the shift started
## and stands him up whole — and the bar goes back to full along with him.
func _check_death() -> bool:
	if _clock < AFTER_FLASH:
		return false
	_expect(not _bar.is_processing(), "healed, the bar should stop breathing")
	var wallet: Node = root.get_node_or_null("Wallet")
	var money_before: int = wallet.money
	# Read where he actually starts rather than where he stood at setup: the map's
	# `HouseSpawns` puts him on a front-door marker a frame later, and that spot —
	# not the one baked into the scene — is what a respawn brings him back to.
	_start = _player.spawn_point()
	_player.global_position = _start + Vector3(4.0, 0.0, 4.0)
	_player.take_damage(999)
	_expect(_deaths == 1, "running out of flesh should announce a death")
	_expect(not _player.is_dead(), "the dead player should be back on his feet at once")
	_expect(_player.health() == _player.max_health, "he should come back whole")
	_expect(_player.global_position.is_equal_approx(_start), "he should come back where the shift started")
	_expect(is_equal_approx(_bar.value, 1.0), "the bar should come back full")
	_expect(wallet.money == money_before, "dying should not touch what was earned")
	return _advance()

## With a rat in hand the bar leaves the screen, and for the same reason the
## hotbar does: it is over the slots that it sits, and that is where the
## strangling prompt opens.
func _check_hidden_while_busy() -> bool:
	if _clock < WAIT:
		return false
	var rat := _closest()
	if rat == null:
		print("FAIL: no loose rat for the capture test")
		return _finish()
	_aim_at(rat)
	_inventory.try_use()
	if not rat.is_captured():
		print("FAIL: the rat was not captured with the hands out")
		return _finish()
	_expect(not _bar.visible, "the bar should leave the screen with the rat in hand")
	_expect(not _hotbar.visible, "the hotbar should leave the screen with it")

	var hands: Node = _inventory.current()
	var squeezes: int = hands.squeezes_to_kill + 2
	for i in squeezes:
		_inventory.press_secondary()
	if _inventory.is_busy():
		print("FAIL: the rat did not die after %d squeezes" % squeezes)
		return _finish()
	_expect(_bar.visible, "the bar should come back once the hands are empty")
	return _advance()

# --- Tools -----------------------------------------------------------------

func _expect(condition: bool, what: String) -> void:
	if condition:
		return
	print("FAIL: %s" % what)
	_failures += 1

## The same colour, alpha aside — the breathing of a critical bar is written
## there, and it is checked on its own.
func _is_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01

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
