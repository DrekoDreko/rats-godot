extends SceneTree
## The strangling: the click is hammered, the pressure drains between one go and
## the next, and a rat that was already stuck gives in in half the squeezes.

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
	for scenario in ["hammering", "glue", "drain", "rising", "unowned"]:
		var hands = script.new()
		var rat := RatStub.new()
		root.add_child(rat)
		hands.camera = Camera3D.new()
		hands._rat = rat
		hands._effort = 0.5 if scenario == "glue" else 1.0
		if scenario in ["hammering", "glue"]:
			var goes: int = hands.squeezes_to_kill if scenario == "hammering" \
				else hands.squeezes_to_kill / 2
			for index in goes:
				assert(not rat.killed, "The rat must not give in before the last squeeze")
				hands.press_secondary()
			assert(rat.killed and rat.squeezes == goes and not rat.escaped,
				"Uninterrupted hammering kills in exactly its own count")
		elif scenario == "drain":
			for index in 6:
				hands.press_secondary()
			var halfway: float = hands._pressure
			hands._process(1.0)
			assert(hands._pressure > 0.0 and hands._pressure < halfway,
				"Pressure drains while nobody is clicking")
			hands._process(1.0)
			assert(is_zero_approx(hands._pressure) and not rat.escaped,
				"An empty neck is not yet a loose rat")
			hands._process(1.0)
			assert(rat.escaped and not rat.killed,
				"The rat gets loose after the empty beat")
		elif scenario == "rising":
			rat.ready_in_hand = false
			hands._process(10.0)
			assert(not rat.escaped, "The escape clock only starts once the rat is in hand")
		else:
			rat.owned = false
			hands.press_secondary()
			assert(rat.squeezes == 0 and is_zero_approx(hands._pressure),
				"A rat the host has not confirmed is not squeezed")
		hands.camera.free()
		hands.free()
		rat.free()
	print("OK: hammering, glue, drain, rising and ownership")
	quit()
