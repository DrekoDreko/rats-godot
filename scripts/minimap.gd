extends Control
class_name Minimap
## A round top-down dial of the current house, in the top corner of the HUD.
##
## The ground shape comes from the same NavigationMesh the rats use, filtered to
## the height of the node in the `minimap_floor` group. Player positions come
## from the local character and the replicated avatars, while the roster and
## colours come from the lobby/session autoloads.

const BACKGROUND_COLOR := Color("252629")
const WALKABLE_COLOR := Color("686b70")
const BORDER_COLOR := Color("a2a4a8")
const MAP_PADDING := 5.0
const PLAYER_MARKER_RADIUS := 4.5
const FLOOR_HEIGHT_TOLERANCE := 0.35
const MAP_ZOOM := 3.0
## How many sides the dial is cut with. It is both the shape the ground is
## clipped against and the circle that is drawn, so that the edge of the floor
## and the ring around it are the same curve to the pixel.
const DIAL_SIDES := 32

@export var navigation_path: NodePath = ^"../../Navigation"
@export var players_path: NodePath = ^"../../Players"
@export var player_path: NodePath = ^"../../Player"

var _navigation: NavigationRegion3D
var _avatars: Node
var _player: Node3D
var _floor: Node3D
var _members: Array[Dictionary] = []
var _walkable_polygons: Array[PackedVector2Array] = []
var _map_min := Vector2.ZERO
var _map_max := Vector2.ONE
var _map_ready := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_navigation = get_node_or_null(navigation_path) as NavigationRegion3D
	_avatars = get_node_or_null(players_path)
	_player = get_node_or_null(player_path) as Node3D
	_floor = get_tree().get_first_node_in_group("minimap_floor") as Node3D

	# The same HUD hangs over the road as over the house, and on the road there
	# is no house to draw. An empty dial is not a map, so it is not shown at all.
	if _navigation == null:
		hide()
		set_process(false)
		return

	LobbyManager.members_changed.connect(_on_members_changed)
	LobbyManager.lobby_left.connect(_on_lobby_left)
	SessionManager.player_joined.connect(_on_session_changed)
	SessionManager.player_left.connect(_on_session_changed)
	SessionManager.player_changed.connect(_on_session_changed)
	PhaseManager.phase_changed.connect(_on_phase_changed)
	_refresh_members()
	_update_navigation()
	_update_visibility()
	queue_redraw()


func _process(_delta: float) -> void:
	# NavigationRegion3D bakes in its _ready method. Polling here keeps the HUD
	# independent of scene child ordering and lets the background appear before
	# the baked geometry is available.
	_update_navigation()
	queue_redraw()


## The dial is round, so everything drawn in it is cut to the same circle rather
## than to the control's rectangle: `clip_contents` only knows about the box, and
## a floor spilling into the corners would be a floor outside the map.
func _draw() -> void:
	var dial := _dial()
	draw_colored_polygon(dial, BACKGROUND_COLOR)
	var viewer_position := _viewer_position()
	var viewer_yaw := _viewer_yaw()

	if _map_ready:
		for polygon in _walkable_polygons:
			var screen_polygon := PackedVector2Array()
			for point in polygon:
				screen_polygon.append(_map_to_screen(point, viewer_position, viewer_yaw))
			# A room reaching past the rim comes back as its clipped pieces, and
			# one lying wholly outside comes back as none.
			for piece in Geometry2D.intersect_polygons(screen_polygon, dial):
				# Tangencies at the rim can leave zero-area or collapsed pieces.
				# The renderer cannot triangulate those clipping artifacts.
				if Geometry2D.triangulate_polygon(piece).is_empty():
					continue
				draw_colored_polygon(piece, WALKABLE_COLOR)

	for marker in _markers():
		_draw_player_marker(
			marker["position"], marker["yaw"], marker["color"], viewer_position, viewer_yaw
		)

	draw_arc(size * 0.5, _dial_radius(), 0.0, TAU, DIAL_SIDES, BORDER_COLOR, 1.0)


## The rim, as a polygon: what the ground is clipped against and what the ring is
## drawn along. Half a side is taken off the radius so the drawn circle sits on
## the clipped edge instead of a hair outside it.
func _dial() -> PackedVector2Array:
	var center := size * 0.5
	var radius := _dial_radius()
	var points := PackedVector2Array()
	for i in DIAL_SIDES:
		var angle := TAU * float(i) / float(DIAL_SIDES)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	return points


func _dial_radius() -> float:
	return maxf(1.0, minf(size.x, size.y) * 0.5 - 1.0)


func _draw_player_marker(
	world_position: Vector3,
	yaw: float,
	color: Color,
	viewer_position: Vector2,
	viewer_yaw: float,
) -> void:
	if not _map_ready:
		return
	var center := _map_to_screen(
		Vector2(world_position.x, world_position.z), viewer_position, viewer_yaw
	)
	# A crewmate further out than the dial reaches is off the map, and half an
	# arrowhead poking through the rim reads as one still on it.
	if center.distance_to(size * 0.5) > _dial_radius() - PLAYER_MARKER_RADIUS:
		return
	# The map rotates with the viewer. Subtracting the viewer yaw keeps each
	# marker's own facing direction correct inside that rotating frame.
	draw_set_transform(center, viewer_yaw - yaw, Vector2.ONE)
	var marker := PackedVector2Array([
		Vector2(0.0, -PLAYER_MARKER_RADIUS),
		Vector2(PLAYER_MARKER_RADIUS * 0.75, PLAYER_MARKER_RADIUS * 0.7),
		Vector2(-PLAYER_MARKER_RADIUS * 0.75, PLAYER_MARKER_RADIUS * 0.7),
	])
	draw_colored_polygon(marker, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _viewer_position() -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return Vector2.ZERO
	return Vector2(_player.global_position.x, _player.global_position.z)


func _viewer_yaw() -> float:
	if _player == null or not is_instance_valid(_player):
		return 0.0
	return _player.global_rotation.y


func _update_navigation() -> void:
	if _map_ready or _navigation == null or _navigation.navigation_mesh == null \
		or _floor == null:
		return

	var mesh := _navigation.navigation_mesh
	var vertices := mesh.get_vertices()
	if vertices.is_empty() or mesh.get_polygon_count() == 0:
		return

	var floor_height := _floor.global_position.y
	var bounds_set := false
	_walkable_polygons.clear()

	for polygon_index in mesh.get_polygon_count():
		var polygon := PackedVector2Array()
		var polygon_min_y := INF
		var polygon_max_y := -INF
		for vertex_index in mesh.get_polygon(polygon_index):
			var world_vertex: Vector3 = _navigation.to_global(vertices[vertex_index])
			var point := Vector2(world_vertex.x, world_vertex.z)
			polygon.append(point)
			polygon_min_y = minf(polygon_min_y, world_vertex.y)
			polygon_max_y = maxf(polygon_max_y, world_vertex.y)

		# The navigation mesh can contain elevated islands on obstacle tops. The
		# minimap represents the main ground plane, so keep only flat polygons at
		# the height of the explicitly tagged Floor node.
		if polygon.size() < 3 \
			or polygon_min_y < floor_height - FLOOR_HEIGHT_TOLERANCE \
			or polygon_max_y > floor_height + FLOOR_HEIGHT_TOLERANCE:
			continue

		if not bounds_set:
			_map_min = polygon[0]
			_map_max = polygon[0]
			bounds_set = true
		for point in polygon:
			_map_min = _map_min.min(point)
			_map_max = _map_max.max(point)
		_walkable_polygons.append(polygon)

	_map_ready = not _walkable_polygons.is_empty()


func _map_to_screen(point: Vector2, viewer_position: Vector2, viewer_yaw: float) -> Vector2:
	var available := maxf(1.0, minf(size.x, size.y) - MAP_PADDING * 2.0)
	var map_extent := maxf(_map_max.x - _map_min.x, _map_max.y - _map_min.y)
	var pixels_per_world_unit := available / maxf(0.001, map_extent) * MAP_ZOOM
	var relative_position := (point - viewer_position).rotated(viewer_yaw)
	return size * 0.5 + relative_position * pixels_per_world_unit


func _markers() -> Array[Dictionary]:
	var markers: Array[Dictionary] = []
	var local_id := LobbyManager.our_crew_id()
	for member in _members:
		var steam_id := int(member.get("steam_id", 0))
		if steam_id == 0 or not SessionManager.has_player(steam_id):
			continue

		var body: Node3D = null
		if steam_id == local_id:
			body = _player
		elif _avatars != null and _avatars.has_method("avatar_for_steam_id"):
			body = _avatars.call("avatar_for_steam_id", steam_id) as Node3D
		if not is_instance_valid(body):
			continue

		markers.append({
			"position": body.global_position,
			"yaw": body.global_rotation.y,
			"color": SessionManager.color(steam_id),
		})
	return markers


func _refresh_members() -> void:
	_members = LobbyManager.list_players()
	if not _members.is_empty():
		return

	# Solo runs have no lobby id, but SessionManager still contains the one player
	# who must be visible on the map.
	for steam_id in SessionManager.players:
		_members.append({"steam_id": steam_id})


func _on_members_changed(members: Array[Dictionary]) -> void:
	_members = members
	if _members.is_empty():
		_refresh_members()
	queue_redraw()


func _on_lobby_left() -> void:
	_refresh_members()
	queue_redraw()


func _on_session_changed(_steam_id: int) -> void:
	_refresh_members()
	queue_redraw()


## The dial is off once the rats are loose. A corner map of the house would
## tell a hiding crew exactly where a strangled man last stood without them
## ever having to look away from the doorway — reading the house is the
## terminal's job now (`scripts/ui/terminal_screen.gd`), which asks a man
## to actually leave the hunt to check it. The survey keeps the dial: nothing
## is loose yet, and a man walking the house for holes still wants to know
## where he is in it.
func _on_phase_changed(_previous: Phase.Type, _current: Phase.Type) -> void:
	_update_visibility()


func _update_visibility() -> void:
	visible = PhaseManager.current() != Phase.Type.HUNT
