"""Download the CC0 Poly Haven assets the game uses.

Textures go straight into the Godot project (godot/assets/textures/<id>/), models and HDRIs into
tools/cache/polyhaven/ (models are assembled by the Blender build scripts; HDRIs are copied by them).

usage: python fetch_polyhaven.py [textures|models|hdris|all]
"""
import json
import os
import sys
import time
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TEX_DIR = os.path.join(ROOT, "godot", "assets", "textures")
CACHE = os.path.join(ROOT, "tools", "cache", "polyhaven")
UA = {"User-Agent": "sete-vidas-build/1.0"}

# id -> resolution. Maps fetched: diffuse, opengl normal, packed AO/rough/metal.
TEXTURES = {
    # floors
    "herringbone_parquet": "2k",
    "old_wooden_floor_01": "2k",
    "old_wooden_floor_02": "2k",
    "old_wood_floor": "2k",
    "weathered_brown_planks": "2k",
    "old_planks_02": "2k",
    "checkered_pavement_tiles": "2k",
    "square_tiles": "2k",
    "dirty_tiles": "2k",
    "damaged_concrete_floor": "2k",
    "concrete_floor_worn_001": "2k",
    # walls / ceilings
    "painted_plaster_wall": "2k",
    "white_plaster_rough_01": "1k",
    "decrepit_wallpaper": "2k",
    "worn_plaster_wall": "1k",
    "long_white_tiles": "2k",
    "rounded_square_tiled_wall": "1k",
    "brick_wall_001": "2k",
    "painted_concrete": "2k",
    "roof_planks": "2k",
    "wood_planks_grey": "1k",
    # exterior
    "blue_painted_planks": "2k",
    "stacked_stone_wall": "1k",
    "roof_slates_02": "2k",
    "leafy_grass": "2k",
    "forest_ground_04": "1k",
    "asphalt_02": "1k",
    "concrete_pavement": "1k",
    "bark_brown_02": "1k",
    "distressed_painted_planks": "1k",
    # fabrics
    "velour_velvet": "1k",
    "floral_jacquard": "1k",
    "quatrefoil_jacquard_fabric": "1k",
    "crepe_satin": "1k",
    "rough_linen": "1k",
    "waffle_pique_cotton": "1k",
    "knitted_fleece": "1k",
    "terry_cloth": "1k",
    "cotton_jersey": "1k",
    "hessian_230": "1k",
    "gingham_check": "1k",
    "curly_teddy_natural": "1k",
    "dirty_carpet": "1k",
    # woods / metals / misc
    "wood_cabinet_worn_long": "1k",
    "dark_planks": "1k",
    "white_planks_clean": "1k",
    "black_walnut_veneer_01": "1k",
    "cherry_veneer": "1k",
    "coated_pine": "1k",
    "rusty_metal_02": "1k",
    "green_metal_rust": "1k",
    "painted_metal_shutter": "1k",
    "marble_01": "1k",
    "leather_red_02": "1k",
}

MODELS = [
    # living room
    "sofa_03", "GreenChair_01", "CoffeeTable_01", "Television_01", "Chandelier_01", "wooden_bookshelf_worn",
    "vintage_grandfather_clock_01", "fancy_picture_frame_01", "fancy_picture_frame_02", "hanging_picture_frame_02",
    "book_encyclopedia_set_01", "decorative_book_set_01", "throw_pillows_01", "potted_plant_01", "potted_plant_02",
    "ceramic_vase_01", "ceramic_vase_02", "ceramic_vase_03", "antique_ceramic_vase_01", "standing_picture_frame_01",
    "standing_picture_frame_02", "Ottoman_01", "side_table_01",
    # office
    "metal_office_desk", "classic_laptop", "desk_lamp_arm_01", "dining_chair_02", "drawer_cabinet",
    "painted_wooden_nightstand", "cardboard_box_01",
    # hall
    "ClassicConsole_01", "ornate_mirror_01", "painted_wooden_bench", "painted_wooden_cabinet_02",
    # kitchen
    "electric_stove", "vintage_microwave", "vintage_electric_kettle", "tea_set_01", "round_wooden_table_01",
    "painted_wooden_chair_01", "painted_wooden_chair_02", "pot_enamel_01", "jug_01", "wooden_bowl_01",
    "food_apple_01", "lemon", "wooden_cutting_board", "wine_bottles_01",
    # bedrooms
    "GothicBed_01", "old_bed_frame", "ClassicNightstand_01", "GothicCabinet_01", "GothicCommode_01",
    "Rockingchair_01", "alarm_clock_01", "vintage_suitcase",
    # basement / laundry / attic
    "steel_frame_shelves_01", "Barrel_01", "wooden_crate_01", "old_military_crate", "spinning_wheel_01",
    "WoodenTable_03", "pull_chain_light_socket", "lightbulb_01", "wicker_basket_01", "bleach_bottle",
    "multi_cleaner_bottle", "plastic_bottle_gallon", "can_rusted", "russian_food_cans_01", "oil_tin",
    "wheelchair_01", "treasure_chest", "Lantern_01", "marble_bust_01", "hatchet", "handsaw_wood", "mousetrap",
    "rubber_duck_toy", "plunger",
    # exterior
    "street_lamp_01", "covered_car", "metal_trash_can", "fire_hydrant", "shrub_02", "shrub_04", "garden_gnome",
    "modular_electricity_poles", "outdoor_table_chair_set_01", "planter_box_01", "dead_tree_trunk_02",
]

HDRIS = {
    "qwantani_moon_noon_puresky": "4k",
    "kloppenheim_07_puresky": "2k",
    "kloofendal_48d_partly_cloudy_puresky": "2k",
    "qwantani_sunset_puresky": "2k",
    "qwantani_dawn_puresky": "2k",
}


def get_json(url):
    req = urllib.request.Request(url, headers=UA)
    for i in range(5):
        try:
            return json.load(urllib.request.urlopen(req, timeout=60))
        except Exception as e:  # noqa: BLE001
            print("retry", url, e)
            time.sleep(2 + i * 2)
    raise RuntimeError(url)


def download(url, path, size=None):
    if os.path.exists(path) and (size is None or os.path.getsize(path) == size):
        return False
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".part"
    for i in range(6):
        try:
            req = urllib.request.Request(url, headers=UA)
            with urllib.request.urlopen(req, timeout=120) as r, open(tmp, "wb") as f:
                while True:
                    chunk = r.read(1 << 16)
                    if not chunk:
                        break
                    f.write(chunk)
            os.replace(tmp, path)
            return True
        except Exception as e:  # noqa: BLE001
            print("retry", url, e)
            time.sleep(2 + i * 3)
    raise RuntimeError(url)


def fetch_texture(tid, res):
    files = get_json(f"https://api.polyhaven.com/files/{tid}")
    jobs = []
    for key, suffix in (("Diffuse", "diff"), ("nor_gl", "nor"), ("arm", "arm")):
        if key not in files:
            print("missing map", tid, key)
            continue
        entry = files[key][res]["jpg"]
        jobs.append((entry["url"], os.path.join(TEX_DIR, tid, f"{tid}_{suffix}.jpg"), entry["size"]))
    for url, path, size in jobs:
        download(url, path, size)
    return tid


def fetch_model(mid):
    files = get_json(f"https://api.polyhaven.com/files/{mid}")
    g = files["gltf"]["1k"]["gltf"]
    base = os.path.join(CACHE, "models", mid)
    download(g["url"], os.path.join(base, f"{mid}.gltf"), g["size"])
    for rel, e in g["include"].items():
        download(e["url"], os.path.join(base, rel), e["size"])
    return mid


def fetch_hdri(hid, res):
    files = get_json(f"https://api.polyhaven.com/files/{hid}")
    e = files["hdri"][res]["hdr"]
    download(e["url"], os.path.join(CACHE, "hdris", f"{hid}_{res}.hdr"), e["size"])
    return hid


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    with ThreadPoolExecutor(6) as ex:
        futs = []
        if what in ("textures", "all"):
            futs += [ex.submit(fetch_texture, t, r) for t, r in TEXTURES.items()]
        if what in ("models", "all"):
            futs += [ex.submit(fetch_model, m) for m in MODELS]
        if what in ("hdris", "all"):
            futs += [ex.submit(fetch_hdri, h, r) for h, r in HDRIS.items()]
        for f in futs:
            try:
                print("ok", f.result())
            except Exception as e:  # noqa: BLE001
                print("FAILED", e)


if __name__ == "__main__":
    main()
