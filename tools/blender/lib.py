"""Shared helpers for the Sete Vidas Blender build scripts.

All builder code works in GAME coordinates (Godot: x right, y up, z towards the back of the house)
and converts to Blender (z up) only when creating data: game (x, y, z) -> blender (x, -z, y).
The glTF exporter converts back, so positions match 1:1 in Godot.
"""
import json
import math
import os
import random

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GODOT = os.path.join(ROOT, "godot")
TEX = os.path.join(GODOT, "assets", "textures")
CACHE = os.path.join(ROOT, "tools", "cache")
PH_MODELS = os.path.join(CACHE, "polyhaven", "models")

# game <-> blender basis
C_G2B = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))
C_B2G = C_G2B.inverted()


def gv(x, y=None, z=None):
    if y is None:
        x, y, z = x
    return Vector((x, -z, y))


def bg(v):
    """blender vector -> game tuple"""
    return (v.x, v.z, -v.y)


def game_matrix(obj):
    """Godot transform (as 3x4 row-major list) of a blender object world matrix."""
    m = C_B2G @ obj.matrix_world @ C_G2B
    return [[m[r][c] for c in range(4)] for r in range(3)]


def load_layout():
    with open(os.path.join(GODOT, "data", "layout.json"), encoding="utf8") as f:
        return json.load(f)


# ------------------------------------------------------------------ scene


def reset_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.curves, bpy.data.lights, bpy.data.cameras):
        for b in list(block):
            if b.users == 0:
                block.remove(b)


def collection(name, parent=None):
    c = bpy.data.collections.get(name)
    if c is None:
        c = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(c)
    return c


def deselect_all():
    for o in bpy.data.objects:
        try:
            o.select_set(False)
        except RuntimeError:
            pass


def link(obj, coll):
    for c in obj.users_collection:
        c.objects.unlink(obj)
    coll.objects.link(obj)
    return obj


def empty(name, coll, pos=(0, 0, 0), yaw=0.0):
    e = bpy.data.objects.new(name, None)
    e.empty_display_size = 0.2
    e.location = gv(pos)
    e.rotation_euler = Euler((0, 0, yaw), "XYZ")
    coll.objects.link(e)
    return e


# ------------------------------------------------------------------ materials

# key -> spec, read from godot/data/materials.json (the same file Godot builds its real materials from).
MATERIALS = {}


def _load_materials():
    path = os.path.join(GODOT, "data", "materials.json")
    with open(path, encoding="utf8") as f:
        data = json.load(f)
    for k, v in data.items():
        if k.startswith("_"):
            continue
        tex_path = None
        if v.get("albedo"):
            tex_path = os.path.join(TEX, v["albedo"])
        elif v.get("tex"):
            tex_path = os.path.join(TEX, v["tex"], f"{v['tex']}_diff.jpg")
        tint = v.get("tint", [1, 1, 1])
        color = v.get("color", tint if tex_path else [0.8, 0.8, 0.8])
        MATERIALS[k] = dict(
            color=[min(1.0, c) for c in color],
            tex=tex_path,
            tile=v.get("tile", 1.0),
            rough=v.get("rough", 0.7) if "color" in v else 0.75,
            metal=v.get("metal", 0.0),
            emit=v.get("emit"),
            alpha=v.get("alpha"),
            rot=v.get("rot", 0),
            unit=v.get("uv") == "unit",
        )


_load_materials()


def mat_spec(key, **kw):
    base = dict(color=(0.8, 0.8, 0.8), tex=None, tile=1.0, rough=0.7, metal=0.0, emit=None, alpha=None, rot=0, unit=False)
    base.update(kw)
    MATERIALS[key] = base


def _principled(nt):
    return next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")


def material(key):
    m = bpy.data.materials.get(key)
    if m is not None:
        return m
    spec = MATERIALS.get(key)
    if spec is None:
        print("WARNING unknown material", key)
        spec = dict(color=(0.8, 0.0, 0.8), tex=None, tile=1.0, rough=0.6, metal=0.0, emit=None, alpha=None, rot=0, unit=False)
    m = bpy.data.materials.new(key)
    try:
        m.use_nodes = True
    except Exception:  # noqa: BLE001  (always on in newer Blender)
        pass
    nt = m.node_tree
    bsdf = _principled(nt)
    col = spec["color"]
    bsdf.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1)
    bsdf.inputs["Roughness"].default_value = spec["rough"]
    bsdf.inputs["Metallic"].default_value = spec["metal"]
    if spec["emit"]:
        e = spec["emit"]
        bsdf.inputs["Emission Color"].default_value = (e[0], e[1], e[2], 1)
        bsdf.inputs["Emission Strength"].default_value = e[3] if len(e) > 3 else 1.0
    if spec["alpha"] is not None:
        bsdf.inputs["Alpha"].default_value = spec["alpha"]
        for attr, val in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(m, attr, val)
            except Exception:  # noqa: BLE001
                pass
    path = spec["tex"]
    if path:
        if os.path.exists(path) and os.path.isfile(path):
            img = bpy.data.images.load(path, check_existing=True)
            ti = nt.nodes.new("ShaderNodeTexImage")
            ti.image = img
            mp = nt.nodes.new("ShaderNodeMapping")
            s = 1.0 if spec["unit"] else 1.0 / max(1e-4, spec["tile"])
            mp.inputs["Scale"].default_value = (s, s, s)
            mp.inputs["Rotation"].default_value = (0, 0, math.radians(spec["rot"]))
            tc = nt.nodes.new("ShaderNodeTexCoord")
            nt.links.new(tc.outputs["UV"], mp.inputs["Vector"])
            nt.links.new(mp.outputs["Vector"], ti.inputs["Vector"])
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs[0].default_value = 1.0
            nt.links.new(ti.outputs["Color"], mix.inputs[6])
            mix.inputs[7].default_value = (col[0], col[1], col[2], 1)
            nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])
    return m


# ------------------------------------------------------------------ geometry


def _world_uv(p, n):
    """metres UV from a game-space point and normal (box projection)."""
    ax, ay, az = abs(n[0]), abs(n[1]), abs(n[2])
    if ay >= ax and ay >= az:
        return (p[0], p[2] if n[1] > 0 else -p[2])
    if ax >= az:
        return (-p[2] if n[0] > 0 else p[2], p[1])
    return (p[0] if n[2] > 0 else -p[0], p[1])


class Geo:
    """Accumulates polygons (game coords) per material and builds one blender mesh object."""

    def __init__(self, name):
        self.name = name
        self.verts = []
        self.faces = []
        self.face_mat = []
        self.face_uv = []
        self.mats = []
        self.smooth = []

    def _mi(self, key):
        if key not in self.mats:
            self.mats.append(key)
        return self.mats.index(key)

    def poly(self, pts, key, uvs=None, smooth=False):
        """pts: list of game-space tuples, counter-clockwise seen from outside."""
        base = len(self.verts)
        self.verts.extend(pts)
        self.faces.append(list(range(base, base + len(pts))))
        self.face_mat.append(self._mi(key))
        if uvs is None:
            a, b, c = Vector(pts[0]), Vector(pts[1]), Vector(pts[2])
            n = (b - a).cross(c - a)
            if n.length < 1e-9 and len(pts) > 3:
                n = (Vector(pts[2]) - a).cross(Vector(pts[3]) - a)
            n.normalize()
            uvs = [_world_uv(p, n) for p in pts]
        self.face_uv.append(uvs)
        self.smooth.append(smooth)

    def box(self, x0, y0, z0, x1, y1, z1, key, skip=(), keys=None):
        """axis aligned box. skip: faces to omit ('px','nx','py','ny','pz','nz'). keys: per-face material override."""
        if x0 > x1:
            x0, x1 = x1, x0
        if y0 > y1:
            y0, y1 = y1, y0
        if z0 > z1:
            z0, z1 = z1, z0
        keys = keys or {}
        P = {
            "px": [(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)],
            "nx": [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)],
            "py": [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)],
            "ny": [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
            "pz": [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
            "nz": [(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)],
        }
        for f, pts in P.items():
            if f in skip:
                continue
            self.poly(pts, keys.get(f, key))

    def prism(self, pts, offset, key, side_key=None):
        """a flat convex polygon (game coords) extruded by `offset`: a slab with thickness (both faces
        and the rim), every face turned to point away from the slab's centre."""
        off = Vector(offset)
        top = [Vector(p) for p in pts]
        bot = [p + off for p in top]
        centre = sum(top + bot, Vector((0, 0, 0))) / (2 * len(top))
        faces = [(top, key), (list(reversed(bot)), key)]
        n = len(top)
        for i in range(n):
            j = (i + 1) % n
            faces.append(([top[i], bot[i], bot[j], top[j]], side_key or key))
        for f, k in faces:
            a, b, c = f[0], f[1], f[2]
            nrm = (b - a).cross(c - a)
            mid = sum(f, Vector((0, 0, 0))) / len(f)
            if nrm.dot(mid - centre) < 0:
                f = list(reversed(f))
            self.poly([tuple(v) for v in f], k)

    def build(self, coll, smooth_all=False):
        me = bpy.data.meshes.new(self.name)
        bverts = [gv(p) for p in self.verts]
        # game->blender flips handedness of nothing (it is a rotation), winding stays valid
        me.from_pydata(bverts, [], self.faces)
        me.update()
        for k in self.mats:
            me.materials.append(material(k))
        for i, poly in enumerate(me.polygons):
            poly.material_index = self.face_mat[i]
            poly.use_smooth = smooth_all or self.smooth[i]
        uvl = me.uv_layers.new(name="UVMap")
        li = 0
        for i, poly in enumerate(me.polygons):
            for j in range(poly.loop_total):
                uvl.data[poly.loop_start + j].uv = self.face_uv[i][j]
                li += 1
        ob = bpy.data.objects.new(self.name, me)
        coll.objects.link(ob)
        return ob


def merge_by_distance(obj, dist=1e-4):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bm.to_mesh(obj.data)
    bm.free()


def add_mod(obj, kind, **kw):
    m = obj.modifiers.new(kind.lower(), kind)
    for k, v in kw.items():
        setattr(m, k, v)
    return m


def apply_mods(obj):
    ctx = bpy.context
    deselect_all()
    ctx.view_layer.objects.active = obj
    obj.select_set(True)
    for m in list(obj.modifiers):
        try:
            bpy.ops.object.modifier_apply(modifier=m.name)
        except RuntimeError as e:
            print("modifier apply failed", obj.name, m.name, e)
    obj.select_set(False)


def world_uv_object(obj, scale=1.0):
    """Box-project UVs (metres, game axes) on every face of a blender mesh object, after transforms."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    uvl = me.uv_layers.active
    mw = obj.matrix_world
    nmat = mw.to_3x3().inverted().transposed()
    for poly in me.polygons:
        n = bg((nmat @ poly.normal).normalized())
        for li in range(poly.loop_start, poly.loop_start + poly.loop_total):
            v = me.vertices[me.loops[li].vertex_index].co
            p = bg(mw @ v)
            u, w = _world_uv(p, n)
            uvl.data[li].uv = (u * scale, w * scale)


def set_material(obj, key, slot=None):
    m = material(key)
    if slot is None:
        obj.data.materials.clear()
        obj.data.materials.append(m)
    else:
        while len(obj.data.materials) <= slot:
            obj.data.materials.append(m)
        obj.data.materials[slot] = m


# ---- primitive generators (return blender objects positioned in game space)


def rounded_box(name, coll, center, size, key, bevel=0.01, segments=2, yaw=0.0, world_uv=True):
    """center/size in game coords (size = w(x), h(y), d(z))."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob.scale = (size[0], size[2], size[1])
    ob.location = gv(center)
    ob.rotation_euler = (0, 0, yaw)
    bpy.context.view_layer.update()
    # apply scale so the bevel is uniform
    me.transform(Matrix.Diagonal((size[0], size[2], size[1], 1)))
    ob.scale = (1, 1, 1)
    if bevel > 0:
        add_mod(ob, "BEVEL", width=bevel, segments=segments, limit_method="ANGLE")
        apply_mods(ob)
    set_material(ob, key)
    for p in ob.data.polygons:
        p.use_smooth = True
    bpy.context.view_layer.update()
    if world_uv:
        world_uv_object(ob)
    try:
        ob.data.shade_auto_smooth()
    except Exception:  # noqa: BLE001
        pass
    return ob


def lathe(name, coll, profile, key, pos=(0, 0, 0), segments=24, world_uv=False, cap=False):
    """profile: list of (radius, height) pairs from bottom to top (game metres). Revolves around game Y."""
    bm = bmesh.new()
    rings = []
    for r, h in profile:
        ring = []
        for i in range(segments):
            a = 2 * math.pi * i / segments
            ring.append(bm.verts.new((math.cos(a) * r, math.sin(a) * r, h)))
        rings.append(ring)
    uv_faces = []
    for k in range(len(rings) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            f = bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
            uv_faces.append((f, i, k))
    if cap:
        bm.faces.new(list(reversed(rings[0])))
        bm.faces.new(rings[-1])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob.location = gv(pos)
    set_material(ob, key)
    uvl = me.uv_layers.new(name="UVMap")
    total_h = max(1e-4, profile[-1][1] - profile[0][1])
    for poly in me.polygons:
        poly.use_smooth = True
        for li in range(poly.loop_start, poly.loop_start + poly.loop_total):
            v = me.vertices[me.loops[li].vertex_index].co
            a = math.atan2(v.y, v.x) / (2 * math.pi) + 0.5
            uvl.data[li].uv = (a, (v.z - profile[0][1]) / total_h)
    if world_uv:
        bpy.context.view_layer.update()
        world_uv_object(ob)
    return ob


def tube(name, coll, points, radius, key, segments=8, pos=(0, 0, 0)):
    """A tube along game-space points via a bevelled curve, converted to mesh."""
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = max(1, segments // 4)
    cu.use_fill_caps = True
    sp = cu.splines.new("POLY")
    sp.points.add(len(points) - 1)
    for i, p in enumerate(points):
        v = gv(p)
        sp.points[i].co = (v.x, v.y, v.z, 1)
    ob = bpy.data.objects.new(name, cu)
    coll.objects.link(ob)
    ob.location = gv(pos)
    bpy.context.view_layer.update()
    me = bpy.data.meshes.new_from_object(ob)
    mo = bpy.data.objects.new(name, me)
    coll.objects.link(mo)
    mo.matrix_world = ob.matrix_world
    bpy.data.objects.remove(ob, do_unlink=True)
    set_material(mo, key)
    for p in mo.data.polygons:
        p.use_smooth = True
    return mo


def join(objs, name):
    objs = [o for o in objs if o is not None]
    if not objs:
        return None
    ctx = bpy.context
    deselect_all()
    for o in objs:
        o.select_set(True)
    ctx.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = ctx.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    ob.select_set(False)
    return ob


# ------------------------------------------------------------------ Poly Haven models

_ph_cache = {}


def import_ph(mid, coll):
    """Import a Poly Haven glTF once into a hidden library collection; returns (objects, bounds_min, bounds_max) in blender space."""
    if mid in _ph_cache:
        return _ph_cache[mid]
    import house_kit  # noqa: PLC0415  (imports lib itself)

    lib = collection("_phlib")
    if mid in house_kit.KIT:
        # our own procedural piece: built in a visible scratch collection (modifiers get applied), then hidden
        new = house_kit.build(mid, collection("_kitbuild"))
    else:
        path = os.path.join(PH_MODELS, mid, f"{mid}.gltf")
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=path)
        new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        link(o, lib)
    lib.hide_render = True
    lib.hide_viewport = True
    bpy.context.view_layer.update()
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in new:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    _ph_cache[mid] = (new, mn, mx)
    return _ph_cache[mid]


def ph_size(mid):
    """model size in game axes (w, h, d) and its bounds in blender space."""
    objs, mn, mx = import_ph(mid, None)
    s = mx - mn
    return (s.x, s.z, s.y), mn, mx


# ------------------------------------------------------------------ recorded data for Godot

class Registry:
    def __init__(self):
        self.placements = []  # {"model":..., "xform": 3x4, "name":...}
        self.colliders = []  # {"min":[...], "max":[...], "tag":..., "cam":bool}
        self.nodes = {}  # name -> data (dynamic objects, markers)

    def collider(self, x0, y0, z0, x1, y1, z1, tag="furniture", cam=False, **extra):
        d = {"min": [min(x0, x1), min(y0, y1), min(z0, z1)], "max": [max(x0, x1), max(y0, y1), max(z0, z1)], "tag": tag, "cam": cam}
        d.update(extra)
        self.colliders.append(d)
        return d

    def collider_obb(self, center, size, x_axis, y_axis, tag="furniture", cam=False, **extra):
        """an oriented box: `size` along its own axes (x_axis, y_axis and their cross product, game coords)."""
        ax = Vector(x_axis).normalized()
        ay = Vector(y_axis).normalized()
        az = ax.cross(ay).normalized()
        ay = az.cross(ax).normalized()
        # rows of the basis matrix (columns = the box axes), as Godot's house_builder reads it
        basis = [[ax.x, ay.x, az.x], [ax.y, ay.y, az.y], [ax.z, ay.z, az.z]]
        d = {"obb": True, "center": list(center), "size": list(size), "basis": basis, "tag": tag, "cam": cam}
        d.update(extra)
        self.colliders.append(d)
        return d

    def save(self, path):
        with open(path, "w", encoding="utf8") as f:
            json.dump({"placements": self.placements, "colliders": self.colliders, "nodes": self.nodes}, f, indent=1)


REG = Registry()


def place_ph(mid, coll, pos, yaw=0.0, fit=None, scale=None, name=None, anchor="bottom", tilt=(0.0, 0.0), record=True, parts=None, col=None, group=None, tag="furniture"):
    """Instance a Poly Haven model.

    pos: game position of the anchor (bottom-centre by default, "top" = top-centre, "center").
    yaw: radians around game Y (0 = model front faces +z). fit: (w, h, d) game metres to scale
    uniformly into (min ratio over the given axes). parts: list of object-name prefixes to keep.
    col: collider template: "box" (bounds), "top" (thin slab on top), ("seat", seat_h, back_h, back_frac)
    or None. group: Godot parent node name (toggle sets of objects together).
    Returns (root, size in game axes, world bounds (mn, mx) in game coords).
    """
    objs_all, _, _ = import_ph(mid, coll)
    objs = objs_all
    if parts:
        objs = [o for o in objs_all if any(o.name.startswith(p) for p in parts)]
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector((min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z)))
            mx = Vector((max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z)))
    size_b = mx - mn
    s = 1.0
    if scale is not None:
        s = scale
    elif fit is not None:
        w, h, d = fit
        ratios = []
        if w:
            ratios.append(w / max(1e-4, size_b.x))
        if h:
            ratios.append(h / max(1e-4, size_b.z))
        if d:
            ratios.append(d / max(1e-4, size_b.y))
        s = min(ratios) if ratios else 1.0
    centre = (mn + mx) / 2
    if anchor == "bottom":
        pivot = Vector((centre.x, centre.y, mn.z))
    elif anchor == "top":
        pivot = Vector((centre.x, centre.y, mx.z))
    elif anchor == "back":
        pivot = Vector((centre.x, mx.y, mn.z))  # blender +y = game -z: the model's back, at floor
    else:
        pivot = centre
    root = bpy.data.objects.new(name or f"PH_{mid}", None)
    coll.objects.link(root)
    keep = set(objs)
    for o in objs:
        if o.type != "MESH":
            continue
        inst = o.copy()
        coll.objects.link(inst)
        inst.parent = root
        inst.matrix_parent_inverse = Matrix.Identity(4)
        inst.matrix_basis = Matrix.Translation(-pivot) @ o.matrix_world
    root.location = gv(pos)
    root.rotation_euler = Euler((tilt[0], tilt[1], yaw), "XYZ")
    root.scale = (s, s, s)
    bpy.context.view_layer.update()
    # world bounds in game coords
    gmn = [1e9, 1e9, 1e9]
    gmx = [-1e9, -1e9, -1e9]
    for ch in root.children:
        for c in ch.bound_box:
            g = bg(ch.matrix_world @ Vector(c))
            for i in range(3):
                gmn[i] = min(gmn[i], g[i])
                gmx[i] = max(gmx[i], g[i])
    if record:
        m = C_B2G @ root.matrix_world @ Matrix.Translation(-pivot) @ C_G2B
        entry = {"model": mid, "name": root.name, "xform": [[m[r][c] for c in range(4)] for r in range(3)]}
        if parts:
            entry["parts"] = list(parts)
        if group:
            entry["group"] = group
        REG.placements.append(entry)
    if col == "box":
        REG.collider(*gmn, *gmx, tag=tag)
    elif col == "top":
        REG.collider(gmn[0], gmx[1] - 0.04, gmn[2], gmx[0], gmx[1], gmx[2], tag=tag)
    elif isinstance(col, tuple) and col[0] == "seat":
        _, seat_h, back_h, back_frac, back_dir = col
        REG.collider(gmn[0], gmn[1], gmn[2], gmx[0], gmn[1] + seat_h, gmx[2], tag=tag)
        # back strip on the side opposite to the facing (back_dir in game axes)
        x0, y0, z0, x1, z1 = gmn[0], gmn[1], gmn[2], gmx[0], gmx[2]
        if back_dir == "-z":
            z1 = z0 + (z1 - z0) * back_frac
        elif back_dir == "+z":
            z0 = z1 - (z1 - z0) * back_frac
        elif back_dir == "-x":
            x1 = x0 + (x1 - x0) * back_frac
        else:
            x0 = x1 - (x1 - x0) * back_frac
        REG.collider(x0, y0, z0, x1, y0 + back_h, z1, tag=tag)
    return root, (size_b.x * s, size_b.z * s, size_b.y * s), (gmn, gmx)


# ------------------------------------------------------------------ export & preview


def export_glb(path, coll_names, images=False, extra_objects=()):
    ctx = bpy.context
    deselect_all()
    names = set(coll_names)
    for c in bpy.data.collections:
        if c.name in names:
            for o in c.all_objects:
                if o.name in ctx.view_layer.objects:
                    o.select_set(True)
    for o in extra_objects:
        o.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    kw = dict(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_extras=True,
        export_lights=False,
        export_cameras=False,
    )
    if not images:
        kw["export_image_format"] = "NONE"
    try:
        bpy.ops.export_scene.gltf(**kw)
    except TypeError as e:
        print("export option fallback", e)
        kw.pop("export_image_format", None)
        bpy.ops.export_scene.gltf(**kw)
    print("EXPORTED", path)


def setup_render(res=(1280, 720), samples=32):
    scene = bpy.context.scene
    for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = eng
            break
        except TypeError:
            pass
    scene.render.resolution_x, scene.render.resolution_y = res
    try:
        scene.eevee.taa_render_samples = samples
    except Exception:  # noqa: BLE001
        pass
    try:
        scene.view_settings.view_transform = "AgX"
    except Exception:  # noqa: BLE001
        pass
    if scene.world is None:
        scene.world = bpy.data.worlds.new("world")
    return scene


def preview(path, cam_pos, look_at, lens=24, res=(1280, 720)):
    scene = setup_render(res)
    cam = bpy.data.objects.get("_preview_cam")
    if cam is None:
        cam = bpy.data.objects.new("_preview_cam", bpy.data.cameras.new("_preview_cam"))
        scene.collection.objects.link(cam)
    cam.data.lens = lens
    cam.data.clip_start = 0.02
    cam.location = gv(cam_pos)
    d = gv(look_at) - gv(cam_pos)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("PREVIEW", path)


def point_light(name, coll, pos, color=(1, 0.8, 0.6), power=60, radius=0.05):
    li = bpy.data.lights.new(name, "POINT")
    li.energy = power
    li.color = color
    li.shadow_soft_size = radius
    ob = bpy.data.objects.new(name, li)
    ob.location = gv(pos)
    coll.objects.link(ob)
    return ob


def rng(seed):
    return random.Random(seed)
