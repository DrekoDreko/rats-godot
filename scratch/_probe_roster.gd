extends Node
## Bench: the Tab scoreboard. Proves it is shut until `player_list` is held, that
## it only answers in TRAVEL and HUNT, and that a catch reaches the crew's row.
## Not part of the game.
##
## The work runs on a node parented to `root` rather than on this one: every
## phase change frees the current scene, and a probe that lived in it would be
## gone before the second phase.

func _ready() -> void:
	get_tree().root.add_child.call_deferred(Probe.new())


class Probe extends Node:
	func _ready() -> void:
		await get_tree().process_frame
		var session := get_node("/root/SessionManager")
		var lobby := get_node("/root/LobbyManager")
		# Our own Steam ID and not an invented one: the tally is written against
		# whoever `our_crew_id` says we are, and a crew we are not in would swallow
		# it silently.
		var mine: int = lobby.our_steam_id()
		session.register_player(mine, "ME", true)
		session.register_player(22, "BETA")

		var manager := get_node("/root/PhaseManager")
		for phase_name in ["TRAVEL", "SURVEY", "HUNT"]:
			manager.go_to(Phase.Type.get(phase_name))
			for i in 30:
				await get_tree().process_frame
			var board := get_tree().get_first_node_in_group("scoreboard")
			if board == null:
				print("PROBE %s: no scoreboard" % phase_name)
				continue
			var panel: Control = board.get_node("Center")
			var idle := panel.visible
			_send(true)
			await get_tree().process_frame
			var held := panel.visible
			var rows := board.get_node("Center/Panel/Margin/Rows/Crew").get_child_count()
			_send(false)
			await get_tree().process_frame
			print("PROBE %s: idle=%s held=%s rows=%d released=%s" % [
				phase_name, idle, held, rows, panel.visible])

		# A rat, paid for in the hunt: the tally has to land on the crew's row and
		# not merely on this machine's pay slip.
		var wallet := get_node("/root/Wallet")
		var report := get_node("/root/ShiftReport")
		wallet.collect(load("res://resources/species/common_rat.tres"), Death.Type.STRANGULATION)
		await get_tree().process_frame
		print("PROBE catch: crew_id=%d slip=%d crew_row=%d other=%d" % [
			mine, report.caught, session.catches(mine), session.catches(22)])

		# End of the job wipes it, on every machine at once.
		report.reset()
		print("PROBE after reset: crew_row=%d" % session.catches(mine))
		get_tree().quit()

	func _send(pressed: bool) -> void:
		var ev := InputEventAction.new()
		ev.action = "player_list"
		ev.pressed = pressed
		Input.parse_input_event(ev)
