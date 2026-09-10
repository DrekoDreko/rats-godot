class_name RatStreak
extends Node3D
## A streak of rat piss on the boards: the one clue in the house that bites back.
##
## Every other clue is something to read. Droppings say which way the animals
## walk, a slit in the skirting says where they go; neither costs anything to
## stand on. A streak is read the same way — it lies along the run, pointing the
## way the animal went (`ClueManager.scatter_streaks`) — but a man who reads it
## with his boots loses flesh for it (`player.gd::take_damage`).
##
## **It is rat-sized, and that is the whole point of it.** This was a disc almost
## two metres across, which is ten times the length of the animal that made it: it
## read as level furniture rather than as something alive, and a dozen of them
## made the house look like a burst sewer rather than an infested kitchen. What is
## drawn now is three thin lines about forty centimetres long, the width of a
## couple of fingers, fanned the way a dribble fans as something walks. You step
## *on* one; you do not walk *near* one.
##
## **It hurts by distance and not by touch.** There is no `Area3D` here and no
## shape to walk into: the streak looks for the one player on this machine and
## measures. That is what the thing actually is — a mark with a smell around it —
## and it saves the house a collision layer and a shape per streak for an answer
## one subtraction gives.
##
## **What you see is exactly what hurts.** `radius` is the only number: the lines
## are modelled at `BASE_RADIUS` and scaled by the ratio on the way up (`_ready`),
## and the flesh is taken inside the same figure. A hazard drawn one size and
## applied at another is a hazard the player cannot learn.
##
## **It has to be opaque, and that is not a style choice.** Every surface in this
## game is drawn through the level shader (`shaders/level.gdshader`), hung on it by the
## applier at the root of the world — runtime-spawned nodes included
## (`PS1MaterialApplier._on_node_added`). That shader writes
## `ALPHA_SCISSOR_THRESHOLD = alpha_scissor`, and `alpha_scissor` defaults to 1, so
## **anything with alpha below 1 has every one of its fragments discarded**. The
## first version of this was a translucent disc at alpha 0.6. It was never drawn,
## on any machine, in any frame — the crew simply never found one. `_test_clues.gd`
## guards it now.
##
## **The wound is local and the streak is not.** Where the streaks are is the
## host's (`ClueManager`), and they arrive on every machine through the
## `MultiplayerSpawner` over the `Streaks` container, so all four screens have the
## same floor. What happens to a man who stands on one is his own machine's
## business: `Stock`, the wallet and the flesh are all single-player autoloads
## holding whatever belongs to whoever is sitting at this desk.
##
## Streaks do not dry. The ones the house opens with are old; a fresh one appears
## only where a sprayer has caught somebody (`rat.gd::_spray_at`), so every new
## mark on the boards was earned in an encounter rather than dripped by an animal
## nobody saw.

## How far the smell reaches, in metres across the floor, and how far the lines
## are scaled from what they were modelled at.
@export var radius := 0.35
## How long between one and the next, in seconds. Standing in it is meant to be
## survivable and stupid, not instantly fatal: it is what makes a man back out of
## a room rather than what ends his shift.
@export var tick := 1.0
## How long the poison remains after contact, including after the player leaves.
@export var poison_duration := 3.0
## Percentage of the player's maximum health removed by each application.
@export_range(1.0, 2.0, 1.0) var damage_percent := 2.0

## The lines, and the sound they make when they take a bite out of somebody.
@export var stain_path: NodePath = ^"Stain"
@export var hiss_path: NodePath = ^"Hiss"

## The radius the lines in `scenes/clues/rat_streak.tscn` are modelled at. The
## scene holds real metres — a line really is 44 cm long in the file — and this is
## what that size means, so that changing `radius` scales the drawing with the
## bite instead of the two drifting apart.
const BASE_RADIUS := 0.35

## How far up a man can be and still be standing in it. Without it a player on
## the platform overhead would be breathing a streak on the floor below.
const MAX_RISE := 1.6

@onready var _stain: Node3D = get_node_or_null(stain_path) as Node3D
@onready var _hiss: AudioStreamPlayer3D = get_node_or_null(hiss_path) as AudioStreamPlayer3D

## What is left of the wait before the next lungful, and whether a foot was on it
## last frame. See `_physics_process` for why the second one has to exist.
var _wait := 0.0
var _poison_time := 0.0


func _ready() -> void:
	add_to_group("streaks")
	_wait = tick
	if _stain != null:
		var factor := radius / BASE_RADIUS
		_stain.scale = Vector3(factor, 1.0, factor)
	_setup_audio()


## **Contact starts a short poison effect, and the effect ticks while it remains.**
##
## The order of those two matters and the old puddle had it backwards. It ran one
## clock and checked where the player was whenever the clock came up — which was
## survivable at a metre of radius, because a man crossing a two-metre disc at a
## run spent a third of a second inside it and the clock nearly always caught him.
## At thirty-five centimetres he is inside for an eighth of a second, so the same
## code would have bitten him on something like one crossing in six. A hazard that
## hurts you one time in six is not a hazard the player can learn; it is a hazard
## he thinks is broken.
##
## A quick crossing still applies the poison for a few seconds. Standing on it
## refreshes that duration, while leaving it lets the effect expire naturally.
func _physics_process(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or (player.has_method("is_dead") and player.is_dead()):
		_poison_time = 0.0
		return
	if _underfoot(player):
		_poison_time = poison_duration

	if _poison_time <= 0.0:
		return

	_poison_time = maxf(0.0, _poison_time - delta)
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = tick
	_bite(player)


## Whether that man is standing on this streak. Null, dead, or a player on the
## platform overhead all read as no.
func _underfoot(player: Node3D) -> bool:
	if player == null or not player.has_method("take_damage"):
		return false
	if player.has_method("is_dead") and player.is_dead():
		return false
	var here := player.global_position - global_position
	if absf(here.y) > MAX_RISE:
		return false
	here.y = 0.0
	return here.length() <= radius


func _bite(player: Node3D) -> void:
	var maximum := int(player.get("max_health"))
	var poison_damage := maxi(1, roundi(maximum * damage_percent / 100.0))
	player.take_damage(poison_damage)
	# Something has to say *why* the bar is draining. The health bar whitens on
	# every wound alike (`scripts/hud_health.gd`), so on its own a man walking
	# backwards out of a dark room learns only that he is being hurt. The hiss
	# comes out of the floor he is standing on, which is the answer.
	#
	# What it does *not* do is splatter his screen. That is what a spray in the
	# face does (`rat.gd::_spray_at`); this is his own boots.
	if _hiss != null:
		_hiss.play()


func _setup_audio() -> void:
	if _hiss == null:
		return
	if _hiss.stream == null:
		_hiss.stream = build_hiss()


## A short wet hiss, built rather than loaded for the same reason the rat's
## screech is (`scripts/house/house.gd::_build_rat_screech`): there is no audio in
## the project yet, and a placeholder that exists beats a placeholder that has to
## be drawn first.
##
## It is noise with the top taken off it — a running average across four samples,
## which is a one-pole low pass in three lines — under an envelope that opens fast
## and falls away. That is what a splash of something caustic sounds like and,
## more to the point, what it does not sound like is any of the dry clicks the
## rest of the game makes.
##
## Public and static because the spraying rat needs the same noise
## (`rat.gd::_spray_at`) and there is no sense in two files rolling their own
## static for the same fluid.
static func build_hiss(duration := 0.45, loudness := 70.0) -> AudioStreamWAV:
	var sample_rate := 22050
	var frames := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(frames)
	var history := [0.0, 0.0, 0.0, 0.0]
	for i in frames:
		var t := float(i) / float(frames)
		history[i % 4] = randf_range(-1.0, 1.0)
		var smoothed: float = (history[0] + history[1] + history[2] + history[3]) * 0.25
		# Opens over the first twentieth and falls away over the rest, squared so
		# the tail is a fade and not a ramp.
		var envelope := (1.0 - t) * (1.0 - t) * (1.0 if t > 0.05 else t / 0.05)
		var sample := int(roundf(smoothed * envelope * loudness))
		data[i] = sample & 0xff

	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_8_BITS
	wave.mix_rate = sample_rate
	wave.stereo = false
	wave.data = data
	return wave
