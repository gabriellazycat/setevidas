"""Probe: build one MPFB human headless and render a preview (used while developing build_humans.py)."""
import sys
import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = argv[0] if argv else "//probe.png"

from bl_ext.blender_org.mpfb.services.humanservice import HumanService
from bl_ext.blender_org.mpfb.services.targetservice import TargetService

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
info = HumanService._create_default_human_info_dict()
info["phenotype"].update({"gender": 0.0, "age": 0.45, "muscle": 0.5, "weight": 0.45, "height": 0.45, "proportions": 0.75, "cupsize": 0.5, "firmness": 0.5})
info["phenotype"]["race"] = {"african": 0.1, "asian": 0.05, "caucasian": 0.85}
info["rig"] = "game_engine"
info["eyes"] = "high-poly/high-poly.mhclo"
info["eyebrows"] = "eyebrow001/eyebrow001.mhclo"
info["eyelashes"] = "eyelashes01/eyelashes01.mhclo"
info["teeth"] = "teeth_base/teeth_base.mhclo"
info["tongue"] = "tongue01/tongue01.mhclo"
info["hair"] = "ponytail01/ponytail01.mhclo"
info["clothes"] = ["female_casualsuit01/female_casualsuit01.mhclo", "shoes02/shoes02.mhclo"]
info["skin_mhmat"] = "young_caucasian_female/young_caucasian_female.mhmat"
info["skin_material_type"] = "GAMEENGINE"
info["eyes_material_type"] = "MAKESKIN"
info["name"] = "Clara"
settings = HumanService.get_default_deserialization_settings()
settings["subdiv_levels"] = 0
basemesh = HumanService.deserialize_from_dict(info, settings)
print("BASEMESH", basemesh.name, len(basemesh.data.vertices))
for o in bpy.data.objects:
    print("OBJ", o.name, o.type, [m.type for m in getattr(o, "modifiers", [])], [s.name for s in o.material_slots] if hasattr(o, "material_slots") else "")

# preview
scene = bpy.context.scene
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        scene.render.engine = eng
        break
    except TypeError:
        pass
cam_data = bpy.data.cameras.new("cam")
cam = bpy.data.objects.new("cam", cam_data)
scene.collection.objects.link(cam)
cam.location = (0.0, -3.2, 1.25)
cam.rotation_euler = (1.5, 0, 0)
cam_data.lens = 50
scene.camera = cam
light = bpy.data.objects.new("key", bpy.data.lights.new("key", "AREA"))
light.data.energy = 600
light.data.size = 2
light.location = (1.6, -2.2, 2.4)
light.rotation_euler = (0.9, 0, 0.6)
scene.collection.objects.link(light)
fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "AREA"))
fill.data.energy = 200
fill.data.size = 3
fill.location = (-2.0, -1.5, 1.5)
fill.rotation_euler = (1.2, 0, -0.9)
scene.collection.objects.link(fill)
world = bpy.data.worlds.new("w")
scene.world = world
world.color = (0.05, 0.05, 0.06)
scene.render.resolution_x = 700
scene.render.resolution_y = 900
scene.render.filepath = out
bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=out.replace(".png", ".blend"))
print("RENDERED", out)
