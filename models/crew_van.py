"""Builds `models/crew_van.glb` by **deforming the imported van asset** into one
the crew can stand up and work in.

**NOT IN USE.** No scene references the van this builds; `scenes/world.tscn`,
`scenes/lobby_van.tscn` and `scenes/van_travel.tscn` all still use
`models/box_van.glb`. It is kept because the deformation works and is a starting
point, not because the result was accepted — it was not. Running it writes a
`.glb` that nothing loads.

Why it was set aside: the asset is a **compact panel van**, 5.1 m long with
1.12 m of inside height, and the requirement is four players walking upright,
which needs about 2.4 m. Doubling a compact van's height cannot leave it looking
like that van — the proportion that makes the asset handsome is the one the
requirement forbids, and stretching it to fit produces a long flat box with a
cab stuck on the front. There is no tuning of the numbers below that avoids
that; it is the requirement and the asset disagreeing.

Three ways forward, none of them free:

  - Keep the asset's proportions and accept roughly 1.9 m inside — a player
    passes upright, but the corridor drops to about 1.4 m.
  - Keep 2.4 m and *design* the tall body properly: a domed roof rather than a
    flat one, a continuous chamfered shoulder, the rear rake carried through,
    bigger wheels and proud arches. That is a high-roof van, not this asset.
  - Leave the asset as scenery and keep `box_van.glb` for the van the crew works
    in, which is what it was built for.

`scripts/session/van_doors.gd` is likewise unused for now. It is sound and needs
a van whose model carries `Van_Door_L`/`Van_Door_R` hinges — this script makes
them, `box_van.glb` does not.

Run it inside Blender (or through the Blender MCP server) and it writes the
`.glb` beside itself. It is checked in so that the van can be rebuilt rather
than only edited: the numbers at the top are the shape, and moving a wall is
changing one of them and running it again.

**The source is the art, not a reference.** It reads
`assets/van/assets/obj/model.obj` — the Blockbench minivan by Mark Komlev /
PomidorkaStudios (credit him; see that folder's README) — and every polygon of
the finished van's body, cab, wheels and mirrors comes out of that file, with its
`UVMap` and `texture.png` intact. Nothing here draws a van from scratch.

What it changes, and why it has to:

  1. **Widens and heightens the cargo half.** The asset is a solid block with
     2.0 m across the inside and 1.12 m of headroom — a player cannot stand in
     it, let alone four of them pass each other. The vertices behind the
     bulkhead are pushed out to `HALF_WIDTH` and up to `CARGO_HEIGHT`. The cab
     is deliberately left alone, so the nose, the windscreen rake and the
     mirrors stay exactly as drawn.
  2. **Hollows it.** The asset has no interior at all: a ray through the cargo
     area crosses two surfaces, not four. The cargo shell is solidified inward
     so there is a room in there.
  3. **Cuts the rear doorway out of the back panel** and hangs two leaves in it,
     so `scripts/session/van_doors.gd` can open them for the hunt and shut them
     for the road.
  4. **Bolts in the furniture**: four car seats facing each other, the floor
     plate, shelving and a grab rail. These are new geometry — the asset has
     none — kept to its own flat-shaded style.

Axes are Blender's — **Z is up**, +Y is forward towards the cab, and the origin
sits on the ground at the middle of the cargo floor, the same convention
`box_van.py` uses so the `.tscn` files read alike. The importer turns that into
Godot's Y-up, which is why the numbers here read one way and the `.tscn`
another.
"""

import bpy
import bmesh
import mathutils
import os
import math

# --- Where the art comes from -----------------------------------------------

## The asset, relative to the repository root. The `.obj` and not the `.gltf`:
## they are the same Blockbench export, but the `.obj` shares vertices between
## faces (78 on the body instead of 304), and a shared-vertex mesh is the one
## that deforms cleanly — moving a corner moves every face meeting there instead
## of splitting the surface open.
SOURCE = os.path.join("assets", "van", "assets", "obj", "model.obj")

## The asset's own object names, which this script reads and must not guess at.
BODY = "cube"
EXTRAS = ("cube.001", "cube.002", "mirror_l", "mirror_r",
	"fl_wheel", "fr_wheel", "bl_wheel", "br_wheel")

# --- The asset's own measurements -------------------------------------------
# Read off the file rather than assumed, and asserted at import time so that a
# different asset dropped in this folder fails loudly instead of quietly
# producing a mangled van.

## Where the asset's body sits: half-width, and the Y of its back.
SRC_HALF_WIDTH = 1.0
SRC_BACK = -2.625

## The flat cargo roof plane, which is what the height stretch maps *from*.
SRC_ROOF = 1.85

## The single highest point on the asset — a crease above the windscreen, 47 mm
## above the roof plane. Only the import check uses it. Kept apart from
## `SRC_ROOF` because conflating the two is what made the check fail on the very
## asset it was written for.
SRC_PEAK = 1.897

## Where the cab ends and the cargo area begins on the asset. Behind this line
## (towards -Y) the body is stretched; in front of it the cab is left exactly as
## drawn, so the windscreen rake, the nose and the mirrors survive untouched.
##
## Read off the asset's roof profile rather than guessed: the roof runs flat at
## 1.85 from the back all the way to y=+1.13, and from there forward it steps
## down (1.50, 1.19, 1.04) as the windscreen rakes over the bonnet. The mirrors
## sit at y=1.0..1.22 and the driver's seat at y=1.13..2.03, which agree — the
## cab is the **+Y** end and it begins here.
SRC_BULKHEAD = 1.13

## The Z below which the asset's chassis, skirt and wheel arches live. Left
## unstretched, or the tyres stop meeting the arches.
SRC_SKIRT = 0.3

# --- The shape we want, in metres -------------------------------------------

## Half the inside width and the standing headroom of the cargo bay. These are
## `box_van.py`'s proven numbers: four players, four seats and the stations fit
## in them with a corridor left over.
HALF_WIDTH = 1.6
CARGO_HEIGHT = 2.4

## How thick the walls are drawn when the shell is hollowed.
WALL = 0.08

## How high the cargo floor sits off the ground, and where the bay's ends are.
##
## `CARGO_FRONT` is where the *bulkhead we build* stands, and it is not
## `SRC_BULKHEAD` — that one is a fact about the asset's topology (the last
## vertex row before its unbroken cabin panel, at -1.188) and pinning the stretch
## there is a different job from deciding how long the room is. The bay runs from
## the back of the cab forward-most seat row to the doorway.
FLOOR_HEIGHT = 0.62
CARGO_FRONT = SRC_BULKHEAD
CARGO_BACK = -3.9

## The rear doorway and the two leaves hung in it.
DOOR_HALF_WIDTH = 1.18
DOOR_HEIGHT = 2.05
DOOR_THICKNESS = 0.06
## How far each leaf swings when open. Mirrored in
## `scripts/session/van_doors.gd`, which animates the same angle.
DOOR_OPEN_ANGLE = math.radians(86.0)

## The step out of the doorway. A plate and not a ramp: both doors swing back
## along the flanks and a ramp would foul whichever one passed over it.
STEP_DEPTH = 0.5
STEP_THICKNESS = 0.08
STEP_HEIGHT = FLOOR_HEIGHT * 0.5

## The four seats: two a side, facing each other across the walkway.
SEAT_WIDTH = 0.52
SEAT_DEPTH = 0.5
SEAT_SQUAB_HEIGHT = 0.42
SEAT_BACK_HEIGHT = 0.62
SEAT_THICKNESS = 0.12
SEAT_Y_FRONT = 0.34
SEAT_Y_REAR = -1.72
SEAT_INSET = SEAT_DEPTH * 0.5 + 0.04

## The palette for the parts the asset does not have. Material names match
## `box_van.py` so the PS1 shader treats the fleet alike. The asset's own
## textured material stays on the asset's own geometry.
MATERIALS = {
	## The door leaves, in the asset's own off-white body tone so a shut door
	## reads as part of the same panel run.
	"VAN_Panel": ((0.78, 0.77, 0.74), 0.7, 0.0),
	"VAN_Floor": ((0.13, 0.13, 0.14), 0.9, 0.0),
	"VAN_Seat": ((0.17, 0.16, 0.19), 0.85, 0.0),
	"VAN_Trim": ((0.09, 0.09, 0.10), 0.7, 0.0),
	"VAN_Shelf": ((0.34, 0.31, 0.27), 0.8, 0.0),
	"VAN_Bumper": ((0.30, 0.30, 0.32), 0.6, 0.0),
}

_root = None
_asset_material = None


def build() -> str:
	"""Everything, from an empty scene to a written `.glb`. Returns the path."""
	_clear()
	_materials()

	global _root
	_root = bpy.data.objects.new("Van_Root", None)
	bpy.context.scene.collection.objects.link(_root)

	body = _import_asset()
	_stretch(body)
	_move_rear_axle()
	_hollow(body)
	_doors(body)
	_interior()
	_reparent()

	return _export()

# --- Reading the asset ------------------------------------------------------


def _import_asset():
	"""Import the `.obj` and hand back its body object.

	Everything the asset ships is kept: the body is what gets deformed, and the
	wheels, mirrors and cab seats ride along untouched.
	"""
	path = os.path.join(_project_root(), SOURCE)
	if not os.path.exists(path):
		raise RuntimeError("the van asset is missing: %s" % path)

	bpy.ops.wm.obj_import(filepath=path)
	bpy.context.view_layer.update()

	body = bpy.data.objects.get(BODY)
	if body is None:
		raise RuntimeError("expected an object named %r in %s" % (BODY, SOURCE))

	# The asset's textured material, which every deformed face keeps. Held so the
	# door leaves can be given the same one and read as panel off the same van.
	global _asset_material
	if body.data.materials:
		_asset_material = body.data.materials[0]

	# Fail loudly if this is not the van the numbers above were read off. A
	# different asset would deform into nonsense, and silence would be worse.
	points = [body.matrix_world @ v.co for v in body.data.vertices]
	for got, want, name in (
		(max(p.x for p in points), SRC_HALF_WIDTH, "half-width"),
		(min(p.y for p in points), SRC_BACK, "back"),
		(max(p.z for p in points), SRC_PEAK, "peak"),
	):
		if abs(got - want) > 0.02:
			raise RuntimeError(
				"the asset's %s is %.3f, expected %.3f — is this the same model?"
				% (name, got, want))

	for name in EXTRAS:
		extra = bpy.data.objects.get(name)
		if extra is not None:
			_flat(extra)

	return body


def _move_rear_axle() -> None:
	"""Slide the asset's rear wheels back under the lengthened body.

	The body's back end moves from `SRC_BACK` to `CARGO_BACK`, and a wheel left
	where the asset drew it ends up under the middle of the van with a long tail
	hanging off behind it. The axle keeps its distance from the *back*, which is
	how a van this shape is actually laid out.
	"""
	shift = CARGO_BACK - SRC_BACK
	# `location` is in the object's parent frame and these wheels are unparented,
	# but they carry the asset's own -90 degree X rotation, so a world-space
	# nudge has to go through `matrix_world` rather than into `location.y`.
	for name in ("bl_wheel", "br_wheel"):
		wheel = bpy.data.objects.get(name)
		if wheel is not None:
			_nudge(wheel, (0.0, shift, 0.0))

	# And the wheels have to clear the widened flanks, or a tyre surfaces through
	# the cargo floor — the same trap `box_van.py` documents.
	out = HALF_WIDTH + 0.02 - SRC_HALF_WIDTH
	for name, sign in (("bl_wheel", -1.0), ("br_wheel", 1.0),
			("fl_wheel", -1.0), ("fr_wheel", 1.0)):
		wheel = bpy.data.objects.get(name)
		if wheel is not None:
			_nudge(wheel, (sign * out, 0.0, 0.0))


def _nudge(obj, offset) -> None:
	"""Move an object by a world-space offset, whatever rotation it carries."""
	matrix = obj.matrix_world.copy()
	matrix.translation += mathutils.Vector(offset)
	obj.matrix_world = matrix


def _project_root() -> str:
	"""The repository root, from this file's own place in `models/`."""
	return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# --- Deforming it -----------------------------------------------------------


def _stretch(body) -> None:
	"""Push the cargo half of the body out to the room we need, leaving the cab.

	Every vertex behind `SRC_BULKHEAD` is *mapped* to a new position rather than
	the object being scaled — scaling would drag the cab and the wheel arches
	with it. Positions inside the cargo area keep their proportions, so the
	waistline crease and the rear light cut-outs stay where they look right.
	"""
	me = body.data

	# **Work in world space.** The asset's objects carry a -90 degree rotation
	# about X (Blockbench exports Y-up, Blender is Z-up), so in a vertex's own
	# local coordinates Y is the height and Z is the length — the opposite of
	# every measurement in this file, which was read off the world positions.
	# Deforming `v.co` directly against these numbers stretches the van along the
	# wrong axes and looks almost right, which is worse than looking wrong.
	to_world = body.matrix_world
	to_local = to_world.inverted()

	# Both spans are measured from the bulkhead, which is the line the stretch is
	# pinned at: only a vertex's distance *behind* it is scaled.
	span_src = SRC_BULKHEAD - SRC_BACK
	span_new = SRC_BULKHEAD - CARGO_BACK

	for v in me.vertices:
		p = to_world @ v.co
		if p.y > SRC_BULKHEAD:
			continue  # the cab: untouched, on purpose

		# Width: the flanks go from +/-1.0 out to +/-HALF_WIDTH, everything
		# between moving in proportion so the panel lines stay spaced.
		p.x = p.x / SRC_HALF_WIDTH * HALF_WIDTH

		# Length: the back goes from SRC_BACK to CARGO_BACK with the bulkhead
		# pinned, so a vertex's distance behind the bulkhead is what scales.
		p.y = SRC_BULKHEAD - (SRC_BULKHEAD - p.y) / span_src * span_new

		# Height: the roof lifts to the top of the bay. Below SRC_SKIRT is the
		# chassis and the arches, left alone so the wheels still meet them.
		#
		# The ratio is deliberately *not* clamped at 1. The asset's highest
		# vertices (`SRC_PEAK`) sit above the roof plane as a crease, and a clamp
		# would iron them flat into the roof; letting the ratio run past 1 keeps
		# the crease standing as proud of the new roof as it was of the old.
		if p.z > SRC_SKIRT:
			ratio = (p.z - SRC_SKIRT) / (SRC_ROOF - SRC_SKIRT)
			p.z = FLOOR_HEIGHT + ratio * CARGO_HEIGHT

		v.co = to_local @ p

	me.update()


def _hollow(body) -> None:
	"""Give the stretched box an inside, and cut the doorway out of its back.

	The asset is a closed solid, so the doorway faces are deleted and the whole
	body is then solidified **inward**: the outer surface stays exactly where
	`_stretch` put it and a second surface appears `WALL` inside it. A Solidify
	modifier rather than a hand-built inset, because it walks the topology itself
	and cannot leave a hole at a corner the way an inset does.
	"""
	me = body.data
	bm = bmesh.new()
	bm.from_mesh(me)
	bm.faces.ensure_lookup_table()

	# The doorway: the rear-facing faces inside the opening, deleted so the
	# leaves have a hole to hang in.
	#
	# Face centres and normals come out of bmesh in the object's **local**
	# space, and the asset carries a -90 degree X rotation, so a rear-facing
	# face has no particular sign in local Y. Both are converted to world
	# first — testing `face.normal.y < -0.7` on raw local data matches nothing
	# and the back of the van silently stays shut.
	to_world = body.matrix_world
	normal_to_world = to_world.to_3x3()

	doorway = []
	for face in bm.faces:
		centre = to_world @ face.calc_center_median()
		normal = (normal_to_world @ face.normal).normalized()
		if (normal.y < -0.7
				and abs(centre.x) < DOOR_HALF_WIDTH
				and FLOOR_HEIGHT - 0.05 < centre.z < FLOOR_HEIGHT + DOOR_HEIGHT):
			doorway.append(face)
	if doorway:
		bmesh.ops.delete(bm, geom=doorway, context="FACES")

	bm.to_mesh(me)
	bm.free()
	me.update()

	# `use_rim` closes the cut edges around the doorway, which is what turns the
	# hole into a jamb with thickness rather than a paper edge seen from inside.
	shell = body.modifiers.new("Shell", "SOLIDIFY")
	shell.thickness = WALL
	shell.offset = 1.0  # inward, so the outside stays where it was drawn
	shell.use_rim = True
	_apply_modifiers(body)


def _rear_panel_y(body) -> float:
	"""The Y of the rear panel at door mid-height, measured off the mesh.

	Not `CARGO_BACK` and not a constant: the asset's back panel is **raked** —
	it leans inboard as it rises, from about -3.82 at the sill to -3.57 at the
	roof. A door hung at one guessed Y therefore stands clear of the body over
	most of its height. Sampling the panel at the door's own mid-height puts the
	hinge line where the leaf actually meets it.
	"""
	to_world = body.matrix_world
	normal_to_world = to_world.to_3x3()
	target_z = FLOOR_HEIGHT + DOOR_HEIGHT * 0.5

	best = None
	for poly in body.data.polygons:
		centre = to_world @ poly.center
		normal = (normal_to_world @ poly.normal).normalized()
		if normal.y > -0.5 or abs(centre.x) > HALF_WIDTH:
			continue
		if best is None or abs(centre.z - target_z) < abs(best[0] - target_z):
			best = (centre.z, centre.y)

	if best is None:
		# No rear-facing panel found at all — fall back to the nominal back so a
		# van still gets doors rather than none.
		return CARGO_BACK
	return best[1]


def _doors(body) -> None:
	"""The two rear leaves, hung on hinges Godot can turn.

	Each leaf is parented to an **empty on the hinge line**, and it is the empty
	that `scripts/session/van_doors.gd` rotates. A leaf whose origin is its own
	centre would pivot about its middle and sweep half the door through the side
	of the van.
	"""
	sill_y = _rear_panel_y(body)
	leaf = DOOR_HALF_WIDTH

	for side, sign in (("L", -1.0), ("R", 1.0)):
		hinge = bpy.data.objects.new("Van_Door_%s" % side, None)
		bpy.context.scene.collection.objects.link(hinge)
		# On the **jamb**, at the edge of the opening — not out at the side wall.
		# A leaf is `DOOR_HALF_WIDTH` wide because that is half the doorway, so
		# hung from the doorway's edge the two leaves meet in the middle. Hung
		# from the wall, each stops a jamb's width short and the shut doors leave
		# a gap down the centre — which no bounding box catches, only a render.
		hinge.location = (sign * DOOR_HALF_WIDTH, sill_y,
			FLOOR_HEIGHT + DOOR_HEIGHT * 0.5)
		hinge.rotation_euler = (0.0, 0.0, sign * DOOR_OPEN_ANGLE)
		hinge.parent = _root
		hinge.matrix_parent_inverse = _root.matrix_world.inverted()

		# The leaf and its handle, in the hinge's own frame: X runs inboard along
		# the leaf from the hinge.
		# Flat-coloured, not the asset's textured material: a fresh cube has no
		# UVs laid out for that atlas, so the texture comes out as streaks
		# stretched off whatever island the default cube unwrap happens to land
		# on. A flat panel colour is what the leaves should read as anyway.
		_door_part("Van_Door_%s_Leaf" % side, hinge,
			(-sign * leaf * 0.5, 0.0, 0.0),
			(leaf, DOOR_THICKNESS, DOOR_HEIGHT), "VAN_Panel")
		_door_part("Van_Door_%s_Handle" % side, hinge,
			(-sign * (leaf - 0.12), sign * (DOOR_THICKNESS * 0.5 + 0.02),
				-DOOR_HEIGHT * 0.06),
			(0.16, 0.05, 0.05), "VAN_Trim")


def _door_part(name: str, hinge, offset, size, material):
	"""One piece of a door, positioned in its **hinge's** frame.

	Everything on a door has to be a child of the hinge, or it stays behind when
	the door swings — the handle would hang in mid-air at the old angle while the
	leaf moved away from it.

	`material` of `None` means the asset's own textured material, which is what
	the leaves get: they are meant to look like panel cut from the same van.
	"""
	obj = _box(name, (0.0, 0.0, 0.0), size, material)
	obj.parent = hinge
	# Identity, **not** `hinge.matrix_world.inverted()`. The offset is already in
	# the hinge's frame, so an inverse would cancel the hinge's rotation right
	# back out: the part would sit at the origin with the door open and fly
	# across the scene with it shut.
	obj.matrix_parent_inverse = mathutils.Matrix.Identity(4)
	obj.location = offset
	return obj

# --- What is bolted inside --------------------------------------------------


def _interior() -> None:
	"""The floor plate, the four seats, the shelving, the grab rail and the step.

	None of it is a station. The stations are Godot scenes dropped into the van
	(`scenes/world.tscn`, `scenes/lobby_van.tscn`, `scenes/van_travel.tscn`) so
	they can light up and be moved without re-exporting a model — this is the
	furniture they bolt to.
	"""
	mid_y = (CARGO_FRONT + CARGO_BACK) * 0.5
	length = CARGO_FRONT - CARGO_BACK

	_plane("Int_Floor", (0.0, mid_y, FLOOR_HEIGHT + 0.002),
		(HALF_WIDTH * 2 - WALL * 2, length - WALL * 2), "VAN_Floor")

	for side, sign in (("L", -1.0), ("R", 1.0)):
		for label, y in (("F", SEAT_Y_FRONT), ("R", SEAT_Y_REAR)):
			_seat("Int_Seat_%s%s" % (label, side), sign, y)

	# Shelving on the right wall, in the gap between that side's two seats, where
	# the traps ride. It starts above the seat backs so it clears them.
	shelf_y = (SEAT_Y_FRONT + SEAT_Y_REAR) * 0.5
	shelf_length = abs(SEAT_Y_FRONT - SEAT_Y_REAR) - SEAT_WIDTH - 0.2
	for index in range(2):
		z = FLOOR_HEIGHT + 1.32 + index * 0.5
		_box("Int_Shelf_R%d" % (index + 1),
			(HALF_WIDTH - WALL - 0.2, shelf_y, z),
			(0.4, shelf_length, 0.05), "VAN_Shelf")
		# A lip along the front edge, so a box on the shelf reads as held there
		# rather than balanced on a plank.
		_box("Int_Shelf_R%d_Lip" % (index + 1),
			(HALF_WIDTH - WALL - 0.38, shelf_y, z + 0.05),
			(0.04, shelf_length, 0.08), "VAN_Shelf")

	# A grab rail down the middle of the roof: four players moving in a corridor
	# this size all reach for the same thing.
	_box("Int_Grab_Rail", (0.0, mid_y, FLOOR_HEIGHT + CARGO_HEIGHT - 0.14),
		(0.05, length - 0.6, 0.05), "VAN_Trim")

	# The step out of the doorway, and its riser.
	_box("Van_Step", (0.0, CARGO_BACK - STEP_DEPTH * 0.5, STEP_HEIGHT),
		(DOOR_HALF_WIDTH * 2 - 0.1, STEP_DEPTH, STEP_THICKNESS), "VAN_Bumper")
	_box("Van_Step_Riser", (0.0, CARGO_BACK - STEP_DEPTH, STEP_HEIGHT * 0.5),
		(DOOR_HALF_WIDTH * 2 - 0.1, 0.06, STEP_HEIGHT), "VAN_Trim")


def _seat(name: str, sign: float, y: float) -> None:
	"""One car seat against the wall on `sign`'s side, facing across the van.

	A squab, a back raked off the wall, a headrest and armrests — the pieces that
	read as a seat rather than as the plank bench the box van had. The back is
	against the wall and the squab reaches inboard, so a player sitting in it
	looks at the seat opposite.
	"""
	wall_x = sign * (HALF_WIDTH - WALL)
	squab_z = FLOOR_HEIGHT + SEAT_SQUAB_HEIGHT - SEAT_THICKNESS * 0.5
	rake = math.radians(8.0)

	_box("%s_Squab" % name, (wall_x - sign * SEAT_INSET, y, squab_z),
		(SEAT_DEPTH, SEAT_WIDTH, SEAT_THICKNESS), "VAN_Seat")

	_box("%s_Frame" % name,
		(wall_x - sign * SEAT_INSET, y,
			FLOOR_HEIGHT + (SEAT_SQUAB_HEIGHT - SEAT_THICKNESS) * 0.5),
		(SEAT_DEPTH - 0.16, SEAT_WIDTH - 0.14, SEAT_SQUAB_HEIGHT - SEAT_THICKNESS),
		"VAN_Trim")

	# The back leans its top inboard, which about the Y axis is a rotation whose
	# sign follows the side — hence `sign * rake` rather than a bare angle.
	_box("%s_Back" % name,
		(wall_x - sign * (SEAT_THICKNESS * 0.5 + math.sin(rake) * SEAT_BACK_HEIGHT * 0.5),
			y, squab_z + SEAT_BACK_HEIGHT * 0.5),
		(SEAT_THICKNESS, SEAT_WIDTH, SEAT_BACK_HEIGHT), "VAN_Seat",
		rotation=(0.0, sign * rake, 0.0))

	_box("%s_Headrest" % name,
		(wall_x - sign * (SEAT_THICKNESS * 0.5 + math.sin(rake) * (SEAT_BACK_HEIGHT + 0.2)),
			y, squab_z + SEAT_BACK_HEIGHT + 0.14),
		(SEAT_THICKNESS, SEAT_WIDTH - 0.16, 0.22), "VAN_Seat",
		rotation=(0.0, sign * rake, 0.0))

	# Armrests along each side of the squab. They run inboard, which is what
	# settles the seat as facing *across* the van rather than along it.
	for edge in (-1.0, 1.0):
		_box("%s_Arm%s" % (name, "F" if edge > 0 else "R"),
			(wall_x - sign * (SEAT_INSET - 0.04),
				y + edge * (SEAT_WIDTH * 0.5 - 0.03), squab_z + 0.16),
			(SEAT_DEPTH - 0.1, 0.06, 0.08), "VAN_Trim")

# --- Primitives -------------------------------------------------------------


def _box(name: str, location, size, material, rotation=(0.0, 0.0, 0.0)):
	"""One flat-shaded cuboid. `size` is the full extent."""
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=location, rotation=rotation)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = size
	bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
	return _finish(obj, material)


def _plane(name: str, location, size, material, rotation=(0.0, 0.0, 0.0)):
	"""One flat quad, for the floor plate."""
	bpy.ops.mesh.primitive_plane_add(size=1.0, location=location, rotation=rotation)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = (size[0], size[1], 1.0)
	bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
	return _finish(obj, material)


def _finish(obj, material):
	"""Flat shading and one material. `None` means the asset's own textured one."""
	chosen = _asset_material if material is None else bpy.data.materials.get(material)
	if chosen is not None:
		obj.data.materials.append(chosen)
	return _flat(obj)


def _flat(obj):
	"""Flat shading, which is the asset's style and this project's."""
	for polygon in obj.data.polygons:
		polygon.use_smooth = False
	return obj


def _apply_modifiers(obj) -> None:
	"""Bake an object's modifier stack into its mesh."""
	bpy.ops.object.select_all(action="DESELECT")
	obj.select_set(True)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.object.convert(target="MESH")


def _reparent() -> None:
	"""Hang every loose part off one root, so the export is a single van.

	Done last, and with `matrix_parent_inverse`, because a part parented before
	it was placed would take the root's transform twice. Parts that already have
	a parent are skipped — the door leaves belong to their hinges, and
	re-parenting them would take them off the thing that swings them.
	"""
	for obj in list(bpy.context.scene.objects):
		if obj is _root or obj.parent is not None:
			continue
		obj.parent = _root
		obj.matrix_parent_inverse = _root.matrix_world.inverted()

# --- Scene plumbing ---------------------------------------------------------


def _clear() -> None:
	"""An empty scene. The van is built from nothing every time, so a rebuild is
	a rebuild and not a second van on top of the first."""
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.object.delete(use_global=False)
	for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
		for datablock in list(block):
			if datablock.users == 0:
				block.remove(datablock)


def _materials() -> None:
	"""The palette for the added furniture. Flat Principled BSDFs — the PS1
	shader in Godot is what actually draws these, and all it reads off the import
	is the base colour. The asset's own textured material is left alone."""
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
	# scratch scene, and `bpy.data.filepath` would drop the van in it.
	path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "crew_van.glb")
	bpy.ops.object.select_all(action="SELECT")
	bpy.ops.export_scene.gltf(
		filepath=path, export_format="GLB", use_selection=True,
		export_apply=True, export_yup=True)
	return path


if __name__ == "__main__":
	build()
