class_name HuntTime
extends RefCounted
## How long the crew gives itself in the house, and what that costs them.
##
## The hunt is the one phase whose clock the crew sets rather than reads. A long
## shift is a comfortable one — every hole checked twice, every trap collected —
## and it pays what the rats are worth and nothing more. A short one is a gamble:
## the same house, the same animals, five times the money and two minutes to get
## it, with whatever is still loose when the clock runs out left in the walls.
##
## **The wager is the whole point.** A crew that always picks ten minutes is a
## crew that never loses and never earns; one that always picks two is a crew
## that comes home with an empty van. The interesting choice is the one made
## against a contract already read — a low infestation is a two-minute job, a
## house with forty rats in it is not — which is why this is picked on the
## clipboard, next to the sheet that says how bad the house is.
##
## **What the multiplier touches is the rats and nothing else.** It is applied
## where an animal is paid for (`Wallet.collect`), after the species price and
## the death discount, so a strangled rat in a two-minute shift is worth five
## strangled rats in a ten-minute one. The contract's own `reward` is not
## multiplied: the client pays what the client agreed to pay, whatever hurry the
## crew was in.
##
## This class is only a table: nothing is ever instantiated from it. It sits
## apart from `SessionManager`, which stores the choice, and from `PhaseManager`,
## which runs the clock off it, for the same reason `Phase` does — neither of
## them should have to load the other to name a setting.

## The three lengths a hunt can be booked at. `LONG` is the default because it is
## the one that cannot go badly: a crew that has never seen the house before
## should not have its first shift be the five-times gamble.
enum Type {
	LONG,   ## Ten minutes at face value.
	MEDIUM, ## Five minutes at double.
	SHORT,  ## Two minutes at five times.
}

## How long each setting runs, in seconds.
const DURATION := {
	Type.LONG: 600.0,
	Type.MEDIUM: 300.0,
	Type.SHORT: 120.0,
}

## What every rat delivered is multiplied by. Whole numbers on purpose: a crew
## reading "x5" on a clipboard should be able to do the sum in its head, which is
## the only way the wager gets made deliberately rather than guessed at.
const MULTIPLIER := {
	Type.LONG: 1.0,
	Type.MEDIUM: 2.0,
	Type.SHORT: 5.0,
}

## What each setting is called on screen and in the test benches.
const NAMES := {
	Type.LONG: "long",
	Type.MEDIUM: "medium",
	Type.SHORT: "short",
}

## The settings in the order they are leafed through, longest first — the same
## order they are written on the sheet, so that pressing right on the clipboard
## always moves towards the gamble.
const ORDER: Array[Type] = [Type.LONG, Type.MEDIUM, Type.SHORT]

## What a shift is booked at before anybody has changed it.
const DEFAULT := Type.LONG


## How long this hunt runs, in seconds.
static func duration(type: Type) -> float:
	return DURATION.get(type, DURATION[DEFAULT])


## What a rat delivered in this hunt is multiplied by.
static func multiplier(type: Type) -> float:
	return MULTIPLIER.get(type, MULTIPLIER[DEFAULT])


static func name_of(type: Type) -> String:
	return NAMES.get(type, NAMES[DEFAULT])


## The setting as the crew reads it: "10:00  x1". Both halves of the wager in one
## line, because neither of them means anything without the other.
static func label_of(type: Type) -> String:
	return "%s  x%d" % [clock_of(type), int(multiplier(type))]


## The length as a clock reads it, `M:SS` — the same shape the HUD counts down
## in, so that what was picked in the van and what is ticking in the house are
## plainly the same number.
static func clock_of(type: Type) -> String:
	var whole := int(duration(type))
	@warning_ignore("integer_division") # Whole minutes: the remainder is the seconds beside it.
	return "%d:%02d" % [whole / 60, whole % 60]


## The setting after this one, wrapping round the end of the list. `step` is +1
## or -1, which is how the clipboard's two arrows leaf through the three.
static func step(type: Type, direction: int) -> Type:
	var at := ORDER.find(type)
	if at == -1:
		return DEFAULT
	return ORDER[wrapi(at + direction, 0, ORDER.size())]


## Whether a value is one of the three. It is asked of anything that arrives off
## the wire, so that a packet from a machine with a different build cannot book a
## shift at a length nobody here has a duration for.
static func is_valid(type: int) -> bool:
	return DURATION.has(type)
