extends SceneTree

class RatStub extends Node3D:
	var killed := false
	var escaped := false
	var ready_in_hand := true
	var owned := true
	var squeezes := 0
	func is_in_hand() -> bool: return ready_in_hand
	func is_held_by_me() -> bool: return owned
	func squeeze() -> void: squeezes += 1
	func die_in_hands(_type: int) -> void: killed = true
	func escape() -> void: escaped = true

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var script: Script = load("res://scripts/weapons/hands.gd")
	var random_hands = script.new()
	seed(38219)
	for effort in [1.0, 0.5, 1.0]:
		random_hands._effort = effort
		var covered := [false, false, false]
		for sweep in 300:
			# Include consecutive first hits to cover new grabs as well.
			random_hands._hits = 0
			var previous: float = random_hands._previous_zone_center
			random_hands._start_sweep()
			var center: float = random_hands._previous_zone_center
			assert(random_hands._zone_start >= 0.08 - 0.00001)
			assert(random_hands._zone_start + random_hands._zone_width <= 0.92 + 0.00001)
			assert(is_equal_approx(random_hands._zone_width, 0.36 if effort == 0.5 else 0.18))
			if previous >= 0.0:
				assert(absf(center - previous) >= random_hands.MIN_ZONE_SHIFT - 0.00001)
			covered[clampi(int(center * 3.0), 0, 2)] = true
		assert(covered.all(func(value: bool) -> bool: return value), "Targets must reach every third of the track")
	random_hands.free()
	for scenario in ["success", "miss", "timeout", "rising", "unowned", "glue"]:
		var hands = script.new()
		var rat := RatStub.new()
		root.add_child(rat)
		hands.camera = Camera3D.new()
		hands._rat = rat
		hands._effort = 0.5 if scenario == "glue" else 1.0
		hands._start_sweep()
		if scenario in ["success", "glue"]:
			var previous_travel := 0.0
			for hit in 3:
				hands._process(0.1)
				var travel: float = 1.0 - hands._pointer
				assert(travel > previous_travel, "Each successful hit must speed up the next sweep")
				previous_travel = travel
				var previous: float = hands._zone_start
				hands._pointer = hands._zone_start + hands._zone_width * 0.5
				hands.press_secondary()
				assert(rat.killed == (hit == 2), "Must kill on exactly the third hit")
				if hit < 2:
					assert(hands._pointer == 1.0 and hands._zone_start != previous)
			assert(rat.squeezes == 3 and not rat.escaped)
		elif scenario == "miss":
			hands.press_secondary()
			assert(rat.escaped and rat.squeezes == 0)
		elif scenario == "timeout":
			hands._process(2.5)
			assert(rat.escaped and not rat.killed)
		elif scenario == "rising":
			rat.ready_in_hand = false
			hands._process(3.0)
			hands.press_secondary()
			assert(not rat.escaped and rat.squeezes == 0 and hands._pointer == 1.0)
		else:
			rat.owned = false
			hands._pointer = hands._zone_start
			hands.press_secondary()
			assert(rat.squeezes == 0)
		hands.camera.free()
		hands.free()
		rat.free()
	print("OK: three timed hits, moving targets, misses, timeout, rising, ownership and glue")
	quit()
