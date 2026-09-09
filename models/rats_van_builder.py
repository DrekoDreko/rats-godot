# -*- coding: utf-8 -*-
import bpy
import bmesh
import mathutils
import math
import os

# --- Dimensions ---
HALF_WIDTH = 1.25          # Max width at beltline / lower body: 2.50m
SHOULDER_HW = 1.08         # Tapered width at roof shoulder: 2.16m
ROOF_HW = 0.96             # Width at roof top chamfer: 1.92m

ROOF_Z = 2.52              # Roof crown peak
SHOULDER_Z = 2.40          # Roof shoulder (base of roof chamfer)
WIN_TOP_Z = 2.36           # Top edge of cab door window opening
DOOR_SILL_Z = 1.40         # Sill of the cab door glass, level with the base of the windshield
BELT_Z = 1.30              # Beltline (middle stripe)
ARCH_Z = 0.88              # Top of wheel arches
FLOOR_Z = 0.45             # Cargo floor height (2.07m standing headroom!)
SILL_Z = 0.36              # Bottom rocker panel between wheels

# Exact tumblehome widths for 100% coplanar alignment
SILL_HW = round(HALF_WIDTH - (HALF_WIDTH - SHOULDER_HW) * ((DOOR_SILL_Z - BELT_Z) / (SHOULDER_Z - BELT_Z)), 4)  # 1.1665
WIN_TOP_HW = round(HALF_WIDTH - (HALF_WIDTH - SHOULDER_HW) * ((WIN_TOP_Z - BELT_Z) / (SHOULDER_Z - BELT_Z)), 4)  # 1.0862

# Y Stations
Y_REAR_BOT = -2.70
Y_REAR_BELT = -2.70
Y_REAR_SHOULDER = -2.70     # Door frame extends flush to shoulder at -2.70
Y_REAR_ROOF = -2.50         # Aligned with Y_CORNER for 100% watertight roof corner!

Y_CORNER = -2.50           # Start of vertical corner 45° bevel
Y_REAR_AXLE = -1.40
Y_BULKHEAD = 0.45

Y_WIN_REAR = 0.58          # Rear edge of cab window
Y_WIN_FRONT_TOP = 1.00     # Front upper corner of cab window
Y_WIN_FRONT_BOT = 1.50     # Front lower corner, on the same rake as the A-pillar
Y_WIN_DIV_BOT = 1.14       # Vent window divider, at the sill
Y_WIN_DIV_TOP = 1.02       # Vent window divider, at the top rail
Y_DOOR_BELT_FRONT = 1.21   # Front cut of the door at the beltline (aligned with the wheel arch)
Y_AP_SILL = 1.60           # Outer A-pillar edge at sill level (continuous slope!)
Z_AP_MID = 1.50            # Station shared by the pillar's inner and outer edges

# Windshield rebate: the inner edge of the A-pillar, where the glass lands.  It
# is a single straight line, 5 mm behind the glass plane, so the pillar reads as
# one continuous rake and the frame can be built from the same two points.
AP_REBATE_BOT = (0.96, 1.63, 1.39)
AP_REBATE_TOP = (0.86, 1.07, 2.42)

# Windshield glass corners, 5 mm proud of the rebate on the same rake.
GLASS_BOT = (0.955, 1.630, 1.400)
GLASS_TOP = (0.855, 1.075, 2.420)

Y_FRONT_AXLE = 1.70
Y_COWL = 1.65
Y_WINDSHIELD_TOP = 1.05
Y_NOSE = 2.65
Y_FRONT_BUMPER = 2.80
Y_REAR_BUMPER = -2.85

X_FRAME_REAR = 1.12        # Rear door frame outer corner
X_DOOR_HINGE = 0.88        # Rear door outer hinge axis        # Rear door outer hinge axis

WHEEL_RADIUS = 0.40
WHEEL_WIDTH = 0.28

ARCH_RADIUS = 0.49         # Wheel arch cut-out radius
ARCH_AXLE_Z = 0.40         # Centre height of that arch

# Inner surface of the cargo lining, right half, as (half width, Z) pairs.
LINER_PROFILE = [
    (1.225, 0.49),
    (1.225, BELT_Z),
    (1.058, SHOULDER_Z),
    (0.940, 2.495),
    (0.000, 2.505),
]

# Bulkhead: solid partition with a single horizontal glazed hatch, no doorway.
# Every dimension below is written at 1:1 body scale.  The game needs a bigger
# van - four players with a 0.4 m capsule have to pass each other inside - so the
# finished hierarchy is scaled once, at the end of run(), and baked into the
# mesh data.  Edit the constants at body scale and let this do the rest.
VAN_SCALE = 1.25

LOBBY_FIXTURES = False     # workbench, shelving, bench, rails: removed from the van

BULKHEAD_T = 0.05
BULKHEAD_WIN_HW = 0.66
BULKHEAD_WIN_Z0 = 1.58
BULKHEAD_WIN_Z1 = 2.06

TEXTURE_PATH = r"c:\\Users\\Ferrareto\\Documents\\Lucas\\GAMES\\rats-godot\\models\\rats_van_texture.png"


def _add_cube(bm, size=(1.0, 1.0, 1.0), pos=(0.0, 0.0, 0.0)):
    res = bmesh.ops.create_cube(bm, size=1.0)
    for v in res['verts']:
        v.co.x = pos[0] + v.co.x * size[0]
        v.co.y = pos[1] + v.co.y * size[1]
        v.co.z = pos[2] + v.co.z * size[2]
    return res['verts']


def _add_cylinder(bm, radius=0.1, depth=1.0, pos=(0.0, 0.0, 0.0), axis='Z', segments=12):
    res = bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=segments, radius1=radius, radius2=radius, depth=depth)
    for v in res['verts']:
        vx, vy, vz = v.co.x, v.co.y, v.co.z
        if axis == 'X':
            v.co.x = pos[0] + vz
            v.co.y = pos[1] + vy
            v.co.z = pos[2] + vx
        elif axis == 'Y':
            v.co.x = pos[0] + vx
            v.co.y = pos[1] + vz
            v.co.z = pos[2] + vy
        else:
            v.co.x = pos[0] + vx
            v.co.y = pos[1] + vy
            v.co.z = pos[2] + vz
    return res['verts']


def add_oriented_box(bm, p_start, p_end, width, thickness, up_hint=None):
    p1 = mathutils.Vector(p_start)
    p2 = mathutils.Vector(p_end)
    axis = p2 - p1
    length = axis.length
    if length < 1e-6:
        return []
    axis_n = axis.normalized()

    if up_hint is None:
        up_hint = mathutils.Vector((0.0, 0.0, 1.0)) if abs(axis_n.z) < 0.90 else mathutils.Vector((0.0, 1.0, 0.0))

    u = axis_n.cross(up_hint)
    if u.length < 1e-4:
        u = axis_n.cross(mathutils.Vector((1.0, 0.0, 0.0)))
    u.normalize()

    v = axis_n.cross(u).normalized()

    hw = width * 0.5
    ht = thickness * 0.5

    v0 = bm.verts.new(p1 - u * hw - v * ht)
    v1 = bm.verts.new(p1 + u * hw - v * ht)
    v2 = bm.verts.new(p1 + u * hw + v * ht)
    v3 = bm.verts.new(p1 - u * hw + v * ht)

    v4 = bm.verts.new(p2 - u * hw - v * ht)
    v5 = bm.verts.new(p2 + u * hw - v * ht)
    v6 = bm.verts.new(p2 + u * hw + v * ht)
    v7 = bm.verts.new(p2 - u * hw + v * ht)

    f_bot = bm.faces.new((v3, v2, v1, v0))
    f_top = bm.faces.new((v4, v5, v6, v7))
    f_s0  = bm.faces.new((v0, v1, v5, v4))
    f_s1  = bm.faces.new((v1, v2, v6, v5))
    f_s2  = bm.faces.new((v2, v3, v7, v6))
    f_s3  = bm.faces.new((v3, v0, v4, v7))

    return [f_bot, f_top, f_s0, f_s1, f_s2, f_s3]


def _add_ring(bm, center, axis, radius, tube, segments=12):
    """Square-section ring (steering wheel rim, gauge bezel) around *axis*."""
    c = mathutils.Vector(center)
    n = mathutils.Vector(axis).normalized()
    ref = mathutils.Vector((0.0, 0.0, 1.0))
    if abs(n.dot(ref)) > 0.90:
        ref = mathutils.Vector((0.0, 1.0, 0.0))
    u = n.cross(ref).normalized()
    v = n.cross(u).normalized()

    sections = []
    for i in range(segments):
        th = i * (2.0 * math.pi / segments)
        d = u * math.cos(th) + v * math.sin(th)
        p = c + d * radius
        sections.append([
            bm.verts.new(p + d * tube + n * tube),
            bm.verts.new(p + d * tube - n * tube),
            bm.verts.new(p - d * tube - n * tube),
            bm.verts.new(p - d * tube + n * tube),
        ])

    faces = []
    for i in range(segments):
        a = sections[i]
        b = sections[(i + 1) % segments]
        for k in range(4):
            k2 = (k + 1) % 4
            faces.append(bm.faces.new((a[k], a[k2], b[k2], b[k])))
    return faces


def _add_prism_x(bm, profile_yz, x0, x1):
    """Extrude a closed YZ polygon along X into a capped solid."""
    ring0 = [bm.verts.new((x0, y, z)) for y, z in profile_yz]
    ring1 = [bm.verts.new((x1, y, z)) for y, z in profile_yz]
    count = len(profile_yz)
    faces = []
    for i in range(count):
        j = (i + 1) % count
        faces.append(bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i])))
    faces.append(bm.faces.new(list(reversed(ring0))))
    faces.append(bm.faces.new(ring1))
    return faces


def _octagon(half_w, half_h, chamfer):
    """Chamfered rectangle centred on the origin - a soft mirror outline."""
    c = min(chamfer, half_w * 0.9, half_h * 0.9)
    return [
        (-half_w + c, -half_h), (half_w - c, -half_h),
        (half_w, -half_h + c), (half_w, half_h - c),
        (half_w - c, half_h), (-half_w + c, half_h),
        (-half_w, half_h - c), (-half_w, -half_h + c),
    ]


def _add_prism_oriented(bm, profile, center, normal, depth, up_hint=None):
    """Extrude a 2D profile through *depth*, facing *normal*, around *center*."""
    n = mathutils.Vector(normal).normalized()
    up = mathutils.Vector(up_hint if up_hint is not None else (0.0, 0.0, 1.0))
    u_ax = up.cross(n)
    if u_ax.length < 1e-4:
        u_ax = mathutils.Vector((1.0, 0.0, 0.0)).cross(n)
    u_ax.normalize()
    v_ax = n.cross(u_ax).normalized()
    c = mathutils.Vector(center)
    back = c - n * (depth * 0.5)
    front = c + n * (depth * 0.5)
    ring0 = [bm.verts.new(back + u_ax * a + v_ax * b) for a, b in profile]
    ring1 = [bm.verts.new(front + u_ax * a + v_ax * b) for a, b in profile]
    count = len(profile)
    faces = []
    for i in range(count):
        j = (i + 1) % count
        faces.append(bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i])))
    faces.append(bm.faces.new(list(reversed(ring0))))
    faces.append(bm.faces.new(ring1))
    return faces


def _add_aperture_panel(bm, x0, x1, z0, z1, ax0, ax1, az0, az1, y, thickness):
    """Panel in the XZ plane with a rectangular window opening cut through it."""
    x_lo, x_hi = sorted((x0, x1))
    ax_lo, ax_hi = sorted((ax0, ax1))
    z_lo, z_hi = sorted((z0, z1))
    az_lo, az_hi = sorted((az0, az1))
    bands = [
        ((x_lo, x_hi), (z_lo, az_lo)),    # below the opening
        ((x_lo, x_hi), (az_hi, z_hi)),    # above the opening
        ((x_lo, ax_lo), (az_lo, az_hi)),  # inboard stile
        ((ax_hi, x_hi), (az_lo, az_hi)),  # outboard stile
    ]
    for (bx0, bx1), (bz0, bz1) in bands:
        w = bx1 - bx0
        h = bz1 - bz0
        if w <= 1e-5 or h <= 1e-5:
            continue
        _add_cube(bm, size=(w, thickness, h), pos=((bx0 + bx1) * 0.5, y, (bz0 + bz1) * 0.5))


def _add_aperture_ring(bm, ax0, ax1, az0, az1, y, thickness, band):
    """Folded return flange lining the four edges of a window aperture."""
    ax_lo, ax_hi = sorted((ax0, ax1))
    az_lo, az_hi = sorted((az0, az1))
    w = ax_hi - ax_lo
    h = az_hi - az_lo
    cx = (ax_lo + ax_hi) * 0.5
    cz = (az_lo + az_hi) * 0.5
    _add_cube(bm, size=(w, thickness, band), pos=(cx, y, az_lo + band * 0.5))
    _add_cube(bm, size=(w, thickness, band), pos=(cx, y, az_hi - band * 0.5))
    _add_cube(bm, size=(band, thickness, h), pos=(ax_lo + band * 0.5, y, cz))
    _add_cube(bm, size=(band, thickness, h), pos=(ax_hi - band * 0.5, y, cz))


def _mark_faces(bm, first_index, material_index):
    """Assign a material slot to every face added since *first_index*."""
    bm.faces.ensure_lookup_table()
    for face in bm.faces[first_index:]:
        face.material_index = material_index


def _flat_uv(me, u=0.85, v=0.06):
    """Pin a whole mesh to a single texel of the atlas."""
    uv_layer = me.uv_layers.new(name="UVMap")
    me.uv_layers.active = uv_layer
    for loop_idx in range(len(me.loops)):
        uv_layer.data[loop_idx].uv = (u, v)

def _liner_hw(z):
    """Half width of the cargo lining's inner surface at height *z*."""
    pts = LINER_PROFILE
    if z <= pts[0][1]:
        return pts[0][0]
    for (hw0, z0), (hw1, z1) in zip(pts, pts[1:]):
        if z <= z1:
            t = (z - z0) / (z1 - z0)
            return hw0 + (hw1 - hw0) * t
    return pts[-1][0]


def _liner_section():
    """Full cross-section of the lining, left floor edge over the roof to the right."""
    # Floor edge up the left wall, across the crown, back down the right wall.
    left = [(-hw, z) for hw, z in LINER_PROFILE[:-1]]
    crown = [(LINER_PROFILE[-1][0], LINER_PROFILE[-1][1])]
    right = [(hw, z) for hw, z in reversed(LINER_PROFILE[:-1])]
    return left + crown + right


def _ap_rebate(z):
    """Point (x, y) on the windshield rebate line at height *z*, right side."""
    (x0, y0, z0), (x1, y1, z1) = AP_REBATE_BOT, AP_REBATE_TOP
    t = (z - z0) / (z1 - z0)
    return x0 + (x1 - x0) * t, y0 + (y1 - y0) * t


def _glass_edge(z):
    """Point (x, y) on the windshield's side edge at height *z*, right side."""
    (x0, y0, z0), (x1, y1, z1) = GLASS_BOT, GLASS_TOP
    t = (z - z0) / (z1 - z0)
    return x0 + (x1 - x0) * t, y0 + (y1 - y0) * t


def _arch_points():
    """Wheel arch outline as (dy, z) offsets from the axle, rear to front.

    Shared by the body cut-out, the wheel tub and the cargo lining so the three
    describe exactly the same opening.
    """
    pts = []
    for deg in [0, 30, 60, 90, 120, 150, 180]:
        rad = math.radians(deg)
        dy = -ARCH_RADIUS * math.cos(rad)
        dz = ARCH_RADIUS * math.sin(rad)
        z = ARCH_AXLE_Z + dz if (0 < deg < 180) else SILL_Z
        pts.append((round(dy, 4), round(z, 4)))
    return pts


def _arch_top_z(y_min, y_max):
    """Highest point of a wheel tub shell between stations *y_min* and *y_max*.

    Returns ``None`` when the span clears both arches, so cargo bay fittings can
    stop short of the tubs instead of poking through them into the wheel.
    """
    pts = _arch_points()
    top = None
    for y_axle in (Y_REAR_AXLE, Y_FRONT_AXLE):
        for (dy0, z0), (dy1, z1) in zip(pts, pts[1:]):
            lo = max(y_min - y_axle, dy0)
            hi = min(y_max - y_axle, dy1)
            if lo > hi:
                continue
            for dy in (lo, hi):
                z = z0 + (z1 - z0) * (dy - dy0) / (dy1 - dy0)
                top = z if top is None else max(top, z)
    return top


def _face_inward(bm, pivot):
    """Point every face of *bm* toward *pivot* - a shell seen only from inside."""
    bm.normal_update()
    target = mathutils.Vector(pivot)
    for face in bm.faces:
        if face.normal.dot(target - face.calc_center_median()) < 0.0:
            face.normal_flip()
    bm.normal_update()


def _add_prism(bm, profile_xz, y0, y1):
    """Extrude a closed XZ polygon along Y into a capped solid."""
    ring0 = [bm.verts.new((x, y0, z)) for x, z in profile_xz]
    ring1 = [bm.verts.new((x, y1, z)) for x, z in profile_xz]
    count = len(profile_xz)
    faces = []
    for i in range(count):
        j = (i + 1) % count
        faces.append(bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i])))
    faces.append(bm.faces.new(list(reversed(ring0))))
    faces.append(bm.faces.new(ring1))
    return faces

def run():
    if bpy.context.mode != 'OBJECT':
        try:
            bpy.ops.object.mode_set(mode='OBJECT')
        except Exception:
            pass
    _clean_scene()
    mats = _setup_materials()
    root = bpy.data.objects.new("Van_Root", None)
    bpy.context.scene.collection.objects.link(root)

    col_ext = _get_or_create_collection("Van_Exterior")
    col_glass = _get_or_create_collection("Van_Glass")
    col_doors = _get_or_create_collection("Van_Doors")
    col_cab = _get_or_create_collection("Van_Interior_Cab")
    col_lobby = _get_or_create_collection("Van_Interior_Lobby")
    col_wheels = _get_or_create_collection("Van_Wheels")
    col_collision = _get_or_create_collection("Van_Collision")

    _build_exterior_body(root, col_ext, mats)
    _build_bumpers(root, col_ext, mats)
    _build_front_details(root, col_ext, mats)
    _build_windshield_and_cab_frames(root, col_ext, mats)
    _build_mirrors_and_wipers(root, col_ext, mats)
    _build_undercarriage(root, col_ext, mats)
    _build_wheel_tubs(root, col_ext, mats)
    _build_windows(root, col_glass, mats)
    _build_rear_doors(root, col_doors, mats)
    _build_wheels(root, col_wheels, mats)
    _build_cab_interior(root, col_cab, mats)
    _build_cargo_liner(root, col_lobby, mats)
    _build_lobby_interior(root, col_lobby, mats)
    if LOBBY_FIXTURES:
        _build_lobby_fixtures(root, col_lobby, mats)
    _build_collision(root, col_collision)
    _setup_lighting(root)

    _apply_van_scale(root, VAN_SCALE)

    if bpy.context.mode != 'OBJECT':
        try:
            bpy.ops.object.mode_set(mode='OBJECT')
        except Exception:
            pass

    print("Van built successfully with refined glass, pillars and frames!")


def _apply_van_scale(root, scale):
    """Bake a uniform scale into the finished van, in place.

    Scaling the hierarchy instead of the constants keeps every measurement in
    this file readable at body scale, and keeps the proportions exact.  Mesh
    data is transformed so nothing is left with a non-unit object scale, which
    would otherwise reach Godot as a scaled node.
    """
    if abs(scale - 1.0) < 1e-9:
        return

    matrix = mathutils.Matrix.Scale(scale, 4)
    seen = set()
    stack = list(root.children)
    while stack:
        obj = stack.pop()
        stack.extend(obj.children)
        obj.location = obj.location * scale
        if obj.type == 'MESH':
            if obj.data.name not in seen:
                seen.add(obj.data.name)
                obj.data.transform(matrix)
        elif obj.type == 'LIGHT' and obj.data.type in {'POINT', 'SPOT', 'AREA'}:
            # Point light falloff is inverse square, so the same look at a
            # bigger radius costs the square of the scale.
            obj.data.energy *= scale * scale


def _clean_scene():
    if bpy.context.view_layer.objects.active and bpy.context.view_layer.objects.active.mode != 'OBJECT':
        try:
            bpy.ops.object.mode_set(mode='OBJECT')
        except Exception:
            pass
    for obj in list(bpy.data.objects):
        if obj.type not in {'CAMERA', 'LIGHT'}:
            bpy.data.objects.remove(obj, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)


def _get_or_create_collection(name):
    col = bpy.data.collections.get(name)
    if not col:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    return col


def _setup_materials():
    mats = {}

    # MAT_Van_Texture
    m_tex = bpy.data.materials.get("MAT_Van_Texture") or bpy.data.materials.new("MAT_Van_Texture")
    m_tex.use_nodes = True
    nt = m_tex.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex_node = nt.nodes.new("ShaderNodeTexImage")
    if os.path.exists(TEXTURE_PATH):
        img = bpy.data.images.load(TEXTURE_PATH, check_existing=True)
        img.reload()
        tex_node.image = img
        tex_node.interpolation = 'Closest'
    nt.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.55
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    mats["texture"] = m_tex

    # MAT_Van_Glass (Translucent, clear view to interior)
    m_glass = bpy.data.materials.get("MAT_Van_Glass") or bpy.data.materials.new("MAT_Van_Glass")
    m_glass.use_nodes = True
    nt_g = m_glass.node_tree
    nt_g.nodes.clear()
    out_g = nt_g.nodes.new("ShaderNodeOutputMaterial")
    bsdf_g = nt_g.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_g.inputs["Base Color"].default_value = (0.80, 0.90, 0.95, 1.0)
    bsdf_g.inputs["Roughness"].default_value = 0.04
    if "Transmission Weight" in bsdf_g.inputs:
        bsdf_g.inputs["Transmission Weight"].default_value = 0.90
    elif "Transmission" in bsdf_g.inputs:
        bsdf_g.inputs["Transmission"].default_value = 0.90
    bsdf_g.inputs["Alpha"].default_value = 0.28
    if hasattr(m_glass, "blend_method"):
        m_glass.blend_method = 'BLEND'
    if hasattr(m_glass, "shadow_method"):
        m_glass.shadow_method = 'NONE'
    # EEVEE Next (Blender 4.2+) dropped blend_method in favour of the render method
    if hasattr(m_glass, "surface_render_method"):
        m_glass.surface_render_method = 'BLENDED'
    nt_g.links.new(bsdf_g.outputs["BSDF"], out_g.inputs["Surface"])
    mats["glass"] = m_glass

    # MAT_Van_Bumper (Dark chassis/bumper/rubber gasket)
    m_bump = bpy.data.materials.get("MAT_Van_Bumper") or bpy.data.materials.new("MAT_Van_Bumper")
    m_bump.use_nodes = True
    nt_b = m_bump.node_tree
    nt_b.nodes.clear()
    out_b = nt_b.nodes.new("ShaderNodeOutputMaterial")
    bsdf_b = nt_b.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_b.inputs["Base Color"].default_value = (0.16, 0.16, 0.17, 1.0)
    bsdf_b.inputs["Roughness"].default_value = 0.70
    bsdf_b.inputs["Metallic"].default_value = 0.30
    nt_b.links.new(bsdf_b.outputs["BSDF"], out_b.inputs["Surface"])
    mats["bumper"] = m_bump
    # MAT_Van_Underbody (Deep dark matte undercoating for inner wheel wells)
    m_und = bpy.data.materials.get("MAT_Van_Underbody") or bpy.data.materials.new("MAT_Van_Underbody")
    m_und.use_nodes = True
    nt_u = m_und.node_tree
    nt_u.nodes.clear()
    out_u = nt_u.nodes.new("ShaderNodeOutputMaterial")
    bsdf_u = nt_u.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_u.inputs["Base Color"].default_value = (0.02, 0.02, 0.02, 1.0)
    bsdf_u.inputs["Roughness"].default_value = 0.95
    bsdf_u.inputs["Metallic"].default_value = 0.0
    nt_u.links.new(bsdf_u.outputs["BSDF"], out_u.inputs["Surface"])
    mats["underbody"] = m_und

    # MAT_Van_Steel_Pillar (Vintage dark blue/gray steel structural frame)
    m_stl = bpy.data.materials.get("MAT_Van_Steel_Pillar") or bpy.data.materials.new("MAT_Van_Steel_Pillar")
    m_stl.use_nodes = True
    nt_s = m_stl.node_tree
    nt_s.nodes.clear()
    out_s = nt_s.nodes.new("ShaderNodeOutputMaterial")
    bsdf_s = nt_s.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_s.inputs["Base Color"].default_value = (0.18, 0.23, 0.28, 1.0) # Matches van dark blue body
    bsdf_s.inputs["Roughness"].default_value = 0.45
    bsdf_s.inputs["Metallic"].default_value = 0.50
    nt_s.links.new(bsdf_s.outputs["BSDF"], out_s.inputs["Surface"])
    mats["steel_pillar"] = m_stl
    mats["steel"] = m_stl

    # MAT_Van_Chrome
    m_chr = bpy.data.materials.get("MAT_Van_Chrome") or bpy.data.materials.new("MAT_Van_Chrome")
    m_chr.use_nodes = True
    nt_c = m_chr.node_tree
    nt_c.nodes.clear()
    out_c = nt_c.nodes.new("ShaderNodeOutputMaterial")
    bsdf_c = nt_c.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_c.inputs["Base Color"].default_value = (0.85, 0.85, 0.87, 1.0)
    bsdf_c.inputs["Metallic"].default_value = 0.90
    bsdf_c.inputs["Roughness"].default_value = 0.18
    nt_c.links.new(bsdf_c.outputs["BSDF"], out_c.inputs["Surface"])
    mats["chrome"] = m_chr

    # MAT_Van_Emit_Warm
    m_emit = bpy.data.materials.get("MAT_Van_Emit_Warm") or bpy.data.materials.new("MAT_Van_Emit_Warm")
    m_emit.use_nodes = True
    nt_e = m_emit.node_tree
    nt_e.nodes.clear()
    out_e = nt_e.nodes.new("ShaderNodeOutputMaterial")
    bsdf_e = nt_e.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_e.inputs["Base Color"].default_value = (1.0, 0.95, 0.85, 1.0)
    if "Emission Color" in bsdf_e.inputs:
        bsdf_e.inputs["Emission Color"].default_value = (1.0, 0.95, 0.85, 1.0)
        bsdf_e.inputs["Emission Strength"].default_value = 3.5
    nt_e.links.new(bsdf_e.outputs["BSDF"], out_e.inputs["Surface"])
    mats["emit_warm"] = m_emit

    # MAT_Van_TailLight
    m_tail = bpy.data.materials.get("MAT_Van_TailLight") or bpy.data.materials.new("MAT_Van_TailLight")
    m_tail.use_nodes = True
    nt_t = m_tail.node_tree
    nt_t.nodes.clear()
    out_t = nt_t.nodes.new("ShaderNodeOutputMaterial")
    bsdf_t = nt_t.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_t.inputs["Base Color"].default_value = (0.85, 0.05, 0.05, 1.0)
    if "Emission Color" in bsdf_t.inputs:
        bsdf_t.inputs["Emission Color"].default_value = (0.85, 0.05, 0.05, 1.0)
        bsdf_t.inputs["Emission Strength"].default_value = 1.2
    nt_t.links.new(bsdf_t.outputs["BSDF"], out_t.inputs["Surface"])
    mats["taillight"] = m_tail

    # MAT_Van_TurnSignal
    m_turn = bpy.data.materials.get("MAT_Van_TurnSignal") or bpy.data.materials.new("MAT_Van_TurnSignal")
    m_turn.use_nodes = True
    nt_u = m_turn.node_tree
    nt_u.nodes.clear()
    out_u = nt_u.nodes.new("ShaderNodeOutputMaterial")
    bsdf_u = nt_u.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_u.inputs["Base Color"].default_value = (0.95, 0.55, 0.05, 1.0)
    if "Emission Color" in bsdf_u.inputs:
        bsdf_u.inputs["Emission Color"].default_value = (0.95, 0.55, 0.05, 1.0)
        bsdf_u.inputs["Emission Strength"].default_value = 1.5
    nt_u.links.new(bsdf_u.outputs["BSDF"], out_u.inputs["Surface"])
    mats["turnsignal"] = m_turn

    # MAT_Van_Vinyl (Seat upholstery / door cards)
    m_vin = bpy.data.materials.get("MAT_Van_Vinyl") or bpy.data.materials.new("MAT_Van_Vinyl")
    m_vin.use_nodes = True
    nt_v = m_vin.node_tree
    nt_v.nodes.clear()
    out_v = nt_v.nodes.new("ShaderNodeOutputMaterial")
    bsdf_v = nt_v.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_v.inputs["Base Color"].default_value = (0.11, 0.14, 0.12, 1.0)
    bsdf_v.inputs["Roughness"].default_value = 0.82
    nt_v.links.new(bsdf_v.outputs["BSDF"], out_v.inputs["Surface"])
    mats["vinyl"] = m_vin

    # MAT_Seat_Leather (PBR leather for bucket seats)
    m_lth = bpy.data.materials.get("MAT_Seat_Leather") or bpy.data.materials.new("MAT_Seat_Leather")
    m_lth.use_nodes = True
    nt_l = m_lth.node_tree
    nt_l.nodes.clear()
    out_l = nt_l.nodes.new("ShaderNodeOutputMaterial")
    bsdf_l = nt_l.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_l.inputs["Roughness"].default_value = 0.42
    if "Coat Weight" in bsdf_l.inputs:
        bsdf_l.inputs["Coat Weight"].default_value = 0.25
        bsdf_l.inputs["Coat Roughness"].default_value = 0.25

    models_dir = os.path.dirname(TEXTURE_PATH)
    alb_path = os.path.join(models_dir, "seat_leather_albedo.png")
    if os.path.exists(alb_path):
        i_alb = bpy.data.images.load(alb_path, check_existing=True)
        t_alb = nt_l.nodes.new("ShaderNodeTexImage")
        t_alb.image = i_alb
        nt_l.links.new(t_alb.outputs["Color"], bsdf_l.inputs["Base Color"])
    else:
        bsdf_l.inputs["Base Color"].default_value = (0.025, 0.025, 0.028, 1.0)

    norm_path = os.path.join(models_dir, "seat_leather_normal.png")
    if os.path.exists(norm_path):
        i_norm = bpy.data.images.load(norm_path, check_existing=True)
        i_norm.colorspace_settings.name = 'Non-Color'
        t_norm = nt_l.nodes.new("ShaderNodeTexImage")
        t_norm.image = i_norm
        n_map = nt_l.nodes.new("ShaderNodeNormalMap")
        n_map.inputs["Strength"].default_value = 0.8
        nt_l.links.new(t_norm.outputs["Color"], n_map.inputs["Color"])
        nt_l.links.new(n_map.outputs["Normal"], bsdf_l.inputs["Normal"])

    nt_l.links.new(bsdf_l.outputs["BSDF"], out_l.inputs["Surface"])
    mats["leather"] = m_lth

    # MAT_Seat_Trim
    m_strim = bpy.data.materials.get("MAT_Seat_Trim") or bpy.data.materials.new("MAT_Seat_Trim")
    m_strim.use_nodes = True
    nt_st = m_strim.node_tree
    nt_st.nodes.clear()
    out_st = nt_st.nodes.new("ShaderNodeOutputMaterial")
    bsdf_st = nt_st.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_st.inputs["Base Color"].default_value = (0.04, 0.04, 0.045, 1.0)
    bsdf_st.inputs["Roughness"].default_value = 0.70
    nt_st.links.new(bsdf_st.outputs["BSDF"], out_st.inputs["Surface"])
    mats["seat_trim"] = m_strim

    # MAT_Seat_RedAccent
    m_sred = bpy.data.materials.get("MAT_Seat_RedAccent") or bpy.data.materials.new("MAT_Seat_RedAccent")
    m_sred.use_nodes = True
    nt_sr = m_sred.node_tree
    nt_sr.nodes.clear()
    out_sr = nt_sr.nodes.new("ShaderNodeOutputMaterial")
    bsdf_sr = nt_sr.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_sr.inputs["Base Color"].default_value = (0.85, 0.05, 0.05, 1.0)
    bsdf_sr.inputs["Roughness"].default_value = 0.35
    nt_sr.links.new(bsdf_sr.outputs["BSDF"], out_sr.inputs["Surface"])
    mats["seat_red"] = m_sred

    m_pls = bpy.data.materials.get("MAT_Van_Plastic") or bpy.data.materials.new("MAT_Van_Plastic")
    m_pls.use_nodes = True
    nt_p = m_pls.node_tree
    nt_p.nodes.clear()
    out_p = nt_p.nodes.new("ShaderNodeOutputMaterial")
    bsdf_p = nt_p.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_p.inputs["Base Color"].default_value = (0.09, 0.10, 0.11, 1.0)
    bsdf_p.inputs["Roughness"].default_value = 0.68
    nt_p.links.new(bsdf_p.outputs["BSDF"], out_p.inputs["Surface"])
    mats["plastic"] = m_pls

    # MAT_Van_Gauge (Backlit instrument cluster face)
    m_gau = bpy.data.materials.get("MAT_Van_Gauge") or bpy.data.materials.new("MAT_Van_Gauge")
    m_gau.use_nodes = True
    nt_ga = m_gau.node_tree
    nt_ga.nodes.clear()
    out_ga = nt_ga.nodes.new("ShaderNodeOutputMaterial")
    bsdf_ga = nt_ga.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_ga.inputs["Base Color"].default_value = (0.06, 0.06, 0.07, 1.0)
    bsdf_ga.inputs["Roughness"].default_value = 0.35
    if "Emission Color" in bsdf_ga.inputs:
        bsdf_ga.inputs["Emission Color"].default_value = (0.95, 0.62, 0.18, 1.0)
        bsdf_ga.inputs["Emission Strength"].default_value = 2.2
    nt_ga.links.new(bsdf_ga.outputs["BSDF"], out_ga.inputs["Surface"])
    mats["gauge"] = m_gau

    # MAT_Van_Liner (Headliner / sun visors)
    m_lin = bpy.data.materials.get("MAT_Van_Liner") or bpy.data.materials.new("MAT_Van_Liner")
    m_lin.use_nodes = True
    nt_l = m_lin.node_tree
    nt_l.nodes.clear()
    out_l = nt_l.nodes.new("ShaderNodeOutputMaterial")
    bsdf_l = nt_l.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf_l.inputs["Base Color"].default_value = (0.52, 0.50, 0.45, 1.0)
    bsdf_l.inputs["Roughness"].default_value = 0.90
    nt_l.links.new(bsdf_l.outputs["BSDF"], out_l.inputs["Surface"])
    mats["liner"] = m_lin
    return mats


def _create_mesh_obj(name, collection, parent=None):
    me = bpy.data.meshes.new(name + "_mesh")
    obj = bpy.data.objects.new(name, me)
    collection.objects.link(obj)
    if parent:
        obj.parent = parent
    return obj, me


def _build_exterior_body(root, col, mats):
    obj, me = _create_mesh_obj("Van_Body", col, root)
    bm = bmesh.new()

    arch_pts = _arch_points()

    cargo_y = [Y_CORNER] + [Y_REAR_AXLE + dy for dy, _ in arch_pts] + [Y_BULKHEAD]

    # Roof crown center vertices for each cargo station
    v_rf_center_cargo = []
    for yst in cargo_y:
        v_rf_center_cargo.append(bm.verts.new((0.0, yst, ROOF_Z + 0.02)))

    v_rf_w_mid = bm.verts.new((0.0, Y_WINDSHIELD_TOP, ROOF_Z))
    # Header and cowl edges carry the same 5 mm crown as the glass, so the
    # rubber surround covers the joint evenly all the way across.
    v_glass_top_mid = bm.verts.new((0.0, AP_REBATE_TOP[1] + 0.005, AP_REBATE_TOP[2] + 0.005))
    v_glass_bot_mid = bm.verts.new((0.0, AP_REBATE_BOT[1], AP_REBATE_BOT[2] + 0.005))
    v_hood_cowl     = bm.verts.new((0.0, Y_COWL, BELT_Z + 0.06))
    v_hood_nose     = bm.verts.new((0.0, Y_NOSE, BELT_Z - 0.02))
    v_fr_bot_mid    = bm.verts.new((0.0, Y_NOSE, FLOOR_Z))
    v_hdr_mid       = bm.verts.new((0.0, Y_REAR_SHOULDER, SHOULDER_Z))

    def build_side(sign):
        sx = lambda val: sign * val

        # Rear Corner Vertices
        v_bot_corner_r = bm.verts.new((sx(X_FRAME_REAR), Y_REAR_BOT, FLOOR_Z))
        v_corner_r     = bm.verts.new((sx(X_FRAME_REAR), Y_REAR_BELT, BELT_Z))
        v_sill_r       = bm.verts.new((sx(SILL_HW * (X_FRAME_REAR / HALF_WIDTH)), Y_REAR_BELT, DOOR_SILL_Z))
        v_sh_r         = bm.verts.new((sx(SHOULDER_HW), Y_REAR_SHOULDER, SHOULDER_Z))

        # Cargo Stations Vertices (from Y=-2.50 to Y=0.45)
        v_cargo_belt = []
        v_cargo_sill = []
        v_cargo_sh   = []
        v_cargo_rf   = []
        for yst in cargo_y:
            v_cargo_belt.append(bm.verts.new((sx(HALF_WIDTH), yst, BELT_Z)))
            v_cargo_sill.append(bm.verts.new((sx(SILL_HW), yst, DOOR_SILL_Z)))
            v_cargo_sh.append(bm.verts.new((sx(SHOULDER_HW), yst, SHOULDER_Z)))
            v_cargo_rf.append(bm.verts.new((sx(ROOF_HW), yst, ROOF_Z)))

        v_rf_r = v_cargo_rf[0] # Exact alignment at Y_CORNER = -2.50

        v_bot_corner_s = bm.verts.new((sx(HALF_WIDTH), Y_CORNER, SILL_Z))
        v_b_bot        = bm.verts.new((sx(HALF_WIDTH), Y_BULKHEAD, SILL_Z))

        # Rear Arch Cutout Vertices
        r_arch_verts = []
        for dy, z in arch_pts:
            yst = Y_REAR_AXLE + dy
            r_arch_verts.append(bm.verts.new((sx(HALF_WIDTH), yst, z)))

        # Cab Roof & Windshield Corner
        v_sh_w = bm.verts.new((sx(SHOULDER_HW * 0.92), Y_WINDSHIELD_TOP, SHOULDER_Z + 0.06))
        v_rf_w = bm.verts.new((sx(ROOF_HW * 0.92), Y_WINDSHIELD_TOP, ROOF_Z - 0.02))

        # Cab Door Vertices
        v_door_belt_r = bm.verts.new((sx(HALF_WIDTH), Y_WIN_REAR, BELT_Z))
        v_win_sill_r  = bm.verts.new((sx(SILL_HW), Y_WIN_REAR, DOOR_SILL_Z))
        v_win_top_r   = bm.verts.new((sx(WIN_TOP_HW), Y_WIN_REAR, WIN_TOP_Z))
        v_sh_win_r    = bm.verts.new((sx(SHOULDER_HW), Y_WIN_REAR, SHOULDER_Z))

        v_door_belt_f = bm.verts.new((sx(HALF_WIDTH), Y_DOOR_BELT_FRONT, BELT_Z))
        v_win_sill_f  = bm.verts.new((sx(SILL_HW), Y_WIN_FRONT_BOT, DOOR_SILL_Z))
        v_win_top_f   = bm.verts.new((sx(WIN_TOP_HW), Y_WIN_FRONT_TOP, WIN_TOP_Z))
        v_sh_win_f    = bm.verts.new((sx(SHOULDER_HW), Y_WIN_FRONT_TOP, SHOULDER_Z))

        v_cowl    = bm.verts.new((sx(HALF_WIDTH), Y_COWL, BELT_Z))
        v_ap_sill = bm.verts.new((sx(SILL_HW), Y_AP_SILL, DOOR_SILL_Z))

        # Front Arch Vertices
        f_arch_verts = []
        f_belt_verts = []
        for dy, z in arch_pts:
            yst = Y_FRONT_AXLE + dy
            f_arch_verts.append(bm.verts.new((sx(HALF_WIDTH), yst, z)))
            f_belt_verts.append(bm.verts.new((sx(HALF_WIDTH), yst, BELT_Z)))

        # Windshield Inner Frame Vertices (all three on the rebate line)
        ap_mid_x, ap_mid_y = _ap_rebate(Z_AP_MID)
        v_ap_top_in = bm.verts.new((sx(AP_REBATE_TOP[0]), AP_REBATE_TOP[1], AP_REBATE_TOP[2]))
        v_ap_mid_in = bm.verts.new((sx(ap_mid_x), ap_mid_y, Z_AP_MID))
        v_ap_bot_in = bm.verts.new((sx(AP_REBATE_BOT[0]), AP_REBATE_BOT[1], AP_REBATE_BOT[2]))

        # Front Nose Vertices
        v_nose_s     = bm.verts.new((sx(HALF_WIDTH * 0.92), Y_NOSE, BELT_Z - 0.05))
        v_nose_c     = bm.verts.new((sx(X_DOOR_HINGE), Y_NOSE, BELT_Z - 0.05))
        v_bot_nose_s = bm.verts.new((sx(HALF_WIDTH * 0.92), Y_NOSE, FLOOR_Z))
        v_bot_nose_c = bm.verts.new((sx(X_DOOR_HINGE), Y_NOSE, FLOOR_Z))

        # Rear Door Opening Vertices
        v_sill_door = bm.verts.new((sx(X_DOOR_HINGE), Y_REAR_BOT, FLOOR_Z))
        v_belt_door = bm.verts.new((sx(X_DOOR_HINGE), Y_REAR_BELT, BELT_Z))
        v_hdr_door  = bm.verts.new((sx(X_DOOR_HINGE), Y_REAR_SHOULDER, SHOULDER_Z))

        def add_f(verts):
            if sign < 0:
                return bm.faces.new(verts)
            else:
                return bm.faces.new(list(reversed(verts)))

        # 1. Beveled Rear Corner
        add_f((v_bot_corner_s, v_bot_corner_r, v_corner_r, v_cargo_belt[0]))
        add_f((v_cargo_belt[0], v_corner_r, v_sill_r, v_cargo_sill[0]))
        add_f((v_cargo_sill[0], v_sill_r, v_sh_r, v_cargo_sh[0]))
        add_f((v_cargo_sh[0], v_sh_r, v_rf_r))

        # 2. Lower Fender around Rear Wheel Arch
        add_f((v_bot_corner_s, v_cargo_belt[0], v_cargo_belt[1], r_arch_verts[0]))
        for i in range(6):
            add_f((r_arch_verts[i], v_cargo_belt[i+1], v_cargo_belt[i+2], r_arch_verts[i+1]))
        add_f((r_arch_verts[6], v_cargo_belt[7], v_cargo_belt[8], v_b_bot))

        # 3. Cargo Wall Lower Row (Belt to Sill) - 100% Watertight!
        for i in range(len(cargo_y) - 1):
            add_f((v_cargo_belt[i], v_cargo_belt[i+1], v_cargo_sill[i+1], v_cargo_sill[i]))

        # 4. Cargo Wall Upper Row (Sill to Shoulder) - 100% Watertight!
        for i in range(len(cargo_y) - 1):
            add_f((v_cargo_sill[i], v_cargo_sill[i+1], v_cargo_sh[i+1], v_cargo_sh[i]))

        # 5. Roof Chamfer over Cargo Area
        for i in range(len(cargo_y) - 1):
            add_f((v_cargo_sh[i], v_cargo_sh[i+1], v_cargo_rf[i+1], v_cargo_rf[i]))

        # 6. Roof Chamfer over Cab Area
        v_sh_b = v_cargo_sh[-1]
        v_rf_b = v_cargo_rf[-1]
        add_f((v_sh_b, v_sh_win_r, v_rf_b))
        add_f((v_sh_win_r, v_sh_win_f, v_rf_w, v_rf_b))
        add_f((v_sh_win_f, v_sh_w, v_rf_w))

        # 7. Cab Door Lower Panels (Beltline to Sill) - Seamless coplanar tumblehome!
        v_sill_b = v_cargo_sill[-1]
        v_b      = v_cargo_belt[-1]
        add_f((v_b, v_door_belt_r, v_win_sill_r, v_sill_b))
        add_f((v_door_belt_r, v_door_belt_f, v_win_sill_f, v_win_sill_r))
        add_f((v_door_belt_f, v_cowl, v_ap_sill, v_win_sill_f))

        # 8. Cab Door B-Pillar, Top Rail, Front Triangle (Leaving opening for window!)
        add_f((v_sill_b, v_win_sill_r, v_win_top_r, v_sh_b))
        add_f((v_win_top_r, v_sh_win_r, v_sh_b))
        add_f((v_win_top_r, v_win_top_f, v_sh_win_f, v_sh_win_r))
        add_f((v_win_sill_f, v_ap_sill, v_sh_w, v_win_top_f))
        add_f((v_win_top_f, v_sh_w, v_sh_win_f))

        # 9. Front Fender & Rocker Panel (100% Watertight connection to all 7 arch points!)
        add_f((v_b_bot, v_b, v_door_belt_r, f_arch_verts[0]))
        add_f((v_door_belt_r, v_door_belt_f, f_belt_verts[0]))
        add_f((v_door_belt_r, f_belt_verts[0], f_arch_verts[0]))

        for i in range(6):
            add_f((f_arch_verts[i], f_belt_verts[i], f_belt_verts[i+1], f_arch_verts[i+1]))
        add_f((f_arch_verts[6], f_belt_verts[6], v_nose_s, v_bot_nose_s))

        add_f((v_door_belt_f, v_cowl, f_belt_verts[1], f_belt_verts[0]))
        add_f((f_belt_verts[1], v_cowl, f_belt_verts[2]))
        add_f((f_belt_verts[2], v_cowl, f_belt_verts[3]))
        add_f((f_belt_verts[3], v_cowl, v_nose_s, f_belt_verts[4]))
        add_f((f_belt_verts[4], v_nose_s, f_belt_verts[5]))
        add_f((f_belt_verts[5], v_nose_s, f_belt_verts[6]))

        # 10. Front A-Pillar Faces
        add_f((v_cowl, v_ap_bot_in, v_ap_mid_in, v_ap_sill))
        add_f((v_ap_sill, v_ap_mid_in, v_ap_top_in, v_sh_w))

        # 11. Front Nose / Hood Side Faces
        add_f((v_bot_nose_s, v_nose_s, v_nose_c, v_bot_nose_c))
        add_f((v_bot_nose_c, v_nose_c, v_hood_nose, v_fr_bot_mid))

        # 12. Rear Door Opening Jamb
        add_f((v_bot_corner_r, v_sill_door, v_belt_door, v_corner_r))
        add_f((v_corner_r, v_belt_door, v_hdr_door, v_sill_r))
        add_f((v_sill_r, v_hdr_door, v_sh_r))

        return {
            "v_cargo_rf": v_cargo_rf,
            "v_rf_r": v_rf_r,
            "v_sh_r": v_sh_r,
            "v_rf_w": v_rf_w,
            "v_sh_w": v_sh_w,
            "v_ap_top_in": v_ap_top_in,
            "v_ap_bot_in": v_ap_bot_in,
            "v_cowl": v_cowl,
            "v_nose_s": v_nose_s,
            "v_nose_c": v_nose_c,
        }

    left_d  = build_side(-1.0)
    right_d = build_side(1.0)

    # Central Roof Crown (Cargo Area)
    for i in range(len(cargo_y) - 1):
        bm.faces.new((left_d["v_cargo_rf"][i], left_d["v_cargo_rf"][i+1], v_rf_center_cargo[i+1], v_rf_center_cargo[i]))
        bm.faces.new((right_d["v_cargo_rf"][i], v_rf_center_cargo[i], v_rf_center_cargo[i+1], right_d["v_cargo_rf"][i+1]))

    # Cab Roof Crown
    bm.faces.new((left_d["v_cargo_rf"][-1], left_d["v_rf_w"], v_rf_w_mid, v_rf_center_cargo[-1]))
    bm.faces.new((right_d["v_cargo_rf"][-1], v_rf_center_cargo[-1], v_rf_w_mid, right_d["v_rf_w"]))

    # Front Roof Corner Chamfers (Closing triangle at A-pillar roof junction!)
    bm.faces.new((left_d["v_sh_w"], v_rf_w_mid, left_d["v_rf_w"]))
    bm.faces.new((right_d["v_sh_w"], right_d["v_rf_w"], v_rf_w_mid))

    # Rear Roof Chamfer over doors (100% Watertight closure!)
    bm.faces.new((left_d["v_sh_r"], v_hdr_mid, v_rf_center_cargo[0], left_d["v_rf_r"]))
    bm.faces.new((right_d["v_sh_r"], right_d["v_rf_r"], v_rf_center_cargo[0], v_hdr_mid))

    # Windshield Brow / Header
    bm.faces.new((left_d["v_ap_top_in"], left_d["v_sh_w"], v_rf_w_mid, v_glass_top_mid))
    bm.faces.new((v_glass_top_mid, v_rf_w_mid, right_d["v_sh_w"], right_d["v_ap_top_in"]))

    # Cowl Ledge
    bm.faces.new((left_d["v_cowl"], left_d["v_ap_bot_in"], v_glass_bot_mid, v_hood_cowl))
    bm.faces.new((v_hood_cowl, v_glass_bot_mid, right_d["v_ap_bot_in"], right_d["v_cowl"]))

    # Front Hood Center (sharing v_nose_c to eliminate nose seam!)
    bm.faces.new((left_d["v_cowl"], v_hood_cowl, left_d["v_nose_c"], left_d["v_nose_s"]))
    bm.faces.new((right_d["v_cowl"], right_d["v_nose_s"], right_d["v_nose_c"], v_hood_cowl))
    bm.faces.new((v_hood_cowl, v_hood_nose, left_d["v_nose_c"]))
    bm.faces.new((v_hood_cowl, right_d["v_nose_c"], v_hood_nose))

    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mats["texture"])

    # UV Mapping for Van Body
    uv_layer = me.uv_layers.new(name="UVMap")
    me.uv_layers.active = uv_layer
    for poly in me.polygons:
        norm = poly.normal
        c = poly.center
        for loop_idx in poly.loop_indices:
            v_idx = me.loops[loop_idx].vertex_index
            v = me.vertices[v_idx].co

            # 1. Left Body Side Outer Panels
            if norm.x < -0.20 or c.x < -0.90:
                u = 0.50 - ((v.y - Y_REAR_BOT) / (Y_NOSE - Y_REAR_BOT)) * 0.49
                v_coord = 0.75 + ((v.z - SILL_Z) / (ROOF_Z - SILL_Z)) * 0.24
                v_coord = min(max(v_coord, 0.75), 0.99)
                u = min(max(u, 0.01), 0.50)

            # 2. Right Body Side Outer Panels
            elif norm.x > 0.20 or c.x > 0.90:
                u = 0.51 + ((v.y - Y_REAR_BOT) / (Y_NOSE - Y_REAR_BOT)) * 0.48
                v_coord = 0.75 + ((v.z - SILL_Z) / (ROOF_Z - SILL_Z)) * 0.24
                v_coord = min(max(v_coord, 0.75), 0.99)
                u = min(max(u, 0.51), 0.99)

            # 3. Roof & Longitudinal Roof Chamfers
            elif norm.z > 0.35 and c.z > 2.25 and c.y > -2.40:
                u = 0.53 + ((v.x + HALF_WIDTH) / (2 * HALF_WIDTH)) * 0.44
                v_coord = 0.53 + ((v.y - Y_REAR_BOT) / (Y_NOSE - Y_REAR_BOT)) * 0.20

            # 4. Rear Frame / Jambs / Rear Header / Beveled Rear Corners
            elif norm.y < -0.20 or c.y < -2.45:
                u = 0.27 + ((v.x + HALF_WIDTH) / (2 * HALF_WIDTH)) * 0.21
                v_coord = 0.53 + ((v.z - SILL_Z) / (ROOF_Z - SILL_Z)) * 0.20

            # 5. Front Nose / Grille Surround / Cowl / Hood / Windshield Surround
            else:
                u = 0.03 + ((v.x + HALF_WIDTH) / (2 * HALF_WIDTH)) * 0.19
                v_coord = 0.53 + ((v.z - SILL_Z) / (ROOF_Z - SILL_Z)) * 0.20

            uv_layer.data[loop_idx].uv = (min(max(u, 0.0), 1.0), min(max(v_coord, 0.0), 1.0))


def _build_windshield_and_cab_frames(root, col, mats):
    obj_frm, me_frm = _create_mesh_obj("Van_Window_Frames", col, root)
    bm = bmesh.new()

    # 1. Roof drip rails, straight along the shoulder from the rear door header
    #    to the front of the cab window.  Past that the roof kicks up toward the
    #    windshield corner, so a rail carried further would poke through it.
    for sign in (-1.0, 1.0):
        add_oriented_box(bm,
                         (sign * (SHOULDER_HW + 0.01), Y_REAR_SHOULDER, SHOULDER_Z + 0.01),
                         (sign * (SHOULDER_HW + 0.01), Y_WIN_FRONT_TOP, SHOULDER_Z + 0.01),
                         0.018, 0.018)
    _mark_faces(bm, 0, 0)
    n = len(bm.faces)

    # 2. Windshield surround: one closed rubber loop seated on the rebate, with
    #    the four bars sharing their corner points so the joints cannot gap.
    frame_bl = (-AP_REBATE_BOT[0] - 0.002, AP_REBATE_BOT[1] + 0.004, AP_REBATE_BOT[2] + 0.004)
    frame_br = (AP_REBATE_BOT[0] + 0.002, AP_REBATE_BOT[1] + 0.004, AP_REBATE_BOT[2] + 0.004)
    frame_tl = (-AP_REBATE_TOP[0] - 0.002, AP_REBATE_TOP[1] + 0.008, AP_REBATE_TOP[2] - 0.003)
    frame_tr = (AP_REBATE_TOP[0] + 0.002, AP_REBATE_TOP[1] + 0.008, AP_REBATE_TOP[2] - 0.003)
    for p_start, p_end in [(frame_bl, frame_br), (frame_tl, frame_tr),
                           (frame_bl, frame_tl), (frame_br, frame_tr)]:
        add_oriented_box(bm, p_start, p_end, 0.055, 0.032)
    _mark_faces(bm, n, 1)

    bm.normal_update()
    bm.to_mesh(me_frm)
    bm.free()
    me_frm.materials.append(mats["steel_pillar"])  # 0 drip rails
    me_frm.materials.append(mats["bumper"])        # 1 windshield surround


def _build_bumpers(root, col, mats):
    # Front Bumper (Heavy-duty stamped steel with wraparounds, chassis horns, rubber overriders, and license plate)
    obj_fb, me_fb = _create_mesh_obj("Van_Bumper_Front", col, root)
    bm_fb = bmesh.new()
    # Main central bar
    _add_cube(bm_fb, size=(2.30, 0.12, 0.20), pos=(0.0, 2.76, 0.48))
    # Left & Right 45° wraparound corner ends
    add_oriented_box(bm_fb, (-1.15, 2.76, 0.48), (-1.26, 2.62, 0.48), 0.20, 0.10)
    add_oriented_box(bm_fb, (1.15, 2.76, 0.48), (1.26, 2.62, 0.48), 0.20, 0.10)
    # Chassis frame horn mounting brackets
    _add_cube(bm_fb, size=(0.06, 0.22, 0.12), pos=(-0.52, 2.67, 0.48))
    _add_cube(bm_fb, size=(0.06, 0.22, 0.12), pos=(0.52, 2.67, 0.48))
    # Rubber vertical bumper overriders (bumperettes)
    _add_cube(bm_fb, size=(0.07, 0.05, 0.26), pos=(-0.48, 2.83, 0.48))
    _add_cube(bm_fb, size=(0.07, 0.05, 0.26), pos=(0.48, 2.83, 0.48))
    # Front license plate holder & plate
    _add_cube(bm_fb, size=(0.32, 0.02, 0.16), pos=(0.0, 2.83, 0.46))
    _add_cube(bm_fb, size=(0.30, 0.012, 0.14), pos=(0.0, 2.842, 0.46))
    bm_fb.normal_update()
    bm_fb.to_mesh(me_fb)
    bm_fb.free()
    me_fb.materials.append(mats["bumper"])

    # Rear Bumper (Heavy-duty stamped steel with wraparounds, center non-slip step plate, and brackets)
    obj_rb, me_rb = _create_mesh_obj("Van_Bumper_Rear", col, root)
    bm_rb = bmesh.new()
    # Main central bar
    _add_cube(bm_rb, size=(2.24, 0.12, 0.20), pos=(0.0, -2.81, 0.48))
    # Left & Right 45° wraparound corner ends
    add_oriented_box(bm_rb, (-1.12, -2.81, 0.48), (-1.24, -2.68, 0.48), 0.20, 0.10)
    add_oriented_box(bm_rb, (1.12, -2.81, 0.48), (1.24, -2.68, 0.48), 0.20, 0.10)
    # Center non-slip entrance step
    _add_cube(bm_rb, size=(0.76, 0.14, 0.04), pos=(0.0, -2.81, 0.58))
    # Chassis frame mounting brackets
    _add_cube(bm_rb, size=(0.06, 0.20, 0.12), pos=(-0.52, -2.73, 0.48))
    _add_cube(bm_rb, size=(0.06, 0.20, 0.12), pos=(0.52, -2.73, 0.48))
    # Rubber bumper overriders
    _add_cube(bm_rb, size=(0.07, 0.05, 0.26), pos=(-0.46, -2.88, 0.48))
    _add_cube(bm_rb, size=(0.07, 0.05, 0.26), pos=(0.46, -2.88, 0.48))
    # Rear license plate & lamp
    _add_cube(bm_rb, size=(0.32, 0.02, 0.16), pos=(-0.25, -2.72, 0.72))
    _add_cube(bm_rb, size=(0.10, 0.04, 0.04), pos=(-0.25, -2.73, 0.82))
    bm_rb.normal_update()
    bm_rb.to_mesh(me_rb)
    bm_rb.free()
    me_rb.materials.append(mats["bumper"])


def _build_front_details(root, col, mats):
    # Front Grille Dark Recessed Backing
    obj_g, me_g = _create_mesh_obj("Van_Grille_Backing", col, root)
    bm_g = bmesh.new()
    _add_cube(bm_g, size=(1.56, 0.05, 0.38), pos=(0.0, Y_NOSE + 0.02, 0.96))
    bm_g.to_mesh(me_g)
    bm_g.free()
    me_g.materials.append(mats["bumper"])

    # Front Grille Chrome Slats & Emblem
    obj_gc, me_gc = _create_mesh_obj("Van_Grille_Chrome", col, root)
    bm_gc = bmesh.new()
    for bz in [0.82, 0.91, 1.00, 1.09]:
        _add_cube(bm_gc, size=(1.48, 0.03, 0.025), pos=(0.0, Y_NOSE + 0.055, bz))
    _add_cube(bm_gc, size=(0.20, 0.03, 0.09), pos=(0.0, Y_NOSE + 0.065, 0.96))
    bm_gc.to_mesh(me_gc)
    bm_gc.free()
    me_gc.materials.append(mats["chrome"])

    # Round Headlights
    for side, sx in [("L", -0.92), ("R", 0.92)]:
        obj_hl, me_hl = _create_mesh_obj(f"Van_Headlight_{side}", col, root)
        bm_hl = bmesh.new()
        _add_cube(bm_hl, size=(0.26, 0.05, 0.26), pos=(sx, Y_NOSE + 0.02, 0.96))
        _add_cylinder(bm_hl, radius=0.10, depth=0.04, pos=(sx, Y_NOSE + 0.05, 0.96), axis='Y', segments=16)
        bm_hl.to_mesh(me_hl)
        bm_hl.free()
        me_hl.materials.append(mats["emit_warm"])

    # Turn Signals (Amber)
    for side, sx in [("L", -0.92), ("R", 0.92)]:
        obj_ts, me_ts = _create_mesh_obj(f"Van_TurnSignal_{side}", col, root)
        bm_ts = bmesh.new()
        _add_cube(bm_ts, size=(0.22, 0.04, 0.10), pos=(sx, Y_NOSE + 0.03, 0.72))
        bm_ts.to_mesh(me_ts)
        bm_ts.free()
        me_ts.materials.append(mats["turnsignal"])

        # Taillights (Vintage 3-section vertical clusters: red brake, amber turn, white reverse)
    for side, sx in [("L", -1.02), ("R", 1.02)]:
        obj_tl, me_tl = _create_mesh_obj(f"Van_Taillight_{side}", col, root)
        bm_tl = bmesh.new()
        # Outer dark chrome bezel housing
        f_bez = _add_cube(bm_tl, size=(0.08, 0.025, 0.40), pos=(sx, Y_REAR_BELT - 0.015, 1.18))
        for v in f_bez: pass
        # 1. Upper Red Brake Lens
        f_red = _add_cube(bm_tl, size=(0.068, 0.018, 0.16), pos=(sx, Y_REAR_BELT - 0.028, 1.28))
        # 2. Middle Amber Turn Indicator
        f_amb = _add_cube(bm_tl, size=(0.068, 0.018, 0.10), pos=(sx, Y_REAR_BELT - 0.028, 1.14))
        # 3. Lower White Reverse Light
        f_wht = _add_cube(bm_tl, size=(0.068, 0.018, 0.08), pos=(sx, Y_REAR_BELT - 0.028, 1.04))

        # Assign material slots
        bm_tl.faces.ensure_lookup_table()
        # Bezel: slot 0 (bumper)
        for i in range(0, 6): bm_tl.faces[i].material_index = 0
        # Red: slot 1 (taillight)
        for i in range(6, 12): bm_tl.faces[i].material_index = 1
        # Amber: slot 2 (turnsignal)
        for i in range(12, 18): bm_tl.faces[i].material_index = 2
        # White: slot 3 (emit_warm)
        for i in range(18, 24): bm_tl.faces[i].material_index = 3

        bm_tl.normal_update()
        bm_tl.to_mesh(me_tl)
        bm_tl.free()
        me_tl.materials.append(mats["bumper"])
        me_tl.materials.append(mats["taillight"])
        me_tl.materials.append(mats["turnsignal"])
        me_tl.materials.append(mats["emit_warm"])

    # Cab Roof Amber Clearance Lights (5 heavy-duty vintage cab marker lights with dark base and amber lens)
    obj_cl, me_cl = _create_mesh_obj("Van_Cab_Clearance_Lights", col, root)
    bm_cl = bmesh.new()
    for cx in [-0.56, -0.28, 0.0, 0.28, 0.56]:
        # Dark rubber base
        f_base_start = len(bm_cl.faces)
        _add_cube(bm_cl, size=(0.055, 0.08, 0.015), pos=(cx, Y_WINDSHIELD_TOP + 0.04, ROOF_Z - 0.038))
        bm_cl.faces.ensure_lookup_table()
        for f in bm_cl.faces[f_base_start:]:
            f.material_index = 0

        # Amber lens
        f_lens_start = len(bm_cl.faces)
        _add_cube(bm_cl, size=(0.045, 0.065, 0.015), pos=(cx, Y_WINDSHIELD_TOP + 0.04, ROOF_Z - 0.026))
        bm_cl.faces.ensure_lookup_table()
        for f in bm_cl.faces[f_lens_start:]:
            f.material_index = 1

    bm_cl.normal_update()
    bm_cl.to_mesh(me_cl)
    bm_cl.free()
    me_cl.materials.append(mats["bumper"])
    me_cl.materials.append(mats["turnsignal"])


def _build_wheel_tubs(root, col, mats):
    # Circular inner wheel housing liner conforming exactly to the 6-segment circular arch
    arch_pts = _arch_points()

    def _create_tub(bm, is_left, y_center):
        sign = -1.0 if is_left else 1.0
        # The rim reaches out to the body skin, so it seals the arch against the
        # cargo lining, whose cut-out edge lies on this same swept surface.
        x_out = sign * (HALF_WIDTH - 0.005)
        x_in  = sign * (HALF_WIDTH - 0.35)

        v_out = []
        v_in  = []
        for dy, z in arch_pts:
            yst = y_center + dy
            v_out.append(bm.verts.new((x_out, yst, z)))
            v_in.append(bm.verts.new((x_in, yst, z)))

        # 6 curved vault ceiling faces
        for i in range(6):
            if is_left:
                bm.faces.new((v_out[i+1], v_in[i+1], v_in[i], v_out[i]))
            else:
                bm.faces.new((v_out[i], v_in[i], v_in[i+1], v_out[i+1]))

        # Inner vertical back wall polygon closing interior
        if is_left:
            bm.faces.new([v_in[i] for i in range(len(v_in))])
        else:
            bm.faces.new([v_in[i] for i in reversed(range(len(v_in)))])


    tubs = [
        ("FL", True, Y_FRONT_AXLE),
        ("FR", False, Y_FRONT_AXLE),
        ("RL", True, Y_REAR_AXLE),
        ("RR", False, Y_REAR_AXLE),
    ]
    for tub_name, is_left, ty in tubs:
        obj_tb, me_tb = _create_mesh_obj(f"Van_WheelTub_{tub_name}", col, root)
        bm_tb = bmesh.new()
        _create_tub(bm_tb, is_left, ty)
        bm_tb.normal_update()
        bm_tb.to_mesh(me_tb)
        bm_tb.free()
        me_tb.materials.append(mats["underbody"])


def _build_mirrors_and_wipers(root, col, mats):
    # West-coast style mirrors: chamfered head on a twin-tube arm, with a
    # convex spotter underneath.  Mounted on the door skin below the new sill.
    for side in ("L", "R"):
        sign = -1.0 if side == "L" else 1.0
        obj_m, me_m = _create_mesh_obj(f"Van_Mirror_{side}", col, root)
        bm_m = bmesh.new()

        x_skin = sign * (HALF_WIDTH + 0.005)
        x_head = sign * (HALF_WIDTH + 0.205)
        # The head sits ahead of the A-pillar so it never covers the door glass
        head = mathutils.Vector((x_head, 1.54, 1.72))
        spot = mathutils.Vector((x_head, 1.52, 1.40))
        # The glass looks back and inboard, at the driver - not straight sideways
        aim = mathutils.Vector((-sign * 0.45, -0.89, -0.06)).normalized()

        # Mounting pads on the door skin, below the beltline
        _add_cube(bm_m, size=(0.024, 0.12, 0.13), pos=(sign * (HALF_WIDTH - 0.006), 1.15, 1.18))
        _add_cube(bm_m, size=(0.024, 0.10, 0.10), pos=(sign * (HALF_WIDTH - 0.006), 1.12, 1.00))
        # Twin tubular arms sweeping up and forward, west-coast style
        # A post outboard of the glass carries both heads; the stays reach it
        # below the housings, so nothing ever crosses a mirror face.
        back = head - aim * 0.030
        add_oriented_box(bm_m, (back.x, back.y, 1.15), (back.x, back.y, 1.90), 0.028, 0.028)
        add_oriented_box(bm_m, (x_skin, 1.17, 1.50), (back.x, back.y, 1.50), 0.024, 0.024)
        add_oriented_box(bm_m, (x_skin, 1.12, 1.15), (back.x, back.y, 1.15), 0.024, 0.024)
        _mark_faces(bm_m, 0, 0)
        n = len(bm_m.faces)

        # Housings: chamfered rectangles, tall and narrow like a van mirror
        _add_prism_oriented(bm_m, _octagon(0.075, 0.135, 0.035), head, aim, 0.055)
        _add_prism_oriented(bm_m, _octagon(0.058, 0.052, 0.022), spot, aim, 0.045)
        _mark_faces(bm_m, n, 0)
        n = len(bm_m.faces)

        # Reflective faces, sitting proud of the housing front
        _add_prism_oriented(bm_m, _octagon(0.063, 0.123, 0.030), head + aim * 0.030, aim, 0.012)
        _add_prism_oriented(bm_m, _octagon(0.047, 0.041, 0.018), spot + aim * 0.025, aim, 0.010)
        _mark_faces(bm_m, n, 1)

        bm_m.normal_update()
        bm_m.to_mesh(me_m)
        bm_m.free()
        me_m.materials.append(mats["bumper"])    # 0 housing, arms
        me_m.materials.append(mats["chrome"])    # 1 mirror glass

    # 3D Cab Exterior Door Handles (Vintage chrome pull handle with keyhole)
    obj_dh, me_dh = _create_mesh_obj("Van_Cab_Door_Handles", col, root)
    bm_dh = bmesh.new()
    for side, sx in [("L", -SILL_HW), ("R", SILL_HW)]:
        sign = -1.0 if side == "L" else 1.0
        _add_cube(bm_dh, size=(0.016, 0.18, 0.055), pos=(sx + sign * 0.008, 0.90, 1.20))
        _add_cube(bm_dh, size=(0.022, 0.14, 0.024), pos=(sx + sign * 0.022, 0.90, 1.20))
        _add_cylinder(bm_dh, radius=0.007, depth=0.02, pos=(sx + sign * 0.012, 0.78, 1.20), axis='X', segments=6)
    bm_dh.normal_update()
    bm_dh.to_mesh(me_dh)
    bm_dh.free()
    me_dh.materials.append(mats["chrome"])

    # Fuel Filler Door (Driver side left)
    obj_fl, me_fl = _create_mesh_obj("Van_Fuel_Door", col, root)
    bm_fl = bmesh.new()
    _add_cube(bm_fl, size=(0.008, 0.17, 0.17), pos=(-HALF_WIDTH - 0.004, 0.05, 1.02))
    _add_cylinder(bm_fl, radius=0.012, depth=0.012, pos=(-HALF_WIDTH - 0.008, 0.11, 1.02), axis='X', segments=6)
    bm_fl.normal_update()
    bm_fl.to_mesh(me_fl)
    bm_fl.free()
    me_fl.materials.append(mats["bumper"])

    # Windshield Wipers
    obj_wp, me_wp = _create_mesh_obj("Van_Wipers", col, root)
    bm_wp = bmesh.new()
    _add_cylinder(bm_wp, radius=0.016, depth=0.035, pos=(-0.45, Y_COWL - 0.005, BELT_Z + 0.08), axis='Z', segments=8)
    add_oriented_box(bm_wp, (-0.45, Y_COWL - 0.005, BELT_Z + 0.08), (-0.20, 1.61, 1.45), 0.018, 0.012)
    add_oriented_box(bm_wp, (-0.42, 1.605, 1.47), (-0.02, 1.575, 1.53), 0.014, 0.022)
    _add_cylinder(bm_wp, radius=0.016, depth=0.035, pos=(0.18, Y_COWL - 0.005, BELT_Z + 0.08), axis='Z', segments=8)
    add_oriented_box(bm_wp, (0.18, Y_COWL - 0.005, BELT_Z + 0.08), (0.43, 1.61, 1.45), 0.018, 0.012)
    add_oriented_box(bm_wp, (0.23, 1.605, 1.47), (0.63, 1.575, 1.53), 0.014, 0.022)
    bm_wp.normal_update()
    bm_wp.to_mesh(me_wp)
    bm_wp.free()
    me_wp.materials.append(mats["bumper"])


def _build_undercarriage(root, col, mats):
    obj_u, me_u = _create_mesh_obj("Van_Differential", col, root)
    bm_u = bmesh.new()
    _add_cylinder(bm_u, radius=0.045, depth=2.10, pos=(0.0, Y_REAR_AXLE, 0.30), axis='X', segments=10)
    _add_cube(bm_u, size=(0.26, 0.26, 0.20), pos=(0.0, Y_REAR_AXLE, 0.30))
    _add_cylinder(bm_u, radius=0.03, depth=2.20, pos=(0.0, Y_REAR_AXLE + 1.10, 0.30), axis='Y', segments=8)
    bm_u.to_mesh(me_u)
    bm_u.free()
    me_u.materials.append(mats["bumper"])


def _build_windows(root, col, mats):
    # 1. Front Windshield (Crystal-clear curved translucent glass + perimeter rubber gasket)
    obj_ws, me_ws = _create_mesh_obj("Van_Windshield", col, root)
    bm_ws = bmesh.new()

    # Single-piece windshield: one flat pane on the rake, its four corners 5 mm
    # proud of the body rebate so the surround in Van_Window_Frames covers the
    # joint on every side.  The old crown at the top and bottom edges did not
    # match the opening and left a slot open at the centre.
    gx_b, gy_b, gz_b = GLASS_BOT
    gx_t, gy_t, gz_t = GLASS_TOP
    v_bl = bm_ws.verts.new((-gx_b, gy_b, gz_b))
    v_bm = bm_ws.verts.new((0.0, gy_b, gz_b))
    v_br = bm_ws.verts.new((gx_b, gy_b, gz_b))
    v_tr = bm_ws.verts.new((gx_t, gy_t, gz_t))
    v_tm = bm_ws.verts.new((0.0, gy_t, gz_t))
    v_tl = bm_ws.verts.new((-gx_t, gy_t, gz_t))

    bm_ws.faces.new((v_bl, v_bm, v_tm, v_tl))
    bm_ws.faces.new((v_bm, v_br, v_tr, v_tm))

    bm_ws.normal_update()
    bm_ws.to_mesh(me_ws)
    bm_ws.free()
    me_ws.materials.append(mats["glass"])

    # 2. Cab Side Windows (Compact window framed cleanly inside the new door structure)
    # Snug fit: X_bot = SILL_HW, X_top = WIN_TOP_HW, Y from 0.58 to 1.21
    for side, side_name, sign, x_bot, x_top in [(-1, "L", -1.0, -SILL_HW + 0.015, -WIN_TOP_HW + 0.015),
                                                (1, "R", 1.0, SILL_HW - 0.015, WIN_TOP_HW - 0.015)]:
        obj_sw, me_sw = _create_mesh_obj(f"Van_Window_Cab_{side_name}", col, root)
        bm_sw = bmesh.new()

        # Perimeter Rubber Weatherstripping Gasket
        g_sw = [
            ((x_bot, Y_WIN_REAR, DOOR_SILL_Z), (x_bot, Y_WIN_FRONT_BOT, DOOR_SILL_Z), 0.022, 0.020),
            ((x_top, Y_WIN_REAR, WIN_TOP_Z), (x_top, Y_WIN_FRONT_TOP, WIN_TOP_Z), 0.022, 0.020),
            ((x_bot, Y_WIN_REAR, DOOR_SILL_Z), (x_top, Y_WIN_REAR, WIN_TOP_Z), 0.022, 0.020),
            # Front edge: raked on the same line as the A-pillar
            ((x_bot, Y_WIN_FRONT_BOT, DOOR_SILL_Z), (x_top, Y_WIN_FRONT_TOP, WIN_TOP_Z), 0.022, 0.020),
            # Vent window divider
            ((x_bot, Y_WIN_DIV_BOT, DOOR_SILL_Z), (x_top, Y_WIN_DIV_TOP, WIN_TOP_Z), 0.018, 0.018),
        ]
        for g_start, g_end, gw, gt in g_sw:
            g_faces = add_oriented_box(bm_sw, g_start, g_end, gw, gt)
            for gf in g_faces:
                gf.material_index = 1

        # Glass Panels (Translucent)
        # Main Roll-Down Glass
        vg_bl = bm_sw.verts.new((x_bot, Y_WIN_REAR + 0.015, DOOR_SILL_Z + 0.012))
        vg_br = bm_sw.verts.new((x_bot, Y_WIN_DIV_BOT - 0.014, DOOR_SILL_Z + 0.012))
        vg_tr = bm_sw.verts.new((x_top, Y_WIN_DIV_TOP - 0.014, WIN_TOP_Z - 0.012))
        vg_tl = bm_sw.verts.new((x_top, Y_WIN_REAR + 0.015, WIN_TOP_Z - 0.012))
        if sign < 0:
            fg_main = bm_sw.faces.new((vg_bl, vg_br, vg_tr, vg_tl))
        else:
            fg_main = bm_sw.faces.new((vg_bl, vg_tl, vg_tr, vg_br))
        fg_main.material_index = 0

        # Triangular Front Vent Window Glass
        vv_bl = bm_sw.verts.new((x_bot, Y_WIN_DIV_BOT + 0.014, DOOR_SILL_Z + 0.012))
        vv_br = bm_sw.verts.new((x_bot, Y_WIN_FRONT_BOT - 0.015, DOOR_SILL_Z + 0.012))
        vv_tr = bm_sw.verts.new((x_top, Y_WIN_FRONT_TOP - 0.015, WIN_TOP_Z - 0.012))
        vv_tl = bm_sw.verts.new((x_top, Y_WIN_DIV_TOP + 0.014, WIN_TOP_Z - 0.012))
        if sign < 0:
            fg_vent = bm_sw.faces.new((vv_bl, vv_br, vv_tr, vv_tl))
        else:
            fg_vent = bm_sw.faces.new((vv_bl, vv_tl, vv_tr, vv_br))
        fg_vent.material_index = 0

        bm_sw.normal_update()
        bm_sw.to_mesh(me_sw)
        bm_sw.free()
        me_sw.materials.append(mats["glass"])   # Slot 0: Glass
        me_sw.materials.append(mats["bumper"])  # Slot 1: Rubber Frame & Divider  # Slot 1: Rubber Frame & Divider


def _build_rear_doors(root, col, mats):
    door_w = X_DOOR_HINGE          # 0.88m each (1.76m total opening)
    door_h = SHOULDER_Z - FLOOR_Z  # 2.40 - 0.45 = 1.95m
    hinge_z = FLOOR_Z + door_h * 0.5 # 1.425m
    panel_t = 0.045

    # Panel outline (local, measured from the hinge axis at x = 0)
    x_in = 0.005
    x_out = door_w - 0.005
    z_bot = -(door_h - 0.01) * 0.5
    z_top = (door_h - 0.01) * 0.5

    # Window aperture: sits at standing eye height once the van floor is added
    # (world Z 1.73 - 2.21 with the hinge at Z 1.425).
    ax_in = 0.17
    ax_out = 0.71
    az_bot = 0.30
    az_top = 0.78

    # sgn points from the hinge toward the centre line of the van, so the left
    # door hangs at -X_DOOR_HINGE and its panel grows toward +X.
    for side_name, sgn in [("L", 1.0), ("R", -1.0)]:
        obj_door = bpy.data.objects.new(f"Van_Door_{side_name}", None)
        col.objects.link(obj_door)
        obj_door.parent = root
        obj_door.location = (-sgn * X_DOOR_HINGE, Y_REAR_BELT, hinge_z)

        # --- Door body: stamped panel with a real window aperture ---
        me_body = bpy.data.meshes.new(f"Van_Door_{side_name}_Body_mesh")
        obj_body = bpy.data.objects.new(f"Van_Door_{side_name}_Body", me_body)
        col.objects.link(obj_body)
        obj_body.parent = obj_door
        obj_body.location = (0, 0, 0)

        bm = bmesh.new()
        _add_aperture_panel(
            bm,
            x0=sgn * x_in, x1=sgn * x_out,
            z0=z_bot, z1=z_top,
            ax0=sgn * ax_in, ax1=sgn * ax_out,
            az0=az_bot, az1=az_top,
            y=0.0, thickness=panel_t,
        )
        # Window return flange, so the cut edge reads as folded sheet metal
        _add_aperture_ring(
            bm,
            ax0=sgn * ax_in, ax1=sgn * ax_out, az0=az_bot, az1=az_top,
            y=0.0, thickness=panel_t - 0.004, band=0.018,
        )
        # Exterior hinges on the pivot axis
        _add_cylinder(bm, radius=0.018, depth=0.10, pos=(sgn * 0.02, -0.02, 0.55), axis='Z', segments=8)
        _add_cylinder(bm, radius=0.018, depth=0.10, pos=(sgn * 0.02, -0.02, -0.55), axis='Z', segments=8)
        _add_cube(bm, size=(0.04, 0.03, 0.06), pos=(sgn * 0.03, -0.02, 0.55))
        _add_cube(bm, size=(0.04, 0.03, 0.06), pos=(sgn * 0.03, -0.02, -0.55))
        if side_name == "R":
            # Vintage T-handle and escutcheon on the closing door only
            _add_cube(bm, size=(0.04, 0.02, 0.08), pos=(sgn * (door_w - 0.06), -0.03, -0.08))
            _add_cylinder(bm, radius=0.012, depth=0.08, pos=(sgn * (door_w - 0.06), -0.045, -0.08), axis='X', segments=8)

        bm.normal_update()
        bm.to_mesh(me_body)
        bm.free()
        me_body.materials.append(mats["texture"])
        _uv_map_door(me_body, is_left=(side_name == "L"), door_h=door_h)

        # --- Glass: seated inside the aperture, visible from both sides ---
        me_glass = bpy.data.meshes.new(f"Van_Door_Window_{side_name}_mesh")
        obj_glass = bpy.data.objects.new(f"Van_Door_Window_{side_name}", me_glass)
        col.objects.link(obj_glass)
        obj_glass.parent = obj_door
        obj_glass.location = (0, 0, 0)

        bm_g = bmesh.new()
        gx = sgn * (ax_in + ax_out) * 0.5
        gz = (az_bot + az_top) * 0.5
        gw = (ax_out - ax_in) + 0.024   # overlaps the flange, no seam gap
        gh = (az_top - az_bot) + 0.024
        _add_cube(bm_g, size=(gw, 0.010, gh), pos=(gx, 0.0, gz))
        n_glass = len(bm_g.faces)

        # Rubber weatherstrip on both faces of the aperture
        for y_seal in (-(panel_t * 0.5 + 0.004), (panel_t * 0.5 + 0.004)):
            _add_cube(bm_g, size=(gw + 0.030, 0.010, 0.026), pos=(gx, y_seal, az_top + 0.010))
            _add_cube(bm_g, size=(gw + 0.030, 0.010, 0.026), pos=(gx, y_seal, az_bot - 0.010))
            _add_cube(bm_g, size=(0.026, 0.010, gh + 0.026), pos=(sgn * (ax_in - 0.012), y_seal, gz))
            _add_cube(bm_g, size=(0.026, 0.010, gh + 0.026), pos=(sgn * (ax_out + 0.012), y_seal, gz))

        bm_g.faces.ensure_lookup_table()
        for i, f in enumerate(bm_g.faces):
            f.material_index = 0 if i < n_glass else 1
        bm_g.normal_update()
        bm_g.to_mesh(me_glass)
        bm_g.free()
        me_glass.materials.append(mats["glass"])
        me_glass.materials.append(mats["bumper"])

        # --- Cargo-side trim: latch paddle and a grab handle ---
        me_trim = bpy.data.meshes.new(f"Van_Door_Trim_{side_name}_mesh")
        obj_trim = bpy.data.objects.new(f"Van_Door_Trim_{side_name}", me_trim)
        col.objects.link(obj_trim)
        obj_trim.parent = obj_door
        obj_trim.location = (0, 0, 0)

        bm_t = bmesh.new()
        y_in = panel_t * 0.5 + 0.02
        _add_cube(bm_t, size=(0.07, 0.05, 0.16), pos=(sgn * (door_w - 0.14), y_in, -0.06))
        add_oriented_box(
            bm_t,
            (sgn * (door_w - 0.30), y_in + 0.02, 0.05),
            (sgn * (door_w - 0.30), y_in + 0.02, 0.24),
            0.030, 0.030,
        )
        # Vertical locking rods, the giveaway detail of a cargo door
        add_oriented_box(bm_t, (sgn * (door_w - 0.10), y_in, z_bot + 0.06), (sgn * (door_w - 0.10), y_in, -0.02), 0.022, 0.022)
        add_oriented_box(bm_t, (sgn * (door_w - 0.10), y_in, 0.02), (sgn * (door_w - 0.10), y_in, z_top - 0.06), 0.022, 0.022)
        bm_t.normal_update()
        bm_t.to_mesh(me_trim)
        bm_t.free()
        me_trim.materials.append(mats["bumper"])


def _uv_map_door(me, is_left=True, door_h=1.95):
    uv_layer = me.uv_layers.new(name="UVMap")
    me.uv_layers.active = uv_layer
    for poly in me.polygons:
        for loop_idx in poly.loop_indices:
            v_idx = me.loops[loop_idx].vertex_index
            v = me.vertices[v_idx].co
            world_z = 1.425 + v.z
            v_coord = 0.53 + ((world_z - SILL_Z) / (ROOF_Z - SILL_Z)) * 0.20
            if is_left:
                u = 0.28 + (v.x / X_DOOR_HINGE) * 0.095
            else:
                u = 0.47 - (-v.x / X_DOOR_HINGE) * 0.095
            uv_layer.data[loop_idx].uv = (min(max(u, 0.0), 1.0), min(max(v_coord, 0.0), 1.0))


def _build_wheels(root, col, mats):
    positions = [
        ("FL", -HALF_WIDTH + 0.12, Y_FRONT_AXLE, WHEEL_RADIUS),
        ("FR", HALF_WIDTH - 0.12, Y_FRONT_AXLE, WHEEL_RADIUS),
        ("RL", -HALF_WIDTH + 0.12, Y_REAR_AXLE, WHEEL_RADIUS),
        ("RR", HALF_WIDTH - 0.12, Y_REAR_AXLE, WHEEL_RADIUS),
    ]

    def _build_single_wheel(bm, wx, wy, wz, is_left, segments=24):
        sign = -1.0 if is_left else 1.0
        x_out_tread = wx + sign * (WHEEL_WIDTH * 0.5)
        x_in_tread  = wx - sign * (WHEEL_WIDTH * 0.5)

        # Cross-section profile from outer center (dome) to tread
        rings_def = [
            (0.00,  sign * 0.020, 1),   # 0: center tip of chrome dome
            (0.08,  sign * 0.015, 1),   # 1: chrome dome contour
            (0.12, -sign * 0.010, 1),   # 2: chrome dome base
            (0.14, -sign * 0.035, 0),   # 3: rim center recess (dark steel rim)
            (0.20, -sign * 0.045, 0),   # 4: rim deep dish well
            (0.25, -sign * 0.015, 0),   # 5: rim outer lip
            (0.26, -sign * 0.010, 0),   # 6: tire inner bead
            (0.38,  sign * 0.005, 0),   # 7: tire sidewall shoulder
            (0.40,  0.0,          0),   # 8: tire tread outer edge
        ]

        rings = []
        for r, dx, mat in rings_def:
            ring_v = []
            rx = x_out_tread + dx
            for i in range(segments):
                ang = i * (2 * math.pi / segments)
                ry = wy + math.cos(ang) * r
                rz = wz + math.sin(ang) * r
                ring_v.append(bm.verts.new((rx, ry, rz)))
            rings.append((ring_v, mat))

        for idx in range(len(rings) - 1):
            r_cur, mat_cur = rings[idx]
            r_nxt, mat_nxt = rings[idx + 1]
            mat = mat_nxt if idx >= 2 else mat_cur
            for i in range(segments):
                i_nxt = (i + 1) % segments
                v0, v1, v2, v3 = r_cur[i], r_cur[i_nxt], r_nxt[i_nxt], r_nxt[i]
                f = bm.faces.new((v0, v1, v2, v3) if is_left else (v3, v2, v1, v0))
                f.material_index = mat

        r0, _ = rings[0]
        center_v = bm.verts.new((x_out_tread + rings_def[0][1], wy, wz))
        for i in range(segments):
            i_nxt = (i + 1) % segments
            f = bm.faces.new((center_v, r0[i_nxt], r0[i]) if is_left else (center_v, r0[i], r0[i_nxt]))
            f.material_index = 1

        inner_tread_v = []
        for i in range(segments):
            ang = i * (2 * math.pi / segments)
            ry = wy + math.cos(ang) * WHEEL_RADIUS
            rz = wz + math.sin(ang) * WHEEL_RADIUS
            inner_tread_v.append(bm.verts.new((x_in_tread, ry, rz)))

        outer_tread_v = rings[-1][0]
        for i in range(segments):
            i_nxt = (i + 1) % segments
            v_out0, v_out1 = outer_tread_v[i], outer_tread_v[i_nxt]
            v_in1,  v_in0  = inner_tread_v[i_nxt], inner_tread_v[i]
            f = bm.faces.new((v_out0, v_out1, v_in1, v_in0) if is_left else (v_in0, v_in1, v_out1, v_out0))
            f.material_index = 0

        inner_center_v = bm.verts.new((x_in_tread, wy, wz))
        for i in range(segments):
            i_nxt = (i + 1) % segments
            f = bm.faces.new((inner_center_v, inner_tread_v[i], inner_tread_v[i_nxt]) if is_left else (inner_center_v, inner_tread_v[i_nxt], inner_tread_v[i]))
            f.material_index = 0

    for w_name, wx, wy, wz in positions:
        obj_w, me_w = _create_mesh_obj(f"Van_Wheel_{w_name}", col, root)
        bm_w = bmesh.new()
        _build_single_wheel(bm_w, wx, wy, wz, is_left=("L" in w_name), segments=24)
        bm_w.normal_update()
        bm_w.to_mesh(me_w)
        bm_w.free()
        me_w.materials.append(mats["bumper"])  # 0: Tire rubber & rim
        me_w.materials.append(mats["chrome"])  # 1: Chrome hubcap dome


def _build_cab_interior(root, col, mats):
    floor_top = FLOOR_Z + 0.06     # 0.51 - walking surface of the cab
    drv_x = -0.55                  # left-hand drive
    pas_x = 0.55
    card_x = 1.200                 # inner face of the cab door trim

    # --- Floor: rear seating area full width, front footwell between the wheel wells ---
    obj_cf, me_cf = _create_mesh_obj("Cab_Floor", col, root)
    bm_cf = bmesh.new()
    _add_cube(bm_cf, size=((HALF_WIDTH - 0.10) * 2, 0.80, 0.06), pos=(0.0, 0.85, FLOOR_Z + 0.03))
    _add_cube(bm_cf, size=(1.55, 0.40, 0.06), pos=(0.0, 1.45, FLOOR_Z + 0.03))
    # Toe board closing the gap to the front bulkhead
    _add_cube(bm_cf, size=(1.55, 0.06, 0.34), pos=(0.0, 1.62, floor_top + 0.17))
    bm_cf.normal_update()
    bm_cf.to_mesh(me_cf)
    bm_cf.free()
    me_cf.materials.append(mats["bumper"])

    # --- Dashboard shell (atlas-textured, matches the exterior sheet metal) ---
    obj_db, me_db = _create_mesh_obj("Cab_Dashboard", col, root)
    bm_db = bmesh.new()
    _add_cube(bm_db, size=((HALF_WIDTH - 0.10) * 2, 0.28, 0.32), pos=(0.0, 1.45, 1.15))
    # Instrument binnacle: hood lip plus side cheeks, so the cluster sits in a recess
    # The lip clears the top of the steering rim (Z 1.362) by 2 cm.
    _add_cube(bm_db, size=(0.56, 0.10, 0.030), pos=(drv_x, 1.250, 1.400))
    for cheek_x in (drv_x - 0.265, drv_x + 0.265):
        _add_cube(bm_db, size=(0.030, 0.10, 0.240), pos=(cheek_x, 1.250, 1.280))
    # Glovebox lid on the passenger side
    _add_cube(bm_db, size=(0.56, 0.03, 0.22), pos=(0.62, 1.302, 1.10))
    bm_db.normal_update()
    bm_db.to_mesh(me_db)
    bm_db.free()
    me_db.materials.append(mats["texture"])

    uv_layer = me_db.uv_layers.new(name="UVMap")
    me_db.uv_layers.active = uv_layer
    for poly in me_db.polygons:
        for loop_idx in poly.loop_indices:
            v = me_db.vertices[me_db.loops[loop_idx].vertex_index].co
            u = 0.50 + ((v.x + HALF_WIDTH) / (2 * HALF_WIDTH)) * 0.25
            v_coord = 0.25 + ((v.z - 0.95) / 0.45) * 0.25
            uv_layer.data[loop_idx].uv = (min(max(u, 0.50), 0.75), min(max(v_coord, 0.25), 0.50))

    # --- Dash hardware: cluster, radio, vents, handles ---
    obj_dd, me_dd = _create_mesh_obj("Cab_DashDetails", col, root)
    bm_dd = bmesh.new()
    y_face = 1.310                 # rear face of the dash, toward the driver
    axis_y = (0.0, 1.0, 0.0)

    # Cluster sits high in the binnacle, framed by the top of the steering rim
    cl_z = 1.30
    _add_cube(bm_dd, size=(0.46, 0.02, 0.15), pos=(drv_x, y_face + 0.004, cl_z))
    _mark_faces(bm_dd, 0, 0)
    n = len(bm_dd.faces)

    # Backlit speedometer and fuel/temp dials
    _add_cylinder(bm_dd, radius=0.056, depth=0.010, pos=(drv_x - 0.10, y_face - 0.004, cl_z), axis='Y', segments=12)
    _add_cylinder(bm_dd, radius=0.040, depth=0.010, pos=(drv_x + 0.13, y_face - 0.004, cl_z), axis='Y', segments=10)
    _mark_faces(bm_dd, n, 2)
    n = len(bm_dd.faces)

    # Chrome bezels
    _add_ring(bm_dd, (drv_x - 0.10, y_face - 0.006, cl_z), axis_y, 0.064, 0.010, segments=12)
    _add_ring(bm_dd, (drv_x + 0.13, y_face - 0.006, cl_z), axis_y, 0.046, 0.009, segments=10)
    _mark_faces(bm_dd, n, 1)
    n = len(bm_dd.faces)

    # Needles
    add_oriented_box(bm_dd, (drv_x - 0.10, y_face - 0.012, cl_z), (drv_x - 0.145, y_face - 0.012, cl_z + 0.038), 0.008, 0.006)
    add_oriented_box(bm_dd, (drv_x + 0.13, y_face - 0.012, cl_z), (drv_x + 0.155, y_face - 0.012, cl_z + 0.032), 0.007, 0.006)
    _mark_faces(bm_dd, n, 0)
    n = len(bm_dd.faces)

    # Centre stack: radio, two knobs, heater slider
    _add_cube(bm_dd, size=(0.24, 0.06, 0.11), pos=(0.0, y_face + 0.015, 1.14))
    _add_cube(bm_dd, size=(0.20, 0.02, 0.03), pos=(0.0, y_face - 0.005, 1.06))
    _mark_faces(bm_dd, n, 0)
    n = len(bm_dd.faces)
    _add_cylinder(bm_dd, radius=0.016, depth=0.035, pos=(-0.135, y_face - 0.025, 1.14), axis='Y', segments=8)
    _add_cylinder(bm_dd, radius=0.016, depth=0.035, pos=(0.135, y_face - 0.025, 1.14), axis='Y', segments=8)
    _mark_faces(bm_dd, n, 1)
    n = len(bm_dd.faces)

    # Defroster vents with slats
    for vent_x in (-0.30, 0.30):
        _add_cube(bm_dd, size=(0.18, 0.035, 0.07), pos=(vent_x, y_face + 0.002, 1.25))
        for slat_z in (1.232, 1.250, 1.268):
            _add_cube(bm_dd, size=(0.17, 0.012, 0.008), pos=(vent_x, y_face - 0.004, slat_z))
    _mark_faces(bm_dd, n, 0)
    n = len(bm_dd.faces)

    # Glovebox handle
    _add_cube(bm_dd, size=(0.10, 0.035, 0.03), pos=(0.62, y_face - 0.012, 1.17))
    _mark_faces(bm_dd, n, 1)

    bm_dd.normal_update()
    bm_dd.to_mesh(me_dd)
    bm_dd.free()
    me_dd.materials.append(mats["plastic"])   # 0
    me_dd.materials.append(mats["chrome"])    # 1
    me_dd.materials.append(mats["gauge"])     # 2
    _flat_uv(me_dd, 0.60, 0.35)

    # --- Steering column and wheel ---
    hub = mathutils.Vector((drv_x, 1.14, 1.20))
    dash_exit = mathutils.Vector((drv_x, 1.42, 0.98))
    axis = (dash_exit - hub).normalized()      # wheel plane normal
    ref = mathutils.Vector((0.0, 0.0, 1.0))
    if abs(axis.dot(ref)) > 0.90:
        ref = mathutils.Vector((0.0, 1.0, 0.0))
    u_ax = axis.cross(ref).normalized()
    v_ax = axis.cross(u_ax).normalized()

    obj_sw, me_sw = _create_mesh_obj("Cab_SteeringWheel", col, root)
    bm_sw = bmesh.new()

    rim_r = 0.185
    # Rim
    _add_ring(bm_sw, hub, axis, rim_r, 0.022, segments=14)
    _mark_faces(bm_sw, 0, 0)
    n = len(bm_sw.faces)

    # Three spokes and the hub cap
    for deg in (90.0, 210.0, 330.0):
        th = math.radians(deg)
        direction = u_ax * math.cos(th) + v_ax * math.sin(th)
        tip = hub + direction * (rim_r - 0.010)
        add_oriented_box(bm_sw, tuple(hub), tuple(tip), 0.040, 0.018, up_hint=axis)
    add_oriented_box(bm_sw, tuple(hub - axis * 0.028), tuple(hub + axis * 0.046), 0.105, 0.105, up_hint=u_ax)
    # Horn button
    add_oriented_box(bm_sw, tuple(hub - axis * 0.040), tuple(hub - axis * 0.030), 0.070, 0.070, up_hint=u_ax)
    _mark_faces(bm_sw, n, 1)
    n = len(bm_sw.faces)

    # Column shroud and turn-signal stalk
    add_oriented_box(bm_sw, tuple(dash_exit), tuple(hub + axis * 0.050), 0.078, 0.078, up_hint=u_ax)
    _mark_faces(bm_sw, n, 0)
    n = len(bm_sw.faces)
    add_oriented_box(bm_sw, (drv_x - 0.045, 1.235, 1.135), (drv_x - 0.245, 1.185, 1.155), 0.018, 0.018)
    _mark_faces(bm_sw, n, 1)

    bm_sw.normal_update()
    bm_sw.to_mesh(me_sw)
    bm_sw.free()
    me_sw.materials.append(mats["plastic"])   # 0 rim, column shroud
    me_sw.materials.append(mats["liner"])     # 1 ivory spokes, hub, stalk

    # --- Pedals ---
    obj_pd, me_pd = _create_mesh_obj("Cab_Pedals", col, root)
    bm_pd = bmesh.new()
    pedals = [
        ((drv_x + 0.15, 1.545, floor_top + 0.02), (drv_x + 0.15, 1.470, floor_top + 0.17), 0.075, 0.020),  # throttle
        ((drv_x - 0.02, 1.560, floor_top + 0.05), (drv_x - 0.02, 1.480, floor_top + 0.23), 0.105, 0.025),  # brake
        ((drv_x - 0.20, 1.560, floor_top + 0.05), (drv_x - 0.20, 1.480, floor_top + 0.23), 0.095, 0.025),  # clutch
    ]
    for p0, p1, pw, pt in pedals:
        add_oriented_box(bm_pd, p0, p1, pw, pt)
    bm_pd.normal_update()
    bm_pd.to_mesh(me_pd)
    bm_pd.free()
    me_pd.materials.append(mats["bumper"])

    # --- Floor shifter and handbrake ---
    obj_ct, me_ct = _create_mesh_obj("Cab_Controls", col, root)
    bm_ct = bmesh.new()
    shift_base = (drv_x + 0.34, 1.16, floor_top + 0.01)
    _add_cube(bm_ct, size=(0.16, 0.16, 0.05), pos=(shift_base[0], shift_base[1], floor_top + 0.025))
    _mark_faces(bm_ct, 0, 0)
    n = len(bm_ct.faces)
    add_oriented_box(bm_ct, shift_base, (drv_x + 0.30, 1.24, floor_top + 0.44), 0.026, 0.026)
    _mark_faces(bm_ct, n, 1)
    n = len(bm_ct.faces)
    _add_cube(bm_ct, size=(0.075, 0.075, 0.070), pos=(drv_x + 0.30, 1.245, floor_top + 0.48))
    # Handbrake, driver's right hand
    add_oriented_box(bm_ct, (drv_x + 0.22, 1.02, floor_top + 0.06), (drv_x + 0.20, 1.20, floor_top + 0.30), 0.036, 0.036)
    _mark_faces(bm_ct, n, 0)
    bm_ct.normal_update()
    bm_ct.to_mesh(me_ct)
    bm_ct.free()
    me_ct.materials.append(mats["bumper"])    # 0 boot, grips
    me_ct.materials.append(mats["chrome"])    # 1 levers

    # --- Seats (Low-poly leather bucket seats) ---
    def _build_bucket_seat_bm(bm, sx, cy, cz, is_driver, scale=0.976):
        def add_v(x, y, z):
            return bm.verts.new((sx + x * scale, cy + y * scale, cz + z * scale))

        def add_box(pos, size, mat_idx):
            px, py, pz = pos
            sx_b, sy_b, sz_b = size
            hx, hy, hz = sx_b*0.5, sy_b*0.5, sz_b*0.5
            v = [
                add_v(px - hx, py - hy, pz - hz),
                add_v(px + hx, py - hy, pz - hz),
                add_v(px + hx, py + hy, pz - hz),
                add_v(px - hx, py + hy, pz - hz),
                add_v(px - hx, py - hy, pz + hz),
                add_v(px + hx, py - hy, pz + hz),
                add_v(px + hx, py + hy, pz + hz),
                add_v(px - hx, py + hy, pz + hz),
            ]
            faces = [
                bm.faces.new((v[3], v[2], v[1], v[0])),
                bm.faces.new((v[4], v[5], v[6], v[7])),
                bm.faces.new((v[0], v[1], v[5], v[4])),
                bm.faces.new((v[2], v[3], v[7], v[6])),
                bm.faces.new((v[1], v[2], v[6], v[5])),
                bm.faces.new((v[3], v[0], v[4], v[7])),
            ]
            for f in faces:
                f.material_index = mat_idx
            return faces

        # 1. BASE RAILS & PEDESTAL (Dark trim - 1)
        for rx in (-0.17, 0.17):
            add_box((rx, 0.05, 0.02), (0.045, 0.58, 0.035), 1)
        add_box((0.0, 0.03, 0.08), (0.38, 0.48, 0.09), 1)
        add_box((0.0, 0.05, 0.13), (0.50, 0.56, 0.05), 1)

        # 2. CUSHION (SQUAB) - Leather (0)
        xs = [-0.27, -0.21, -0.12, 0.0, 0.12, 0.21, 0.27]
        ys = [-0.22, -0.06, 0.12, 0.14, 0.28, 0.35, 0.38]
        cushion_z = [
            [0.17, 0.23, 0.20, 0.19, 0.20, 0.23, 0.17],
            [0.18, 0.27, 0.23, 0.21, 0.23, 0.27, 0.18],
            [0.18, 0.265, 0.215, 0.198, 0.215, 0.265, 0.18],
            [0.18, 0.27, 0.238, 0.222, 0.238, 0.27, 0.18],
            [0.17, 0.265, 0.245, 0.232, 0.245, 0.265, 0.17],
            [0.15, 0.21, 0.195, 0.190, 0.195, 0.21, 0.15],
            [0.13, 0.14, 0.14, 0.14, 0.14, 0.14, 0.13]
        ]
        cushion_grid = []
        for r in range(7):
            row_verts = []
            for c in range(7):
                v = add_v(xs[c], ys[r], cushion_z[r][c])
                row_verts.append(v)
            cushion_grid.append(row_verts)

        for r in range(6):
            for c in range(6):
                f = bm.faces.new((cushion_grid[r][c], cushion_grid[r][c+1], cushion_grid[r+1][c+1], cushion_grid[r+1][c]))
                f.material_index = 0
                f.smooth = True

        for r in range(6):
            f = bm.faces.new((cushion_grid[r][0], add_v(-0.27, ys[r], 0.13), add_v(-0.27, ys[r+1], 0.13), cushion_grid[r+1][0]))
            f.material_index = 0
            f.smooth = True

        for r in range(6):
            f = bm.faces.new((cushion_grid[r][6], cushion_grid[r+1][6], add_v(0.27, ys[r+1], 0.13), add_v(0.27, ys[r], 0.13)))
            f.material_index = 0
            f.smooth = True

        for c in range(6):
            f = bm.faces.new((cushion_grid[6][c], cushion_grid[6][c+1], add_v(xs[c+1], ys[6], 0.11), add_v(xs[c], ys[6], 0.11)))
            f.material_index = 0
            f.smooth = True

        # 3. BACKREST - Leather (0)
        theta = 0.19
        sin_t, cos_t = math.sin(theta), math.cos(theta)
        fwd_y, fwd_z = cos_t, sin_t
        up_y, up_z = -sin_t, cos_t
        b_y0 = -0.16
        b_z0 = 0.22

        ts = [0.00, 0.14, 0.27, 0.30, 0.44, 0.54, 0.62, 0.68]
        back_grid, back_rear_grid = [], []

        for r, t in enumerate(ts):
            if t <= 0.40:
                w_scale, shoulder_drop = 1.0, 0.0
            elif t <= 0.54:
                w_scale, shoulder_drop = 0.95, 0.005
            elif t <= 0.62:
                w_scale, shoulder_drop = 0.88, 0.020
            else:
                w_scale, shoulder_drop = 0.78, 0.045

            b_xs = [x * w_scale for x in [-0.25, -0.20, -0.11, 0.0, 0.11, 0.20, 0.25]]
            row_f, row_b = [], []
            for c in range(7):
                cur_drop = shoulder_drop * ((abs(b_xs[c]) / 0.25)**2)
                cy_t = b_y0 + up_y * (t - cur_drop)
                cz_t = b_z0 + up_z * (t - cur_drop)

                if c in (0, 6):
                    fwd_dist = 0.040
                elif c in (1, 5):
                    fwd_dist = 0.088 if t < 0.55 else 0.050
                elif c in (2, 4):
                    fwd_dist = 0.026
                else:
                    fwd_dist = 0.022

                if r == 2 and c in (2, 3, 4):
                    fwd_dist -= 0.022
                elif r == 3 and c in (2, 3, 4):
                    fwd_dist += 0.004

                row_f.append(add_v(b_xs[c], cy_t + fwd_y * fwd_dist, cz_t + fwd_z * fwd_dist))
                rear_dist = -0.090 if c in (1, 2, 3, 4, 5) else -0.060
                row_b.append(add_v(b_xs[c], cy_t + fwd_y * rear_dist, cz_t + fwd_z * rear_dist))

            back_grid.append(row_f)
            back_rear_grid.append(row_b)

        for r in range(7):
            for c in range(6):
                f = bm.faces.new((back_grid[r][c], back_grid[r][c+1], back_grid[r+1][c+1], back_grid[r+1][c]))
                f.material_index = 0
                f.smooth = True

        for r in range(7):
            for c in range(6):
                f = bm.faces.new((back_rear_grid[r][c], back_rear_grid[r+1][c], back_rear_grid[r+1][c+1], back_rear_grid[r][c+1]))
                f.material_index = 0
                f.smooth = True

        for r in range(7):
            f = bm.faces.new((back_grid[r][0], back_rear_grid[r][0], back_rear_grid[r+1][0], back_grid[r+1][0]))
            f.material_index = 0
            f.smooth = True

        for r in range(7):
            f = bm.faces.new((back_grid[r][6], back_grid[r+1][6], back_rear_grid[r+1][6], back_rear_grid[r][6]))
            f.material_index = 0
            f.smooth = True

        for c in range(6):
            f = bm.faces.new((back_grid[7][c], back_grid[7][c+1], back_rear_grid[7][c+1], back_rear_grid[7][c]))
            f.material_index = 0
            f.smooth = True

        # 4. HEADREST (Chrome posts 3, Leather cushion 0)
        t_top = ts[-1]
        t_hr_base = 0.74
        for post_x in (-0.07, 0.07):
            p0_y = b_y0 + up_y * (t_top - 0.03)
            p0_z = b_z0 + up_z * (t_top - 0.03)
            p1_y = b_y0 + up_y * t_hr_base
            p1_z = b_z0 + up_z * t_hr_base
            r_post = 0.009
            ring0, ring1 = [], []
            for i in range(6):
                ang = i * (2.0 * math.pi / 6.0)
                ring0.append(add_v(post_x + r_post * math.cos(ang), p0_y + r_post * math.sin(ang) * fwd_y, p0_z + r_post * math.sin(ang) * fwd_z))
                ring1.append(add_v(post_x + r_post * math.cos(ang), p1_y + r_post * math.sin(ang) * fwd_y, p1_z + r_post * math.sin(ang) * fwd_z))
            for i in range(6):
                j = (i + 1) % 6
                f = bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i]))
                f.material_index = 3
                f.smooth = True

        hr_ts = [0.73, 0.76, 0.83, 0.88, 0.91]
        hr_widths = [0.22, 0.27, 0.27, 0.24, 0.17]
        hr_depths = [0.10, 0.14, 0.14, 0.12, 0.06]
        hr_rings = []
        for r_idx in range(len(hr_ts)):
            ht, hw, hd = hr_ts[r_idx], hr_widths[r_idx] * 0.5, hr_depths[r_idx] * 0.5
            h_cy, h_cz = b_y0 + up_y * ht, b_z0 + up_z * ht
            oct_pts = [
                (-hw * 0.65, hd), (hw * 0.65, hd),
                (hw, hd * 0.5), (hw, -hd * 0.5),
                (hw * 0.65, -hd), (-hw * 0.65, -hd),
                (-hw, -hd * 0.5), (-hw, hd * 0.5)
            ]
            hr_rings.append([add_v(ox, h_cy + fwd_y * of, h_cz + fwd_z * of) for ox, of in oct_pts])

        for r_idx in range(len(hr_rings) - 1):
            r0, r1 = hr_rings[r_idx], hr_rings[r_idx + 1]
            for i in range(8):
                j = (i + 1) % 8
                f = bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
                f.material_index = 0
                f.smooth = True

        f_bot = bm.faces.new(list(reversed(hr_rings[0])))
        f_bot.material_index = 0
        f_bot.smooth = True
        f_top = bm.faces.new(hr_rings[-1])
        f_top.material_index = 0
        f_top.smooth = True

        # 5. RECLINER KNOB (Trim 1)
        outboard_x = -0.285 if is_driver else 0.285
        hinge_y, hinge_z = -0.15, 0.22
        knob_r, knob_thick = 0.040, 0.020
        knob_sign = -1.0 if is_driver else 1.0

        k_inner, k_outer = [], []
        for i in range(8):
            ang = i * (2.0 * math.pi / 8.0)
            k_inner.append(add_v(outboard_x, hinge_y + knob_r * math.cos(ang), hinge_z + knob_r * math.sin(ang)))
            k_outer.append(add_v(outboard_x + knob_sign * knob_thick, hinge_y + knob_r * math.cos(ang), hinge_z + knob_r * math.sin(ang)))

        for i in range(8):
            j = (i + 1) % 8
            if is_driver:
                f = bm.faces.new((k_inner[i], k_inner[j], k_outer[j], k_outer[i]))
            else:
                f = bm.faces.new((k_inner[j], k_inner[i], k_outer[i], k_outer[j]))
            f.material_index = 1
            f.smooth = True

        f_kcap = bm.faces.new(k_outer if not is_driver else list(reversed(k_outer)))
        f_kcap.material_index = 1
        add_box((outboard_x + knob_sign * 0.010, hinge_y + 0.05, hinge_z + 0.01), (0.016, 0.065, 0.022), 1)

        # 6. SEATBELT BUCKLE (Trim 1, Red 2)
        inboard_x = 0.265 if is_driver else -0.265
        add_box((inboard_x, -0.12, 0.16), (0.015, 0.035, 0.14), 1)
        add_box((inboard_x, -0.04, 0.26), (0.038, 0.032, 0.060), 1)
        add_box((inboard_x, -0.04, 0.291), (0.028, 0.022, 0.006), 2)

        # 7. UV MAPPING
        bm.normal_update()
        uv_layer = bm.loops.layers.uv.verify()
        scale_uv = 4.0
        for f in bm.faces:
            n = f.normal
            ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            for l in f.loops:
                p = l.vert.co
                if az > ax and az > ay:
                    u = (p.x - sx) * scale_uv
                    v = (p.y - cy) * scale_uv
                elif ax > ay:
                    u = (p.y - cy) * scale_uv
                    v = (p.z - cz) * scale_uv
                else:
                    u = (p.x - sx) * scale_uv
                    v = (p.z - cz) * scale_uv
                l[uv_layer].uv = (u, v)

    for s_name, sx in [("Driver", drv_x), ("Passenger", pas_x)]:
        obj_st, me_st = _create_mesh_obj(f"Cab_Seat_{s_name}", col, root)
        bm_st = bmesh.new()
        _build_bucket_seat_bm(bm_st, sx, 0.856, floor_top, is_driver=(s_name == "Driver"))
        bm_st.normal_update()
        bm_st.to_mesh(me_st)
        bm_st.free()
        me_st.materials.append(mats["leather"])    # 0
        me_st.materials.append(mats["seat_trim"])  # 1
        me_st.materials.append(mats["seat_red"])   # 2
        me_st.materials.append(mats["chrome"])     # 3

    # --- Cab door trim panels (also closes off the body backfaces) ---
    for d_name, dx in [("L", -card_x), ("R", card_x)]:
        obj_dc, me_dc = _create_mesh_obj(f"Cab_DoorCard_{d_name}", col, root)
        bm_dc = bmesh.new()
        inward = -1.0 if dx > 0 else 1.0

        _add_cube(bm_dc, size=(0.030, 0.72, 0.84), pos=(dx, 0.98, 0.95))
        _mark_faces(bm_dc, 0, 0)
        n = len(bm_dc.faces)

        # Armrest, pull handle and window crank
        _add_cube(bm_dc, size=(0.09, 0.40, 0.07), pos=(dx + inward * 0.055, 1.00, 1.20))
        _mark_faces(bm_dc, n, 1)
        n = len(bm_dc.faces)
        _add_cube(bm_dc, size=(0.05, 0.13, 0.032), pos=(dx + inward * 0.040, 1.24, 1.31))
        _add_cylinder(bm_dc, radius=0.030, depth=0.030, pos=(dx + inward * 0.035, 1.10, 1.05), axis='X', segments=8)
        _add_cube(bm_dc, size=(0.030, 0.075, 0.028), pos=(dx + inward * 0.055, 1.10, 1.015))
        _mark_faces(bm_dc, n, 1)

        bm_dc.normal_update()
        bm_dc.to_mesh(me_dc)
        bm_dc.free()
        me_dc.materials.append(mats["vinyl"])     # 0 panel
        me_dc.materials.append(mats["chrome"])    # 1 hardware

    # --- Headliner, sun visors and mirror ---
    # The headliner follows the roof instead of hanging under it as a board:
    # a crown panel, a chamfer down each side and a short return that tucks
    # behind the top rail of the door window, so no body back face is left on
    # show between the roof and the windows.  Front edge stops at y = 1.02;
    # the windshield rake puts the glass at y = 1.04 by the crown height.
    obj_hl, me_hl = _create_mesh_obj("Cab_Headliner", col, root)
    bm_hl = bmesh.new()
    liner_outer = [(1.070, 2.350), (1.040, 2.380), (0.895, 2.478), (0.0, 2.484)]
    liner_inner = [(1.040, 2.350), (1.012, 2.372), (0.890, 2.448), (0.0, 2.454)]
    section = ([(-x, z) for x, z in liner_outer[:-1]] + [liner_outer[-1]]
               + [(x, z) for x, z in reversed(liner_outer[:-1])]
               + [(x, z) for x, z in liner_inner[:-1]] + [liner_inner[-1]]
               + [(-x, z) for x, z in reversed(liner_inner[:-1])])
    _add_prism(bm_hl, section, Y_BULKHEAD - 0.01, 1.02)
    bmesh.ops.recalc_face_normals(bm_hl, faces=bm_hl.faces)

    # Sun visors, stowed flat against the header on the windshield rake rather
    # than lying horizontally out into the cab.
    for visor_x in (-0.50, 0.50):
        add_oriented_box(bm_hl, (visor_x, 1.028, 2.415), (visor_x, 1.083, 2.314), 0.44, 0.018)

    bm_hl.normal_update()
    bm_hl.to_mesh(me_hl)
    bm_hl.free()
    me_hl.materials.append(mats["liner"])

    obj_rm, me_rm = _create_mesh_obj("Cab_RearviewMirror", col, root)
    bm_rm = bmesh.new()
    _add_cube(bm_rm, size=(0.24, 0.045, 0.09), pos=(0.0, 1.135, 2.175))
    add_oriented_box(bm_rm, (0.0, 1.105, 2.270), (0.0, 1.130, 2.205), 0.030, 0.030)
    _mark_faces(bm_rm, 0, 0)
    n = len(bm_rm.faces)
    _add_cube(bm_rm, size=(0.21, 0.010, 0.07), pos=(0.0, 1.109, 2.175))
    _mark_faces(bm_rm, n, 1)
    bm_rm.normal_update()
    bm_rm.to_mesh(me_rm)
    bm_rm.free()
    me_rm.materials.append(mats["bumper"])
    me_rm.materials.append(mats["chrome"])

    # --- Cab light ---
    cab_light = bpy.data.lights.get("Cab_Interior_Light") or bpy.data.lights.new("Cab_Interior_Light", 'POINT')
    cab_l_obj = bpy.data.objects.get("Cab_Interior_Light") or bpy.data.objects.new("Cab_Interior_Light", cab_light)
    if cab_l_obj.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(cab_l_obj)
    cab_light.energy = 45.0
    cab_light.color = (1.0, 0.95, 0.90)
    cab_l_obj.location = (0.0, 1.15, 1.95)
    cab_l_obj.parent = root


def _build_cargo_liner(root, col, mats):
    """Inward-facing panel shell for the cargo bay.

    The exterior body is a single-sided skin, so without this the cargo bay is
    made of back faces and reads as see-through under back-face culling.

    The lower side walls carry the rear wheel arch as a cut-out.  Without it the
    lining runs straight across the opening, 25 mm inside the fender, and its
    blue interior sheet shows from outside between the tyre and the arch.
    """
    y_front = Y_BULKHEAD - 0.01
    y_rear = -2.68

    obj, me = _create_mesh_obj("Lobby_Liner", col, root)
    bm = bmesh.new()

    # Beltline and up: a plain extrusion, well clear of the arches.
    upper = [(x, z) for x, z in _liner_section() if z >= BELT_Z]
    ring_f = [bm.verts.new((x, y_front, z)) for x, z in upper]
    ring_r = [bm.verts.new((x, y_rear, z)) for x, z in upper]
    for i in range(len(upper) - 1):
        bm.faces.new((ring_f[i], ring_f[i + 1], ring_r[i + 1], ring_r[i]))

    # Below the beltline: side walls whose bottom edge climbs over the arch.
    hw, z_floor = LINER_PROFILE[0]
    stations = ([(y_rear, z_floor)]
                + [(Y_REAR_AXLE + dy, max(z_floor, z)) for dy, z in _arch_points()]
                + [(y_front, z_floor)])
    for sign in (-1.0, 1.0):
        bottom = [bm.verts.new((sign * hw, y, z)) for y, z in stations]
        top = [bm.verts.new((sign * hw, y, BELT_Z)) for y, _ in stations]
        for i in range(len(stations) - 1):
            bm.faces.new((bottom[i], top[i], top[i + 1], bottom[i + 1]))

    _face_inward(bm, (0.0, (y_front + y_rear) * 0.5, 1.45))
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mats["texture"])

    uv_layer = me.uv_layers.new(name="UVMap")
    me.uv_layers.active = uv_layer
    for poly in me.polygons:
        for loop_idx in poly.loop_indices:
            v = me.vertices[me.loops[loop_idx].vertex_index].co
            # Ribbed blue sheet-metal panel of the atlas, ribs running lengthwise
            u = 0.52 + ((v.y + 2.70) / 3.15) * 0.46
            v_coord = 0.52 + ((v.z - FLOOR_Z) / (ROOF_Z - FLOOR_Z)) * 0.21
            uv_layer.data[loop_idx].uv = (min(max(u, 0.52), 0.98), min(max(v_coord, 0.52), 0.73))


def _build_lobby_interior(root, col, mats):
    floor_top = FLOOR_Z + 0.04     # 0.49 - walking surface of the cargo bay

    # --- Floor (diamond plate) ---
    obj_lf, me_lf = _create_mesh_obj("Lobby_Floor", col, root)
    bm_lf = bmesh.new()
    _add_cube(bm_lf, size=((HALF_WIDTH - 0.06) * 2, 3.10, 0.04), pos=(0.0, -1.10, FLOOR_Z + 0.02))
    bm_lf.normal_update()
    bm_lf.to_mesh(me_lf)
    bm_lf.free()
    me_lf.materials.append(mats["texture"])

    uv_layer = me_lf.uv_layers.new(name="UVMap")
    me_lf.uv_layers.active = uv_layer
    for poly in me_lf.polygons:
        for loop_idx in poly.loop_indices:
            v = me_lf.vertices[me_lf.loops[loop_idx].vertex_index].co
            u = 0.02 + ((v.x + HALF_WIDTH) / (2 * HALF_WIDTH)) * 0.22
            v_coord = 0.27 + ((v.y + 2.70) / 3.15) * 0.22
            uv_layer.data[loop_idx].uv = (min(max(u, 0.0), 0.25), min(max(v_coord, 0.25), 0.50))

    # --- Bulkhead: closes the cargo bay off from the cab, glazed hatch only ---
    obj_bh, me_bh = _create_mesh_obj("Lobby_Bulkhead", col, root)
    bm_bh = bmesh.new()
    y0 = Y_BULKHEAD - BULKHEAD_T * 0.5
    y1 = Y_BULKHEAD + BULKHEAD_T * 0.5
    wx, wz0, wz1 = BULKHEAD_WIN_HW, BULKHEAD_WIN_Z0, BULKHEAD_WIN_Z1
    hw_low = _liner_hw(wz0)
    hw_high = _liner_hw(wz1)
    floor_z = LINER_PROFILE[0][1]

    # Below the window: full width up to the beltline, then the tumblehome
    _add_prism(bm_bh, [
        (-1.225, floor_z), (1.225, floor_z), (1.225, BELT_Z),
        (hw_low, wz0), (-hw_low, wz0), (-1.225, BELT_Z),
    ], y0, y1)
    # Above the window: up the tumblehome, over the roof chamfer and the crown
    _add_prism(bm_bh, [
        (-hw_high, wz1), (hw_high, wz1),
        (LINER_PROFILE[2][0], LINER_PROFILE[2][1]),
        (LINER_PROFILE[3][0], LINER_PROFILE[3][1]),
        (LINER_PROFILE[4][0], LINER_PROFILE[4][1]),
        (-LINER_PROFILE[3][0], LINER_PROFILE[3][1]),
        (-LINER_PROFILE[2][0], LINER_PROFILE[2][1]),
    ], y0, y1)
    # Either side of the window
    _add_prism(bm_bh, [(-hw_low, wz0), (-wx, wz0), (-wx, wz1), (-hw_high, wz1)], y0, y1)
    _add_prism(bm_bh, [(wx, wz0), (hw_low, wz0), (hw_high, wz1), (wx, wz1)], y0, y1)
    bmesh.ops.recalc_face_normals(bm_bh, faces=bm_bh.faces)
    bm_bh.to_mesh(me_bh)
    bm_bh.free()
    me_bh.materials.append(mats["texture"])

    uv_layer = me_bh.uv_layers.new(name="UVMap")
    me_bh.uv_layers.active = uv_layer
    for poly in me_bh.polygons:
        for loop_idx in poly.loop_indices:
            v = me_bh.vertices[me_bh.loops[loop_idx].vertex_index].co
            u = 0.27 + ((v.x + HALF_WIDTH) / (2 * HALF_WIDTH)) * 0.22
            v_coord = 0.26 + ((v.z - FLOOR_Z) / (ROOF_Z - FLOOR_Z)) * 0.22
            uv_layer.data[loop_idx].uv = (min(max(u, 0.25), 0.50), min(max(v_coord, 0.25), 0.50))

    # --- Glazed hatch in the bulkhead ---
    obj_bw, me_bw = _create_mesh_obj("Lobby_Bulkhead_Window", col, root)
    bm_bw = bmesh.new()
    _add_cube(bm_bw, size=(wx * 2 + 0.030, 0.012, wz1 - wz0 + 0.030),
              pos=(0.0, Y_BULKHEAD, (wz0 + wz1) * 0.5))
    _mark_faces(bm_bw, 0, 0)
    n = len(bm_bw.faces)
    _add_aperture_ring(bm_bw, ax0=-wx, ax1=wx, az0=wz0, az1=wz1,
                       y=Y_BULKHEAD, thickness=BULKHEAD_T + 0.008, band=0.028)
    for y_seal in (y0 - 0.006, y1 + 0.006):
        _add_cube(bm_bw, size=(wx * 2 + 0.060, 0.012, 0.026), pos=(0.0, y_seal, wz1 + 0.013))
        _add_cube(bm_bw, size=(wx * 2 + 0.060, 0.012, 0.026), pos=(0.0, y_seal, wz0 - 0.013))
        _add_cube(bm_bw, size=(0.026, 0.012, wz1 - wz0 + 0.026), pos=(-wx - 0.013, y_seal, (wz0 + wz1) * 0.5))
        _add_cube(bm_bw, size=(0.026, 0.012, wz1 - wz0 + 0.026), pos=(wx + 0.013, y_seal, (wz0 + wz1) * 0.5))
    _mark_faces(bm_bw, n, 1)
    bm_bw.normal_update()
    bm_bw.to_mesh(me_bw)
    bm_bw.free()
    me_bw.materials.append(mats["glass"])     # 0 pane
    me_bw.materials.append(mats["bumper"])    # 1 frame and weatherstrip

    # --- Structural ribs, now following the tumblehome of the lining ---
    obj_rib, me_rib = _create_mesh_obj("Lobby_Ribs", col, root)
    bm_rib = bmesh.new()
    rib_half_depth = 0.025          # Half of the 0.05 rib depth, in Y
    for ry in [-0.20, -0.90, -1.60, -2.30]:
        # A rib standing over a wheel tub would run straight through it and show
        # up inside the arch, so it starts on top of the tub instead.
        z_tub = _arch_top_z(ry - rib_half_depth, ry + rib_half_depth)
        rib_bottom = floor_top if z_tub is None else max(floor_top, z_tub + 0.020)
        for sgn in (-1.0, 1.0):
            add_oriented_box(bm_rib, (sgn * 1.205, ry, rib_bottom), (sgn * 1.205, ry, BELT_Z), 0.030, 0.05)
            add_oriented_box(bm_rib, (sgn * 1.205, ry, BELT_Z), (sgn * 1.040, ry, SHOULDER_Z), 0.030, 0.05)
        _add_cube(bm_rib, size=(1.84, 0.05, 0.035), pos=(0.0, ry, 2.470))
    bm_rib.normal_update()
    bm_rib.to_mesh(me_rib)
    bm_rib.free()
    me_rib.materials.append(mats["bumper"])

    # --- Ceiling lights ---
    obj_cl, me_cl = _create_mesh_obj("Lobby_CeilingLights", col, root)
    bm_cl = bmesh.new()
    for ly in [-0.55, -1.65]:
        _add_cube(bm_cl, size=(0.28, 0.65, 0.04), pos=(0.0, ly, 2.455))
    bm_cl.normal_update()
    bm_cl.to_mesh(me_cl)
    bm_cl.free()
    me_cl.materials.append(mats["emit_warm"])

    # --- Floor lashing rings ---
    obj_lr, me_lr = _create_mesh_obj("Lobby_LashingRings", col, root)
    bm_lr = bmesh.new()
    for rx in (-1.12, 1.12):
        for ry in (-0.30, -1.30, -2.40):
            _add_cube(bm_lr, size=(0.09, 0.09, 0.014), pos=(rx, ry, floor_top + 0.007))
            _add_ring(bm_lr, (rx, ry, floor_top + 0.035), (0.0, 1.0, 0.0), 0.032, 0.008, segments=8)
    bm_lr.normal_update()
    bm_lr.to_mesh(me_lr)
    bm_lr.free()
    me_lr.materials.append(mats["chrome"])


def _slab_profile(p0, p1, thickness, outward_sign):
    """Parallelogram slab of *thickness* offset outward from segment p0-p1 (XZ)."""
    (x0, z0), (x1, z1) = p0, p1
    dx, dz = x1 - x0, z1 - z0
    length = math.hypot(dx, dz)
    nx, nz = dz / length, -dx / length
    if nx * outward_sign < 0.0:
        nx, nz = -nx, -nz
    return [
        (x0, z0), (x1, z1),
        (x1 + nx * thickness, z1 + nz * thickness),
        (x0 + nx * thickness, z0 + nz * thickness),
    ]


def _build_lobby_fixtures(root, col, mats):
    """Loose cargo-bay furniture.

    Stripped out of the van by hand; kept here behind LOBBY_FIXTURES so a
    rebuild does not put it back, and so the geometry is not lost.
    """
    floor_top = FLOOR_Z + 0.04

    # --- Handholds: ceiling rail with straps, wall rail, two stanchions ---
    obj_gr, me_gr = _create_mesh_obj("Lobby_GrabRail", col, root)
    bm_gr = bmesh.new()
    _add_cylinder(bm_gr, radius=0.018, depth=2.40, pos=(0.0, -1.15, 2.380), axis='Y', segments=8)
    for y_drop in [-0.15, -1.15, -2.15]:
        _add_cylinder(bm_gr, radius=0.015, depth=0.09, pos=(0.0, y_drop, 2.425), axis='Z', segments=6)
    # Wall rail above the crew bench, on brackets
    rail_x = _liner_hw(1.55) - 0.060
    _add_cylinder(bm_gr, radius=0.018, depth=0.75, pos=(rail_x, -2.22, 1.55), axis='Y', segments=8)
    for bracket_y in (-2.55, -1.89):
        add_oriented_box(bm_gr, (_liner_hw(1.55) - 0.005, bracket_y, 1.55), (rail_x, bracket_y, 1.55), 0.030, 0.030)
    # Vertical stanchions, staggered so neither narrows the walkway
    for pole_x, pole_y in ((-0.42, -1.80), (0.42, -1.00)):
        _add_cylinder(bm_gr, radius=0.022, depth=2.45 - floor_top, pos=(pole_x, pole_y, (floor_top + 2.45) * 0.5), axis='Z', segments=8)
        _add_cube(bm_gr, size=(0.09, 0.09, 0.02), pos=(pole_x, pole_y, floor_top + 0.01))
    _mark_faces(bm_gr, 0, 0)
    n = len(bm_gr.faces)
    # Hanging straps off the ceiling rail
    for strap_y in (-0.55, -1.35, -2.15):
        add_oriented_box(bm_gr, (0.0, strap_y, 2.360), (0.0, strap_y, 2.075), 0.045, 0.012)
        _add_ring(bm_gr, (0.0, strap_y, 2.010), (1.0, 0.0, 0.0), 0.058, 0.012, segments=8)
    _mark_faces(bm_gr, n, 1)
    bm_gr.normal_update()
    bm_gr.to_mesh(me_gr)
    bm_gr.free()
    me_gr.materials.append(mats["chrome"])    # 0 rails and poles
    me_gr.materials.append(mats["bumper"])    # 1 straps

    # --- Workbench, with a fiddle rail so tools stay put in motion ---
    obj_wb, me_wb = _create_mesh_obj("Lobby_Workbench", col, root)
    bm_wb = bmesh.new()
    top_x = -SHOULDER_HW + 0.35
    top_z = FLOOR_Z + 0.85
    _add_cube(bm_wb, size=(0.58, 1.25, 0.06), pos=(top_x, -0.45, top_z))
    for lx in [-SHOULDER_HW + 0.12, -SHOULDER_HW + 0.58]:
        for ly in [-1.00, 0.10]:
            _add_cube(bm_wb, size=(0.05, 0.05, 0.82), pos=(lx, ly, FLOOR_Z + 0.41))
    _add_cube(bm_wb, size=(0.48, 0.52, 0.65), pos=(top_x, -0.65, FLOOR_Z + 0.35))
    _mark_faces(bm_wb, 0, 0)
    n = len(bm_wb.faces)
    _add_cube(bm_wb, size=(0.020, 1.25, 0.045), pos=(top_x + 0.28, -0.45, top_z + 0.05))
    _add_cube(bm_wb, size=(0.58, 0.020, 0.045), pos=(top_x, -1.070, top_z + 0.05))
    _add_cube(bm_wb, size=(0.58, 0.020, 0.045), pos=(top_x, 0.170, top_z + 0.05))
    _mark_faces(bm_wb, n, 1)
    bm_wb.normal_update()
    bm_wb.to_mesh(me_wb)
    bm_wb.free()
    me_wb.materials.append(mats["bumper"])    # 0 frame
    me_wb.materials.append(mats["chrome"])    # 1 fiddle rail

    # --- Retro CRT computer terminal ---
    obj_pc, me_pc = _create_mesh_obj("Lobby_Computer", col, root)
    bm_pc = bmesh.new()
    _add_cube(bm_pc, size=(0.38, 0.34, 0.32), pos=(top_x, -0.30, FLOOR_Z + 0.88 + 0.16))
    _add_cube(bm_pc, size=(0.28, 0.02, 0.22), pos=(top_x, -0.12, FLOOR_Z + 0.88 + 0.16))
    _add_cube(bm_pc, size=(0.32, 0.16, 0.03), pos=(top_x, -0.04, FLOOR_Z + 0.88 + 0.02))
    bm_pc.normal_update()
    bm_pc.to_mesh(me_pc)
    bm_pc.free()
    me_pc.materials.append(mats["texture"])

    uv_layer = me_pc.uv_layers.new(name="UVMap")
    me_pc.uv_layers.active = uv_layer
    for poly in me_pc.polygons:
        for loop_idx in poly.loop_indices:
            v = me_pc.vertices[me_pc.loops[loop_idx].vertex_index].co
            if abs(v.y - (-0.12)) < 0.03:
                u = 0.76 + ((v.x - top_x + 0.14) / 0.28) * 0.22
                v_coord = 0.26 + ((v.z - (FLOOR_Z + 0.88 + 0.05)) / 0.22) * 0.22
                uv_layer.data[loop_idx].uv = (min(max(u, 0.75), 1.0), min(max(v_coord, 0.25), 0.50))
            else:
                uv_layer.data[loop_idx].uv = (0.55, 0.35)

    # --- Notice board ---
    obj_nb, me_nb = _create_mesh_obj("Lobby_NoticeBoard", col, root)
    bm_nb = bmesh.new()
    _add_cube(bm_nb, size=(0.04, 0.85, 0.65), pos=(-_liner_hw(1.93) + 0.04, -1.25, 1.60))
    bm_nb.normal_update()
    bm_nb.to_mesh(me_nb)
    bm_nb.free()
    me_nb.materials.append(mats["texture"])

    uv_layer = me_nb.uv_layers.new(name="UVMap")
    me_nb.uv_layers.active = uv_layer
    for poly in me_nb.polygons:
        for loop_idx in poly.loop_indices:
            v = me_nb.vertices[me_nb.loops[loop_idx].vertex_index].co
            u = 0.02 + ((v.y + 1.25 + 0.425) / 0.85) * 0.22
            v_coord = 0.02 + ((v.z - 1.275) / 0.65) * 0.22
            uv_layer.data[loop_idx].uv = (min(max(u, 0.0), 0.25), min(max(v_coord, 0.0), 0.25))

    # --- Shelving rack with retaining rods and strapped crates ---
    obj_sh, me_sh = _create_mesh_obj("Lobby_Shelving", col, root)
    bm_sh = bmesh.new()
    shelf_x = SHOULDER_HW - 0.28
    shelf_zs = [FLOOR_Z + 0.10, FLOOR_Z + 0.55, FLOOR_Z + 1.05, FLOOR_Z + 1.55]
    for z_shelf in shelf_zs:
        _add_cube(bm_sh, size=(0.45, 1.10, 0.04), pos=(shelf_x, -0.85, z_shelf))
    for px in [shelf_x - 0.20, shelf_x + 0.20]:
        for py in [-1.35, -0.35]:
            _add_cube(bm_sh, size=(0.04, 0.04, 1.65), pos=(px, py, FLOOR_Z + 0.85))
    _add_cube(bm_sh, size=(0.36, 0.40, 0.32), pos=(shelf_x, -0.65, FLOOR_Z + 0.73))
    _add_cube(bm_sh, size=(0.36, 0.42, 0.26), pos=(shelf_x, -0.65, FLOOR_Z + 0.25))
    _mark_faces(bm_sh, 0, 0)
    n = len(bm_sh.faces)
    # Front rods keep the load on the shelf when the van moves
    for z_shelf in shelf_zs:
        _add_cylinder(bm_sh, radius=0.011, depth=1.06, pos=(shelf_x - 0.205, -0.85, z_shelf + 0.10), axis='Y', segments=6)
    _mark_faces(bm_sh, n, 1)
    n = len(bm_sh.faces)
    # Lashing straps over both crates
    for crate_top, crate_w in ((FLOOR_Z + 0.90, 0.38), (FLOOR_Z + 0.39, 0.38)):
        add_oriented_box(bm_sh, (shelf_x - crate_w * 0.5, -0.65, crate_top), (shelf_x + crate_w * 0.5, -0.65, crate_top), 0.055, 0.010)
    _mark_faces(bm_sh, n, 2)
    bm_sh.normal_update()
    bm_sh.to_mesh(me_sh)
    bm_sh.free()
    me_sh.materials.append(mats["bumper"])    # 0 rack and crates
    me_sh.materials.append(mats["chrome"])    # 1 retaining rods
    me_sh.materials.append(mats["vinyl"])     # 2 straps

    # --- Tool rack with a retaining bungee ---
    obj_tr, me_tr = _create_mesh_obj("Lobby_ToolRack", col, root)
    bm_tr = bmesh.new()
    rack_x = -_liner_hw(1.90) + 0.04
    _add_cube(bm_tr, size=(0.03, 0.80, 0.10), pos=(rack_x, -1.95, 1.45))
    _add_cylinder(bm_tr, radius=0.015, depth=1.05, pos=(rack_x + 0.05, -1.75, 1.35), axis='Z', segments=6)
    _add_cylinder(bm_tr, radius=0.018, depth=0.80, pos=(rack_x + 0.05, -2.15, 1.30), axis='Z', segments=6)
    _mark_faces(bm_tr, 0, 0)
    n = len(bm_tr.faces)
    add_oriented_box(bm_tr, (rack_x + 0.09, -1.60, 1.20), (rack_x + 0.09, -2.30, 1.20), 0.030, 0.010)
    _mark_faces(bm_tr, n, 1)
    bm_tr.normal_update()
    bm_tr.to_mesh(me_tr)
    bm_tr.free()
    me_tr.materials.append(mats["bumper"])    # 0 rack and tools
    me_tr.materials.append(mats["vinyl"])     # 1 bungee

    # --- Crew bench: backrest, end restraints and lap belts ---
    obj_cb, me_cb = _create_mesh_obj("Lobby_CrewBench", col, root)
    bm_cb = bmesh.new()
    bench_x = SHOULDER_HW - 0.28
    bench_y = -2.25
    seat_z = FLOOR_Z + 0.45
    _add_cube(bm_cb, size=(0.42, 0.85, 0.06), pos=(bench_x, bench_y, seat_z))
    for bx, by in [(bench_x - 0.16, -1.88), (bench_x + 0.16, -1.88), (bench_x - 0.16, -2.62), (bench_x + 0.16, -2.62)]:
        _add_cube(bm_cb, size=(0.05, 0.05, 0.42), pos=(bx, by, FLOOR_Z + 0.21))
    # End panels stop a crew member sliding off in a corner
    for by in (-1.83, -2.67):
        _add_cube(bm_cb, size=(0.42, 0.05, 0.30), pos=(bench_x, by, seat_z + 0.18))
    _mark_faces(bm_cb, 0, 1)
    n = len(bm_cb.faces)
    # Backrest against the wall
    back_x = _liner_hw(1.20) - 0.12
    _add_cube(bm_cb, size=(0.05, 0.85, 0.46), pos=(back_x, bench_y, seat_z + 0.26))
    for br_y in (-2.60, -1.90):
        add_oriented_box(bm_cb, (back_x + 0.02, br_y, seat_z + 0.42), (_liner_hw(1.40) - 0.005, br_y, seat_z + 0.42), 0.045, 0.030)
    _add_cube(bm_cb, size=(0.40, 0.85, 0.05), pos=(bench_x, bench_y, seat_z + 0.055))
    _mark_faces(bm_cb, n, 0)
    n = len(bm_cb.faces)
    # Three lap belts with buckles
    for belt_y in (-2.50, -2.25, -2.00):
        add_oriented_box(bm_cb, (bench_x - 0.21, belt_y, seat_z + 0.085), (bench_x + 0.21, belt_y, seat_z + 0.085), 0.055, 0.012)
    _mark_faces(bm_cb, n, 2)
    n = len(bm_cb.faces)
    for belt_y in (-2.50, -2.25, -2.00):
        _add_cube(bm_cb, size=(0.075, 0.045, 0.030), pos=(bench_x + 0.04, belt_y, seat_z + 0.100))
    _mark_faces(bm_cb, n, 1)
    bm_cb.normal_update()
    bm_cb.to_mesh(me_cb)
    bm_cb.free()
    me_cb.materials.append(mats["vinyl"])     # 0 cushions
    me_cb.materials.append(mats["bumper"])    # 1 frame and buckles
    me_cb.materials.append(mats["plastic"])   # 2 webbing


def _build_collision(root, col):
    """Convex collision proxies, exported with Godot's -convcolonly suffix.

    Godot turns each of these into a StaticBody3D with a convex shape and hides
    the mesh.  They are deliberately simpler than the visual meshes: a player
    capsule should never collide against the decorated geometry.
    """

    def prism(name, profile_xz, y0, y1, parent=None):
        me = bpy.data.meshes.new(name + "_mesh")
        obj = bpy.data.objects.new(name + "-convcolonly", me)
        col.objects.link(obj)
        obj.parent = parent or root
        bm = bmesh.new()
        _add_prism(bm, profile_xz, y0, y1)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        # Proxies must never show up in a render; the glTF export still picks
        # them up because it is not filtered by visibility.
        obj.hide_render = True
        obj.display_type = 'WIRE'
        return obj

    def box(name, x0, x1, y0, y1, z0, z1, parent=None):
        return prism(name, [(x0, z0), (x1, z0), (x1, z1), (x0, z1)], y0, y1, parent)

    y_front = Y_BULKHEAD
    y_rear = -2.68
    wall_t = 0.08

    # Cargo bay shell
    box("Cargo_Floor", -1.24, 1.24, y_rear, y_front + 0.02, FLOOR_Z - 0.06, FLOOR_Z + 0.04)
    box("Cargo_Ceiling", -0.95, 0.95, y_rear, y_front, 2.495, 2.495 + wall_t)
    for side, sgn in (("L", -1.0), ("R", 1.0)):
        pts = LINER_PROFILE
        prism("Cargo_Wall_%s_Lower" % side,
              _slab_profile((sgn * pts[0][0], pts[0][1]), (sgn * pts[1][0], pts[1][1]), wall_t, sgn),
              y_rear, y_front)
        prism("Cargo_Wall_%s_Tumble" % side,
              _slab_profile((sgn * pts[1][0], pts[1][1]), (sgn * pts[2][0], pts[2][1]), wall_t, sgn),
              y_rear, y_front)
        prism("Cargo_Wall_%s_Chamfer" % side,
              _slab_profile((sgn * pts[2][0], pts[2][1]), (sgn * pts[3][0], pts[3][1]), wall_t, sgn),
              y_rear, y_front)

    # Solid bulkhead: the cab is reachable only through its own doors
    box("Cargo_Bulkhead", -1.24, 1.24, y_front - BULKHEAD_T * 0.5, y_front + BULKHEAD_T * 0.5,
        FLOOR_Z, ROOF_Z)

    # Wheel arches
    for side, sgn in (("L", -1.0), ("R", 1.0)):
        box("Cargo_WheelTub_%s" % side, min(sgn * 0.88, sgn * 1.25), max(sgn * 0.88, sgn * 1.25),
            -1.90, -0.90, FLOOR_Z + 0.04, 0.90)
    if LOBBY_FIXTURES:
        box("Cargo_Workbench", -1.06, -0.42, -1.10, 0.18, FLOOR_Z + 0.04, 1.36)
        box("Cargo_Shelving", 0.55, 1.06, -1.42, -0.28, FLOOR_Z + 0.04, 2.06)
        box("Cargo_Bench", 0.55, 1.06, -2.70, -1.80, FLOOR_Z + 0.04, 1.42)
        for idx, (px, py) in enumerate(((-0.42, -1.80), (0.42, -1.00))):
            box("Cargo_Pole_%d" % idx, px - 0.035, px + 0.035, py - 0.035, py + 0.035, FLOOR_Z + 0.04, 2.40)

    # Cab
    box("Cab_Floor", -1.16, 1.16, 0.45, 1.66, FLOOR_Z, FLOOR_Z + 0.06)
    box("Cab_Dash", -1.16, 1.16, 1.31, 1.66, FLOOR_Z + 0.06, 1.34)
    for s_name, sx in (("Driver", -0.55), ("Passenger", 0.55)):
        box("Cab_Seat_%s" % s_name, sx - 0.28, sx + 0.28, 0.52, 1.19, FLOOR_Z + 0.06, 1.36)

    # Door panels, parented to their hinge pivots so the shape swings with them
    for side_name, sgn in (("L", 1.0), ("R", -1.0)):
        pivot = bpy.data.objects.get("Van_Door_%s" % side_name)
        if pivot is None:
            continue
        obj = box("Van_Door_%s_Panel" % side_name,
                  min(0.0, sgn * X_DOOR_HINGE), max(0.0, sgn * X_DOOR_HINGE),
                  -0.03, 0.03,
                  -(SHOULDER_Z - FLOOR_Z) * 0.5, (SHOULDER_Z - FLOOR_Z) * 0.5,
                  parent=pivot)
        obj.location = (0.0, 0.0, 0.0)


def _setup_lighting(root):
    sun_data = bpy.data.lights.get("Van_Sun") or bpy.data.lights.new("Van_Sun", 'SUN')
    sun_obj = bpy.data.objects.get("Van_Sun") or bpy.data.objects.new("Van_Sun", sun_data)
    if sun_obj.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(sun_obj)
    sun_data.energy = 2.5
    sun_data.color = (1.0, 0.98, 0.94)
    sun_obj.location = (5.0, -5.0, 8.0)
    sun_obj.rotation_euler = (math.radians(45), math.radians(20), math.radians(-30))

    lib_data = bpy.data.lights.get("Lobby_Interior_Light") or bpy.data.lights.new("Lobby_Interior_Light", 'POINT')
    lib_obj = bpy.data.objects.get("Lobby_Interior_Light") or bpy.data.objects.new("Lobby_Interior_Light", lib_data)
    if lib_obj.name not in bpy.context.scene.collection.objects:
        bpy.context.scene.collection.objects.link(lib_obj)
    lib_data.energy = 70.0
    lib_data.color = (1.0, 0.95, 0.88)
    lib_obj.location = (0.0, -1.10, 2.25)
    lib_obj.parent = root




if __name__ == "__main__":
    run()
