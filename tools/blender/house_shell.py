"""The house architecture: floors, ceilings, walls with openings, mouldings, window frames, stairs,
roof and porch. Ported from the web version's House.ts, with real profiles instead of boxes."""
import math

from mathutils import Vector

import lib
from lib import REG, Geo

ROOM_FLOOR_KEY = {
    "sala": "floor_sala",
    "hall": "floor_hall",
    "quarto": "floor_quarto",
    "hospedes": "floor_hospedes",
    "corredor": "floor_corredor",
    "escritorio": "floor_escritorio",
    "varanda": "floor_varanda",
    "cozinha": "floor_cozinha",
    "banheiro_cima": "floor_banheiro",
    "banheiro_baixo": "floor_banheiro_baixo",
    "porao": "floor_porao",
    "lavanderia": "floor_lavanderia",
    "sotao": "floor_sotao",
    "jantar": "floor_jantar",
    "despensa": "floor_despensa",
}
CROWN = {"wall_hall", "wall_corredor", "wall_sala", "wall_escritorio", "wall_quarto", "wall_hospedes", "wall_cozinha", "wall_jantar", "wall_despensa"}
WAINSCOT = {"wall_hall": "wainscot", "wall_corredor": "wainscot", "wall_sala": "wainscot", "wall_escritorio": "wainscot_blue", "wall_quarto": "wainscot", "wall_jantar": "wainscot"}
# lower part of some walls is tiled: key -> (tile key, height above floor, upper key)
SPLIT = {"wall_cozinha": ("wall_cozinha_tile", 1.25, "wall_cozinha"), "wall_banheiro": ("wall_banheiro", 1.55, "wall_banheiro_upper")}

BASEBOARD = [(0.0, 0.0), (0.016, 0.0), (0.016, 0.085), (0.012, 0.1), (0.006, 0.108), (0.0, 0.112)]
CROWN_PROFILE = [(0.0, 0.0), (0.012, 0.0), (0.016, 0.012), (0.03, 0.03), (0.05, 0.07), (0.056, 0.085), (0.056, 0.1), (0.0, 0.1)]
CHAIR_RAIL = [(0.0, 0.0), (0.012, 0.0), (0.022, 0.012), (0.022, 0.03), (0.012, 0.045), (0.0, 0.045)]
CASING = [(0.0, 0.0), (0.008, 0.0), (0.016, 0.02), (0.018, 0.05), (0.012, 0.07), (0.0, 0.075)]  # (out, across)


def floor_level(y):
    if y < -2:
        return -3.0
    if -0.5 < y < 0.5:
        return 0.0
    if 2.5 < y < 3.5:
        return 3.0
    return y


def rect_minus(r, holes):
    """split rect r (x0,x1,z0,z1) by axis-aligned holes into covering rects (as the TS rectMinus)."""
    out = [r]
    for h in holes:
        nxt = []
        for a in out:
            if h["x1"] <= a["x0"] or h["x0"] >= a["x1"] or h["z1"] <= a["z0"] or h["z0"] >= a["z1"]:
                nxt.append(a)
                continue
            if h["x0"] > a["x0"]:
                nxt.append(dict(x0=a["x0"], x1=h["x0"], z0=a["z0"], z1=a["z1"]))
            if h["x1"] < a["x1"]:
                nxt.append(dict(x0=h["x1"], x1=a["x1"], z0=a["z0"], z1=a["z1"]))
            ix0, ix1 = max(a["x0"], h["x0"]), min(a["x1"], h["x1"])
            if h["z0"] > a["z0"]:
                nxt.append(dict(x0=ix0, x1=ix1, z0=a["z0"], z1=h["z0"]))
            if h["z1"] < a["z1"]:
                nxt.append(dict(x0=ix0, x1=ix1, z0=h["z1"], z1=a["z1"]))
        out = nxt
    return out


class Shell:
    def __init__(self, L, coll):
        self.L = L
        self.coll = coll
        self.g = Geo("house_shell")
        self.ext = Geo("house_exterior_shell")
        self.trim = Geo("house_trim")

    # -------------------------------------------------------------- helpers

    def wall_point(self, axis, face, side, s, out, y):
        if axis == "z":
            return (face + side * out, y, s)
        return (s, y, face + side * out)

    def profile_run(self, geo, axis, face, side, s0, s1, ybase, profile, key, caps=True):
        """extrude a 2D (out, up) profile along a wall face from s0 to s1."""
        sv = Vector((side, 0, 0)) if axis == "z" else Vector((0, 0, side))
        along = Vector((0, 0, 1)) if axis == "z" else Vector((1, 0, 0))
        n = len(profile)
        for i in range(n - 1):
            o0, y0 = profile[i]
            o1, y1 = profile[i + 1]
            pts = [
                self.wall_point(axis, face, side, s0, o0, ybase + y0),
                self.wall_point(axis, face, side, s1, o0, ybase + y0),
                self.wall_point(axis, face, side, s1, o1, ybase + y1),
                self.wall_point(axis, face, side, s0, o1, ybase + y1),
            ]
            d_o, d_y = o1 - o0, y1 - y0
            hint = sv * d_y + Vector((0, -d_o, 0))
            self._poly(geo, pts, key, hint)
        if caps:
            for s, sg in ((s0, -1), (s1, 1)):
                pts = [self.wall_point(axis, face, side, s, o, ybase + y) for o, y in profile]
                self._poly(geo, pts, key, along * sg)

    def _poly(self, geo, pts, key, hint):
        a, b, c = Vector(pts[0]), Vector(pts[1]), Vector(pts[2])
        nrm = (b - a).cross(c - a)
        if nrm.length < 1e-10 and len(pts) > 3:
            nrm = (c - a).cross(Vector(pts[3]) - a)
        if nrm.dot(hint) < 0:
            pts = list(reversed(pts))
        geo.poly(pts, key)

    def col_box(self, x0, y0, z0, x1, y1, z1, tag, cam=True):
        REG.collider(x0, y0, z0, x1, y1, z1, tag=tag, cam=cam)

    # -------------------------------------------------------------- floors / ceilings

    def floors(self):
        L = self.L
        for r in L["ROOMS"]:
            rect = dict(x0=r["x0"], x1=r["x1"], z0=r["z0"], z1=r["z1"])
            key = ROOM_FLOOR_KEY[r["id"]]
            for fr in rect_minus(rect, L["FLOOR_HOLES"].get(r["id"], [])):
                self.g.box(fr["x0"], r["y"] - 0.1, fr["z0"], fr["x1"], r["y"], fr["z1"], key, keys={"ny": "ceiling" if r["y"] > 0 else key})
                self.col_box(fr["x0"], r["y"] - 0.1, fr["z0"], fr["x1"], r["y"], fr["z1"], "floor")
            if r["ceiling"]:
                for cr in rect_minus(rect, L["CEILING_HOLES"].get(r["id"], [])):
                    self.g.box(cr["x0"], r["y"] + r["h"], cr["z0"], cr["x1"], r["y"] + r["h"] + 0.1, cr["z1"], "ceiling", skip=("py",))
                    self.col_box(cr["x0"], r["y"] + r["h"], cr["z0"], cr["x1"], r["y"] + r["h"] + 0.1, cr["z1"], "ceiling")

    # -------------------------------------------------------------- walls

    def openings_on(self, w):
        out = []
        y_top = w["y"] + w["h"]

        def on(o):
            return o["axis"] == w["axis"] and abs(o["fixed"] - w["fixed"]) < 0.01 and o["s1"] > w["a"] and o["s0"] < w["b"] and o["y1"] > w["y"] and o["y0"] < y_top

        for d in self.L["DOORS"]:
            o = dict(axis=d["axis"], fixed=d["fixed"], s0=d["s0"], s1=d["s1"], y0=d["y"], y1=d["y"] + d["h"], kind="door")
            if on(o):
                out.append(o)
        for win in self.L["WINDOWS"]:
            if on(win):
                out.append(dict(win, kind="window"))
        for a in self.L["ARCHES"]:
            if on(a):
                out.append(dict(a, kind="arch"))
        return sorted(out, key=lambda o: o["s0"])

    def wall_half(self, axis, fixed, side, half, s0, s1, ya, yb, key, floor_y, skip=()):
        """one side (half thickness) of a wall segment, splitting tiled walls. skip: the end caps that
        lie in the face of a wall meeting this one at a corner (coplanar faces flicker)."""
        def emit(y0, y1, k):
            if y1 - y0 < 1e-4:
                return
            if axis == "z":
                x0, x1 = (fixed - half, fixed) if side < 0 else (fixed, fixed + half)
                self.g.box(x0, y0, s0, x1, y1, s1, k, skip=skip)
            else:
                z0, z1 = (fixed - half, fixed) if side < 0 else (fixed, fixed + half)
                self.g.box(s0, y0, z0, s1, y1, z1, k, skip=skip)

        if key in SPLIT:
            low, hgt, up = SPLIT[key]
            cut = floor_y + hgt
            if ya < cut < yb:
                emit(ya, cut, low)
                emit(cut, yb, up)
            elif yb <= cut:
                emit(ya, yb, low)
            else:
                emit(ya, yb, up)
        else:
            emit(ya, yb, key)

    def walls(self):
        for w in self.L["WALLS"]:
            self.wall(w)

    def _end_buried(self, w, s, direction):
        """does a wall at right angles have its outer face exactly where this wall ends (a corner)?
        Then this end cap lies inside that face and must not be drawn."""
        return self._end_inset(w, s, direction) > 0

    def _end_inset(self, w, s, direction):
        """thickness of the wall at right angles whose outer face is where this wall ends (0 if none): the
        skirting/wainscot/crown runs along this wall's faces stop at that wall's inner face, or their end
        caps would lie in its outer face (flush with the facade, flickering with it)."""
        for w2 in self.L["WALLS"]:
            if w2["axis"] == w["axis"]:
                continue
            face = w2["fixed"] + direction * w2["t"] / 2
            if abs(face - s) > 0.015:
                continue
            if w2["a"] > w["fixed"] + 0.001 or w2["b"] < w["fixed"] - 0.001:
                continue
            if w2["y"] >= w["y"] + w["h"] - 0.001 or w2["y"] + w2["h"] <= w["y"] + 0.001:
                continue
            return w2["t"]
        return 0.0

    def wall(self, w):
        ops = self.openings_on(w)
        y0, y1 = w["y"], w["y"] + w["h"]
        segs = []
        cur = w["a"]
        for o in ops:
            s0 = max(o["s0"], w["a"])
            s1 = min(o["s1"], w["b"])
            if s0 > cur:
                segs.append((cur, s0, y0, y1, True))
            if o["y0"] > y0:
                segs.append((s0, s1, y0, o["y0"], True))
            if o["y1"] < y1:
                segs.append((s0, s1, o["y1"], y1, False))
            cur = max(cur, s1)
        if cur < w["b"]:
            segs.append((cur, w["b"], y0, y1, True))
        half = w["t"] / 2
        fl = floor_level(w["y"])
        lo, hi = ("nz", "pz") if w["axis"] == "z" else ("nx", "px")
        inset_a = self._end_inset(w, w["a"], -1)
        inset_b = self._end_inset(w, w["b"], 1)
        bury_a, bury_b = inset_a > 0, inset_b > 0
        for s0, s1, ya, yb, base in segs:
            skip = tuple(([lo] if bury_a and abs(s0 - w["a"]) < 1e-4 else []) + ([hi] if bury_b and abs(s1 - w["b"]) < 1e-4 else []))
            for side, key in ((-1, w["neg"]), (1, w["pos"])):
                if key:
                    self.wall_half(w["axis"], w["fixed"], side, half, s0, s1, ya, yb, key, fl, skip)
            # collision for the full thickness
            if w["axis"] == "z":
                self.col_box(w["fixed"] - half, ya, s0, w["fixed"] + half, yb, s1, "wall")
            else:
                self.col_box(s0, ya, w["fixed"] - half, s1, yb, w["fixed"] + half, "wall")
            # the trim runs along the room-side faces only, between the faces of the walls at the corners
            p0 = s0 + inset_a if abs(s0 - w["a"]) < 1e-4 else s0
            p1 = s1 - inset_b if abs(s1 - w["b"]) < 1e-4 else s1
            if p1 - p0 < 1e-3:
                continue
            for side, key in ((-1, w["neg"]), (1, w["pos"])):
                if not key or key.startswith("exterior"):
                    continue
                face = w["fixed"] + side * half
                if key in CROWN and yb >= y1 - 0.01:
                    self.profile_run(self.trim, w["axis"], face, side, p0, p1, y1 - 0.1, CROWN_PROFILE, "trim")
                wk = WAINSCOT.get(key)
                if wk and ya <= y0 + 0.01:
                    top = min(fl + 1.0, yb)
                    if top > fl + 0.2:
                        self.profile_run(self.trim, w["axis"], face, side, p0, p1, fl, [(0, 0), (0.01, 0), (0.01, top - fl), (0, top - fl)], wk, caps=True)
                        if top >= fl + 0.99:
                            self.profile_run(self.trim, w["axis"], face, side, p0, p1, top - 0.02, CHAIR_RAIL, "trim")
                if base:
                    self.profile_run(self.trim, w["axis"], face, side, p0, p1, fl, BASEBOARD, "trim")

    # -------------------------------------------------------------- openings

    def casing(self, o, face_offsets, key="trim"):
        """door/arch casing on both faces of the wall."""
        for side, face in face_offsets:
            s0, s1, y0, y1 = o["s0"], o["s1"], o["y0"], o["y1"]
            tw = 0.075
            # jambs (profile runs vertically): emulate with thin boxes + bevel-ish front
            for sA, sB in ((s0 - tw, s0), (s1, s1 + tw)):
                self.casing_strip(o["axis"], face, side, sA, sB, y0, y1, key)
            self.casing_strip(o["axis"], face, side, s0 - tw, s1 + tw, y1, y1 + tw, key)

    def casing_strip(self, axis, face, side, sA, sB, yA, yB, key):
        d = 0.018
        if axis == "z":
            xa, xb = sorted((face, face + side * d))
            self.trim.box(xa, yA, sA, xb, yB, sB, key)
        else:
            za, zb = sorted((face, face + side * d))
            self.trim.box(sA, yA, za, sB, yB, zb, key)

    def doors_trims(self):
        L = self.L
        for d in L["DOORS"]:
            wt = 0.2 if d["style"] == "front" else 0.12
            o = dict(axis=d["axis"], fixed=d["fixed"], s0=d["s0"], s1=d["s1"], y0=d["y"], y1=d["y"] + d["h"])
            self.casing(o, ((-1, d["fixed"] - wt / 2), (1, d["fixed"] + wt / 2)), "trim" if d["style"] != "front" else "exterior_trim")
            # jamb lining inside the opening
            self.jamb(o, wt)
        for a in L["ARCHES"]:
            o = dict(axis=a["axis"], fixed=a["fixed"], s0=a["s0"], s1=a["s1"], y0=a["y0"], y1=a["y1"])
            self.casing(o, ((-1, a["fixed"] - 0.06), (1, a["fixed"] + 0.06)))
            self.jamb(o, 0.12)

    def jamb(self, o, wt):
        h = wt / 2 + 0.002
        t = 0.015
        if o["axis"] == "z":
            self.trim.box(o["fixed"] - h, o["y0"], o["s0"], o["fixed"] + h, o["y1"], o["s0"] + t, "trim")
            self.trim.box(o["fixed"] - h, o["y0"], o["s1"] - t, o["fixed"] + h, o["y1"], o["s1"], "trim")
            self.trim.box(o["fixed"] - h, o["y1"] - t, o["s0"], o["fixed"] + h, o["y1"], o["s1"], "trim")
        else:
            self.trim.box(o["s0"], o["y0"], o["fixed"] - h, o["s0"] + t, o["y1"], o["fixed"] + h, "trim")
            self.trim.box(o["s1"] - t, o["y0"], o["fixed"] - h, o["s1"], o["y1"], o["fixed"] + h, "trim")
            self.trim.box(o["s0"], o["y1"] - t, o["fixed"] - h, o["s1"], o["y1"], o["fixed"] + h, "trim")

    def windows(self):
        for w in self.L["WINDOWS"]:
            self.window(w)

    def window(self, w):
        t = 0.2
        fw = 0.05
        g = self.trim
        ins = w["inside"]
        ext_key = "exterior_trim"

        def L(s0, s1, y0, y1, n0, n1, key):
            if w["axis"] == "z":
                g.box(w["fixed"] + n0, y0, s0, w["fixed"] + n1, y1, s1, key)
            else:
                g.box(s0, y0, w["fixed"] + n0, s1, y1, w["fixed"] + n1, key)

        s0, s1, y0, y1 = w["s0"], w["s1"], w["y0"], w["y1"]
        # frame lining in the opening
        L(s0, s1, y0, y0 + fw, -t / 2, t / 2, "trim")
        L(s0, s1, y1 - fw, y1, -t / 2, t / 2, "trim")
        L(s0, s0 + fw, y0 + fw, y1 - fw, -t / 2, t / 2, "trim")
        L(s1 - fw, s1, y0 + fw, y1 - fw, -t / 2, t / 2, "trim")
        # sash: double hung look with meeting rail and a centre mullion
        if not w.get("small"):
            mid = (s0 + s1) / 2
            L(mid - 0.022, mid + 0.022, y0 + fw, y1 - fw, -0.035, 0.035, "trim")
            my = y0 + (y1 - y0) * 0.52
            L(s0 + fw, s1 - fw, my - 0.03, my + 0.03, -0.04, 0.04, "trim")
            for q in (0.25, 0.75):
                xs = s0 + (s1 - s0) * q
                L(xs - 0.01, xs + 0.01, my + 0.03, y1 - fw, -0.02, 0.02, "trim")
        if w["id"] != "w_basculante":
            L(s0 + fw, s1 - fw, y0 + fw, y1 - fw, -0.004, 0.004, "glass")
        # interior sill (a ledge cats love) + apron
        sill_d = 0.12 if w.get("small") else 0.22
        if ins > 0:
            L(s0 - 0.06, s1 + 0.06, y0 - 0.04, y0 + 0.004, t / 2 - 0.02, t / 2 + sill_d, "trim")
            L(s0 - 0.03, s1 + 0.03, y0 - 0.12, y0 - 0.04, t / 2, t / 2 + 0.018, "trim")
            n_in0, n_in1 = t / 2, t / 2 + sill_d
        else:
            L(s0 - 0.06, s1 + 0.06, y0 - 0.04, y0 + 0.004, -t / 2 - sill_d, -t / 2 + 0.02, "trim")
            L(s0 - 0.03, s1 + 0.03, y0 - 0.12, y0 - 0.04, -t / 2 - 0.018, -t / 2, "trim")
            n_in0, n_in1 = -t / 2 - sill_d, -t / 2
        # sill collision (cats sit on it)
        if w["axis"] == "z":
            REG.collider(w["fixed"] + n_in0, y0 - 0.04, s0 - 0.06, w["fixed"] + n_in1, y0 + 0.004, s1 + 0.06, tag="sill")
        else:
            REG.collider(s0 - 0.06, y0 - 0.04, w["fixed"] + n_in0, s1 + 0.06, y0 + 0.004, w["fixed"] + n_in1, tag="sill")
        # the opening itself: an invisible wall for the cat only (Godot LAYER_CAT_BLOCK), so it can sit on
        # the sill but never walk or jump out; the official ways out (basculante, basement window, tree)
        # are interactions that move the cat through
        if w["axis"] == "z":
            REG.collider(w["fixed"] - 0.06, y0 - 0.04, s0, w["fixed"] + 0.06, y1, s1, tag="window", cat_only=True)
        else:
            REG.collider(s0, y0 - 0.04, w["fixed"] - 0.06, s1, y1, w["fixed"] + 0.06, tag="window", cat_only=True)
        # interior casing
        face_in = w["fixed"] + ins * t / 2
        for (a, b, c, d) in ((s0 - 0.07, s0, y0, y1), (s1, s1 + 0.07, y0, y1), (s0 - 0.07, s1 + 0.07, y1, y1 + 0.07)):
            self.casing_strip(w["axis"], face_in, ins, a, b, c, d, "trim")
        # exterior: sill, head and shutters-style casing
        face_out = w["fixed"] - ins * t / 2
        # (they start just above the sill, which already covers the strips' feet)
        for (a, b, c, d) in ((s0 - 0.08, s0, y0 + 0.004, y1), (s1, s1 + 0.08, y0 + 0.004, y1), (s0 - 0.12, s1 + 0.12, y1, y1 + 0.1)):
            self.casing_strip(w["axis"], face_out, -ins, a, b, c, d, ext_key)
        if ins > 0:
            L(s0 - 0.08, s1 + 0.08, y0 - 0.06, y0 + 0.004, -t / 2 - 0.09, -t / 2 + 0.02, ext_key)
        else:
            L(s0 - 0.08, s1 + 0.08, y0 - 0.06, y0 + 0.004, t / 2 - 0.02, t / 2 + 0.09, ext_key)

    # -------------------------------------------------------------- stairs

    def stairs(self):
        L = self.L
        g = self.trim
        s = L["STAIR_MAIN"]
        n = 16
        run = (s["z1"] - s["z0"]) / n
        rise = 3.0 / n
        for k in range(n):
            z0 = s["z0"] + k * run
            top = (k + 1) * rise
            # riser + solid body
            g.box(s["x0"], top - rise, z0, s["x1"] - 0.04, top - 0.025, z0 + run, "stair_wood")
            # tread with nosing
            g.box(s["x0"], top - 0.025, z0 - 0.025, s["x1"], top, z0 + run, "stair_wood")
            # under-stair closed panel (seen from the hall)
            g.box(s["x1"] - 0.04, 0, z0, s["x1"] - 0.02, top - 0.025, z0 + run, "wood_paint")
        # open stringer, balusters and rail
        ang = math.atan2(3.0, s["z1"] - s["z0"])
        for k in range(n):
            z = s["z0"] + k * run + run * 0.5
            y = (k + 1) * rise
            lib.lathe(f"baluster_m{k}", self.coll, [(0.016, 0), (0.016, 0.06), (0.022, 0.09), (0.012, 0.16), (0.014, 0.62), (0.02, 0.7), (0.014, 0.76), (0.014, 0.86)],
                      "wood_paint", pos=(s["x1"] - 0.03, y, z), segments=10)
        rail_pts = [(s["x1"] - 0.03, 0.95 + rise, s["z0"]), (s["x1"] - 0.03, 0.95 + 3.0, s["z1"])]
        lib.tube("handrail_main", self.coll, rail_pts, 0.03, "trim_dark", segments=10)
        lib.lathe("newel_bottom", self.coll, [(0.06, 0), (0.06, 0.1), (0.045, 0.14), (0.04, 0.9), (0.055, 0.98), (0.06, 1.05), (0.035, 1.12), (0.0, 1.16)],
                  "trim_dark", pos=(s["x1"] - 0.03, 0, s["z0"] - 0.06), segments=16)
        # ramp collider (smooth walking surface through the tread midpoints)
        za = s["z0"] - run * 0.5
        zb = s["z1"] - run * 0.5
        self.ramp((s["x0"] + s["x1"]) / 2, s["x1"] - s["x0"], za, zb, 0.0, 3.0, "stair")
        REG.collider(s["x0"], 2.9, zb, s["x1"], 3.0, s["z1"] + 0.01, tag="stair")
        # rail guards (not for the camera)
        REG.collider(s["x1"] - 0.05, 0.0, s["z0"], s["x1"] + 0.02, 4.0, s["z1"], tag="rail", cam=False)
        # first floor railing around the stair hole
        fy = 3.0
        g.box(s["x1"] - 0.03, fy + 0.9, s["z0"], s["x1"] + 0.03, fy + 0.95, s["z1"], "trim_dark")
        g.box(s["x0"], fy + 0.9, s["z0"] - 0.03, s["x1"] + 0.03, fy + 0.95, s["z0"] + 0.03, "trim_dark")
        z = s["z0"] + 0.14
        i = 0
        while z <= s["z1"] - 0.05:
            lib.lathe(f"baluster_t{i}", self.coll, [(0.016, 0), (0.02, 0.05), (0.012, 0.12), (0.014, 0.8), (0.02, 0.86), (0.014, 0.9)], "wood_paint", pos=(s["x1"], fy, z), segments=8)
            z += 0.2
            i += 1
        x = s["x0"] + 0.15
        while x <= s["x1"]:
            lib.lathe(f"baluster_u{i}", self.coll, [(0.016, 0), (0.02, 0.05), (0.012, 0.12), (0.014, 0.8), (0.02, 0.86), (0.014, 0.9)], "wood_paint", pos=(x, fy, s["z0"]), segments=8)
            x += 0.2
            i += 1
        REG.collider(s["x1"] - 0.04, fy, s["z0"], s["x1"] + 0.04, fy + 0.95, s["z1"], tag="rail", cam=False)
        REG.collider(s["x0"], fy, s["z0"] - 0.04, s["x1"] + 0.04, fy + 0.95, s["z0"] + 0.04, tag="rail", cam=False)
        REG.collider(s["x1"] - 0.03, fy + 0.9, s["z0"], s["x1"] + 0.03, fy + 0.95, s["z1"], tag="railtop")
        # the cat must not hop onto the handrail and over it into the stairwell: invisible wall up to 1.2 m,
        # for the cat only (floor raycasts still see the rail, the jump sweep does not get past it)
        REG.collider(s["x1"] - 0.07, fy, s["z0"] - 0.07, s["x1"] + 0.07, fy + 1.2, s["z1"], tag="rail_block", cat_only=True)
        REG.collider(s["x0"], fy, s["z0"] - 0.07, s["x1"] + 0.07, fy + 1.2, s["z0"] + 0.07, tag="rail_block", cat_only=True)

        # basement stairs (x 11..12, rising +z from y -3 to 0)
        b = L["STAIR_BASE"]
        run = (b["z1"] - b["z0"]) / n
        for k in range(n):
            z0 = b["z0"] + k * run
            top = -3 + (k + 1) * rise
            g.box(b["x0"] + 0.04, top - rise, z0, b["x1"], top - 0.03, z0 + run, "stair_wood")
            g.box(b["x0"], top - 0.03, z0 - 0.02, b["x1"], top, z0 + run, "stair_wood")
            if k % 2 == 0:
                g.box(b["x0"] + 0.01, top, z0 + 0.06, b["x0"] + 0.045, top + 0.9, z0 + 0.095, "wood_worn")
        g.box(b["x0"] - 0.02, -3 + 0.08, b["z0"], b["x0"] + 0.06, -3 + 0.25, b["z1"], "wood_worn")  # stringer
        lib.tube("handrail_base", self.coll, [(b["x0"] + 0.03, -3 + 0.9 + rise, b["z0"]), (b["x0"] + 0.03, 0.9, b["z1"])], 0.025, "wood_worn")
        za = b["z0"] - run * 0.5
        zb = b["z1"] - run * 0.5
        self.ramp((b["x0"] + b["x1"]) / 2, b["x1"] - b["x0"], za, zb, -3.0, 0.0, "stair")
        REG.collider(b["x0"], -0.1, zb, b["x1"], 0.0, b["z1"] + 0.01, tag="stair")
        REG.collider(b["x0"] - 0.03, -3.0, b["z0"], b["x0"] + 0.04, 1.0, b["z1"], tag="rail", cam=False)

    def ramp(self, cx, width, za, zb, ya, yb, tag):
        run = zb - za
        rise = yb - ya
        length = math.hypot(run, rise)
        ang = math.atan2(rise, run)
        th = 0.12
        # centre of the box: midpoint of the top surface pushed down half the thickness along the normal
        nz, ny = -math.sin(ang), math.cos(ang)
        cz = (za + zb) / 2 - nz * th / 2
        cy = (ya + yb) / 2 - ny * th / 2
        c, s_ = math.cos(-ang), math.sin(-ang)
        # rotation about game X by -ang (so +z rises): rows of the basis
        basis = [[1, 0, 0], [0, c, -s_], [0, s_, c]]
        REG.colliders.append({"obb": True, "center": [cx, cy, cz], "size": [width, th, length], "basis": basis, "tag": tag, "cam": False})

    # -------------------------------------------------------------- roof

    def roof(self):
        g = self.ext
        knee = self.L["ATTIC"]["knee"]   # the attic has low side walls: the slope starts this far above its floor
        ridge_y = 8.4 + knee
        ang = math.atan2(2.4, 3.75)
        for side in (-1, 1):
            eave_x = -0.5 if side < 0 else 8.0
            ridge_x = 3.75
            # slope as a quad strip (outer slates, inner planks)
            def y_at(x):
                return 6 + knee + (x if side < 0 else 7.5 - x) * math.tan(ang)
            za, zb = -0.45, 10.45
            for key, off, flip in (("roof", 0.12, False), ("roof_under", 0.02, True)):
                xa, xb = (eave_x, ridge_x) if side < 0 else (ridge_x, eave_x)
                pts = [(xa, y_at(xa) + off, za), (xb, y_at(xb) + off, za), (xb, y_at(xb) + off, zb), (xa, y_at(xa) + off, zb)]
                hint = Vector((side * math.sin(ang), math.cos(ang), 0)) * (-1 if flip else 1)
                pts_uv = None
                self._poly_slope(g, pts, key, hint)
            # roof thickness edge (fascia) at the eave
            x = eave_x
            yy = y_at(x)
            self.trim.box(x - 0.03, yy - 0.12, za, x + 0.03, yy + 0.16, zb, "exterior_trim")
            # gutter
            lib.tube(f"gutter_{side}", self.coll, [(x + side * 0.08, yy - 0.06, za), (x + side * 0.08, yy - 0.06, zb)], 0.055, "metal_painted", segments=10)
            for i in range(8):
                xa = (i / 8) * 3.75 if side < 0 else 7.5 - ((i + 1) / 8) * 3.75
                xb = xa + 3.75 / 8
                low = min(y_at(xa), y_at(xb))
                REG.collider(xa, low, -0.1, xb, ridge_y + 0.6, 10.1, tag="roof", cam=True)
        self.trim.box(3.6, ridge_y + 0.08, -0.45, 3.9, ridge_y + 0.22, 10.45, "roof")
        # gables
        for z in (0.0, 10.0):
            front = z == 0.0
            for key, z0, z1, hint_z in (("exterior", -0.1 if front else 10.0, 0.0 if front else 10.1, -1 if front else 1), ("wall_attic", 0.0 if front else 9.9, 0.1 if front else 10.0, 1 if front else -1)):
                zf = z0 if hint_z < 0 else z1
                tri = [(-0.1, 6.0 + knee, zf), (7.6, 6.0 + knee, zf), (3.75, ridge_y + 0.06, zf)]
                if front:
                    # leave a round hole for the oculus: build as a fan of quads around it
                    self.gable_with_hole(g if key == "exterior" else self.g, tri, zf, key, hint_z)
                else:
                    self._poly(g if key == "exterior" else self.g, tri, key, Vector((0, 0, hint_z)))
                # band between the first floor walls and the gable
                # (between the attic side walls, which already cover x -0.1..0 and 7.5..7.6 over the whole depth)
                (g if key == "exterior" else self.g).box(0.0, 5.8, z0, 7.5, 6.0 + knee, z1, key)
            REG.collider(-0.1, 6, -0.1 if front else 9.9, 7.6, ridge_y, 0.1 if front else 10.1, tag="wall", cam=True)
        # the low side walls of the attic (the roof slope rests on them), outside skin and inside skin
        for xo0, xo1, xi0, xi1 in ((-0.1, 0.0, 0.0, 0.1), (7.5, 7.6, 7.4, 7.5)):
            self.ext.box(xo0, 5.8, -0.1, xo1, 6.0 + knee, 10.1, "exterior")
            self.g.box(xi0, 5.8, 0.1, xi1, 6.0 + knee, 9.9, "wall_attic")
            REG.collider(min(xo0, xi0), 6, -0.1, max(xo1, xi1), 6.0 + knee, 10.1, tag="wall", cam=True)
        # oculus frame + glass
        ring = lib.lathe("oculus_frame", self.coll, [(0.38, -0.06), (0.46, -0.06), (0.46, 0.04), (0.38, 0.04), (0.38, -0.06)], "exterior_trim", segments=32, cap=False)
        oy = 7.15 + knee
        ring.location = lib.gv(3.75, oy, -0.02)
        ring.rotation_euler = (math.pi / 2, 0.0, 0.0)  # lathe axis (game y) -> game +z
        self.trim.box(3.75 - 0.4, oy - 0.015, -0.03, 3.75 + 0.4, oy + 0.015, 0.0, "exterior_trim")
        self.trim.box(3.75 - 0.015, oy - 0.4, -0.03, 3.75 + 0.015, oy + 0.4, 0.0, "exterior_trim")
        disc = []
        for i in range(24):
            a = i / 24 * 2 * math.pi
            disc.append((3.75 + math.cos(a) * 0.4, oy + math.sin(a) * 0.4, -0.01))
        self._poly(self.trim, disc, "glass", Vector((0, 0, -1)))
        # bathroom flat roof + parapet
        self.ext.box(7.5, 5.9, 5.9, 12.1, 6.0, 10.1, "roof")
        REG.collider(7.5, 5.9, 5.9, 12.1, 6.0, 10.1, tag="roof", cam=True)
        self.trim.box(7.5, 6.0, 5.9, 12.15, 6.14, 5.98, "exterior_trim")
        self.trim.box(12.07, 6.0, 5.98, 12.15, 6.14, 10.07, "exterior_trim")
        self.trim.box(7.5, 6.0, 10.07, 12.15, 6.14, 10.15, "exterior_trim")
        # back wing (dining room + pantry): one storey, flat roof with a low parapet
        # (the slab stops at the parapet's inner face: its side ends used to lie in the same plane as the
        # parapet's, flush with the first-floor wall)
        self.ext.box(-0.1, 2.82, 10.0, 12.1, 2.96, 13.1, "roof")
        REG.collider(-0.15, 2.82, 10.0, 12.15, 2.96, 13.15, tag="roof", cam=True)
        self.trim.box(-0.18, 2.6, 13.1, 12.18, 3.1, 13.18, "exterior_trim")
        self.trim.box(-0.18, 2.6, 10.0, -0.1, 3.1, 13.1, "exterior_trim")
        self.trim.box(12.1, 2.6, 10.0, 12.18, 3.1, 13.1, "exterior_trim")
        # eave boards over the first floor
        self.trim.box(-0.5, 5.6, -0.42, 8.0, 5.74, -0.34, "exterior_trim")
        self.trim.box(-0.5, 5.6, 10.34, 8.0, 5.74, 10.42, "exterior_trim")

    def _poly_slope(self, g, pts, key, hint):
        # uv along the slope: u = z, v = distance along slope
        a, b = Vector(pts[0]), Vector(pts[1])
        span = (b - a).length
        uvs = [(pts[0][2], 0.0), (pts[1][2], span), (pts[2][2], span), (pts[3][2], 0.0)]
        nrm = (Vector(pts[1]) - Vector(pts[0])).cross(Vector(pts[2]) - Vector(pts[0]))
        if nrm.dot(hint) < 0:
            pts = list(reversed(pts))
            uvs = list(reversed(uvs))
        g.poly(pts, key, uvs=uvs)

    def gable_with_hole(self, g, tri, zf, key, hint_z):
        """front gable triangle with a circular hole at the oculus (3.75, 7.15, r=0.42)."""
        cx, cy, r = 3.75, 7.15 + self.L["ATTIC"]["knee"], 0.42
        n = 32
        circle = [(cx + math.cos(i / n * 2 * math.pi) * r, cy + math.sin(i / n * 2 * math.pi) * r) for i in range(n)]
        # project each circle point outward onto the triangle boundary (ray from centre)
        (ax, ay, _), (bx, by, _), (tx, ty, _) = tri
        edges = [((ax, ay), (bx, by)), ((bx, by), (tx, ty)), ((tx, ty), (ax, ay))]

        def ray_hit(dx, dy):
            best = None
            for (p0, p1) in edges:
                ex, ey = p1[0] - p0[0], p1[1] - p0[1]
                den = dx * ey - dy * ex
                if abs(den) < 1e-9:
                    continue
                t = ((p0[0] - cx) * ey - (p0[1] - cy) * ex) / den
                u = ((p0[0] - cx) * dy - (p0[1] - cy) * dx) / den
                if t > 0 and -1e-6 <= u <= 1 + 1e-6 and (best is None or t < best):
                    best = t
            return (cx + dx * best, cy + dy * best)

        outer = [ray_hit(px - cx, py - cy) for px, py in circle]
        for i in range(n):
            j = (i + 1) % n
            pts = [(circle[i][0], circle[i][1], zf), (outer[i][0], outer[i][1], zf), (outer[j][0], outer[j][1], zf), (circle[j][0], circle[j][1], zf)]
            self._poly(g, pts, key, Vector((0, 0, hint_z)))
        # the triangle corners are not covered by the radial fan; add them as triangles
        for corner in ((ax, ay), (bx, by), (tx, ty)):
            # nearest two outer points around the corner
            angs = [math.atan2(oy - cy, ox - cx) for ox, oy in outer]
            ca = math.atan2(corner[1] - cy, corner[0] - cx)
            idx = min(range(n), key=lambda k: (angs[k] - ca) % (2 * math.pi))
            prev = (idx - 1) % n
            pts = [(outer[prev][0], outer[prev][1], zf), (corner[0], corner[1], zf), (outer[idx][0], outer[idx][1], zf)]
            self._poly(g, pts, key, Vector((0, 0, hint_z)))

    # -------------------------------------------------------------- porch / balcony / base

    def porch(self):
        L = self.L
        ty = L["TERRAIN_Y"]
        g = self.ext
        # house base band of stone where the basement meets the ground, open around the little
        # basement windows (they sit inside its height: a solid band hid them from the yard)
        def band(axis, fixed, n0, n1, a, b):
            low = [w for w in L["WINDOWS"] if w["axis"] == axis and abs(w["fixed"] - fixed) < 0.01 and w["y1"] < -0.18]
            cuts = sorted((w["s0"] - 0.12, w["s1"] + 0.12, w["y0"] - 0.06, w["y1"] + 0.1) for w in low)

            def put(s0, y0, s1, y1):
                if s1 - s0 > 1e-3 and y1 - y0 > 1e-3:
                    if axis == "x":
                        g.box(s0, y0, n0, s1, y1, n1, "exterior_base")
                    else:
                        g.box(n0, y0, s0, n1, y1, s1, "exterior_base")

            s = a
            for c0, c1, cy0, cy1 in cuts:
                put(s, ty - 0.05, c0, -0.18)
                put(c0, ty - 0.05, c1, cy0)
                put(c0, cy1, c1, -0.18)
                s = c1
            put(s, ty - 0.05, b, -0.18)

        band("x", 0, -0.16, -0.1, -0.16, 12.16)
        band("x", 10, 10.1, 10.16, -0.16, 12.16)
        band("z", 0, -0.16, -0.1, -0.1, 10.1)
        band("z", 12, 12.1, 12.16, -0.1, 10.1)
        # skirting board above the stone
        self.trim.box(-0.17, -0.2, -0.17, 12.17, -0.1, -0.1, "exterior_trim")
        # back steps under the back door of the dining room (d_back, x 6.5..7.35)
        for i, top in enumerate((-0.02, -0.32, -0.62)):
            g.box(6.3, ty, 13.1 + i * 0.32, 7.55, top, 13.1 + (i + 1) * 0.32, "porch_wood")
            REG.collider(6.3, ty, 13.1 + i * 0.32, 7.55, top, 13.1 + (i + 1) * 0.32, tag="porch", cam=True)
        # a flat stone under the cat flap of the pantry: a step back up to it
        # (it starts at the top of the dirt band, 3 cm above the lawn: its back face is no longer in the band's)
        g.box(10.45, ty + 0.03, 13.15, 11.1, -0.48, 13.6, "exterior_base")
        REG.collider(10.45, ty, 13.15, 11.1, -0.48, 13.6, tag="porch", cam=True)
        # porch deck
        g.box(5.2, ty, -1.6, 7.8, 0.0, 0.0, "porch_wood")
        REG.collider(5.2, ty, -1.6, 7.8, 0.0, 0.0, tag="porch", cam=True)
        # three steps: a fourth would be flat on the lawn (and flicker with it)
        for i in range(3):
            top = -0.225 * (i + 1)
            g.box(5.7, ty, -1.6 - (i + 1) * 0.3, 7.2, top, -1.6 - i * 0.3, "porch_wood")
            REG.collider(5.7, ty, -1.6 - (i + 1) * 0.3, 7.2, top, -1.6 - i * 0.3, tag="porch", cam=True)
        for x in (5.3, 7.7):
            lib.lathe(f"porch_col_{x}", self.coll, [(0.09, 0), (0.09, 0.12), (0.07, 0.18), (0.055, 0.3), (0.06, 2.2), (0.08, 2.35), (0.09, 2.48), (0.09, 2.6)], "exterior_trim", pos=(x, 0, -1.5), segments=16)
            REG.collider(x - 0.08, 0, -1.58, x + 0.08, 2.6, -1.42, tag="post")
        # porch roof
        self.ext.box(5.0, 2.6, -1.95, 8.0, 2.74, 0.0, "roof")
        self.trim.box(5.0, 2.5, -1.97, 8.0, 2.62, -1.88, "exterior_trim")
        # porch railing
        for x0, x1 in ((5.2, 5.7), (7.2, 7.8)):
            self.trim.box(x0, 0.82, -1.58, x1, 0.88, -1.48, "exterior_trim")
            xx = x0 + 0.06
            while xx < x1 - 0.02:
                self.trim.box(xx - 0.015, 0.0, -1.545, xx + 0.015, 0.82, -1.515, "exterior_trim")
                xx += 0.12
        # balcony railing (first floor, open terrace over the kitchen/bath)
        x = 7.62
        while x < 12.0:
            self.trim.box(x - 0.02, 3.0, -0.02, x + 0.02, 3.95, 0.02, "exterior_trim")
            x += 0.16
        z = 0.12
        while z < 6.0:
            self.trim.box(11.98, 3.0, z - 0.02, 12.02, 3.95, z + 0.02, "exterior_trim")
            z += 0.16
        self.trim.box(7.5, 3.95, -0.05, 12.06, 4.02, 0.05, "exterior_trim")
        self.trim.box(11.94, 3.95, 0.05, 12.06, 4.02, 6.0, "exterior_trim")
        self.trim.box(7.5, 2.8, -0.12, 12.12, 3.0, 0.0, "exterior_trim")
        self.trim.box(12.0, 2.8, 0.0, 12.12, 3.0, 6.0, "exterior_trim")
        REG.collider(7.5, 3.0, -0.4, 12.4, 6.5, 0.02, tag="blocker", cam=False)
        REG.collider(11.98, 3.0, -0.4, 12.4, 6.5, 6.0, tag="blocker", cam=False)
        REG.collider(7.5, 3.95, -0.05, 12.06, 4.02, 0.05, tag="railtop")
        REG.collider(11.94, 3.95, -0.05, 12.06, 4.02, 6.0, tag="railtop")

    # -------------------------------------------------------------- build

    def build(self):
        self.floors()
        self.walls()
        self.doors_trims()
        self.windows()
        self.stairs()
        self.roof()
        self.porch()
        objs = [self.g.build(self.coll), self.ext.build(self.coll), self.trim.build(self.coll)]
        return objs
