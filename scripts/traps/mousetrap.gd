class_name Mousetrap
extends Trap
## The spring trap. It snaps shut on whatever steps on it and kills it on the
## spot — and mangles it doing so, which is why what it leaves behind is worth
## three quarters of the animal (`Death.Type.TRAP`).
##
## It is the lazy half of the player's two options: it works while he is somewhere
## else entirely, and it pays less for the privilege. What it does not do is
## tidy up after itself. The body stays in it — the bar holds what it killed, and
## nothing about that changes on its own — and a dead rat left lying on the
## boards is a thing the other rats can smell from across the room. The trap
## joins the `fear` group and the floor around it empties out.
##
## So the price of setting one is paid twice, and the second half comes due
## later: three quarters of the animal at the moment it dies, and after that a
## patch of the map that no rat will walk through until the player comes back,
## stands over the mess and cleans it out. He gets the trap back for his trouble.
##
## That is the whole difference between this and the glue. The glue kills nothing
## and waits for him; this kills without him and then makes him come anyway.

## The snap. It is a number far past any rat's health on purpose: whatever the
## species turns out to be made of, the bar comes down the same way.
const BITE := 99
## How long the bar takes to come down, and how flat it leaves the trap.
const SNAP_TIME := 0.06
const SNAP_SCALE := 0.3
## The hop the body is allowed as it goes. It is nearly nothing on purpose: there
## is no leap to be had out of a rat with a steel bar across its back, and a body
## thrown clear of the trap is a body lying next to the mess instead of in it.
const SETTLE_LEAP := 0.4
## How far the smell of what is in it reaches. Smaller than the player's own
## `panic_radius`: he is a hunter and he moves, and this is neither.
const FEAR_RADIUS := 4.0
## How long the cleaned-out trap takes to leave the floor, and how flat it goes
## on the way. It is the glue tray's own gesture: the two things go for the same
## reason, and there is no sense in them going differently.
const LIFT_TIME := 0.2
const LIFT_SCALE := Vector3(1.0, 0.02, 1.0)

@onready var model: Node3D = $Model
## The face it turns to the player once there is something on it worth coming
## back for. Clean, the trap is nothing he can put his hands on — he sets it and
## walks away — so the reach is switched off until the thing goes foul.
@onready var handle: Interactable = $Handle
@onready var handle_shape: CollisionShape3D = $Handle/Reach

func _ready() -> void:
	super()
	handle_shape.disabled = true
	handle.used.connect(_on_cleaned)

func _catch_rat(rat: Node3D) -> void:
	# The claim comes before the blow. `_die()` starts the body vanishing the
	# moment the health runs out, and a carcass already on its way out cannot be
	# asked to stay.
	rat.claim_carcass(self)
	# The blow has no direction to throw the body in: it comes straight down, from
	# directly above the animal, and what it kills stays under it. That is what
	# the missing origin buys — every other weapon in the game names the place the
	# hit came from and the body leaps away from it, and a rat that leapt out of
	# the trap that killed it would leave nothing behind to come back for.
	rat.take_damage(BITE, Vector3.INF, Death.Type.TRAP, SETTLE_LEAP)
	_snap()
	_go_foul()

## The bar coming down. It is the gesture and not the model: whatever shape sits
## under `Model` — the placeholder box today, the sprung wood tomorrow — is what
## flattens, and this never has to be told which.
func _snap() -> void:
	var tween := create_tween()
	tween.tween_property(model, "scale:y", SNAP_SCALE, SNAP_TIME).set_trans(Tween.TRANS_QUAD)

## What the trap becomes once there is a dead rat in it: not a trap any more, a
## smell. Every rat in the map gives the spot a wide berth from here until
## somebody comes and cleans it out.
func _go_foul() -> void:
	add_to_group("fear")
	handle_shape.disabled = false

## How far the rats stay away. It is the one thing the `fear` group asks of
## whatever joins it (`rat.gd: _fear_spots`).
func fear_radius() -> float:
	return FEAR_RADIUS

## Cleaned out. The player stood over it long enough, and what he walks away with
## is the trap itself — bent, sprung and worth nothing until somebody puts a new
## spring in it, which is what the box charges him for the day he sets it down
## again (`scripts/weapons/mousetrap_weapon.gd`). The ground goes back to being
## ordinary ground before the thing is even off it.
##
## Scraping it off the boards costs him only the time it took. He pays for the
## parts when he asks for the parts, and not before.
func _on_cleaned(_by: Node3D) -> void:
	remove_from_group("fear")
	handle_shape.disabled = true
	monitoring = false
	# The body has been holding the floor on this trap's account. Let go of it and
	# it goes the way every other carcass goes.
	if _prey != null and is_instance_valid(_prey):
		_prey.release_carcass()
	_prey = null
	Stock.salvage(stock_id)
	var tween := create_tween()
	tween.tween_property(self, "scale", LIFT_SCALE, LIFT_TIME).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
