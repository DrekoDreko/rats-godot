extends SceneTree
## Full scene transition: death, Van report, then the next map vote.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var phase = root.get_node("PhaseManager")
	var session = root.get_node("SessionManager")
	session.register_player(root.get_node("SteamManager").get_steam_id(), "Test player", true)
	session.phase = Phase.Type.HUNT
	TranslationServer.set_locale("pt_BR")
	var wrapper = load("res://scenes/game_post_process_wrapper.tscn").instantiate()
	wrapper.initial_scene = load("res://scenes/world.tscn")
	root.add_child(wrapper)
	current_scene = wrapper
	await process_frame
	await process_frame
	var report = root.get_node("ShiftReport")
	report.earned = 123
	var player = get_first_node_in_group("player")
	player.take_damage(player.max_health)
	await create_timer(3.5).timeout
	for frame in 10:
		await process_frame
	assert(phase.current() == Phase.Type.RESULT, "Death must wait at the report")
	assert(wrapper.current_game_scene_path() == "res://scenes/van_travel.tscn")
	assert(report.earned == 123, "Report must survive the return to the Van")
	var screen = wrapper.current_game_scene().get_node("ResultScreen")
	assert(screen.visible, "The report must be visible in the Van")
	assert(not get_first_node_in_group("player").is_dead(), "Van player is alive")
	assert(not root.get_node("ContractManager").voting_open, "Map vote must wait for the report")
	assert(phase.seconds_left == 0.0, "No travel countdown while reading results")
	if DisplayServer.get_name() != "headless":
		await create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("C:/Users/Ferrareto/AppData/Local/Temp/rats-result-screen.png")
	screen._on_ok_pressed()
	await process_frame
	await process_frame
	assert(phase.current() == Phase.Type.TRAVEL)
	assert(not screen.visible)
	assert(root.get_node("ContractManager").voting_open, "Confirmation opens the next map vote")
	assert(report.earned == 0, "Clear the old report only after confirmation")
	assert(get_first_node_in_group("player").is_ui_open(), "Map vote retains control of the player")
	print("Result flow: passed")
	quit()
