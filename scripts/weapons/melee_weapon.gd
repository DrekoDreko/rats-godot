class_name MeleeWeapon
extends Weapon
## A weapon swung at arm's length that settles the rat in one blow: the bat, and
## whatever club comes after it.
##
## It is the opposite of the hands in every way that matters. The hands are slow,
## they occupy the player, and they pay the full price of the animal; this one is
## one click, it never holds anybody down, and what it hands over is a body worth
## a fraction of the same rat (`Death.Type.CRUSHING`, 40% — see
## `scripts/economy/death.gd`). That is the whole trade the shelf is selling, and
## none of it is written here: the weapon says what death it kills with and the
## rat is the one that works out what the carcass is worth.
##
## **The swing happens whether or not there is anything in the sights.** A club
## that only moved when it was going to connect would tell the player he had
## missed before he swung, which is the one thing a club must never do — the miss
## is the game. So the gesture, the shake and the `used` signal all fire on the
## click, and only the damage waits to find a rat.
##
## Nothing here counts units: a bat is not spent by being swung. It comes out of
## the shop's catalogue like everything else (`resources/store/baseball_bat.tres`)
## and `available()` is left as the base class has it — bought once, carried for
## the rest of the shift.

@export_group("Blow")
## What death this weapon kills with, and so what the body is worth. Exported
## rather than fixed because the class is meant to carry the broom as well, and a
## broom is not a bat: the same swing at the same reach, worth a different
## fraction of the animal.
@export var death_type: Death.Type = Death.Type.CRUSHING
## How much damage one blow does. One is a kill, since a rat has one point of
## health (`rat.gd: max_health`).
@export var damage := 1
## How far the body hops as it goes. Something swung at arm's length sends the
## animal off; something that comes down on top of it does not
## (`rat.gd: take_damage`).
@export var leap := 4.0

@export_group("Feel")
## Strength of the shake the swing puts in the camera, whether or not it lands.
@export var swing_recoil := 0.55
## Extra shake on top of that when the blow actually connects, so a hit feels
## different from a miss without the two being different gestures.
@export var hit_recoil := 0.9

## What the player swings, in his own hand. It is a path into the view model
## rather than a model hanging under this node, because the bat is held by the
## arm the player can see and has to go wherever that arm goes — see
## `PlayerViewModel.set_held_item` for why that is the arm's business and not
## this file's.
##
## Empty is a weapon that swings invisibly, which is what every weapon in the
## game did before there was a model for any of them, and what the benches still
## run as.
@export var held_item := &"BaseballBat"

## The arms the player sees, which are the ones that carry the model. Looked up
## rather than exported: every weapon already hangs off the head and the view
## model already hangs off the camera, so the path between them is fixed by the
## player scene.
@onready var _view_model: PlayerViewModel = camera.get_node_or_null("ViewModel") as PlayerViewModel


## Taken out of the belt: the bat comes up in the player's hand with it.
func equip() -> void:
	super()
	if _view_model != null:
		_view_model.set_held_item(held_item)


## Put away, and so is the model. The arm is left empty rather than left holding
## a bat nobody can swing — the belt swaps weapons without telling the arm what
## the next one is, and a model that stayed would ride the hands into the next
## grab.
func unequip() -> void:
	if _view_model != null:
		_view_model.set_held_item(&"")
	super()


## One swing. The gesture is unconditional; only the damage looks for a rat.
func _use() -> void:
	var target := _rat_in_sights()
	_animate_swing()
	if _view_model != null:
		_view_model.swing()
	_add_recoil(swing_recoil if target == null else hit_recoil)
	used.emit(target != null)
	if target == null:
		return
	# `global_position` and not the camera's: the blow comes from where the
	# weapon is, and it is what the body is knocked away from. At the reach of a
	# bat the two are centimetres apart and the difference barely shows — but the
	# rat is thrown along that line, and a rat thrown from the lens flies
	# straight back down the sights instead of off to the side the swing came
	# from.
	target.take_damage(damage, global_position, death_type, leap)
