class_name GlueTrap
extends Trap
## The tray of glue. It kills nothing: whatever walks onto it simply stops being
## able to leave (`rat.gd: pin()`), and stays there for as long as it takes the
## player to come and finish it himself.
##
## That is the whole trade against the mousetrap. The trap works alone and hands
## back a mangled animal; the glue does half the job and hands back a rat that
## cannot run — to be strangled whole at full price, or, the day the van sells a
## broom, to be flattened with that instead. The glue has no opinion on how it
## ends. It only holds, and it hears about the ending through `released()`
## whichever ending it turns out to be.
##
## A rat left on it stays on it. Nothing here counts down and nothing lets go on
## its own: a stronger rat that tears itself loose is a rat that will do it from
## its own script, by calling `unpin()` on itself, and this tray will hear about
## that through the same door as any other ending.

## How long the spent tray takes to peel off the floor, and how flat it goes.
const PEEL_TIME := 0.25
const PEEL_SCALE := Vector3(1.0, 0.02, 1.0)

func _catch_rat(rat: Node3D) -> void:
	rat.pin(self)

## Whatever was on the tray is off it: killed where it lay, or torn off by a hand
## that came for it. Either way the glue is spent — a tray with a rat's worth of
## fur pulled off it is not catching a second one — and it peels off the floor
## and goes, leaving the boards clear.
func released(_rat: Node3D) -> void:
	# It stops watching on the way out: a tray in the middle of peeling is not
	# catching the next rat to wander over the same spot.
	_armed = false
	monitoring = false
	var tween := create_tween()
	tween.tween_property(self, "scale", PEEL_SCALE, PEEL_TIME).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
