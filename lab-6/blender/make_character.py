"""
make_character.py  -  สร้างตัวละคร Hero (สไตล์การ์ตูน, T-Pose) ใน Blender แล้ว Export เป็น FBX สำหรับ Mixamo

วิธีใช้ (Blender 3.6 / 4.x / 5.x):
  1. เปิด Blender -> File > New > General
  2. ไปแท็บ Scripting -> Text > Open... -> เลือกไฟล์นี้ (make_character.py)
  3. กด Run Script (▶)
  4. จะได้ไฟล์ hero_for_mixamo.fbx และ hero_character.blend ในโฟลเดอร์เดียวกับสคริปต์นี้
     (ต้องมี face_atlas.png อยู่ในโฟลเดอร์เดียวกัน)

หรือรันแบบไม่เปิดหน้าต่าง:
  blender -b -P make_character.py

แกนของ Blender: หน้าตัวละครหันไปทาง -Y, ความสูงประมาณ 1.77 m, เท้าอยู่ที่ z = 0
"""

import bpy
import bmesh
import math
import os

# ---------------------------------------------------------------- paths
def script_dir():
    try:
        d = os.path.dirname(os.path.abspath(__file__))
        if os.path.exists(os.path.join(d, "face_atlas.png")):
            return d
    except NameError:
        pass
    for t in bpy.data.texts:
        if t.filepath:
            d = os.path.dirname(bpy.path.abspath(t.filepath))
            if os.path.exists(os.path.join(d, "face_atlas.png")):
                return d
    d = bpy.path.abspath("//")
    if d and os.path.exists(os.path.join(d, "face_atlas.png")):
        return d
    raise RuntimeError("หา face_atlas.png ไม่เจอ - เปิดสคริปต์ด้วย Text > Open จากโฟลเดอร์ blender/ ของโปรเจค")

BASE = script_dir()
ATLAS = os.path.join(BASE, "face_atlas.png")
OUT_FBX = os.path.join(BASE, "hero_for_mixamo.fbx")
OUT_BLEND = os.path.join(BASE, "hero_character.blend")

# ---------------------------------------------------------------- atlas UV (Blender UV: origin bottom-left)
SWATCH = {
    "skin":   (0.80, 0.20),
    "shirt":  (0.796875, 0.953125),
    "collar": (0.875, 0.953125),
    "pants":  (0.953125, 0.953125),
    "shoe":   (0.71875, 0.875),
    "sole":   (0.796875, 0.875),
    "hair":   (0.875, 0.875),
    "button": (0.796875, 0.796875),
}
# face region on atlas: u 0..0.625, v 0.375..1.0
FACE_U = (0.0, 0.625)
FACE_V = (0.375, 1.0)

HEAD_C = (0.0, 0.0, 1.60)
HEAD_R = (0.150, 0.140, 0.165)
FACE_X = 0.165                 # half width of photo projected on head
FACE_ZTOP = 1.7335             # z of top edge of photo
FACE_ZBOT = 1.413              # z of bottom edge of photo

SHOULDER_Z = 1.38

# ---------------------------------------------------------------- helpers
def clear_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)


def make_material():
    mat = bpy.data.materials.get("HeroMat") or bpy.data.materials.new("HeroMat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    tex = nt.nodes.new("ShaderNodeTexImage")
    img = bpy.data.images.load(ATLAS, check_existing=True)
    tex.image = img
    bsdf.inputs["Roughness"].default_value = 0.7
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    out.location = (300, 0)
    tex.location = (-400, 0)
    return mat


PARTS = []


def finish(obj, swatch, mat, name):
    """apply transform, give material + UV, remember object."""
    obj.name = name
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uv = me.uv_layers.active.data
    for loop in me.loops:
        uv[loop.index].uv = SWATCH[swatch]
    me.materials.clear()
    me.materials.append(mat)
    bpy.ops.object.shade_smooth()
    PARTS.append(obj)
    return obj


def sphere(loc, scale, seg=24, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1.0, location=loc)
    o = bpy.context.active_object
    o.scale = scale
    return o


def cylinder(loc, radius, depth, rot=(0, 0, 0), verts=16, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = scale
    return o


def cone(loc, r1, r2, depth, rot=(0, 0, 0), verts=16, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = scale
    return o


def cube(loc, size, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=rot)
    o = bpy.context.active_object
    o.scale = size
    return o


# ---------------------------------------------------------------- build
def build():
    clear_scene()
    mat = make_material()
    ROT_X = (0, math.radians(90), 0)   # cylinder along X axis

    # ---- head with cartoon face texture (planar projection from the front)
    head = sphere(HEAD_C, HEAD_R, seg=40, rings=20)
    finish(head, "skin", mat, "Head")
    me = head.data
    uv = me.uv_layers.active.data
    for poly in me.polygons:
        for li in poly.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            if v.y < 0.0:   # front half -> photo
                u = (v.x + FACE_X) / (2 * FACE_X)
                w = (v.z - FACE_ZBOT) / (FACE_ZTOP - FACE_ZBOT)
                u = min(max(u, 0.0), 1.0)
                w = min(max(w, 0.0), 1.0)
                uv[li].uv = (FACE_U[0] + u * (FACE_U[1] - FACE_U[0]),
                             FACE_V[0] + w * (FACE_V[1] - FACE_V[0]))
            else:
                uv[li].uv = SWATCH["skin"]

    # ---- ears
    for sx in (-1, 1):
        finish(sphere((sx * 0.148, 0.0, 1.60), (0.025, 0.035, 0.045), 12, 8), "skin", mat, "Ear")

    # ---- hair: shell around head, trimmed to show the face
    hair = sphere((0.0, 0.012, 1.615), (0.160, 0.155, 0.172), seg=40, rings=20)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bm = bmesh.new()
    bm.from_mesh(hair.data)
    kill = []
    for v in bm.verts:
        co = hair.matrix_world @ v.co
        front = -co.y            # >0 = face side
        if front > 0.04:
            cut = 1.705          # fringe line above eyebrows
        elif front > -0.03:
            cut = 1.62           # above the ears
        else:
            cut = 1.52           # back of the head / nape
        if co.z < cut:
            kill.append(v)
    bmesh.ops.delete(bm, geom=kill, context="VERTS")
    bm.to_mesh(hair.data)
    bm.free()
    solid = hair.modifiers.new("Solid", "SOLIDIFY")
    solid.thickness = 0.012
    bpy.context.view_layer.objects.active = hair
    bpy.ops.object.modifier_apply(modifier=solid.name)
    finish(hair, "hair", mat, "Hair")

    # ---- neck
    finish(cylinder((0, 0, 1.46), 0.07, 0.14), "skin", mat, "Neck")

    # ---- torso (white polo, chubby)
    finish(sphere((0, 0.0, 1.17), (0.25, 0.18, 0.31)), "shirt", mat, "Torso")
    finish(cylinder((0, 0, SHOULDER_Z), 0.095, 0.50, ROT_X, scale=(1, 1.1, 1)), "shirt", mat, "Shoulders")
    finish(sphere((0, -0.03, 1.05), (0.24, 0.19, 0.20)), "shirt", mat, "Belly")
    bpy.ops.mesh.primitive_torus_add(major_radius=0.08, minor_radius=0.022, location=(0, 0.0, 1.45))
    finish(bpy.context.active_object, "collar", mat, "Collar")
    for i in range(2):
        finish(sphere((0, -0.178, 1.37 - i * 0.06), (0.012, 0.008, 0.012), 8, 6), "button", mat, "Button")

    # ---- arms (T-pose, along X)
    for sx in (-1, 1):
        finish(cylinder((sx * 0.31, 0, SHOULDER_Z), 0.09, 0.22, ROT_X), "shirt", mat, "Sleeve")
        finish(cone((sx * 0.57, 0, SHOULDER_Z), 0.062, 0.047, 0.40,
                    (0, math.radians(90 * sx), 0)), "skin", mat, "Arm")
        # hand (palm down), four fingers + thumb pointing forward
        finish(sphere((sx * 0.815, 0, SHOULDER_Z), (0.06, 0.05, 0.025), 16, 8), "skin", mat, "Palm")
        for j, fy in enumerate((-0.033, -0.011, 0.011, 0.033)):
            length = 0.075 if j in (1, 2) else 0.065
            finish(cylinder((sx * (0.865 + length / 2), fy, SHOULDER_Z), 0.011, length, ROT_X, 8),
                   "skin", mat, "Finger")
        finish(cylinder((sx * 0.815, -0.07, SHOULDER_Z - 0.005), 0.013, 0.07,
                        (math.radians(90), 0, math.radians(-35 * sx)), 8), "skin", mat, "Thumb")

    # ---- hips + legs (white pants)
    finish(cylinder((0, 0, 0.93), 0.22, 0.22, scale=(1.05, 0.78, 1)), "pants", mat, "Hips")
    for sx in (-1, 1):
        finish(cone((sx * 0.115, 0, 0.52), 0.078, 0.11, 0.84), "pants", mat, "Leg")
        # sneaker
        finish(sphere((sx * 0.115, -0.04, 0.06), (0.07, 0.14, 0.055)), "shoe", mat, "Shoe")
        finish(cube((sx * 0.115, -0.04, 0.012), (0.13, 0.28, 0.024)), "sole", mat, "Sole")

    # ---- join everything into one mesh
    bpy.ops.object.select_all(action="DESELECT")
    for o in PARTS:
        o.select_set(True)
    body = bpy.data.objects["Torso"]
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = "Hero"
    body.data.name = "HeroMesh"
    # origin at the feet
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return body


def export(body):
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.fbx(
        filepath=OUT_FBX,
        use_selection=True,
        object_types={"MESH"},
        mesh_smooth_type="FACE",
        path_mode="COPY",
        embed_textures=True,
        apply_scale_options="FBX_SCALE_ALL",
    )
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND)
    print("Saved:", OUT_FBX)
    print("Saved:", OUT_BLEND)


if __name__ == "__main__":
    export(build())
