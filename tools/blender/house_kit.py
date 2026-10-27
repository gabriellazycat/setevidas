"""Procedural furniture kit (clean MiSide-like style) that replaces the Poly Haven models.

KIT maps every Poly Haven id the house (and props.gd / photo.gd) uses to a builder. A builder makes
the piece at the origin in game coordinates: bottom at y=0, centred on x/z, front facing +z (the
Poly Haven convention), real scale. Rounded 1-3 cm bevels and flat colours; materials are keys of
godot/data/materials.json, so Godot swaps in the real surfaces by name.

Part names matter where the game filters or animates them: tea_set_01_teapot_01 / _cup_small_01,
wine_bottles_01_bordeaux, book_encyclopedia_set_01_bookNN, shrub_02_a..d, metal_trash_can(_rust),
fire_hydrant_*_aged, preset_01_* (power pole), vintage_suitcase_01/02, the clock's *HourHand /
*MinuteHand (origin on the dial centre), the laptop's *screen and the chest's *lid.
"""
import math

import bmesh
import bpy
from mathutils import Matrix

import house_custom as C
import lib
from lib import gv

PI = math.pi
HALF = PI / 2
BOOK_KEYS = ["fabric_red", "fabric_green", "fabric_blue", "wood_paint_blue", "fabric_rose", "wood_dark", "fabric_cream"]


class Kit:
    """Primitive helpers that name every object after the model id and collect them."""

    def __init__(self, coll, mid):
        self.coll = coll
        self.mid = mid
        self.objs = []
        self._names = {}

    def nm(self, part):
        name = part if part.startswith(self.mid) or part.startswith("preset_") else f"{self.mid}_{part}"
        n = self._names.get(name, 0)
        self._names[name] = n + 1
        return name if n == 0 else f"{name}_{n}"

    def add(self, ob):
        self.objs.append(ob)
        return ob

    # ---- primitives (game coords of the model space)

    def box(self, part, cx, cy, cz, w, h, d, key, bev=0.012, seg=3):
        bev = min(bev, 0.45 * min(w, h, d))
        return self.add(C.rbox(self.nm(part), self.coll, cx, cy, cz, w, h, d, key, bev, seg))

    def bmin(self, part, x0, y0, z0, x1, y1, z1, key, bev=0.012, seg=3):
        return self.box(part, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, abs(x1 - x0), abs(y1 - y0), abs(z1 - z0), key, bev, seg)

    def soft(self, part, cx, cy, cz, w, h, d, key, bev=0.0, levels=2):
        bev = min(bev, 0.45 * min(w, h, d))
        return self.add(C.soft_box(self.nm(part), self.coll, cx, cy, cz, w, h, d, key, levels, bev))

    def cyl(self, part, x, y, z, r0, r1, h, key, seg=16):
        """vertical, bottom radius r0 at y, top radius r1 at y + h."""
        return self.add(C.cyl(self.nm(part), self.coll, x, y, z, r0, r1, h, key, seg))

    def lathe(self, part, prof, key, pos=(0, 0, 0), seg=24, cap=False):
        return self.add(C.smooth(lib.lathe(self.nm(part), self.coll, prof, key, pos=pos, segments=seg, cap=cap)))

    def tube(self, part, pts, r, key, seg=8):
        name = self.nm(part)
        ob = lib.tube(name, self.coll, pts, r, key, segments=seg)
        ob.name = name  # the temporary curve held the name while the mesh was made
        ob.data.name = name
        return self.add(ob)

    def ball(self, part, x, y, z, r, key, s=(1, 1, 1), sub=2):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
        ob = C._new_obj(self.nm(part), self.coll, bm)
        ob.data.transform(Matrix.Diagonal((s[0], s[2], s[1], 1)))
        ob.location = gv(x, y, z)
        lib.set_material(ob, key)
        bpy.context.view_layer.update()
        lib.world_uv_object(ob)
        for p in ob.data.polygons:
            p.use_smooth = True
        return self.add(ob)

    def cylax(self, part, x, y, z, r, length, key, axis="z", ry=None, seg=24, bev=0.003):
        """cylinder of `length` along a game axis, centred on (x, y, z). ry: second radius (ellipse):
        the extent along game y for x/z axes, along game z for the y axis."""
        ry = r if ry is None else ry
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=seg, radius1=1.0, radius2=1.0, depth=1.0)
        ob = C._new_obj(self.nm(part), self.coll, bm)
        # blender axes: x = game x, y = -game z, z = game y
        if axis == "z":
            ob.data.transform(Matrix.Diagonal((r, length, ry, 1)) @ Matrix.Rotation(HALF, 4, "X"))
        elif axis == "x":
            ob.data.transform(Matrix.Diagonal((length, r, ry, 1)) @ Matrix.Rotation(HALF, 4, "Y"))
        else:
            ob.data.transform(Matrix.Diagonal((r, ry, length, 1)))
        ob.location = gv(x, y, z)
        if bev > 0:
            lib.add_mod(ob, "BEVEL", width=min(bev, 0.4 * min(r, ry, length)), segments=2, limit_method="ANGLE")
            lib.apply_mods(ob)
        lib.set_material(ob, key)
        bpy.context.view_layer.update()
        lib.world_uv_object(ob)
        return self.add(C.smooth(ob))

    def ring(self, part, x, y, z, R, t, key, axis="y", seg=32):
        """square-section torus of radius R (tube half-size t) around a game axis."""
        prof = [(R - t, -t), (R + t, -t), (R + t, t), (R - t, t), (R - t, -t)]
        ob = C.smooth(lib.lathe(self.nm(part), self.coll, prof, key, pos=(x, y, z), segments=seg))
        if axis == "x":
            self.rot(ob, "z", HALF, (x, y, z))
        elif axis == "z":
            self.rot(ob, "x", HALF, (x, y, z))
        return self.add(ob)

    def legs(self, xs, zs, h, r_bot, r_top, key, y0=0.0, seg=12):
        return [self.cyl("leg", x, y0, z, r_bot, r_top, h, key, seg) for x in xs for z in zs]

    # ---- transforms

    def rot(self, ob, axis, ang, pivot=(0, 0, 0)):
        """rotate about a game axis through a game point (right handed, game coords)."""
        bax, a = {"x": ("X", ang), "y": ("Z", ang), "z": ("Y", -ang)}[axis]
        bpy.context.view_layer.update()
        p = gv(pivot)
        ob.matrix_world = Matrix.Translation(p) @ Matrix.Rotation(a, 4, bax) @ Matrix.Translation(-p) @ ob.matrix_world
        bpy.context.view_layer.update()
        return ob

    def rot_all(self, objs, axis, ang, pivot=(0, 0, 0)):
        for o in objs:
            self.rot(o, axis, ang, pivot)
        return objs

    def origin(self, ob, p):
        """move the object origin to game point p without moving the geometry."""
        bpy.context.view_layer.update()
        local = ob.matrix_world.inverted() @ gv(p)
        ob.data.transform(Matrix.Translation(-local))
        ob.matrix_world = ob.matrix_world @ Matrix.Translation(local)
        return ob

    def join(self, objs, part):
        objs = [o for o in objs if o is not None]
        for o in objs:
            if o in self.objs:
                self.objs.remove(o)
        name = self.nm(part)
        ob = lib.join(objs, name)
        ob.name = name
        return self.add(ob)


# ====================================================================== sala


def sofa_03(k):
    """creamy upholstered three-seater with loose cushions (2.6 x 0.86 x 0.95, seat 0.48)."""
    F = "fabric_cream"
    k.legs((-1.2, 1.2), (-0.38, 0.38), 0.1, 0.02, 0.028, "wood")
    k.box("base", 0, 0.24, 0, 2.6, 0.28, 0.95, F, 0.05, 4)
    for s in (-1, 1):
        k.box("arm", s * 1.19, 0.41, 0.0, 0.22, 0.62, 0.95, F, 0.08, 5)
    back = k.box("back", 0, 0.58, -0.36, 2.16, 0.56, 0.23, F, 0.07, 4)
    k.rot(back, "x", -0.06, (0, 0.3, -0.36))
    for s in (-1, 1):
        k.soft("seat", s * 0.54, 0.425, 0.07, 1.06, 0.12, 0.74, F, 0.03)
        bk = k.soft("backrest", s * 0.54, 0.66, -0.2, 1.04, 0.4, 0.16, F, 0.04)
        k.rot(bk, "x", -0.16, (0, 0.46, -0.2))
        p = k.soft("pillow", s * 0.76, 0.67, -0.05, 0.38, 0.38, 0.11, "fabric_rose", 0.03)
        k.rot(p, "x", -0.28, (s * 0.76, 0.5, -0.05))
        k.rot(p, "y", -s * 0.25, (s * 0.76, 0.5, -0.05))


def CoffeeTable_01(k):
    k.box("top", 0, 0.405, 0, 1.3, 0.05, 0.8, "wood", 0.02, 4)
    k.legs((-0.58, 0.58), (-0.33, 0.33), 0.38, 0.018, 0.026, "wood")


def Television_01(k):
    """cream CRT set with rabbit ears; screen centre at y 0.28, x -0.05 (house.gd's static quad)."""
    for x in (-0.26, 0.26):
        for z in (-0.17, 0.17):
            k.cyl("foot", x, 0, z, 0.022, 0.02, 0.04, "plastic_black", 12)
    k.box("body", 0, 0.27, 0, 0.66, 0.46, 0.48, "plastic_beige", 0.045, 4)
    k.box("bezel", -0.05, 0.28, 0.236, 0.5, 0.38, 0.012, "plastic_black", 0.03, 4)
    k.box("glass", -0.05, 0.28, 0.24, 0.44, 0.33, 0.008, "window_dark", 0.025, 3)
    for y in (0.37, 0.27):
        k.cylax("knob", 0.255, y, 0.245, 0.024, 0.024, "plastic_black", "z")
    k.box("grille", 0.255, 0.13, 0.241, 0.08, 0.1, 0.006, "hessian", 0.006, 2)
    k.ball("ant_base", 0.05, 0.5, -0.05, 0.032, "metal_dark", (1, 0.6, 1))
    for dx in (-0.17, 0.17):
        k.tube("antenna", [(0.05, 0.5, -0.05), (0.05 + dx, 0.8, -0.09)], 0.004, "chrome", 6)


def GreenChair_01(k):
    """sage velvet armchair (0.72 x 0.98 x 0.72, seat 0.48)."""
    F = "fabric_green"
    k.legs((-0.3, 0.3), (-0.28, 0.28), 0.12, 0.018, 0.024, "wood")
    k.box("base", 0, 0.25, 0.0, 0.72, 0.26, 0.7, F, 0.05, 4)
    k.soft("seat", 0, 0.43, 0.05, 0.54, 0.11, 0.56, F, 0.03)
    for s in (-1, 1):
        k.box("arm", s * 0.305, 0.51, 0.0, 0.11, 0.26, 0.7, F, 0.045, 4)
    back = k.box("back", 0, 0.68, -0.29, 0.72, 0.6, 0.13, F, 0.06, 4)
    cush = k.soft("backrest", 0, 0.67, -0.19, 0.5, 0.38, 0.1, F, 0.03)
    k.rot_all([back, cush], "x", -0.12, (0, 0.38, -0.29))


def wooden_bookshelf_worn(k):
    """honey wood bookcase, 1.0 x 1.9 x 0.4, four shelves, a few books."""
    W = "wood"
    for s in (-1, 1):
        k.bmin("side", s * 0.5, 0, -0.2, s * 0.476, 1.9, 0.2, W, 0.006)
    k.bmin("top", -0.5, 1.876, -0.2, 0.5, 1.9, 0.2, W, 0.006)
    k.bmin("plinth", -0.476, 0, -0.18, 0.476, 0.08, 0.19, W, 0.004)
    for y in (0.08, 0.5, 0.92, 1.36):
        k.bmin("board", -0.476, y, -0.19, 0.476, y + 0.022, 0.19, W, 0.004)
    k.bmin("back", -0.476, 0.02, -0.2, 0.476, 1.876, -0.188, "wood_paint", 0.002)
    r = lib.rng(7)
    books = []
    for y, x0, x1 in ((0.522, -0.45, 0.2), (0.942, -0.1, 0.45), (1.382, -0.45, -0.05)):
        x = x0
        while x < x1:
            w = r.uniform(0.025, 0.045)
            h = r.uniform(0.2, 0.3)
            books.append(k.bmin("book", x, y, -0.16, x + w, y + h, 0.12 + r.uniform(0, 0.04), r.choice(BOOK_KEYS), 0.004, 2))
            x += w + 0.003
    k.join(books, "books")


def vintage_grandfather_clock_01(k):
    """simplified pendulum clock (0.55 x 2.15 x 0.36). Dial centre at y 1.72; the hands' origins sit on it."""
    W = "wood"
    k.bmin("plinth", -0.275, 0, -0.18, 0.275, 0.14, 0.18, W, 0.012)
    k.bmin("trunk", -0.21, 0.14, -0.15, 0.21, 1.42, 0.06, W, 0.008)
    for x0, x1 in ((-0.21, -0.14), (0.14, 0.21)):
        k.bmin("stile", x0, 0.14, 0.06, x1, 1.42, 0.15, W, 0.008)
    k.bmin("rail", -0.14, 0.14, 0.06, 0.14, 0.4, 0.15, W, 0.008)
    k.bmin("rail", -0.14, 1.3, 0.06, 0.14, 1.42, 0.15, W, 0.008)
    k.bmin("glass", -0.14, 0.4, 0.142, 0.14, 1.3, 0.148, "glass", 0.002, 1)
    k.tube("rod", [(0, 1.38, 0.1), (0, 0.66, 0.1)], 0.006, "brass", 6)
    k.cylax("bob", 0, 0.62, 0.1, 0.07, 0.016, "brass", "z")
    k.bmin("hood", -0.25, 1.42, -0.17, 0.25, 1.98, 0.17, W, 0.012)
    k.bmin("cornice", -0.275, 1.98, -0.18, 0.275, 2.04, 0.18, W, 0.01)
    k.cylax("crown", 0, 2.04, 0, 0.2, 0.3, W, "z", ry=0.11, seg=32)
    k.cylax("dial", 0, 1.72, 0.17, 0.165, 0.014, "ceramic", "z", seg=40)
    k.ring("bezel", 0, 1.72, 0.177, 0.17, 0.008, "brass", "z", 40)
    marks = []
    for i in range(12):
        a = i / 12 * 2 * PI
        m = k.box("mark", math.sin(a) * 0.135, 1.72 + math.cos(a) * 0.135, 0.178, 0.008, 0.026 if i % 3 == 0 else 0.016, 0.003, "plastic_black", 0.001, 1)
        k.rot(m, "z", -a, (math.sin(a) * 0.135, 1.72 + math.cos(a) * 0.135, 0.178))
        marks.append(m)
    k.join(marks, "marks")
    hour = k.box("HourHand", 0, 1.72 + 0.045, 0.184, 0.014, 0.1, 0.004, "plastic_black", 0.0015, 1)
    k.origin(hour, (0, 1.72, 0.184))
    minute = k.box("MinuteHand", 0, 1.72 + 0.065, 0.189, 0.009, 0.14, 0.004, "plastic_black", 0.0015, 1)
    k.origin(minute, (0, 1.72, 0.189))
    k.cylax("pin", 0, 1.72, 0.193, 0.011, 0.008, "brass", "z")


def Chandelier_01(k):
    """five-arm brass ceiling lamp, 0.75 x 0.75; the linen shades are what lights.gd makes glow."""
    k.cyl("canopy", 0, 0.72, 0, 0.07, 0.055, 0.03, "brass", 20)
    k.tube("rod", [(0, 0.72, 0), (0, 0.12, 0)], 0.008, "brass", 8)
    k.ball("hub", 0, 0.12, 0, 0.045, "brass", (1, 0.8, 1))
    k.ball("finial", 0, 0.035, 0, 0.03, "brass")
    for i in range(5):
        a = i / 5 * 2 * PI + 0.3
        cx, cz = math.cos(a) * 0.3, math.sin(a) * 0.3
        k.tube("arm", [(0, 0.12, 0), (cx * 0.6, 0.11, cz * 0.6), (cx, 0.14, cz), (cx, 0.2, cz)], 0.007, "brass", 6)
        k.cyl("cup", cx, 0.19, cz, 0.018, 0.03, 0.02, "brass", 12)
        k.ball("bulb", cx, 0.25, cz, 0.024, "bulb", (1, 1.3, 1))
        k.lathe("shade", [(0.075, 0.0), (0.045, 0.15), (0.044, 0.152), (0.074, 0.002)], "lampshade", pos=(cx, 0.2, cz), seg=24)


def potted_plant_01(k):
    """terracotta pot with a round leafy tree (1.25 tall)."""
    k.lathe("pot", [(0.0, 0.0), (0.13, 0.0), (0.17, 0.27), (0.19, 0.29), (0.19, 0.32), (0.0, 0.32)], "terracotta", seg=28)
    k.tube("stem", [(0, 0.3, 0), (0.02, 0.6, 0.0), (0.0, 0.85, 0.01)], 0.02, "wood_dark", 6)
    leaves = [k.ball("leaf", x, y, z, r, "leaves", (1, 0.85, 1)) for x, y, z, r in ((0, 0.98, 0, 0.27), (0.17, 0.82, 0.05, 0.19), (-0.15, 1.08, -0.05, 0.17), (0.06, 1.08, 0.13, 0.15), (-0.16, 0.84, 0.09, 0.16), (0.1, 0.9, -0.17, 0.15))]
    k.join(leaves, "leaves")


def fancy_picture_frame_01(k):
    _frame(k, 0.6, 0.46, 0.022, "wood", "landscape")


def fancy_picture_frame_02(k):
    _frame(k, 0.55, 0.64, 0.05, "wood_dark", "vase")


def hanging_picture_frame_02(k):
    _frame(k, 0.75, 0.5, 0.03, "wood_paint", "fields")


def _frame(k, w, h, d, key, motif):
    """wall frame, back at z=0 side (anchor back), front +z."""
    t = 0.045
    z0, z1 = -d / 2, d / 2
    k.bmin("frame_b", -w / 2, 0, z0, w / 2, t, z1, key, 0.008)
    k.bmin("frame_t", -w / 2, h - t, z0, w / 2, h, z1, key, 0.008)
    k.bmin("frame_l", -w / 2, t, z0, -w / 2 + t, h - t, z1, key, 0.008)
    k.bmin("frame_r", w / 2 - t, t, z0, w / 2, h - t, z1, key, 0.008)
    zc = z1 - 0.008
    k.bmin("canvas", -w / 2 + t, t, z0, w / 2 - t, h - t, zc, "paper", 0.0, 1)
    iw, ih = w - 2 * t - 0.04, h - 2 * t - 0.04
    yb = t + 0.02
    if motif == "landscape":
        k.bmin("sky", -iw / 2, yb + ih * 0.45, zc, iw / 2, yb + ih, zc + 0.002, "fabric_blue", 0.0, 1)
        k.bmin("hill", -iw / 2, yb, zc, iw / 2, yb + ih * 0.45, zc + 0.002, "fabric_green", 0.0, 1)
        k.cylax("sun", iw * 0.25, yb + ih * 0.72, zc + 0.002, ih * 0.12, 0.002, "fabric_cream", "z", bev=0)
    elif motif == "vase":
        k.bmin("wall", -iw / 2, yb, zc, iw / 2, yb + ih, zc + 0.002, "fabric_green", 0.0, 1)
        k.cylax("vase", 0, yb + ih * 0.25, zc + 0.002, iw * 0.16, 0.002, "ceramic", "z", ry=ih * 0.2, bev=0)
        for dx, dy in ((-0.05, 0.62), (0.05, 0.6), (0.0, 0.72)):
            k.cylax("flower", dx * w, yb + ih * dy, zc + 0.003, iw * 0.09, 0.002, "fabric_rose", "z", bev=0)
    else:
        for i, kk in enumerate(("fabric_green", "fabric_cream", "fabric_rose", "fabric_green")):
            k.bmin("band", -iw / 2, yb + ih * i / 4, zc, iw / 2, yb + ih * (i + 1) / 4, zc + 0.002, kk, 0.0, 1)


# ====================================================================== escritório


def metal_office_desk(k):
    """wooden desk with two drawer pedestals (1.8 x 0.71 x 0.85); pedestals |x| 0.45..0.85."""
    k.bmin("top", -0.9, 0.68, -0.425, 0.9, 0.71, 0.425, "wood", 0.012)
    for s in (-1, 1):
        x0, x1 = sorted((s * 0.45, s * 0.85))
        k.bmin("pedestal", x0, 0.0, -0.4, x1, 0.68, 0.39, "wood_paint", 0.01)
        for y0, y1 in ((0.04, 0.3), (0.32, 0.5), (0.52, 0.66)):
            k.bmin("drawer", x0 + 0.02, y0, 0.39, x1 - 0.02, y1, 0.405, "wood", 0.006)
            k.cylax("knob", (x0 + x1) / 2, (y0 + y1) / 2, 0.415, 0.014, 0.02, "brass", "z")
    k.bmin("modesty", -0.45, 0.3, -0.4, 0.45, 0.66, -0.38, "wood_paint", 0.006)


def dining_chair_02(k):
    """desk chair: honey wood, blue seat pad (0.44 x 0.95 x 0.5, seat 0.47)."""
    k.legs((-0.18, 0.18), (-0.19, 0.19), 0.43, 0.015, 0.02, "wood")
    k.box("seat", 0, 0.45, 0, 0.44, 0.04, 0.46, "wood", 0.012)
    k.soft("pad", 0, 0.485, 0.01, 0.38, 0.045, 0.4, "fabric_blue", 0.015)
    back = [k.bmin("post", s * 0.2, 0.45, -0.215, s * 0.165, 0.95, -0.185, "wood", 0.008) for s in (-1, 1)]
    back.append(k.box("rail", 0, 0.86, -0.2, 0.4, 0.13, 0.025, "wood", 0.01))
    back.append(k.box("slat", 0, 0.66, -0.2, 0.08, 0.28, 0.018, "wood", 0.006))
    k.rot_all(back, "x", -0.08, (0, 0.45, -0.2))


def classic_laptop(k):
    """cream laptop, open; the *screen object is the one panel house.gd lights up."""
    k.bmin("base", -0.18, 0, -0.125, 0.18, 0.02, 0.125, "plastic_beige", 0.006)
    k.bmin("keys", -0.155, 0.019, -0.11, 0.155, 0.022, 0.02, "plastic_black", 0.001, 1)
    k.bmin("pad", -0.04, 0.019, 0.04, 0.04, 0.0215, 0.1, "plastic_white", 0.001, 1)
    lid = k.bmin("lid", -0.18, 0.02, -0.131, 0.18, 0.26, -0.122, "plastic_beige", 0.006)
    scr = k.bmin("screen", -0.16, 0.04, -0.122, 0.16, 0.245, -0.12, "window_dark", 0.002, 1)
    k.rot_all([lid, scr], "x", -0.26, (0, 0.02, -0.125))


def desk_lamp_arm_01(k):
    M = "metal_painted"
    k.cylax("base", 0, 0.0125, 0, 0.075, 0.025, M, "y")
    k.tube("arm", [(0, 0.02, 0), (0, 0.3, -0.07), (0, 0.48, 0.08)], 0.008, M, 8)
    k.ball("joint", 0, 0.3, -0.07, 0.016, M)
    shade = k.lathe("shade", [(0.012, 0.03), (0.03, 0.02), (0.08, -0.08), (0.076, -0.082), (0.026, 0.016), (0.0, 0.025)], M, pos=(0, 0.5, 0.1), seg=24)
    bulb = k.ball("bulb", 0, 0.45, 0.1, 0.025, "bulb")
    k.rot_all([shade, bulb], "x", 0.5, (0, 0.5, 0.1))


def drawer_cabinet(k):
    """chest of drawers for the office (1.0 x 1.1 x 0.5)."""
    k.legs((-0.45, 0.45), (-0.2, 0.2), 0.1, 0.018, 0.024, "wood")
    k.bmin("body", -0.5, 0.1, -0.25, 0.5, 1.08, 0.23, "wood", 0.012)
    k.bmin("top", -0.51, 1.08, -0.255, 0.51, 1.1, 0.255, "wood", 0.008)
    ys = [0.13, 0.36, 0.59, 0.82, 1.05]
    for i in range(4):
        k.bmin("drawer", -0.47, ys[i], 0.23, 0.47, ys[i + 1] - 0.02, 0.245, "wood_paint", 0.008)
        k.bmin("pull", -0.07, (ys[i] + ys[i + 1]) / 2 - 0.018, 0.245, 0.07, (ys[i] + ys[i + 1]) / 2 - 0.002, 0.262, "brass", 0.004)


def painted_wooden_nightstand(k):
    """sage painted bedside table, two drawers (0.48 x 0.62 x 0.46)."""
    k.legs((-0.2, 0.2), (-0.18, 0.18), 0.12, 0.016, 0.022, "wood")
    k.bmin("body", -0.24, 0.12, -0.23, 0.24, 0.6, 0.21, "wood_paint_green", 0.01)
    k.bmin("top", -0.245, 0.6, -0.235, 0.245, 0.62, 0.235, "wood", 0.008)
    for y0, y1 in ((0.15, 0.36), (0.38, 0.58)):
        k.bmin("drawer", -0.22, y0, 0.21, 0.22, y1, 0.225, "wood_paint_green", 0.006)
        k.cylax("knob", 0, (y0 + y1) / 2, 0.235, 0.016, 0.02, "wood", "z")


# ====================================================================== hall


def ClassicNightstand_01(k):
    """honey wood nightstand with a drawer and an open niche (0.5 x 0.62 x 0.4)."""
    k.legs((-0.21, 0.21), (-0.16, 0.16), 0.12, 0.016, 0.022, "wood")
    k.bmin("body", -0.25, 0.12, -0.2, 0.25, 0.6, 0.19, "wood", 0.01)
    k.bmin("top", -0.255, 0.6, -0.205, 0.255, 0.62, 0.205, "wood", 0.008)
    k.bmin("drawer", -0.23, 0.44, 0.19, 0.23, 0.58, 0.205, "wood_paint", 0.006)
    k.cylax("knob", 0, 0.51, 0.213, 0.015, 0.016, "brass", "z")
    k.bmin("niche", -0.22, 0.15, 0.17, 0.22, 0.41, 0.192, "wood_dark", 0.004)


def side_table_01(k):
    k.bmin("top", -0.25, 0.67, -0.21, 0.25, 0.7, 0.21, "wood", 0.01)
    k.bmin("apron", -0.22, 0.58, -0.18, 0.22, 0.67, 0.18, "wood", 0.006)
    k.legs((-0.205, 0.205), (-0.165, 0.165), 0.67, 0.016, 0.022, "wood")
    k.bmin("shelf", -0.2, 0.2, -0.16, 0.2, 0.22, 0.16, "wood", 0.005)


def painted_wooden_bench(k):
    """sage hall bench with a low back and a shoe shelf (0.95 x 0.85 x 0.42, seat 0.45)."""
    P = "wood_paint_green"
    for s in (-1, 1):
        k.bmin("side", s * 0.475, 0, -0.2, s * 0.437, 0.45, 0.2, P, 0.008)
        k.bmin("post", s * 0.475, 0.45, -0.205, s * 0.44, 0.85, -0.17, P, 0.008)
    k.bmin("seat", -0.475, 0.41, -0.2, 0.475, 0.45, 0.21, "wood", 0.01)
    k.bmin("shelf", -0.437, 0.1, -0.18, 0.437, 0.12, 0.18, P, 0.004)
    k.bmin("rail", -0.44, 0.58, -0.2, 0.44, 0.66, -0.178, P, 0.006)
    k.bmin("rail", -0.475, 0.77, -0.205, 0.475, 0.85, -0.17, P, 0.01)


def ornate_mirror_01(k):
    """oval wall mirror in honey wood (0.55 x 0.85), back on z = -0.015."""
    k.cylax("frame", 0, 0.425, 0, 0.275, 0.03, "wood", "z", ry=0.425, seg=48, bev=0.006)
    k.cylax("glass", 0, 0.425, 0.012, 0.235, 0.012, "mirror", "z", ry=0.385, seg=48, bev=0.002)


# ====================================================================== cozinha


def electric_stove(k):
    """cream enamel cooker (0.52 x 0.9 x 0.62)."""
    E = "enamel_cream"
    k.bmin("body", -0.26, 0, -0.31, 0.26, 0.86, 0.29, E, 0.012)
    k.bmin("hob", -0.26, 0.86, -0.31, 0.26, 0.9, 0.31, "enamel", 0.01)
    for x in (-0.12, 0.12):
        for z in (-0.14, 0.12):
            k.cylax("burner", x, 0.904, z, 0.07 if z < 0 else 0.055, 0.012, "metal_dark", "y")
    k.bmin("door", -0.23, 0.12, 0.29, 0.23, 0.62, 0.305, E, 0.008)
    k.box("window", 0, 0.4, 0.307, 0.3, 0.17, 0.004, "window_dark", 0.01, 2)
    k.tube("handle", [(-0.18, 0.58, 0.305), (-0.18, 0.58, 0.33), (0.18, 0.58, 0.33), (0.18, 0.58, 0.305)], 0.007, "chrome", 6)
    k.bmin("drawer", -0.23, 0.02, 0.29, 0.23, 0.1, 0.303, E, 0.006)
    for i in range(4):
        k.cylax("knob", -0.165 + i * 0.11, 0.76, 0.302, 0.02, 0.022, "plastic_black", "z")


def round_wooden_table_01(k):
    """round pedestal table, radius 0.53, top at 0.76."""
    k.cylax("top", 0, 0.74, 0, 0.53, 0.04, "wood", "y", seg=48, bev=0.01)
    k.lathe("pedestal", [(0.0, 0.0), (0.28, 0.0), (0.28, 0.025), (0.09, 0.06), (0.05, 0.13), (0.045, 0.6), (0.07, 0.68), (0.13, 0.72), (0.0, 0.72)], "wood", seg=32)


def painted_wooden_chair_01(k):
    """cream kitchen chair with spindle back and gingham cushion (0.43 x 0.95 x 0.54, seat 0.46)."""
    P = "wood_paint"
    k.legs((-0.18, 0.18), (-0.21, 0.21), 0.43, 0.015, 0.02, P)
    k.box("seat", 0, 0.445, 0, 0.43, 0.035, 0.5, "wood", 0.012)
    k.soft("cushion", 0, 0.48, 0.02, 0.38, 0.04, 0.4, "gingham", 0.015)
    back = [k.tube("post", [(s * 0.19, 0.44, -0.22), (s * 0.19, 0.95, -0.25)], 0.016, P, 8) for s in (-1, 1)]
    back.append(k.box("crest", 0, 0.89, -0.245, 0.42, 0.09, 0.025, P, 0.01))
    for x in (-0.09, 0.0, 0.09):
        back.append(k.tube("spindle", [(x, 0.46, -0.225), (x, 0.85, -0.243)], 0.009, P, 6))
    k.join(back, "back")


def wooden_bowl_01(k):
    k.lathe("bowl", [(0.0, 0.0), (0.06, 0.0), (0.1, 0.012), (0.14, 0.05), (0.15, 0.09), (0.14, 0.09), (0.13, 0.055), (0.09, 0.022), (0.0, 0.022)], "wood", seg=32)


def food_apple_01(k):
    k.ball("apple", 0, 0.04, 0, 0.044, "fabric_red", (1, 0.9, 1))
    k.tube("stem", [(0, 0.075, 0), (0.004, 0.092, 0.002)], 0.003, "wood_dark", 5)


def lemon(k):
    k.ball("lemon", 0, 0.034, 0, 0.034, "enamel_cream", (1, 1, 1.35))


def vintage_electric_kettle(k):
    E = "enamel_cream"
    k.cylax("base", 0, 0.01, 0, 0.105, 0.02, "plastic_black", "y")
    k.lathe("body", [(0.0, 0.02), (0.1, 0.02), (0.115, 0.06), (0.11, 0.17), (0.08, 0.215), (0.04, 0.225), (0.0, 0.226)], E, seg=28)
    k.ball("knob", 0, 0.235, 0, 0.015, "plastic_black")
    k.tube("handle", [(-0.09, 0.19, 0), (-0.08, 0.29, 0), (0.06, 0.29, 0), (0.07, 0.2, 0)], 0.012, "plastic_black", 8)
    k.tube("spout", [(0.1, 0.12, 0), (0.15, 0.17, 0), (0.16, 0.2, 0)], 0.014, E, 8)


def tea_set_01(k):
    """teapot (tea_set_01_teapot_01*) and a small cup (tea_set_01_cup_small_01*) for the props."""
    C_ = "ceramic"
    tp = "tea_set_01_teapot_01"
    k.lathe(tp + "_body", [(0.0, 0.0), (0.05, 0.0), (0.075, 0.03), (0.085, 0.07), (0.075, 0.11), (0.045, 0.13), (0.0, 0.13)], C_, seg=28)
    k.lathe(tp + "_lid", [(0.0, 0.125), (0.05, 0.125), (0.045, 0.14), (0.015, 0.15), (0.012, 0.16), (0.02, 0.17), (0.0, 0.175)], C_, seg=20)
    k.tube(tp + "_spout", [(0.07, 0.05, 0), (0.11, 0.08, 0), (0.13, 0.12, 0)], 0.012, C_, 8)
    k.tube(tp + "_handle", [(-0.07, 0.1, 0), (-0.12, 0.1, 0), (-0.12, 0.04, 0), (-0.075, 0.035, 0)], 0.009, C_, 8)
    cp = "tea_set_01_cup_small_01"
    k.lathe(cp + "_body", [(0.0, 0.0), (0.025, 0.0), (0.04, 0.03), (0.045, 0.06), (0.04, 0.06), (0.036, 0.03), (0.022, 0.008), (0.0, 0.008)], C_, pos=(0.3, 0, 0), seg=24)
    k.tube(cp + "_handle", [(0.343, 0.045, 0), (0.365, 0.04, 0), (0.36, 0.02, 0), (0.338, 0.02, 0)], 0.005, C_, 6)


def wooden_cutting_board(k):
    k.box("board", -0.03, 0.01, 0, 0.34, 0.02, 0.22, "wood", 0.008)
    k.box("handle", 0.17, 0.01, 0, 0.06, 0.02, 0.07, "wood", 0.008)


def wine_bottles_01(k):
    """dark glass bottles; the house keeps only wine_bottles_01_bordeaux."""
    for name, x, foil in (("wine_bottles_01_bordeaux", 0.0, "fabric_red"), ("wine_bottles_01_burgundy", 0.12, "brass")):
        k.lathe(name + "_glass", [(0.0, 0.0), (0.036, 0.0), (0.038, 0.006), (0.038, 0.2), (0.03, 0.245), (0.014, 0.265), (0.013, 0.3), (0.0, 0.3)], "window_dark", pos=(x, 0, 0), seg=24)
        k.cylax(name + "_label", x, 0.11, 0, 0.0385, 0.08, "paper", "y", bev=0)
        k.cylax(name + "_foil", x, 0.305, 0, 0.0145, 0.05, foil, "y")


def jug_01(k):
    k.lathe("body", [(0.0, 0.0), (0.055, 0.0), (0.072, 0.05), (0.068, 0.13), (0.055, 0.17), (0.062, 0.2), (0.058, 0.205), (0.0, 0.2)], "enamel_cream", seg=28)
    k.tube("handle", [(-0.06, 0.17, 0), (-0.11, 0.16, 0), (-0.1, 0.06, 0), (-0.065, 0.05, 0)], 0.01, "enamel_cream", 8)
    k.box("lip", 0.065, 0.198, 0, 0.03, 0.012, 0.04, "enamel_cream", 0.005)


# ====================================================================== banheiro / lavanderia / porão


def plunger(k):
    k.lathe("cup", [(0.0, 0.07), (0.035, 0.068), (0.075, 0.03), (0.085, 0.0), (0.0, 0.0)], "fabric_red", seg=24)
    k.cyl("stick", 0, 0.06, 0, 0.012, 0.012, 0.36, "wood", 10)


def rubber_duck_toy(k):
    # TODO(materials.json): a yellow plastic key ("plastic_yellow") would read better
    k.ball("body", 0, 0.035, 0, 0.042, "enamel_cream", (1, 0.75, 1.3))
    k.ball("head", 0, 0.075, 0.03, 0.026, "enamel_cream")
    k.ball("beak", 0, 0.072, 0.058, 0.012, "terracotta", (1.2, 0.5, 1))


def steel_frame_shelves_01(k):
    """utility shelf, 0.95 x 1.85 x 0.44; shelf tops at 0.42 / 0.86 / 1.3 / 1.74 (jars stand there)."""
    M = "metal_painted"
    for x in (-0.46, 0.46):
        for z in (-0.205, 0.205):
            k.bmin("post", x - 0.016, 0, z - 0.016, x + 0.016, 1.85, z + 0.016, M, 0.004)
    for y in (0.1, 0.42, 0.86, 1.3, 1.74):
        k.bmin("shelf", -0.475, y - 0.025, -0.22, 0.475, y, 0.22, M, 0.005)


def can_rusted(k):
    k.cyl("can", 0, 0, 0, 0.0625, 0.0625, 0.15, "iron", 24)
    k.cylax("label", 0, 0.07, 0, 0.0635, 0.08, "paper", "y", bev=0)
    k.ring("rim", 0, 0.148, 0, 0.06, 0.004, "iron", "y", 24)


def oil_tin(k):
    k.box("tin", 0, 0.09, 0, 0.115, 0.18, 0.154, "metal_painted", 0.008)
    k.cyl("spout", 0.025, 0.18, 0.04, 0.012, 0.01, 0.025, "brass", 12)
    k.tube("grip", [(-0.03, 0.18, -0.05), (-0.03, 0.2, -0.02), (-0.03, 0.2, 0.0), (-0.03, 0.18, 0.02)], 0.005, "metal_dark", 6)


def bleach_bottle(k):
    b = k.lathe("bottle", [(0.0, 0.0), (0.042, 0.0), (0.044, 0.02), (0.044, 0.2), (0.03, 0.25), (0.016, 0.262), (0.0, 0.262)], "plastic_white", seg=24)
    lbl = k.cylax("label", 0, 0.1, 0, 0.0445, 0.1, "wood_paint_blue", "y", bev=0)
    cap = k.cyl("cap", 0, 0.255, 0, 0.018, 0.017, 0.035, "wood_paint_blue", 14)
    for o in (b, lbl, cap):
        o.scale = (1, 0.7, 1)


def multi_cleaner_bottle(k):
    k.lathe("bottle", [(0.0, 0.0), (0.04, 0.0), (0.042, 0.02), (0.04, 0.14), (0.02, 0.17), (0.0, 0.17)], "fabric_blue", seg=24)
    k.cyl("neck", 0, 0.165, 0, 0.015, 0.015, 0.02, "plastic_white", 12)
    k.box("head", 0.005, 0.2, 0, 0.05, 0.035, 0.03, "plastic_white", 0.008)
    k.box("trigger", 0.015, 0.17, 0, 0.012, 0.035, 0.015, "plastic_white", 0.004)


def plastic_bottle_gallon(k):
    k.box("jug", 0, 0.11, 0, 0.16, 0.22, 0.12, "plastic_white", 0.03, 4)
    k.cyl("neck", 0.04, 0.215, 0, 0.022, 0.02, 0.035, "plastic_white", 14)
    k.cyl("cap", 0.04, 0.245, 0, 0.024, 0.024, 0.025, "fabric_red", 14)
    k.tube("handle", [(-0.07, 0.2, 0), (-0.06, 0.25, 0), (-0.01, 0.25, 0), (0.0, 0.215, 0)], 0.012, "plastic_white", 8)


def wicker_basket_01(k):
    """laundry basket (0.55 x 0.34 x 0.42) with a folded towel."""
    k.bmin("basket", -0.275, 0, -0.21, 0.275, 0.3, 0.21, "hessian", 0.03)
    k.bmin("rim", -0.285, 0.28, -0.22, 0.285, 0.315, 0.22, "wood", 0.012)
    k.soft("towel", 0, 0.32, 0.0, 0.42, 0.06, 0.3, "towel", 0.02)


def WoodenTable_03(k):
    """workbench (1.3 x 0.83 x 0.56)."""
    W = "wood_worn"
    k.bmin("top", -0.65, 0.78, -0.28, 0.65, 0.83, 0.28, W, 0.008)
    for x in (-0.6, 0.6):
        for z in (-0.23, 0.23):
            k.bmin("leg", x - 0.03, 0, z - 0.03, x + 0.03, 0.78, z + 0.03, W, 0.006)
    k.bmin("shelf", -0.6, 0.16, -0.23, 0.6, 0.19, 0.23, W, 0.006)
    k.bmin("rail", -0.6, 0.66, -0.25, 0.6, 0.76, -0.22, W, 0.006)


def hatchet(k):
    """handle along y (0.42); the blade faces -z so it points up once tilted onto the bench."""
    k.tube("handle", [(0, 0.0, 0), (0, 0.2, 0.004), (0, 0.4, 0)], 0.014, "wood", 8)
    k.box("head", 0, 0.37, -0.035, 0.022, 0.06, 0.1, "metal_dark", 0.005)
    k.box("edge", 0, 0.37, -0.088, 0.012, 0.085, 0.012, "chrome", 0.004)


def handsaw_wood(k):
    k.bmin("blade", -0.001, 0.0, -0.3, 0.001, 0.11, 0.17, "chrome", 0.0006, 1)
    k.bmin("handle", -0.013, 0.0, 0.16, 0.013, 0.15, 0.3, "wood", 0.008)


def Barrel_01(k):
    k.lathe("staves", [(0.0, 0.0), (0.235, 0.0), (0.262, 0.2), (0.272, 0.425), (0.262, 0.65), (0.235, 0.85), (0.0, 0.85)], "wood_worn", seg=32)
    for y, r in ((0.1, 0.25), (0.3, 0.27), (0.55, 0.27), (0.75, 0.25)):
        k.ring("hoop", 0, y, 0, r + 0.004, 0.012, "iron", "y", 32)


def wooden_crate_01(k):
    W = "wood_worn"
    w, h, d = 0.8, 0.34, 0.4
    k.bmin("bottom", -w / 2, 0, -d / 2, w / 2, 0.02, d / 2, W, 0.004)
    for x in (-w / 2 + 0.025, w / 2 - 0.025):
        for z in (-d / 2 + 0.025, d / 2 - 0.025):
            k.bmin("post", x - 0.025, 0, z - 0.025, x + 0.025, h, z + 0.025, W, 0.005)
    for y in (0.04, 0.2):
        for z in (-d / 2, d / 2):
            k.bmin("slat", -w / 2, y, z - 0.012 * (1 if z > 0 else -1), w / 2, y + 0.11, z, W, 0.004)
        for x in (-w / 2, w / 2):
            k.bmin("slat", x - 0.012 * (1 if x > 0 else -1), y, -d / 2, x, y + 0.11, d / 2, W, 0.004)


def cardboard_box_01(k):
    w, h, d = 0.4, 0.34, 0.52
    k.bmin("box", -w / 2, 0, -d / 2, w / 2, h, d / 2, "cardboard", 0.006, 2)
    k.bmin("tape", -0.03, h - 0.001, -d / 2 - 0.001, 0.03, h + 0.002, d / 2 + 0.001, "plastic_beige", 0.0, 1)
    for z in (-d / 2 - 0.002, d / 2 - 0.001):
        k.bmin("tape", -0.03, h - 0.08, z, 0.03, h, z + 0.003, "plastic_beige", 0.0, 1)


def mousetrap(k):
    k.bmin("base", -0.025, 0, -0.05, 0.025, 0.01, 0.05, "wood", 0.002, 1)
    k.tube("bar", [(-0.02, 0.012, -0.03), (-0.02, 0.016, 0.03), (0.02, 0.016, 0.03), (0.02, 0.012, -0.03)], 0.0015, "chrome", 4)
    k.box("bait", 0, 0.013, 0.0, 0.012, 0.005, 0.012, "brass", 0.001, 1)


def pull_chain_light_socket(k):
    k.lathe("socket", [(0.0, 0.0), (0.025, 0.0), (0.03, 0.04), (0.03, 0.1), (0.05, 0.13), (0.055, 0.165), (0.0, 0.165)], "ceramic", seg=24)
    k.tube("chain", [(0.03, 0.09, 0), (0.035, 0.02, 0)], 0.002, "brass", 4)
    k.ball("pull", 0.035, 0.012, 0, 0.008, "brass")


def lightbulb_01(k):
    """hanging bulb: brass screw on top, glass below (the whole thing glows with the room light)."""
    k.ball("glass", 0, 0.035, 0, 0.033, "bulb", (1, 1.05, 1))
    k.lathe("neck", [(0.0, 0.05), (0.028, 0.05), (0.018, 0.075), (0.0, 0.075)], "bulb", seg=16)
    k.cyl("screw", 0, 0.072, 0, 0.014, 0.014, 0.03, "bulb", 12)


# ====================================================================== quarto / hóspedes


def GothicBed_01(k):
    """low double bed in honey wood with a plain headboard (1.62 x 0.95 x 2.14, mattress top 0.4:
    the lying pose and the cat's purr spot expect the old bed's height). Head at -z, foot at +z."""
    W = "wood"
    for x in (-0.76, 0.76):
        k.bmin("rail", x - 0.05, 0.08, -1.0, x + 0.05, 0.24, 1.01, W, 0.012)
    k.legs((-0.74, 0.74), (0.98,), 0.08, 0.022, 0.028, W)
    k.bmin("deck", -0.71, 0.14, -1.0, 0.71, 0.21, 1.0, W, 0.008)
    k.bmin("headboard", -0.81, 0.0, -1.07, 0.81, 0.95, -1.0, W, 0.025, 4)
    k.bmin("footboard", -0.81, 0.0, 1.0, 0.81, 0.34, 1.07, W, 0.02, 4)
    k.soft("mattress", 0, 0.305, 0.0, 1.52, 0.19, 1.98, "sheet", 0.05)
    for s in (-1, 1):
        k.soft("pillow", s * 0.37, 0.46, -0.79, 0.62, 0.13, 0.36, "sheet", 0.04)


def old_bed_frame(k):
    """single bed frame, cream painted (1.0 x 0.9 x 2.04); the mattress is built by house_furnish."""
    P = "wood_paint"
    for x in (-0.47, 0.47):
        for z, h in ((-0.99, 0.9), (0.99, 0.6)):
            k.bmin("post", x - 0.03, 0, z - 0.03, x + 0.03, h, z + 0.03, P, 0.01)
        k.bmin("rail", x - 0.025, 0.2, -0.96, x + 0.025, 0.36, 0.96, P, 0.008)
    k.bmin("headboard", -0.44, 0.38, -1.0, 0.44, 0.84, -0.98, P, 0.008)
    k.bmin("footboard", -0.44, 0.3, 0.98, 0.44, 0.55, 1.0, P, 0.008)
    k.bmin("deck", -0.44, 0.32, -0.96, 0.44, 0.39, 0.96, "wood", 0.006)


def GothicCommode_01(k):
    """dresser: cream drawers, honey top (1.2 x 1.0 x 0.5; props stand on its top at 1.0)."""
    k.legs((-0.54, 0.54), (-0.19, 0.19), 0.1, 0.018, 0.026, "wood")
    k.bmin("body", -0.6, 0.1, -0.25, 0.6, 0.97, 0.22, "wood_paint", 0.012)
    k.bmin("top", -0.61, 0.97, -0.255, 0.61, 1.0, 0.255, "wood", 0.01)
    for y0, y1 in ((0.13, 0.39), (0.41, 0.67), (0.69, 0.94)):
        k.bmin("drawer", -0.57, y0, 0.22, 0.57, y1, 0.236, "wood_paint", 0.008)
        for x in (-0.3, 0.3):
            k.cylax("knob", x, (y0 + y1) / 2, 0.247, 0.017, 0.022, "wood", "z")


def painted_wooden_cabinet_02(k):
    """wardrobe: honey carcass, cream doors (0.9 x 2.2 x 0.6)."""
    k.bmin("plinth", -0.43, 0, -0.28, 0.43, 0.08, 0.28, "wood", 0.006)
    k.bmin("body", -0.45, 0.08, -0.3, 0.45, 2.12, 0.28, "wood", 0.012)
    k.bmin("crown", -0.47, 2.12, -0.31, 0.47, 2.2, 0.31, "wood", 0.015)
    for s in (-1, 1):
        x0, x1 = sorted((s * 0.44, s * 0.005))
        k.bmin("door", x0, 0.11, 0.28, x1, 2.09, 0.3, "wood_paint", 0.01)
        k.box("handle", s * 0.045, 1.15, 0.31, 0.016, 0.2, 0.02, "brass", 0.006)


def alarm_clock_01(k):
    k.cylax("body", 0, 0.075, 0, 0.062, 0.04, "wood_paint_blue", "z", seg=32, bev=0.008)
    k.cylax("face", 0, 0.075, 0.021, 0.052, 0.004, "ceramic", "z", seg=32)
    for s in (-1, 1):
        k.ball("bell", s * 0.04, 0.135, 0, 0.026, "brass", (1, 0.7, 1))
        k.ball("foot", s * 0.04, 0.01, 0, 0.01, "brass")
    k.box("hand", 0, 0.09, 0.024, 0.004, 0.032, 0.002, "plastic_black", 0.0, 1)
    k.box("hand", 0.012, 0.075, 0.024, 0.024, 0.004, 0.002, "plastic_black", 0.0, 1)


def standing_picture_frame_01(k):
    _photo(k, "wood", "fabric_blue")


def standing_picture_frame_02(k):
    _photo(k, "wood_paint", "fabric_green")


def _photo(k, key, bg):
    parts = [k.bmin("frame", -0.075, 0, -0.008, 0.075, 0.2, 0.008, key, 0.006)]
    parts.append(k.bmin("photo", -0.058, 0.018, 0.0075, 0.058, 0.182, 0.0095, bg, 0.0, 1))
    parts.append(k.cylax("face", 0, 0.1, 0.0098, 0.028, 0.001, "fabric_rose", "z", ry=0.034, bev=0))
    k.rot_all(parts, "x", -0.15, (0, 0, 0))
    leg = k.box("stand", 0, 0.08, -0.04, 0.03, 0.16, 0.006, key, 0.002, 1)
    k.rot(leg, "x", 0.35, (0, 0.15, -0.03))


def Rockingchair_01(k):
    """honey wood rocking chair (0.62 x 1.0 x 0.84, seat 0.45)."""
    W = "wood"
    for x in (-0.26, 0.26):
        pts = [(x, 0.03 + 0.12 * (z / 0.42) ** 2, z) for z in [-0.42 + i * 0.07 for i in range(13)]]
        k.tube("rocker", pts, 0.02, W, 8)
        for z in (-0.2, 0.2):
            k.tube("leg", [(x, 0.03 + 0.12 * (z / 0.42) ** 2, z), (x * 0.95, 0.43, z)], 0.017, W, 8)
        k.tube("arm", [(x * 1.1, 0.66, -0.27), (x * 1.1, 0.64, 0.2)], 0.018, W, 8)
        k.tube("arm_post", [(x * 0.97, 0.43, 0.18), (x * 1.1, 0.64, 0.2)], 0.014, W, 6)
    k.bmin("seat", -0.27, 0.41, -0.24, 0.27, 0.45, 0.24, W, 0.012)
    k.soft("cushion", 0, 0.47, 0.0, 0.46, 0.05, 0.42, "fabric_rose", 0.02)
    tops = []
    for x in (-0.25, 0.25):
        tops.append(k.tube("post", [(x, 0.43, -0.23), (x, 0.98, -0.36)], 0.018, W, 8))
    k.tube("crest", [(-0.25, 0.97, -0.358), (0.25, 0.97, -0.358)], 0.022, W, 8)
    for i in range(5):
        x = -0.16 + i * 0.08
        k.tube("spindle", [(x, 0.45, -0.235), (x, 0.96, -0.355)], 0.008, W, 6)


def vintage_suitcase(k):
    """two suitcases side by side: vintage_suitcase_01 (blue, Davi's) and _02 (brown)."""
    for name, x, w, h, d, key in (("vintage_suitcase_01", -0.42, 0.72, 0.5, 0.22, "fabric_blue"), ("vintage_suitcase_02", 0.42, 0.62, 0.42, 0.2, "terracotta")):
        k.box(name + "_body", x, h / 2, 0, w, h, d, key, 0.03, 4)
        k.bmin(name + "_band", x - w / 2 - 0.002, 0.04, -d / 2 - 0.002, x + w / 2 + 0.002, 0.06, d / 2 + 0.002, "wood_dark", 0.004)
        k.tube(name + "_handle", [(x - 0.07, h, 0), (x - 0.06, h + 0.045, 0), (x + 0.06, h + 0.045, 0), (x + 0.07, h, 0)], 0.011, "wood_dark", 8)
        for sx in (-1, 1):
            k.bmin(name + "_latch", x + sx * 0.18 - 0.02, h - 0.06, d / 2, x + sx * 0.18 + 0.02, h - 0.02, d / 2 + 0.008, "brass", 0.003)


def ClassicConsole_01(k):
    """low hall console: cream body, honey top and drawers (1.0 x 0.62 x 0.4)."""
    k.legs((-0.45, 0.45), (-0.16, 0.16), 0.12, 0.016, 0.022, "wood")
    k.bmin("body", -0.5, 0.12, -0.2, 0.5, 0.6, 0.18, "wood_paint", 0.012)
    k.bmin("top", -0.51, 0.6, -0.205, 0.51, 0.62, 0.205, "wood", 0.008)
    for s in (-1, 1):
        x0, x1 = sorted((s * 0.48, s * 0.01))
        k.bmin("drawer", x0, 0.15, 0.18, x1, 0.57, 0.195, "wood", 0.008)
        k.cylax("knob", (x0 + x1) / 2, 0.47, 0.203, 0.016, 0.02, "brass", "z")


# ====================================================================== varanda / sótão


def potted_plant_02(k):
    """round bush in a cream pot (0.85 tall, also the knock-off-able 'pot' prop)."""
    k.lathe("pot", [(0.0, 0.0), (0.12, 0.0), (0.16, 0.26), (0.175, 0.28), (0.175, 0.3), (0.0, 0.3)], "ceramic", seg=28)
    leaves = [k.ball("leaf", x, y, z, r, "leaves", (1, 0.9, 1)) for x, y, z, r in ((0, 0.55, 0, 0.27), (0.17, 0.48, 0.06, 0.17), (-0.15, 0.5, -0.06, 0.17), (0.04, 0.68, -0.08, 0.15), (-0.06, 0.62, 0.15, 0.14))]
    k.join(leaves, "leaves")


def planter_box_01(k):
    k.bmin("box", -0.45, 0, -0.2, 0.45, 0.3, 0.2, "wood_paint_green", 0.012)
    k.bmin("soil", -0.43, 0.27, -0.18, 0.43, 0.29, 0.18, "soil", 0.0, 1)
    leaves = [k.ball("leaf", x, 0.33, z, 0.1 + 0.02 * (i % 2), "leaves", (1, 0.8, 1)) for i, (x, z) in enumerate(((-0.33, 0.0), (-0.16, 0.05), (0.0, -0.04), (0.16, 0.05), (0.33, -0.02)))]
    k.join(leaves, "leaves")


def outdoor_table_chair_set_01(k):
    """bistro table at the origin and two chairs at z = +-0.62 facing it (0.78 x 0.86 x 1.7)."""
    M = "metal_dark"
    k.cylax("top", 0, 0.715, 0, 0.35, 0.03, "wood", "y", seg=40, bev=0.006)
    k.cyl("pole", 0, 0.03, 0, 0.022, 0.022, 0.67, M, 10)
    k.cylax("foot", 0, 0.015, 0, 0.2, 0.03, M, "y", seg=32)
    for s in (-1, 1):
        zc = s * 0.62
        k.bmin("seat", -0.2, 0.43, zc - 0.2, 0.2, 0.46, zc + 0.2, "wood", 0.008)
        for x in (-0.17, 0.17):
            for dz in (-0.17, 0.17):
                k.tube("leg", [(x, 0.0, zc + dz), (x, 0.43, zc + dz)], 0.011, M, 6)
            k.tube("back_post", [(x, 0.45, zc + s * 0.19), (x, 0.86, zc + s * 0.23)], 0.011, M, 6)
        for y in (0.62, 0.8):
            k.bmin("back_slat", -0.19, y, zc + s * (0.18 + (y - 0.45) * 0.1) - 0.01, 0.19, y + 0.05, zc + s * (0.18 + (y - 0.45) * 0.1) + 0.01, "wood", 0.006)


def treasure_chest(k):
    """steamer chest (1.0 x 0.62 x 0.55); the lid is one object (*lid) that house.gd hinges open."""
    k.bmin("body", -0.5, 0, -0.275, 0.5, 0.42, 0.275, "wood", 0.012)
    for x in (-0.36, 0.36):
        k.bmin("strap", x - 0.025, -0.001, -0.279, x + 0.025, 0.42, 0.279, "brass", 0.004)
    lid = [k.bmin("lid", -0.5, 0.42, -0.275, 0.5, 0.62, 0.275, "wood", 0.08, 5)]
    for x in (-0.36, 0.36):
        lid.append(k.bmin("lid_strap", x - 0.025, 0.43, -0.279, x + 0.025, 0.6, 0.279, "brass", 0.02, 3))
    lid.append(k.box("lid_latch", 0, 0.42, 0.281, 0.07, 0.09, 0.014, "brass", 0.005))
    k.join(lid, "lid")


def wheelchair_01(k):
    """old wheelchair (0.66 x 1.0 x 0.8)."""
    M = "chrome"
    for s in (-1, 1):
        x = s * 0.3
        k.ring("wheel", x, 0.3, -0.06, 0.29, 0.014, "rubber", "x", 40)
        k.ring("rim", x - s * 0.02, 0.3, -0.06, 0.25, 0.006, M, "x", 32)
        k.cylax("hub", x, 0.3, -0.06, 0.03, 0.05, M, "x")
        k.ring("caster", s * 0.22, 0.06, 0.3, 0.055, 0.012, "rubber", "x", 20)
        k.tube("frame", [(s * 0.22, 0.12, 0.3), (s * 0.22, 0.46, 0.25), (s * 0.22, 0.46, -0.2), (s * 0.22, 1.0, -0.26), (s * 0.22, 1.0, -0.36)], 0.012, M, 6)
        k.tube("arm", [(s * 0.24, 0.46, 0.18), (s * 0.24, 0.68, 0.16), (s * 0.24, 0.68, -0.18)], 0.011, M, 6)
        k.tube("footrest", [(s * 0.2, 0.46, 0.25), (s * 0.16, 0.12, 0.4)], 0.01, M, 6)
        k.bmin("foot_plate", s * 0.2 - 0.07, 0.1, 0.35, s * 0.2 + 0.07, 0.115, 0.45, "metal_dark", 0.004)
    k.bmin("seat", -0.21, 0.44, -0.2, 0.21, 0.47, 0.24, "plastic_black", 0.01)
    k.bmin("back", -0.21, 0.5, -0.25, 0.21, 0.92, -0.23, "plastic_black", 0.008)


def spinning_wheel_01(k):
    W = "wood"
    bench = k.box("bench", 0, 0.4, 0.0, 0.18, 0.06, 0.9, W, 0.012)
    k.rot(bench, "x", -0.12, (0, 0.4, 0))
    for x, z in ((-0.08, -0.38), (0.08, -0.38), (0.0, 0.38)):
        k.tube("leg", [(x * 2.0, 0.0, z * 1.1), (x, 0.4 + (0.05 if z < 0 else -0.05), z)], 0.018, W, 8)
    for x in (-0.06, 0.06):
        k.tube("upright", [(x, 0.42, 0.22), (x, 0.66, 0.2)], 0.016, W, 8)
    k.ring("wheel", 0, 0.62, 0.2, 0.3, 0.018, W, "x", 40)
    for i in range(8):
        a = i / 8 * 2 * PI
        k.tube("spoke", [(0, 0.62, 0.2), (0, 0.62 + math.cos(a) * 0.29, 0.2 + math.sin(a) * 0.29)], 0.006, W, 5)
    k.cylax("hub", 0, 0.62, 0.2, 0.035, 0.16, W, "x")
    k.tube("maiden", [(0, 0.42, -0.3), (0, 0.72, -0.32)], 0.016, W, 8)
    k.cylax("bobbin", 0, 0.72, -0.32, 0.03, 0.14, "hessian", "x")
    k.bmin("treadle", -0.12, 0.02, 0.05, 0.12, 0.04, 0.3, W, 0.006)


def marble_bust_01(k):
    M = "ceramic"
    k.lathe("plinth", [(0.0, 0.0), (0.1, 0.0), (0.1, 0.03), (0.07, 0.05), (0.05, 0.1), (0.0, 0.1)], M, seg=24)
    k.soft("shoulders", 0, 0.17, 0.0, 0.26, 0.14, 0.15, M, 0.03)
    k.cyl("neck", 0, 0.2, 0.0, 0.04, 0.036, 0.1, M, 16)
    k.ball("head", 0, 0.37, 0.01, 0.075, M, (0.9, 1.15, 1))
    k.ball("hair", 0, 0.405, -0.012, 0.072, M, (0.95, 0.8, 1))
    k.ball("nose", 0, 0.37, 0.085, 0.012, M, (0.7, 1.4, 1))


def Lantern_01(k):
    M = "metal_dark"
    k.cylax("base", 0, 0.01, 0, 0.05, 0.02, M, "y")
    k.cyl("glass", 0, 0.02, 0, 0.04, 0.04, 0.15, "glass", 20)
    k.cyl("candle", 0, 0.02, 0, 0.015, 0.015, 0.07, "paper", 12)
    for i in range(4):
        a = i / 4 * 2 * PI + PI / 4
        k.tube("post", [(math.cos(a) * 0.045, 0.02, math.sin(a) * 0.045), (math.cos(a) * 0.045, 0.17, math.sin(a) * 0.045)], 0.004, M, 4)
    k.lathe("roof", [(0.0, 0.215), (0.012, 0.21), (0.055, 0.17), (0.0, 0.17)], M, seg=20)
    k.ring("handle", 0, 0.235, 0, 0.022, 0.003, M, "z", 16)


def ceramic_vase_02(k):
    k.lathe("vase", [(0.0, 0.0), (0.05, 0.0), (0.08, 0.06), (0.09, 0.14), (0.06, 0.22), (0.04, 0.27), (0.05, 0.3), (0.0, 0.3)], "fabric_rose", seg=28)


def book_encyclopedia_set_01(k):
    """twenty volumes standing in a row along x (book01..book20)."""
    for i in range(20):
        x = -0.28 + i * 0.03
        name = f"book_encyclopedia_set_01_book{str(i + 1).zfill(2)}"
        cover = k.box(name + "_cover", x, 0.1185, 0, 0.028, 0.237, 0.163, BOOK_KEYS[i % 4], 0.003, 1)
        pages = k.bmin(name + "_pages", x - 0.011, 0.008, -0.075, x + 0.011, 0.229, 0.0825, "paper", 0.0, 1)
        k.join([cover, pages], name)


# ====================================================================== exterior


def street_lamp_01(k):
    """cast iron post lantern, head centred over the base at ~4.4 (env.gd's street_lamp_head)."""
    M = "metal_dark"
    k.lathe("base", [(0.0, 0.0), (0.16, 0.0), (0.16, 0.05), (0.1, 0.12), (0.07, 0.5), (0.06, 0.55), (0.0, 0.55)], M, seg=24)
    k.cyl("pole", 0, 0.55, 0, 0.05, 0.04, 3.45, M, 16)
    k.lathe("cup", [(0.0, 4.0), (0.06, 4.0), (0.14, 4.15), (0.15, 4.17), (0.0, 4.17)], M, seg=24)
    k.cyl("glass", 0, 4.17, 0, 0.11, 0.15, 0.25, "bulb", 24)
    k.lathe("cap", [(0.2, 4.42), (0.05, 4.53), (0.02, 4.58), (0.0, 4.6)], M, seg=24, cap=False)


def modular_electricity_poles(k):
    """wooden utility pole (parts preset_01_*): cross arm at 5.62 along z, insulators at z +-0.55, lower bracket at 4.5."""
    W = "wood_worn"
    k.cyl("preset_01_pole", 0, 0, 0, 0.14, 0.11, 7.0, W, 16)
    k.bmin("preset_01_arm", -0.06, 5.5, -0.95, 0.06, 5.62, 0.95, W, 0.01)
    for z in (-0.85, -0.55, 0.55, 0.85):
        k.cyl("preset_01_insulator", 0, 5.62, z, 0.03, 0.022, 0.09, "ceramic", 12)
    for s in (-1, 1):
        k.tube("preset_01_brace", [(0, 5.0, 0.0), (0, 5.5, s * 0.5)], 0.02, "iron", 6)
    k.bmin("preset_01_bracket", -0.05, 4.38, -0.18, 0.05, 4.44, 0.18, W, 0.008)
    k.cyl("preset_01_insulator", 0, 4.44, 0.16, 0.03, 0.022, 0.08, "ceramic", 12)


def covered_car(k):
    """a car under a dust sheet (1.76 x 1.39 x 4.3), wheels peeking out."""
    for x in (-0.76, 0.76):
        for z in (-1.35, 1.35):
            k.cylax("tyre", x, 0.3, z, 0.3, 0.2, "rubber", "x")
    k.soft("body", 0, 0.52, 0.0, 1.76, 0.72, 4.3, "dust_sheet", 0.2)
    k.soft("cabin", 0, 1.06, -0.2, 1.42, 0.62, 2.1, "dust_sheet", 0.2)
    k.soft("hem", 0, 0.22, 0.0, 1.8, 0.16, 4.2, "dust_sheet", 0.06)


def metal_trash_can(k):
    """two bins: metal_trash_can (clean) at x -0.45 and metal_trash_can_rust at x +0.45."""
    for name, x, key in (("metal_trash_can", -0.45, "metal_dark"), ("metal_trash_can_rust", 0.45, "iron")):
        k.lathe(name + "_body", [(0.0, 0.0), (0.22, 0.0), (0.25, 0.74), (0.26, 0.75), (0.0, 0.75)], key, pos=(x, 0, 0), seg=28)
        for y in (0.2, 0.45):
            k.ring(name + "_rib", x, y, 0, 0.232 + y * 0.04, 0.01, key, "y", 28)
        k.lathe(name + "_lid", [(0.27, 0.75), (0.27, 0.77), (0.2, 0.81), (0.0, 0.83)], key, pos=(x, 0, 0), seg=28)
        k.tube(name + "_handle", [(x - 0.06, 0.82, 0), (x - 0.05, 0.86, 0), (x + 0.05, 0.86, 0), (x + 0.06, 0.82, 0)], 0.01, key, 6)


def fire_hydrant(k):
    # TODO(materials.json): "paint_red" would be the proper colour; terracotta is the closest red now
    R = "terracotta"
    k.lathe("fire_hydrant_aged", [(0.0, 0.0), (0.15, 0.0), (0.15, 0.04), (0.1, 0.07), (0.1, 0.55), (0.12, 0.58), (0.12, 0.61), (0.09, 0.63), (0.06, 0.72), (0.02, 0.75), (0.0, 0.75)], R, seg=24)
    k.cylax("fire_hydrant_cap_01_aged", 0.13, 0.45, 0, 0.045, 0.07, R, "x")
    k.cylax("fire_hydrant_cap_02_aged", -0.13, 0.45, 0, 0.045, 0.07, R, "x")
    k.cylax("fire_hydrant_cap_03_aged", 0, 0.38, 0.13, 0.06, 0.07, R, "z")
    k.tube("fire_hydrant_chain_aged", [(0.165, 0.43, 0.02), (0.15, 0.36, 0.06), (0.06, 0.34, 0.15)], 0.004, "iron", 4)


def garden_gnome(k):
    k.ball("boots", 0, 0.03, 0.02, 0.07, "plastic_black", (1.3, 0.5, 1))
    k.lathe("body", [(0.0, 0.03), (0.09, 0.03), (0.1, 0.12), (0.075, 0.26), (0.0, 0.28)], "fabric_blue", seg=24)
    k.ball("beard", 0, 0.25, 0.05, 0.06, "paper", (1, 1.2, 0.8))
    k.ball("face", 0, 0.32, 0.02, 0.05, "fabric_rose")
    k.ball("nose", 0, 0.31, 0.07, 0.015, "fabric_rose")
    k.lathe("hat", [(0.0, 0.34), (0.062, 0.34), (0.045, 0.42), (0.012, 0.5), (0.0, 0.52)], "fabric_red", seg=20)


def dead_tree_trunk_02(k):
    """fallen log along x (4.0 m)."""
    k.cylax("log", 0, 0.3, 0, 0.3, 4.0, "bark", "x", seg=20, bev=0.02)
    for s in (-1, 1):
        k.cylax("end", s * 2.0, 0.3, 0, 0.27, 0.03, "wood_worn", "x", seg=20)
    k.tube("branch", [(0.6, 0.5, 0.15), (0.9, 0.85, 0.35), (1.1, 1.0, 0.5)], 0.06, "bark", 8)


def shrub_02(k):
    """four round shrubs (shrub_02_a..d), each ~1 m, side by side."""
    r = lib.rng(3)
    for i, part in enumerate(("shrub_02_a", "shrub_02_b", "shrub_02_c", "shrub_02_d")):
        cx = -3.0 + i * 2.0
        blobs = [k.ball(part + "_blob", cx, 0.45, 0, 0.45, "leaves", (1.1, 0.95, 1))]
        for _ in range(4 + i % 2):
            a = r.uniform(0, 2 * PI)
            rr = r.uniform(0.25, 0.35)
            blobs.append(k.ball(part + "_blob", cx + math.cos(a) * 0.35, r.uniform(0.3, 0.6), math.sin(a) * 0.35, rr, "leaves", (1, 0.9, 1)))
        k.join(blobs, part)


def shrub_04(k):
    """a weed tuft (0.5 x 0.22 x 0.15)."""
    blades = []
    for i, (x, z, ax, az, h) in enumerate(((0, 0, 0, 0, 0.22), (-0.12, 0.02, -0.5, 0.1, 0.18), (0.12, -0.02, 0.5, -0.1, 0.19), (-0.2, -0.03, -0.8, 0.0, 0.14), (0.2, 0.03, 0.8, 0.1, 0.15))):
        b = k.lathe("blade", [(0.02, 0.0), (0.0, h)], "leaves", pos=(x, 0, z), seg=5, cap=True)
        k.rot(b, "z", -ax * 0.5, (x, 0, z))
        k.rot(b, "x", az, (x, 0, z))
        blades.append(b)
    k.join(blades, "tuft")


# ====================================================================== registry

KIT = {name: fn for name, fn in globals().items() if callable(fn) and not name.startswith("_") and name not in ("Kit", "build") and fn.__module__ == __name__}


def build(mid, coll):
    """build a kit piece in `coll` (must be visible: modifiers get applied); returns its mesh objects."""
    k = Kit(coll, mid)
    KIT[mid](k)
    bpy.context.view_layer.update()
    return [o for o in k.objs if o.type == "MESH"]
