class_name RatSpecies
extends Resource
## A breed of rat: what it is called, what fur it is born with and what it is
## worth.
##
## Each species is a file in `resources/species/`. A new rat in the game means
## duplicating one of those and changing the numbers — no code.
##
## For now the species only handles looks and price; what the animal can take
## and how fast it runs stay with the rat node (`rat.gd`), so that no two places
## own the same number.

@export var display_name := "Rat"
## The furs it can roll at birth. Empty leaves the model's own material alone.
@export var furs: Array[Texture2D] = []

@export_group("Reward")
## The price of the whole animal, before the death discount.
@export var base_value := 10
## How much bigger or smaller one individual can be compared to the rest of its
## species (0.15 = ±15%). At zero every one is worth the same.
@export_range(0.0, 0.5) var variation := 0.0

## What this animal, at this size, is worth killed this way. Never less than 1:
## a crushed rat is still a rat delivered.
func value(death_type: Death.Type, size := 1.0) -> int:
	return maxi(1, roundi(base_value * size * Death.multiplier(death_type)))

## The size of one individual, rolled when it is born.
func roll_size() -> float:
	if variation <= 0.0:
		return 1.0
	return randf_range(1.0 - variation, 1.0 + variation)

## One of the species' furs, or null if it has none.
func roll_fur() -> Texture2D:
	if furs.is_empty():
		return null
	return furs.pick_random()
