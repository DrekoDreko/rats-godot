extends Node
## What moves a shift from one phase to the next: the clock the phase runs on,
## the scene each phase happens in, and the one decision — that it is time to go
## — which only the host is allowed to make.
##
## **The host is the clock.** Only he runs a `Timer`, only he decides a phase is
## over, and only he sends the change. Everybody else is told. This is not
## caution about cheating so much as caution about disagreement: four machines
## each counting down their own sixty seconds will end that minute at four
## different moments, and the crew would watch the van leave four times. One
## clock, broadcast, is the only version of this that stays in step.
##
## **A shared clock still has to look smooth.** The host sends the time left
## every half second (`SYNC_INTERVAL`) rather than every frame, because a
## timer's worth of packets per second is a timer's worth of packets nobody
## needed. Between two of them the client counts down on its own (`_process`)
## and is corrected the moment the next one lands, so the number on screen moves
## every frame and is never more than half a second's drift from the host's.
##
## **The scene is not reloaded when it does not change.** Survey and hunt happen
## in the same house, and the difference between them is that the rats are out —
## not that the house is new. Reloading it between the two would throw away
## every trap the crew spent a minute placing and put everybody back on the
## doorstep. So a phase change to the same scene changes nothing but the phase,
## and `phase_changed` is what the house listens to.
##
## **`SessionManager` holds, this drives.** The phase itself lives on that
## autoload, because it has to survive the scene change like everything else
## about the shift. This node writes it and announces it, and keeps no second
## copy that could disagree with the first.

## The shift moved on. Both phases are given because most listeners want to know
## what they are leaving as much as what they are entering — the house cuts its
## lights on `SURVEY -> HUNT` and on nothing else.
##
## It is emitted on every machine, whether or not the scene changed with it. When
## the scene did change, it comes *after* the new one is standing, so a node in
## it can be built already knowing which phase it woke up in.
signal phase_changed(previous: Phase.Type, current: Phase.Type)

## How much of the phase is left, in seconds. Fired on the host as his own timer
## runs and on the clients as they count between packets — so a HUD connects to
## this one signal and never has to know which machine it is on.
signal timer_updated(seconds_left: float)

## A phase with a clock has run out of it. Host only, because it is the host's
## clock: it is what walks the shift on when the crew never all said ready.
signal timer_expired(phase: Phase.Type)

## The scene each phase is played in. Survey and hunt share one deliberately —
## see the note above about not throwing the traps away. A phase absent from
## here stays wherever it is and only changes the phase, which is how `RESULT`
## works: the pay slip is a panel drawn over the house the crew has just
## cleared, not a room they are moved to, and the house standing behind it is
## most of what makes it read as the end of that shift rather than a menu.
##
## A `var` and not a `const`, because the house is not one scene: the contract
## the host signs is what says which one, and `set_scene` is how the clipboard
## will point survey and hunt at it. Whoever changes it must change both of them
## to the same path or the traps go in the bin — hence `set_house`, which is the
## one that should actually be called.
var scenes := {
	Phase.Type.LOBBY: "res://scenes/menu.tscn",
	Phase.Type.TRAVEL: "res://scenes/van_travel.tscn",
	Phase.Type.SURVEY: "res://scenes/world.tscn",
	Phase.Type.HUNT: "res://scenes/world.tscn",
}

## How many frames a scene change will wait for the outgoing scene to actually
## be freed before it announces the new phase. See `_change_scene`.
const SCENE_FREE_FRAMES := 4

## How often the host tells everybody what the clock says. Half a second is
## enough that a client's own counting never drifts far enough to see, and
## little enough traffic that it is not worth thinking about.
const SYNC_INTERVAL := 0.5

## The peer that is allowed to decide anything. Godot hands the host peer 1 the
## moment `host_with_lobby` succeeds, and it stays 1 for the life of the wire —
## which is what makes it a safer answer than a Steam ID that may not have been
## introduced yet.
const HOST_PEER := 1

## The phases in the order a shift walks them. What `advance()` steps along, so
## that the ordinary case — the crew is ready, on to whatever is next — does not
## need a phase named at the call site.
const ORDER: Array[Phase.Type] = [
	Phase.Type.LOBBY,
	Phase.Type.TRAVEL,
	Phase.Type.SURVEY,
	Phase.Type.HUNT,
	Phase.Type.RESULT,
]

## Seconds left in the phase, or zero when nothing is timing it. On the host it
## is his own timer read back; on a client it is the last packet, counted down
## since it landed.
var seconds_left := 0.0

## The host's own clock. Built on the host and on a client alike — a client's
## simply never starts, and having it there means `is_host()` is asked in one
## place rather than four.
var _timer: Timer

## Seconds until the next sync packet goes out. Host only.
var _until_sync := 0.0

## Whether a scene change is in flight. Between two scenes the tree has no
## current scene to compare a path against, and an empty answer must not come
## back equal to anything (see `_current_scene_path`).
var _changing_scene := false


func _ready() -> void:
	# A phase can end while the game is paused — a pause menu is not a hiding
	# place from the van leaving — and the packet that says so still has to be
	# read. `LobbyManager` is set the same way and for the same reason.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)

	# The wire going down mid-shift leaves a client counting a clock nobody is
	# sending any more. It should stop counting rather than run to zero and look
	# as though the phase ended.
	multiplayer.server_disconnected.connect(_stop_clock)


## Counts the clock down between the host's packets, so the number on screen
## moves every frame instead of twice a second. The host does not do this: his
## `Timer` is the real thing and he reads it back rather than guess at it.
func _process(delta: float) -> void:
	if is_host():
		_tick_host(delta)
		return
	if seconds_left <= 0.0:
		return
	# Floored at zero rather than allowed to go negative: a client that has not
	# heard from the host in a while should sit at nought, not count into the
	# minus. Whether the phase actually ended is the host's word, and it is on
	# its way.
	seconds_left = maxf(0.0, seconds_left - delta)
	timer_updated.emit(seconds_left)

# --- What everybody can ask ------------------------------------------------

## Where the shift is. Read off `SessionManager`, which holds the one copy.
func current() -> Phase.Type:
	return SessionManager.phase


## Whether this machine is the one that decides. True when there is no wire at
## all, which is what makes a solo game work without a special case anywhere:
## the only player is his own host.
func is_host() -> bool:
	if not _on_the_wire():
		return true
	return multiplayer.get_unique_id() == HOST_PEER


## Whether there is anybody to say it to. An `rpc` with no wire under it is an
## error in the log twice a second for a packet that had no one to reach: solo
## play never has a wire, and a host whose last client just left has stopped
## having one. Every call that goes out from here asks first. The same question
## `TrapManager._on_the_wire` asks, and for the same reason.
func _on_the_wire() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


## Whether a clock is running on the phase we are in. The HUD asks before it
## draws one.
func has_timer() -> bool:
	return duration_of(current()) > 0.0


## How long a phase runs on this shift, in seconds, or zero for one nothing is
## timing.
##
## Every phase but the hunt reads its length off `Phase.DURATION`, which is the
## same on every shift. The hunt does not: the crew books it in the van, at ten
## minutes, five or two, and the shorter the booking the more each rat is worth
## (`HuntTime`). So the length has to be asked of the shift rather than of the
## table — and asked *here*, in the one place, so that the clock the host starts
## and the clock the HUD decides to draw can never be two different answers.
func duration_of(phase: Phase.Type) -> float:
	if phase == Phase.Type.HUNT:
		return HuntTime.duration(SessionManager.hunt_time)
	return Phase.duration(phase)


## The phase after this one. The list is walked in order, and `RESULT` comes back
## round to `TRAVEL` — the van, not the menu. That is what makes a shift a loop
## rather than a line: a crew that has been paid is a crew back in its van with
## the money it made, the gear it did not use, and a board of jobs to sign the
## next one off. Going to the menu instead would end the evening at the end of
## every house.
##
## A phase that is not on the list at all is treated as the end of one — there is
## nowhere sensible to walk on to from a phase the order does not know about, and
## the menu is the one place that is always safe.
func next_phase() -> Phase.Type:
	if current() == Phase.Type.RESULT:
		return Phase.Type.TRAVEL
	var at := ORDER.find(current())
	if at == -1:
		return Phase.Type.LOBBY
	if at + 1 >= ORDER.size():
		return Phase.Type.LOBBY
	return ORDER[at + 1]


## The scene a phase is played in, or empty for one that has none. The stations
## read it to know whether they are about to be unloaded.
func scene_of(phase: Phase.Type) -> String:
	return String(scenes.get(phase, ""))


## Points the survey and the hunt at a house. **Both at once, and that is the
## point of the function** — they have to be the same path or the change from
## one to the other stops being free and starts being a reload, which is a
## minute of trap-placing in the bin. The contract is what calls this, once the
## clipboard is in.
func set_house(path: String) -> void:
	scenes[Phase.Type.SURVEY] = path
	scenes[Phase.Type.HUNT] = path

# --- What the host decides --------------------------------------------------

## On to the next phase. **Host only** — a client calling this is a client
## trying to take the van, and it is dropped with a word in the log rather than
## quietly ignored, because the only way it happens is a mistake worth finding.
##
## The crew's ready flags are cleared on the way through: being ready to leave
## the van is not being ready to walk into the house, and a flag left standing
## would skip the next phase the instant it began. It happens in `_apply`, on
## every machine at once, rather than here on the host's alone — see the note
## there.
func advance() -> void:
	go_to(next_phase())


## Straight to a named phase, wherever we are. **Host only.** `advance()` is
## what the ready stations call; this is for the shift that has to jump — a hunt
## cut short, a crew sent back to the lobby.
func go_to(phase: Phase.Type) -> void:
	if not is_host():
		push_warning("PhaseManager: only the host changes the phase.")
		return
	if phase == current():
		return
	if _on_the_wire():
		_apply.rpc(phase)
	else:
		_apply(phase)


## The clock ran out. Kept apart from `advance()` so that the reason the shift
## moved is visible here rather than guessed at, and so that the two things that
## end a phase — the crew and the clock — are two lines of code and not one.
func _on_timeout() -> void:
	if not is_host():
		return
	var ended := current()
	seconds_left = 0.0
	timer_updated.emit(0.0)
	timer_expired.emit(ended)
	# The clock does not drive the van somewhere the crew has not signed for.
	# It matters now that a paid shift comes back to the road rather than to the
	# menu: the board is cleared on the way in, and two minutes later this would
	# otherwise pull up at last job's house with nobody's name on the sheet. The
	# van waits instead, and leaves when the job is signed and the crew is ready
	# — which is `ReadyManager`'s business and happens the moment `blocked` goes
	# down.
	if ended == Phase.Type.TRAVEL and ReadyManager.blocked:
		return
	advance()

# --- The wire ---------------------------------------------------------------

## The phase change itself, run on every machine at once, the host included
## (`call_local`) — the host walking on alone while the crew stands in the van
## is exactly the bug that costs an evening to find.
##
## `authority` means Godot itself drops a packet from anybody but peer 1, so the
## check below is belt and braces: a client that somehow got one through is
## refused here and says so, which is the audit the robustness card asks for.
@rpc("authority", "call_local", "reliable")
func _apply(phase: Phase.Type) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != HOST_PEER:
		push_warning("PhaseManager: phase change from peer %d, which is not the host — ignored."
			% sender)
		return

	var previous: Phase.Type = SessionManager.phase
	if previous == phase:
		return

	# Cleared here and not in `go_to`, because `SessionManager` never touches the
	# wire: a reset done on the host alone leaves every client still holding the
	# flags it raised in the phase that just ended. The board in the next scene
	# would then be drawn green on a machine the host reads as red, and the man
	# standing at it would have to press it twice — once to un-ready a flag only
	# he can see, once to actually say it. Doing it in here puts the clearing in
	# the same packet as the phase, so all four machines forget together.
	SessionManager.reset_ready()

	SessionManager.phase = phase

	# Home from a shift. Everything the shift accumulated goes out with it —
	# the money made in the house, what is left in the crates, the pins on the
	# map, the contract that was signed for — so the crew arrives in the menu
	# with a clean board rather than with last job's numbers still on it.
	#
	# Not `SessionManager.reset()`, which is `NetworkGuard`'s wipe and takes the
	# crew with it: these men have not gone anywhere, they have finished a job.
	# What is cleared here is the shift, not the lobby.
	if phase == Phase.Type.LOBBY and previous != Phase.Type.LOBBY:
		_clear_shift()
	# Paid, and back in the van for the next one. Only the job goes in the bin
	# here — the money and the crates are what the crew worked for and are the
	# whole point of driving out again.
	elif previous == Phase.Type.RESULT:
		_clear_job()

	_start_clock(phase)

	# The same house for survey and for hunt: the traps stay where they were put
	# and nobody is teleported back to the doorstep. Only the phase moved.
	var scene := scene_of(phase)
	if scene.is_empty() or scene == _current_scene_path():
		phase_changed.emit(previous, phase)
		return
	_change_scene(scene, previous, phase)


## Loads the phase's scene, then says the phase changed — in that order, so that
## whatever wakes up in the new scene is built already knowing where it is. The
## wait of a frame is not politeness: `change_scene_to_file` is deferred by
## Godot, and announcing before it lands would announce to the scene on its way
## out.
## What one shift leaves behind, wiped on the way back to the menu. Done on
## every machine and not only on the host, because every one of these is a local
## tally: this player's money, this player's crates, this player's pay slip.
## The crew and their colours are untouched — they are the lobby's, and the
## lobby is where we are going.
##
## The purses go back to the first day's hundred rather than to nought
## (`SessionManager.reset_money`), because that is what the crew is handed when it
## is registered and a menu that gave them nothing would be a van that could not
## buy its first trap. It is the one thing here that is not local — it is the
## crew's replicated money — but it is a constant written the same way on every
## machine, so it needs no packet to stay in step.
func _clear_shift() -> void:
	Wallet.reset()
	Stock.reset()
	SessionManager.reset_money()
	_clear_job()


## The job itself, wiped: last house's pay slip, last house's pins, and the
## signature that named it. What a crew rolling out of one house and into the
## van needs gone before it signs for the next one — and the part of
## `_clear_shift` that is *only* about the job, so that going home to the menu
## and going back to the van do not each keep their own list of what to clear.
##
## The money and the crates are deliberately not in here. They belong to the
## crew rather than to the house, and they are what the shop in the van is for.
func _clear_job() -> void:
	ShiftReport.reset()
	MapManager.clear_all_pins()
	# Trap numbering starts over with the floor: `TrapManager` watches the lobby
	# for the same reason, and a crew that never passes through it on its way to
	# the next house would otherwise keep last job's count running.
	TrapManager.reset()
	# The van is held shut again by this, and not by a line here putting
	# `ReadyManager.blocked` up: that flag has one owner (`ContractManager`),
	# which watches the signature and raises it the moment there is not one. Two
	# places writing it is how it ends up stuck in a state neither of them meant.
	SessionManager.set_contract("")


func _change_scene(path: String, previous: Phase.Type, phase: Phase.Type) -> void:
	# The scene being left, held on to so that the announcement can wait for it
	# to actually be gone. `change_scene_to_file` takes it out of the tree and
	# queues it for freeing, and until that free lands its nodes are still
	# connected to `phase_changed` — so the house the crew has just walked out of
	# hears the phase that replaced it, tries to look a player up in a tree it is
	# no longer in, and takes the game down with it. Every node in a scene would
	# otherwise have to guard for that itself; waiting here is the one place it
	# can be done once.
	var outgoing := get_tree().current_scene

	_changing_scene = true
	get_tree().change_scene_to_file(path)
	await get_tree().process_frame

	# Capped rather than open-ended: a scene that somehow outlives its own free
	# must not hold the shift here for ever. Whatever is still standing after
	# these frames gets the signal and is welcome to it.
	var waited := 0
	while is_instance_valid(outgoing) and waited < SCENE_FREE_FRAMES:
		waited += 1
		await get_tree().process_frame

	_changing_scene = false
	phase_changed.emit(previous, phase)


## The clock the phase runs on: started on the host, and on a client only set to
## the full duration so that the HUD has a number to draw in the moment before
## the first packet lands. A phase with no duration stops the clock rather than
## starting one at zero, so that a HUD asking `has_timer()` and a HUD reading
## `seconds_left` never disagree.
func _start_clock(phase: Phase.Type) -> void:
	var duration := duration_of(phase)
	if duration <= 0.0:
		_stop_clock()
		return
	seconds_left = duration
	timer_updated.emit(seconds_left)
	if not is_host():
		return
	_until_sync = SYNC_INTERVAL
	_timer.start(duration)
	if _on_the_wire():
		_sync.rpc(seconds_left)


func _stop_clock() -> void:
	if _timer != null:
		_timer.stop()
	if seconds_left == 0.0:
		return
	seconds_left = 0.0
	timer_updated.emit(0.0)


## The host's half of the clock: read his own timer back, tell his own listeners
## every frame, and tell the room twice a second. The `Timer` is what actually
## ends the phase — this only reports on it.
func _tick_host(delta: float) -> void:
	if _timer == null or _timer.is_stopped():
		return
	seconds_left = _timer.time_left
	timer_updated.emit(seconds_left)
	_until_sync -= delta
	if _until_sync > 0.0:
		return
	_until_sync = SYNC_INTERVAL
	if _on_the_wire():
		_sync.rpc(seconds_left)


## The host's clock, landing on everybody else. `unreliable_ordered` on purpose:
## a dropped packet costs half a second of the client's own counting and the
## next one puts it right, whereas a resent one would arrive already stale. What
## `ordered` buys is that a packet overtaken in flight is thrown away rather
## than winding the number back up.
##
## Not `call_local` — the host is reading his own timer, and taking his own
## packet back would only be a staler version of the number he already has.
@rpc("authority", "unreliable_ordered")
func _sync(remaining: float) -> void:
	if multiplayer.get_remote_sender_id() != HOST_PEER:
		return
	seconds_left = maxf(0.0, remaining)
	timer_updated.emit(seconds_left)


## Where the tree is standing. Empty while a scene change is in flight, which is
## the one moment it must not be compared against a path and found equal.
func _current_scene_path() -> String:
	if _changing_scene:
		return ""
	var scene := get_tree().current_scene
	return "" if scene == null else scene.scene_file_path
