"""Builds `models/box_van.glb`: the walk-in pest-control truck the crew works out of.

Run it inside Blender (or through the Blender MCP server) and it writes the
`.glb` beside itself. It is checked in so that the truck can be rebuilt rather
than only edited: the shape is the numbers at the top of this file, and moving a
wall is changing one of them and running it again.

Why a second van at all, with `models/van.glb` already in the map: that one is a
panel van, and its cargo bay is 2.38 m across and 2.23 m of headroom. Four
players, a colour panel, a clipboard, a shelf of traps, a map table and a ready
board do not fit in it — two people passing each other in there have to breathe
in. This one is a box body on the same cab: 3.2 m across the inside, 7 m of it,
and 2.4 m of standing room, which is a corridor down the middle with a station
on either side and nobody stuck behind anybody.

The style is the older van's, deliberately, down to the material names and
colours: flat-shaded boxes, one flat colour per part, no bevels, no smoothing,
no textures. Everything is built from `_box` and `_plane`, and the PS1 shader in
Godot is what actually dresses it (`scripts/ps1.gdshader`).

Axes are Blender's — **Z is up**, +Y is forward towards the cab, and the origin
sits on the ground at the middle of the cargo floor. Godot's importer turns that
into its own Y-up, which is why the numbers here read one way and the `.tscn`
another.
"""

import bpy
import os
import math

# --- The shape, in metres ---------------------------------------------------
# The inside of the box is what everything else is arranged around: it is the
# room the crew actually walks in, and the card asks for four of them plus the
# stations. The walls are built outwards from it.

## Half the inside width, the inside length and the standing headroom.
BOX_HALF_WIDTH = 1.6
BOX_LENGTH = 7.0
BOX_HEIGHT = 2.4

## How thick a wall, the floor and the roof are drawn. Thin enough to read as
## sheet metal, thick enough that the seam never shows a gap from inside.
WALL = 0.08

## How high the cargo floor sits off the ground. It is a step van: the floor is
## low so that the ramp is short and a player walks in rather than climbs.
FLOOR_HEIGHT = 0.62

## Where the box ends and the cab begins, measured along +Y from the origin.
BOX_FRONT = BOX_LENGTH * 0.5
BOX_BACK = -BOX_LENGTH * 0.5

## The cab: shorter and a little narrower than the box, the way a box body
## always overhangs the cab it is bolted to.
CAB_LENGTH = 1.9
CAB_HALF_WIDTH = 1.45
CAB_HEIGHT = 1.85

## The rear doorway the crew walks through, and the ramp folded down out of it.
DOOR_HALF_WIDTH = 1.15
DOOR_HEIGHT = 2.1
RAMP_LENGTH = 2.4
RAMP_WIDTH = 2.0
RAMP_THICKNESS = 0.09

## Where the ramp ends up once it is tilted, worked out here rather than in the
## middle of `_rear()` so that the `.tscn` can copy the same numbers into its
## collision box instead of guessing at them.
##
## It is a plank of `RAMP_LENGTH` laid from the doorway sill down to the road.
## The rotation is about the plank's own centre, so the centre is what has to be
## placed: half a plank back from the sill along the slope, and half a plank
## down it. The plank then has to be dropped by half its own thickness measured
## *perpendicular to the slope*, or its top face — the face that is walked on —
## ends up half a thickness above the floor it is supposed to meet.
RAMP_ANGLE = math.asin(min(FLOOR_HEIGHT / RAMP_LENGTH, 1.0))
_RAMP_SINK = RAMP_THICKNESS * 0.5
RAMP_CENTRE = (
	BOX_BACK - math.cos(RAMP_ANGLE) * RAMP_LENGTH * 0.5 + math.sin(RAMP_ANGLE) * _RAMP_SINK,
	FLOOR_HEIGHT - math.sin(RAMP_ANGLE) * RAMP_LENGTH * 0.5 - math.cos(RAMP_ANGLE) * _RAMP_SINK,
)


def ramp_offset(across: float, up: float) -> tuple:
	"""A point `across` metres to the side and `up` metres above the ramp's own
	top face, given back in the van's own coordinates.

	The rails need this. A rail placed by adding to `RAMP_CENTRE[1]` would rise
	straight up while the plank under it runs away downhill, which is how it
	ends up floating in the air at one end and buried at the other. Going up
	*perpendicular to the slope* is what keeps it lying on the plank.
	"""
	return (
		across,
		RAMP_CENTRE[0] - math.sin(RAMP_ANGLE) * up,
		RAMP_CENTRE[1] + math.cos(RAMP_ANGLE) * up,
	)

## The wheels. Six of them, doubled up at the back the way a truck this size is.
WHEEL_RADIUS = 0.52
WHEEL_WIDTH = 0.34
WHEEL_SIDES = 12
## How far outboard the innermost rear tyre sits. A wheel of this radius stands
## `2 * WHEEL_RADIUS` tall, which is well above the cargo floor — so the only
## thing keeping a tyre from surfacing inside the van is this number, and it has
## to clear the side wall outright rather than tuck under it.
WHEEL_TRACK = BOX_HALF_WIDTH + WALL + WHEEL_WIDTH * 0.5

## The palette, straight off `van.glb` so that the two vehicles are the same
## fleet: `(base colour, roughness, metallic)`.
MATERIALS = {
	"VAN_Body": ((0.72, 0.19, 0.16), 0.6, 0.0),
	"VAN_Box": ((0.78, 0.76, 0.71), 0.75, 0.0),
	"VAN_Trim": ((0.09, 0.09, 0.10), 0.7, 0.0),
	"VAN_Bumper": ((0.30, 0.30, 0.32), 0.6, 0.0),
	"VAN_Floor": ((0.13, 0.13, 0.14), 0.9, 0.0),
	"VAN_Interior": ((0.26, 0.24, 0.23), 0.85, 0.0),
	"VAN_Seat": ((0.17, 0.16, 0.19), 0.85, 0.0),
	"VAN_Glass": ((0.22, 0.42, 0.52), 0.25, 0.0),
	"VAN_HeadLight": ((0.95, 0.93, 0.78), 0.2, 0.0),
	"VAN_TailLight": ((0.68, 0.09, 0.07), 0.3, 0.0),
	"VAN_Tire": ((0.045, 0.045, 0.05), 0.9, 0.0),
	"VAN_Rim": ((0.55, 0.56, 0.58), 0.35, 1.0),
	"VAN_Shelf": ((0.34, 0.31, 0.27), 0.8, 0.0),
}

_root = None


def build() -> str:
	"""Everything, from an empty scene to a written `.glb`. Returns the path."""
	_clear()
	_materials()

	global _root
	_root = bpy.data.objects.new("Van_Root", None)
	bpy.context.scene.collection.objects.link(_root)

	_shell()
	_cab()
	_rear()
	_wheels()
	_interior()

	return _export()

# --- The body ---------------------------------------------------------------


def _shell() -> None:
	"""The box: floor, roof and three walls, with a doorway left in the fourth.

	Built as separate slabs rather than as one hollowed cube on purpose — a
	boolean would leave n-gons and the whole point of the style is that every
	face is a quad somebody placed.
	"""
	inner_floor = FLOOR_HEIGHT
	inner_roof = FLOOR_HEIGHT + BOX_HEIGHT
	length = BOX_LENGTH
	mid_y = (BOX_FRONT + BOX_BACK) * 0.5

	_box("Box_Floor", (0.0, mid_y, inner_floor - WALL * 0.5),
		(BOX_HALF_WIDTH * 2 + WALL * 2, length, WALL), "VAN_Box")
	_box("Box_Roof", (0.0, mid_y, inner_roof + WALL * 0.5),
		(BOX_HALF_WIDTH * 2 + WALL * 2, length, WALL), "VAN_Box")

	for side, sign in (("L", -1.0), ("R", 1.0)):
		_box("Box_Side_%s" % side,
			(sign * (BOX_HALF_WIDTH + WALL * 0.5), mid_y, inner_floor + BOX_HEIGHT * 0.5),
			(WALL, length, BOX_HEIGHT), "VAN_Box")

	# The bulkhead between the crew and the cab, and the ribs down the outside
	# that make a box body read as a box body rather than as a crate.
	_box("Box_Bulkhead", (0.0, BOX_FRONT - WALL * 0.5, inner_floor + BOX_HEIGHT * 0.5),
		(BOX_HALF_WIDTH * 2, WALL, BOX_HEIGHT), "VAN_Interior")

	rib_count = 5
	for index in range(rib_count):
		# Spread along the box, clear of both ends so a rib never lands on the
		# doorway edge or on the bulkhead seam.
		span = length - 1.4
		y = BOX_BACK + 0.7 + span * index / float(rib_count - 1)
		for side, sign in (("L", -1.0), ("R", 1.0)):
			_box("Box_Rib_%s%d" % (side, index + 1),
				(sign * (BOX_HALF_WIDTH + WALL + 0.015), y, inner_floor + BOX_HEIGHT * 0.5),
				(0.03, 0.1, BOX_HEIGHT - 0.1), "VAN_Trim")

	# The skirt hiding the chassis rails, one down each side.
	for side, sign in (("L", -1.0), ("R", 1.0)):
		_box("Van_Skirt_%s" % side,
			(sign * (BOX_HALF_WIDTH + WALL * 0.5), mid_y + 0.2, FLOOR_HEIGHT - 0.22),
			(0.07, length - 1.2, 0.3), "VAN_Trim")


def _cab() -> None:
	"""The driving end: the same red cab as the panel van, one box and its glass."""
	front = BOX_FRONT + CAB_LENGTH
	mid_y = (BOX_FRONT + front) * 0.5
	base = FLOOR_HEIGHT - 0.18

	_box("Cab_Body", (0.0, mid_y, base + CAB_HEIGHT * 0.5),
		(CAB_HALF_WIDTH * 2, CAB_LENGTH, CAB_HEIGHT), "VAN_Body")

	# Windscreen and side glass, as planes sitting just proud of the body so
	# they never z-fight with it.
	_plane("Cab_Windscreen", (0.0, front - 0.01, base + CAB_HEIGHT - 0.62),
		(CAB_HALF_WIDTH * 2 - 0.3, 0.95), "VAN_Glass", rotation=(math.pi * 0.5, 0.0, 0.0))
	for side, sign in (("L", -1.0), ("R", 1.0)):
		_plane("Cab_Window_%s" % side,
			(sign * (CAB_HALF_WIDTH + 0.01), mid_y + 0.15, base + CAB_HEIGHT - 0.6),
			(CAB_LENGTH - 0.55, 0.8), "VAN_Glass",
			rotation=(math.pi * 0.5, 0.0, math.pi * 0.5))

	_box("Van_Bumper_Front", (0.0, front + 0.12, base + 0.18),
		(CAB_HALF_WIDTH * 2 + 0.1, 0.24, 0.34), "VAN_Bumper")
	_box("Van_Grille", (0.0, front + 0.02, base + 0.62),
		(CAB_HALF_WIDTH * 1.4, 0.1, 0.3), "VAN_Trim")
	for side, sign in (("L", -1.0), ("R", 1.0)):
		_box("Van_Headlight_%s" % side, (sign * (CAB_HALF_WIDTH - 0.3), front + 0.03, base + 0.5),
			(0.5, 0.1, 0.22), "VAN_HeadLight")
		_box("Van_Mirror_%s" % side,
			(sign * (CAB_HALF_WIDTH + 0.16), front - 0.35, base + CAB_HEIGHT - 0.45),
			(0.26, 0.08, 0.3), "VAN_Trim")

	# The roof beacon: a pest-control truck has one, and in the parked lobby it
	# is the thing that says which van on the street is yours.
	_box("Van_Beacon", (0.0, front - 0.45, base + CAB_HEIGHT + 0.08),
		(0.42, 0.3, 0.16), "VAN_TailLight")


def _rear() -> None:
	"""The back: the doorway frame, the door hung open, the ramp and the lights.

	The doorway is left as a hole by building the rear wall as three pieces —
	two jambs and a header — rather than by cutting one.
	"""
	inner_floor = FLOOR_HEIGHT
	jamb = BOX_HALF_WIDTH - DOOR_HALF_WIDTH

	for side, sign in (("L", -1.0), ("R", 1.0)):
		_box("Box_Jamb_%s" % side,
			(sign * (DOOR_HALF_WIDTH + jamb * 0.5), BOX_BACK + WALL * 0.5,
				inner_floor + BOX_HEIGHT * 0.5),
			(jamb, WALL, BOX_HEIGHT), "VAN_Box")

	header = BOX_HEIGHT - DOOR_HEIGHT
	_box("Box_Header", (0.0, BOX_BACK + WALL * 0.5, inner_floor + BOX_HEIGHT - header * 0.5),
		(DOOR_HALF_WIDTH * 2, WALL, header), "VAN_Box")

	# The roll-up door, drawn as a slab tucked under the roof: this van is
	# parked with its back open and stays that way through the lobby.
	_box("Box_Door_Rolled", (0.0, BOX_BACK + 0.28, inner_floor + BOX_HEIGHT - 0.16),
		(DOOR_HALF_WIDTH * 2 - 0.05, 0.4, 0.24), "VAN_Trim")

	# The ramp, folded down from the sill to the ground. Its own object so that
	# Godot can hang a collision box on it at the same angle
	# (`RAMP_ANGLE`/`RAMP_CENTRE` below are what the `.tscn` copies).
	_box("Van_Ramp", (0.0, RAMP_CENTRE[0], RAMP_CENTRE[1]),
		(RAMP_WIDTH, RAMP_LENGTH, RAMP_THICKNESS), "VAN_Bumper",
		rotation=(-RAMP_ANGLE, 0.0, 0.0))
	# A kerb down each edge of it. It is what makes the ramp read as a ramp from
	# inside the van rather than as a lighter patch of road, and it is placed
	# along the slope (`ramp_offset`) rather than straight up from the middle of
	# it — see the note on that function.
	for side, sign in (("L", -1.0), ("R", 1.0)):
		_box("Van_Ramp_Rail_%s" % side,
			ramp_offset(sign * (RAMP_WIDTH * 0.5 - 0.05), RAMP_THICKNESS * 0.5 + 0.04),
			(0.1, RAMP_LENGTH - 0.1, 0.09), "VAN_Trim",
			rotation=(-RAMP_ANGLE, 0.0, 0.0))

	# Two stubs of bumper rather than one bar across the back: the ramp comes
	# down the middle of the doorway, and a bar there would be a shin-high step
	# at the top of it.
	for side, sign in (("L", -1.0), ("R", 1.0)):
		_box("Van_Bumper_Rear_%s" % side,
			(sign * (BOX_HALF_WIDTH - 0.22), BOX_BACK - 0.06, FLOOR_HEIGHT - 0.2),
			(0.62, 0.2, 0.2), "VAN_Bumper")
	for side, sign in (("L", -1.0), ("R", 1.0)):
		_box("Van_Taillight_%s" % side,
			(sign * (BOX_HALF_WIDTH - 0.18), BOX_BACK - 0.05, FLOOR_HEIGHT + 0.2),
			(0.3, 0.08, 0.34), "VAN_TailLight")


def _wheels() -> None:
	"""Six wheels: singles at the front, doubles at the back.

	All of them are hung outboard of the box walls (`WHEEL_TRACK`) rather than
	tucked under it. A truck this shape has its arches proud of the body anyway,
	and it means no tyre can ever surface through the floor the crew stands on.
	"""
	front_y = BOX_FRONT + CAB_LENGTH * 0.45
	rear_y = BOX_BACK + 1.75

	for side, sign in (("L", -1.0), ("R", 1.0)):
		_wheel("Van_Wheel_F%s" % side,
			(sign * (CAB_HALF_WIDTH + WHEEL_WIDTH * 0.25), front_y, WHEEL_RADIUS))
		for index, offset in enumerate((0.0, WHEEL_WIDTH * 0.95)):
			_wheel("Van_Wheel_R%s%d" % (side, index + 1),
				(sign * (WHEEL_TRACK + offset), rear_y, WHEEL_RADIUS))
			# An arch over each rear pair, so the tyres read as belonging to the
			# body rather than as being parked beside it.
			if index == 0:
				_box("Van_Arch_%s" % side,
					(sign * (WHEEL_TRACK + WHEEL_WIDTH * 0.5), rear_y,
						FLOOR_HEIGHT - 0.04),
					(WHEEL_WIDTH * 2.4, WHEEL_RADIUS * 2.5, 0.1), "VAN_Trim")


def _interior() -> None:
	"""What is bolted inside: the floor plate, the benches down the walls and the
	empty shelving the shop will fill.

	None of it is a station. The stations are Godot scenes dropped into the van
	(`scenes/lobby_van.tscn`) so that they can light up, be interacted with and
	be moved without re-exporting a model — what is here is the furniture they
	are bolted to.
	"""
	mid_y = (BOX_FRONT + BOX_BACK) * 0.5

	_plane("Int_Floor", (0.0, mid_y, FLOOR_HEIGHT + 0.002),
		(BOX_HALF_WIDTH * 2, BOX_LENGTH), "VAN_Floor")

	# A bench down each side, low enough to sit on and to stand a crate on.
	for side, sign in (("L", -1.0), ("R", 1.0)):
		_box("Int_Bench_%s" % side,
			(sign * (BOX_HALF_WIDTH - 0.22), mid_y + 1.4, FLOOR_HEIGHT + 0.21),
			(0.44, 2.4, 0.42), "VAN_Seat")

	# Shelving above the right-hand bench, where the traps ride.
	#
	# On the right and over the bench on purpose, and both halves of that matter.
	# The **left** wall is left clear along its whole length because that is
	# where the stations go (`scenes/lobby_van.tscn`) — a shelf crossing at chest
	# height in front of a panel is a shelf the player's eye and his interaction
	# ray both have to get past. And it sits over the **bench** rather than over
	# open floor so that the walkway down the middle keeps its full height: a
	# crew of four passing each other should not have to duck.
	for index in range(2):
		_box("Int_Shelf_R%d" % (index + 1),
			(BOX_HALF_WIDTH - 0.2, mid_y + 1.4, FLOOR_HEIGHT + 0.95 + index * 0.55),
			(0.4, 2.2, 0.05), "VAN_Shelf")

		# A lip along the front edge, so that a box on the shelf reads as being
		# held there rather than balanced on a plank.
		_box("Int_Shelf_R%d_Lip" % (index + 1),
			(BOX_HALF_WIDTH - 0.38, mid_y + 1.4, FLOOR_HEIGHT + 1.0 + index * 0.55),
			(0.04, 2.2, 0.08), "VAN_Shelf")

	# The two cab seats, seen through the bulkhead doorway.
	for side, sign in (("L", -1.0), ("R", 1.0)):
		base_y = BOX_FRONT + CAB_LENGTH * 0.4
		_box("Int_Seat_%s_Base" % side, (sign * 0.62, base_y, FLOOR_HEIGHT - 0.1),
			(0.6, 0.55, 0.16), "VAN_Seat")
		_box("Int_Seat_%s_Back" % side, (sign * 0.62, base_y - 0.28, FLOOR_HEIGHT + 0.3),
			(0.6, 0.16, 0.72), "VAN_Seat")

	_box("Int_Dashboard", (0.0, BOX_FRONT + CAB_LENGTH - 0.3, FLOOR_HEIGHT + 0.32),
		(CAB_HALF_WIDTH * 1.8, 0.4, 0.34), "VAN_Interior")
	_box("Int_Wheel_Rim", (-0.62, BOX_FRONT + CAB_LENGTH - 0.62, FLOOR_HEIGHT + 0.5),
		(0.44, 0.44, 0.05), "VAN_Trim", rotation=(math.pi * 0.42, 0.0, 0.0))

# --- Primitives -------------------------------------------------------------


def _box(name: str, location, size, material: str, rotation=(0.0, 0.0, 0.0)):
	"""One flat-shaded cuboid, parented to the root. `size` is the full extent."""
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = size
	bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
	return _finish(obj, material)


def _plane(name: str, location, size, material: str, rotation=(0.0, 0.0, 0.0)):
	"""One flat quad, for glass and for the floor plate."""
	bpy.ops.mesh.primitive_plane_add(size=1.0, location=location, rotation=rotation)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = (size[0], size[1], 1.0)
	bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
	return _finish(obj, material)


def _wheel(name: str, location):
	"""A tyre with a rim face, as few sides as reads round at a distance."""
	bpy.ops.mesh.primitive_cylinder_add(
		vertices=WHEEL_SIDES, radius=WHEEL_RADIUS, depth=WHEEL_WIDTH,
		location=location, rotation=(0.0, math.pi * 0.5, 0.0))
	obj = bpy.context.active_object
	obj.name = name
	_finish(obj, "VAN_Tire")

	rim = WHEEL_RADIUS * 0.55
	sign = 1.0 if location[0] > 0.0 else -1.0
	bpy.ops.mesh.primitive_cylinder_add(
		vertices=WHEEL_SIDES, radius=rim, depth=0.04,
		location=(location[0] + sign * (WHEEL_WIDTH * 0.5 + 0.02), location[1], location[2]),
		rotation=(0.0, math.pi * 0.5, 0.0))
	hub = bpy.context.active_object
	hub.name = "%s_Rim" % name
	_finish(hub, "VAN_Rim")
	return obj


def _finish(obj, material: str):
	"""Flat shading, one material, parented to the root — every part gets this."""
	obj.data.materials.append(bpy.data.materials[material])
	for polygon in obj.data.polygons:
		polygon.use_smooth = False
	obj.parent = _root
	obj.matrix_parent_inverse = _root.matrix_world.inverted()
	return obj

# --- Scene plumbing ---------------------------------------------------------


def _clear() -> None:
	"""An empty scene. The truck is built from nothing every time, so that a
	rebuild is a rebuild and not a second truck on top of the first."""
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete(use_global=False)
	for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
		for datablock in list(block):
			if datablock.users == 0:
				block.remove(datablock)


def _materials() -> None:
	"""The palette. Flat Principled BSDFs — the PS1 shader in Godot is what
	actually draws these, and all it reads off the import is the base colour."""
	for name, (color, roughness, metallic) in MATERIALS.items():
		material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
		material.use_nodes = True
		# Found by type and not by name: Blender localises the node's label, so
		# `nodes.get("Principled BSDF")` comes back empty on a non-English
		# install and on the newer versions that renamed it.
		bsdf = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
		bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
		bsdf.inputs["Roughness"].default_value = roughness
		bsdf.inputs["Metallic"].default_value = metallic
		material.diffuse_color = (color[0], color[1], color[2], 1.0)


def _export() -> str:
	# Beside *this file*, not beside whatever `.blend` happens to be open — the
	# script is usually run through the MCP server against somebody else's
	# scratch scene, and `bpy.data.filepath` would drop the truck in it.
	path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "box_van.glb")
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.export_scene.gltf(
		filepath=path, export_format="GLB", use_selection=True,
		export_apply=True, export_yup=True)
	return path


if __name__ == "__main__":
	build()
