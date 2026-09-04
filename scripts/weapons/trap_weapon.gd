class_name TrapWeapon
extends Weapon
## A weapon that runs out and leaves something behind: it comes out of a box
## bought at the computer, and every use takes one out of the box and puts it on
## the floor.
##
## What it has that the hands do not is a *count*. The box lives in the `Stock`
## autoload under `stock_id`, the same string the catalogue item carries
## (`scripts/economy/store_item.gd`), so buying and spending never have to know
## about each other: the shop credits the id and the belt and the hotbar follow
## the signal. Empty, the weapon says it is not available and its slot goes back
## to being an empty loop on the belt.
##
## What it adds is *aiming at the floor*. Every other weapon in the game looks
## for an animal — the cone around the sights in `Weapon._rat_in_sights()` — and
## a trap is the one thing that looks for ground instead: a short ray out of the
## camera, and the flat spot it lands on. It also carries the ghost, the
## trap-to-be that follows that spot around while the weapon is out, because both
## traps need one and neither needs a different one.
##
## What each trap does with that spot is `_use()`'s business, and it is the only
## thing that changes between the box of mousetraps
## (`scripts/weapons/mousetrap_weapon.gd`) and the tray of glue
## (`scripts/weapons/glue_weapon.gd`). This class never goes on a node by itself.
##
## **What it does not do is put anything on the floor.** It used to: `_place()`
## instantiated the scene and added it, and the trap existed on the machine of
## whoever clicked and on no other. Now it *asks*
## (`scripts/session/trap_manager.gd`), the host checks it and the host puts it
## down, and it arrives here through the same `MultiplayerSpawner` it arrives
## through on everybody else's machine. The unit comes out of the box on the
## host's word too, which is why nothing here spends one.
##
## So a click is a request and not an event, and the two things that follow it —
## the swing, and the `used` signal the HUD beeps off — are this machine saying
## *the gesture happened*, not *the trap is down*. That is the honest reading of
## a click whose answer is still on the wire, and it is why they are still fired
## the moment the button goes down.
##
## The **ghost** never crosses. It is this machine's drawing of what the player
## is about to ask for, it hangs outside the replicated container
## (`_ghost_root`), and nobody else has any business seeing it.

## The key of the box this weapon comes out of.
@export var stock_id := ""

@export_group("Placing")
## What gets left on the floor.
@export var trap_scene: PackedScene
## How far along the sights a trap can be set down. It is the length of the ray
## and not a distance across the floor, and that is what makes the number look
## large: the player's eyes are 1.6 m up, so the ray has already spent most of
## its length getting down to the boards before it has gone anywhere at all.
##
## The number is picked from the angle it costs the player, not from the distance
## it buys him. A ray of length `r` from eyes `h` up only reaches the floor once
## the head is tipped `asin(h / r)` — so 4.5 m, which is what this was, demands
## nearly twenty-one degrees before a single trap will go down. That is not a
## glance at the floor; it is staring at your own boots, and looking level at the
## room in front of you showed no trap-to-be at all. At 8 m the same tip is 11.5
## degrees, which is what a player actually does when he means "there, in front
## of me". What it buys — a little under 8 m of floor — is then clipped back to
## `max_floor_distance` so the extra reach is angle and not range.
@export var place_range := 8.0
## The furthest across the floor a trap will actually land, measured from the
## player's own feet. `place_range` is spent on the *angle* — it is what lets the
## player look at the floor rather than at his boots — and this is what keeps the
## slack from turning into a trap set halfway across the room. Beyond it the ray
## still finds floor and the ghost simply stops following, the way the glue stops
## stretching at `max_length`.
@export var max_floor_distance := 4.0
## What it costs to set down one that came back off the floor. A trap scraped out
## from under a dead rat is bent, and the box will not arm it again for nothing:
## the money goes at the moment it is set down, and the price hangs over the
## ghost until then (`_price_tag`).
##
## It is charged on the salvaged ones only. What the player bought at the
## computer he has already paid for, and it goes down free.
@export var salvage_fee := 0

## Only the floor and the walls take a trap (layer 1).
const GROUND_MASK := 1
## Steepest floor a trap will sit on, as the upward part of the surface's normal.
## Past this it is a wall, and nothing is going to balance on it.
const MAX_SLOPE := 0.7
## How far off the floor a trap sits, so it is not buried in the boards.
const FLOOR_LIFT := 0.01
## How see-through the trap-to-be is.
const GHOST_ALPHA := 0.45
## What the ghost is tinted while the spot is good, and while it is not.
const GHOST_COLOR := Color(0.6, 1.0, 0.6)
const GHOST_BLOCKED_COLOR := Color(1.0, 0.4, 0.35)
## How high over the ghost the price hangs, and how big it is written. The size
## is in metres per pixel, the way `Label3D` counts: the number is small because
## the thing it is standing on is the size of a hand.
const PRICE_HEIGHT := 0.28
const PRICE_PIXEL_SIZE := 0.004
const PRICE_FONT_SIZE := 48
const PRICE_OUTLINE := 12
## Nowhere: what the ground ray gives back with no floor in range. Spelled the
## way `rat.gd` spells it.
const INVALID_POINT := Vector3.INF

## The trap-to-be that follows the sights around. It is built the first time the
## weapon needs one and thrown away when the weapon is put back.
var _ghost: Node3D
## The price hanging over it, on the ones that have a price. It is a child of the
## ghost and goes when the ghost goes.
var _price_tag: Label3D

## There is a weapon here for as long as there is one left in the box.
func available() -> bool:
	return not stock_id.is_empty() and Stock.count(stock_id) > 0


## Traps are tactical equipment placed on the floor; permitted in the SURVEY phase.
func is_attack_weapon() -> bool:
	return false

## Cooldown duration for arming/placing a trap during the HUNT phase (Card 13).
## Taking time to place a trap when rats are loose requires more deliberate arming.
@export var hunt_cooldown := 1.8

## Returns the phase-aware cooldown: longer during HUNT when rats are loose.
func get_cooldown() -> float:
	if PhaseManager.current() == Phase.Type.HUNT:
		return hunt_cooldown
	return cooldown

## Put away. Everything this weapon had going out in the world stops here — the
## ghost comes off it, and whatever was half-placed is called off. It matters
## more than it looks: the belt calls this by itself the moment the last unit
## leaves the box, so a half-drawn strip of glue has to die on this line.
func unequip() -> void:
	cancel()
	_clear_ghost()
	super()

func _process(delta: float) -> void:
	super(delta)
	_update_ghost()

# --- Aiming at the floor ----------------------------------------------------

## Where the player is pointing on the floor, or `INVALID_POINT` with nothing
## flat enough in range. It is the whole of a trap's aiming: the cone the other
## weapons use is looking for animals, and this is looking for ground.
func _ground_point() -> Vector3:
	var origin := camera.global_position
	var to := origin - camera.global_basis.z * place_range
	var params := PhysicsRayQueryParameters3D.create(origin, to, GROUND_MASK, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if hit.is_empty():
		return INVALID_POINT
	if (hit.normal as Vector3).y < MAX_SLOPE:
		return INVALID_POINT
	var spot := (hit.position as Vector3) + Vector3.UP * FLOOR_LIFT
	# The reach across the boards is the player's arm, not the ray's length: the
	# ray is long so that looking at the floor is a glance and not a stoop, and
	# without this that same length would also let him set a trap on the far side
	# of the room. Aiming past the limit puts the trap down at the limit, which is
	# how the glue already treats a strip stretched too far.
	var reach := spot - player.global_position
	reach.y = 0.0
	if reach.length() > max_floor_distance:
		spot = player.global_position + reach.normalized() * max_floor_distance
		spot.y = (hit.position as Vector3).y + FLOOR_LIFT
	return spot

# --- The price of what is going down ----------------------------------------

## Whether the next one out of the bag is going to cost anything to set down.
func _next_costs() -> bool:
	return salvage_fee > 0 and Stock.next_is_salvaged(stock_id)

## What the next one costs, or zero when it is one of the ones already paid for.
func _next_fee() -> int:
	return salvage_fee if _next_costs() else 0

## Whether the player can cover what he is about to put down. A bought trap is
## always affordable: it costs nothing.
func _can_afford() -> bool:
	return not _next_costs() or Wallet.money >= salvage_fee

## Takes the fee, if there is one. Returns false when the money is not there, and
## in that case nothing is spent and nothing should be placed.
func _charge() -> bool:
	if not _next_costs():
		return true
	return Wallet.spend(salvage_fee)

## Which way the player is facing, flattened. It is what a trap set on the floor
## is turned to: the animal comes at it from wherever it likes, but the player
## still put it down the way he was standing.
func _facing() -> Vector3:
	var forward := -player.global_basis.z
	forward.y = 0.0
	return Vector3.FORWARD if forward.is_zero_approx() else forward.normalized()

## Where the ghost hangs. **Not** the `Traps` container: that one is under a
## `MultiplayerSpawner` (`scripts/session/trap_manager.gd`), and anything added
## to it is replicated to every machine in the game — which is the last thing a
## translucent trap-to-be following one man's sights around should be. So the
## ghost goes beside it, on whatever the player himself hangs off, and never
## crosses the wire.
##
## The real traps do not come through here at all any more. They are the host's
## to add, and he adds them where the spawner is watching.
func _ghost_root() -> Node:
	return player.get_parent()

## Asks for one: the trap, on the spot, turned the way the player is standing.
## `length` stretches it along its own body, which is what a strip of glue is and
## what everything else leaves at one.
##
## **Nothing is put on the floor here.** It used to be — this method instantiated
## the scene and added it, and the trap existed on the machine of whoever clicked
## and on no other. Now it asks the host, the host checks it and the host adds
## it, and the trap arrives on this machine the same way it arrives on everybody
## else's: through the `MultiplayerSpawner` over `Traps`. So there is nothing to
## hand back, and a caller wanting to know what landed listens to
## `TrapManager.trap_placed` rather than reading a return value that would only
## ever have been this machine's own guess.
##
## The `stock_id` is what travels, because it is already the string that names
## both the box in the van and the trap that comes out of it, and a scene *path*
## on the wire would be a client choosing what gets built on every machine.
func _place(at: Vector3, facing: Vector3, length := 1.0) -> void:
	if trap_scene == null:
		return
	TrapManager.request_place(_our_steam_id(), stock_id, at, facing, length)

## Who we are, as the crew counts people. The same question the ready boards and
## the colour panel ask, and asked the same way — see `LobbyManager.our_steam_id`
## for why it is not `SteamManager.get_steam_id()`.
func _our_steam_id() -> int:
	return LobbyManager.our_steam_id()

# --- The trap-to-be ---------------------------------------------------------
#
# The ghost is the same scene that gets placed, with everything in it switched
# off and its skin made see-through. Building it out of the real thing is what
# keeps the two honest with each other: there is no second model to keep in step,
# and a trap whose shape changes changes the ghost with it.

## Where the ghost should stand this frame, or `INVALID_POINT` to take it off the
## screen. Each trap answers for itself — the mousetrap sits on the spot the
## player is pointing at, the glue stretches from a pinned end to it.
func _ghost_spot() -> Vector3:
	return _ground_point()

## Which way the ghost is turned, and how far it is stretched along its own body.
## The plain answer is "the way the player is standing, at its own size".
func _ghost_pose() -> Transform3D:
	return Transform3D(Basis.looking_at(_facing(), Vector3.UP), Vector3.ONE)

## Whether what the ghost is showing could actually be put down right now. It is
## what decides the colour, and it is asked every frame. Each trap adds its own
## reasons on top of the one they share: an empty wallet in front of a price.
func _ghost_allowed() -> bool:
	return _can_afford()

func _update_ghost() -> void:
	if trap_scene == null:
		return
	var spot := _ghost_spot()
	if spot == INVALID_POINT:
		if _ghost != null:
			_ghost.hide()
		return
	if _ghost == null:
		_build_ghost()
	var pose := _ghost_pose()
	_ghost.global_position = spot
	_ghost.global_basis = pose.basis
	_ghost.scale.z = maxf(pose.origin.z, 0.001)
	var allowed := _ghost_allowed()
	_tint_ghost(GHOST_COLOR if allowed else GHOST_BLOCKED_COLOR)
	_update_price_tag(allowed)
	_ghost.show()

func _build_ghost() -> void:
	_ghost = trap_scene.instantiate()
	# Nothing in it runs: an `Area3D` that ticked would catch rats for a trap the
	# player has not put down yet.
	_ghost.process_mode = Node.PROCESS_MODE_DISABLED
	_ghost_root().add_child(_ghost)
	_strip(_ghost)
	_build_price_tag()

## The price, hung over the ghost and facing the player wherever he stands. It is
## built with the ghost whether or not there is anything to charge today: what is
## in the bag changes while the weapon is out, and a label that is merely hidden
## can be shown again the same frame the last bought trap runs out.
func _build_price_tag() -> void:
	_price_tag = Label3D.new()
	_price_tag.pixel_size = PRICE_PIXEL_SIZE
	_price_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_price_tag.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_price_tag.font_size = PRICE_FONT_SIZE
	_price_tag.outline_size = PRICE_OUTLINE
	# It reads through whatever it is standing on. The trap is flat on the floor
	# and the player is looking down at it, so an occluded price would spend half
	# its life inside the model it belongs to.
	_price_tag.no_depth_test = true
	_price_tag.position.y = PRICE_HEIGHT
	_ghost.add_child(_price_tag)

## Puts the price up, or takes it away. The colour is the ghost's own: green
## while he can pay for it, red in the same breath as the trap turns red.
func _update_price_tag(allowed: bool) -> void:
	if _price_tag == null:
		return
	var fee := _next_fee()
	if fee <= 0:
		_price_tag.hide()
		return
	_price_tag.text = "$%d" % fee
	_price_tag.modulate = GHOST_COLOR if allowed else GHOST_BLOCKED_COLOR
	# The ghost is stretched along its own body for a strip of glue, and a label
	# parented to it would be stretched with it.
	_price_tag.scale = Vector3.ONE / maxf(_ghost.scale.z, 0.001)
	_price_tag.show()

## Takes the working parts out of the ghost and leaves the picture. The shapes go
## because a ghost is not a thing in the world; the meshes stay, and get a skin
## of their own so tinting one never reaches the trap it was copied from.
func _strip(node: Node) -> void:
	var shape := node as CollisionShape3D
	if shape != null:
		shape.disabled = true
	var mesh := node as MeshInstance3D
	if mesh != null:
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = material
	for child in node.get_children():
		_strip(child)

func _tint_ghost(color: Color) -> void:
	_tint(_ghost, Color(color.r, color.g, color.b, GHOST_ALPHA))

func _tint(node: Node, color: Color) -> void:
	var mesh := node as MeshInstance3D
	if mesh != null:
		var material := mesh.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = color
	for child in node.get_children():
		_tint(child, color)

func _clear_ghost() -> void:
	if _ghost == null:
		return
	_ghost.queue_free()
	_ghost = null
	# It hung off the ghost and went with it.
	_price_tag = null
