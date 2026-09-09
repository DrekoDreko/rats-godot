@tool
class_name VanSeat
extends Marker3D
## Origin is the cushion surface; -Z faces the aisle.

@export var standing_offset := Vector3(0, -0.25, -0.9):
	set(value):
		standing_offset = value
		if is_node_ready():
			$StandPoint.position = standing_offset

@export_range(1, 4) var seat_number := 1:
	set(value):
		seat_number = value
		if is_node_ready():
			$Number.text = str(seat_number)

func _ready() -> void:
	$Number.text = str(seat_number)
	$StandPoint.position = standing_offset

func standing_position() -> Vector3:
	return $StandPoint.global_position
