extends Label
## Shows how many rats are still loose on the map.

const INTERVAL := 0.2

var _total := 0
var _time := 0.0

func _ready() -> void:
	# Wait one frame so every rat is already in the tree.
	# Held onto before the wait rather than fetched again after it: a phase can
	# end on the frame this HUD is waiting through — the board in the van does
	# exactly that — and the node then resumes already out of the tree, where
	# `get_tree()` is null and reaching through it throws.
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame

	# Out of the tree while we waited: the scene we belong to was freed, there is
	# nobody left to wire to, and this HUD goes out with the rest of it.
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
