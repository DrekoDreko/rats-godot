class_name Death
extends RefCounted
## The ways a rat can die, and how much each one ruins the goods.
##
## Whoever buys a dead rat wants the whole animal. Strangled, it arrives without
## a hole in it and without a bone out of place, and that is why the hands pay
## full price: every weapon from here on will take a bite out of it. Strangling
## is the slow job — and it is the one that pays.
##
## This class is only a table: nothing is ever instantiated from it.

## What it died of. Today the game only reaches `STRANGULATION`, which is what
## the hands do; the others are already here waiting for the weapons to come.
enum Type {
	UNKNOWN,       ## Died with no weapon claiming it: a fall, a vanishing, who knows.
	STRANGULATION, ## The hands. Whole body, unmarked fur.
	POISON,        ## Whole on the outside; it is the meat that is no good anymore.
	TRAP,          ## Died alone and stayed there, mangled by whatever held it.
	PIERCING,      ## Knife, spear, bolt: a single hole, but it is a hole.
	GUNSHOT,       ## Scattered shot, fur torn open.
	CRUSHING,      ## Hammer, shovel, boot. What is left barely reads as a rat.
}

## How much of the animal's value survives each death. Strangulation is the
## ceiling: no death pays more than the whole rat is worth.
const MULTIPLIER := {
	Type.STRANGULATION: 1.00,
	Type.POISON: 0.85,
	Type.TRAP: 0.75,
	Type.PIERCING: 0.65,
	Type.UNKNOWN: 0.50,
	Type.GUNSHOT: 0.50,
	Type.CRUSHING: 0.40,
}

## What each death is called on screen and in the test benches.
const NAMES := {
	Type.UNKNOWN: "natural causes",
	Type.STRANGULATION: "strangulation",
	Type.POISON: "poison",
	Type.TRAP: "trap",
	Type.PIERCING: "piercing",
	Type.GUNSHOT: "gunshot",
	Type.CRUSHING: "crushing",
}

## How much of the price survives this death, from 0 to 1.
static func multiplier(type: Type) -> float:
	return MULTIPLIER.get(type, MULTIPLIER[Type.UNKNOWN])

static func name_of(type: Type) -> String:
	return NAMES.get(type, NAMES[Type.UNKNOWN])
