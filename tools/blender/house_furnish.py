"""Furniture, fixtures and the named dynamic objects of every room.
Positions follow the original web version (House.ts) so gameplay spots still line up."""
import math

import bpy
from mathutils import Matrix

import house_custom as C
import lib
from lib import REG, gv

PI = math.pi
HALF = PI / 2


def ph(coll, mid, pos, yaw=0.0, **kw):
    return lib.place_ph(mid, coll, pos, yaw, **kw)


def name_all(objs, prefix):
    for i, o in enumerate(objs):
        if o is not None:
            o.name = f"{prefix}_{i}" if len(objs) > 1 else prefix


def boxes(coll, cx, cz, y, sizes, seed=0, name="box"):
    """stack of cardboard boxes (Poly Haven) with slight random offsets. sizes: list of (w, h, d)."""
    r = lib.rng(seed)
    yy = y
    for i, (w, h, d) in enumerate(sizes):
        jx, jz = r.uniform(-0.04, 0.04), r.uniform(-0.04, 0.04)
        _, _, (mn, mx) = ph(coll, "cardboard_box_01", (cx + jx, yy, cz + jz), r.uniform(-0.25, 0.25) + (HALF if w < d else 0), fit=(max(w, d), h, None), name=f"{name}_{i}", col="box")
        yy = mx[1] - 0.004
    return yy


def painting(coll, mid, axis_wall, fixed, normal, s, y, fit_w, name):
    """hang a frame on a wall. axis_wall 'x' = wall runs along x at z=fixed; 'z' = along z at x=fixed."""
    if axis_wall == "x":
        yaw = 0.0 if normal > 0 else PI
        pos = (s, y, fixed + normal * 0.012)
    else:
        yaw = HALF if normal > 0 else -HALF
        pos = (fixed + normal * 0.012, y, s)
    return ph(coll, mid, pos, yaw, fit=(fit_w, None, None), anchor="back", name=name)


def books_on(coll, x0, x1, z, y, yaw, seed, name, depth_axis="z"):
    """a row of encyclopedia volumes standing between x0 and x1 (or z range) at height y."""
    r = lib.rng(seed)
    length = x1 - x0
    s = 0.0
    k = 0
    while s < length - 0.1:
        n = r.randint(4, 9)
        parts = [f"book_encyclopedia_set_01_book{str(r.randint(1, 20)).zfill(2)}" for _ in range(n)]
        w = min(length - s, n * 0.028)
        if depth_axis == "z":
            pos = (x0 + s + w / 2, y, z)
        else:
            pos = (z, y, x0 + s + w / 2)
        sc = r.uniform(0.82, 1.0)
        ph(coll, "book_encyclopedia_set_01", pos, yaw, scale=sc, parts=parts[:1], name=f"{name}_{k}")
        s += w + r.uniform(0.02, 0.12)
        k += 1


def furnish(L, coll):
    q = 3.0  # first floor
    a = 6.0  # attic
    b = -3.0  # basement

    # ================================================================== SALA
    C.rug(coll, "rug_sala", 1.1, 2.15, 3.9, 4.25, 0, "rug_red")
    ph(coll, "sofa_03", (2.5, 0, 1.42), 0.0, fit=(2.6, None, 0.95), col=("seat", 0.46, 0.98, 0.32, "-z"), name="sofa")
    ph(coll, "CoffeeTable_01", (2.6, 0, 3.05), 0.0, fit=(1.3, None, 0.8), col="top", name="coffee_table")
    tvc = C.counter(coll, "tv_cabinet", 1.75, 4.98, 3.25, 5.44, 0.0, 0.55, front="-z", body="wood_dark", top="wood_dark")
    ph(coll, "Television_01", (2.5, 0.55, 5.2), PI, fit=(0.66, None, None), col="box", name="TV")
    ph(coll, "GreenChair_01", (0.72, 0, 3.85), HALF, fit=(0.72, None, None), col=("seat", 0.48, 1.0, 0.28, "-x"), name="armchair")
    ph(coll, "wooden_bookshelf_worn", (0.3, 0, 4.92), HALF, fit=(1.0, 1.9, 0.4), col="box", name="shelf_sala")
    ph(coll, "vintage_grandfather_clock_01", (0.24, 0, 1.0), HALF, fit=(None, 2.15, None), col="box", name="CLOCK")
    REG.nodes["clock"] = [0.3, 1.75, 1.0]
    ph(coll, "potted_plant_01", (4.55, 0, 5.05), 0.4, fit=(None, 1.25, None), col=None, name="plant_sala")
    boxes(coll, 4.5, 0.55, 0, [(0.55, 0.42, 0.5), (0.45, 0.36, 0.42)], 1, "box_sala_a")
    boxes(coll, 4.45, 3.2, 0, [(0.5, 0.35, 0.45)], 2, "box_sala_b")
    C.radiator(coll, 1.6, 3.4, 0.1, 0.12, 0.6, 1)
    painting(coll, "fancy_picture_frame_01", "x", 5.44, -1, 2.5, 1.72, 0.7, "paint_sala_tv")
    painting(coll, "fancy_picture_frame_02", "z", 4.94, -1, 4.3, 1.55, 0.55, "paint_sala_e")
    ph(coll, "Chandelier_01", (2.5, 2.8, 2.75), 0.0, anchor="top", fit=(None, 0.75, None), name="L2_chandelier")
    # floor lamp (decor)
    C.smooth(lib.lathe("floorlamp_pole", coll, [(0.13, 0), (0.13, 0.02), (0.03, 0.05), (0.012, 0.06), (0.012, 1.42), (0.0, 1.45)], "brass", pos=(4.55, 0, 2.95), segments=16))
    C.smooth(lib.lathe("floorlamp_shade", coll, [(0.22, 1.32), (0.14, 1.6), (0.138, 1.602), (0.218, 1.322)], "lampshade", pos=(4.55, 0, 2.95), segments=32))
    REG.collider(4.5, 0, 2.9, 4.6, 1.6, 3.0, tag="furniture")

    # ================================================================== ESCRITÓRIO
    C.rug(coll, "rug_esc", 1.0, 7.0, 3.8, 9.0, 0, "rug_blue")
    ph(coll, "metal_office_desk", (2.4, 0, 9.5), PI, fit=(1.8, None, 0.85), col="top", name="desk")
    REG.collider(1.55, 0, 9.1, 1.95, 0.7, 9.92, tag="furniture")
    REG.collider(2.85, 0, 9.1, 3.25, 0.7, 9.92, tag="furniture")
    ph(coll, "dining_chair_02", (2.45, 0, 8.72), 0.0, fit=(None, 0.95, None), col=("seat", 0.47, 0.95, 0.25, "-z"), name="desk_chair")
    ph(coll, "classic_laptop", (2.4, 0.71, 9.55), PI, fit=(0.36, None, None), name="LAPTOP")
    ph(coll, "desk_lamp_arm_01", (3.05, 0.71, 9.7), PI + 0.5, fit=(None, 0.55, None), name="desk_lamp")
    ph(coll, "wooden_bookshelf_worn", (0.3, 0, 6.3), HALF, fit=(1.2, 2.0, 0.42), col="box", name="shelf_esc")
    ph(coll, "drawer_cabinet", (4.35, 0, 5.82), 0.0, fit=(1.0, None, 0.5), col="box", name="filing")
    ph(coll, "painted_wooden_nightstand", (0.32, 0, 7.75), HALF, fit=(None, 0.6, None), col="box", name="side_esc")
    boxes(coll, 4.2, 7.3, 0, [(0.6, 0.45, 0.55), (0.5, 0.4, 0.45), (0.38, 0.3, 0.36)], 3, "box_esc")
    painting(coll, "hanging_picture_frame_02", "z", 4.94, -1, 7.4, 1.6, 0.7, "paint_esc")

    # ================================================================== HALL
    ph(coll, "ClassicNightstand_01", (7.2, 0, 0.85), -HALF, fit=(None, 0.8, None), col="box", name="shoe_cabinet")
    C.coat_rack(coll, 5.35, 0, 0.45)
    ph(coll, "side_table_01", (7.2, 0, 2.95), -HALF, fit=(None, 0.7, 0.42), col="box", name="phone_table")
    C.rotary_phone(coll, 7.24, 0.7, 2.82, -HALF)
    C.rug(coll, "rug_hall", 5.55, 0.4, 6.95, 3.3, 0, "rug_runner")
    ph(coll, "painted_wooden_bench", (6.6, 0, 9.72), PI, fit=(0.95, None, 0.42), col=("seat", 0.45, 0.85, 0.35, "+z"), name="bench")
    ph(coll, "ornate_mirror_01", (7.43, 1.05, 0.85), -HALF, fit=(None, 0.85, None), anchor="back", name="mirror_hall")
    painting(coll, "hanging_picture_frame_02", "z", 5.07, 1, 6.6, 1.65, 0.6, "paint_hall_w")
    painting(coll, "fancy_picture_frame_01", "z", 7.43, -1, 8.2, 1.65, 0.6, "paint_hall_e")

    # ================================================================== COZINHA
    C.counter(coll, "counter_n", 7.56, 9.35, 9.5, 9.94, 0.0, 0.9, front="-z", sink=(8.8, 9.6, 0.62, 0.42))
    C.faucet(coll, "sink_faucet", 8.8, 0.9, 9.86, toward=(0, 0, -1), reach=0.17, height=0.24)
    REG.nodes["faucet_coz"] = {"spout": [8.8, 1.07, 9.69], "handle": [8.72, 0.95, 9.86], "basin": [8.8, 0.72, 9.6, 0.6, 0.4], "floor": [8.8, 0.0, 9.0]}
    ph(coll, "electric_stove", (9.76, 0, 9.62), PI, fit=(0.52, None, None), col="box", name="stove")
    C.counter(coll, "counter_ne", 10.02, 9.35, 10.42, 9.94, 0.0, 0.9, front="-z")
    C.upper_cabinet(coll, "upper_coz", 9.0, 9.6, 10.42, 9.94, 1.5, 2.2, front="-z")
    C.fridge(coll, 7.56, 3.56, 8.26, 4.26, 0.0, 1.75, front="+z")
    ph(coll, "round_wooden_table_01", (9.2, 0, 6.7), 0.0, fit=(None, 0.76, None), col="top", name="kitchen_table")
    ph(coll, "painted_wooden_chair_01", (9.2, 0, 5.82), 0.0, fit=(None, 0.95, None), col=("seat", 0.46, 0.95, 0.22, "-z"), name="chair_coz_a")
    ph(coll, "painted_wooden_chair_01", (9.2, 0, 7.58), PI, fit=(None, 0.95, None), col=("seat", 0.46, 0.95, 0.22, "+z"), name="chair_coz_b")
    ph(coll, "wooden_bowl_01", (9.15, 0.76, 6.65), 0.3, fit=(0.3, None, None), name="fruit_bowl")
    ph(coll, "food_apple_01", (9.1, 0.8, 6.6), 0.0, fit=(0.08, None, None), name="apple_a")
    ph(coll, "food_apple_01", (9.2, 0.8, 6.7), 1.0, fit=(0.08, None, None), name="apple_b")
    ph(coll, "lemon", (9.22, 0.79, 6.58), 0.5, fit=(None, 0.07, None), name="lemon")
    C.counter(coll, "counter_radio", 10.4, 5.4, 10.94, 7.4, 0.0, 0.9, front="-x")
    radio, dial = C.radio_vintage(coll, 10.66, 0.9, 6.4, "-x")
    dial.name = "RADIO_DIAL"
    C.counter(coll, "counter_e", 11.4, 3.56, 11.94, 5.1, 0.0, 0.9, front="-x")
    ph(coll, "vintage_electric_kettle", (11.65, 0.9, 3.95), -HALF + 0.3, fit=(None, 0.24, None), name="kettle")
    ph(coll, "tea_set_01", (10.7, 0.9, 7.05), -HALF, parts=["tea_set_01_teapot_01"], scale=1.0, name="teapot")
    ph(coll, "wooden_cutting_board", (9.3, 0.9, 9.62), 0.1, fit=(0.4, None, None), name="board")
    ph(coll, "wine_bottles_01", (10.25, 0.9, 9.66), 0.0, parts=["wine_bottles_01_bordeaux"], name="wine_a")
    ph(coll, "jug_01", (7.75, 0.9, 9.62), 0.6, fit=(0.2, None, None), name="jug")
    food_bowl = C.bowls(coll, 8.6, 0.0, 3.9)
    food_bowl[1].name = "BOWL_FOOD"

    # ================================================================== SALA DE JANTAR (back wing)
    C.rug(coll, "rug_jan", 2.7, 10.85, 5.1, 12.65, 0, "rug_red")
    ph(coll, "WoodenTable_03", (3.9, 0, 11.75), 0.0, fit=(1.6, 0.76, 0.8), col="top", name="dining_table")
    for i, (x, z, yaw) in enumerate(((3.5, 10.95, 0.0), (4.3, 10.95, 0.0), (3.5, 12.55, PI), (4.3, 12.55, PI))):
        side = "-z" if yaw == 0.0 else "+z"
        ph(coll, "dining_chair_02", (x, 0, z), yaw, fit=(None, 0.95, None), col=("seat", 0.47, 0.95, 0.25, side), name=f"chair_jan_{i}")
    C.counter(coll, "sideboard_jan", 0.1, 10.9, 0.55, 12.5, 0.0, 0.85, front="+x", body="wood_dark", top="wood_dark")
    ph(coll, "tea_set_01", (0.32, 0.85, 11.3), HALF, parts=["tea_set_01_teapot_01"], scale=1.0, name="teapot_jan")
    ph(coll, "standing_picture_frame_02", (0.3, 0.85, 12.1), HALF - 0.3, fit=(None, 0.24, None), name="frame_jan")
    ph(coll, "potted_plant_02", (2.55, 0, 12.6), 0.7, fit=(None, 1.1, None), col=None, name="plant_jan")
    painting(coll, "fancy_picture_frame_01", "x", 10.07, 1, 3.9, 1.7, 0.7, "paint_jan")

    # ================================================================== DESPENSA (back wing)
    ph(coll, "steel_frame_shelves_01", (11.68, 0, 11.4), -HALF, fit=(1.6, 1.9, 0.5), col="box", name="shelf_desp_e")
    ph(coll, "steel_frame_shelves_01", (8.55, 0, 12.66), PI, fit=(1.2, 1.9, 0.45), col="box", name="shelf_desp_b")
    ph(coll, "wooden_crate_01", (10.0, 0, 10.45), 0.2, fit=(0.6, None, None), col="box", name="crate_desp")
    boxes(coll, 11.45, 12.6, 0, [(0.5, 0.4, 0.45), (0.42, 0.3, 0.4)], 41, "box_desp")
    ph(coll, "jug_01", (11.6, 0.885, 11.0), 0.3, fit=(0.2, None, None), name="jug_desp")
    ph(coll, "wine_bottles_01", (8.4, 0.885, 12.66), 0.0, parts=["wine_bottles_01_bordeaux"], name="wine_desp")
    # the cat flap: a small swinging panel low in the back door of the pantry wall
    C.rbox("CAT_FLAP_frame", coll, 10.78, 0.18, 12.9, 0.4, 0.36, 0.03, "exterior_trim", 0.004, 1)
    flap = C.rbox("CAT_FLAP", coll, 10.78, 0.17, 12.88, 0.32, 0.3, 0.012, "plastic_beige", 0.003, 1)
    # and its outer face, seen from the yard (the wall's outside face is z 13.1)
    C.rbox("CAT_FLAP_frame_out", coll, 10.78, 0.18, 13.1, 0.4, 0.36, 0.03, "exterior_trim", 0.004, 1)
    C.rbox("CAT_FLAP_out", coll, 10.78, 0.17, 13.121, 0.32, 0.3, 0.012, "plastic_beige", 0.003, 1)
    REG.nodes["cat_flap"] = [10.78, 0.32, 12.88]

    # ================================================================== BANHEIRO DE BAIXO
    sink_b, spout_b = C.pedestal_sink(coll, "sink_banb", 9.3, 0.32, 0.0, "+z")
    REG.nodes["faucet_banb"] = {"spout": list(spout_b), "handle": [9.3, 0.9, 0.2], "basin": [9.3, 0.78, 0.36, 0.42, 0.28], "floor": [9.3, 0.0, 0.9]}
    C.mirror(coll, "mirror_banb", "x", 0.1, 1, 9.0, 9.6, 1.2, 1.85)
    C.toilet(coll, "toilet_b", 10.62, 0.42, 0.0, "+z")
    C.shower(coll, 11.0, 2.5, 11.94, 3.44, 0.0)
    C.rbox_min("cab_banb", coll, 7.56, 0.0, 2.55, 8.0, 0.9, 3.35, "wood_paint", 0.01, 2)
    REG.collider(7.56, 0.0, 2.55, 8.0, 0.9, 3.35, tag="furniture")
    C.soft_box("towel_banb", coll, 8.4, 1.62, 3.42, 0.4, 0.55, 0.03, "towel")
    ph(coll, "plunger", (11.05, 0, 0.35), 0.0, fit=(None, 0.42, None), name="plunger")
    ph(coll, "rubber_duck_toy", (7.8, 0.9, 3.1), 0.8, fit=(None, 0.09, None), name="duck")

    # ================================================================== PORÃO
    # the third shelf used to stand in front of the cellar window (z 5..6.2): the cat could not reach it
    for i, zc in enumerate((3.55, 4.53)):
        ph(coll, "steel_frame_shelves_01", (0.3, b, zc), HALF, fit=(None, 1.85, 0.44), col="box", name=f"shelf_porao_{i}")
    r = lib.rng(41)
    jars = ["can_rusted", "oil_tin", "bleach_bottle", "multi_cleaner_bottle"]
    for lvl in (0.42, 0.86, 1.3):
        z = 3.1
        while z < 4.95:
            mid = r.choice(jars)
            ph(coll, mid, (0.28 + r.uniform(-0.05, 0.05), b + lvl, z), r.uniform(0, 6), fit=(None, r.uniform(0.12, 0.22), None), name=f"jar_{mid}_{int(z*100)}_{int(lvl*10)}")
            z += r.uniform(0.18, 0.35)
    boxes(coll, 5.9, 0.6, b, [(0.7, 0.5, 0.6), (0.55, 0.4, 0.5)], 5, "box_porao_a")
    open_box(coll, 6.75, 0.55, b)
    boxes(coll, 2.8, 9.3, b, [(0.6, 0.45, 0.55), (0.6, 0.45, 0.55), (0.45, 0.35, 0.4)], 6, "box_porao_b")
    boxes(coll, 1.6, 9.4, b, [(0.5, 0.4, 0.45)], 7, "box_porao_c")
    C.boiler(coll, 0.55, 9.35, b)
    ph(coll, "WoodenTable_03", (7.62, b, 3.7), -HALF, fit=(1.3, None, None), col="box", name="workbench")
    ph(coll, "hatchet", (7.6, b + 0.885, 3.4), 0.3, tilt=(HALF, 0.0), fit=(None, 0.42, None), name="hatchet")
    ph(coll, "handsaw_wood", (7.65, b + 0.83, 4.05), 0.1, tilt=(0.0, HALF), fit=(None, None, 0.6), name="saw")
    ph(coll, "Barrel_01", (0.55, b, 7.4), 0.4, fit=(None, 0.85, None), col="box", name="barrel")
    ph(coll, "wooden_crate_01", (6.2, b, 9.5), 0.1, fit=(0.8, None, None), col="box", name="crate_a")
    ph(coll, "wooden_crate_01", (6.25, b + 0.32, 9.48), -0.15, fit=(0.7, None, None), col="box", name="crate_b")
    ph(coll, "mousetrap", (4.2, b, 0.4), 0.7, fit=(None, None, 0.1), name="mousetrap")
    for z in (2.0, 8.0):
        C.pipe_run(coll, f"pipe_porao_{z}", [(0.1, -0.45, z), (7.9, -0.45, z)], 0.045, "iron")
    C.pipe_run(coll, "pipe_boiler", [(0.55, b + 1.9, 9.0), (0.55, -0.45, 8.6), (0.55, -0.45, 8.0)], 0.04, "iron")
    # (the three dust-sheet blocks that stood here were removed: they read as blank white boxes)
    # basement bulb (light 0) hangs from a pull-chain socket
    ph(coll, "pull_chain_light_socket", (3.8, -0.2, 5.2), 0.0, anchor="top", fit=(None, 0.16, None), name="L0_socket")
    ph(coll, "lightbulb_01", (3.8, -0.36, 5.2), PI, anchor="top", fit=(None, 0.11, None), name="L0_bulb")

    # ================================================================== LAVANDERIA
    C.washer(coll, "washer_a", 8.47, 0.4, b, "+z")
    C.washer(coll, "washer_b", 9.15, 0.4, b, "+z")
    ph(coll, "bleach_bottle", (8.4, b + 0.86, 0.35), 0.4, fit=(None, 0.26, None), name="bleach_top")
    ph(coll, "multi_cleaner_bottle", (9.25, b + 0.86, 0.4), 1.4, fit=(None, 0.22, None), name="cleaner_top")
    C.tanque(coll, 9.8, 0.08, 10.5, 0.68, b)
    REG.nodes["faucet_tanque"] = {"spout": [10.15, b + 1.1, 0.2]}
    ph(coll, "steel_frame_shelves_01", (11.7, b, 2.25), -HALF, fit=(2.4, 1.6, 0.44), col="box", name="shelf_lav")
    # the kit shelf scales to 0.82 m wide here: tops at 0.36 / 0.74 / 1.12
    for i, (mid, y, z) in enumerate((("plastic_bottle_gallon", 0.365, 1.98), ("plastic_bottle_gallon", 0.365, 2.2), ("bleach_bottle", 0.365, 2.48), ("can_rusted", 0.745, 2.05), ("oil_tin", 0.745, 2.42))):
        ph(coll, mid, (11.7, b + y, z), 0.4 * i, fit=(None, 0.22, None), name=f"lav_item_{i}")
    boxes(coll, 11.7, 2.25, b + 1.125, [(0.4, 0.3, 0.38)], 11, "box_lav")
    ph(coll, "wicker_basket_01", (8.55, b, 2.45), 0.2, fit=(0.55, None, None), col="box", name="laundry_basket")
    C.ironing_board(coll, 9.9, 4.45, b)
    clothesline(coll, b)

    # ================================================================== QUARTO (Clara)
    C.rug(coll, "rug_quarto", 1.6, 1.0, 4.2, 4.6, q, "rug_red")
    ph(coll, "GothicBed_01", (1.13, q, 2.8), HALF, fit=(1.62, None, 2.14), name="bed_clara")
    REG.nodes["bed_clara"] = {"rect": [0.06, 2.0, 2.2, 3.6]}
    ph(coll, "ClassicNightstand_01", (0.3, q, 1.66), HALF, fit=(None, 0.62, 0.44), col="box", name="nightstand_l")
    ph(coll, "ClassicNightstand_01", (0.3, q, 3.92), HALF, fit=(None, 0.62, 0.44), col="box", name="nightstand_r")
    lamp, shade, bulb = C.table_lamp(coll, "L8_lamp", 0.3, q + 0.62, 1.68)
    shade.name = "L8_shade"
    bulb.name = "L8_bulb"
    ph(coll, "alarm_clock_01", (0.32, q + 0.62, 3.78), HALF, fit=(None, 0.15, None), name="alarm_clock")
    ph(coll, "painted_wooden_cabinet_02", (4.3, q, 5.1), PI, fit=(None, 2.2, 0.62), col="box", name="wardrobe")
    ph(coll, "GothicCommode_01", (2.8, q, 5.15), PI, fit=(1.2, 1.0, 0.56), col="box", name="dresser")
    ph(coll, "ornate_mirror_01", (2.8, q + 1.15, 5.43), PI, fit=(None, 0.8, None), anchor="back", name="mirror_quarto")
    ph(coll, "standing_picture_frame_01", (2.4, q + 1.0, 5.2), PI - 0.3, fit=(None, 0.22, None), name="frame_quarto")
    boxes(coll, 4.5, 0.5, q, [(0.55, 0.4, 0.5), (0.42, 0.34, 0.4)], 21, "box_quarto")
    painting(coll, "fancy_picture_frame_02", "z", 4.94, -1, 3.2, 4.6, 0.5, "paint_quarto")

    # ================================================================== HÓSPEDES
    ph(coll, "old_bed_frame", (1.08, q, 8.33), HALF, fit=(1.0, None, 2.04), name="bed_guest")
    C.soft_box("guest_mattress", coll, 1.08, q + 0.47, 8.33, 1.9, 0.16, 0.9, "sheet", 2)
    REG.collider(0.1, q, 7.85, 2.06, q + 0.55, 8.8, tag="bed")
    C.soft_box("guest_pillow", coll, 0.4, q + 0.6, 8.33, 0.32, 0.12, 0.6, "sheet", 2)
    ph(coll, "painted_wooden_nightstand", (0.3, q, 9.2), HALF, fit=(None, 0.62, None), col="box", name="nightstand_guest")
    lamp2, shade2, bulb2 = C.table_lamp(coll, "L17_lamp", 0.3, q + 0.62, 9.2)
    shade2.name = "L17_shade"
    bulb2.name = "L17_bulb"
    boxes(coll, 2.6, 6.2, q, [(0.6, 0.45, 0.55), (0.55, 0.4, 0.5), (0.4, 0.32, 0.38)], 31, "box_hosp_a")
    # the old dresser where Davi stands the doll, and Ivone's little wooden chest he opens (its lid
    # swings in the game: IVONE_BOX / treasure_chest_lid_1)
    ph(coll, "GothicCommode_01", (3.45, q, 5.8), 0.0, fit=(1.1, None, None), col="box", name="DRESSER_hosp")
    ph(coll, "treasure_chest", (4.4, q, 7.2), -0.63, fit=(0.7, None, None), col="box", name="IVONE_BOX")
    boxes(coll, 3.2, 9.4, q, [(0.7, 0.5, 0.6), (0.6, 0.45, 0.5)], 34, "box_hosp_d")
    covered(coll, "covered_hosp_mirror", "ornate_mirror_01", (4.62, q, 6.0), -HALF, 0.55, upright=1.75)
    # by the side window, out of the way from the door to the boxes (people walked through it in the middle)
    ph(coll, "Rockingchair_01", (0.65, q, 6.95), -HALF + 0.3, fit=(None, 1.0, None), col=("seat", 0.45, 1.0, 0.3, "+x"), name="ROCKING_CHAIR")

    # ================================================================== CORREDOR
    ph(coll, "ClassicConsole_01", (7.24, q, 7.0), -HALF, fit=(1.0, None, 0.4), col="box", name="console_cor")
    C.rug(coll, "rug_cor", 6.2, 4.6, 7.2, 9.6, q, "rug_runner")
    painting(coll, "hanging_picture_frame_02", "z", 7.43, -1, 5.0, 4.65, 0.55, "paint_cor_a")
    painting(coll, "fancy_picture_frame_01", "x", 9.94, -1, 6.2, 4.6, 0.55, "paint_cor_b")

    # ================================================================== BANHEIRO DE CIMA
    C.bathtub(coll, 9.9, 9.16, 11.94, 9.94, q)
    sink_c, spout_c = C.pedestal_sink(coll, "sink_banc", 8.2, 6.32, q, "+z")
    REG.nodes["faucet_banc"] = {"spout": list(spout_c)}
    C.mirror(coll, "mirror_banc", "x", 6.06, 1, 7.95, 8.45, q + 1.2, q + 1.85)
    C.toilet(coll, "toilet_c", 11.52, 6.42, q, "+z")
    C.counter(coll, "cab_banc", 9.9, 6.06, 10.9, 6.55, q, 0.9, front="+z", body="wood_paint", top="countertop")
    C.smooth(lib.lathe("hamper", coll, [(0.0, 0.0), (0.2, 0.0), (0.22, 0.5), (0.0, 0.5)], "hessian", pos=(8.22, q, 9.62), segments=20, cap=True))
    REG.collider(8.0, q, 9.4, 8.45, q + 0.5, 9.85, tag="furniture")
    C.soft_box("towel_banc", coll, 11.2, q + 1.6, 9.92, 0.4, 0.6, 0.03, "towel_blue")

    # ================================================================== VARANDA
    ph(coll, "potted_plant_02", (11.55, q, 0.5), 0.0, fit=(None, 0.85, None), name="plant_var_a")
    ph(coll, "potted_plant_02", (8.0, q, 0.5), 1.4, fit=(None, 0.7, None), name="plant_var_b")
    ph(coll, "planter_box_01", (11.55, q, 5.4), HALF, fit=(0.9, None, None), col="box", name="planter_var")
    ph(coll, "outdoor_table_chair_set_01", (10.25, q, 2.6), 0.2, fit=(None, 0.86, None), name="outdoor_set")
    REG.collider(9.9, q, 2.25, 10.6, q + 0.73, 2.95, tag="furniture")

    # ================================================================== SÓTÃO
    # side walls 0.9 m high, then the slope: an item must stay under the rafters (knee + 0.64 x distance to the wall - 0.14)
    # and keep 0.3 m or more from its neighbours and from the walking line stair -> middle -> chest
    knee = L["ATTIC"]["knee"]
    attic_rafters(coll, knee)
    boxes(coll, 2.0, 2.2, a, [(0.6, 0.45, 0.5), (0.5, 0.35, 0.45)], 51, "box_sotao_a")   # the chest key sits on top (house.gd)
    boxes(coll, 5.0, 8.7, a, [(0.6, 0.45, 0.55)], 52, "box_sotao_b")
    boxes(coll, 1.0, 5.6, a, [(0.5, 0.4, 0.5)], 53, "box_sotao_c")
    C.mannequin(coll, 4.6, a, 2.9)
    C.rocking_horse(coll, 3.3, a, 2.0, 0.4)
    _, _, (_cmn, chest_mx) = ph(coll, "treasure_chest", (3.1, a, 9.0), PI, fit=(1.0, None, 0.62), col="box", name="CHEST")
    REG.nodes["chest"] = [3.1, a, 9.0]
    ph(coll, "wheelchair_01", (6.3, a, 7.4), -HALF - 0.4, fit=(None, 0.9, None), col="box", name="wheelchair")
    ph(coll, "spinning_wheel_01", (1.3, a, 8.2), 0.6, fit=(None, 0.95, None), col="box", name="spinning_wheel")
    ph(coll, "marble_bust_01", (5.0, a + 0.45, 8.7), PI + 0.4, fit=(None, 0.42, None), name="bust")
    ph(coll, "vintage_suitcase", (1.6, a, 1.0), 0.3, parts=["vintage_suitcase_02"], name="suitcase_attic")
    ph(coll, "Lantern_01", (3.35, chest_mx[1] - 0.01, 9.0), 0.0, fit=(None, 0.25, None), name="lantern")
    # the bare bulb hangs on a cord from the ridge beam
    ridge_bottom = 8.14 + knee
    lib.tube("L12_cord", coll, [(3.75, ridge_bottom, 5.0), (3.75, 8.45, 5.0)], 0.006, "fabric_cream", segments=6)
    ph(coll, "pull_chain_light_socket", (3.75, 8.45, 5.0), 0.0, anchor="top", fit=(None, 0.16, None), name="L12_socket")
    ph(coll, "lightbulb_01", (3.75, 8.29, 5.0), PI, anchor="top", fit=(None, 0.11, None), name="L12_bulb")

    # ================================================================== light fixtures, switches, outlets
    fixtures(L, coll)
    dynamic_objects(L, coll)
    davi_move_in(coll)


# ---------------------------------------------------------------------- helpers per room


def open_box(coll, cx, cz, y):
    """the open moving box in the basement where the old photograph waits."""
    w, h, d = 0.55, 0.38, 0.5
    g = lib.Geo("open_box")
    t = 0.008
    g.box(cx - w / 2, y, cz - d / 2, cx + w / 2, y + t, cz + d / 2, "cardboard")
    for (x0, z0, x1, z1) in ((cx - w / 2, cz - d / 2, cx + w / 2, cz - d / 2 + t), (cx - w / 2, cz + d / 2 - t, cx + w / 2, cz + d / 2), (cx - w / 2, cz - d / 2, cx - w / 2 + t, cz + d / 2), (cx + w / 2 - t, cz - d / 2, cx + w / 2, cz + d / 2)):
        g.box(x0, y, z0, x1, y + h, z1, "cardboard")
    ob = g.build(coll)
    for k, (dx, ang) in enumerate(((-1, -1.9), (1, 1.9))):
        flap = C.rbox(f"open_box_flap{k}", coll, cx + dx * (w / 2 + 0.11), y + h + 0.0, cz, 0.22, 0.008, d, "cardboard", 0.0, 1)
        C.rotate_about_y(flap, 0.0, (cx, y, cz))
        flap.rotation_euler[1] = dx * 0.35
    REG.collider(cx - w / 2, y, cz - d / 2, cx + w / 2, y + h, cz + d / 2, tag="furniture")
    return ob


def clothesline(coll, b):
    lib.tube("clothesline", coll, [(8.3, b + 1.82, 3.0), (11.1, b + 1.8, 3.0)], 0.004, "fabric_cream", segments=6)
    for x in (8.3, 11.1):
        C.cyl("line_post", coll, x, b, 3.0, 0.02, 0.02, 1.85, "iron", 8)
    for i in range(3):
        cx = 8.85 + i * 0.85
        # a hanging sheet: plane in the xy plane, slightly wavy (Godot sways it)
        g = lib.Geo(f"SHEET_{i}")
        nu, nv = 10, 14
        pts = {}
        for j in range(nv + 1):
            for k in range(nu + 1):
                u, v = k / nu, j / nv
                x = cx - 0.36 + u * 0.72
                y = b + 1.8 - v * 1.15
                z = 3.0 + 0.04 * math.sin(u * 7 + i) * v + 0.02 * math.sin(v * 5)
                pts[(j, k)] = (x, y, z)
        for j in range(nv):
            for k in range(nu):
                g.poly([pts[(j, k)], pts[(j, k + 1)], pts[(j + 1, k + 1)], pts[(j + 1, k)]], "sheet", uvs=[(k / nu, -j / nv), ((k + 1) / nu, -j / nv), ((k + 1) / nu, -(j + 1) / nv), (k / nu, -(j + 1) / nv)])
        ob = g.build(coll, smooth_all=True)
        lib.add_mod(ob, "SOLIDIFY", thickness=0.004)
        lib.apply_mods(ob)
        C.smooth(ob)


def covered(coll, name, proxy_mid, pos, yaw, size, upright=None):
    """a dust sheet over a piece of furniture: a soft block the size of the (hidden) piece with a hem that
    rests on the floor, so it never hangs in the air. Only the sheet is exported."""
    tmp = lib.collection("_tmp_cloth")
    if upright:
        root, sz, (mn, mx) = ph(tmp, proxy_mid, pos, yaw, fit=(None, upright, None), record=False)
    else:
        root, sz, (mn, mx) = ph(tmp, proxy_mid, pos, yaw, fit=(size, None, None), record=False)
    for o in list(tmp.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    fy = pos[1]
    cx, cz = (mn[0] + mx[0]) / 2, (mn[2] + mx[2]) / 2
    w = max(mx[0] - mn[0], 0.3) + 0.1
    d = max(mx[2] - mn[2], 0.3) + 0.1
    top = mx[1] + 0.05 - fy
    body = C.rbox(name + "_body", coll, cx, fy + top / 2 + 0.06, cz, w, top - 0.12, d, "dust_sheet", 0.08, 3)
    hem = C.rbox(name + "_hem", coll, cx, fy + 0.11, cz, w + 0.16, 0.22, d + 0.16, "dust_sheet", 0.09, 3)
    sheet = lib.join([body, hem], name)
    REG.collider(cx - (w + 0.16) / 2, fy, cz - (d + 0.16) / 2, cx + (w + 0.16) / 2, mx[1] + 0.05, cz + (d + 0.16) / 2, tag="furniture")
    return sheet


def attic_stair(coll, L):
    """the attic stair, one straight flight like the ones downstairs: from the corridor (foot at z_foot, just north of
    the main stair's railing) up toward the front wall to a last tread flush with the attic floor, against the
    varanda wall (east). 16 risers of 0.1875 m. Hidden by the game until the hatch is open (node LADDER)."""
    A = L["ATTIC"]
    x0, x1, zf, zt, n = A["x0"], A["x1"], A["z_foot"], A["z_top"], A["steps"]
    rise = 3.0 / n
    run = (zf - zt) / n
    key, key2 = "stair_wood", "wood_worn"
    g = lib.Geo("LADDER")
    st = 0.04   # stringer thickness
    for k in range(n):
        top = 3.0 + (k + 1) * rise
        z1 = zf - k * run
        # open stair: a tread with a nosing toward the foot and a thin riser board, between the two stringers
        g.box(x0 + st, top - 0.035, z1 - run, x1 - st, top, z1 + 0.025, key)
        g.box(x0 + st, top - rise, z1 - 0.02, x1 - st, top - 0.035, z1, key)
    # two stringers (west side and against the wall): boards along the flight, cut level at the corridor floor
    # and at the attic floor
    up0 = rise + 0.08
    dn = 0.32

    def z_at(h):   # where the upper edge of the stringer (h above the tread nose line) reaches y
        return lambda y: zf - (y - 3.0 - h) * run / rise
    zc = z_at(up0)(6.0)
    zb = z_at(up0 - dn)(3.0)
    for xs in (x0, x1 - st):
        pts = [(xs, 3.0, zf), (xs, 3.0 + up0, zf), (xs, 6.0, zc), (xs, 6.0, zt),
               (xs, 3.0 + up0 - dn + (zf - zt) / run * rise, zt), (xs, 3.0, zb)]
        g.prism(pts, (st, 0, 0), key2)
    ob = g.build(coll)
    parts = [ob]
    xr = x0 + 0.03
    z_open = zt + 0.65   # the last stretch has no rail: the cat steps off sideways into the attic

    def nose(z):
        return 3.0 + (zf - z) / run * rise

    pts = [(xr, nose(zf - run * 0.5) + 0.9, zf - run * 0.5), (xr, nose(z_open) + 0.9, z_open)]
    parts.append(lib.tube("stair_rail", coll, pts, 0.025, key2, segments=8))
    for k in range(n):
        zc = zf - k * run - run * 0.5
        if zc < z_open:
            break
        parts.append(lib.tube(f"stair_bal{k}", coll, [(xr, 3.0 + (k + 1) * rise, zc), (xr, nose(zc) + 0.9, zc)], 0.012, key2, segments=5))
    parts.append(lib.tube("stair_newel", coll, [(xr, 3.0, zf - 0.04), (xr, nose(zf) + 1.05, zf - 0.04)], 0.035, key2, segments=8))
    # attic side: a railing along the west edge of the hole (from the open stretch on) and across its south end
    h1 = L["HATCH"]
    ya = 6.0
    for (px, pz) in ((xr, z_open), (xr, h1["z1"] - 0.03), (x1 - 0.03, h1["z1"] - 0.03)):
        parts.append(lib.tube(f"stair_post_{px:.2f}_{pz:.2f}", coll, [(px, nose(pz) if pz < z_open + 0.01 else ya, pz), (px, ya + 0.95, pz)], 0.03, key2, segments=8))
    parts.append(lib.tube("stair_rail_attic", coll, [(xr, ya + 0.9, z_open), (xr, ya + 0.9, h1["z1"] - 0.03), (x1 - 0.03, ya + 0.9, h1["z1"] - 0.03)], 0.022, key2, segments=8))
    z = z_open + 0.25
    while z < h1["z1"] - 0.1:
        parts.append(lib.tube(f"stair_bal_a{z:.2f}", coll, [(xr, ya, z), (xr, ya + 0.9, z)], 0.012, key2, segments=5))
        z += 0.25
    x = xr + 0.25
    while x < x1 - 0.1:
        parts.append(lib.tube(f"stair_bal_s{x:.2f}", coll, [(x, ya, h1["z1"] - 0.03), (x, ya + 0.9, h1["z1"] - 0.03)], 0.012, key2, segments=5))
        x += 0.25
    lib.join(parts, "LADDER")


def floor_proxy(coll, y):
    return C.rbox(f"_floor_{y:.2f}", coll, 6.0, y - 0.05, 5.0, 14.0, 0.1, 12.0, "black", 0.0, 1, uv=False)


def attic_rafters(coll, knee):
    ang = math.atan2(2.4, 3.75)
    for i in range(18):
        z = 0.3 + i * 0.56
        for side in (-1, 1):
            x0, x1 = (0.05, 3.7) if side < 0 else (3.8, 7.45)
            y_at = (lambda x: 6 + knee + x * math.tan(ang)) if side < 0 else (lambda x: 6 + knee + (7.5 - x) * math.tan(ang))
            pts = [(x0, y_at(x0) - 0.08, z), (x1, y_at(x1) - 0.08, z)]
            r = lib.rounded_box(f"rafter_{i}_{side}", coll, ((x0 + x1) / 2, (y_at(x0) + y_at(x1)) / 2 - 0.08, z), (math.hypot(x1 - x0, y_at(x1) - y_at(x0)), 0.12, 0.06), "wood_worn", bevel=0.008, segments=1)
            r.rotation_euler = (0, -(ang if side < 0 else -ang), 0)
            bpy.context.view_layer.update()
            lib.world_uv_object(r)
        if i % 3 == 1:
            C.rbox(f"collar_{i}", coll, 3.75, 7.6 + knee, z, 2.6, 0.1, 0.06, "wood_worn", 0.008, 1)
    C.rbox("ridge_beam", coll, 3.75, 8.22 + knee, 5.0, 0.08, 0.16, 10.0, "wood_worn", 0.008, 1)


def fixtures(L, coll):
    """ceiling fixtures for every room light (named L<index>_*), switches and their levers."""
    for d in L["LIGHTS"]:
        idx = d["index"]
        x, y, z = d["pos"]
        fx = d["fixture"]
        room = d["room"]
        ceiling = None
        if room not in ("exterior", "dynamic"):
            r = L["ROOM_BY_ID"][room]
            ceiling = r["y"] + r["h"]
        if fx == "pendant":
            objs, shade, bulb = C.pendant(coll, f"L{idx}_pendant", x, y, z, ceiling)
            shade.name = f"L{idx}_shade"
            bulb.name = f"L{idx}_bulb"
        elif fx == "flush":
            objs, dome = C.flush_light(coll, f"L{idx}_flush", x, ceiling, z)
            dome.name = f"L{idx}_bulb"
        if d.get("sw"):
            p, n = d["sw"]["p"], d["sw"]["n"]
            plate, lever = C.switch_plate(coll, f"SW{idx}", p, n)
            plate.name = f"SW{idx}_plate"
            lever.name = f"SW{idx}_lever"
            REG.nodes[f"switch_{idx}"] = {"p": p, "n": n}


def dynamic_objects(L, coll):
    # ---- doors: leaf objects with their origin on the hinge
    for d in L["DOORS"]:
        width = d["s1"] - d["s0"] - 0.03
        h = d["h"] - 0.02
        leaf = C.paneled_door(coll, f"DOOR_{d['id']}", width, h, d["style"])
        # leaf is built along +x from its origin; rotate to the wall axis and move to the hinge
        hinge_s = d["s0"] + 0.015 if d["hinge"] == 0 else d["s1"] - 0.015
        dir_s = 1 if d["hinge"] == 0 else -1
        if d["axis"] == "z":
            pos = (d["fixed"], d["y"], hinge_s)
            yaw = -HALF if dir_s > 0 else HALF  # leaf runs along +z or -z
        else:
            pos = (hinge_s, d["y"], d["fixed"])
            yaw = 0.0 if dir_s > 0 else PI
        leaf.location = gv(pos)
        leaf.rotation_euler = (0, 0, yaw)
        REG.nodes[f"door_{d['id']}"] = {"pos": list(pos), "yaw": yaw, "width": width}
    # ---- attic hatch (two leaves that lie open on the attic floor), stair and cord
    H = L["HATCH"]
    hx0, hx1, hz0, hz1 = H["x0"], H["x1"], H["z0"], H["z1"]
    hxm = (hx0 + hx1) / 2
    # one leaf hinged on the west edge (the east edge is against the knee wall); HATCH_E is gone
    for name, xa, xb, hx in (("HATCH_W", hx0, hx1, hx0),):
        leaf = C.rbox_min(name, coll, xa, 5.8, hz0, xb, 5.85, hz1, "wood_paint", 0.006, 2)
        hinge = gv(hx, 5.825, (hz0 + hz1) / 2)  # hinge along the long edge; the leaf lies flat on the attic floor when open
        leaf.data.transform(Matrix.Translation(-(hinge - leaf.location)))
        leaf.location = hinge
    attic_stair(coll, L)
    cx, cz = hxm, hz1 - 0.15
    cord = lib.tube("HATCH_CORD", coll, [(cx, 5.8, cz), (cx, 3.62, cz)], 0.004, "fabric_cream", segments=6)
    knob = C.smooth(lib.lathe("HATCH_CORD_knob", coll, [(0.0, -0.03), (0.018, -0.02), (0.02, 0.0), (0.012, 0.02), (0.0, 0.03)], "wood", pos=(cx, 3.6, cz), segments=10))
    lib.join([cord, knob], "HATCH_CORD")
    # ---- duct ends: a short sleeve out of the wall (black inside) and a grate hinged on its bottom edge that
    # swings out into the room (zf = the wall face; both ends look towards +z)
    for i, (x, y, zf) in enumerate(((10.95, -2.95, 0.1), (10.8, 0.05, 3.56))):
        yc = y + 0.15
        dp = 0.14
        sleeve = [
            C.rbox(f"duct{i}_top", coll, x, yc + 0.145, zf + dp / 2, 0.38, 0.03, dp, "metal_painted", 0.004, 1),
            C.rbox(f"duct{i}_bot", coll, x, yc - 0.145, zf + dp / 2, 0.38, 0.03, dp, "metal_painted", 0.004, 1),
            C.rbox(f"duct{i}_l", coll, x - 0.175, yc, zf + dp / 2, 0.03, 0.3, dp, "metal_painted", 0.004, 1),
            C.rbox(f"duct{i}_r", coll, x + 0.175, yc, zf + dp / 2, 0.03, 0.3, dp, "metal_painted", 0.004, 1),
            C.rbox(f"duct_hole{i}", coll, x, yc, zf + 0.006, 0.32, 0.26, 0.012, "black", 0.0, 1, uv=False),
        ]
        lib.join(sleeve, f"duct_sleeve{i}")
        zg = zf + dp + 0.01
        parts = [
            C.rbox(f"duct{i}_gtop", coll, x, y + 0.29, zg, 0.38, 0.03, 0.025, "metal_painted", 0.004, 1),
            C.rbox(f"duct{i}_gbot", coll, x, y + 0.01, zg, 0.38, 0.03, 0.025, "metal_painted", 0.004, 1),
            C.rbox(f"duct{i}_gl", coll, x - 0.175, y + 0.15, zg, 0.03, 0.3, 0.025, "metal_painted", 0.004, 1),
            C.rbox(f"duct{i}_gr", coll, x + 0.175, y + 0.15, zg, 0.03, 0.3, 0.025, "metal_painted", 0.004, 1),
        ]
        for k in range(5):
            parts.append(C.rbox(f"duct{i}_slat{k}", coll, x, y + 0.05 + k * 0.05, zg, 0.32, 0.016, 0.03, "metal_painted", 0.003, 1))
        g = lib.join(parts, f"DUCT_{i}")
        hp = gv(x, y, zg)
        g.data.transform(Matrix.Translation(-(hp - g.location)))
        g.location = hp
        REG.nodes[f"duct_{i}"] = [x, y, zf]
    # ---- basculante pane (pivot on its top edge)
    pane = lib.join([C.rbox("bas_frame", coll, 10.4, 4.95, 6.0, 0.7, 0.6, 0.03, "trim", 0.004, 1), C.rbox("bas_glass", coll, 10.4, 4.95, 6.0, 0.64, 0.54, 0.035, "glass_dirty", 0.0, 1)], "BASCULANTE")
    hp = gv(10.4, 5.3, 6.0)
    pane.data.transform(Matrix.Translation(-(hp - pane.location)))
    pane.location = hp
    # ---- outlets + device plugs
    for dev, p, n in (("tv", (3.55, 0.3, 5.43), (0, 0, -1)), ("radio", (10.93, 1.1, 6.95), (-1, 0, 0)), ("laptop", (3.5, 0.3, 9.89), (0, 0, -1))):
        o = C.outlet(coll, f"OUTLET_{dev}", p, n)
        REG.nodes[f"outlet_{dev}"] = {"p": list(p), "n": list(n)}
    # ---- cat bed
    C.cat_bed(coll, 4.25, 0.0, 4.6)


def davi_move_in(coll):
    """things that appear in the guest room once Davi moves in (group GUEST_MOVEIN) and the
    dust sheet over the bed before that (GUEST_DUST)."""
    q = 3.0
    ph(coll, "vintage_suitcase", (4.3, q, 8.75), -HALF + 0.2, parts=["vintage_suitcase_01"], group="GUEST_MOVEIN", name="davi_suitcase")
    ph(coll, "standing_picture_frame_02", (0.32, q + 0.62, 9.05), HALF + 0.3, fit=(None, 0.2, None), group="GUEST_MOVEIN", name="davi_photo")
    pack = C.soft_box("GUEST_MOVEIN_backpack", coll, 4.5, q + 0.22, 8.25, 0.32, 0.44, 0.2, "fabric_green", 2)
    mug = C.smooth(lib.lathe("GUEST_MOVEIN_mug", coll, [(0.0, 0.0), (0.04, 0.0), (0.042, 0.09), (0.036, 0.09), (0.034, 0.008), (0.0, 0.008)], "terracotta", pos=(0.3, q + 0.62, 9.36), segments=16))
    for k, (x, z, ya) in enumerate(((2.5, 9.0, 0.1), (2.68, 9.05, 0.5))):
        C.soft_box(f"GUEST_MOVEIN_shoe{k}", coll, x, q + 0.04, z, 0.11, 0.08, 0.27, "plastic_black", 2)
    # dust sheet over the guest bed before Davi
    tmp = lib.collection("_tmp_cloth")
    mat = C.rbox("_bedproxy", tmp, 1.08, q + 0.3, 8.33, 2.0, 0.6, 1.0, "black", 0.02, 2, uv=False)
    pil = C.rbox("_pilproxy", tmp, 0.4, q + 0.64, 8.33, 0.3, 0.12, 0.6, "black", 0.02, 2, uv=False)
    C.cloth_drape(coll, "GUEST_DUST", (2.5, 1.7), (1.1, q + 0.85, 8.33), [mat, pil, floor_proxy(tmp, q)], "dust_sheet", frames=40, res=36)
    for o in list(tmp.objects):
        bpy.data.objects.remove(o, do_unlink=True)
