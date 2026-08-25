extends Label
## Shows how many rats are still loose on the map.

const INTERVAL := 0.2

var _total := 0
var _time := 0.0

func _ready() -> void:
	# Wait one frame so every rat is already in the tree.
	await get_tree().process_frame
	# A phase can end on the frame this HUD is waiting through — the board in the
	# van does exactly that — and a node that wakes up under a freed scene has no
	# tree left to look a player up in. There is nobody to wire to in that case,
	# and the HUD is on its way out with the rest of the scene anyway.
	if not is_inside_tree():
		return
	_update()

func _process(delta: float) -> void:
	_time -= delta
	if _time > 0.0:
		return
	_time = INTERVAL
	_update()

func _update() -> void:
	var alive := get_tree().get_nodes_in_group("rats").size()
	_total = maxi(_total, alive)
	text = "Rats: %d / %d" % [alive, _total]
