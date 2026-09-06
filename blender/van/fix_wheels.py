"""Give the van wheels by extending its body down to the painted tyres.

Run headless:
    blender -b van.blend --python fix_wheels.py -- --save

The body is a flat-bottomed box, so the wheels painted on its flanks are cut off
at the sills. This drops the underside down to follow each tyre's outline, so the
painted wheel lands on real geometry instead of being sliced in half.

Every wheel is part of the body mesh - a solid block spanning the full width of
the van, capped underneath - not a shell stuck to the side, so there is no hollow
to see into and nothing coplanar to z-fight. The blocks are exactly as wide as
the body, so the flanks read as one continuous surface with no step at the sill.

The tyre outlines are not written down here: they are traced off van_ref_256.png
at import time, column by column, so the geometry always follows the artwork it
is textured with.
"""

import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_van

# --------------------------------------------------------------------------- #
# The blueprint's right-hand side view, in texels of the 256x171 reference.
# --------------------------------------------------------------------------- #

REFERENCE_PATH = os.path.join(build_van.HERE, "van_ref_256.png")

# The side view's ink, measured by scanning the reference: the van spans these
# texels, its flat sills sit on SILL_ROW, and only the tyres reach below.
VIEW_X0, VIEW_Y0 = 86, 6
VIEW_X1, VIEW_Y1 = 220, 58
SILL_ROW = 52

INK_THRESHOLD = 0.5

# Where to look for each tyre, as a span of reference columns. The scan finds
# their true outlines inside these; they only need to be wide enough to contain
# a wheel and narrow enough to hold just one.
TYRE_WINDOWS = {"F": (90, 125), "B": (170, 200)}

# The van is 51 texels wide at the sills, over a 5 m length.
PX_PER_M = build_van.SIDE_PX_W / build_van.LENGTH

# The wheel blocks span the body exactly, so the flank is one flat surface from
# roof to tread. Any inset here reads as a groove along the sill.
WHEEL_HALF = build_van.BODY_HALF

# The underside is never seen from outside; it borrows a dark texel from the
# shadow under the front axle.
UNDERSIDE_TEXEL = (115.0, 47.0)


def read_tyre_profiles():
    """Trace each painted tyre's lower outline off the reference image.

    Returns {tag: [(column, row), ...]} in view-relative texels, walking front
    to back, with the first and last entry pulled up onto the sill so the block
    meets the body flush.
    """
    image = bpy.data.images.load(REFERENCE_PATH)
    width, height = image.size
    pixels = list(image.pixels)

    def is_ink(x, y):
        offset = ((height - 1 - y) * width + x) * 4
        luma = (pixels[offset] + pixels[offset + 1] + pixels[offset + 2]) / 3.0
        return luma < INK_THRESHOLD

    def lowest_row(x):
        rows = [y for y in range(VIEW_Y0, VIEW_Y1 + 1) if is_ink(x, y)]
        return max(rows) if rows else SILL_ROW

    profiles = {}
    for tag, (x_start, x_end) in TYRE_WINDOWS.items():
        below = [x for x in range(x_start, x_end + 1) if lowest_row(x) > SILL_ROW]
        if not below:
            raise RuntimeError(f"No tyre found in the {tag} window of the reference")

        # Take only the run of columns containing the deepest point. Rear lights
        # and bumper trim also dip below the sill line, and letting the block
        # stretch out to them hangs a slab off the back of the wheel.
        deepest = max(below, key=lowest_row)
        first, last = deepest, deepest
        while first - 1 in below:
            first -= 1
        while last + 1 in below:
            last += 1

        points = [(x - VIEW_X0, lowest_row(x) - VIEW_Y0) for x in range(first, last + 1)]

        sill = SILL_ROW - VIEW_Y0
        profiles[tag] = (
            [(points[0][0] - 1, sill)] + points + [(points[-1][0] + 1, sill)]
        )

    bpy.data.images.remove(image)
    return profiles


def x_of(column):
    """Side-view column -> metres from the front bumper."""
    return column / PX_PER_M


def z_of(row):
    """Side-view row -> metres above the ground."""
    return (build_van.SIDE_PX_H - row) / PX_PER_M


def texel_to_uv(x, y):
    return x / build_van.TEX_W, 1.0 - y / build_van.TEX_H


# --------------------------------------------------------------------------- #
# Build
# --------------------------------------------------------------------------- #


def remove_wheel_objects():
    for obj in [o for o in bpy.data.objects if o.name.startswith("Wheel_")]:
        bpy.data.objects.remove(obj, do_unlink=True)


def add_wheels(obj, profiles):
    """Extend the body downward over each tyre, and UV the new faces."""
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)

    uv_layer = bm.loops.layers.uv.active or bm.loops.layers.uv.new("UVMap")

    # Reuse the body's own side projection verbatim. Anything else - even a
    # projection onto the same view rectangle - lands the tyre a texel off and
    # leaves a visible step where the wheel meets the sill.
    def side_uv(x, z, right):
        view = "side_r" if right else "side_l"
        u0, v0, u1, v1 = build_van.view_rect(view)
        if right:
            u = build_van.remap(x, build_van.X_NOSE, build_van.X_TAIL, u0, u1)
        else:
            u = build_van.remap(x, build_van.X_NOSE, build_van.X_TAIL, u1, u0)
        v = build_van.remap(
            z, build_van.Z_GROUND, build_van.Z_ROOF, v0, v1 - build_van.ROOF_BLEED
        )
        return u, v

    underside_uv = texel_to_uv(*UNDERSIDE_TEXEL)

    for tag, profile in profiles.items():
        points = [(x_of(col), z_of(row)) for col, row in profile]
        body_z = z_of(profile[0][1])

        # Two rails of verts along the tyre outline, one per flank, plus the
        # matching pair up on the body line that the block hangs from.
        right_low, left_low, right_top, left_top = [], [], [], []
        for x, z in points:
            right_low.append(bm.verts.new((x, WHEEL_HALF, z)))
            left_low.append(bm.verts.new((x, -WHEEL_HALF, z)))
            right_top.append(bm.verts.new((x, WHEEL_HALF, body_z)))
            left_top.append(bm.verts.new((x, -WHEEL_HALF, body_z)))
        bm.verts.ensure_lookup_table()

        for i in range(len(points) - 1):
            # The visible flanks: these carry the painted tyre.
            right = bm.faces.new(
                (right_top[i], right_top[i + 1], right_low[i + 1], right_low[i])
            )
            for loop in right.loops:
                co = loop.vert.co
                loop[uv_layer].uv = side_uv(co.x, co.z, True)

            left = bm.faces.new(
                (left_low[i], left_low[i + 1], left_top[i + 1], left_top[i])
            )
            for loop in left.loops:
                co = loop.vert.co
                loop[uv_layer].uv = side_uv(co.x, co.z, False)

            # The tread, closing the block underneath so it is solid.
            tread = bm.faces.new(
                (left_low[i], right_low[i], right_low[i + 1], left_low[i + 1])
            )
            for loop in tread.loops:
                loop[uv_layer].uv = underside_uv

            for face in (right, left, tread):
                face.smooth = False

        # Cap the two ends where the block meets the sills.
        for verts in (
            (right_top[0], right_low[0], left_low[0], left_top[0]),
            (left_top[-1], left_low[-1], right_low[-1], right_top[-1]),
        ):
            cap = bm.faces.new(verts)
            cap.smooth = False
            for loop in cap.loops:
                loop[uv_layer].uv = underside_uv

    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def main():
    body = bpy.data.objects.get("Van")
    if body is None:
        raise RuntimeError("No object named 'Van' in this file")

    profiles = read_tyre_profiles()
    remove_wheel_objects()
    add_wheels(body, profiles)

    uv_layer = body.data.uv_layers.active
    if uv_layer is None or len(uv_layer.data) != len(body.data.loops):
        raise RuntimeError("The body lost its UVs while the wheels were added")

    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    print(f"WHEELS_OK objects={len(bpy.data.objects)} tris={tris}")

    if "--save" in sys.argv:
        bpy.ops.wm.save_mainfile()
        print("SAVED")


main()
