"""Custom built furniture and fixtures (things Poly Haven does not have, or that must be animated).
Everything is created in game coordinates through lib helpers."""
import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import lib
from lib import REG, Geo, gv

FACING_YAW = {"+z": 0.0, "-z": math.pi, "+x": math.pi / 2, "-x": -math.pi / 2}


def _new_obj(name, coll, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def smooth(ob, angle=40):
    for p in ob.data.polygons:
        p.use_smooth = True
    try:
        mod = ob.modifiers.new("smooth", "SMOOTH_BY_ANGLE")
        mod["Input_1"] = math.radians(angle)
    except Exception:  # noqa: BLE001
        try:
            ob.data.shade_auto_smooth(angle=math.radians(angle))
        except Exception:  # noqa: BLE001
            pass
    return ob


def rbox(name, coll, cx, cy, cz, w, h, d, key, bevel=0.01, seg=2, yaw=0.0, uv=True):
    """rounded box by centre (game)."""
    return lib.rounded_box(name, coll, (cx, cy, cz), (w, h, d), key, bevel=bevel, segments=seg, yaw=yaw, world_uv=uv)


def rbox_min(name, coll, x0, y0, z0, x1, y1, z1, key, bevel=0.01, seg=2):
    return rbox(name, coll, (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, abs(x1 - x0), abs(y1 - y0), abs(z1 - z0), key, bevel, seg)


def soft_box(name, coll, cx, cy, cz, w, h, d, key, levels=2, bevel=0.0, squash=1.0):
    """cushion-like box: subdivision surface over a cube (rounded, pillowy)."""
    ob = rbox(name, coll, cx, cy, cz, w, h, d, key, bevel=bevel, seg=1, uv=False)
    lib.add_mod(ob, "SUBSURF", levels=levels, render_levels=levels)
    lib.apply_mods(ob)
    bpy.context.view_layer.update()
    # re-normalise size after subdivision shrink
    dims = ob.dimensions
    ob.scale = (w / max(dims.x, 1e-4), d / max(dims.y, 1e-4), h * squash / max(dims.z, 1e-4))
    bpy.context.view_layer.update()
    apply_scale(ob)
    lib.world_uv_object(ob)
    smooth(ob)
    return ob


def apply_scale(ob):
    mw = ob.matrix_world.copy()
    loc, rot, sca = mw.decompose()
    ob.data.transform(Matrix.Diagonal((sca.x, sca.y, sca.z, 1)))
    ob.scale = (1, 1, 1)


def cyl(name, coll, x, y, z, r0, r1, h, key, seg=16):
    return smooth(lib.lathe(name, coll, [(r0, 0), (r1, h)], key, pos=(x, y, z), segments=seg, cap=True))


def rotate_about_y(ob, yaw, pivot):
    """rotate a finished object about the game Y axis through a game-space pivot."""
    p = gv(pivot)
    m = Matrix.Translation(p) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Translation(-p)
    ob.matrix_world = m @ ob.matrix_world


# ------------------------------------------------------------------ kitchen


def counter(coll, name, x0, z0, x1, z1, y=0.0, h=0.9, front="+z", body="wood_paint_green", top="countertop", sink=None, doors=True):
    """base cabinet run. front: side with the doors. sink: (cx, cz, w, d) cut in the countertop."""
    objs = []
    objs.append(rbox_min(f"{name}_kick", coll, x0 + 0.06, y, z0 + 0.06, x1 - 0.06, y + 0.1, z1 - 0.06, "plastic_black", 0.003, 1))
    objs.append(rbox_min(f"{name}_body", coll, x0 + 0.02, y + 0.1, z0 + 0.02, x1 - 0.02, y + h - 0.04, z1 - 0.02, body, 0.006, 2))
    # doors + drawers on the front face
    along_x = front in ("+z", "-z")
    length = (x1 - x0) if along_x else (z1 - z0)
    n = max(1, round(length / 0.55))
    seg = length / n
    for i in range(n if doors else 0):
        a = (x0 if along_x else z0) + i * seg + 0.02
        b = a + seg - 0.04
        for (ya, yb, kind) in ((y + 0.14, y + h - 0.22, "door"), (y + h - 0.2, y + h - 0.07, "drawer")):
            if along_x:
                zf = z1 if front == "+z" else z0
                sgn = 1 if front == "+z" else -1
                p = rbox_min(f"{name}_{kind}{i}", coll, a, ya, zf - 0.005 * sgn, b, yb, zf + 0.012 * sgn, body, 0.004, 2)
                hx = (a + b) / 2 if kind == "drawer" else (b - 0.06 if i % 2 == 0 else a + 0.06)
                hy = (ya + yb) / 2 if kind == "drawer" else yb - 0.08
                objs.append(p)
                objs.append(rbox(f"{name}_{kind}{i}_h", coll, hx, hy, zf + 0.028 * sgn, 0.1 if kind == "drawer" else 0.018, 0.018 if kind == "drawer" else 0.1, 0.02, "brass", 0.006, 2))
            else:
                xf = x1 if front == "+x" else x0
                sgn = 1 if front == "+x" else -1
                p = rbox_min(f"{name}_{kind}{i}", coll, xf - 0.005 * sgn, ya, a, xf + 0.012 * sgn, yb, b, body, 0.004, 2)
                hz = (a + b) / 2 if kind == "drawer" else (b - 0.06 if i % 2 == 0 else a + 0.06)
                hy = (ya + yb) / 2 if kind == "drawer" else yb - 0.08
                objs.append(p)
                objs.append(rbox(f"{name}_{kind}{i}_h", coll, xf + 0.028 * sgn, hy, hz, 0.02, 0.018 if kind == "drawer" else 0.1, 0.1 if kind == "drawer" else 0.018, "brass", 0.006, 2))
    # countertop (with an optional sink cut)
    ov = 0.025
    tx0, tx1, tz0, tz1 = x0 - (ov if front == "-x" else 0), x1 + (ov if front == "+x" else 0), z0 - (ov if front == "-z" else 0), z1 + (ov if front == "+z" else 0)
    ty0, ty1 = y + h - 0.04, y + h
    if sink:
        sx, sz, sw, sd = sink
        pieces = [(tx0, tz0, sx - sw / 2, tz1), (sx + sw / 2, tz0, tx1, tz1), (sx - sw / 2, tz0, sx + sw / 2, sz - sd / 2), (sx - sw / 2, sz + sd / 2, sx + sw / 2, tz1)]
        for k, (a0, b0, a1, b1) in enumerate(pieces):
            if a1 - a0 > 0.005 and b1 - b0 > 0.005:
                objs.append(rbox_min(f"{name}_top{k}", coll, a0, ty0, b0, a1, ty1, b1, top, 0.004, 1))
        # basin: open box below the cut
        g = Geo(f"{name}_basin")
        bx0, bx1, bz0, bz1 = sx - sw / 2, sx + sw / 2, sz - sd / 2, sz + sd / 2
        depth = 0.2
        g.box(bx0, ty1 - depth, bz0, bx1, ty1 - depth + 0.01, bz1, "chrome")
        for (a, b, c, d) in ((bx0, bz0, bx1, bz0 + 0.01), (bx0, bz1 - 0.01, bx1, bz1), (bx0, bz0, bx0 + 0.01, bz1), (bx1 - 0.01, bz0, bx1, bz1)):
            g.box(a, ty1 - depth, b, c, ty1, d, "chrome")
        objs.append(g.build(coll))
        REG.collider(bx0, ty1 - depth, bz0, bx1, ty1 - depth + 0.01, bz1, tag="furniture")
    else:
        objs.append(rbox_min(f"{name}_top", coll, tx0, ty0, tz0, tx1, ty1, tz1, top, 0.004, 1))
    REG.collider(x0, y, z0, x1, y + h, z1, tag="furniture")
    return objs


def upper_cabinet(coll, name, x0, z0, x1, z1, y0, y1, front="+z", body="wood_paint_green"):
    objs = [rbox_min(f"{name}_body", coll, x0, y0, z0, x1, y1, z1, body, 0.006, 2)]
    length = x1 - x0
    n = max(1, round(length / 0.5))
    seg = length / n
    zf = z1 if front == "+z" else z0
    sgn = 1 if front == "+z" else -1
    for i in range(n):
        a = x0 + i * seg + 0.015
        b = a + seg - 0.03
        objs.append(rbox_min(f"{name}_door{i}", coll, a, y0 + 0.02, zf, b, y1 - 0.02, zf + 0.015 * sgn, body, 0.004, 2))
        objs.append(rbox_min(f"{name}_panel{i}", coll, a + 0.05, y0 + 0.07, zf + 0.012 * sgn, b - 0.05, y1 - 0.07, zf + 0.02 * sgn, body, 0.003, 1))
        hx = b - 0.04 if i % 2 == 0 else a + 0.04
        objs.append(rbox(f"{name}_h{i}", coll, hx, y0 + 0.1, zf + 0.03 * sgn, 0.015, 0.07, 0.02, "brass", 0.005, 2))
    REG.collider(x0, y0, z0, x1, y1, z1, tag="furniture")
    return objs


def faucet(coll, name, x, y, z, toward=(0, 0, 1), key="chrome", reach=0.16, height=0.22):
    """gooseneck faucet standing at (x,y,z) (deck), pointing its spout along `toward`."""
    tx, _, tz = toward
    pts = [(x, y, z), (x, y + height * 0.8, z), (x + tx * reach * 0.4, y + height, z + tz * reach * 0.4), (x + tx * reach, y + height * 0.85, z + tz * reach), (x + tx * reach, y + height * 0.7, z + tz * reach)]
    objs = [cyl(f"{name}_base", coll, x, y, z, 0.03, 0.025, 0.03, key, 16), lib.tube(f"{name}_neck", coll, pts, 0.012, key, segments=12)]
    sx, sz = -tz, tx
    for s in (-1, 1):
        hx, hz = x + sx * 0.08 * s, z + sz * 0.08 * s
        objs.append(cyl(f"{name}_valve{s}", coll, hx, y, hz, 0.018, 0.016, 0.05, key, 12))
        handle = rbox(f"{name}_cross{s}", coll, hx, y + 0.06, hz, 0.06, 0.012, 0.012, "ceramic", 0.005, 2)
        objs.append(handle)
    return objs, (x + tx * reach, y + height * 0.7, z + tz * reach)


def fridge(coll, x0, z0, x1, z1, y=0.0, h=1.75, front="+z"):
    objs = []
    w, d = x1 - x0, z1 - z0
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    body = rbox("fridge_body", coll, cx, y + 0.06 + (h - 0.06) / 2, cz, w, h - 0.06, d, "enamel_cream", bevel=0.07, seg=6)
    objs.append(body)
    zf = z1 if front == "+z" else z0
    sgn = 1 if front == "+z" else -1
    # door seam + freezer seam
    for yy in (y + 1.22,):
        objs.append(rbox(f"fridge_seam", coll, cx, yy, zf + 0.001 * sgn, w * 0.86, 0.008, 0.01, "metal_dark", 0.002, 1))
    # handles
    objs.append(lib.tube("fridge_handle_low", coll, [(x1 - 0.08, y + 0.75, zf), (x1 - 0.08, y + 0.75, zf + 0.05 * sgn), (x1 - 0.08, y + 1.15, zf + 0.05 * sgn), (x1 - 0.08, y + 1.15, zf)], 0.013, "chrome", segments=12))
    objs.append(lib.tube("fridge_handle_top", coll, [(x1 - 0.08, y + 1.3, zf), (x1 - 0.08, y + 1.3, zf + 0.05 * sgn), (x1 - 0.08, y + 1.55, zf + 0.05 * sgn), (x1 - 0.08, y + 1.55, zf)], 0.013, "chrome", segments=12))
    objs.append(rbox("fridge_badge", coll, cx, y + 1.62, zf + 0.004 * sgn, 0.18, 0.04, 0.008, "chrome", 0.004, 2))
    for fx in (x0 + 0.08, x1 - 0.08):
        for fz in (z0 + 0.08, z1 - 0.08):
            objs.append(cyl("fridge_foot", coll, fx, y, fz, 0.03, 0.025, 0.06, "metal_dark", 10))
    REG.collider(x0, y, z0, x1, y + h, z1, tag="furniture")
    return objs


# ------------------------------------------------------------------ bathroom


def bathtub(coll, x0, z0, x1, z1, y=3.0):
    """clawfoot tub along x. returns (objs, water_bottom_y, water_top_y)."""
    w, d = x1 - x0, z1 - z0
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    h = 0.5
    base = y + 0.16
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        # taper towards the bottom like a slipper tub
        t = v.co.z + 0.5
        v.co.x *= w * (0.86 + 0.14 * t)
        v.co.y *= d * (0.8 + 0.2 * t)
        v.co.z = t * h
    top = [f for f in bm.faces if f.normal.z > 0.9]
    bmesh.ops.delete(bm, geom=top, context="FACES_ONLY")
    ob = _new_obj("tub", coll, bm)
    ob.location = gv(cx, base, cz)
    lib.add_mod(ob, "SOLIDIFY", thickness=0.05, offset=-1)
    lib.add_mod(ob, "BEVEL", width=0.012, segments=2, limit_method="ANGLE")
    lib.add_mod(ob, "SUBSURF", levels=2, render_levels=2)
    lib.apply_mods(ob)
    lib.set_material(ob, "enamel")
    smooth(ob)
    objs = [ob]
    # rolled rim
    rim = []
    for i in range(48):
        a = i / 48 * 2 * math.pi
        rim.append((cx + math.cos(a) * (w * 0.5 - 0.02), base + h + 0.005, cz + math.sin(a) * (d * 0.5 - 0.015)))
    rim.append(rim[0])
    objs.append(lib.tube("tub_rim", coll, rim, 0.022, "enamel", segments=10))
    # claw feet
    for fx in (x0 + 0.22, x1 - 0.22):
        for fz in (z0 + 0.14, z1 - 0.14):
            foot = smooth(lib.lathe("tub_foot", coll, [(0.0, 0.0), (0.045, 0.005), (0.05, 0.03), (0.03, 0.07), (0.035, 0.12), (0.05, 0.17), (0.0, 0.19)], "brass", pos=(fx, y, fz), segments=12))
            objs.append(foot)
    # faucet at the +x end
    fo, spout = faucet(coll, "tub_faucet", x1 - 0.08, base + h, cz, toward=(-1, 0, 0), reach=0.12, height=0.16)
    objs += fo
    REG.collider(x0, y, z0, x1, base + h, z0 + 0.06, tag="furniture")
    REG.collider(x0, y, z1 - 0.06, x1, base + h, z1, tag="furniture")
    REG.collider(x0, y, z0, x0 + 0.08, base + h, z1, tag="furniture")
    REG.collider(x1 - 0.08, y, z0, x1, base + h, z1, tag="furniture")
    REG.collider(x0, y, z0, x1, base + 0.05, z1, tag="furniture")
    REG.nodes["tub"] = {"bottom": base + 0.05, "top": base + h - 0.06, "rect": [x0 + 0.1, z0 + 0.08, x1 - 0.1, z1 - 0.08], "spout": list(spout)}
    return objs


def toilet(coll, name, cx, cz, y, facing="+z"):
    yaw = FACING_YAW[facing]
    objs = []
    bowl = lib.lathe(f"{name}_bowl", coll, [(0.12, 0), (0.13, 0.05), (0.11, 0.15), (0.13, 0.28), (0.19, 0.36), (0.2, 0.39), (0.16, 0.4), (0.12, 0.33), (0.06, 0.25)], "ceramic", pos=(cx, y, cz + 0.05), segments=28)
    bowl.scale = (0.85, 1.15, 1.0)
    objs.append(smooth(bowl))
    seat = lib.lathe(f"{name}_seat", coll, [(0.13, 0.4), (0.2, 0.4), (0.205, 0.42), (0.19, 0.43), (0.13, 0.43), (0.125, 0.41)], "plastic_white", pos=(cx, y, cz + 0.05), segments=28)
    seat.scale = (0.85, 1.15, 1.0)
    objs.append(smooth(seat))
    tank = rbox(f"{name}_tank", coll, cx, y + 0.62, cz - 0.2, 0.42, 0.4, 0.18, "ceramic", 0.03, 4)
    lid = rbox(f"{name}_lid", coll, cx, y + 0.83, cz - 0.2, 0.45, 0.04, 0.2, "ceramic", 0.015, 3)
    lever = rbox(f"{name}_lever", coll, cx - 0.15, y + 0.75, cz - 0.11, 0.06, 0.012, 0.015, "chrome", 0.004, 2)
    objs += [tank, lid, lever]
    objs.append(lib.tube(f"{name}_pipe", coll, [(cx, y + 0.42, cz - 0.2), (cx, y + 0.3, cz - 0.2), (cx, y + 0.3, cz - 0.08)], 0.02, "chrome"))
    for o in objs:
        rotate_about_y(o, yaw, (cx, y, cz))
    REG.collider(cx - 0.21, y, cz - 0.3, cx + 0.21, y + 0.43, cz + 0.28, tag="furniture") if facing in ("+z", "-z") else REG.collider(cx - 0.3, y, cz - 0.21, cx + 0.28, y + 0.43, cz + 0.21, tag="furniture")
    return objs


def pedestal_sink(coll, name, cx, cz, y, facing="+z"):
    """returns (objs, spout point, basin rect)"""
    yaw = FACING_YAW[facing]
    objs = []
    objs.append(smooth(lib.lathe(f"{name}_ped", coll, [(0.13, 0), (0.12, 0.04), (0.08, 0.12), (0.075, 0.55), (0.11, 0.7)], "ceramic", pos=(cx, y, cz), segments=24)))
    basin = lib.lathe(f"{name}_basin", coll, [(0.0, 0.7), (0.12, 0.7), (0.24, 0.76), (0.29, 0.84), (0.3, 0.87), (0.27, 0.88), (0.22, 0.84), (0.08, 0.78), (0.02, 0.77)], "ceramic", pos=(cx, y, cz + 0.02), segments=32)
    basin.scale = (1.0, 0.72, 1.0)
    objs.append(smooth(basin))
    objs.append(rbox(f"{name}_deck", coll, cx, y + 0.875, cz - 0.16, 0.5, 0.03, 0.1, "ceramic", 0.012, 3))
    fo, spout = faucet(coll, f"{name}_faucet", cx, y + 0.89, cz - 0.17, toward=(0, 0, 1), reach=0.11, height=0.13)
    objs += fo
    for o in objs:
        rotate_about_y(o, yaw, (cx, y, cz))
    # rotate the spout point as well
    s = Vector(spout) - Vector((cx, y, cz))
    c, sn = math.cos(yaw), math.sin(yaw)
    spout_r = (cx + s.x * c + s.z * sn, spout[1], cz - s.x * sn + s.z * c)
    if facing in ("+z", "-z"):
        REG.collider(cx - 0.3, y + 0.7, cz - 0.24, cx + 0.3, y + 0.88, cz + 0.24, tag="furniture")
    else:
        REG.collider(cx - 0.24, y + 0.7, cz - 0.3, cx + 0.24, y + 0.88, cz + 0.3, tag="furniture")
    REG.collider(cx - 0.09, y, cz - 0.09, cx + 0.09, y + 0.7, cz + 0.09, tag="furniture")
    return objs, spout_r


def shower(coll, x0, z0, x1, z1, y=0.0):
    objs = [rbox_min("shower_tray", coll, x0, y, z0, x1, y + 0.06, z1, "ceramic", 0.01, 2)]
    g = Geo("shower_glass")
    g.box(x0, y + 0.06, z0 - 0.01, x1, y + 2.0, z0 + 0.01, "glass")
    g.box(x0 - 0.01, y + 0.06, z0, x0 + 0.01, y + 2.0, z1, "glass")
    objs.append(g.build(coll))
    objs.append(lib.tube("shower_frame", coll, [(x1, y + 2.0, z0), (x0, y + 2.0, z0), (x0, y + 2.0, z1)], 0.012, "chrome"))
    objs.append(lib.tube("shower_pipe", coll, [(x1 - 0.06, y + 1.0, z1 - 0.02), (x1 - 0.06, y + 1.95, z1 - 0.02), (x1 - 0.06, y + 1.98, z1 - 0.2)], 0.012, "chrome"))
    objs.append(cyl("shower_head", coll, x1 - 0.06, y + 1.9, z1 - 0.22, 0.02, 0.07, 0.06, "chrome", 20))
    REG.collider(x0, y, z0, x1, y + 0.06, z1, tag="furniture")
    REG.collider(x0, y, z0 - 0.02, x1, y + 2.0, z0 + 0.02, tag="wall", cam=False)
    REG.collider(x0 - 0.02, y, z0, x0 + 0.02, y + 2.0, z1, tag="wall", cam=False)
    return objs


def mirror(coll, name, axis, fixed, normal, s0, s1, y0, y1, frame="trim_dark"):
    """wall mirror. axis = wall axis ('x' wall runs along x, constant z)."""
    t = 0.02
    if axis == "x":
        z = fixed + normal * (t / 2 + 0.002)
        f = rbox_min(f"{name}_frame", coll, s0 - 0.04, y0 - 0.04, z - t / 2, s1 + 0.04, y1 + 0.04, z + t / 2, frame, 0.008, 2)
        g = rbox_min(f"{name}_glass", coll, s0, y0, z + normal * t / 2, s1, y1, z + normal * (t / 2 + 0.003), "mirror", 0.0, 1)
    else:
        x = fixed + normal * (t / 2 + 0.002)
        f = rbox_min(f"{name}_frame", coll, x - t / 2, y0 - 0.04, s0 - 0.04, x + t / 2, y1 + 0.04, s1 + 0.04, frame, 0.008, 2)
        g = rbox_min(f"{name}_glass", coll, x + normal * t / 2, y0, s0, x + normal * (t / 2 + 0.003), y1, s1, "mirror", 0.0, 1)
    return [f, g]


# ------------------------------------------------------------------ laundry / basement


def washer(coll, name, cx, cz, y, front="+z"):
    objs = [rbox(f"{name}_body", coll, cx, y + 0.43, cz, 0.6, 0.86, 0.6, "plastic_white", 0.03, 4)]
    zf = cz + 0.3 if front == "+z" else cz - 0.3
    sgn = 1 if front == "+z" else -1
    ring = lib.lathe(f"{name}_ring", coll, [(0.15, 0), (0.19, 0), (0.2, 0.02), (0.19, 0.04), (0.15, 0.04), (0.15, 0.0)], "chrome", segments=32)
    ring.location = gv(cx, y + 0.42, zf)
    ring.rotation_euler = (math.pi / 2 * sgn, 0, 0)
    objs.append(smooth(ring))
    glass = lib.lathe(f"{name}_glass", coll, [(0.0, 0.035), (0.15, 0.02)], "glass_dirty", segments=32)
    glass.location = gv(cx, y + 0.42, zf)
    glass.rotation_euler = (math.pi / 2 * sgn, 0, 0)
    objs.append(glass)
    objs.append(rbox(f"{name}_panel", coll, cx, y + 0.8, zf + 0.005 * sgn, 0.56, 0.08, 0.02, "plastic_beige", 0.008, 2))
    for k, kx in enumerate((cx - 0.18, cx + 0.18)):
        knob = cyl(f"{name}_knob{k}", coll, 0, 0, 0, 0.025, 0.022, 0.025, "plastic_black", 16)
        knob.location = gv(kx, y + 0.8, zf + 0.015 * sgn)
        knob.rotation_euler = (math.pi / 2 * sgn, 0, 0)
        objs.append(knob)
    REG.collider(cx - 0.3, y, cz - 0.3, cx + 0.3, y + 0.86, cz + 0.3, tag="furniture")
    return objs


def tanque(coll, x0, z0, x1, z1, y):
    """concrete wash tub on a pedestal."""
    h = 0.85
    g = Geo("tanque")
    g.box(x0, y + h - 0.32, z0, x1, y + h - 0.28, z1, "wall_lavanderia")
    for (a, b, c, d) in ((x0, z0, x1, z0 + 0.05), (x0, z1 - 0.05, x1, z1), (x0, z0, x0 + 0.05, z1), (x1 - 0.05, z0, x1, z1)):
        g.box(a, y + h - 0.32, b, c, y + h, d, "wall_lavanderia")
    g.box(x0 + 0.1, y, z0 + 0.1, x1 - 0.1, y + h - 0.32, z1 - 0.1, "wall_lavanderia")
    objs = [g.build(coll)]
    fo, spout = faucet(coll, "tanque_faucet", (x0 + x1) / 2, y + h + 0.25, z0 + 0.02, toward=(0, 0, 1), reach=0.12, height=0.08)
    objs += fo
    REG.collider(x0, y, z0, x1, y + h, z1, tag="furniture")
    return objs


def ironing_board(coll, cx, cz, y, length=1.2, height=0.85):
    pts = []
    for i in range(41):
        t = i / 40
        x = -length / 2 + t * length
        w = 0.18 * (1 - max(0.0, (t - 0.65) / 0.35) ** 1.6) + 0.01
        pts.append((x, w))
    bm = bmesh.new()
    top = []
    bot = []
    for x, w in pts:
        top.append((bm.verts.new((x, w, 0.012)), bm.verts.new((x, -w, 0.012))))
        bot.append((bm.verts.new((x, w, -0.012)), bm.verts.new((x, -w, -0.012))))
    for i in range(len(pts) - 1):
        bm.faces.new((top[i][0], top[i][1], top[i + 1][1], top[i + 1][0]))
        bm.faces.new((bot[i][0], bot[i + 1][0], bot[i + 1][1], bot[i][1]))
        bm.faces.new((top[i][0], top[i + 1][0], bot[i + 1][0], bot[i][0]))
        bm.faces.new((top[i][1], bot[i][1], bot[i + 1][1], top[i + 1][1]))
    ob = _new_obj("ironing_board", coll, bm)
    ob.location = gv(cx, y + height, cz)
    lib.set_material(ob, "gingham")
    lib.world_uv_object(ob)
    objs = [ob]
    for s in (-1, 1):
        objs.append(lib.tube(f"ib_leg{s}", coll, [(cx - 0.3 * s, y, cz - 0.12), (cx + 0.25 * s, y + height - 0.02, cz)], 0.01, "chrome"))
        objs.append(lib.tube(f"ib_leg{s}b", coll, [(cx - 0.3 * s, y, cz + 0.12), (cx + 0.25 * s, y + height - 0.02, cz)], 0.01, "chrome"))
    REG.collider(cx - length / 2, y + height - 0.015, cz - 0.18, cx + length / 2, y + height + 0.015, cz + 0.18, tag="furniture")
    return objs


def boiler(coll, cx, cz, y, r=0.42, h=1.75):
    objs = [smooth(lib.lathe("boiler_body", coll, [(0.0, 0.0), (r, 0.0), (r, 0.06), (r - 0.01, 0.08), (r - 0.01, h - 0.2), (r * 0.8, h - 0.05), (r * 0.3, h), (0.0, h)], "boiler", pos=(cx, y, cz), segments=28))]
    for yy in (0.3, h - 0.35):
        objs.append(smooth(lib.lathe("boiler_band", coll, [(r + 0.005, yy), (r + 0.015, yy + 0.01), (r + 0.015, yy + 0.05), (r + 0.005, yy + 0.06)], "iron", pos=(cx, y, cz), segments=28)))
    objs.append(lib.tube("boiler_flue", coll, [(cx, y + h, cz), (cx, y + h + 0.5, cz), (cx + 0.6, y + h + 0.75, cz)], 0.07, "iron", segments=12))
    # pilot window + gauge
    objs.append(rbox("boiler_hatch", coll, cx + r + 0.005, y + 0.25, cz, 0.02, 0.18, 0.22, "iron", 0.01, 2))
    REG.nodes["boiler_pilot"] = [cx + r + 0.02, y + 0.25, cz]
    gauge = cyl("boiler_gauge", coll, 0, 0, 0, 0.05, 0.05, 0.03, "brass", 16)
    gauge.location = gv(cx + r * 0.7, y + 1.2, cz - r * 0.7)
    gauge.rotation_euler = (0, math.pi / 2, -math.pi / 4)
    objs.append(gauge)
    REG.collider(cx - r, y, cz - r, cx + r, y + h, cz + r, tag="furniture")
    return objs


def pipe_run(coll, name, pts, r=0.05, key="iron"):
    objs = [lib.tube(name, coll, pts, r, key, segments=12)]
    for i, p in enumerate(pts[1:-1]):
        objs.append(smooth(lib.lathe(f"{name}_j{i}", coll, [(r * 1.25, -0.03), (r * 1.25, 0.03)], key, pos=(p[0], p[1], p[2]), segments=12, cap=True)))
    return objs


def radiator(coll, x0, x1, z, y=0.12, h=0.6, normal=1):
    objs = []
    n = int((x1 - x0) / 0.06)
    for i in range(n):
        x = x0 + (i + 0.5) * (x1 - x0) / n
        objs.append(rbox(f"rad_fin{i}", coll, x, y + h / 2, z + normal * 0.06, 0.04, h, 0.09, "iron", 0.012, 3))
    objs.append(lib.tube("rad_top", coll, [(x0, y + h - 0.05, z + normal * 0.06), (x1, y + h - 0.05, z + normal * 0.06)], 0.02, "iron"))
    objs.append(lib.tube("rad_bot", coll, [(x0, y + 0.05, z + normal * 0.06), (x1, y + 0.05, z + normal * 0.06)], 0.02, "iron"))
    objs.append(lib.tube("rad_feed", coll, [(x0, y + 0.05, z + normal * 0.06), (x0 - 0.05, y + 0.05, z + normal * 0.06), (x0 - 0.05, -0.05 + (y - 0.12), z + normal * 0.06)], 0.012, "brass"))
    REG.collider(x0, y - 0.12, min(z, z + normal * 0.11), x1, y + h, max(z, z + normal * 0.11), tag="furniture")
    return objs


# ------------------------------------------------------------------ textiles


def rug(coll, name, x0, z0, x1, z1, y, key, thick=0.008):
    bm = bmesh.new()
    w, d = x1 - x0, z1 - z0
    bmesh.ops.create_grid(bm, x_segments=12, y_segments=12, size=0.5)
    for v in bm.verts:
        v.co.x *= w
        v.co.y *= d
    ob = _new_obj(name, coll, bm)
    ob.location = gv((x0 + x1) / 2, y + thick, (z0 + z1) / 2)
    uvl = ob.data.uv_layers.new(name="UVMap")
    for poly in ob.data.polygons:
        for li in range(poly.loop_start, poly.loop_start + poly.loop_total):
            co = ob.data.vertices[ob.data.loops[li].vertex_index].co
            u = co.x / w + 0.5
            v = -co.y / d + 0.5
            # long rugs: texture runs along the long axis
            uvl.data[li].uv = (u, v) if d >= w else (v, u)
    lib.add_mod(ob, "SOLIDIFY", thickness=thick, offset=-1)
    lib.apply_mods(ob)
    lib.set_material(ob, key)
    smooth(ob)
    return [ob]


def curtain_panel(coll, name, axis, fixed, inside, s0, s1, y_top, y_bot, key, folds=6, seed=0, gather=0.0):
    """wavy fabric panel hanging just inside a window. gather: pull the bottom toward s1 (tie-back)."""
    r = lib.rng(seed)
    nu, nv = 36, 24
    off = inside * 0.13
    verts = []
    for j in range(nv + 1):
        v = j / nv
        y = y_top - v * (y_top - y_bot)
        row = []
        for i in range(nu + 1):
            u = i / nu
            s = s0 + u * (s1 - s0)
            if gather:
                tie = max(0.0, 1 - abs(v - 0.62) / 0.38)
                s = s + (s1 - s) * gather * tie * (1 - u * 0.3)
            depth = 0.035 * math.sin(u * folds * 2 * math.pi + seed) * (0.6 + 0.6 * v) + 0.01 * math.sin(u * 23 + v * 3)
            n = fixed + off + inside * depth
            row.append((n, y, s) if axis == "z" else (s, y, n))
        verts.append(row)
    bm = bmesh.new()
    vv = [[bm.verts.new(gv(p)) for p in row] for row in verts]
    for j in range(nv):
        for i in range(nu):
            bm.faces.new((vv[j][i], vv[j + 1][i], vv[j + 1][i + 1], vv[j][i + 1]))
    ob = _new_obj(name, coll, bm)
    uvl = ob.data.uv_layers.new(name="UVMap")
    for poly in ob.data.polygons:
        for li in range(poly.loop_start, poly.loop_start + poly.loop_total):
            vi = ob.data.loops[li].vertex_index
            j, i = divmod(vi, nu + 1)
            uvl.data[li].uv = (i / nu * (s1 - s0) * 1.3, -j / nv * (y_top - y_bot))
    lib.add_mod(ob, "SOLIDIFY", thickness=0.006)
    lib.apply_mods(ob)
    lib.set_material(ob, key)
    smooth(ob)
    return ob


def curtains(coll, w, key):
    """two panels + rod for a window def."""
    axis, fixed, ins = w["axis"], w["fixed"], w["inside"]
    s0, s1, y0, y1 = w["s0"], w["s1"], w["y0"], w["y1"]
    top = y1 + 0.2
    bot = max(y0 - 0.3, y0 - 0.3)
    objs = []
    pw = max(0.3, (s1 - s0) * 0.3)
    objs.append(curtain_panel(coll, f"curtain_{w['id']}_a", axis, fixed, ins, s0 - 0.28, s0 - 0.28 + pw, top, bot, key, folds=4, seed=hash(w["id"]) % 7, gather=0.0))
    objs.append(curtain_panel(coll, f"curtain_{w['id']}_b", axis, fixed, ins, s1 + 0.28 - pw, s1 + 0.28, top, bot, key, folds=4, seed=(hash(w["id"]) + 3) % 7, gather=0.0))
    off = ins * 0.15
    if axis == "z":
        p0, p1 = (fixed + off, top + 0.02, s0 - 0.38), (fixed + off, top + 0.02, s1 + 0.38)
    else:
        p0, p1 = (s0 - 0.38, top + 0.02, fixed + off), (s1 + 0.38, top + 0.02, fixed + off)
    objs.append(lib.tube(f"rod_{w['id']}", coll, [p0, p1], 0.012, "brass"))
    for p in (p0, p1):
        objs.append(smooth(lib.lathe("rod_finial", coll, [(0.0, -0.025), (0.025, -0.02), (0.03, 0.0), (0.025, 0.02), (0.0, 0.025)], "brass", pos=p, segments=12)))
    return objs


def cloth_drape(coll, name, size, pos, colliders, key, frames=40, res=40, pin=None, quality=6):
    """drop a cloth sheet of size (w, d) from pos (game) onto collider objects and freeze the result."""
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=res, y_segments=res, size=0.5)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
    ob = _new_obj(name, coll, bm)
    ob.location = gv(pos)
    for c in colliders:
        m = c.modifiers.new("collision", "COLLISION")
        c.collision.thickness_outer = 0.01
        c.collision.cloth_friction = 8
    cm = ob.modifiers.new("cloth", "CLOTH")
    cm.settings.quality = quality
    cm.settings.mass = 0.25
    cm.settings.tension_stiffness = 12
    cm.settings.compression_stiffness = 12
    cm.settings.bending_stiffness = 0.4
    cm.collision_settings.distance_min = 0.006
    cm.collision_settings.use_self_collision = False
    cm.point_cache.frame_start = 1
    cm.point_cache.frame_end = frames
    if pin:
        vg = ob.vertex_groups.new(name="pin")
        idx = [v.index for v in ob.data.vertices if pin(v.co)]
        vg.add(idx, 1.0, "REPLACE")
        cm.settings.vertex_group_mass = "pin"
    scene = bpy.context.scene
    scene.frame_start = 1
    scene.frame_end = frames
    for f in range(1, frames + 1):
        scene.frame_set(f)
    bpy.context.view_layer.update()
    # bake the evaluated mesh
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = bpy.data.meshes.new_from_object(ev)
    res_ob = bpy.data.objects.new(name, me)
    coll.objects.link(res_ob)
    res_ob.matrix_world = ob.matrix_world
    bpy.data.objects.remove(ob, do_unlink=True)
    for c in colliders:
        for m in list(c.modifiers):
            if m.type == "COLLISION":
                c.modifiers.remove(m)
    scene.frame_set(1)
    lib.add_mod(res_ob, "SOLIDIFY", thickness=0.006)
    lib.add_mod(res_ob, "SUBSURF", levels=1, render_levels=1)
    lib.apply_mods(res_ob)
    lib.set_material(res_ob, key)
    bpy.context.view_layer.update()
    lib.world_uv_object(res_ob, 1.0)
    smooth(res_ob)
    return res_ob


# ------------------------------------------------------------------ small fixtures


def table_lamp(coll, name, x, y, z, shade_key="lampshade"):
    objs = [smooth(lib.lathe(f"{name}_base", coll, [(0.0, 0.0), (0.075, 0.0), (0.075, 0.015), (0.06, 0.03), (0.075, 0.08), (0.085, 0.14), (0.06, 0.22), (0.02, 0.26), (0.012, 0.36), (0.0, 0.36)], "ceramic", pos=(x, y, z), segments=24))]
    shade = smooth(lib.lathe(f"{name}_shade", coll, [(0.15, 0.27), (0.09, 0.45), (0.088, 0.452), (0.148, 0.272)], shade_key, pos=(x, y, z), segments=32))
    objs.append(shade)
    bulb = smooth(lib.lathe(f"{name}_bulb", coll, [(0.0, 0.3), (0.03, 0.31), (0.035, 0.34), (0.022, 0.37), (0.0, 0.38)], "bulb", pos=(x, y, z), segments=12))
    objs.append(bulb)
    return objs, shade, bulb


def pendant(coll, name, x, y, z, ceiling):
    objs = [lib.tube(f"{name}_cord", coll, [(x, ceiling, z), (x, y + 0.15, z)], 0.005, "plastic_black", segments=6)]
    objs.append(cyl(f"{name}_canopy", coll, x, ceiling - 0.03, z, 0.06, 0.05, 0.03, "brass", 16))
    shade = smooth(lib.lathe(f"{name}_shade", coll, [(0.03, 0.15), (0.06, 0.14), (0.16, 0.04), (0.24, -0.06), (0.245, -0.07), (0.235, -0.065), (0.155, 0.035), (0.055, 0.13)], "lampshade", pos=(x, y, z), segments=36))
    objs.append(shade)
    bulb = smooth(lib.lathe(f"{name}_bulb", coll, [(0.0, -0.05), (0.035, -0.04), (0.04, 0.0), (0.025, 0.04), (0.018, 0.06), (0.0, 0.07)], "bulb", pos=(x, y, z), segments=14))
    objs.append(bulb)
    return objs, shade, bulb


def flush_light(coll, name, x, ceiling, z, r=0.2):
    base = cyl(f"{name}_base", coll, x, ceiling - 0.025, z, r, r, 0.025, "brass", 28)
    dome = smooth(lib.lathe(f"{name}_dome", coll, [(r * 0.95, 0.0), (r * 0.9, -0.05), (r * 0.65, -0.12), (r * 0.3, -0.16), (0.0, -0.17)], "bulb", pos=(x, ceiling - 0.025, z), segments=32))
    return [base, dome], dome


def switch_plate(coll, name, p, n):
    """light switch on a wall at game point p with normal n (axis aligned)."""
    nx, _, nz = n
    if abs(nx) > 0.5:
        plate = rbox(f"{name}_plate", coll, p[0] + nx * 0.006, p[1], p[2], 0.012, 0.115, 0.075, "plastic_beige", 0.004, 2)
        lever = rbox(f"{name}_lever", coll, p[0] + nx * 0.018, p[1], p[2], 0.02, 0.034, 0.016, "plastic_white", 0.003, 2)
    else:
        plate = rbox(f"{name}_plate", coll, p[0], p[1], p[2] + nz * 0.006, 0.075, 0.115, 0.012, "plastic_beige", 0.004, 2)
        lever = rbox(f"{name}_lever", coll, p[0], p[1], p[2] + nz * 0.018, 0.016, 0.034, 0.02, "plastic_white", 0.003, 2)
    return plate, lever


def outlet(coll, name, p, n):
    nx, _, nz = n
    if abs(nx) > 0.5:
        return rbox(f"{name}", coll, p[0] + nx * 0.006, p[1], p[2], 0.012, 0.1, 0.07, "plastic_beige", 0.004, 2)
    return rbox(f"{name}", coll, p[0], p[1], p[2] + nz * 0.006, 0.07, 0.1, 0.012, "plastic_beige", 0.004, 2)


def radio_vintage(coll, cx, cy, cz, facing="-x"):
    """tabletop valve radio. returns (objs, dial object)."""
    yaw = FACING_YAW[facing]
    w, h, d = 0.36, 0.24, 0.16
    objs = [rbox("radio_body", coll, cx, cy + h / 2, cz, w, h, d, "wood_dark", 0.03, 4)]
    objs.append(rbox("radio_grille", coll, cx - 0.06, cy + h * 0.5, cz + d / 2 + 0.002, 0.18, 0.15, 0.006, "hessian", 0.004, 2))
    dial = rbox("radio_dial", coll, cx + 0.11, cy + h * 0.58, cz + d / 2 + 0.003, 0.09, 0.09, 0.006, "bulb", 0.01, 3)
    objs.append(dial)
    for k, ky in enumerate((cy + 0.06, cy + 0.06)):
        kn = cyl(f"radio_knob{k}", coll, 0, 0, 0, 0.018, 0.016, 0.02, "plastic_black", 14)
        kn.location = gv(cx + 0.075 + k * 0.07, ky, cz + d / 2)
        kn.rotation_euler = (math.pi / 2, 0, 0)
        objs.append(kn)
    for o in objs:
        rotate_about_y(o, yaw, (cx, cy, cz))
    REG.collider(cx - 0.18, cy, cz - 0.18, cx + 0.18, cy + h, cz + 0.18, tag="furniture")
    return objs, dial


def rotary_phone(coll, cx, cy, cz, yaw=0.0):
    objs = [rbox("phone_base", coll, cx, cy + 0.04, cz, 0.18, 0.08, 0.2, "plastic_black", 0.03, 4)]
    objs.append(cyl("phone_dial", coll, cx, cy + 0.075, cz + 0.03, 0.055, 0.05, 0.01, "chrome", 20))
    objs.append(lib.tube("phone_handset", coll, [(cx - 0.09, cy + 0.11, cz - 0.04), (cx - 0.05, cy + 0.12, cz - 0.05), (cx + 0.05, cy + 0.12, cz - 0.05), (cx + 0.09, cy + 0.11, cz - 0.04)], 0.018, "plastic_black", segments=10))
    for s in (-1, 1):
        objs.append(soft_box(f"phone_cup{s}", coll, cx + 0.095 * s, cy + 0.1, cz - 0.04, 0.05, 0.035, 0.05, "plastic_black", 2))
    for o in objs:
        rotate_about_y(o, yaw, (cx, cy, cz))
    return objs


def coat_rack(coll, x, y, z):
    objs = [smooth(lib.lathe("rack_pole", coll, [(0.16, 0.0), (0.16, 0.02), (0.03, 0.06), (0.02, 1.7), (0.035, 1.74), (0.0, 1.8)], "wood_dark", pos=(x, y, z), segments=16))]
    for i in range(4):
        a = i / 4 * 2 * math.pi
        objs.append(lib.tube(f"rack_hook{i}", coll, [(x, y + 1.62, z), (x + math.cos(a) * 0.12, y + 1.66, z + math.sin(a) * 0.12), (x + math.cos(a) * 0.14, y + 1.71, z + math.sin(a) * 0.14)], 0.008, "brass"))
    coat = soft_box("rack_coat", coll, x + 0.04, y + 1.25, z + 0.03, 0.34, 0.75, 0.16, "fabric_blue", 2, squash=1.0)
    objs.append(coat)
    REG.collider(x - 0.04, y, z - 0.04, x + 0.04, y + 1.8, z + 0.04, tag="furniture")
    return objs


def cat_bed(coll, x, y, z):
    ring = smooth(lib.lathe("catbed_ring", coll, [(0.17, 0.0), (0.26, 0.0), (0.3, 0.05), (0.29, 0.12), (0.25, 0.15), (0.21, 0.12), (0.19, 0.04)], "cat_bed", pos=(x, y, z), segments=32))
    cushion = smooth(lib.lathe("catbed_cushion", coll, [(0.0, 0.0), (0.2, 0.0), (0.21, 0.03), (0.18, 0.05), (0.0, 0.055)], "fabric_cream", pos=(x, y, z), segments=24))
    lib.world_uv_object(ring)
    return [ring, cushion]


def bowls(coll, x, y, z):
    a = smooth(lib.lathe("bowl_food", coll, [(0.0, 0.0), (0.07, 0.0), (0.09, 0.05), (0.085, 0.055), (0.065, 0.012), (0.0, 0.012)], "ceramic", pos=(x, y, z), segments=24))
    b = smooth(lib.lathe("bowl_water", coll, [(0.0, 0.0), (0.07, 0.0), (0.09, 0.05), (0.085, 0.055), (0.065, 0.012), (0.0, 0.012)], "chrome", pos=(x + 0.3, y, z + 0.02), segments=24))
    food = smooth(lib.lathe("BOWL_FOOD", coll, [(0.0, 0.035), (0.06, 0.03), (0.075, 0.02), (0.07, 0.012)], "cat_food", pos=(x, y, z), segments=16))
    water = smooth(lib.lathe("bowl_water_surface", coll, [(0.0, 0.035), (0.078, 0.035)], "water", pos=(x + 0.3, y, z + 0.02), segments=16))
    return [a, b, water], food


def mannequin(coll, x, y, z):
    objs = [smooth(lib.lathe("dress_form", coll, [(0.0, 0.75), (0.13, 0.77), (0.17, 0.85), (0.155, 1.0), (0.13, 1.08), (0.165, 1.22), (0.17, 1.3), (0.12, 1.38), (0.05, 1.42), (0.04, 1.5), (0.0, 1.52)], "fabric_cream", pos=(x, y, z), segments=28))]
    objs[0].scale = (1.0, 0.75, 1.0)
    objs.append(cyl("dress_pole", coll, x, y + 0.05, z, 0.015, 0.015, 0.72, "wood_dark", 10))
    for i in range(3):
        a = i / 3 * 2 * math.pi
        objs.append(lib.tube(f"dress_leg{i}", coll, [(x, y + 0.2, z), (x + math.cos(a) * 0.25, y, z + math.sin(a) * 0.25)], 0.012, "wood_dark"))
    REG.collider(x - 0.27, y, z - 0.27, x + 0.27, y + 1.52, z + 0.27, tag="furniture")
    return lib.join(objs, "mannequin")


def rocking_horse(coll, x, y, z, yaw=0.0):
    objs = []
    body = soft_box("rh_body", coll, x, y + 0.42, z, 0.5, 0.18, 0.16, "wood_paint_blue", 2)
    neck = soft_box("rh_neck", coll, x + 0.22, y + 0.58, z, 0.12, 0.26, 0.1, "wood_paint_blue", 2)
    neck.rotation_euler = (0, -0.5, 0)
    head = soft_box("rh_head", coll, x + 0.32, y + 0.7, z, 0.2, 0.1, 0.09, "wood_paint_blue", 2)
    objs += [body, neck, head]
    for s in (-1, 1):
        objs.append(lib.tube(f"rh_rocker{s}", coll, [(x - 0.42, y + 0.06, z + 0.11 * s), (x - 0.2, y + 0.01, z + 0.11 * s), (x + 0.2, y + 0.01, z + 0.11 * s), (x + 0.42, y + 0.06, z + 0.11 * s)], 0.015, "wood_dark"))
        for lx in (-0.18, 0.18):
            objs.append(lib.tube(f"rh_leg{s}{lx}", coll, [(x + lx, y + 0.02, z + 0.11 * s), (x + lx * 0.8, y + 0.38, z + 0.06 * s)], 0.018, "wood_paint_blue"))
    objs.append(lib.tube("rh_tail", coll, [(x - 0.25, y + 0.45, z), (x - 0.33, y + 0.4, z), (x - 0.36, y + 0.28, z)], 0.02, "hessian"))
    for o in objs:
        rotate_about_y(o, yaw, (x, y, z))
    horse = lib.join(objs, "rocking_horse")
    bpy.context.view_layer.update()
    pts = [lib.bg(horse.matrix_world @ Vector(c)) for c in horse.bound_box]
    REG.collider(min(q[0] for q in pts), y, min(q[2] for q in pts), max(q[0] for q in pts), y + 0.75, max(q[2] for q in pts), tag="furniture")
    return horse


def trunk(coll, x0, z0, x1, z1, y, h=0.42):
    """steamer trunk; lid is a separate object named CHEST_LID with origin on the back hinge."""
    objs = [rbox_min("chest_body", coll, x0, y, z0, x1, y + h, z1, "wood_worn", 0.012, 2)]
    for xx in (x0 + 0.12, (x0 + x1) / 2, x1 - 0.12):
        objs.append(rbox_min("chest_strap", coll, xx - 0.025, y - 0.002, z0 - 0.004, xx + 0.025, y + h, z1 + 0.004, "iron", 0.003, 1))
    objs.append(rbox_min("chest_band", coll, x0 - 0.004, y + 0.1, z0 - 0.004, x1 + 0.004, y + 0.13, z1 + 0.004, "brass", 0.003, 1))
    lid = rbox_min("CHEST_LID", coll, x0, y + h, z0, x1, y + h + 0.1, z1, "wood_worn", 0.02, 3)
    strap = [rbox_min("CHEST_LID_strap", coll, xx - 0.025, y + h - 0.002, z0 - 0.004, xx + 0.025, y + h + 0.102, z1 + 0.004, "iron", 0.003, 1) for xx in (x0 + 0.12, x1 - 0.12)]
    latch = rbox("CHEST_LID_latch", coll, (x0 + x1) / 2, y + h - 0.02, z0 - 0.006, 0.06, 0.08, 0.012, "brass", 0.004, 2)
    lid = lib.join([lid] + strap + [latch], "CHEST_LID")
    # move origin to the hinge (back top edge, z1)
    hinge = gv((x0 + x1) / 2, y + h, z1)
    lid.data.transform(Matrix.Translation(-(hinge - lid.location)))
    lid.location = hinge
    REG.collider(x0, y, z0, x1, y + h, z1, tag="furniture")
    return objs, lid


def paneled_door(coll, name, width, height, style, t=0.045):
    """door leaf whose origin is at the hinge edge, extending along game +x, centred on z. Returns object."""
    parts = []
    key = {"front": "wood_paint_green", "basement": "wood_worn", "glass": "wood_paint", "interior": "wood_paint"}[style]
    if style == "glass":
        fw = 0.08
        parts.append(rbox_min(f"{name}_s1", coll, 0, 0, -t / 2, fw, height, t / 2, key, 0.006, 2))
        parts.append(rbox_min(f"{name}_s2", coll, width - fw, 0, -t / 2, width, height, t / 2, key, 0.006, 2))
        parts.append(rbox_min(f"{name}_b", coll, fw, 0, -t / 2, width - fw, 0.25, t / 2, key, 0.006, 2))
        parts.append(rbox_min(f"{name}_t", coll, fw, height - fw, -t / 2, width - fw, height, t / 2, key, 0.006, 2))
        parts.append(rbox_min(f"{name}_m", coll, fw, height * 0.5 - 0.02, -t / 2, width - fw, height * 0.5 + 0.02, t / 2, key, 0.006, 2))
        for yy in ((0.25, height * 0.5 - 0.02), (height * 0.5 + 0.02, height - fw)):
            parts.append(rbox_min(f"{name}_gl", coll, fw, yy[0], -0.004, width - fw, yy[1], 0.004, "glass", 0.0, 1))
            mid = width / 2
            parts.append(rbox_min(f"{name}_mu", coll, mid - 0.015, yy[0], -0.015, mid + 0.015, yy[1], 0.015, key, 0.004, 1))
    else:
        parts.append(rbox_min(f"{name}_slab", coll, 0, 0, -t / 2, width, height, t / 2, key, 0.006, 2))
        # raised panels both faces: 2 columns x (2 or 3) rows
        rows = [(0.12, 0.42 * height), (0.48 * height, 0.94 * height)] if style != "front" else [(0.12, 0.45 * height)]
        for side in (-1, 1):
            for (ya, yb) in rows:
                for (xa, xb) in ((0.1, width / 2 - 0.04), (width / 2 + 0.04, width - 0.1)):
                    parts.append(rbox_min(f"{name}_p", coll, xa, ya, side * t / 2, xb, yb, side * (t / 2 + 0.012), key, 0.012, 3))
        if style == "front":
            # one pane only: it used to be added once per side, two glass boxes in the same place
            parts.append(rbox_min(f"{name}_win", coll, 0.12, 0.55 * height, -0.004, width - 0.12, 0.9 * height, 0.004, "glass", 0.0, 1))
        # door knocker on the front door
    for side in (-1, 1):
        knob = smooth(lib.lathe(f"{name}_knob{side}", coll, [(0.03, 0.0), (0.03, 0.01), (0.012, 0.03), (0.012, 0.045), (0.032, 0.06), (0.03, 0.08), (0.0, 0.085)], "brass", segments=16))
        knob.location = gv(width - 0.08, 1.0, side * t / 2)
        knob.rotation_euler = (math.pi / 2 * side, 0, 0)
        parts.append(knob)
        parts.append(rbox(f"{name}_rose{side}", coll, width - 0.08, 0.95, side * (t / 2 + 0.003), 0.05, 0.16, 0.006, "brass", 0.003, 1))
    for hy in (0.25, height - 0.25):
        parts.append(cyl(f"{name}_hinge", coll, 0.0, hy - 0.05, 0.0, 0.012, 0.012, 0.1, "brass", 10))
    door = lib.join(parts, name)
    return door
