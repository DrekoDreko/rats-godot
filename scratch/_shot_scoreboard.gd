extends Node
## Screenshot rig: a crew of three with different tallies, in the hunt, with the
## scoreboard key held down. Not part of the game.

func _ready() -> void:
	get_tree().root.add_child.call_deferred(Rig.new())


class Rig extends Node:
	func _ready() -> void:
		await get_tree().process_frame
		var session := get_node("/root/SessionManager")
		var lobby := get_node("/root/LobbyManager")
		var mine: int = lobby.our_steam_id()
		session.register_player(mine, "luscadreko", true)
		session.register_player(22, "ratkiller99")
		session.register_player(33, "bibi")
		session.set_catches(mine, 7)
		session.set_catches(22, 12)
		session.set_catches(33, 0)

		get_node("/root/PhaseManager").go_to(Phase.Type.HUNT)
		for i in 40:
			await get_tree().process_frame
		var ev := InputEventAction.new()
		ev.action = "player_list"
		ev.pressed = true
		Input.parse_input_event(ev)
