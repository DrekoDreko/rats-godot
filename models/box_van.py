"""Builds `models/box_van.glb`: the walk-in pest-control truck the crew works out of.

Run it inside Blender (or through the Blender MCP server) and it writes the
`.glb` beside itself. It is checked in so that the truck can be rebuilt rather
than only edited: the shape is the numbers at the top of this file, and moving a
wall is changing one of them and running it again.

Why a box body and not a van: the panel van this replaced (`models/van.glb`,
deleted once this one took over — recoverable from git history) had a cargo bay
2.38 m across with 2.23 m of headroom. Four players, a colour panel, a
clipboard, a shelf of traps, a map table and a ready board do not fit in it —
two people passing each other in there have to breathe in. This is a box body on
the same cab: 3.2 m across the inside, 7 m of it, and 2.4 m of standing room,
which is a corridor down the middle with a station on either side and nobody
stuck behind anybody.

The style is that older van's, deliberately, down to the material names and
colours: flat-shaded boxes, one flat colour per part, no bevels, no smoothing.
Everything is built from `_box` and `_plane`, and the PS1 shader in Godot is
what actually dresses it (`scripts/ps1.gdshader`). The one exception is the
inside, which is lined with tiling textures — see `TEXTURED_MATERIALS` for why
the room gets them and the outside of the truck does not.

Axes are Blender's — **Z is up**, +Y is forward towards the cab, and the origin
sits on the ground at the middle of the cargo floor. Godot's importer turns that
into its own Y-up, which is why the numbers here read one way and the `.tscn`
another.
"""

import bpy
import bmesh
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

## The palette, carried over from the panel van this replaced so that anything
## else in the fleet still matches: `(base colour, roughness, metallic)`.
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

# --- The interior textures --------------------------------------------------
#
# Everything above is painted with one flat colour per part, which is the style
# and stays the style *outside*. Inside is the one place it does not hold up:
# the crew stands in this room for the whole lobby, a metre from the walls, and
# a 3.2 by 7 metre surface of a single unbroken grey reads as a missing texture
# rather than as a van. So the inside gets panelling — and only the inside.
#
# The textures are drawn here in code rather than loaded from a `.png`, for the
# same reason the van itself is a script: a checked-in file is a thing you can
# only edit, and a generator is a thing you can change one number in and rerun.
# Blender packs the generated image straight into the `.glb`, so nothing has to
# ship beside the model.
#
# They are PS1-sized on purpose — 64 pixels across a two-metre panel is coarse
# enough that `filter_nearest` in `scripts/ps1.gdshader` has visible pixels to
# show, which is the look. Anything finer just blurs back into the flat colour
# it replaced.

## How many pixels a texture is across. A power of two, and small: this is the
## console the look is borrowed from, not a modern one.
TEXTURE_SIZE = 64

## How many metres of surface one tile of the texture covers. It is what sets
## the apparent pixel size in the game, and it is the number to change if the
## panelling reads too coarse or too fine — not `TEXTURE_SIZE`, which changes
## how much detail is drawn rather than how large it lands.
TEXTURE_SCALE = 2.0

## How long a piece of lining is, in metres, before it is cut again.
##
## Half a metre, which is margin rather than a requirement now.
##
## It used to be the thing holding the room together: `scripts/ps1.gdshader` ran
## the PS1's affine texture mapping and its vertex snap, both of which are only
## tolerable on small faces, and an uncut seven metre plate tore open under them
## — see `_lined_plane`. The shader now runs perspective-correct and unsnapped by
## default (`affine_strength` and `jitter` at zero, the N64's look rather than the
## PS1's), and a single quad would hold still just as well. The cut stays because
## it costs a few hundred vertices and it is what makes turning that look back on
## a one-number change instead of a re-export.
SUBDIVISION = 0.5


def _noise(x: int, y: int, seed: int) -> float:
	"""A repeatable value in 0..1 for one pixel.

	Hashed rather than randomised so that two runs of this script produce the
	same van: a texture reseeded every rebuild would show up as a diff in the
	`.glb` with no change behind it.
	"""
	h = (x * 374761393 + y * 668265263 + seed * 1442695040) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def _image(name: str, painter) -> "bpy.types.Image":
	"""One generated texture, drawn by `painter(x, y) -> (r, g, b)`.

	Reused rather than redrawn if it already exists, so that a rebuild in a
	session that has already run once does not leave `Wall.001` behind it.

	The pixel buffer is filled as one flat list and assigned in a single write:
	`image.pixels[i] = v` on a 64x64 image is four thousand round trips through
	the RNA property, which takes long enough to look like a hang.
	"""
	existing = bpy.data.images.get(name)
	if existing is not None:
		bpy.data.images.remove(existing)

	image = bpy.data.images.new(name, width=TEXTURE_SIZE, height=TEXTURE_SIZE, alpha=False)
	buffer = [0.0] * (TEXTURE_SIZE * TEXTURE_SIZE * 4)
	for y in range(TEXTURE_SIZE):
		for x in range(TEXTURE_SIZE):
			red, green, blue = painter(x, y)
			offset = (y * TEXTURE_SIZE + x) * 4
			buffer[offset] = red
			buffer[offset + 1] = green
			buffer[offset + 2] = blue
			buffer[offset + 3] = 1.0
	image.pixels = buffer
	# Without this the image is a `GENERATED` block with nowhere to be saved to,
	# and the exporter has nothing to write into the `.glb`.
	image.pack()
	return image


def _shade(color, amount: float):
	"""`color` lightened (positive) or darkened (negative) by `amount`, clamped.

	Every painter below works this way — one base colour off `MATERIALS` and a
	handful of shades of it — so that the panelling stays recognisably the same
	part it replaced rather than becoming a new colour scheme.
	"""
	return tuple(min(1.0, max(0.0, channel + amount)) for channel in color)


def _paint_wall(x: int, y: int):
	"""Corrugated sheet: vertical ribs, seams between panels, and grime.

	The ribs run vertically because that is the way a box body's lining panels
	are pressed, and because a vertical line is the one the player's eye reads
	as height when standing in a long room.

	There is deliberately no rail across it. A band drawn into this texture is a
	band that *tiles*: the image repeats every `TEXTURE_SCALE` metres up the
	wall as well as along it, so one rail at waist height is also a rail at the
	knee and another at the shoulder. Anything that happens once in the room has
	to be geometry — which is what the bench and the shelving already are.
	"""
	base = MATERIALS["VAN_Box"][0]
	# The rib: a shallow trough every eight pixels, lit on one edge and shaded
	# on the other so it reads as pressed metal rather than as a stripe.
	phase = x % 8
	if phase == 0:
		color = _shade(base, -0.14)
	elif phase == 1:
		color = _shade(base, 0.07)
	elif phase == 7:
		color = _shade(base, -0.07)
	else:
		color = base

	# The seam where one lining panel butts against the next. On the tile edge
	# so that it lands once per `TEXTURE_SCALE` metres and reads as panel width.
	if x % TEXTURE_SIZE == 0:
		color = _shade(base, -0.18)

	# Grime, plus the scuffing along the bottom where boots and crates hit.
	grime = _noise(x, y, 11)
	kick = max(0.0, (10 - y) / 10.0) if y < 10 else 0.0
	return _shade(color, -0.06 * grime - 0.12 * kick * (0.4 + 0.6 * grime))


def _paint_floor(x: int, y: int):
	"""Treadplate: a raised stud every few pixels, scuffed along the walkway.

	The studs are what say *floor* from above, which is the angle it is nearly
	always seen from — a flat dark plate at the player's feet reads as a hole.
	"""
	base = MATERIALS["VAN_Floor"][0]
	color = base

	# Studs on a staggered grid, the way treadplate is actually stamped. Each is
	# a solid 3x3 block with its top and left edges lit and its bottom and right
	# shaded, which is what makes it sit *above* the plate. Shading only the two
	# outer edges and leaving the corner between them alone is what turned the
	# first attempt into a little arrow instead of a stud, so the body of the
	# stud is filled first and the highlight laid over it.
	row = y // 8
	stud_x = (x + (4 if row % 2 else 0)) % 8
	stud_y = y % 8
	if 2 <= stud_x <= 4 and 2 <= stud_y <= 4:
		color = _shade(base, 0.06)
		if stud_x == 2 or stud_y == 4:
			color = _shade(base, 0.13)
		if stud_x == 4 or stud_y == 2:
			color = _shade(base, -0.04)

	# Wear polished into the metal, plus the general grain of a dirty floor.
	return _shade(color, 0.05 * _noise(x, y, 23) - 0.02)


def _paint_ceiling(x: int, y: int):
	"""The roof lining: plain sheet on cross members, and nothing else.

	It is the surface the player looks at least and the one a busy texture would
	cost the most on — a patterned ceiling in a room this size reads as pressing
	down on you.

	The members are spaced on a divisor of `TEXTURE_SIZE` so that the spacing
	survives the tile edge. On anything else the last gap before the seam comes
	out a different width from the rest, and a ceiling of even ribs with one odd
	one every two metres is more distracting than no ribs at all.
	"""
	base = _shade(MATERIALS["VAN_Box"][0], -0.06)
	member = y % 16
	if member == 0:
		return _shade(base, -0.11)
	if member == 1:
		return _shade(base, -0.04)
	return _shade(base, -0.05 * _noise(x, y, 37))


## The lined surfaces: `name -> (painter, roughness)`.
##
## These are separate materials rather than textures hung on the ones above,
## and that is the whole trick of keeping this to the inside. `VAN_Box` is the
## body: the same material draws the outside of the truck and — because the
## walls are slabs and `cull_disabled` in `scripts/ps1.gdshader` draws their far
## side — the inside face of them too. Texturing `VAN_Box` would panel the
## outside of the truck as well, which is not what was asked for and is not what
## a box body looks like. So the room is lined instead: thin plates laid just
## inside the walls, floor and roof, wearing these.
TEXTURED_MATERIALS = {
	"VAN_Lining_Wall": (_paint_wall, 0.8),
	"VAN_Lining_Floor": (_paint_floor, 0.9),
	"VAN_Lining_Ceiling": (_paint_ceiling, 0.85),
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
	_lining()

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


def _lining() -> None:
	"""The panelling: a lined plate laid over the inside face of every surface of
	the room — the two side walls, the roof, the bulkhead and the rear jambs.

	Plates rather than textures on the walls themselves, for the reason set out
	at `TEXTURED_MATERIALS`: the wall slabs are shared with the outside of the
	truck, and the outside stays flat-painted.

	Each plate is a single quad facing into the room, floated a couple of
	millimetres proud of the wall behind it — far enough that the depth buffer
	never has to choose between the two at any range the player sees them from,
	near enough that it reads as the surface and not as a board hung on it. The
	floor is not here because it already had a plate of its own (`Int_Floor`);
	it just changed material.
	"""
	mid_y = (BOX_FRONT + BOX_BACK) * 0.5
	inner_roof = FLOOR_HEIGHT + BOX_HEIGHT
	## How far a plate stands off the wall it covers.
	##
	## Two centimetres, which is more than a lining panel would really stand
	## proud of a wall and is set by the depth buffer rather than by the join.
	## The plate and the wall behind it are parallel and both drawn — the body is
	## a solid slab and `cull_disabled` in `scripts/ps1.gdshader` draws its inside
	## face too — so a few millimetres of gap is inside the depth buffer's
	## precision at the far end of a seven metre van, and the flat white of the
	## body punches through the panelling in torn triangles. It is worse under the
	## PS1 shader than it would be otherwise, because the vertex snap moves the
	## two surfaces by different amounts across the screen.
	skin = 0.02

	# The side walls. Their quads are rotated to stand upright and turned to
	# face the middle of the van, which is what puts the texture the right way
	# up and its front face towards the player.
	for side, sign in (("L", -1.0), ("R", 1.0)):
		_lined_plane("Int_Lining_Wall_%s" % side,
			(sign * (BOX_HALF_WIDTH - skin), mid_y, FLOOR_HEIGHT + BOX_HEIGHT * 0.5),
			(BOX_LENGTH, BOX_HEIGHT), "VAN_Lining_Wall",
			rotation=(math.pi * 0.5, 0.0, sign * math.pi * 0.5))

	# The roof lining.
	_lined_plane("Int_Lining_Ceiling", (0.0, mid_y, inner_roof - skin),
		(BOX_HALF_WIDTH * 2, BOX_LENGTH), "VAN_Lining_Ceiling",
		rotation=(math.pi, 0.0, 0.0))

	# The bulkhead, the wall the crew faces down the length of the van. It is
	# the one interior surface that is already its own material rather than the
	# body's (`VAN_Interior`), but it is lined too: it is dead ahead of anybody
	# walking in, which makes it the worst place in the van for a flat colour.
	_lined_plane("Int_Lining_Bulkhead",
		(0.0, BOX_FRONT - WALL - skin, FLOOR_HEIGHT + BOX_HEIGHT * 0.5),
		(BOX_HALF_WIDTH * 2, BOX_HEIGHT), "VAN_Lining_Wall",
		rotation=(math.pi * 0.5, 0.0, math.pi))

	# The jambs either side of the rear doorway, seen edge-on walking in and
	# square-on turning round at the far end.
	jamb = BOX_HALF_WIDTH - DOOR_HALF_WIDTH
	for side, sign in (("L", -1.0), ("R", 1.0)):
		_lined_plane("Int_Lining_Jamb_%s" % side,
			(sign * (DOOR_HALF_WIDTH + jamb * 0.5), BOX_BACK + WALL + skin,
				FLOOR_HEIGHT + BOX_HEIGHT * 0.5),
			(jamb, BOX_HEIGHT), "VAN_Lining_Wall",
			rotation=(math.pi * 0.5, 0.0, 0.0))


def _interior() -> None:
	"""What is bolted inside: the floor plate, the benches down the walls and the
	empty shelving the shop will fill.

	None of it is a station. The stations are Godot scenes dropped into the van
	(`scenes/lobby_van.tscn`) so that they can light up, be interacted with and
	be moved without re-exporting a model — what is here is the furniture they
	are bolted to.
	"""
	mid_y = (BOX_FRONT + BOX_BACK) * 0.5

	# Floated the same two centimetres as the wall plates and for the same reason
	# — see `skin` in `_lining`. Two millimetres is inside the depth buffer's
	# precision here and the floor tears white.
	_lined_plane("Int_Floor", (0.0, mid_y, FLOOR_HEIGHT + 0.02),
		(BOX_HALF_WIDTH * 2, BOX_LENGTH), "VAN_Lining_Floor")

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


def _lined_plane(name: str, location, size, material: str, rotation=(0.0, 0.0, 0.0)):
	"""One tiled, **subdivided** panel of lining.

	Two things separate this from `_plane`, and both are forced by
	`scripts/ps1.gdshader` rather than chosen.

	**The UVs.** The default unwrap Blender gives a primitive maps the image once
	across the face whatever its size, so the same panelling would come out fine
	grained on a jamb and stretched across seven metres of side wall. The quad is
	measured instead: the corners are set to the plate's size in metres over
	`TEXTURE_SCALE`, so one tile covers the same distance on every surface and a
	rib is a rib everywhere in the van.

	**The subdivision**, which is margin for the PS1 look rather than something
	the current one needs — see `SUBDIVISION`. With `affine_strength` or `jitter`
	turned up, the shader does two things per vertex that are only tolerable on
	dense geometry:

	  - It *snaps vertices to a grid* (`round(VERTEX / w * i) / i * w`), which is
	    the console's wobble. Between two vertices the surface is straight, so
	    the snap is spread across whatever distance separates them. On a four
	    vertex plate seven metres long, the entire wall shears.
	  - It *maps textures affinely* (`UV *= VERTEX.z`), which is the console's
	    texture swim — real, wanted, and interpolated per triangle with no
	    perspective correction. Across a seven metre triangle the swim is not a
	    wobble any more; the ribs bend into curves and the ceiling tears open.

	Nothing else in the map shows this because nothing else is both large and
	textured: the walls and floors in `scenes/world.tscn` carry `albedo_color`
	alone, and a flat colour hides any amount of warping. The lining is the first
	textured surface in the van big enough to expose it.

	So the plate is cut into roughly `SUBDIVISION` metre pieces. That is the same
	answer the console's own artists gave — PS1 rooms are visibly gridded for
	exactly this reason — and it keeps both effects local to one small quad,
	which is what makes them read as period wobble instead of breakage.

	None of that is happening at the shader's current settings. It is kept so
	that they can be changed back.
	"""
	obj = _plane(name, location, size, material, rotation=rotation)

	# Cut the plate up before touching the UVs, so the new loops are unwrapped
	# along with the original corners rather than left at (0, 0).
	cuts_u = max(1, int(round(size[0] / SUBDIVISION))) - 1
	cuts_v = max(1, int(round(size[1] / SUBDIVISION))) - 1
	if cuts_u > 0 or cuts_v > 0:
		mesh = bmesh.new()
		mesh.from_mesh(obj.data)
		# `cuts` is per edge, and a quad's two axes need different counts, so the
		# cuts are made one axis at a time: the edges running along the plate's
		# width are cut to divide U, then the ones running along its length.
		for axis, cuts in ((0, cuts_u), (1, cuts_v)):
			if cuts <= 0:
				continue
			# The edges to cut are the ones *perpendicular* to the axis being
			# divided — cutting an edge adds vertices along it, which is what
			# splits the face across the other direction.
			edges = [e for e in mesh.edges if _edge_axis(e) == axis]
			bmesh.ops.subdivide_edges(mesh, edges=edges, cuts=cuts, use_grid_fill=True)
		mesh.to_mesh(obj.data)
		mesh.free()
		obj.data.update()
		for polygon in obj.data.polygons:
			polygon.use_smooth = False

	# Unwrap by position rather than by scaling whatever the primitive had: after
	# subdivision the loops are no longer the four corners, so there is nothing
	# left to scale. Each loop takes the UV its own vertex sits at, measured in
	# tiles from the plate's corner, which tiles seamlessly across every piece.
	uvs = obj.data.uv_layers.active or obj.data.uv_layers.new()
	half_u = size[0] * 0.5
	half_v = size[1] * 0.5
	for polygon in obj.data.polygons:
		for loop_index in polygon.loop_indices:
			vertex = obj.data.vertices[obj.data.loops[loop_index].vertex_index].co
			uvs.data[loop_index].uv = (
				(vertex.x + half_u) / TEXTURE_SCALE,
				(vertex.y + half_v) / TEXTURE_SCALE,
			)
	return obj


def _edge_axis(edge) -> int:
	"""Which of the plate's own axes `edge` runs along: 0 for X, 1 for Y.

	The plate is built flat in XY and rotated afterwards by the object's
	transform, so its vertices are still axis aligned in local space here — which
	is what makes this a comparison rather than a projection.
	"""
	delta = edge.verts[1].co - edge.verts[0].co
	return 0 if abs(delta.x) > abs(delta.y) else 1


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
	"""The palette, then the lined surfaces.

	The flat half is Principled BSDFs carrying nothing but a base colour, which
	is all the PS1 shader in Godot reads off them. The lined half additionally
	hangs a generated image on the base colour, which that same shader picks up
	as its `albedo` — see `scripts/ps1_material_applier.gd`, which takes the
	texture off whatever material the importer left on the surface.
	"""
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

	for name, (painter, roughness) in TEXTURED_MATERIALS.items():
		_textured_material(name, painter, roughness)


def _textured_material(name: str, painter, roughness: float):
	"""One material whose base colour is a generated image rather than a value."""
	material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	material.use_nodes = True
	tree = material.node_tree
	bsdf = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
	bsdf.inputs["Roughness"].default_value = roughness
	bsdf.inputs["Metallic"].default_value = 0.0

	# Rebuilt rather than reused: running the script twice would otherwise stack
	# a second image node on the first and leave the link pointing at whichever
	# one Blender happened to connect last.
	for node in [n for n in tree.nodes if n.type == "TEX_IMAGE"]:
		tree.nodes.remove(node)

	texture = tree.nodes.new("ShaderNodeTexImage")
	texture.image = _image(name, painter)
	# Nearest here as well as in the Godot shader. It is what the `.glb` carries
	# as the sampler's filter, so the model looks the same opened in Blender or
	# in any other viewer as it does in the game.
	texture.interpolation = "Closest"
	texture.location = (-320.0, 200.0)
	tree.links.new(texture.outputs["Color"], bsdf.inputs["Base Color"])

	# The viewport's flat colour, so the part is not white in solid shading.
	middle = painter(TEXTURE_SIZE // 2, TEXTURE_SIZE // 2)
	material.diffuse_color = (middle[0], middle[1], middle[2], 1.0)
	return material


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
