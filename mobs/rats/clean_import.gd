@tool
extends EditorScenePostImport
## Cleanup of `Rat_Fbx.fbx` on import.
##
## The FBX was exported with the whole Blender scene: along with the rat came the
## author's light and camera, and every animation has tracks pointing at those
## two nodes. Without this cleanup every rat on the map would carry a light of
## its own and the AnimationPlayer would complain about the orphan tracks every
## time a rat was born.
##
## The duplicate animations fall here too: the exporter generates a copy of each
## action for every object in the scene (`Camera|Run`, `Light|Attack`,
## `Rat Model|Death`), and only the ones with the `Rat|` prefix matter.

const DISCARDED_NODES := ["Light", "Camera"]
const ANIMATION_PREFIX := "Rat|"
## The two animations the rat repeats endlessly; the others play once.
const LOOPING_ANIMATIONS := ["Rat|Idle", "Rat|Run"]

func _post_import(scene: Node) -> Object:
	for node_name in DISCARDED_NODES:
		var node := scene.find_child(node_name, false, false)
		if node != null:
			node.free()

	var animator := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animator == null:
		return scene

	for library_name in animator.get_animation_library_list():
		var library := animator.get_animation_library(library_name)
		for animation_name in library.get_animation_list():
			if not animation_name.begins_with(ANIMATION_PREFIX):
				library.remove_animation(animation_name)
				continue
			var animation := library.get_animation(animation_name)
			_clear_tracks(animation)
			if animation_name in LOOPING_ANIMATIONS:
				animation.loop_mode = Animation.LOOP_LINEAR
	return scene

## Strips the animation of the tracks belonging to the nodes just removed.
func _clear_tracks(animation: Animation) -> void:
	for i in range(animation.get_track_count() - 1, -1, -1):
		if animation.track_get_path(i).get_name(0) in DISCARDED_NODES:
			animation.remove_track(i)
