"""Everything outside: a house in the countryside. Lawn and fenced yard (shed, clothesline, vegetable
beds, woodpile, empty doghouse), a dirt road to the gate, a lamp post, dead trees and the woods all
around, low hills far away. No street, no neighbours."""
import math

import bmesh
import bpy
from mathutils import Vector

import house_custom as C
import house_shell
import lib
from lib import REG, Geo, gv

PI = math.pi
HALF = PI / 2
# the dirt road from the gate (its grass is cut out) and how far the dirt surfaces stand above the lawn
ROAD_X0, ROAD_X1, ROAD_Z1 = 5.0, 8.0, -5.75
DIRT_UP = 0.03


def ph(coll, mid, pos, yaw=0.0, **kw):
    return lib.place_ph(mid, coll, pos, yaw, **kw)


def build(L, coll):
    ty = L["TERRAIN_Y"]
    ground(coll, ty)
    dirt_road(coll, ty)
    hills(coll, ty)
    fence(coll, ty)
    mailbox(coll, 4.65, ty, -5.95)
    porch_lamp(coll)
    lamp_post(coll, ty)
    trees(coll, ty)
    woods(coll, ty)
    props(coll, ty)
    yard(coll, ty)


# ---------------------------------------------------------------------- ground


def ground(coll, ty):
    g = Geo("terrain")
    big = dict(x0=-140, x1=150, z0=-140, z1=150)
    # no grass under the house, the dirt band around it or the dirt road: nothing coplanar to flicker
    holes = [dict(x0=-0.6, x1=12.6, z0=-0.6, z1=13.6), dict(x0=ROAD_X0, x1=ROAD_X1, z0=-140, z1=ROAD_Z1)]
    for r in house_shell.rect_minus(big, holes):
        g.box(r["x0"], ty - 0.3, r["z0"], r["x1"], ty, r["z1"], "grass", skip=("ny",))
    # the house sits in the ground: a dirt band around the foundation (house + back wing), 3 cm proud
    # of the lawn so its edge never z-fights with the grass
    for (x0, z0, x1, z1) in ((-0.6, -0.6, 12.6, -0.1), (-0.6, 13.1, 12.6, 13.6), (-0.6, -0.1, -0.1, 13.1), (12.1, -0.1, 12.6, 13.1)):
        g.box(x0, ty - 0.29, z0, x1, ty + DIRT_UP, z1, "dirt", skip=("ny",))
    g.build(coll)
    # ground collider with a hole over the basement footprint, so the cat can walk down the cellar stairs
    for (x0, z0, x1, z1) in ((-140, -140, -0.1, 150), (12.1, -140, 150, 150), (-0.1, -140, 12.1, -0.1), (-0.1, 10.1, 12.1, 150)):
        REG.collider(x0, ty - 0.3, z0, x1, ty, z1, tag="terrain", cam=True)
    # stepping stones to the porch
    r = lib.rng(3)
    z = -6.4
    while z < -2.9:
        C.rbox(f"stone_{z:.2f}", coll, 6.45 + r.uniform(-0.06, 0.06), ty + 0.02, z + 0.21, 0.82 + r.uniform(-0.05, 0.05), 0.05, 0.4, "sidewalk", 0.02, 2, yaw=r.uniform(-0.06, 0.06))
        z += 0.55


def dirt_road(coll, ty):
    """a dirt road from the gate out to the main road, far away; two worn wheel tracks."""
    g = Geo("dirt_road")
    g.box(ROAD_X0, ty - 0.29, -140, ROAD_X1, ty + DIRT_UP, ROAD_Z1, "dirt", skip=("ny",))
    g.build(coll)
    # wheel tracks a good centimetre above the road (no bottom face, nothing coplanar)
    tr = Geo("road_tracks")
    for x in (5.75, 7.15):
        tr.box(x - 0.18, ty + DIRT_UP, -140, x + 0.18, ty + DIRT_UP + 0.014, -6.0, "dirt", skip=("ny",))
    tr.build(coll)


def hills(coll, ty):
    """low rolling hills on the horizon (flattened spheres half under the ground)."""
    r = lib.rng(41)
    for i, (x, z, sx, sz, h) in enumerate(((-95, 60, 70, 45, 14), (40, 125, 90, 40, 18), (120, 30, 50, 70, 12), (-110, -60, 60, 50, 11),
                                            (70, -115, 80, 40, 15), (-30, -125, 70, 35, 13), (125, -70, 45, 55, 10), (-120, 15, 40, 60, 9))):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=1.0)
        ob = bpy.context.active_object
        ob.name = f"hill_{i}"
        for c in ob.users_collection:
            c.objects.unlink(ob)
        coll.objects.link(ob)
        ob.scale = (sx, sz, h)
        ob.location = gv(x, ty - h * 0.55 + r.uniform(-1, 1), z)
        lib.set_material(ob, "grass")
        lib.world_uv_object(ob, 4.0)
        for poly in ob.data.polygons:
            poly.use_smooth = True


# ---------------------------------------------------------------------- fence


def picket_run(g, x0, x1, z, ty, along="x"):
    """white picket fence along x (or z) between x0 and x1 at the given line."""
    h = 1.0
    w = 0.075
    gap = 0.155
    rails = ((ty + 0.25, ty + 0.31), (ty + 0.72, ty + 0.78))
    for (ya, yb) in rails:
        if along == "x":
            g.box(x0, ya, z - 0.035, x1, yb, z - 0.01, "exterior_trim")
        else:
            g.box(z - 0.035, ya, x0, z - 0.01, yb, x1, "exterior_trim")
    s = x0
    i = 0
    while s < x1 - 0.02:
        tip = h + (0.02 if i % 2 else 0.0)
        a, b = s, s + w
        # pointed picket: front & back pentagons + sides
        if along == "x":
            def P(u, y, zz):
                return (u, y, zz)
            z0, z1 = z - 0.01, z + 0.012
        else:
            def P(u, y, zz):
                return (zz, y, u)
            z0, z1 = z - 0.01, z + 0.012
        top = ty + tip
        mid = (a + b) / 2
        for zz, flip in ((z1, False), (z0, True)):
            pts = [P(a, ty, zz), P(b, ty, zz), P(b, top - 0.06, zz), P(mid, top, zz), P(a, top - 0.06, zz)]
            g.poly(list(reversed(pts)) if (flip ^ (along != "x")) else pts, "exterior_trim")
        for (u0, y0, u1, y1) in ((a, ty, a, top - 0.06), (b, top - 0.06, b, ty), (a, top - 0.06, mid, top), (mid, top, b, top - 0.06)):
            pts = [P(u0, y0, z0), P(u1, y1, z0), P(u1, y1, z1), P(u0, y0, z1)]
            n = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[0]))
            centre = Vector(P(mid, ty + 0.5, (z0 + z1) / 2))
            if n.dot(Vector(pts[0]) - centre) < 0:
                pts = list(reversed(pts))
            g.poly(pts, "exterior_trim")
        s += gap
        i += 1


def fence(coll, ty):
    g = Geo("fence")
    picket_run(g, -8.0, 5.6, -5.6, ty)
    picket_run(g, 7.3, 20.0, -5.6, ty)
    picket_run(g, -5.6, 20.0, -8.0, ty, along="z")
    picket_run(g, -5.6, 20.0, 20.0, ty, along="z")
    picket_run(g, -8.0, 20.0, 20.0, ty)
    g.build(coll)
    # the yard ends at the fence (ghosts pass, the cat does not); the gate gap is closed too: the cat
    # stays in the yard
    for (x0, z0, x1, z1) in ((-8.0, -5.65, 5.6, -5.55), (5.6, -5.65, 7.3, -5.55), (7.3, -5.65, 20.0, -5.55), (-8.05, -5.6, -7.95, 20.0), (19.95, -5.6, 20.05, 20.0), (-8.0, 19.95, 20.0, 20.05)):
        REG.collider(x0, ty, z0, x1, ty + 1.05, z1, tag="fence", cam=False)
    for x in (5.6, 7.3):
        C.rbox(f"gate_post_{x}", coll, x, ty + 0.6, -5.6, 0.12, 1.2, 0.12, "exterior_trim", 0.01, 2)
    # an old gate left ajar
    gate = Geo("gate")
    picket_run(gate, 0.0, 1.6, 0.0, 0.0)
    gob = gate.build(coll)
    gob.location = gv(5.66, ty, -5.6)
    gob.rotation_euler = (0, 0, -0.9)


def slope_normal(ridge, eave):
    """unit (x, y) normal, pointing up and out, of a roof slope from the ridge (x, y) down to the eave."""
    dx, dy = eave[0] - ridge[0], eave[1] - ridge[1]
    ln = math.hypot(dx, dy)
    nx, ny = -dy / ln, dx / ln
    if ny < 0:
        nx, ny = -nx, -ny
    return (nx, ny)


def roof_slab_collider(ridge, eave, za, zb, th):
    """an oriented box whose top face is the roof slope from the ridge (x, y) to the eave, over z za..zb."""
    nx, ny = slope_normal(ridge, eave)
    dx, dy = eave[0] - ridge[0], eave[1] - ridge[1]
    ln = math.hypot(dx, dy)
    th = max(th, 0.08)
    cxm = (ridge[0] + eave[0]) / 2 - nx * th / 2
    cym = (ridge[1] + eave[1]) / 2 - ny * th / 2
    REG.collider_obb((cxm, cym, (za + zb) / 2), (ln, th, zb - za), (dx / ln, dy / ln, 0.0), (nx, ny, 0.0), tag="roof", cam=True)


def mailbox(coll, x, ty, z):
    C.rbox("mailbox_post", coll, x, ty + 0.55, z, 0.09, 1.1, 0.09, "wood_worn", 0.01, 2)
    body = C.rbox("mailbox_box", coll, x, ty + 1.18, z, 0.22, 0.2, 0.45, "metal_painted", 0.05, 4)
    flag = C.rbox("mailbox_flag", coll, x + 0.12, ty + 1.3, z + 0.08, 0.01, 0.16, 0.05, "fabric_red", 0.003, 1)
    REG.collider(x - 0.12, ty, z - 0.24, x + 0.12, ty + 1.3, z + 0.24, tag="furniture")


def porch_lamp(coll):
    """wall lantern beside the front door (decorative light L18 in Godot)."""
    x, y, z = 7.15, 2.0, -0.12
    C.rbox("L18_bracket", coll, x, y, z + 0.02, 0.06, 0.12, 0.04, "metal_dark", 0.005, 1)
    lantern = C.smooth(lib.lathe("L18_lantern", coll, [(0.0, -0.12), (0.06, -0.12), (0.08, -0.05), (0.08, 0.1), (0.1, 0.12), (0.03, 0.18), (0.0, 0.2)], "metal_dark", pos=(x, y, z - 0.12), segments=6))
    glass = C.smooth(lib.lathe("L18_bulb", coll, [(0.0, -0.1), (0.07, -0.1), (0.07, 0.1), (0.0, 0.1)], "bulb", pos=(x, y, z - 0.12), segments=6))
    REG.nodes["porch_lamp"] = [x, y, z - 0.12]


# ---------------------------------------------------------------------- trees


def dead_tree(coll, name, x, ty, z, seed, height=6.5, trunk_r=0.28, spread=1.0, lean=0.0):
    r = lib.rng(seed)
    bm = bmesh.new()
    sk = bm.verts.layers.skin.verify()
    radii = []
    root = bm.verts.new((0, 0, -0.3))
    radii.append((root, trunk_r * 1.35))

    def grow(v0, p, d, length, rad, depth):
        n = max(2, int(length / 0.32))
        prev = v0
        cur = Vector(p)
        for i in range(n):
            jitter = Vector((r.uniform(-0.3, 0.3), r.uniform(-0.3, 0.3), r.uniform(-0.12, 0.2)))
            d = (d + jitter * 0.45).normalized()
            if depth < 3:
                d.z += 0.08  # reach for the sky
                d.normalize()
            cur = cur + d * (length / n)
            v = bm.verts.new(cur)
            bm.edges.new((prev, v))
            rr = rad * (1 - 0.55 * (i + 1) / n)
            radii.append((v, max(0.012, rr)))
            if depth > 0 and i > 0 and i < n - 1 and r.random() < 0.28:
                side = Vector((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(0.0, 0.8))).normalized()
                grow(v, cur, (d * 0.4 + side).normalized(), length * r.uniform(0.35, 0.6), rr * 0.6, depth - 1)
            prev = v
        if depth > 0:
            for _ in range(r.randint(2, 3)):
                side = Vector((r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(0.2, 1.0))).normalized()
                grow(prev, cur, (d + side * spread).normalized(), length * r.uniform(0.45, 0.7), max(0.012, rad * 0.45), depth - 1)

    # trunk
    trunk_len = height * 0.45
    d0 = Vector((lean, 0, 1)).normalized()
    grow(root, (0, 0, -0.3), d0, trunk_len, trunk_r, 4)
    # roots flaring into the ground
    for k in range(5):
        a = k / 5 * 2 * PI + r.uniform(-0.3, 0.3)
        v = bm.verts.new((math.cos(a) * 0.55, math.sin(a) * 0.55, -0.25))
        bm.edges.new((root, v))
        radii.append((v, trunk_r * 0.35))
    for v, rad in radii:
        v[sk].radius = (rad, rad)
    root[sk].use_root = True
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    lib.add_mod(ob, "SKIN", branch_smoothing=0.6, use_smooth_shade=True)
    lib.add_mod(ob, "SUBSURF", levels=1, render_levels=1)
    lib.apply_mods(ob)
    ob.location = gv(x, ty, z)
    ob.rotation_euler = (0, 0, r.uniform(0, 2 * PI))
    bpy.context.view_layer.update()
    lib.set_material(ob, "bark")
    lib.world_uv_object(ob, 1.0)
    for p in ob.data.polygons:
        p.use_smooth = True
    REG.collider(x - trunk_r, ty, z - trunk_r, x + trunk_r, ty + trunk_len * 0.8, z + trunk_r, tag="tree", cam=True)
    return ob


def trees(coll, ty):
    spots = [(-3.5, 4.0, 1, 6.5, 0.26), (-4.5, 12.0, 2, 7.5, 0.3), (15.5, 13.0, 3, 7.0, 0.3), (16.5, 3.0, 4, 6.0, 0.24),
             (-2.6, -3.2, 5, 5.0, 0.2), (24.0, -2.0, 6, 8.0, 0.32), (-14.0, -3.0, 7, 8.5, 0.34), (-11.0, 20.0, 8, 9.0, 0.36),
             (28.0, 18.0, 9, 9.0, 0.36), (6.0, 22.0, 10, 9.5, 0.38)]
    for i, (x, z, seed, h, rr) in enumerate(spots):
        dead_tree(coll, f"tree_{i}", x, ty, z, seed * 17, h, rr)
    # the old tree whose branches reach over the balcony railing
    dead_tree(coll, "tree_balcony", 13.8, ty, 1.4, 99, 9.0, 0.42, spread=1.2, lean=-0.25)
    # hedges / shrubs along the facade
    r = lib.rng(9)
    for i, (x, z) in enumerate(((0.8, -0.7), (2.4, -0.8), (3.8, -0.65), (8.6, -0.7), (10.4, -0.8), (11.6, -0.65), (-0.75, 3.0), (-0.75, 7.0), (12.75, 7.5), (-6.5, -4.6), (18.5, -4.5))):
        part = r.choice(["shrub_02_a", "shrub_02_b", "shrub_02_d"])
        ph(coll, "shrub_02", (x, ty, z), r.uniform(0, 2 * PI), parts=[part], fit=(None, r.uniform(0.8, 1.15), None), name=f"shrub_{i}")
    for i in range(14):
        x = r.uniform(-7, 19)
        z = r.uniform(-5, 16)
        if -0.8 < x < 12.8 and -2.2 < z < 10.8:
            continue
        ph(coll, "shrub_04", (x, ty, z), r.uniform(0, 2 * PI), scale=r.uniform(1.0, 1.8), name=f"weed_{i}")


# ---------------------------------------------------------------------- the woods


def woods(coll, ty):
    """dead trees all around the yard, thicker further out: a few grown meshes, many linked copies."""
    variants = []
    hidden = lib.collection("_tree_variants")
    for k in range(6):
        ob = dead_tree(hidden, f"wood_tree_v{k}", 0.0, ty, -400.0 - k * 10, 300 + k * 7, 7.5 + k * 0.6, 0.26 + 0.02 * k, spread=1.0 + 0.1 * k)
        # far away: a fifth of the polygons is plenty
        lib.add_mod(ob, "DECIMATE", ratio=0.2)
        lib.apply_mods(ob)
        variants.append(ob)
    # the variants were grown far away only to be copied: drop their trunk colliders
    REG.colliders[:] = [c for c in REG.colliders if not (c.get("tag") == "tree" and c["min"][2] < -390)]
    r = lib.rng(77)
    n = 0
    tries = 0
    while n < 90 and tries < 2000:
        tries += 1
        a = r.uniform(0, 2 * PI)
        dist = r.uniform(25.0, 75.0) ** 1.0
        x = 6.0 + math.cos(a) * dist
        z = 7.0 + math.sin(a) * dist * 0.9
        if -12 < x < 24 and -9 < z < 24:
            continue
        if 3.5 < x < 9.5 and z < -5:
            continue  # keep the dirt road clear
        src = r.choice(variants)
        ob = src.copy()
        ob.name = f"woods_{n}"
        coll.objects.link(ob)
        ob.location = gv(x, ty, z)
        ob.rotation_euler = (0, 0, r.uniform(0, 2 * PI))
        sc = r.uniform(0.8, 1.35)
        ob.scale = (sc, sc, sc)
        n += 1
    for ob in variants:
        for c in list(ob.users_collection):
            c.objects.unlink(ob)
        bpy.data.objects.remove(ob)


def lamp_post(coll, ty):
    """a wooden pole with a lamp by the gate: the only light outside at night (game light 13)."""
    x, z = 4.9, -5.0
    C.rbox("lamp_pole", coll, x, ty + 2.1, z, 0.16, 4.2, 0.16, "wood_worn", 0.01, 2)
    C.rbox("lamp_arm", coll, x + 0.35, ty + 4.05, z, 0.7, 0.07, 0.07, "wood_worn", 0.005, 1)
    shade = C.smooth(lib.lathe("lamp_shade", coll, [(0.0, 0.12), (0.06, 0.12), (0.2, 0.0), (0.19, -0.02), (0.0, 0.09)], "metal_painted", pos=(x + 0.62, ty + 3.98, z), segments=16))
    bulb = C.smooth(lib.lathe("lamp_bulb", coll, [(0.0, 0.0), (0.05, 0.02), (0.05, 0.07), (0.0, 0.09)], "bulb", pos=(x + 0.62, ty + 3.9, z), segments=12))
    REG.collider(x - 0.08, ty, z - 0.08, x + 0.08, ty + 4.2, z + 0.08, tag="post")
    REG.nodes["street_lamp_head"] = [x + 0.62, ty + 3.95, z]


# ---------------------------------------------------------------------- props


def props(coll, ty):
    ph(coll, "garden_gnome", (2.6, ty, -2.7), PI + 0.3, fit=(None, 0.45, None), name="GNOME")
    ph(coll, "dead_tree_trunk_02", (-5.0, ty, 8.0), 0.8, scale=1.0, name="fallen_log")


# ---------------------------------------------------------------------- the yard


def yard(coll, ty):
    shed(coll, ty, 16.0, 16.2)
    clothesline_yard(coll, ty)
    veg_beds(coll, ty)
    woodpile(coll, ty)
    doghouse(coll, ty, 9.0, 16.6)


def shed(coll, ty, cx, cz):
    """a small wooden tool shed, door opening toward the house (-z); the cat hides inside."""
    g = Geo("shed")
    w, d, h, t = 2.8, 2.4, 2.1, 0.08
    x0, x1, z0, z1 = cx - w / 2, cx + w / 2, cz - d / 2, cz + d / 2
    # no two boxes share an outer plane: the side walls run the full depth, the back and front walls fit
    # between them, and the floor slab sits inside the walls (plus the threshold in the doorway)
    g.box(x0 + t, ty, z0 + t, x1 - t, ty + 0.06, z1 - t, "wood_worn")
    g.box(cx - 0.5, ty, z0, cx + 0.5, ty + 0.06, z0 + t, "wood_worn")
    g.box(x0 + t, ty, z1 - t, x1 - t, ty + h, z1, "wood_worn")
    g.box(x0, ty, z0, x0 + t, ty + h, z1, "wood_worn")
    g.box(x1 - t, ty, z0, x1, ty + h, z1, "wood_worn")
    g.box(x0 + t, ty, z0, cx - 0.5, ty + h, z0 + t, "wood_worn")
    g.box(cx + 0.5, ty, z0, x1 - t, ty + h, z0 + t, "wood_worn")
    g.box(cx - 0.5, ty + 1.75, z0, cx + 0.5, ty + h, z0 + t, "wood_worn")
    g.build(coll)
    roof = Geo("shed_roof")
    rh = 0.7
    for side in (-1, 1):
        xa = cx
        xb = cx + side * (w / 2 + 0.25)
        pts = [(xa, ty + h + rh, z0 - 0.25), (xb, ty + h - 0.1, z0 - 0.25), (xb, ty + h - 0.1, z1 + 0.25), (xa, ty + h + rh, z1 + 0.25)]
        n = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[0]))
        if n.y < 0:
            pts = list(reversed(pts))
        roof.poly(pts, "roof")
    for zz, sgn in ((z0, -1), (z1, 1)):
        tri = [(x0, ty + h, zz), (x1, ty + h, zz), (cx, ty + h + rh, zz)]
        roof.poly(tri if sgn > 0 else list(reversed(tri)), "wood_worn")
    roof.build(coll)
    for (a, b, c, e) in ((x0, z1 - t, x1, z1), (x0, z0, x0 + t, z1), (x1 - t, z0, x1, z1), (x0, z0, cx - 0.5, z0 + t), (cx + 0.5, z0, x1, z0 + t)):
        REG.collider(a, ty, b, c, ty + h, e, tag="wall", cam=True)
    # roof colliders: one slab under each slope (the cat walks on the roof it sees)
    for side in (-1, 1):
        roof_slab_collider((cx, ty + h + rh), (cx + side * (w / 2 + 0.25), ty + h - 0.1), z0 - 0.25, z1 + 0.25, 0.1)
    # a workbench and a few things inside
    C.rbox("shed_bench", coll, cx + 0.6, ty + 0.43, z1 - 0.4, 1.3, 0.74, 0.55, "wood_worn", 0.01, 2)
    REG.collider(cx + 0.0, ty, z1 - 0.7, cx + 1.25, ty + 0.8, z1 - 0.1, tag="furniture")
    ph(coll, "hatchet", (cx + 0.9, ty + 0.8, z1 - 0.4), 0.5, fit=(None, None, 0.4), name="shed_hatchet")
    ph(coll, "oil_tin", (cx + 0.3, ty + 0.8, z1 - 0.35), 0.2, fit=(None, 0.22, None), name="shed_oil")


def clothesline_yard(coll, ty):
    for x in (1.0, 6.0):
        C.rbox(f"cl_post_{x}", coll, x, ty + 0.95, 16.0, 0.08, 1.9, 0.08, "wood_worn", 0.005, 1)
        C.rbox(f"cl_bar_{x}", coll, x, ty + 1.85, 16.0, 0.06, 0.06, 0.7, "wood_worn", 0.005, 1)
        REG.collider(x - 0.05, ty, 15.95, x + 0.05, ty + 1.9, 16.05, tag="post")
    for dz in (-0.25, 0.25):
        pts = []
        for k in range(11):
            t = k / 10
            pts.append((1.0 + 5.0 * t, ty + 1.85 - 0.18 * 4 * t * (1 - t), 16.0 + dz))
        lib.tube(f"cl_line_{dz}", coll, pts, 0.006, "plastic_white", segments=5)
    # two sheets left out on the line: they sway in the night wind
    for i, (xa, dz, key) in enumerate(((1.6, -0.25, "sheet"), (3.9, 0.25, "curtain_cream"))):
        g = Geo(f"YARD_SHEET_{i}")
        g.box(xa, ty + 0.75, 16.0 + dz - 0.005, xa + 1.3, ty + 1.8, 16.0 + dz + 0.005, key)
        g.build(coll)


def veg_beds(coll, ty):
    r = lib.rng(55)
    for i, (x0, z0) in enumerate(((-4.2, 14.4), (-4.2, 16.2), (-1.8, 14.4))):
        g = Geo(f"veg_bed_{i}")
        g.box(x0, ty, z0, x0 + 1.9, ty + 0.3, z0 + 1.2, "wood_worn")
        g.box(x0 + 0.06, ty + 0.3, z0 + 0.06, x0 + 1.84, ty + 0.32, z0 + 1.14, "dirt")
        g.build(coll)
        REG.collider(x0, ty, z0, x0 + 1.9, ty + 0.32, z0 + 1.2, tag="furniture")
        for k in range(6):
            ph(coll, "shrub_04", (x0 + 0.3 + (k % 3) * 0.6, ty + 0.3, z0 + 0.35 + (k // 3) * 0.5), r.uniform(0, 2 * PI), scale=r.uniform(0.35, 0.5), name=f"veg_{i}_{k}")


def woodpile(coll, ty):
    """firewood stacked against two stakes, west of the dining room; the cat squeezes in behind it."""
    r = lib.rng(61)
    x0, x1 = -2.3, -1.3
    for layer in range(5):
        y = ty + 0.09 + layer * 0.16
        z = 10.6
        while z < 12.6:
            lib.tube(f"log_{layer}_{z:.2f}", coll, [(x0 + r.uniform(-0.05, 0.05), y, z), (x1 + r.uniform(-0.05, 0.05), y, z)], 0.075 + r.uniform(-0.01, 0.015), "bark", segments=8)
            z += 0.17
    for z in (10.5, 12.7):
        C.rbox(f"pile_stake_{z}", coll, -1.8, ty + 0.55, z, 0.06, 1.1, 0.06, "wood_worn", 0.005, 1)
    REG.collider(x0, ty, 10.5, x1, ty + 0.85, 12.7, tag="furniture")


def doghouse(coll, ty, cx, cz):
    g = Geo("doghouse")
    w, d, h = 0.9, 1.0, 0.7
    x0, x1, z0, z1 = cx - w / 2, cx + w / 2, cz - d / 2, cz + d / 2
    # side walls the full depth, back and front walls between them (no shared outer planes)
    g.box(x0 + 0.04, ty, z1 - 0.04, x1 - 0.04, ty + h, z1, "wood_paint")
    g.box(x0, ty, z0, x0 + 0.04, ty + h, z1, "wood_paint")
    g.box(x1 - 0.04, ty, z0, x1, ty + h, z1, "wood_paint")
    g.box(x0 + 0.04, ty, z0, cx - 0.2, ty + h, z0 + 0.04, "wood_paint")
    g.box(cx + 0.2, ty, z0, x1 - 0.04, ty + h, z0 + 0.04, "wood_paint")
    g.box(cx - 0.2, ty + 0.45, z0, cx + 0.2, ty + h, z0 + 0.04, "wood_paint")
    ridge, eave, th = ty + h + 0.35, ty + h - 0.05, 0.035
    roof = Geo("doghouse_roof")
    for side in (-1, 1):
        xb = cx + side * (w / 2 + 0.08)
        # a board with thickness (top, underside and edges), not a single sheet
        pts = [(cx, ridge, z0 - 0.08), (xb, eave, z0 - 0.08), (xb, eave, z1 + 0.08), (cx, ridge, z1 + 0.08)]
        nrm = slope_normal((cx, ridge), (xb, eave))
        roof.prism(pts, (-nrm[0] * th, -nrm[1] * th, 0.0), "roof")
    roof.build(coll)
    # gables: the front and back walls close up to the underside of the roof
    # (the side walls already reach into the roof board, so a triangle up to the ridge's underside does)
    slope = (ridge - eave) / (w / 2 + 0.08)
    peak = ridge - th * math.hypot(1.0, slope)
    for zz in (z0, z1 - 0.04):
        g.prism([(x0, ty + h, zz), (x1, ty + h, zz), (cx, peak, zz)], (0.0, 0.0, 0.04), "wood_paint")
    g.build(coll)
    REG.collider(x0, ty, z0, x1, ty + h, z1, tag="furniture")
    for side in (-1, 1):
        roof_slab_collider((cx, ridge), (cx + side * (w / 2 + 0.08), eave), z0 - 0.08, z1 + 0.08, th)
    # an empty bowl and a chain: whoever lived here is gone
    ph(coll, "wooden_bowl_01", (cx + 0.7, ty, cz - 0.6), 0.0, fit=(0.22, None, None), name="dog_bowl")
