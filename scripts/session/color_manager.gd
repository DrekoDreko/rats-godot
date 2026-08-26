extends Node
## Who wears which colour, and the one rule about it: no two men in the same one.
##
## A crew of four in identical overalls in a dark house is four identical
## silhouettes, and the colour is the whole of what tells them apart — on the
## body across the room, on the name in the HUD, on the bulb on the ready board.
## So it is worth being strict about, and being strict means somebody has to
## hold the pen.
##
## **The host holds it.** A player at the panel does not take a colour; he *asks*
## for one (`request_color`), the host looks at who is wearing what, and either
## it is written on every machine at once (`_apply`) or the man who asked hears a
## buzzer and nobody else hears anything (`_refuse`). That is the same round trip
## the ready boards take, for the same reason: two men reaching for the last
## green swatch in the same frame both get it if either of them writes locally,
## and no amount of correcting afterwards makes that not have happened. Here the
## second one is simply turned down, because by the time his packet is opened
## the first one is already wearing it.
##
## **Everybody gets one at the door.** A player with no colour is a grey body
## somebody has to squint at, so nobody is ever without one: the crew entry is
## born wearing the first free colour (`SessionManager._new_player`), and the
## host confirms that choice out loud on the wire (`seat_everybody`) so that the
## machine that just joined and the machines that were already here agree about
## it. Picking at the panel is changing a colour, never getting a first one.
##
## **It stores nothing.** The colours live on `SessionManager` like everything
## else that has to outlive the van, and this only decides what goes into it.
## Ask that autoload what a man is wearing; ask this one to change it.

## Somebody's colour was settled — after it was written, so a listener that reads
## `SessionManager.color` off this sees the new one. `SessionManager.player_changed`
## says the same thing among everything else; this carries the colour and nothing
## but, and is what the panel lights off.
signal color_changed(steam_id: int, color: Color)

## We asked and were turned down. Emitted only on the machine that asked, which
## is what the panel plays its buzzer off. `reason` is a sentence.
signal request_refused(reason: String)

## The peer that decides. The same 1 the phase machine and the ready manager use,
## and for the same reason: Godot hands it to the host the moment the wire comes
## up, and it is a surer answer than a Steam ID that may not have been introduced
## yet.
const HOST_PEER := 1


func _ready() -> void:
	# A colour can be settled while the game is paused — the panel is in the van
	# and a pause menu is not a hiding place from the wire — so the packet still
	# has to land. Same as `PhaseManager` and `ReadyManager`.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# A man who walks out takes his colour off the rack with him. The crew entry
	# going is what frees it (`SessionManager.remove_player`), so there is
	# nothing to write here — only something to say, so that the panels repaint
	# the swatch that has just come free.
	SessionManager.player_left.connect(_on_player_left)


## The palette, in the order it is worn on the wall. A thin way through to
## `SessionManager`, so that a panel has one autoload to talk to rather than two.
func palette() -> Array[Color]:
	return SessionManager.COLORS


## How many swatches there are on the wall.
func count() -> int:
	return SessionManager.COLORS.size()


## The colour at a place on the wall, or white for an index off the end of it —
## a colour, so that whoever is painting a swatch never has to check first.
func color_at(index: int) -> Color:
	if index < 0 or index >= SessionManager.COLORS.size():
		return Color.WHITE
	return SessionManager.COLORS[index]


## Where in the palette a colour sits, or -1 for one that is not in it. What the
## panel asks to find the swatch a player is standing in front of.
func index_of(color: Color) -> int:
	return SessionManager.COLORS.find(color)


## Who is wearing the colour at a place on the wall, or zero when nobody is. The
## panel draws its crossed-out swatches off this.
func owner_of_index(index: int) -> int:
	if index < 0 or index >= SessionManager.COLORS.size():
		return 0
	return SessionManager.color_owner(SessionManager.COLORS[index])


## Whether a place on the wall is free for a player to take. His own colour
## counts as free to him — pressing the swatch you are already wearing is not an
## error, it is a man checking which one is his — and `_handle_request` throws
## that away quietly rather than buzzing at him.
func is_available(index: int, for_steam_id := 0) -> bool:
	if index < 0 or index >= SessionManager.COLORS.size():
		return false
	return not SessionManager.is_color_taken(SessionManager.COLORS[index], for_steam_id)


## Asks the host for the colour at a place on the wall. **This is the only way in
## from a panel** — it never writes anything itself, and what comes back is
## `_apply` on every machine at once, our own included.
##
## Off the wire (a solo game, a bench) an `rpc_id` to peer 1 would be an error in
## the log for an answer that is already here, so the request is handed straight
## to the host's own handler. It is the same code down either road, which is what
## keeps solo from being a second set of rules.
func request_color(steam_id: int, index: int) -> void:
	if steam_id == 0:
		return
	if PhaseManager.is_host():
		_handle_request(steam_id, index, _our_peer_id())
		return
	_request.rpc_id(HOST_PEER, steam_id, index)


## Everybody in the crew, confirmed in what he is already wearing. **Host only**,
## and only worth calling when the crew changes shape: a player who has just been
## registered is wearing whatever `SessionManager` handed him on the way in, and
## that was worked out from the crew *that machine* could see. The host's own
## view is the one that counts, so he states it, and any machine that had guessed
## differently is corrected.
##
## It is deliberately not clever about which of them actually needed saying:
## `_apply` writes through `SessionManager.set_color`, which announces nothing
## when the colour did not move, so the redundant ones cost a packet and change
## no pixels.
func seat_everybody() -> void:
	if not PhaseManager.is_host():
		return
	# The colours settled so far in this pass. Asking `SessionManager` who owns a
	# colour would answer "the other man" whichever of the two is being looked
	# at, and would move the first of them as readily as the second — so the
	# tie is broken against the list being built here rather than against the
	# crew, and seniority means the man who was already in the van keeps what he
	# is wearing.
	var settled: Array[Color] = []
	for steam_id in SessionManager.players:
		var color := SessionManager.color(steam_id)
		if settled.has(color):
			# Two men arrived wearing the same colour, which happens when two
			# machines each worked out "the first free one" before either had
			# heard of the other. Whoever is found second is moved.
			color = _first_color_outside(settled)
			SessionManager.set_color(steam_id, color)
		settled.append(color)
		_announce(steam_id, color)

# --- The wire ---------------------------------------------------------------

## A player's request, arriving at the host. `any_peer` because anybody may ask;
## what makes it safe is that the host is the only one who acts on it, and that
## what he does with it is checked below rather than taken on trust.
@rpc("any_peer", "reliable")
func _request(steam_id: int, index: int) -> void:
	if not PhaseManager.is_host():
		push_warning("ColorManager: a colour request reached a machine that is not the host.")
		return
	_handle_request(steam_id, index, multiplayer.get_remote_sender_id())


## The host's decision, in one place so that it is the same whether the request
## came off the wire or out of a solo game.
##
## Four things are checked, and each of them is a way the wall could otherwise be
## made to lie:
##
## - **The swatch exists.** An index off the end of the palette is a client
##   asking for a colour that is not painted on any wall.
## - **The crew.** A Steam ID nobody has been introduced to is not a player, and
##   dressing one would put a colour on the rack that no body is wearing.
## - **Whose overalls they are.** A peer may only paint his own. Without this,
##   any client could dress the whole van in one colour.
## - **The colour is free.** The one rule the panel exists for.
func _handle_request(steam_id: int, index: int, from_peer: int) -> void:
	if index < 0 or index >= SessionManager.COLORS.size():
		push_warning("ColorManager: asked for swatch %d, which is not on the wall." % index)
		return
	if not SessionManager.has_player(steam_id):
		push_warning("ColorManager: colour asked for %d, who is not in the crew." % steam_id)
		return
	if not _may_speak_for(from_peer, steam_id):
		push_warning("ColorManager: peer %d tried to dress %d." % [from_peer, steam_id])
		return

	var wanted := SessionManager.COLORS[index]
	# Already his. Not a refusal — there is nothing to refuse — and not a write
	# either, so no buzzer and no packet.
	if SessionManager.color(steam_id) == wanted:
		return
	var taken_by := SessionManager.color_owner(wanted, steam_id)
	if taken_by != 0:
		_refuse_to(from_peer, "%s is already wearing that one." % _name_of(taken_by))
		return
	_announce(steam_id, wanted)


## Whether a peer is allowed to dress a Steam ID: his own only. The host calling
## in from his own game arrives as his own peer id — or as zero with no wire at
## all, which is a machine with nobody to lie to.
func _may_speak_for(from_peer: int, steam_id: int) -> bool:
	if from_peer == 0 or not multiplayer.has_multiplayer_peer():
		return true
	var owner_id := LobbyManager.steam_id_of_peer(from_peer)
	# A peer whose introduction has not landed yet has no Steam ID to check
	# against. Refusing him would mean a panel that does nothing for the first
	# second of a lobby, which is a worse bug than the one being guarded
	# against — and the introduction is already on its way.
	return owner_id == 0 or owner_id == steam_id


## The host's decision, said out loud. On the wire it goes to every machine at
## once, his own included (`call_local`); off it — a solo game, or a host whose
## last client has just left, which is the state `leave_lobby` puts him in on the
## way through `members_changed` — the same call is made straight into `_apply`,
## because an `rpc` with no peer under it is an error in the log for a packet
## that had nobody to reach.
func _announce(steam_id: int, color: Color) -> void:
	if _on_the_wire():
		_apply.rpc(steam_id, color)
		return
	_apply(steam_id, color)


## The answer, run on every machine at once, the host included (`call_local`).
## The colour is written here and nowhere else — a panel reacts to this, it does
## not write ahead of it.
@rpc("authority", "call_local", "reliable")
func _apply(steam_id: int, color: Color) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("ColorManager: colour change from peer %d, which is not the host — ignored."
			% sender)
		return
	if not SessionManager.has_player(steam_id):
		return
	SessionManager.set_color(steam_id, color)
	color_changed.emit(steam_id, color)


## A refusal, landing only on the man who asked. It is a sentence and not a code,
## because the only thing anybody does with it is put it on a screen or play a
## buzzer beside it.
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

# --- Odds and ends ----------------------------------------------------------

## Somebody left, and the colour he was wearing is back on the rack. Nothing to
## write — his crew entry is what held it — but the panels have a swatch to
## un-cross, and they repaint off `color_changed` like everything else.
func _on_player_left(steam_id: int) -> void:
	color_changed.emit(steam_id, Color.WHITE)


## The first colour that is neither already settled in this pass nor worn by
## anybody in the crew. `SessionManager.first_free_color` is not enough on its
## own here: the crew still holds the clash being untangled, so it would hand
## back a colour that one of the men already looked at is keeping.
##
## Falls back to the first of the palette when every colour is spoken for, which
## needs more players than the van holds and is still better answered with a
## colour than with a crash — the same call `first_free_color` makes.
func _first_color_outside(settled: Array[Color]) -> Color:
	for palette_color in SessionManager.COLORS:
		if not settled.has(palette_color) and not SessionManager.is_color_taken(palette_color):
			return palette_color
	for palette_color in SessionManager.COLORS:
		if not settled.has(palette_color):
			return palette_color
	return SessionManager.COLORS[0]


## Whoever is wearing a colour, by name, for the sentence in a refusal. Falls
## back to something rather than an empty string: "is already wearing that one"
## with nobody in front of it reads like a bug.
func _name_of(steam_id: int) -> String:
	var found: String = SessionManager.player(steam_id).get("name", "")
	return found if not found.is_empty() else "Somebody else"


## Our own id on the wire, or zero when there is no wire to have one on — asking
## Godot for an id then is an error in the log for an answer nobody needed. The
## same shape as `ReadyManager._our_peer_id`, and for the same reason.
func _our_peer_id() -> int:
	if not _on_the_wire():
		return 0
	return multiplayer.get_unique_id()


## Whether there is anybody to say it to. The same question `PhaseManager` and
## `TrapManager` ask, and for the same reason: a solo game never has a wire, and
## a host whose last client just left has stopped having one.
func _on_the_wire() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer
