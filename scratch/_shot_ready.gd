extends Node
## Screenshot rig: the terminal on the shop page with a crew of four, two of
## them ready, so the READY button in the footer and the crew list down the left
## can be looked at at the size the glass actually is. Not part of the game.

const TERMINAL := preload("res://scenes/terminal_screen.tscn")

## The glass itself (`world.tscn`, Van/StoreTerminal/Screen/Viewport).
const GLASS := Vector2i(640, 507)

const SHOTS := "C:/Users/FERRAR~1/AppData/Local/Temp/claude/C--Users-Ferrareto-Documents-Lucas-GAMES-rats-godot/c7cea5f2-53f2-448d-b664-217cb1cc6f2f/scratchpad/"

const TRAVEL := 1
const HUNT := 3

var _view: SubViewport
var _terminal: Control


class PreviewUser extends Node3D:
	func set_ui_open(_is_open: bool) -> void:
		pass


func _ready() -> void:
	# Our own Steam ID and not an invented one: the screen draws itself against
	# whoever `our_steam_id` says we are, and a crew we are not in leaves it
	# showing "PLAYER" and an empty purse.
	var mine := LobbyManager.our_steam_id()
	var crew := [mine, 222, 333, 444]
	SessionManager.register_player(mine, "Lucas", true)
	SessionManager.register_player(222, "Bruno")
	SessionManager.register_player(333, "Joao")
	SessionManager.register_player(444, "Nome Bem Comprido")
	for index in crew.size():
		SessionManager.set_color(crew[index], SessionManager.COLORS[index])

	# The road, without the van: the phase is what opens the shelf, and loading
	# the scene with it would put a second terminal in the shot. Before the
	# flags, because a phase change clears them (`PhaseManager._apply`).
	PhaseManager.scenes[TRAVEL] = ""
	PhaseManager.go_to(TRAVEL)
	SessionManager.set_ready(222, true)
	SessionManager.set_ready(333, true)
	SessionManager.set_bank_balance(400)

	_view = SubViewport.new()
	_view.size = GLASS
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)

	_terminal = TERMINAL.instantiate()
	_view.add_child(_terminal)
	var user := PreviewUser.new()
	add_child(user)
	await get_tree().process_frame
	_terminal.open(user)

	await _settle()
	await _shot("ready_shot.png")

	# Us as well, which is what turns the button.
	SessionManager.set_ready(mine, true)
	ReadyManager.ready_changed.emit(mine, true)
	await _settle()
	await _shot("ready_shot_said.png")

	# The same, with a job signed: the amber above is the van being held by the
	# vote (`ContractManager`), and green is what it reads once it is let go.
	ReadyManager.blocked = false
	await _settle()
	await _shot("ready_shot_green.png")

	# And out in the hunt, where nobody is waiting on a show of hands: the
	# button goes dead rather than taking presses the host would refuse.
	PhaseManager.scenes[HUNT] = ""
	PhaseManager.go_to(HUNT)
	await _settle()
	await _shot("ready_shot_hunt.png")

	get_tree().quit()


func _settle() -> void:
	for i in 20:
		await get_tree().process_frame


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	_view.get_texture().get_image().save_png(SHOTS + file)
	print("shot written: ", SHOTS + file)
