extends Node
## What is on the floor of the house, and the one rule about it: nobody puts a
## trap down but the host, and everybody sees the same ones.
##
## **The host holds the floor.** A player at the boards does not put a trap down;
## he *asks* to (`request_place`), the host looks at where he is standing and what
## is in his bag, and either the trap goes down on every machine at once
## (`_spawn`) or the man who asked hears a buzzer and nobody else hears anything
## (`_refuse`). It is the same round trip the colour panel, the ready boards and
## the shelf take, and it is here for the same reason as the shelf: a floor that
## each machine wrote for itself is four different floors, and a rat that walks
## into a trap on one screen and over bare boards on the other is not one animal
## in one house.
##
## **The trap is a node, not a row in a table.** That is the whole difference
## between this and the other three managers, and it is why the announcement is
## not an RPC: what this decides is that a *scene* should exist, and the thing
## that carries a scene across the wire is a `MultiplayerSpawner` — the one over
## `Traps` in `world.tscn`, which is the same pair `Rats` already carries for the
## animals (`scripts/house/house.gd`). So the host calls `spawn()` and the
## spawner builds the node on every machine. What is on the wire as an RPC here
## is the request going up, the refusal coming back down and the unit leaving the
## box, and nothing else.
##
## **The pose travels as spawn data, and that is deliberate.** A spawner
## replicates the *fact* of a node — which scene, what name — and nothing more. A
## rat gets away with that because it carries a `MultiplayerSynchronizer` and
## publishes where it is every frame; a trap is the opposite kind of object,
## fixed the moment it is set down and never moving again. Giving it a
## synchroniser would buy a packet a frame, for ever, to repeat a number that
## will never change. So where it stands, which way it is turned and how far the
## glue is stretched all go into the dictionary handed to `spawn()`, and
## `_build_trap` is the one description both machines build from. Without that
## every trap arrives at the origin on the guest's screen, which is the shape the
## original bug takes once the node itself is crossing.
##
## **The ghost never crosses.** The translucent trap-to-be that follows a
## player's sights around is his own machine's drawing of what he is about to
## ask for (`scripts/weapons/trap_weapon.gd`). It is not a trap, nobody else has
## any business seeing it, and it is kept out of the replicated container for
## exactly that reason.
##
## **Names are the host's, and they are counted.** Two mousetraps both called
## `Mousetrap` is two nodes fighting over one path, and the path is the whole of
## how two machines know they are talking about the same object. So the host
## numbers them — `Mousetrap_1`, `Mousetrap_2` — off a counter that only ever
## goes up, and never off the child count, which goes *down* every time somebody
## cleans a trap out and would hand the next one a name that is still on a node
## the guest has not finished freeing.

## A trap went down. It fires on the host, at the moment he adds it — a guest
## hears about its own arrivals from the container itself, which is what
## `scripts/weapons/trap_weapon.gd` does not need and `house.gd` would. `by` is
## whoever asked for it.
signal trap_placed(trap: Node3D, by: int)

## We asked for a trap and were turned down. Emitted only on the machine that
## asked, which is what the weapon plays its buzzer off. `reason` is a sentence.
signal request_refused(reason: String)

## The peer that decides. Peer 1, the same as everywhere else: Godot hands it to
## the host the moment the wire comes up, and it is a surer answer than a Steam
## ID that may not have been introduced yet.
const HOST_PEER := 1

## Where a trap may be put down. The survey is what the minute of lights-on is
## *for*, and the hunt still lets a man drop one in front of a rat he is backing
## away from — at the longer arming cooldown the weapon already charges him
## (`TrapWeapon.hunt_cooldown`). Anywhere else there is no house to put it in.
const PHASES: Array[Phase.Type] = [
	Phase.Type.SURVEY,
	Phase.Type.HUNT,
]

## Every trap that may be asked for, by the id its scene carries in `stock_id`.
## The request travels as one of these strings and never as a path: a client that
## could name its own scene could name any scene in the project, and what came
## back would be built on every machine in the game.
##
## The same two paths are registered on the spawner in `world.tscn`. A spawner
## refuses to replicate a scene that is not on its list, so the two have to
## agree — and this is the one that produces the refusal a player can read.
const SCENES := {
	"mousetrap": "res://scenes/traps/mousetrap.tscn",
	"rat_glue": "res://scenes/traps/glue_trap.tscn",
}

## How far from the man who asked a trap may land. It is the weapon's own
## `place_range` with a stride of slack on top: the request is answered a round
## trip after it was sent, and in that time the asker has walked. What it
## actually stops is the client that names a spot across the house — a trap set
## through a wall into a room nobody has been in yet.
const MAX_REACH := 6.0

## The longest strip of glue anybody may ask for, and the shortest. They are
## `GlueWeapon.max_length` (2.4) and `min_length` (0.25) seen from the other side
## of the wire: the weapon already refuses to draw one outside them, so what this
## catches is a machine that was made to ask anyway.
##
## The margin is on purpose and it is why these are not simply those two numbers.
## Both are `@export`s — a designer may widen the tray tomorrow without knowing
## this file exists — and a host that clamped to the exact figure would quietly
## shorten every strip in the game the day somebody nudged it. What is wanted
## here is a ceiling loose enough never to argue with the weapon and tight enough
## that a client cannot ask for a strip across the hallway.
const MAX_LENGTH := 4.0
const MIN_LENGTH := 0.1

## What a man is told, in the order the host checks it. Sentences and not codes,
## because the only thing done with one is putting it on a screen.
const REFUSAL_PHASE := "Nothing to put it on here."
const REFUSAL_UNKNOWN := "That is not a trap."
const REFUSAL_EMPTY := "Nothing left in the bag."
const REFUSAL_FAR := "Too far away."

## How many traps the host has named so far. It only ever goes up — see the note
## on names at the top of the file — and it starts over with the shift, because a
## new house is a bare floor and `Mousetrap_1` is free again.
var _placed := 0


func _ready() -> void:
	# A trap can land while the game is paused — a pause menu is not a hiding
	# place from the wire — so the packet still has to be read. Same as
	# `PhaseManager`, `ReadyManager`, `ColorManager` and `ShopManager`.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# The floor is bare again at the top of every shift, so the numbering may
	# start over.
	PhaseManager.phase_changed.connect(_on_phase_changed)

# --- What everybody can ask -------------------------------------------------

## Whether a trap may be put down where the shift is standing. The weapon asks
## before it draws its ghost, so that a man in the van is not aiming at the floor
## of a room he has not arrived in.
func is_open() -> bool:
	return PHASES.has(PhaseManager.current())


## Whether an id is one of the things that can go on a floor. What a weapon
## checks before it bothers asking.
func is_known(trap_id: String) -> bool:
	return SCENES.has(trap_id)

# --- Asking for a trap ------------------------------------------------------

## Asks the host to put a trap down. **This is the only way in from a weapon** —
## it never adds anything itself, and what comes back is the trap arriving in the
## `Traps` container, on this machine like on every other.
##
## `facing` is which way the thing is turned and `length` stretches it along its
## own body, which is what a strip of glue is and what everything else leaves at
## one.
##
## Off the wire (a solo game, a bench) an `rpc_id` to peer 1 would be an error in
## the log for an answer that is already here, so the request is handed straight
## to the host's own handler. It is the same code down either road, which is what
## keeps solo from being a second set of rules.
func request_place(steam_id: int, trap_id: String, at: Vector3,
		facing: Vector3, length := 1.0) -> void:
	if steam_id == 0 or trap_id.is_empty():
		return
	if PhaseManager.is_host():
		_handle_request(steam_id, trap_id, at, facing, length, _our_peer_id())
		return
	_request.rpc_id(HOST_PEER, steam_id, trap_id, at, facing, length)

# --- The wire ---------------------------------------------------------------

## A player's request, arriving at the host. `any_peer` because anybody may ask;
## what makes it safe is that the host is the only one who acts on it, and that
## what he does with it is checked below rather than taken on trust.
@rpc("any_peer", "reliable")
func _request(steam_id: int, trap_id: String, at: Vector3,
		facing: Vector3, length: float) -> void:
	if not PhaseManager.is_host():
		push_warning("TrapManager: a trap request reached a machine that is not the host.")
		return
	_handle_request(steam_id, trap_id, at, facing, length,
		multiplayer.get_remote_sender_id())


## The host's decision, in one place so that it is the same whether the request
## came off the wire or out of a solo game.
##
## Six things are checked, and each of them is a way the floor could otherwise be
## made to lie:
##
## - **The trap exists.** An id that is on neither shelf is a client naming a
##   scene of its own choosing.
## - **The crew.** A Steam ID nobody has been introduced to is not a player, and
##   a trap belonging to one is a trap nobody paid for.
## - **Whose bag it is.** A peer may only spend his own. Without this, any client
##   could empty the whole van's boxes onto the floor.
## - **The phase.** There is no floor to put one on outside the house.
## - **The bag.** He has to have the thing he is putting down.
## - **The spot.** Not across the house — see `MAX_REACH`.
##
## The length is pinned rather than refused: a strip of glue a hair over the
## maximum is a client that rounded differently, not a client that is lying, and
## clamping it puts down the strip he can actually have.
func _handle_request(steam_id: int, trap_id: String, at: Vector3,
		facing: Vector3, length: float, from_peer: int) -> void:
	if not is_known(trap_id):
		push_warning("TrapManager: asked for '%s', which is not a trap." % trap_id)
		_refuse_to(from_peer, REFUSAL_UNKNOWN)
		return
	if not _is_somebody(steam_id):
		push_warning("TrapManager: trap asked for %d, who is not in the crew." % steam_id)
		return
	if not _may_speak_for(from_peer, steam_id):
		push_warning("TrapManager: peer %d tried to spend %d's traps." % [from_peer, steam_id])
		return
	if not is_open():
		_refuse_to(from_peer, REFUSAL_PHASE)
		return
	if not _has_in_bag(steam_id, trap_id):
		_refuse_to(from_peer, REFUSAL_EMPTY)
		return
	if not _is_plausible(steam_id, at):
		push_warning("TrapManager: %d asked for a trap nowhere near him." % steam_id)
		_refuse_to(from_peer, REFUSAL_FAR)
		return

	# The box before the floor. Taking the last one out of a box is what puts the
	# weapon away on the machine that owns it (`Inventory._on_stock_changed`),
	# and a man who sees his trap land before his belt has let go of it can click
	# a second time in the frame between the two.
	if _on_the_wire():
		_debit.rpc(steam_id, trap_id)
	else:
		_debit(steam_id, trap_id)
	_spawn(steam_id, trap_id, at, facing, clampf(length, MIN_LENGTH, MAX_LENGTH))


## Whether there is a man behind a Steam ID at all.
##
## The plain answer is `SessionManager.has_player`, and on the wire it is the
## only answer: a trap put down for somebody nobody has been introduced to is a
## trap nobody paid for.
##
## An **empty crew** is the one exception, and it is not a hole. Nobody has
## registered — a solo hunt started straight into the house, or a bench that
## built a world without a lobby under it — so there is no other player's traps
## to spend and nobody to take them from. Refusing there would mean a trap weapon
## that silently does nothing everywhere the game is played alone, which is a
## worse bug than the one being guarded against. It is the same reasoning
## `ShopManager.is_ours` gives for treating a one-man crew as the man at the
## shelf.
func _is_somebody(steam_id: int) -> bool:
	if SessionManager.players.is_empty():
		return true
	return SessionManager.has_player(steam_id)


## Whether a Steam ID is the man sitting at this machine — the one whose `Stock`
## is the box on this desk and whose body is the one in the `player` group.
##
## `ShopManager.is_ours` is the answer and is deferred to, with one case added on
## top of it: an **empty crew**. That autoload answers false there, and rightly,
## because the question it is asked is whose purse to debit and guessing wrong
## would hand one player another player's money. Here the crew being empty means
## something narrower and safe — nobody has registered at all, so the only man
## who could have asked is the one at this keyboard. It is the same exception
## `_is_somebody` makes, for the same reason, and without it a solo hunt spends
## nothing out of its own box.
func _is_ours(steam_id: int) -> bool:
	if steam_id == 0:
		return false
	if SessionManager.players.is_empty():
		return true
	return ShopManager.is_ours(steam_id)


## Whether a peer is allowed to spend a Steam ID's traps: his own only. The host
## calling in from his own game arrives as his own peer id — or as zero with no
## wire at all, which is a machine with nobody to lie to.
func _may_speak_for(from_peer: int, steam_id: int) -> bool:
	if from_peer == 0 or not multiplayer.has_multiplayer_peer():
		return true
	var owner_id := LobbyManager.steam_id_of_peer(from_peer)
	# A peer whose introduction has not landed yet has no Steam ID to check
	# against. Refusing him would mean a weapon that does nothing for the first
	# second of a house, which is a worse bug than the one being guarded
	# against — and the introduction is already on its way.
	return owner_id == 0 or owner_id == steam_id


## A refusal, landing only on the man who asked.
@rpc("authority", "reliable")
func _refuse(reason: String) -> void:
	if multiplayer.get_remote_sender_id() != HOST_PEER:
		return
	request_refused.emit(reason)


## The host turning somebody down, whoever it was. His own refusal never goes on
## the wire — it is already on the machine that has to hear it.
func _refuse_to(peer_id: int, reason: String) -> void:
	if peer_id == 0 or peer_id == _our_peer_id():
		request_refused.emit(reason)
		return
	_refuse.rpc_id(peer_id, reason)

# --- Putting one down -------------------------------------------------------

## The trap itself. **Host only** — this is the end of every road through
## `_handle_request`, and the one place in the game that adds a trap to a floor.
##
## There is no `rpc` here on purpose. The `MultiplayerSpawner` over the `Traps`
## container is what carries the node to the other machines. What it carries,
## though, is only *which scene* and *what name* — a spawner replicates the fact
## of a node, not its state, and the rats get away with that because each animal
## carries a `MultiplayerSynchronizer` that publishes where it is every frame.
##
## A trap is the opposite kind of object: it never moves again after the moment
## it is put down. Giving it a synchroniser would mean paying for a packet a
## frame, for ever, to say a number that will never change — and going without
## one is what leaves every trap sitting at the origin on the guest's screen,
## which is what the bench caught. So the pose travels **as spawn data**
## (`_build_trap`): one dictionary, sent once, at the moment the node is created.
##
## What is still settled here, before the add, is what the spawner reads off the
## node itself:
##
## - The name, or the guest builds an `@Area3D@31` while the host has
##   `Mousetrap_4`, and two nodes that do not share a path never hear each other
##   again.
## - The authority, so the trap wakes up on the guest already knowing it is not
##   the one deciding what it catches (`scripts/traps/trap.gd`).
func _spawn(steam_id: int, trap_id: String, at: Vector3,
		facing: Vector3, length: float) -> void:
	var spawner := _spawner()
	if spawner == null:
		push_warning("TrapManager: no TrapSpawner to put a trap through.")
		return

	_placed += 1
	var trap := spawner.spawn({
		"id": trap_id,
		"n": _placed,
		"at": at,
		"facing": facing,
		"length": length,
		"by": steam_id,
	}) as Node3D
	if trap == null:
		return
	trap_placed.emit(trap, steam_id)


## Builds one trap out of what came over the wire. **This runs on every machine**
## — it is the spawner's `spawn_function`, so the host runs it when `spawn()` is
## called and each guest runs it when the packet lands, with the same dictionary
## in hand. That is what makes it the one description of what a placed trap is.
##
## Everything is settled before the node is returned, because the spawner adds it
## to the container itself the moment this hands it back. A pose written after
## that is a pose written on a trap that has already been in the world for a
## frame — and on the host, one that has already had a chance to catch something
## at the origin.
func _build_trap(data: Variant) -> Node:
	var fields := data as Dictionary
	if fields == null:
		return null
	var packed := _scene_of(String(fields.get("id", "")))
	if packed == null:
		return null
	var trap := packed.instantiate() as Node3D
	if trap == null:
		return null

	# Named here rather than left to the engine's `@Area3D@22`, and numbered off
	# the host's counter so that two traps of a kind are two nodes: a floor with
	# a dozen things on it is read far more often than it is counted, and two
	# nodes fighting over one path is the bug underneath that.
	trap.name = "%s_%d" % [trap.get_script().get_global_name(), int(fields.get("n", 0))]
	trap.set_multiplayer_authority(HOST_PEER)
	# `position` and not `global_position`: the node is not in the tree yet, and
	# a global write before it has a parent is a write onto nothing. The
	# container sits at the origin, so the two are the same number.
	trap.position = fields.get("at", Vector3.ZERO)
	var facing: Vector3 = fields.get("facing", Vector3.ZERO)
	if not facing.is_zero_approx():
		trap.basis = Basis.looking_at(facing, Vector3.UP)
	trap.scale.z = maxf(float(fields.get("length", 1.0)), 0.001)
	# Who set it, so that whatever is eventually paid for the catch is paid to
	# the man who put the thing down (`scripts/traps/trap.gd`).
	if "placed_by" in trap:
		trap.placed_by = int(fields.get("by", 0))
	return trap


## The spawner over the `Traps` container, with this autoload's builder hung on
## it. The hook is set here rather than in the scene because a `spawn_function`
## is a `Callable` and there is nowhere in a `.tscn` to write one — and setting
## it every time is harmless: it is the same callable, and assigning it again
## changes nothing.
##
## Null when there is no house up — a man in the van has no floor, and `_spawn`
## says so rather than putting a trap somewhere the wire cannot follow it.
func _spawner() -> MultiplayerSpawner:
	var root := traps_root()
	if root == null:
		return null
	var spawner := root.get_node_or_null(^"TrapSpawner") as MultiplayerSpawner
	if spawner == null:
		# A barer world than the game builds — a bench, or a scene somebody
		# trimmed. Whatever spawner is over the container will do.
		for child in root.get_children():
			spawner = child as MultiplayerSpawner
			if spawner != null:
				break
	if spawner == null:
		return null
	if spawner.spawn_function != _build_trap:
		spawner.spawn_function = _build_trap
	return spawner


## Where placed traps go: the `Traps` node in `world.tscn`, which is the one the
## `MultiplayerSpawner` is watching. Null when there is no house up — a man in
## the van has no floor, and `_spawn` says so rather than putting a trap
## somewhere the wire cannot follow it.
##
## It is found by **group** and not by path. `house.gd` puts the container in
## `traps_root` on the way up, and that is the one handle that answers in every
## way the world gets built: the game's own scene change, and the benches that
## instance `world.tscn` under the root without ever making it `current_scene`.
## A path off `current_scene` would find the first and quietly miss the second.
func traps_root() -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var found := tree.get_first_node_in_group("traps_root") as Node3D
	if found != null:
		return found
	# No house script to have marked it. That is a barer world than the game
	# builds, and the container is still the same child of the same scene.
	if tree.current_scene == null:
		return null
	return tree.current_scene.get_node_or_null(^"Traps") as Node3D


## The scene behind an id, loaded on demand. `SCENES` holds paths rather than
## `PackedScene`s so that this autoload costs nothing on a machine that never
## puts a trap down — the lobby screen loads it too.
func _scene_of(trap_id: String) -> PackedScene:
	var path: String = SCENES.get(trap_id, "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as PackedScene

# --- The bag ----------------------------------------------------------------

## Whether a player has the thing he is trying to put down.
##
## What is checked is `SessionManager.inventory`, which is the host's own record
## of what each man bought (`ShopManager._apply` writes it on every machine) —
## and so the only account of a player's kit that a client cannot touch. It stops
## the case that matters: a man putting down traps he never bought.
##
## A crew with nothing in anybody's bag has not been through the shop — a bench,
## a house loaded straight into — and refusing there would mean a trap weapon
## that does nothing in half the test benches in the project. The stock the
## asker's own machine holds is the answer then, which is what the answer was
## before any of this was on the wire.
func _has_in_bag(steam_id: int, trap_id: String) -> bool:
	var bag := SessionManager.inventory(steam_id)
	if bag.is_empty():
		return not _is_ours(steam_id) or Stock.count(trap_id) > 0
	return bag.has(trap_id)


## Takes the unit out of the bag, on every machine at once (`call_local`) — the
## same shape as `ShopManager._apply`, which is what put the unit *in* the bag,
## and for the same reason: the box a weapon actually spends from is `Stock`, and
## `Stock` is a single-player autoload holding only the boxes of whichever man is
## sitting at *this* machine. So the announcement crosses to everybody and each
## machine debits its own man and nobody else's, exactly as each machine credits
## its own man on a purchase.
##
## It is the **only** place a trap leaves a box. The weapons used to spend their
## own unit at the end of `_use()`; they no longer do, because a weapon that
## spent locally and then asked the host would spend a unit for a trap the host
## went on to refuse.
##
## # TODO (next card): the *decision* is authoritative but the **count** is not.
## `SessionManager.inventory` holds one entry per purchase and not one per
## unit — a box is three mousetraps under a single `"mousetrap"` — so there is no
## unit count on the host to check a request against, only the presence of a
## purchase (`_has_in_bag`). Moving the count itself onto the host is the shop's
## job rather than this one's: `Stock` has to become per-player on
## `SessionManager` before this can debit it there.
##
## What that leaves open is one player asking twice for a unit he has already
## spent — his own machine catches it (`TrapWeapon.available()` reads the count
## before the weapon is even in his hand), which is a client checking itself.
## What it does **not** leave open is the thing the card forbids: two players
## spending the same item. Each machine's `Stock` holds only its own man's boxes,
## so there is no shared count for two men to race for.
@rpc("authority", "call_local", "reliable")
func _debit(steam_id: int, trap_id: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("TrapManager: a debit from peer %d, which is not the host — ignored."
			% sender)
		return
	if _is_ours(steam_id):
		Stock.spend_one(trap_id)

# --- Odds and ends ----------------------------------------------------------

## Whether a spot is near enough the man who asked for it to be somewhere he
## could have been pointing. It is deliberately generous — see `MAX_REACH` — and
## that is the difference between a check and a straitjacket: what it is for is
## the client naming a spot in another room, not the client whose ping put him a
## step further along than the host thinks.
##
## A player whose body the host cannot find is let through. That is a man whose
## avatar has not gone up yet, or a bench with no bodies in it at all, and
## refusing him would be refusing a trap for a reason that has nothing to do with
## where he put it.
func _is_plausible(steam_id: int, at: Vector3) -> bool:
	var body := _body_of(steam_id)
	if body == null:
		return true
	return body.global_position.distance_to(at) <= MAX_REACH


## Where a player is standing, as far as this machine can see. Our own man is the
## one in the `player` group; everybody else is a capsule under `Players`
## (`scripts/steam/player_avatars.gd`). Null for a man with neither, which is
## what `_is_plausible` reads as "no opinion".
func _body_of(steam_id: int) -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	if _is_ours(steam_id):
		return tree.get_first_node_in_group("player") as Node3D
	if tree.current_scene == null:
		return null
	var avatars := tree.current_scene.get_node_or_null(^"Players")
	if avatars == null or not avatars.has_method("avatar_of"):
		return null
	var peer_id := _peer_of(steam_id)
	if peer_id == 0:
		return null
	return avatars.avatar_of(peer_id) as Node3D


## The peer behind a Steam ID, or zero for somebody nobody on the wire answers
## for. `LobbyManager` maps peers to accounts and not the other way about, so the
## guest list is walked — it is four names at the very most, and it is walked
## once per trap rather than once per frame.
func _peer_of(steam_id: int) -> int:
	if not multiplayer.has_multiplayer_peer():
		return 0
	for peer_id in multiplayer.get_peers():
		if LobbyManager.steam_id_of_peer(peer_id) == steam_id:
			return peer_id
	return 0


## A new shift is a bare floor, so the numbering starts over. Watched on the way
## *into* the lobby rather than out of the result: a shift abandoned halfway —
## the host dropping, somebody walking out — comes back through the lobby too,
## and that floor is just as bare.
func _on_phase_changed(_previous: Phase.Type, current: Phase.Type) -> void:
	if current == Phase.Type.LOBBY:
		_placed = 0


## Wipes the count, the way `Wallet.reset()` and `SessionManager.reset()` do: the
## start of a shift, and the start of every test bench.
func reset() -> void:
	_placed = 0


## Whether there is anybody to say it to. An `rpc` with no wire under it is an
## error in the log for a call that would have run here anyway, so the host asks
## first and calls the function plainly when the answer is no. The same question
## `ReadyManager._handle_request` asks before its own announcement.
func _on_the_wire() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


## Our own id on the wire, or zero when there is no wire to have one on — asking
## Godot for an id then is an error in the log for an answer nobody needed. The
## same shape as `ReadyManager._our_peer_id`, and for the same reason.
func _our_peer_id() -> int:
	if not multiplayer.has_multiplayer_peer():
		return 0
	var peer := multiplayer.multiplayer_peer
	if peer is OfflineMultiplayerPeer:
		return 0
	return multiplayer.get_unique_id()
