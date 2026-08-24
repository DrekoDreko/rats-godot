class_name Trap
extends Area3D
## Something the player leaves on the floor for the rats to walk into.
##
## A trap is an `Area3D` and nothing more: it does not move, it does not think,
## and it has no body to be bumped into. It watches the rats' layer, and the
## first rat to step inside it is the one it does something to — what, is
## `_catch_rat()`'s business, and it is the only thing that changes from one trap
## to the next.
##
## What every trap has in common is that it is *used up*. It catches one rat and
## it is over: the mousetrap goes off, the glue holds what it caught until
## somebody comes for it, and neither of them is ever going to catch a second
## one.
##
## A trap is deliberately **not** in the `scenery` group. The navigation mesh is
## baked from that group (`scripts/navigation.gd`), and a trap that joined it
## would be baked into the floor as an obstacle — the rats would route politely
## around every trap the player ever set, which is exactly the opposite of the
## point of setting one.
##
## What a trap may do, once it has caught something and is holding on to it, is
## join the `fear` group: the rats then give that patch of floor a wide berth
## until somebody comes and clears it (`scripts/traps/mousetrap.gd`). That is a
## preference and not geometry, which is the whole difference — the flight can
## still cross bad ground when there is nowhere else to go.
##
## **The catch belongs to the host.** The trap itself crosses the wire — it is
## put down by the host and carried to everybody by the `MultiplayerSpawner` over
## `Traps` (`scripts/session/trap_manager.gd`) — and so the same trap exists on
## every machine with the same rat walking towards it. Two machines both deciding
## that rat was caught is one animal counted twice, one carcass claimed twice and
## two springs going off. So only the machine that thinks for the rats decides
## anything here, and the others are told: `_on_body_entered` returns on a guest
## before it has looked at what walked in, and what actually fires the trap on
## every machine at once is `_fire`.
##
## It is the same rule the rats already keep for themselves — `rat.gd` refuses to
## take damage or be picked up anywhere but on its authority — and it is kept
## here for the same reason: the money and the tally are the host's.

## Caught something. `rat` is whatever walked in.
signal caught(rat: Node3D)

## Who set it. Written by the host before the trap enters the tree
## (`TrapManager._spawn`), so it crosses with the node and every machine agrees
## whose trap this is. Zero for one that nobody put down — a trap placed straight
## into a scene by a test bench.
##
## Nothing pays out on it yet: the tally is still the host's single wallet
## (`scripts/economy/wallet.gd`). It is written now because the moment a catch
## has to credit the man who set the trap rather than the man who owns the
## machine, this is the only thing that can answer — and it costs nothing to have
## been carrying it since the trap went down.
@export var placed_by := 0

## Which box in the van this came out of (`scripts/economy/stock.gd`), so a trap
## that ends up back in the player's hands knows where to put itself. It is the
## same string the weapon that sets it carries in its `stock_id`, and it is set
## on the scene rather than written into the script so the two never drift apart
## in two files.
@export var stock_id := ""

## Only the rats set a trap off (layer 3).
const RAT_MASK := 4

## Still waiting for something. A trap that has caught its rat is furniture.
var _armed := true
## What it caught, for as long as it still holds it.
var _prey: Node3D

func _ready() -> void:
	add_to_group("traps")
	# Nothing collides *with* a trap: it is a patch of floor that notices things,
	# and the player walks over it without feeling it.
	collision_layer = 0
	collision_mask = RAT_MASK
	monitoring = true
	body_entered.connect(_on_body_entered)

## Whether this trap is still waiting for a rat.
func is_armed() -> bool:
	return _armed

## What it is holding, or null. Only the traps that *hold* anything ever have one.
func prey() -> Node3D:
	return _prey

## A rat stepped on it — on *this* machine. Whether that is a catch is not this
## machine's to say unless it is the one holding the trap: a guest's `Area3D`
## fires on its own drawn copy of a rat that the host may already have seen go
## somewhere else, and a guest that acted on it would spring a trap the host
## still has armed.
##
## So the guest looks and does nothing. The host looks, decides, and says so
## (`_fire`), and the guest's trap goes off when that lands — which is a frame or
## two later and is the only honest answer available: the alternative is two
## machines each counting the same rat.
func _on_body_entered(body: Node3D) -> void:
	if not is_multiplayer_authority():
		return
	if not _armed or not body.is_in_group("rats"):
		return
	# A body already spoken for is nobody's catch: one that died on its way here,
	# and one being carried over the trap in somebody's hand.
	if body.has_method("is_dead") and body.is_dead():
		return
	if body.has_method("is_captured") and body.is_captured():
		return
	# Disarmed here and not only in `_fire`: the announcement is a round trip away
	# and the area goes on reporting bodies the whole time. Without this a second
	# rat walking in next frame is a second catch announced for a trap that has
	# already caught one.
	_armed = false
	if _on_the_wire():
		_fire.rpc(_path_of(body))
	else:
		_fire(_path_of(body))


## The catch, run on every machine at once, the host included (`call_local`).
## This is where a trap actually goes off, and it is the only place — `_armed`,
## the prey and `_catch_rat` are written here and nowhere else.
##
## The rat travels as its **path** rather than as a node, because a node cannot
## cross a wire. It is the path under the `Rats` container, which is the same on
## every machine precisely because `house.gd` names the animals before it adds
## them.
##
## A path that resolves to nothing is a rat that has already gone on this
## machine — freed, or not yet delivered by its own spawner. The trap still
## disarms, because on the host it certainly caught something and a trap that
## re-armed itself here would be a trap that catches a second rat on one screen
## and not on the others.
@rpc("authority", "call_local", "reliable")
func _fire(rat_path: NodePath) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		push_warning("Trap: a catch from peer %d, which does not own this trap — ignored."
			% sender)
		return
	_armed = false
	var body := get_node_or_null(rat_path) as Node3D
	if body == null:
		return
	_prey = body
	_catch_rat(body)
	caught.emit(body)


## A rat's path, as something that can be put in a packet. Relative to this trap,
## so that it resolves against the same tree on the machine that reads it.
func _path_of(body: Node3D) -> NodePath:
	return get_path_to(body)


## Whether there is anybody to say it to. An `rpc` with no wire under it is an
## error in the log for a call that would have run here anyway — the same
## question the session autoloads ask before their own announcements.
func _on_the_wire() -> bool:
	if not multiplayer.has_multiplayer_peer():
		return false
	return not multiplayer.multiplayer_peer is OfflineMultiplayerPeer

## What this trap does to what it caught. Every trap overrides this.
func _catch_rat(_rat: Node3D) -> void:
	pass

## The rat this trap was holding is gone — killed on it, or torn off it by hand.
## It is the door `rat.gd: unpin()` knocks on, and only a trap that *holds*
## something has anything to do about it.
func released(_rat: Node3D) -> void:
	pass
