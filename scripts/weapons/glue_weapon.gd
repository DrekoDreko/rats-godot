class_name GlueWeapon
extends TrapWeapon
## The tray of rat glue, laid down the way tape is laid down.
##
## The first click pins the near end of the strip to the floor. From then on the
## strip stretches from that spot to wherever the player is pointing, and it
## follows him while he walks — the far end is his to place, and the way to place
## it is to go and stand where he wants it. The second click puts the whole run
## down and the tray is spent. Esc, or the right button, throws the run away and
## gives the tray back unspent.
##
## Between the two clicks the weapon is deliberately **not busy**. Walking is the
## entire gesture: a player pinned to `holding_speed` while stretching a strip of
## tape would be a player who cannot do the one thing the strip is asking of him.
## What it takes instead is the *belt* (`Weapon.holds_belt()`) — `1`, `2` and `Q`
## are refused mid-strip, because a strip abandoned halfway is neither on the
## floor nor back in the box.
##
## The strip catches nothing on its own and kills nothing ever
## (`scripts/traps/glue_trap.gd`). What it does is stop a rat where it stands, so
## the player can come and finish it himself, with whatever he happens to be
## carrying — and a rat finished by hand pays the full price of the animal, which
## is the whole reason to prefer glue over a mousetrap.

@export_group("Strip")
## The longest run of glue a single tray makes. Aiming past it does not stretch
## the strip any further; it simply stops following.
@export var max_length := 2.4
## The shortest run worth putting down. Two clicks in the same spot is a slip,
## not a strip, and it is turned down without spending anything.
@export var min_length := 0.25

## Where the near end of the strip is pinned, or `INVALID_POINT` with no strip
## being laid. It is the whole of this weapon's state.
var _anchor := INVALID_POINT

## Laying a strip. It is not the same question as `is_busy()` — the player walks
## the whole time he is doing it — and it is what the belt asks before letting
## him reach for something else.
func is_placing() -> bool:
	return _anchor != INVALID_POINT

## Stretching a strip holds the belt without holding the player.
func holds_belt() -> bool:
	return is_busy() or is_placing()

## Throws away a strip that was started and never finished. The tray was never
## spent — nothing leaves the box until the second click — so calling it off
## costs the player nothing but the walk.
func cancel() -> bool:
	if not is_placing():
		return false
	_anchor = INVALID_POINT
	return true

## The two beats of laying tape: pin the near end, then put the run down.
func _use() -> void:
	if Stock.count(stock_id) <= 0:
		return
	var spot := _ground_point()
	if not is_placing():
		_pin_end(spot)
		return
	_lay_strip(spot)

## The first click: the near end goes on the floor, and from here the strip
## follows the player. Nothing is spent yet.
func _pin_end(spot: Vector3) -> void:
	_animate_swing()
	used.emit(spot != INVALID_POINT)
	if spot == INVALID_POINT:
		return
	_anchor = spot

## The second click: the whole run goes down, and the tray with it.
##
## A run too short to be a strip is not put down and not paid for either — the
## anchor simply stays where it is, and the player is still laying the same strip
## he was. Only a strip that actually lands takes the tray out of the box.
func _lay_strip(spot: Vector3) -> void:
	var start := _anchor
	var end := _strip_end(spot)
	var run := end - start
	run.y = 0.0
	_animate_swing()
	if run.length() < min_length:
		used.emit(false)
		return

	used.emit(true)
	_anchor = INVALID_POINT
	# The tray is laid along its own body, from one end to the other: it sits on
	# the middle of the run, faces down it, and is stretched to its length.
	_place((start + end) * 0.5, run.normalized(), run.length())
	# Last, and on purpose: see the note on the box in `trap_weapon.gd`.
	Stock.spend_one(stock_id)

## Where the far end of the strip actually falls: where the player is pointing,
## pulled back to the length one tray makes. Aiming past the end of the tape does
## not tear off any more of it.
func _strip_end(aim: Vector3) -> Vector3:
	if aim == INVALID_POINT:
		return _anchor
	var run := aim - _anchor
	run.y = 0.0
	if run.length() > max_length:
		run = run.normalized() * max_length
	return _anchor + run

# --- The trap-to-be ---------------------------------------------------------
#
# With no strip started the ghost is a single tray sitting under the sights, the
# way the mousetrap's is. Once the near end is pinned it becomes the run itself,
# stretched between the two ends, and it stops following the sights anywhere but
# along its own length.

func _ghost_spot() -> Vector3:
	if not is_placing():
		return _ground_point()
	var end := _strip_end(_ground_point())
	return (_anchor + end) * 0.5

func _ghost_pose() -> Transform3D:
	if not is_placing():
		return super()
	var run := _strip_end(_ground_point()) - _anchor
	run.y = 0.0
	if run.is_zero_approx():
		return super()
	return Transform3D(Basis.looking_at(run.normalized(), Vector3.UP),
		Vector3(1.0, 1.0, run.length()))

## A run too short to lay reads as blocked, so the player can see the strip is
## not worth putting down before he spends the tray on it.
func _ghost_allowed() -> bool:
	# What every trap has to answer for first — the money, on the ones that cost
	# anything to put down — and then the one thing that is this weapon's own.
	if not super():
		return false
	if not is_placing():
		return true
	var run := _strip_end(_ground_point()) - _anchor
	run.y = 0.0
	return run.length() >= min_length
