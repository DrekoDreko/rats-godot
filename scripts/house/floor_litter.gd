class_name FloorLitter
extends Sprite3D
## One piece of rubbish lying on the boards: a banana skin, a burst bin bag, a
## doll somebody's child left behind.
##
## **It is a sprite and not a model, and that is the look rather than a shortcut.**
## The house is drawn through the PS1 shader, where every surface is unshaded and
## snapped to a low grid; a flat billboard turning to face the camera is what that
## era did for anything too small to model, and a hundred of them cost the frame
## almost nothing. It is a `Sprite3D` for a second reason as well: the applier at
## the root of the world dresses `MeshInstance3D`s and only those
## (`PS1MaterialApplier._collect_meshes`), so a sprite keeps the transparent
## material it was given. A quad would have had its alpha scissored away and been
## invisible — the mistake `_test_clues.gd::_check_streaks_are_drawn` exists to
## catch.
##
## **Walking past it makes it move.** A piece of rubbish that never reacts is
## wallpaper; one that hops and rustles as you pass reads as a house with things
## living in it. The hop is a short arc through `BOUNCE_HEIGHT` and back, and the
## sound under it is `blood_drop` pitched right down, which stops being a drip and
## becomes something dry shifting.
##
## **It fires once per approach, not once per frame.** The trigger is an edge: it
## arms when the player leaves `trigger_radius` and only fires again on the way
## back in. A man standing still in a kitchen is not a man repeatedly startling
## the same banana skin, and a room of litter all rustling at once every frame
## would be noise rather than atmosphere.
##
## Nothing here crosses the wire. Where the litter is comes from the shift's seed
## (`scripts/house/litter_scatter.gd`), so every machine already has the same
## rubbish in the same places; the hop is a reaction to *this* screen's player and
## belongs to him alone, the same way a streak's bite does
## (`scripts/house/rat_streak.gd`).

## How close a man has to come before it stirs, in metres across the floor.
##
## Close enough that it reads as *this* piece reacting to *his* boot. It was more
## than twice this to begin with, which put the trigger a stride and a half away —
## far enough that rubbish went off while he was walking past the other side of a
## room, and with a floor of the stuff the house rustled continuously.
@export var trigger_radius := 0.55

## How far the sprite lifts at the top of the hop, and how long the whole arc
## takes. Small and quick: it is rubbish being disturbed by a passing boot, not
## something jumping.
const BOUNCE_HEIGHT := 0.12
const BOUNCE_TIME := 0.28

## How far above or below the litter a player may be and still disturb it.
## Without it a man on the landing would be startling the rubbish in the room
## below him.
const MAX_RISE := 1.4

## The dry rustle: a drip slowed until it stops sounding wet. The sound exists
## already (`audio/blood_drop.wav`) and is pitched rather than replaced, which is
## what the pitch parameter on `AudioManager.play_3d` is for.
const RUSTLE_SOUND := "blood_drop"
const RUSTLE_PITCH := Vector2(0.42, 0.58)
## Quiet, and quieter than it first was. `AudioManager` gives every world sound a
## `unit_size` of 3 and carries it 20 metres, which is right for a trap going off
## and far too generous for a crisp packet being nudged: at -12 dB a rustle two
## rooms away was as present as one underfoot. This is meant to be heard by the
## man who caused it and nobody else.
const RUSTLE_VOLUME_DB := -22.0

## Where the sprite rests, so the hop can be measured from it. Read on the way up
## rather than assumed to be zero: the scatter lifts each piece by half its own
## height so it sits on the boards instead of halfway through them.
var _rest_y := 0.0

## How far through the current hop, in seconds, or -1 while it is at rest. And
## whether the player has been away since the last one — the edge that keeps a man
## standing still from rustling the same litter for ever.
var _bounce_time := -1.0
var _armed := true


func _ready() -> void:
	add_to_group("litter")
	_rest_y = position.y


func _process(delta: float) -> void:
	_advance_bounce(delta)

	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var near := _within_reach(player)
	if near and _armed:
		_armed = false
		_stir()
	elif not near:
		_armed = true


## Whether that man is close enough to disturb this. Measured flat, like the
## streak's own reach, with the rise checked separately so a floor overhead is not
## the same room.
func _within_reach(player: Node3D) -> bool:
	var here := player.global_position - global_position
	if absf(here.y) > MAX_RISE:
		return false
	here.y = 0.0
	return here.length() <= trigger_radius


## The hop and the rustle, together. A piece already in the air is left alone:
## restarting the arc on top of itself would make it twitch rather than bounce.
func _stir() -> void:
	if _bounce_time < 0.0:
		_bounce_time = 0.0
	AudioManager.play_3d(
		RUSTLE_SOUND,
		global_position,
		RUSTLE_VOLUME_DB,
		randf_range(RUSTLE_PITCH.x, RUSTLE_PITCH.y))


## One frame of the arc. `sin` over half a turn is up and back down again with no
## corner at the top and no arithmetic to get the landing right — at the end the
## sprite is put back exactly on its rest height rather than left wherever the
## last frame's remainder landed it.
func _advance_bounce(delta: float) -> void:
	if _bounce_time < 0.0:
		return
	_bounce_time += delta
	if _bounce_time >= BOUNCE_TIME:
		_bounce_time = -1.0
		position.y = _rest_y
		return
	position.y = _rest_y + sin(_bounce_time / BOUNCE_TIME * PI) * BOUNCE_HEIGHT
