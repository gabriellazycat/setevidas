"""Clara and Davi from VRoid Studio: tools/vroid/<id>.vrm -> godot/assets/models/people/<id>.glb.

usage: blender -b -P tools/blender/build_vroid.py -- [--only clara_day,...] [--preview dir]

Each VRM (VRM 1.0, one body and face per character, two outfits) is converted to what HumanRig
expects from the old MPFB characters:
  - humanoid bones renamed to the game names (pelvis, spine_01..03, neck_01, head, thigh/calf/foot/ball,
    clavicle/upperarm/lowerarm/hand, fingers); a warning lists any game bone that is missing
  - arms lowered from the VRM T-pose into the A-pose the rig's poses were tuned on, applied as rest
  - meshes split by material into <id>_body (skin, face, mouth), _eyes, _eyebrows, _eyelashes, _hair
    and _cloth, with VRoid's blink as the "eyes_closed" shape key (on every part it moves)
  - MToon materials replaced by Principled ones (base texture and alpha mode kept); the MToon shading
    values go to <id>.toon.json next to the GLB for the Godot toon shader
  - scaled to the target height and checked against anime_proportions.json
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import lib  # noqa: E402
import measure_vrm  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = argv[argv.index("--only") + 1].split(",") if "--only" in argv else None
PREVIEW = argv[argv.index("--preview") + 1] if "--preview" in argv else None
VROID = os.path.join(lib.ROOT, "tools", "vroid")
OUT = os.path.join(lib.GODOT, "assets", "models", "people")

CHARACTERS = {"clara_day": "clara", "clara_night": "clara", "clara_bath": "clara", "davi_day": "davi", "davi_night": "davi"}
# pieces cut after scaling (so the skeleton matches the other outfits): the bath outfit is barefoot
DROP = {"clara_bath": ("shoes_",)}

# VRM 1.0 humanoid bone -> game (Unreal-style) bone name
HUMANOID = {
    "hips": "pelvis", "spine": "spine_01", "chest": "spine_02", "upper_chest": "spine_03", "neck": "neck_01", "head": "head",
    "left_shoulder": "clavicle_l", "left_upper_arm": "upperarm_l", "left_lower_arm": "lowerarm_l", "left_hand": "hand_l",
    "right_shoulder": "clavicle_r", "right_upper_arm": "upperarm_r", "right_lower_arm": "lowerarm_r", "right_hand": "hand_r",
    "left_upper_leg": "thigh_l", "left_lower_leg": "calf_l", "left_foot": "foot_l", "left_toes": "ball_l",
    "right_upper_leg": "thigh_r", "right_lower_leg": "calf_r", "right_foot": "foot_r", "right_toes": "ball_r",
}
for _s, _side in (("left", "l"), ("right", "r")):
    for _f, _g in (("thumb", "thumb"), ("index", "index"), ("middle", "middle"), ("ring", "ring"), ("little", "pinky")):
        for _k, _n in ((("metacarpal" if _f == "thumb" else "proximal"), 1), (("proximal" if _f == "thumb" else "intermediate"), 2), ("distal", 3)):
            HUMANOID[f"{_s}_{_f}_{_k}"] = f"{_g}_0{_n}_{_side}"

# bones HumanRig drives or measures
NEEDED = ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head", "thigh_l", "calf_l", "foot_l", "thigh_r", "calf_r", "foot_r",
          "upperarm_l", "lowerarm_l", "hand_l", "upperarm_r", "lowerarm_r", "hand_r", "clavicle_l", "clavicle_r", "ball_l", "ball_r"]
# angle of the upper arm from hanging straight down in the MPFB rest pose (measured on the old GLBs)
ARM_DOWN = math.radians(42.5)
BLINK = "Fcl_EYE_Close"
# VRoid face shape keys kept for the rig (talking mouth, moods), with short names
FACE = {BLINK: "eyes_closed", "Fcl_MTH_A": "mouth_a", "Fcl_MTH_I": "mouth_i", "Fcl_MTH_O": "mouth_o",
        "Fcl_ALL_Joy": "joy", "Fcl_ALL_Surprised": "surprised", "Fcl_ALL_Sorrow": "sorrow", "Fcl_EYE_Joy": "eye_joy"}


def activate(ob):
    lib.deselect_all()
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def mode(m):
    if bpy.context.object and bpy.context.object.mode != m:
        bpy.ops.object.mode_set(mode=m)


def rename_bones(arm):
    h = arm.data.vrm_addon_extension.vrm1.humanoid.human_bones
    done = {}
    for vrm_name, game in HUMANOID.items():
        hb = getattr(h, vrm_name, None)
        src = hb.node.bone_name if hb is not None and hb.node.bone_name else ""
        b = arm.data.bones.get(src)
        if b is not None:
            b.name = game  # also renames the vertex groups of the skinned meshes
            done[game] = src
    missing = [n for n in NEEDED if n not in arm.data.bones]
    for n in missing:
        print("WARNING missing game bone:", n)
    return missing


def trim_shape_keys(meshes):
    """keep the blink (eyes_closed) and the FACE keys under their short names"""
    for ob in meshes:
        sk = ob.data.shape_keys
        if not sk:
            continue
        for kb in list(sk.key_blocks):
            kb.value = 0.0
        for kb in list(sk.key_blocks)[1:]:
            if kb.name in FACE:
                kb.name = FACE[kb.name]
            else:
                ob.shape_key_remove(kb)
        if len(ob.data.shape_keys.key_blocks) == 1:
            ob.shape_key_clear()


def lower_arms(arm):
    activate(arm)
    mode("POSE")
    for side in ("l", "r"):
        pb = arm.pose.bones["upperarm_" + side]
        lo = arm.pose.bones["lowerarm_" + side]
        head = pb.head.copy()
        d = (lo.head - pb.head).normalized()
        sx = 1.0 if d.x > 0 else -1.0
        want = Vector((sx * math.sin(ARM_DOWN), 0.0, -math.cos(ARM_DOWN)))
        rot = d.rotation_difference(want).to_matrix().to_4x4()
        pb.matrix = Matrix.Translation(head) @ rot @ Matrix.Translation(-head) @ pb.matrix
        bpy.context.view_layer.update()
    mode("OBJECT")


def bake_pose(arm, meshes):
    """write the posed (armature-deformed) shape into each mesh, keeping shape key offsets, then make
    the pose the new rest"""
    dg = bpy.context.evaluated_depsgraph_get()
    for ob in meshes:
        ev = ob.evaluated_get(dg)
        tmp = ev.to_mesh()
        co = [v.co.copy() for v in tmp.vertices]
        ev.to_mesh_clear()
        me = ob.data
        assert len(co) == len(me.vertices), ob.name
        sk = me.shape_keys
        if sk:
            basis = sk.reference_key
            offs = {kb.name: [kb.data[i].co - basis.data[i].co for i in range(len(co))] for kb in sk.key_blocks if kb != basis}
            for i, c in enumerate(co):
                basis.data[i].co = c
                me.vertices[i].co = c
            for kb in sk.key_blocks:
                if kb != basis:
                    off = offs[kb.name]
                    for i, c in enumerate(co):
                        kb.data[i].co = c + off[i]
        else:
            for i, c in enumerate(co):
                me.vertices[i].co = c
        me.update()
    activate(arm)
    mode("POSE")
    bpy.ops.pose.armature_apply(selected=False)
    mode("OBJECT")


def part_for(mat_name):
    n = mat_name.lower()
    if "eyeiris" in n or "eyewhite" in n or "eyehighlight" in n:
        return "eyes"
    if "facebrow" in n:
        return "eyebrows"
    if "eyeline" in n or "eyelash" in n:
        return "eyelashes"
    if "_hair" in n:
        return "hair"
    if "_cloth" in n:
        return "cloth"
    return "body"


def core_name(mat_name):
    n = mat_name.replace(" (Instance)", "").split(".")[0]
    bits = n.split("_")
    return "_".join(bits[3:]) if len(bits) > 3 else n


def principled_from_mtoon(cid, src, toon):
    mt = src.vrm_addon_extension.mtoon1
    pbr = mt.pbr_metallic_roughness
    img = pbr.base_color_texture.index.source
    fac = tuple(pbr.base_color_factor)
    alpha = mt.alpha_mode
    m = bpy.data.materials.new(f"{cid}_{core_name(src.name)}")
    try:
        m.use_nodes = True
    except Exception:  # noqa: BLE001
        pass
    nt = m.node_tree
    b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Roughness"].default_value = 0.6
    b.inputs["Base Color"].default_value = fac
    m.use_backface_culling = not mt.double_sided
    if img is not None:
        t = nt.nodes.new("ShaderNodeTexImage")
        t.image = img
        if fac[:3] != (1.0, 1.0, 1.0):
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(t.outputs["Color"], mix.inputs["A"])
            mix.inputs["B"].default_value = fac
            nt.links.new(mix.outputs["Result"], b.inputs["Base Color"])
        else:
            nt.links.new(t.outputs["Color"], b.inputs["Base Color"])
        if alpha == "MASK":
            # the glTF exporter reads a Round node on the alpha as alphaMode MASK (cutoff 0.5)
            rnd = nt.nodes.new("ShaderNodeMath")
            rnd.operation = "ROUND"
            nt.links.new(t.outputs["Alpha"], rnd.inputs[0])
            nt.links.new(rnd.outputs["Value"], b.inputs["Alpha"])
        elif alpha == "BLEND":
            nt.links.new(t.outputs["Alpha"], b.inputs["Alpha"])
    ext = mt.extensions.vrmc_materials_mtoon
    toon[m.name] = {
        "part": part_for(src.name),
        "alpha": alpha,
        "cutoff": mt.alpha_cutoff,
        "double_sided": mt.double_sided,
        "shade": list(ext.shade_color_factor),
        "toony": ext.shading_toony_factor,
        "shift": ext.shading_shift_factor,
        "rim": list(ext.parametric_rim_color_factor),
        "outline_width": ext.outline_width_factor,
        "outline_color": list(ext.outline_color_factor),
    }
    return m


def convert_materials(cid, meshes):
    toon = {}
    done = {}
    for ob in meshes:
        for slot in ob.material_slots:
            src = slot.material
            if src is None:
                continue
            if src.name not in done:
                done[src.name] = principled_from_mtoon(cid, src, toon)
            slot.material = done[src.name]
    return toon


def split_parts(cid, arm, meshes):
    lib.deselect_all()
    for ob in meshes:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.join()
    whole = bpy.context.view_layer.objects.active
    activate(whole)
    mode("EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.separate(type="MATERIAL")
    mode("OBJECT")
    groups = {}
    # objects merged by join stay in bpy.data without a scene: only look at the live ones
    for ob in [o for o in bpy.context.view_layer.objects if o.type == "MESH"]:
        mats = [m for m in ob.data.materials if m]
        used = {p.material_index for p in ob.data.polygons}
        name = mats[min(used)].name if used and mats else (mats[0].name if mats else "")
        groups.setdefault(part_for(name), []).append(ob)
    out = {}
    for part, obs in groups.items():
        lib.deselect_all()
        for ob in obs:
            ob.select_set(True)
        bpy.context.view_layer.objects.active = obs[0]
        if len(obs) > 1:
            bpy.ops.object.join()
        ob = bpy.context.view_layer.objects.active
        # drop the unused material slots left over by the split
        activate(ob)
        bpy.ops.object.material_slot_remove_unused()
        ob.name = f"{cid}_{part}"
        ob.data.name = ob.name
        sk = ob.data.shape_keys
        if sk:
            # only the keys that move this part
            basis = sk.reference_key
            for kb in list(sk.key_blocks)[1:]:
                if all((kb.data[i].co - basis.data[i].co).length < 1e-6 for i in range(len(kb.data))):
                    ob.shape_key_remove(kb)
            if len(ob.data.shape_keys.key_blocks) == 1:
                ob.shape_key_clear()
        out[part] = ob
    return out


def drop_materials(ob, keys):
    """delete the faces whose material name has one of `keys`, and the vertices left alone"""
    idx = {i for i, m in enumerate(ob.data.materials) if m and any(k in m.name.lower() for k in keys)}
    if not idx:
        return 0
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    faces = [f for f in bm.faces if f.material_index in idx]
    bmesh.ops.delete(bm, geom=faces, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    activate(ob)
    bpy.ops.object.material_slot_remove_unused()
    return len(faces)


def bounds(meshes):
    zs = [(o.matrix_world @ v.co).z for o in meshes for v in o.data.vertices]
    return min(zs), max(zs)


def scale_to(arm, meshes, height):
    lo, hi = bounds(meshes)
    s = height / (hi - lo)
    arm.scale = (s, s, s)
    arm.location.z -= lo * s
    bpy.context.view_layer.update()
    lib.deselect_all()
    arm.select_set(True)
    for ob in meshes:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return s


def check(cid, who, got, missing, parts, meshes):
    with open(os.path.join(os.path.dirname(__file__), "anime_proportions.json"), encoding="utf8") as f:
        spec = json.load(f)
    tol = spec["tol"]
    tgt = spec["targets"][who]
    off = []
    for k, v in got.items():
        if k == "height_m":
            continue
        err = v / tgt[k] - 1.0
        flag = "ok" if abs(err) <= tol else "OFF"
        if flag == "OFF":
            off.append(k)
        print("CHECK %s %-22s %.3f target %.3f %+5.1f%% %s" % (cid, k, v, tgt[k], err * 100, flag))
    lo, hi = bounds(meshes)
    print("CHECK %s height %.3f m (target %.2f)" % (cid, hi - lo, tgt["height_m"]))
    body = parts.get("body")
    has_blink = bool(body and body.data.shape_keys and "eyes_closed" in body.data.shape_keys.key_blocks)
    print("CHECK %s parts=%s eyes_closed_on_body=%s missing_bones=%s ratios_off=%s" % (cid, sorted(parts), has_blink, missing, off))
    for part, ob in sorted(parts.items()):
        keys = [kb.name for kb in ob.data.shape_keys.key_blocks[1:]] if ob.data.shape_keys else []
        print("CHECK %s shape keys %s: %s" % (cid, part, keys))


def export(cid, arm, meshes, toon):
    lib.deselect_all()
    arm.select_set(True)
    for ob in meshes:
        ob.select_set(True)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{cid}.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False, export_yup=True,
                              export_skins=True, export_morph=True, export_animations=False, export_materials="EXPORT",
                              export_image_format="AUTO")
    with open(os.path.join(OUT, f"{cid}.toon.json"), "w", encoding="utf8") as f:
        json.dump(toon, f, indent=1)
    print("EXPORTED", path)


def preview(cid, meshes, out_dir):
    prev = lib.collection("_prev")
    scene = lib.setup_render((700, 1000), 24)
    scene.world.color = (0.08, 0.08, 0.09)
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
    _, top = bounds(meshes)
    # full body front, face close-up, profile
    for k, (pos, h, lens) in enumerate((((0.9, -3.6, 0), top * 0.52, 50), ((0.15, -0.75, 0), top * 0.93, 70), ((3.6, 0.0, 0), top * 0.52, 50))):
        cam.data.lens = lens
        cam.location = (pos[0], pos[1], h)
        tgt = Vector((0, 0, h - (0.0 if k == 1 else 0.05)))
        cam.rotation_euler = (tgt - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, f"{cid}_{k}.png")
        bpy.ops.render.render(write_still=True)


def build(cid, who):
    with open(os.path.join(os.path.dirname(__file__), "anime_proportions.json"), encoding="utf8") as f:
        height = json.load(f)["targets"][who]["height_m"]
    lib.reset_scene()
    got = measure_vrm.measure(os.path.join(VROID, f"{cid}.vrm"))   # imports the VRM
    for o in [o for o in bpy.data.objects if o.type not in ("ARMATURE", "MESH")]:
        bpy.data.objects.remove(o, do_unlink=True)
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    # the importer can leave some meshes outside the view layer or hidden
    vl = bpy.context.view_layer
    for ob in [arm] + meshes:
        if ob.name not in vl.objects:
            bpy.context.scene.collection.objects.link(ob)
        ob.hide_viewport = False
        ob.hide_set(False)
        ob.hide_select = False
    missing = rename_bones(arm)
    trim_shape_keys(meshes)
    lower_arms(arm)
    bake_pose(arm, meshes)
    toon = convert_materials(cid, meshes)
    parts = split_parts(cid, arm, meshes)
    meshes = list(parts.values())
    for ob in meshes:
        if ob.parent != arm:
            mw = ob.matrix_world.copy()
            ob.parent = arm
            ob.matrix_world = mw
    scale_to(arm, meshes, height)
    for ob in meshes:
        if DROP.get(cid):
            n = drop_materials(ob, DROP[cid])
            if n:
                print("DROP %s %s: %d faces" % (cid, ob.name, n))
    arm.name = f"{cid}_rig"
    check(cid, who, got, missing, parts, meshes)
    export(cid, arm, meshes, toon)
    if PREVIEW:
        os.makedirs(PREVIEW, exist_ok=True)
        preview(cid, meshes, PREVIEW)


def main():
    for cid, who in CHARACTERS.items():
        if ONLY and cid not in ONLY:
            continue
        build(cid, who)


main()
