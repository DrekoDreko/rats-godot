class_name FloorShadow
extends Sprite3D
## A painted contact shadow that stays on the scenery below its owner.
##
## It is deliberately a separate visual node: the body may leave the ground,
## while this sprite follows the floor its feet left behind. The ray only sees
## scenery (layer 1), so it cannot mistake another character for the floor.

## The shadow stays readable in a normal jump, but loses a little weight as its
## owner gets further from the floor.
const MAX_HEIGHT := 2.0
const RAY_LENGTH := 30.0
const MIN_SCALE := 0.78
const FLOOR_OFFSET := 0.01
const RAY_START_HEIGHT := 0.1

@export var hide_while_captured := false


func _process(_delta: float) -> void:
	var body := get_parent() as Node3D
	if body == null:
		return
	if hide_while_captured and body.has_method(&"is_captured") and body.is_captured():
		visible = false
		return

	var space := get_world_3d().direct_space_state
	var from := body.global_position + Vector3.UP * RAY_START_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(
		from,
		from - Vector3.UP * RAY_LENGTH,
		1
	)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		visible = false
		return

	visible = true
	var floor_position: Vector3 = hit.position
	global_position = floor_position + Vector3.UP * FLOOR_OFFSET
	var height := maxf(body.global_position.y - floor_position.y, 0.0)
	var size := lerpf(1.0, MIN_SCALE, clampf(height / MAX_HEIGHT, 0.0, 1.0))
	scale = Vector3.ONE * size
