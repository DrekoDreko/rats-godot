extends SceneTree
## Bake the existing hazmat rig into an editable, dedicated seated idle clip.

func _initialize() -> void:
	call_deferred("_run")

func _aim(skeleton: Skeleton3D, bone_name: String, child_name: String, direction: Vector3) -> void:
	var bone := skeleton.find_bone("mixamorig_" + bone_name)
	var child := skeleton.find_bone("mixamorig_" + child_name)
	var pose := skeleton.get_bone_global_pose(bone)
	var old_direction := (skeleton.get_bone_global_pose(child).origin - pose.origin).normalized()
	var wanted := (skeleton.global_basis.inverse() * direction).normalized()
	pose.basis = Basis(Quaternion(old_direction, wanted)) * pose.basis
	var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone))
	skeleton.set_bone_pose_rotation(bone, (parent.basis.inverse() * pose.basis).get_rotation_quaternion())

func _run() -> void:
	var model := load("res://scenes/player_model.tscn").instantiate() as Node3D
	root.add_child(model)
	var skeleton := model.get_node("Hazmat/Armature/Skeleton3D") as Skeleton3D
	var player := model.get_node("Hazmat/AnimationPlayer") as AnimationPlayer
	player.play("Idle")
	player.advance(0.0)
	player.pause()
	var hips := skeleton.find_bone("mixamorig_Hips")
	skeleton.set_bone_pose_position(hips, skeleton.global_transform.affine_inverse() * Vector3(0, 0.13, 0))
	for side in ["Left", "Right"]:
		_aim(skeleton, side + "UpLeg", side + "Leg", Vector3(0, 0.12, -1))
		_aim(skeleton, side + "Leg", side + "Foot", Vector3(0, -0.82, -0.58))
		_aim(skeleton, side + "Foot", side + "ToeBase", Vector3(0, 0, -1))
		_aim(skeleton, side + "Arm", side + "ForeArm", Vector3(0, -1, -0.3))
		_aim(skeleton, side + "ForeArm", side + "Hand", Vector3(0, -0.3, -1))
	var animation := Animation.new()
	animation.resource_name = "SeatedIdle"
	animation.length = 4.0
	animation.loop_mode = Animation.LOOP_LINEAR
	for bone in skeleton.get_bone_count():
		var path := NodePath("Armature/Skeleton3D:" + skeleton.get_bone_name(bone))
		var track := animation.add_track(Animation.TYPE_POSITION_3D)
		animation.track_set_path(track, path)
		animation.position_track_insert_key(track, 0, skeleton.get_bone_pose_position(bone))
		track = animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, path)
		var rotation := skeleton.get_bone_pose_rotation(bone)
		animation.rotation_track_insert_key(track, 0, rotation)
		if skeleton.get_bone_name(bone) == "mixamorig_Spine2":
			animation.rotation_track_insert_key(track, 2, rotation * Quaternion(Vector3.RIGHT, 0.012))
			animation.rotation_track_insert_key(track, 4, rotation)
	var library := AnimationLibrary.new()
	library.add_animation("SeatedIdle", animation)
	var error := ResourceSaver.save(library, "res://resources/seated_animations.tres")
	print("Saved seated animation: ", error)
	quit(error)
