extends Node
## Screenshot rig: jumps the shift straight to a phase so the HUD can be
## photographed as it is in play. Not part of the game.

@export var phase_name := "HUNT"
## Whether to put the contract vote sheet away, so the HUD under it can be seen.
@export var dismiss_vote := false

func _ready() -> void:
	await get_tree().process_frame
	var manager := get_node("/root/PhaseManager")
	manager.go_to(Phase.Type.get(phase_name))
	if not dismiss_vote:
		return
	for i in 30:
		await get_tree().process_frame
	var root := get_tree().current_scene
	if root == null:
		return
	var vote := root.find_child("ContractVoteScreen", true, false) as CanvasItem
	if vote != null:
		vote.hide()
	var hud := root.find_child("HUD", true, false) as CanvasLayer
	if hud != null:
		hud.visible = true
