extends SceneTree
## The sprint reserve: what running spends, what the glue and the strangling
## charge, and the pause and the lockout that make any of it cost something.
##
## The player is built without its scene: nothing here touches the body, the
## camera or the arms, only the reserve and the rules over it. `_health` has to
## be set by hand — a freshly constructed player has none, and a dead one is
## never charged (`player.gd: _spend_stamina`).

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var script: Script = load("res://scripts/player.gd")
	var glue_script: Script = load("res://scripts/traps/glue_trap.gd")

	# --- The three costs ----------------------------------------------------
	var player = _fresh(script)
	var glue = glue_script.new()
	player.set_glue_state(glue, true, 0.0, Vector3.ZERO)
	_close(player.stamina_fraction(), 1.0 - player.stamina_glue_cost,
		"The glue takes its cost on the catch")
	# Every frame the player stays stuck says so again; only the edge is billed.
	for index in 30:
		player.set_glue_state(glue, true, 0.0, Vector3.ZERO)
	_close(player.stamina_fraction(), 1.0 - player.stamina_glue_cost,
		"Standing on the glue is charged once, not per frame")
	player.set_glue_state(glue, false, 0.0, Vector3.ZERO)
	glue.free()
	player.free()

	player = _fresh(script)
	player._held_rat_effort = 1.0
	player._on_weapon_finished(true)
	_close(player.stamina_fraction(), 1.0 - player.stamina_strangle_cost,
		"Strangling a rat that fought back takes the full price")
	player.free()

	player = _fresh(script)
	player._held_rat_effort = 0.35
	player._on_weapon_finished(true)
	_close(player.stamina_fraction(), 1.0 - player.stamina_strangle_pinned_cost,
		"A rat taken off the glue is the cheaper kill")
	player.free()

	# A rat that got loose cost him nothing.
	player = _fresh(script)
	player._held_rat_effort = 1.0
	# Constructed off the script rather than a bare Node3D with the script set:
	# the property is typed, and only the former satisfies it. Nothing under
	# the arms is touched — `set_gripping(false)` on a fresh one returns at its
	# own early exit.
	player.view_model = load("res://scripts/player_view_model.gd").new()
	player._on_weapon_finished(false)
	_close(player.stamina_fraction(), 1.0, "An escaped rat is not charged for")
	player.view_model.free()
	player.free()

	# --- The pause before it comes back -------------------------------------
	player = _fresh(script)
	player._spend_stamina(0.5)
	var after_cost: float = player.stamina_fraction()
	# Half the pause: still nothing back.
	player._update_stamina(player.stamina_recovery_delay * 0.5, Vector3.ZERO, false)
	_close(player.stamina_fraction(), after_cost,
		"Nothing comes back while the pause is still running")
	player._update_stamina(player.stamina_recovery_delay, Vector3.ZERO, false)
	player._update_stamina(0.5, Vector3.ZERO, false)
	assert(player.stamina_fraction() > after_cost,
		"The reserve comes back once the pause is out")
	player.free()

	# --- Running, emptying, and the lockout ---------------------------------
	player = _fresh(script)
	Input.action_press("run")
	var forward := Vector3.FORWARD
	# Run until it gives out, one physics step at a time, and stop on the step it
	# does: past that point the player is no longer sprinting and the same call
	# starts giving the reserve back, so there is no later frame at which an
	# emptied bar is still empty.
	var spent := 0.0
	while not player.is_exhausted() and spent < 30.0:
		player._update_stamina(0.05, forward, false)
		spent += 0.05
	assert(is_zero_approx(player.stamina_fraction()),
		"Holding the run key empties the reserve")
	# Within the step that emptied it: the loop stops after the step, not on the
	# instant the bar reached zero.
	var expected: float = player.max_stamina / player.stamina_drain_rate
	assert(spent >= expected and spent <= expected + 0.06,
		"A full bar lasts its own seconds of running (got %.2f, wanted %.2f)"
			% [spent, expected])
	assert(not player._is_sprinting(forward, false),
		"An exhausted player cannot run")

	# It stays locked while a sliver comes back: this is the stutter the latch
	# exists to stop.
	player._update_stamina(player.stamina_recovery_delay, Vector3.ZERO, false)
	player._update_stamina(0.05, forward, false)
	assert(player.stamina_fraction() > 0.0, "The bar is visibly refilling")
	assert(player.is_exhausted() and not player._is_sprinting(forward, false),
		"A sliver of stamina does not give the run back")

	# Past the threshold it does, and the run key bites again.
	while player.is_exhausted() and player.stamina_fraction() < 1.0:
		player._update_stamina(0.05, forward, false)
	assert(not player.is_exhausted(), "Enough of the bar back clears the lockout")
	# At the threshold, give or take the step that crossed it.
	var step: float = player.stamina_recovery_rate * 0.05 / player.max_stamina
	assert(player.stamina_fraction() >= player.stamina_exhaustion_recovery
			and player.stamina_fraction() <= player.stamina_exhaustion_recovery + step,
		"The lockout clears at the threshold and not before (got %.3f, wanted %.3f)"
			% [player.stamina_fraction(), player.stamina_exhaustion_recovery])
	assert(player._is_sprinting(forward, false), "And the run key works again")
	Input.action_release("run")
	player.free()

	print("OK: glue cost, strangle costs, escape, recovery pause and exhaustion")
	quit()


## A player with a whole bar and enough flesh to be charged.
func _fresh(script: Script):
	var player = script.new()
	player._health = player.max_health
	player._stamina = player.max_stamina
	return player


func _close(got: float, want: float, message: String) -> void:
	assert(absf(got - want) < 0.001, "%s (got %.3f, wanted %.3f)" % [message, got, want])
