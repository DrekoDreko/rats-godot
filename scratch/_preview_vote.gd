extends SceneTree
## Throwaway: puts the contract vote sheets up on their own and saves a shot,
## so the layout can be measured against the 640x360 the game is drawn at.
##
## Run with: godot --script scratch/_preview_vote.gd

const VOTE := "res://scenes/contract_vote_screen.tscn"
const SHOT := "res://scratch/vote_preview.png"

var _screen: Control
var _clock := 0


func _initialize() -> void:
	Engine.max_fps = 60


func _physics_process(_delta: float) -> bool:
	_clock += 1
	if _clock == 1:
		var session := root.get_node_or_null("SessionManager")
		session.register_player(111, "Lucas", true)
		root.size = Vector2i(640, 360)
		_screen = (load(VOTE) as PackedScene).instantiate() as Control
		root.add_child(_screen)
		return false
	if _clock == 10:
		var contracts := root.get_node_or_null("ContractManager")
		contracts.voting_open = true
		contracts.voting_opened.emit()
		return false
	if _clock == 30:
		print("viewport ", root.get_visible_rect().size)
		for path in ["Center/Rows", "Center/Rows/Title", "Center/Rows/CardsRow",
				"Center/Rows/TimeRow", "Center/Rows/Rate", "Center/Rows/Start",
				"Center/Rows/Hint"]:
			var node := _screen.get_node_or_null(path) as Control
			if node != null:
				print(path, " ", node.get_global_rect())
		var image := root.get_texture().get_image()
		image.save_png(SHOT)
		print("saved ", SHOT)
		return true
	return false
