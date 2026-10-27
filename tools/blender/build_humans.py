"""People of Sete Vidas built with MPFB (MakeHuman for Blender, CC0 assets):
Clara and Davi (day / night outfits) plus the human-shaped ghosts and Dona Ivone.

usage: blender -b -P tools/blender/build_humans.py -- [--only clara_day,...] [--preview dir]

Each character is exported to godot/assets/models/people/<id>.glb with the MPFB "game_engine"
skeleton, simple PBR materials (diffuse/normal/alpha) and an "eyes_closed" shape key on the body.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402

from bl_ext.blender_org.mpfb.services.humanservice import HumanService  # noqa: E402
from bl_ext.blender_org.mpfb.services.locationservice import LocationService  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None
OUT = os.path.join(lib.GODOT, "assets", "models", "people")

BASE = {
    "eyes": "high-poly/high-poly.mhclo",
    "eyelashes": "eyelashes01/eyelashes01.mhclo",
    "teeth": "teeth_base/teeth_base.mhclo",
    "tongue": "tongue01/tongue01.mhclo",
}

CHARACTERS = {
    "clara_day": dict(
        phenotype={"gender": 0.0, "age": 0.42, "muscle": 0.45, "weight": 0.42, "height": 0.48, "proportions": 0.72, "cupsize": 0.45, "firmness": 0.55},
        race={"african": 0.12, "asian": 0.05, "caucasian": 0.83},
        skin="young_caucasian_female/young_caucasian_female.mhmat",
        eyebrows="eyebrow006/eyebrow006.mhclo",
        hair="ponytail01/ponytail01.mhclo",
        hair_mat="dariush086_ponytail01_brown",
        clothes=["female_elegantsuit01/female_elegantsuit01.mhclo", "shoes01/shoes01.mhclo"],
        eye_mat="brown",
    ),
    "clara_night": dict(
        phenotype={"gender": 0.0, "age": 0.42, "muscle": 0.45, "weight": 0.42, "height": 0.48, "proportions": 0.72, "cupsize": 0.45, "firmness": 0.55},
        race={"african": 0.12, "asian": 0.05, "caucasian": 0.83},
        skin="young_caucasian_female/young_caucasian_female.mhmat",
        eyebrows="eyebrow006/eyebrow006.mhclo",
        hair="braid01/braid01.mhclo",
        hair_mat="toigo_braid01_black",
        clothes=["female_casualsuit01/female_casualsuit01.mhclo"],
        eye_mat="brown",
        cloth_fx={"female_casualsuit01": "pajama"},
    ),
    "davi_day": dict(
        phenotype={"gender": 1.0, "age": 0.56, "muscle": 0.6, "weight": 0.55, "height": 0.62, "proportions": 0.62},
        race={"african": 0.35, "asian": 0.05, "caucasian": 0.6},
        skin="young_caucasian_male/young_caucasian_male.mhmat",
        eyebrows="eyebrow001/eyebrow001.mhclo",
        hair="short02/short02.mhclo",
        hair_mat="bogdan666_short_02_brown",
        clothes=["male_casualsuit05/male_casualsuit05.mhclo", "shoes06/shoes06.mhclo"],
        eye_mat="brownlight",
    ),
    "davi_night": dict(
        phenotype={"gender": 1.0, "age": 0.56, "muscle": 0.6, "weight": 0.55, "height": 0.62, "proportions": 0.62},
        race={"african": 0.35, "asian": 0.05, "caucasian": 0.6},
        skin="young_caucasian_male/young_caucasian_male.mhmat",
        eyebrows="eyebrow001/eyebrow001.mhclo",
        hair="short02/short02.mhclo",
        hair_mat="bogdan666_short_02_brown",
        clothes=["male_casualsuit01/male_casualsuit01.mhclo"],
        eye_mat="brownlight",
    ),
    # Dona Ivone: the old woman who lived here forty years (old photograph, the Drowner)
    "ivone": dict(
        phenotype={"gender": 0.0, "age": 0.92, "muscle": 0.3, "weight": 0.38, "height": 0.4, "proportions": 0.5, "cupsize": 0.4, "firmness": 0.2},
        race={"african": 0.0, "asian": 0.0, "caucasian": 1.0},
        skin="old_caucasian_female/old_caucasian_female.mhmat",
        eyebrows="eyebrow010/eyebrow010.mhclo",
        hair="long01/long01.mhclo",
        hair_mat="toigo_long_01_gray",
        clothes=["female_elegantsuit01/female_elegantsuit01.mhclo"],
        eye_mat="grey",
    ),
    # O Visitante: very tall, gaunt, in a suit and a fedora
    "visitor": dict(
        phenotype={"gender": 1.0, "age": 0.6, "muscle": 0.25, "weight": 0.0, "height": 1.0, "proportions": 0.0},
        race={"african": 0.0, "asian": 0.0, "caucasian": 1.0},
        skin="old_caucasian_male/old_caucasian_male.mhmat",
        eyebrows="eyebrow001/eyebrow001.mhclo",
        hair=None,
        clothes=["male_elegantsuit01/male_elegantsuit01.mhclo", "fedora01/fedora01.mhclo", "shoes04/shoes04.mhclo"],
        eye_mat="ice",
    ),
    # A Sombra: an emaciated, too-long body (the game stretches its limbs further)
    "shadow": dict(
        phenotype={"gender": 0.5, "age": 0.5, "muscle": 0.0, "weight": 0.0, "height": 1.0, "proportions": 0.0},
        race={"african": 0.33, "asian": 0.33, "caucasian": 0.34},
        skin="young_caucasian_male/young_caucasian_male.mhmat",
        eyebrows=None,
        hair=None,
        clothes=[],
        eye_mat="ice",
    ),
}


def deselect():
    lib.deselect_all()


def activate(ob):
    deselect()
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def build(cid, spec):
    lib.reset_scene()
    info = HumanService._create_default_human_info_dict()
    info["phenotype"].update(spec["phenotype"])
    info["phenotype"]["race"] = spec["race"]
    info["rig"] = "game_engine"
    for k, v in BASE.items():
        info[k] = v
    info["eyebrows"] = spec["eyebrows"] or ""
    info["hair"] = spec["hair"] or ""
    info["clothes"] = list(spec["clothes"])
    info["skin_mhmat"] = spec["skin"]
    info["skin_material_type"] = "GAMEENGINE"
    info["eyes_material_type"] = "MAKESKIN"
    if spec.get("hair_mat"):
        info["alternative_materials"] = {}
    info["name"] = cid
    st = HumanService.get_default_deserialization_settings()
    st["subdiv_levels"] = 0
    body = HumanService.deserialize_from_dict(info, st)
    rig = body.parent
    return body, rig


def bake_shape_keys(ob):
    if ob.data.shape_keys:
        activate(ob)
        bpy.ops.object.shape_key_remove(all=True, apply_mix=True)


def apply_masks(ob):
    """delete the vertices hidden by MASK modifiers (helpers, skin under clothes) and drop the masks."""
    masks = [m for m in ob.modifiers if m.type == "MASK"]
    if not masks:
        return
    me = ob.data
    keep = [True] * len(me.vertices)
    for m in masks:
        g = ob.vertex_groups.get(m.vertex_group)
        inside = [False] * len(me.vertices)
        if g is not None:
            gi = g.index
            for v in me.vertices:
                for e in v.groups:
                    if e.group == gi and e.weight > 0.0:
                        inside[v.index] = True
                        break
        for i in range(len(keep)):
            want = (not inside[i]) if m.invert_vertex_group else inside[i]
            keep[i] = keep[i] and want
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep[v.index]], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    for m in masks:
        ob.modifiers.remove(m)


def eyes_closed_key(body, eyes_ob):
    """create an 'eyes_closed' shape key by sliding the upper eyelids down over the eyeballs."""
    if eyes_ob is None:
        return
    pts = [eyes_ob.matrix_world @ v.co for v in eyes_ob.data.vertices]
    centres = []
    for side in (1, -1):
        sel = [p for p in pts if p.x * side > 0]
        if not sel:
            continue
        c = sum(sel, Vector()) / len(sel)
        r = max((p - c).length for p in sel)
        centres.append((c, r))
    if not body.data.shape_keys:
        body.shape_key_add(name="Basis")
    key = body.shape_key_add(name="eyes_closed", from_mix=False)
    key.value = 0.0
    mw = body.matrix_world
    inv = mw.inverted()
    for i, v in enumerate(body.data.vertices):
        p = mw @ v.co
        for c, r in centres:
            d = p - c
            if d.y > r * 0.35 or d.length > r * 1.75:
                continue
            rho = math.hypot(d.x, d.z)
            if d.z < -r * 0.25 or rho > r * 1.6:
                continue
            w = max(0.0, 1.0 - rho / (r * 1.6))
            w = w * w * (3 - 2 * w)
            target_z = c.z - r * 0.22 + (d.z + r * 0.22) * (1.0 - w) * 0.35 if d.z > -r * 0.22 else p.z
            nz = p.z + (target_z - p.z) * w
            q = Vector((p.x, p.y, nz))
            # keep the lid on (just outside) the eyeball
            dq = q - c
            if dq.length < r * 1.06 and dq.y < 0:
                q = c + dq.normalized() * r * 1.06
            key.data[i].co = inv @ q
            break


def find_image(mat, want):
    def walk(nt):
        out = []
        for n in nt.nodes:
            if n.type == "TEX_IMAGE" and n.image:
                out.append(n.image)
            if n.type == "GROUP" and n.node_tree:
                out += walk(n.node_tree)
        return out

    imgs = walk(mat.node_tree) if mat and mat.node_tree else []
    for im in imgs:
        if want in im.name.lower() or want in os.path.basename(im.filepath).lower():
            return im
    if want == "diffuse":
        for im in imgs:
            n = im.name.lower()
            if "normal" not in n and "ao" not in n and "bump" not in n:
                return im
    return None


def process_image(img, fx, name):
    """texture tweaks done with numpy inside Blender: 'pajama' removes the logo and turns the outfit
    into soft checked flannel."""
    import numpy as np
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    a = px.reshape(h, w, 4)
    rgb = a[..., :3].copy()
    if fx in ("pajama", "nologo"):
        r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
        orange = (r > 0.45) & (r > b + 0.18) & (r > g + 0.05)
        white = (r > 0.7) & (g > 0.7) & (b > 0.7)
        # grow the orange mask so the white parts of the emblem are covered too
        m = orange.copy()
        for _ in range(10):
            m = m | np.roll(m, 1, 0) | np.roll(m, -1, 0) | np.roll(m, 1, 1) | np.roll(m, -1, 1)
        mask = orange | (white & m)
        if fx == "nologo":
            # the printed logo on the white tee (texture rows are bottom-up in Blender)
            yy0, xx0 = np.mgrid[0:h, 0:w]
            fy = 1.0 - yy0 / h
            fxx = xx0 / w
            lum0 = rgb.mean(axis=2)
            for (x0, x1, y0, y1) in ((0.39, 0.66, 0.09, 0.22), (0.16, 0.32, 0.1, 0.18)):
                box = (fxx > x0) & (fxx < x1) & (fy > y0) & (fy < y1)
                mask |= box & ((lum0 < 0.86) | orange)
        for _ in range(60):
            if not mask.any():
                break
            acc = np.zeros_like(rgb)
            cnt = np.zeros(mask.shape, np.float32)
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                sm = np.roll(~mask, (dy, dx), (0, 1))
                acc += np.roll(rgb, (dy, dx), (0, 1)) * sm[..., None]
                cnt += sm
            fill = mask & (cnt > 0)
            rgb[fill] = acc[fill] / cnt[fill][:, None]
            mask = mask & ~fill
    if fx in ("pajama", "nologo"):
        pass
    if fx == "pajama":
        lum = rgb.mean(axis=2, keepdims=True)
        soft = lum * 0.55 + rgb * 0.45
        tint = np.array([0.86, 0.84, 1.0], np.float32)
        yy, xx = np.mgrid[0:h, 0:w]
        check = (((xx // 22) + (yy // 22)) % 2).astype(np.float32)[..., None]
        line = ((xx % 22 < 2) | (yy % 22 < 2)).astype(np.float32)[..., None]
        rgb = soft * tint * (0.94 + 0.08 * check) * (1.0 - 0.08 * line) + np.array([0.06, 0.05, 0.08], np.float32)
    a[..., :3] = np.clip(rgb, 0, 1)
    out = bpy.data.images.new(name, w, h, alpha=True)
    out.pixels.foreach_set(a.ravel())
    path = os.path.join(lib.CACHE, "people_tex", name + ".png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out.filepath_raw = path
    out.file_format = "PNG"
    out.save()
    return out


def simple_material(name, diffuse, normal=None, alpha=False, rough=0.6):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:  # noqa: BLE001
        pass
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Roughness"].default_value = rough
    if diffuse:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = diffuse
        nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
        if alpha:
            nt.links.new(t.outputs["Alpha"], b.inputs["Alpha"])
            for attr, val in (("surface_render_method", "DITHERED"), ("blend_method", "HASHED")):
                try:
                    setattr(m, attr, val)
                except Exception:  # noqa: BLE001
                    pass
    if normal:
        t2 = nt.nodes.new("ShaderNodeTexImage")
        t2.image = normal
        normal.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(t2.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    return m


PART_KEYS = ("eyebrow", "eyelash", "high-poly", "low-poly", "teeth", "tongue", "hair", "ponytail", "braid", "short", "long", "bob", "afro")


def part_of(name, spec):
    n = name.lower()
    if n.endswith(".body") or n == "body":
        return "body"
    if "eyebrow" in n:
        return "eyebrows"
    if "eyelash" in n:
        return "eyelashes"
    if "high-poly" in n or "low-poly" in n:
        return "eyes"
    if "teeth" in n:
        return "teeth"
    if "tongue" in n:
        return "tongue"
    hair = spec.get("hair") or ""
    if hair and hair.split("/")[0].lower() in n:
        return "hair"
    for c in spec["clothes"]:
        if c.split("/")[0].lower() in n:
            return "cloth_" + c.split("/")[0]
    return "misc"


def finish(cid, spec, body, rig):
    bake_shape_keys(body)
    eyes = next((o for o in bpy.data.objects if o.type == "MESH" and part_of(o.name, spec) == "eyes"), None)
    apply_masks(body)
    for o in bpy.data.objects:
        if o.type == "MESH" and o is not body:
            bake_shape_keys(o)
            apply_masks(o)
    eyes_closed_key(body, eyes)
    # materials + names Godot can recognise
    for o in list(bpy.data.objects):
        if o.type != "MESH":
            continue
        part = part_of(o.name, spec)
        mat = o.active_material
        diff = find_image(mat, "diffuse")
        if part == "hair" and spec.get("hair_mat"):
            alt = os.path.join(LocationService.get_user_data("hair"), spec["hair"].split("/")[0], spec["hair_mat"])
            for fn in sorted(os.listdir(alt) if os.path.isdir(alt) else []):
                if fn.lower().endswith((".png", ".jpg")) and "normal" not in fn.lower():
                    diff = bpy.data.images.load(os.path.join(alt, fn), check_existing=True)
                    break
        norm = find_image(mat, "normal")
        fx = spec.get("cloth_fx", {}).get(part.replace("cloth_", ""))
        if fx and diff:
            diff = process_image(diff, fx, f"{cid}_{part}_{fx}")
        alpha = part in ("hair", "eyebrows", "eyelashes")
        rough = {"body": 0.55, "eyes": 0.05, "teeth": 0.25, "tongue": 0.35, "hair": 0.45}.get(part, 0.75)
        m = simple_material(f"{cid}_{part}", diff, norm, alpha, rough)
        o.data.materials.clear()
        o.data.materials.append(m)
        o.name = f"{cid}_{part}"
        o.data.name = o.name
    rig.name = f"{cid}_rig"
    return body


def export(cid, rig):
    deselect()
    rig.select_set(True)
    for ch in rig.children_recursive:
        ch.select_set(True)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{cid}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True,
                              export_skins=True, export_morph=True, export_animations=False, export_materials="EXPORT",
                              export_image_format="AUTO")
    print("EXPORTED", path)


def preview(cid, rig, out_dir):
    prev = lib.collection("_prev")
    scene = lib.setup_render((900, 1100), 32)
    scene.world.color = (0.06, 0.06, 0.07)
    for nm, loc, rot, en, sz in (("key", (1.4, -2.2, 2.3), (0.9, 0, 0.55), 500, 1.5), ("fill", (-2.0, -1.6, 1.4), (1.2, 0, -0.9), 160, 2.5), ("rim", (0.0, 2.0, 2.2), (-0.9, 0, 3.14), 300, 1.0)):
        li = bpy.data.objects.new(nm, bpy.data.lights.new(nm, "AREA"))
        li.data.energy = en
        li.data.size = sz
        li.location = loc
        li.rotation_euler = rot
        prev.objects.link(li)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    prev.objects.link(cam)
    scene.camera = cam
    top = max((o.matrix_world @ Vector(c)).z for o in rig.children_recursive if o.type == "MESH" for c in o.bound_box)
    for k, (dist, h, lens) in enumerate(((3.6, top * 0.55, 50), (0.75, top * 0.93, 70))):
        cam.data.lens = lens
        cam.location = (0.25 * dist, -dist, h)
        tgt = Vector((0, 0, h - (0.0 if k else 0.05)))
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, f"{cid}_{k}.png")
        bpy.ops.render.render(write_still=True)


def main():
    for cid, spec in CHARACTERS.items():
        if ONLY and cid not in ONLY:
            continue
        body, rig = build(cid, spec)
        finish(cid, spec, body, rig)
        export(cid, rig)
        if PREVIEW:
            os.makedirs(PREVIEW, exist_ok=True)
            preview(cid, rig, PREVIEW)


main()
