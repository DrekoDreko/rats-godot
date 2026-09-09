"""Builds the PS1 Shed Yard scene (`assets/models/shed_yard.glb`) via Blender.

Constructs:
- Corrugated metal shed (galpao) with roll-up garage door, side door, gabled roof.
- Utility pole ("pole") with crossarms, insulators, hanging catenary wires, street lamp.
- Chain-link fence with posts, rails, wire mesh, and open driveway gate.
- Props: red/white, blue, and green oil barrels, wooden work table, ladder with draped blue tarp.
- Muddy ground terrain with puddles and subtle height variation.
- Procedural PS1 pixel-art textures (128x128 / 64x64) packed into materials.
- Camera and preview lighting matching the reference image.
"""

import math
import os
import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix

PROJECT_ROOT = r"c:\Users\Ferrareto\Documents\Lucas\GAMES\rats-godot"
EXPORT_PATH = os.path.join(PROJECT_ROOT, "assets", "models", "shed_yard.glb")
BLEND_SAVE_PATH = os.path.join(PROJECT_ROOT, "models", "shed_yard.blend")
PREVIEW_RENDER_PATH = os.path.join(PROJECT_ROOT, "blender", "_previews", "shed_yard_preview.png")

# --- Procedural Texture Helpers ---

def create_image(name, width, height, generator_fn):
    """Creates a packed Blender image using a numpy RGB(A) generator."""
    existing = bpy.data.images.get(name)
    if existing:
        bpy.data.images.remove(existing)
    
    img = bpy.data.images.new(name, width=width, height=height, alpha=True)
    pixels = generator_fn(width, height)
    img.pixels.foreach_set(pixels.ravel())
    img.pack()
    return img

def create_material(name, img=None, color=(0.8, 0.8, 0.8, 1.0), roughness=0.8, is_emissive=False, emissive_color=(1, 1, 1), is_cutout=False):
    """Creates a Principled BSDF material with the given texture or color."""
    mat = bpy.data.materials.get(name)
    if mat:
        bpy.data.materials.remove(mat)
    
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    nodes.clear()
    
    bsdf = nodes.new(type="ShaderNodeBsdfPrincipled")
    bsdf.location = (0, 0)
    bsdf.inputs["Roughness"].default_value = roughness
    
    if is_emissive:
        bsdf.inputs["Emission Color"].default_value = (*emissive_color, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 5.0
    
    if img:
        tex_node = nodes.new(type="ShaderNodeTexImage")
        tex_node.image = img
        tex_node.interpolation = "Closest"  # Crisp PS1 pixel filtering
        tex_node.location = (-300, 0)
        mat.node_tree.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
        if is_cutout:
            mat.node_tree.links.new(tex_node.outputs["Alpha"], bsdf.inputs["Alpha"])
            if hasattr(mat, "blend_method"):
                mat.blend_method = "CLIP"
    else:
        bsdf.inputs["Base Color"].default_value = color
    
    output = nodes.new(type="ShaderNodeOutputMaterial")
    output.location = (300, 0)
    mat.node_tree.links.new(bsdf.outputs["BSDF"], output.inputs["Surface"])
    
    return mat

# --- Texture Generators (PS1 Style) ---

def gen_corrugated_metal(w, h):
    arr = np.zeros((h, w, 4), dtype=np.float32)
    for y in range(h):
        for x in range(w):
            phase = (x % 8) / 8.0
            rib = math.sin(phase * math.pi * 2) * 0.15
            noise = (math.sin(x * 12.3 + y * 45.6) % 1.0) * 0.08
            grime = (1.0 - (y / h)) * 0.12 if y < h * 0.25 else 0.0
            val = 0.62 + rib + noise - grime
            val = max(0.2, min(0.9, val))
            rust = 0.0
            if (x * 7 + y * 13) % 29 < 2 and y < h * 0.4:
                rust = 0.25
            r = min(1.0, val + rust * 0.3)
            g = max(0.0, val - rust * 0.1)
            b = max(0.0, val - rust * 0.25)
            arr[y, x] = [r, g, b, 1.0]
    return arr

def gen_garage_door(w, h):
    arr = np.zeros((h, w, 4), dtype=np.float32)
    for y in range(h):
        slat = (y % 10) / 10.0
        shade = -0.2 if slat < 0.15 else (0.1 if slat < 0.35 else 0.0)
        grime = 0.15 * (1.0 - y / h)
        for x in range(w):
            edge = 0.15 if (x < 4 or x >= w - 4) else 0.0
            noise = (math.sin(x * 23.4 + y * 7.8) % 1.0) * 0.05
            v = 0.75 + shade - grime - edge + noise
            v = max(0.15, min(0.95, v))
            arr[y, x] = [v, v * 0.95, v * 0.88, 1.0]
    return arr

def gen_blue_tarp(w, h):
    arr = np.zeros((h, w, 4), dtype=np.float32)
    for y in range(h):
        for x in range(w):
            wrinkle = math.sin(x * 0.4 + y * 0.2) * 0.12 + math.sin(x * 0.15 - y * 0.35) * 0.08
            noise = (math.sin(x * 9.1 + y * 19.3) % 1.0) * 0.05
            v = 0.55 + wrinkle + noise
            r = max(0.05, min(0.4, 0.15 * v))
            g = max(0.15, min(0.65, 0.38 * v))
            b = max(0.45, min(1.0, 0.95 * v))
            arr[y, x] = [r, g, b, 1.0]
    return arr

def gen_wood_pole(w, h):
    arr = np.zeros((h, w, 4), dtype=np.float32)
    for y in range(h):
        for x in range(w):
            grain = math.sin(x * 1.5 + math.sin(y * 0.2) * 2.0) * 0.08
            noise = (math.sin(x * 14.2 + y * 51.7) % 1.0) * 0.06
            v = 0.32 + grain + noise
            arr[y, x] = [v * 1.1, v * 0.82, v * 0.55, 1.0]
    return arr

def gen_barrel_red(w, h):
    arr = np.zeros((h, w, 4), dtype=np.float32)
    for y in range(h):
        norm_y = y / float(h)
        is_white = 0.38 <= norm_y <= 0.62
        is_rim = (y in (2, 3, h - 3, h - 4) or 
                  abs(norm_y - 0.33) < 0.02 or 
                  abs(norm_y - 0.67) < 0.02)
        for x in range(w):
            roundness = math.cos((x / w - 0.5) * math.pi) * 0.25
            noise = (math.sin(x * 8.5 + y * 17.1) % 1.0) * 0.06
            if is_rim:
                v = 0.35 + roundness + noise
                arr[y, x] = [v, v, v, 1.0]
            elif is_white:
                v = 0.72 + roundness + noise
                arr[y, x] = [v, v * 0.98, v * 0.92, 1.0]
            else:
                v = 0.55 + roundness + noise
                arr[y, x] = [v * 1.3, v * 0.2, v * 0.15, 1.0]
    return arr

def gen_barrel_blue(w, h):
    arr = np.zeros((h, w, 4), dtype=np.float32)
    for y in range(h):
        norm_y = y / float(h)
        is_white = 0.44 <= norm_y <= 0.56
        is_rim = (y in (2, 3, h - 3, h - 4) or 
                  abs(norm_y - 0.33) < 0.02 or 
                  abs(norm_y - 0.67) < 0.02)
        for x in range(w):
            roundness = math.cos((x / w - 0.5) * math.pi) * 0.25
            noise = (math.sin(x * 8.5 + y * 17.1) % 1.0) * 0.06
            if is_rim:
                v = 0.35 + roundness + noise
                arr[y, x] = [v, v, v, 1.0]
            elif is_white:
                v = 0.72 + roundness + noise
                arr[y, x] = [v, v * 0.98, v * 0.92, 1.0]
            else:
                v = 0.45 + roundness + noise
                arr[y, x] = [v * 0.2, v * 0.4, v * 1.1, 1.0]
    return arr

def gen_barrel_green(w, h):
    arr = np.zeros((h, w, 4), dtype=np.float32)
    for y in range(h):
        norm_y = y / float(h)
        is_rim = (y in (2, 3, h - 3, h - 4) or 
                  abs(norm_y - 0.33) < 0.02 or 
                  abs(norm_y - 0.67) < 0.02)
        for x in range(w):
            roundness = math.cos((x / w - 0.5) * math.pi) * 0.25
            noise = (math.sin(x * 8.5 + y * 17.1) % 1.0) * 0.06
            if is_rim:
                v = 0.35 + roundness + noise
                arr[y, x] = [v, v, v, 1.0]
            else:
                v = 0.40 + roundness + noise
                arr[y, x] = [v * 0.35, v * 0.65, v * 0.3, 1.0]
    return arr

def gen_mud_ground(w, h):
    arr = np.zeros((h, w, 4), dtype=np.float32)
    for y in range(h):
        for x in range(w):
            nx = x / float(w)
            ny = y / float(h)
            # Puddle patches
            puddle1 = (math.sin(nx * 8.0) * math.cos(ny * 7.0)) > 0.45
            puddle2 = (math.sin((nx + 0.3) * 11.0) * math.sin(ny * 9.0)) > 0.5
            noise = (math.sin(x * 27.3 + y * 49.1) % 1.0) * 0.08
            if puddle1 or puddle2:
                # Dark reflective muddy water
                v = 0.16 + noise * 0.4
                arr[y, x] = [v * 1.05, v * 0.95, v * 0.85, 1.0]
            else:
                # Muddy earth / grit
                v = 0.32 + noise
                arr[y, x] = [v * 1.15, v * 0.85, v * 0.65, 1.0]
    return arr

def gen_chain_link(w, h):
    arr = np.zeros((h, w, 4), dtype=np.float32)
    for y in range(h):
        for x in range(w):
            diag1 = (x + y) % 8
            diag2 = (x - y) % 8
            if diag1 == 0 or diag2 == 0:
                # Thin metallic wire
                arr[y, x] = [0.48, 0.48, 0.50, 0.95]
            else:
                # Transparent opening
                arr[y, x] = [0.0, 0.0, 0.0, 0.0]
    return arr


# --- Mesh Construction Helpers ---

def new_mesh_obj(name, collection):
    mesh = bpy.data.meshes.new(name + "_mesh")
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    return obj, mesh

def uv_box_project(obj, scale=1.0):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=scale, correct_aspect=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)

def uv_cylinder_project(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cylinder_project(direction="VIEW_ON_EQUATOR", align="POLAR_ZX")
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)


# --- Scene Construction ---

def build_scene():
    print("Building PS1 Shed Yard scene...")
    
    # 1. Prepare collection in active scene
    scene = bpy.context.scene
    coll_name = "SHED_YARD"
    if coll_name in bpy.data.collections:
        # Clear existing
        coll = bpy.data.collections[coll_name]
        for obj in list(coll.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
    else:
        coll = bpy.data.collections.new(coll_name)
        scene.collection.children.link(coll)
    
    # 2. Build Textures & Materials
    print("Generating PS1 procedural textures...")
    tex_wall = create_image("tex_corrugated_metal", 128, 128, gen_corrugated_metal)
    mat_wall = create_material("M_CorrugatedMetal", tex_wall, roughness=0.6)
    
    tex_garage = create_image("tex_garage_door", 128, 128, gen_garage_door)
    mat_garage = create_material("M_GarageDoor", tex_garage, roughness=0.7)
    
    tex_tarp = create_image("tex_blue_tarp", 128, 128, gen_blue_tarp)
    mat_tarp = create_material("M_BlueTarp", tex_tarp, roughness=0.45)
    
    tex_wood = create_image("tex_wood_pole", 64, 128, gen_wood_pole)
    mat_wood = create_material("M_WoodPole", tex_wood, roughness=0.9)
    
    tex_b_red = create_image("tex_barrel_red", 64, 64, gen_barrel_red)
    mat_b_red = create_material("M_BarrelRed", tex_b_red, roughness=0.55)
    
    tex_b_blue = create_image("tex_barrel_blue", 64, 64, gen_barrel_blue)
    mat_b_blue = create_material("M_BarrelBlue", tex_b_blue, roughness=0.55)
    
    tex_b_green = create_image("tex_barrel_green", 64, 64, gen_barrel_green)
    mat_b_green = create_material("M_BarrelGreen", tex_b_green, roughness=0.55)
    
    tex_mud = create_image("tex_mud_ground", 128, 128, gen_mud_ground)
    mat_mud = create_material("M_MudGround", tex_mud, roughness=0.4)
    
    tex_fence = create_image("tex_chain_link", 64, 64, gen_chain_link)
    mat_fence = create_material("M_ChainLink", tex_fence, roughness=0.7, is_cutout=True)
    
    mat_metal_dark = create_material("M_DarkMetal", color=(0.25, 0.25, 0.27, 1.0), roughness=0.6)
    mat_lamp_light = create_material("M_LampLight", color=(1.0, 0.95, 0.8, 1.0), is_emissive=True, emissive_color=(2.0, 1.9, 1.5))
    mat_table_wood = create_material("M_TableWood", tex_wood, roughness=0.9)

    # 3. Build Ground (Mud Terrain)
    print("Building ground terrain...")
    g_obj, g_mesh = new_mesh_obj("Ground_Terrain", coll)
    bm = bmesh.new()
    # 30m x 30m ground with subtle height variation
    bmesh.ops.create_grid(bm, x_segments=16, y_segments=16, size=15.0)
    for v in bm.verts:
        noise = math.sin(v.co.x * 0.8) * math.cos(v.co.y * 0.7) * 0.08
        v.co.z = noise
        # Lower driveway puddle slightly
        if -2.0 < v.co.x < 2.0 and -4.0 < v.co.y < 0.0:
            v.co.z -= 0.06
    bm.to_mesh(g_mesh)
    bm.free()
    g_obj.data.materials.append(mat_mud)
    uv_box_project(g_obj, scale=3.0)

    # 4. Build Shed (Galpao)
    print("Building shed structure...")
    # Shed footprint: X: -2.5 to 2.5 (width 5.0m), Y: 0.0 to 7.5 (length 7.5m)
    # Eaves Z: 2.8m, Peak Z: 3.8m at X: 0.0
    s_obj, s_mesh = new_mesh_obj("Shed_Body", coll)
    bm = bmesh.new()
    
    # Back wall (Y = 7.5)
    v_b1 = bm.verts.new((-2.5, 7.5, 0.0))
    v_b2 = bm.verts.new((2.5, 7.5, 0.0))
    v_b3 = bm.verts.new((2.5, 7.5, 2.8))
    v_b4 = bm.verts.new((0.0, 7.5, 3.8))
    v_b5 = bm.verts.new((-2.5, 7.5, 2.8))
    bm.faces.new((v_b1, v_b2, v_b3, v_b4, v_b5))
    
    # Left wall (X = -2.5)
    v_l1 = bm.verts.new((-2.5, 0.0, 0.0))
    v_l2 = bm.verts.new((-2.5, 0.0, 2.8))
    bm.faces.new((v_l1, v_b1, v_b5, v_l2))
    
    # Right wall (X = 2.5)
    v_r1 = bm.verts.new((2.5, 0.0, 0.0))
    v_r2 = bm.verts.new((2.5, 0.0, 2.8))
    # Side pedestrian door at X = 2.5, Y = 4.5 to 5.5
    v_rd1 = bm.verts.new((2.5, 4.5, 0.0))
    v_rd2 = bm.verts.new((2.5, 5.5, 0.0))
    v_rd3 = bm.verts.new((2.5, 5.5, 2.1))
    v_rd4 = bm.verts.new((2.5, 4.5, 2.1))
    bm.faces.new((v_r1, v_rd1, v_rd4, v_r2))
    bm.faces.new((v_rd2, v_b2, v_b3, v_r2))
    bm.faces.new((v_rd4, v_rd3, v_b3, v_r2))
    
    # Front wall (Y = 0.0) with garage opening (X: -1.3 to 1.3, Z: 0.0 to 2.3)
    v_f_peak = bm.verts.new((0.0, 0.0, 3.8))
    v_f_topl = bm.verts.new((-1.3, 0.0, 2.3))
    v_f_topr = bm.verts.new((1.3, 0.0, 2.3))
    v_f_botl = bm.verts.new((-1.3, 0.0, 0.0))
    v_f_botr = bm.verts.new((1.3, 0.0, 0.0))
    
    bm.faces.new((v_l1, v_f_botl, v_f_topl, v_l2))  # Left front column
    bm.faces.new((v_f_botr, v_r1, v_r2, v_f_topr))  # Right front column
    bm.faces.new((v_l2, v_f_topl, v_f_topr, v_r2, v_f_peak))  # Gable above door
    
    # Roof (Gabled roof with eaves overhang: X extends to -2.8 and +2.8, Y from -0.3 to 7.8)
    r_peak_front = bm.verts.new((0.0, -0.3, 3.9))
    r_peak_back  = bm.verts.new((0.0, 7.8, 3.9))
    r_eave_lf    = bm.verts.new((-2.8, -0.3, 2.75))
    r_eave_lb    = bm.verts.new((-2.8, 7.8, 2.75))
    r_eave_rf    = bm.verts.new((2.8, -0.3, 2.75))
    r_eave_rb    = bm.verts.new((2.8, 7.8, 2.75))
    
    bm.faces.new((r_eave_lf, r_peak_front, r_peak_back, r_eave_lb))  # Left roof pitch
    bm.faces.new((r_peak_front, r_eave_rf, r_eave_rb, r_peak_back))  # Right roof pitch
    
    bm.to_mesh(s_mesh)
    bm.free()
    s_obj.data.materials.append(mat_wall)
    uv_box_project(s_obj, scale=2.0)

    # Garage Door (Roll-up shutter at Y = 0.05)
    gd_obj, gd_mesh = new_mesh_obj("Garage_Door", coll)
    bm_gd = bmesh.new()
    bmesh.ops.create_cube(bm_gd, size=1.0)
    for v in bm_gd.verts:
        v.co.x *= 2.6
        v.co.y = v.co.y * 0.08 + 0.04
        v.co.z = (v.co.z + 0.5) * 2.3
    bm_gd.to_mesh(gd_mesh)
    bm_gd.free()
    gd_obj.data.materials.append(mat_garage)
    uv_box_project(gd_obj, scale=1.5)

    # Door Frame Trims
    trim_obj, trim_mesh = new_mesh_obj("Garage_Trim", coll)
    bm_tr = bmesh.new()
    # Left post
    bmesh.ops.create_cube(bm_tr, size=1.0, matrix=Matrix.Translation((-1.35, -0.02, 1.15)) @ Matrix.Diagonal((0.14, 0.12, 2.35, 1.0)))
    # Right post
    bmesh.ops.create_cube(bm_tr, size=1.0, matrix=Matrix.Translation((1.35, -0.02, 1.15)) @ Matrix.Diagonal((0.14, 0.12, 2.35, 1.0)))
    # Lintel
    bmesh.ops.create_cube(bm_tr, size=1.0, matrix=Matrix.Translation((0.0, -0.02, 2.35)) @ Matrix.Diagonal((2.8, 0.12, 0.16, 1.0)))
    bm_tr.to_mesh(trim_mesh)
    bm_tr.free()
    trim_obj.data.materials.append(mat_metal_dark)

    # 5. Build Leaning Ladder & Blue Tarp (on the right side, visible from front)
    print("Building ladder and blue tarp...")
    # Ladder: leans against shed eave at X = 2.5, Y = 3.2
    lad_obj, lad_mesh = new_mesh_obj("Ladder", coll)
    bm_lad = bmesh.new()
    rail_len = math.sqrt((3.3 - 2.5)**2 + 2.8**2)  # ~2.91m
    angle = math.atan2(2.8, 3.3 - 2.5)  # ~74 deg
    rot = Matrix.Rotation(math.pi/2 - angle, 4, 'Y')
    
    # 2 rails
    for offset_y in (-0.20, 0.20):
        mat_rail = Matrix.Translation((2.9, 3.2 + offset_y, 1.4)) @ rot @ Matrix.Diagonal((0.06, 0.05, rail_len, 1.0))
        bmesh.ops.create_cube(bm_lad, size=1.0, matrix=mat_rail)
    # 8 rungs
    for i in range(1, 9):
        frac = i / 9.0
        rz = 2.8 * frac
        rx = 2.5 + (3.3 - 2.5) * (1.0 - frac)
        mat_rung = Matrix.Translation((rx, 3.2, rz)) @ Matrix.Diagonal((0.04, 0.40, 0.04, 1.0))
        bmesh.ops.create_cube(bm_lad, size=1.0, matrix=mat_rung)
    bm_lad.to_mesh(lad_mesh)
    bm_lad.free()
    lad_obj.data.materials.append(mat_wood)

    # Blue Tarp draped over roof and ladder
    tarp_obj, tarp_mesh = new_mesh_obj("Blue_Tarp", coll)
    bm_tarp = bmesh.new()
    cols_x = [0.0, 1.0, 2.0, 2.7, 3.3, 3.8]
    rows_y = [1.8, 2.4, 3.0, 3.6, 4.2]
    grid_verts = []
    for r, y in enumerate(rows_y):
        row_v = []
        for c, x in enumerate(cols_x):
            if x <= 2.6:
                z = 3.8 - (x / 2.8) * 1.0 + 0.06
            elif x <= 3.3:
                z = 2.8 - ((x - 2.6) / 0.7) * 1.25
            else:
                z = max(0.02, 1.55 - ((x - 3.3) / 0.5) * 1.55)
            z += math.sin(x * 4.0 + y * 3.5) * 0.08
            v = bm_tarp.verts.new((x, y, z))
            row_v.append(v)
        grid_verts.append(row_v)
    
    for r in range(len(rows_y) - 1):
        for c in range(len(cols_x) - 1):
            v1 = grid_verts[r][c]
            v2 = grid_verts[r][c+1]
            v3 = grid_verts[r+1][c+1]
            v4 = grid_verts[r+1][c]
            bm_tarp.faces.new((v1, v2, v3, v4))
    
    bm_tarp.to_mesh(tarp_mesh)
    bm_tarp.free()
    tarp_obj.data.materials.append(mat_tarp)
    uv_box_project(tarp_obj, scale=1.5)

    # 6. Build Utility Pole ("Pole") with Street Lamp & Cables
    print("Building utility pole with lamp and wires...")
    pole_x, pole_y = -3.2, -1.0
    pole_obj, pole_mesh = new_mesh_obj("Utility_Pole", coll)
    bm_pole = bmesh.new()
    
    # Octagonal Pole trunk (height 6.8m)
    bmesh.ops.create_cone(
        bm_pole, 
        cap_ends=True, 
        cap_tris=False, 
        segments=8, 
        radius1=0.17, 
        radius2=0.12, 
        depth=6.8, 
        matrix=Matrix.Translation((pole_x, pole_y, 3.4))
    )
    # Crossarm beam at Z = 6.1m (length 2.2m along X)
    bmesh.ops.create_cube(
        bm_pole, 
        size=1.0, 
        matrix=Matrix.Translation((pole_x, pole_y, 6.1)) @ Matrix.Diagonal((2.2, 0.14, 0.14, 1.0))
    )
    # Diagonal braces
    bmesh.ops.create_cube(
        bm_pole, 
        size=1.0, 
        matrix=Matrix.Translation((pole_x - 0.45, pole_y + 0.06, 5.65)) @ Matrix.Rotation(-0.55, 4, 'Y') @ Matrix.Diagonal((0.95, 0.04, 0.04, 1.0))
    )
    bmesh.ops.create_cube(
        bm_pole, 
        size=1.0, 
        matrix=Matrix.Translation((pole_x + 0.45, pole_y + 0.06, 5.65)) @ Matrix.Rotation(0.55, 4, 'Y') @ Matrix.Diagonal((0.95, 0.04, 0.04, 1.0))
    )
    # 4 Ceramic Insulators on crossarm
    for ix in (-0.9, -0.3, 0.3, 0.9):
        bmesh.ops.create_cone(
            bm_pole, 
            cap_ends=True, 
            segments=6, 
            radius1=0.04, 
            radius2=0.03, 
            depth=0.15, 
            matrix=Matrix.Translation((pole_x + ix, pole_y, 6.24))
        )
    
    # Street Lamp Fixture on pole (angled toward yard center)
    arm_start = Vector((pole_x, pole_y, 5.3))
    arm_end = Vector((pole_x + 0.9, pole_y + 0.6, 4.9))
    bmesh.ops.create_cone(
        bm_pole, 
        cap_ends=True, 
        segments=6, 
        radius1=0.03, 
        radius2=0.03, 
        depth=(arm_end - arm_start).length,
        matrix=Matrix.Translation((arm_start + arm_end) * 0.5) @ Matrix.Rotation(0.4, 4, 'Z') @ Matrix.Rotation(-0.35, 4, 'Y')
    )
    # Lamp Hood / Cowl
    bmesh.ops.create_cone(
        bm_pole, 
        cap_ends=True, 
        segments=8, 
        radius1=0.20, 
        radius2=0.10, 
        depth=0.16, 
        matrix=Matrix.Translation(arm_end)
    )
    bm_pole.to_mesh(pole_mesh)
    bm_pole.free()
    pole_obj.data.materials.append(mat_wood)
    uv_box_project(pole_obj, scale=1.5)

    # Street Lamp Light Emissive Bulb
    bulb_obj, bulb_mesh = new_mesh_obj("Street_Lamp_Bulb", coll)
    bm_bulb = bmesh.new()
    bmesh.ops.create_cone(
        bm_bulb, 
        cap_ends=True, 
        segments=6, 
        radius1=0.17, 
        radius2=0.02, 
        depth=0.04, 
        matrix=Matrix.Translation((pole_x + 0.9, pole_y + 0.6, 4.82))
    )
    bm_bulb.to_mesh(bulb_mesh)
    bm_bulb.free()
    bulb_obj.data.materials.append(mat_lamp_light)

    # Power Lines (catenary sagging wires)
    wire_obj, wire_mesh = new_mesh_obj("Power_Wires", coll)
    bm_wire = bmesh.new()
    wire_ends = [
        (Vector((pole_x - 0.9, pole_y, 6.3)), Vector((10.0, -1.0, 6.0))),
        (Vector((pole_x - 0.3, pole_y, 6.3)), Vector((10.0, 2.0, 6.1))),
        (Vector((pole_x + 0.3, pole_y, 6.3)), Vector((10.0, 5.0, 6.2))),
        (Vector((pole_x + 0.9, pole_y, 6.3)), Vector((10.0, 8.0, 6.3))),
        (Vector((pole_x - 0.9, pole_y, 6.3)), Vector((-12.0, -5.0, 5.9))),
        (Vector((pole_x + 0.9, pole_y, 6.3)), Vector((-12.0, 2.0, 6.0))),
    ]
    for start_pt, end_pt in wire_ends:
        segments = 10
        pts = []
        for s in range(segments + 1):
            t = s / float(segments)
            p = start_pt.lerp(end_pt, t)
            sag = math.sin(t * math.pi) * 0.65
            p.z -= sag
            pts.append(p)
        for i in range(segments):
            seg_vec = pts[i+1] - pts[i]
            mid = (pts[i] + pts[i+1]) * 0.5
            bmesh.ops.create_cone(
                bm_wire, 
                cap_ends=False, 
                segments=4, 
                radius1=0.012, 
                radius2=0.012, 
                depth=seg_vec.length,
                matrix=Matrix.Translation(mid) @ seg_vec.to_track_quat('Z', 'Y').to_matrix().to_4x4()
            )
    bm_wire.to_mesh(wire_mesh)
    bm_wire.free()
    wire_obj.data.materials.append(mat_metal_dark)

    # 7. Build Barrels (55-gallon oil drums)
    print("Building oil barrels...")
    def add_barrel(name, pos, rot_z, mat):
        b_obj, b_mesh = new_mesh_obj(name, coll)
        bm_b = bmesh.new()
        bmesh.ops.create_cone(
            bm_b, 
            cap_ends=True, 
            segments=12, 
            radius1=0.28, 
            radius2=0.28, 
            depth=0.90, 
            matrix=Matrix.Translation((0, 0, 0.45))
        )
        for r_z in (0.30, 0.60):
            bmesh.ops.create_cone(
                bm_b, 
                cap_ends=False, 
                segments=12, 
                radius1=0.295, 
                radius2=0.295, 
                depth=0.04, 
                matrix=Matrix.Translation((0, 0, r_z))
            )
        bm_b.to_mesh(b_mesh)
        bm_b.free()
        b_obj.location = pos
        b_obj.rotation_euler.z = rot_z
        b_obj.data.materials.append(mat)
        uv_cylinder_project(b_obj)
        return b_obj

    add_barrel("Barrel_Red_Garage", Vector((-1.6, -0.3, 0.0)), 0.4, mat_b_red)
    add_barrel("Barrel_Red_Ladder", Vector((3.1, 2.5, 0.0)), 1.2, mat_b_red)
    add_barrel("Barrel_Red_Ladder_2", Vector((3.5, 3.0, 0.0)), -0.6, mat_b_red)
    add_barrel("Barrel_Blue_Fence", Vector((2.8, -3.1, 0.0)), 0.2, mat_b_blue)
    add_barrel("Barrel_Green_Fence", Vector((3.4, -2.8, 0.0)), -0.8, mat_b_green)

    # 8. Build Wooden Work Table
    print("Building wooden work bench...")
    t_obj, t_mesh = new_mesh_obj("Work_Table", coll)
    bm_t = bmesh.new()
    bmesh.ops.create_cube(
        bm_t, 
        size=1.0, 
        matrix=Matrix.Translation((3.6, 1.4, 0.72)) @ Matrix.Diagonal((0.8, 1.4, 0.06, 1.0))
    )
    for lx in (3.3, 3.9):
        for ly in (0.85, 1.95):
            bmesh.ops.create_cube(
                bm_t, 
                size=1.0, 
                matrix=Matrix.Translation((lx, ly, 0.35)) @ Matrix.Diagonal((0.08, 0.08, 0.70, 1.0))
            )
    bm_t.to_mesh(t_mesh)
    bm_t.free()
    t_obj.data.materials.append(mat_table_wood)
    uv_box_project(t_obj, scale=1.0)

    # 9. Build Chain-link Fence Enclosure
    print("Building chain-link fence...")
    fence_segments = [
        (Vector((-5.8, -3.5, 0)), Vector((-5.8, 9.0, 0)), False),
        (Vector((-5.8, 9.0, 0)), Vector((5.5, 9.0, 0)), False),
        (Vector((5.5, 9.0, 0)), Vector((5.5, -3.5, 0)), False),
        # Front right section (starts at X = 2.4, framing the right side with barrels)
        (Vector((5.5, -3.5, 0)), Vector((2.4, -3.5, 0)), False),
        # Front left section (leaning/broken)
        (Vector((-2.0, -3.5, 0)), Vector((-5.8, -3.5, 0)), True),
    ]
    
    f_post_obj, f_post_mesh = new_mesh_obj("Fence_Posts", coll)
    f_mesh_obj, f_mesh_mesh = new_mesh_obj("Fence_Mesh", coll)
    bm_posts = bmesh.new()
    bm_mesh = bmesh.new()
    
    for start, end, is_tilted in fence_segments:
        disp = end - start
        total_len = disp.length
        num_bays = max(1, int(round(total_len / 2.2)))
        step = disp / float(num_bays)
        
        for b in range(num_bays):
            p0 = start + step * b
            p1 = start + step * (b + 1)
            tilt_angle = 0.12 if (is_tilted and b == 0) else 0.0
            
            bmesh.ops.create_cone(
                bm_posts, 
                cap_ends=True, 
                segments=6, 
                radius1=0.035, 
                radius2=0.035, 
                depth=1.8, 
                matrix=Matrix.Translation((p0.x, p0.y, 0.9)) @ Matrix.Rotation(tilt_angle, 4, 'X')
            )
            
            bay_vec = p1 - p0
            mid_bay = (p0 + p1) * 0.5
            bmesh.ops.create_cone(
                bm_posts, 
                cap_ends=True, 
                segments=4, 
                radius1=0.025, 
                radius2=0.025, 
                depth=bay_vec.length, 
                matrix=Matrix.Translation((mid_bay.x, mid_bay.y, 1.78)) @ bay_vec.to_track_quat('Z', 'Y').to_matrix().to_4x4()
            )
            
            mv1 = bm_mesh.verts.new((p0.x, p0.y, 0.05))
            mv2 = bm_mesh.verts.new((p1.x, p1.y, 0.05))
            mv3 = bm_mesh.verts.new((p1.x, p1.y, 1.78))
            mv4 = bm_mesh.verts.new((p0.x, p0.y, 1.78))
            bm_mesh.faces.new((mv1, mv2, mv3, mv4))
            
        bmesh.ops.create_cone(
            bm_posts, 
            cap_ends=True, 
            segments=6, 
            radius1=0.035, 
            radius2=0.035, 
            depth=1.8, 
            matrix=Matrix.Translation((end.x, end.y, 0.9))
        )
    
    bm_posts.to_mesh(f_post_mesh)
    bm_posts.free()
    f_post_obj.data.materials.append(mat_metal_dark)
    
    bm_mesh.to_mesh(f_mesh_mesh)
    bm_mesh.free()
    f_mesh_obj.data.materials.append(mat_fence)
    uv_box_project(f_mesh_obj, scale=1.0)

    # 10. Setup Camera Matching Image 5
    print("Setting up preview camera and lights matching image 5...")
    cam_data = bpy.data.cameras.get("ShedCam") or bpy.data.cameras.new("ShedCam")
    cam_data.lens = 28.0
    cam_data.clip_start = 0.1
    cam_data.clip_end = 150.0
    
    cam_obj = bpy.data.objects.get("ShedCam")
    if not cam_obj:
        cam_obj = bpy.data.objects.new("ShedCam", cam_data)
        coll.objects.link(cam_obj)
    
    cam_obj.location = Vector((3.6, -6.6, 1.35))
    cam_obj.rotation_euler = (math.radians(88.0), math.radians(0.0), math.radians(28.0))
    scene.camera = cam_obj

    # 11. Preview Lights
    sun_data = bpy.data.lights.get("ShedSun") or bpy.data.lights.new("ShedSun", "SUN")
    sun_data.energy = 2.5
    sun_data.color = (1.0, 0.94, 0.86)
    sun_obj = bpy.data.objects.get("ShedSun")
    if not sun_obj:
        sun_obj = bpy.data.objects.new("ShedSun", sun_data)
        coll.objects.link(sun_obj)
    sun_obj.rotation_euler = (math.radians(35.0), math.radians(-25.0), math.radians(45.0))
    
    lamp_light_data = bpy.data.lights.get("StreetLampLight") or bpy.data.lights.new("StreetLampLight", "SPOT")
    lamp_light_data.energy = 150.0
    lamp_light_data.color = (1.0, 0.92, 0.75)
    lamp_light_data.spot_size = math.radians(75.0)
    lamp_light_data.spot_blend = 0.3
    lamp_light_obj = bpy.data.objects.get("StreetLampLight")
    if not lamp_light_obj:
        lamp_light_obj = bpy.data.objects.new("StreetLampLight", lamp_light_data)
        coll.objects.link(lamp_light_obj)
    lamp_light_obj.location = Vector((pole_x + 0.9, pole_y + 0.6, 4.85))
    lamp_light_obj.rotation_euler = (math.radians(15.0), math.radians(10.0), math.radians(-30.0))

    # 12. Export .glb
    os.makedirs(os.path.dirname(BLEND_SAVE_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(EXPORT_PATH), exist_ok=True)
    os.makedirs(os.path.dirname(PREVIEW_RENDER_PATH), exist_ok=True)
    
    bpy.ops.object.select_all(action="DESELECT")
    for obj in coll.objects:
        if obj.type == "MESH":
            obj.select_set(True)
    
    print(f"Exporting GLB to {EXPORT_PATH}...")
    bpy.ops.export_scene.gltf(
        filepath=EXPORT_PATH,
        use_selection=True,
        export_format="GLB",
        export_apply=True,
        export_texcoords=True,
        export_materials="EXPORT"
    )
    print("GLB export complete!")
    
    return {
        "status": "success",
        "export_path": EXPORT_PATH,
        "object_count": len(coll.objects),
        "camera_location": list(cam_obj.location),
        "camera_rotation": list(cam_obj.rotation_euler)
    }

if __name__ == "__main__":
    res = build_scene()
    print("Result:", res)
