class_name PendingStation
extends Interactable
## A station that is bolted to the wall of the van and does not work yet.
##
## The lobby van (card 05) has three fittings in it: the colour panel, the
## contract clipboard and the ready board. Only the last of those has been
## written — the other two are cards 06 and 08 — and the question is what to put
## in their places in the meantime.
##
## Leaving the wall bare is the wrong answer. The card asks for a van a crew can
## walk around and find its way about, and the arrangement of the thing — what
## is on which wall, how far apart, whether two people can stand at two
## different stations without being in each other's way — is exactly what cannot
## be judged from an empty box. So the fittings go in now, at their real size and
## in their real places, and each one says what it will be.
##
## What it does when used is say so, out loud and once: the prompt reads the
## station's name, and pressing it prints a line and plays the refusal sound. It
## is deliberately not a silent no — a player pressing `E` on a panel and getting
## nothing back cannot tell a station that is not finished from a key that is not
## working.
##
## **Replacing one is meant to be easy.** When card 06 lands, the colour panel's
## script changes from this to the real one and the geometry stays where it is;
## nothing else in `lobby_van.tscn` has to move. That is why the panel is
## dressed here rather than in the van scene — the swap is one line, not a
## re-lay-out.

## What this will be, once its card is written. It goes into the log line so that
## a player pressing an unfinished panel is told which one it was.
@export var station_name := "station"

## What card finishes it, for the same reason.
@export var card := ""

## The lamp over the panel, if it has one. Dimmed on purpose: an unfinished
## fitting should read as switched off rather than as broken.
@export var lamp_path: NodePath = ^"Lamp"

## The refusal. Optional, like every other sound in the van — there is no audio
## in the project yet and a station has to work without it.
@export var refused_sound_path: NodePath = ^"Refused"

## How dim the lamp burns while the station is not finished.
const LAMP_ENERGY := 0.25

@onready var _lamp: OmniLight3D = get_node_or_null(lamp_path) as OmniLight3D
@onready var _refused_sound: AudioStreamPlayer3D = \
	get_node_or_null(refused_sound_path) as AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("pending_station")
	if _lamp != null:
		_lamp.light_energy = LAMP_ENERGY


## Hands on a panel that is not wired up yet. It answers rather than doing
## nothing, so that the player knows the panel heard him.
func use(by: Node3D) -> void:
	super.use(by)
	if _refused_sound != null and _refused_sound.stream != null:
		_refused_sound.play()
	print("%s is not fitted yet (%s)." % [station_name, card])
