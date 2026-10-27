class_name HumanRig
extends Node3D
## A person (Clara, Davi, Dona Ivone...): day and night outfits on the same "game engine" skeleton,
## dressed with skin / hair / eye materials. Clara and Davi are VRoid models ("anime": toon + outline
## materials from <id>.toon.json); the ghosts keep the MPFB models and the realistic materials.
##
## Layers, per outfit skeleton (children run in this order):
##   AnimationTree   mocap clips retargeted from the Quaternius library (res://assets/anims/<id>.res,
##                   scripts/dev/retarget.gd): idle / walk / jog blended by speed with the cycle
##                   synced to the ground speed, looping states (sitting, crouching, phone...) and
##                   one-shots (sit down, stand up, startle...)
##   HumanPoseMod    the procedural poses (lying, bath, hugging the knees...) blended per joint over
##                   the clips, each joint easing in with its own delay; breathing, sleep, tremble,
##                   gestures and the look chain (eyes, head, neck, chest) on a damped spring
##   TwoBoneIK3D     feet on the steps, hands on the cat / bowl
##   SpringBoneSimulator3D  hair (J_Sec_Hair*) and Clara's skirt
## Models without a clip library (the ghosts) run the poses and the old procedural walk cycle.

const TOON := preload("res://shaders/toon.gdshader")
const TOON_BLEND := preload("res://shaders/toon_blend.gdshader")
const OUTLINE := preload("res://shaders/outline.gdshader")

# ref_pelvis / ref_hipw: rest pelvis height and hip width of the MPFB models the poses (hips_y) were
# tuned on
const LOOKS := {
	"clara": {"anime": true, "ref_pelvis": 0.804, "ref_hipw": 0.179, "skin": Color(1.0, 0.86, 0.78), "hair": Color(0.32, 0.2, 0.13), "hair_night": Color(0.42, 0.32, 0.26), "eyes": "brown"},
	"davi": {"anime": true, "ref_pelvis": 1.045, "ref_hipw": 0.237, "skin": Color(0.86, 0.66, 0.52), "hair": Color(0.16, 0.11, 0.08), "hair_night": Color(0.16, 0.11, 0.08), "eyes": "brownlight"},
	"ivone": {"skin": Color(0.96, 0.9, 0.86), "hair": Color(1.0, 1.0, 1.0), "hair_night": Color(1.0, 1.0, 1.0), "eyes": "grey"},
}

# Each pose: hips_y (pelvis drop), then joint Euler angles (radians, model axes, same conventions
# as the web version: +x bends forward for the spine/head, -x swings limbs forward).
static func P(o: Dictionary) -> Dictionary:
	var d := {"hips_y": 0.0, "hips": Vector3.ZERO, "spine": Vector3.ZERO, "chest": Vector3.ZERO, "neck": Vector3.ZERO, "head": Vector3.ZERO,
		"shL": Vector3(0, 0, 0.12), "elL": Vector3(-0.15, 0, 0), "shR": Vector3(0, 0, -0.12), "elR": Vector3(-0.15, 0, 0),
		"thL": Vector3.ZERO, "knL": Vector3.ZERO, "thR": Vector3.ZERO, "knR": Vector3.ZERO}
	for k in o.keys():
		d[k] = o[k]
	return d

static var POSES := {
	"stand": P({}),
	"stare": P({"head": Vector3(0.12, 0, 0), "shL": Vector3(0, 0, 0.05), "shR": Vector3(0, 0, -0.05), "elL": Vector3.ZERO, "elR": Vector3.ZERO}),
	# on her back, head on the pillow: arms along the body, hands on the sheet by the hips (IK, _belly_w);
	# knees a little bent
	"lie": P({"hips": Vector3(-PI / 2, 0, 0), "hips_y": -0.43, "thL": Vector3(-0.12, 0, 0.04), "knL": Vector3(0.22, 0, 0), "thR": Vector3(-0.05, 0, -0.03), "knR": Vector3(0.1, 0, 0), "shL": Vector3(-0.3, 0, -0.15), "shR": Vector3(-0.3, 0, 0.15), "spine": Vector3(0.1, 0, 0), "chest": Vector3(0.05, 0, 0), "neck": Vector3(0.28, 0, 0), "head": Vector3(0.0, 0, 0), "elL": Vector3(-1.4, 0, 0), "elR": Vector3(-1.4, 0, 0)}),
	# awake in bed, rolled toward one side (Y before the X pitch rolls the body about its long axis)
	# both hands resting on the belly (none under the body or up in the air)
	"lieSide": P({"hips": Vector3(-PI / 2, 0.55, 0), "hips_y": -0.43, "thL": Vector3(-0.35, 0, 0), "knL": Vector3(0.55, 0, 0), "thR": Vector3(-0.2, 0, 0), "knR": Vector3(0.35, 0, 0), "shL": Vector3(-0.3, 0, -0.15), "shR": Vector3(-0.3, 0, 0.15), "elL": Vector3(-1.3, 0, 0), "elR": Vector3(-1.3, 0, 0), "neck": Vector3(0.2, 0, 0), "head": Vector3(-0.1, -0.35, 0)}),
	# sitting up against the pillow: hands on the thighs, elbows bent
	"sitUp": P({"hips_y": -0.4, "thL": Vector3(-1.5, 0, 0), "thR": Vector3(-1.5, 0, 0), "knL": Vector3(0.15, 0, 0), "knR": Vector3(0.15, 0, 0), "shL": Vector3(-0.5, 0, 0.12), "shR": Vector3(-0.5, 0, -0.12), "elL": Vector3(-0.75, 0, 0), "elR": Vector3(-0.75, 0, 0), "spine": Vector3(0.12, 0, 0)}),
	"hug": P({"hips_y": -0.42, "thL": Vector3(-2.3, 0, 0), "thR": Vector3(-2.3, 0, 0), "knL": Vector3(2.2, 0, 0), "knR": Vector3(2.2, 0, 0), "spine": Vector3(0.45, 0, 0), "chest": Vector3(0.2, 0, 0), "neck": Vector3(0.3, 0, 0), "head": Vector3(0.25, 0, 0), "shL": Vector3(-1.25, 0, 0.1), "shR": Vector3(-1.25, 0, -0.1), "elL": Vector3(-1.4, 0, 0), "elR": Vector3(-1.4, 0, 0)}),
	"cry": P({"hips_y": -0.42, "thL": Vector3(-2.3, 0, 0), "thR": Vector3(-2.3, 0, 0), "knL": Vector3(2.2, 0, 0), "knR": Vector3(2.2, 0, 0), "spine": Vector3(0.5, 0, 0), "chest": Vector3(0.25, 0, 0), "neck": Vector3(0.35, 0, 0), "head": Vector3(0.35, 0, 0), "shL": Vector3(-2.2, 0, 0.35), "shR": Vector3(-2.2, 0, -0.35), "elL": Vector3(-2.3, 0, 0), "elR": Vector3(-2.3, 0, 0)}),
	"paralysis": P({"hips_y": -0.4, "thL": Vector3(-1.5, 0, 0), "thR": Vector3(-1.5, 0, 0), "spine": Vector3(-0.1, 0, 0), "neck": Vector3(-0.25, 0, 0), "head": Vector3(-0.2, 0, 0), "shL": Vector3(-0.4, 0, 0.2), "shR": Vector3(-0.4, 0, -0.2), "elL": Vector3(-0.35, 0, 0), "elR": Vector3(-0.35, 0, 0)}),
	"kneel": P({"hips_y": -0.44, "thL": Vector3(0.05, 0, 0), "thR": Vector3(0.05, 0, 0), "knL": Vector3(1.55, 0, 0), "knR": Vector3(1.55, 0, 0), "spine": Vector3(0.7, 0, 0), "chest": Vector3(0.2, 0, 0), "neck": Vector3(0.1, 0, 0), "shL": Vector3(-1.3, 0, 0.15), "shR": Vector3(-1.3, 0, -0.15), "elL": Vector3(-0.3, 0, 0), "elR": Vector3(-0.3, 0, 0)}),
	"sit": P({"hips_y": -0.44, "thL": Vector3(-1.5, 0, 0.06), "thR": Vector3(-1.5, 0, -0.06), "knL": Vector3(1.5, 0, 0), "knR": Vector3(1.5, 0, 0), "shL": Vector3(-0.3, 0, 0.1), "shR": Vector3(-0.3, 0, -0.1), "elL": Vector3(-0.8, 0, 0), "elR": Vector3(-0.8, 0, 0)}),
	"read": P({"hips_y": -0.44, "thL": Vector3(-1.5, 0, 0), "thR": Vector3(-1.5, 0, 0), "knL": Vector3(1.5, 0, 0), "knR": Vector3(1.5, 0, 0), "spine": Vector3(0.15, 0, 0), "neck": Vector3(0.12, 0, 0), "head": Vector3(0.12, 0, 0), "shL": Vector3(-0.9, 0, 0.2), "shR": Vector3(-0.9, 0, -0.2), "elL": Vector3(-0.9, 0, 0), "elR": Vector3(-0.9, 0, 0)}),
	"reach": P({"spine": Vector3(0.15, 0, 0), "shR": Vector3(-1.35, 0, -0.05), "elR": Vector3(-0.2, 0, 0), "head": Vector3(0.15, 0, 0)}),
	"pet": P({"hips_y": -0.42, "thL": Vector3(-1.1, 0, 0), "thR": Vector3(-0.4, 0, 0), "knL": Vector3(2.1, 0, 0), "knR": Vector3(1.9, 0, 0), "spine": Vector3(0.5, 0, 0), "neck": Vector3(0.3, 0, 0), "shR": Vector3(-0.9, 0, -0.1), "elR": Vector3(-0.3, 0, 0), "shL": Vector3(-0.2, 0, 0.2)}),
	"phone": P({"shR": Vector3(-0.4, 0, -0.9), "elR": Vector3(-2.4, 0, 0), "head": Vector3(0, 0.2, -0.1)}),
	"drink": P({"shR": Vector3(-1.1, 0, -0.3), "elR": Vector3(-2.0, 0, 0), "head": Vector3(-0.25, 0, 0)}),
	"bath": P({"hips_y": -0.62, "hips": Vector3(-1.0, 0, 0), "thL": Vector3(-1.45, 0, 0.1), "thR": Vector3(-1.45, 0, -0.1), "knL": Vector3(1.95, 0, 0), "knR": Vector3(1.95, 0, 0), "neck": Vector3(0.6, 0, 0), "head": Vector3(0.25, 0, 0), "shL": Vector3(0, 0, 0.4), "shR": Vector3(0, 0, -0.4)}),
	"carry": P({"shL": Vector3(-1.1, 0, 0.25), "shR": Vector3(-1.1, 0, -0.25), "elL": Vector3(-1.2, 0, 0), "elR": Vector3(-1.2, 0, 0)}),
	"arms_up": P({"shL": Vector3(-2.9, 0, 0.2), "shR": Vector3(-2.9, 0, -0.2), "elL": Vector3(-0.35, 0, 0), "elR": Vector3(-0.35, 0, 0), "head": Vector3(-0.4, 0, 0)}),
	"sit_talk": P({"hips_y": -0.44, "thL": Vector3(-1.5, 0, 0.06), "thR": Vector3(-1.5, 0, -0.06), "knL": Vector3(1.5, 0, 0), "knR": Vector3(1.5, 0, 0), "shL": Vector3(-0.3, 0, 0.1), "shR": Vector3(-0.3, 0, -0.1), "elL": Vector3(-0.8, 0, 0), "elR": Vector3(-0.8, 0, 0)}),
	"fold": P({"shL": Vector3(-0.9, 0, -0.5), "elL": Vector3(-1.9, 0, 0), "shR": Vector3(-0.9, 0, 0.5), "elR": Vector3(-1.9, 0, 0)}),
	"talk": P({}),
	# on all fours (the Shadow fleeing): pelvis pitched forward, thighs and arms down to the floor
	"crawl": P({"hips": Vector3(1.35, 0, 0), "hips_y": -0.5, "spine": Vector3(0.1, 0, 0), "chest": Vector3(-0.1, 0, 0), "neck": Vector3(-0.7, 0, 0), "head": Vector3(-0.5, 0, 0),
		"thL": Vector3(-1.35, 0, 0.05), "thR": Vector3(-1.35, 0, -0.05), "knL": Vector3(1.6, 0, 0), "knR": Vector3(1.6, 0, 0),
		"shL": Vector3(-1.45, 0, 0.12), "shR": Vector3(-1.45, 0, -0.12), "elL": Vector3(-0.1, 0, 0), "elR": Vector3(-0.1, 0, 0)}),
	# the Shadow running (shadow_run.glb): on its back like a spider, belly up, knees high, the long
	# arms reaching down behind it and the head bent all the way back, upside down, looking ahead.
	# It runs head first: its body is turned around (ShadowThreat turns the model by PI)
	"spider": P({"hips": Vector3(-1.45, 0, 0), "hips_y": -1.2, "spine": Vector3(-0.15, 0, 0), "chest": Vector3(-0.1, 0, 0), "neck": Vector3(-0.7, 0, 0), "head": Vector3(-0.9, 0, 0),
		"thL": Vector3(-0.75, 0, 0.12), "thR": Vector3(-0.75, 0, -0.12), "knL": Vector3(2.0, 0, 0), "knR": Vector3(2.0, 0, 0),
		"shL": Vector3(1.35, 0, 0.85), "shR": Vector3(1.35, 0, -0.85), "elL": Vector3(-0.7, 0, 0), "elR": Vector3(-0.7, 0, 0)}),
	# the Visitor at the door: knocking with the right hand, listening with the head on the wood,
	# the face and both hands pressed on a window pane
	"knock": P({"spine": Vector3(0.05, 0, 0), "head": Vector3(0.1, 0, 0), "shR": Vector3(-1.35, 0, 0.05), "elR": Vector3(-1.5, 0, 0), "shL": Vector3(0, 0, 0.05), "elL": Vector3(0, 0, 0)}),
	"listen": P({"spine": Vector3(0.2, 0, 0.1), "chest": Vector3(0.1, 0, 0.1), "neck": Vector3(0.2, 0, 0.45), "head": Vector3(0.15, 0, 0.55), "shR": Vector3(-1.1, 0, -0.35), "elR": Vector3(-1.0, 0, 0), "shL": Vector3(0, 0, 0.05), "elL": Vector3(0, 0, 0)}),
	"window_press": P({"spine": Vector3(0.15, 0, 0), "neck": Vector3(0.15, 0, 0), "head": Vector3(0.05, 0, 0), "shL": Vector3(-1.55, 0, -0.8), "elL": Vector3(-1.3, 0, 0), "shR": Vector3(-1.55, 0, 0.8), "elR": Vector3(-1.3, 0, 0)}),
	"loom": P({"spine": Vector3(0.35, 0, 0), "chest": Vector3(0.25, 0, 0), "neck": Vector3(0.4, 0, 0), "head": Vector3(0.3, 0, 0), "shL": Vector3(-0.5, 0, 0.15), "shR": Vector3(-0.5, 0, -0.15), "elL": Vector3(-0.2, 0, 0), "elR": Vector3(-0.2, 0, 0)}),
}

const JOINTS := ["hips", "spine", "chest", "neck", "head", "shL", "elL", "shR", "elR", "thL", "knL", "thR", "knR"]
const BONES := {"hips": "pelvis", "spine": "spine_01", "chest": "spine_02", "neck": "neck_01", "head": "head",
	"shL": "upperarm_l", "elL": "lowerarm_l", "shR": "upperarm_r", "elR": "lowerarm_r",
	"thL": "thigh_l", "knL": "calf_l", "thR": "thigh_r", "knR": "calf_r"}
const ARMS := ["shL", "elL", "shR", "elR"]
const UPPER := ["spine", "chest", "neck", "head", "shL", "elL", "shR", "elR"]
# pose -> [clip state (null: fully procedural), joints still posed procedurally over the clip]
const POSE_MIX := {
	"stand": ["loco", []],
	"stare": ["loco", ["neck", "head", "shL", "elL", "shR", "elR"]],
	"sit": ["sit_idle", []],
	"sit_talk": ["sit_talk", []],
	"read": ["sit_idle", ["neck", "head", "shL", "elL", "shR", "elR"]],
	"kneel": ["crouch_idle", []],
	"pet": ["crouch_idle", ["shR", "elR"]],
	"phone": ["phone", []],
	"fold": ["fold_arms", []],
	"talk": ["talk", []],
	"reach": ["loco", ["spine", "head", "shR", "elR"]],
	"drink": ["loco", ["head", "shR", "elR"]],
	"carry": ["loco", ["shL", "elL", "shR", "elR"]],
	"arms_up": ["loco", ["spine", "chest", "neck", "head", "shL", "elL", "shR", "elR"]],
	"loom": ["loco", ["spine", "chest", "neck", "head", "shL", "elL", "shR", "elR"]],
}
const SEATED := ["sit_idle", "sit_talk"]
# pelvis height over the feet sat on a seat at the default height (seat_lift 0), the same for everyone
const SEAT_PELVIS := 0.364
# standing clips whose legs are the library's guard stance (feet wide, one in front, hips turned):
# standing still they get a plain stance (STANCE_BONES back to rest) and the shoulders drop
const STANCE_STATES := ["loco", "talk", "phone", "fold_arms"]
const STANCE_BONES := ["thigh_l", "calf_l", "foot_l", "ball_l", "thigh_r", "calf_r", "foot_r", "ball_r"]
# trunk first, then the arms, the head last
const DELAY := {"hips": 0.0, "thL": 0.0, "thR": 0.0, "knL": 0.04, "knR": 0.04, "spine": 0.02, "chest": 0.06,
	"shL": 0.1, "shR": 0.1, "elL": 0.16, "elR": 0.16, "neck": 0.12, "head": 0.18}
const SLOW_POSES := ["lie", "lieSide", "sitUp", "hug", "cry", "paralysis", "bath", "kneel", "pet"]

# procedural one-shot gestures over the clips: the joints they move and keyframes [time, {joint: euler}]
const GESTURES := {
	"glasses": {"len": 1.3, "keys": [[0.35, {"shR": Vector3(-1.15, 0, 0.3), "elR": Vector3(-2.5, 0, 0), "head": Vector3(0.1, 0, 0)}], [0.9, {"shR": Vector3(-1.2, 0, 0.3), "elR": Vector3(-2.55, 0, 0), "head": Vector3(0.1, 0, 0)}]]},
	"hair": {"len": 1.7, "keys": [[0.45, {"shR": Vector3(-0.9, 0, -1.9), "elR": Vector3(-2.4, 0, 0), "head": Vector3(0, 0, -0.12)}], [1.1, {"shR": Vector3(-0.8, 0, -1.8), "elR": Vector3(-2.3, 0, 0), "head": Vector3(0, 0, -0.08)}]]},
	"yawn": {"len": 2.4, "keys": [[0.5, {"shR": Vector3(-1.1, 0, 0.25), "elR": Vector3(-2.5, 0, 0), "head": Vector3(-0.35, 0, 0), "neck": Vector3(-0.1, 0, 0)}], [1.7, {"shR": Vector3(-1.1, 0, 0.25), "elR": Vector3(-2.5, 0, 0), "head": Vector3(-0.3, 0, 0), "neck": Vector3(-0.1, 0, 0)}]]},
	"stretch": {"len": 2.6, "keys": [[0.7, {"shL": Vector3(-2.9, 0, 0.35), "shR": Vector3(-2.9, 0, -0.35), "elL": Vector3(-0.25, 0, 0), "elR": Vector3(-0.25, 0, 0), "spine": Vector3(-0.15, 0, 0), "head": Vector3(-0.3, 0, 0)}], [1.8, {"shL": Vector3(-2.95, 0, 0.45), "shR": Vector3(-2.95, 0, -0.45), "elL": Vector3(-0.1, 0, 0), "elR": Vector3(-0.1, 0, 0), "spine": Vector3(-0.2, 0, 0), "head": Vector3(-0.35, 0, 0)}]]},
	"hug_self": {"len": 2.4, "keys": [[0.4, {"shL": Vector3(-0.85, 0, -0.55), "elL": Vector3(-2.0, 0, 0), "shR": Vector3(-0.85, 0, 0.55), "elR": Vector3(-2.0, 0, 0), "head": Vector3(0.15, 0, 0), "spine": Vector3(0.1, 0, 0)}], [2.0, {"shL": Vector3(-0.9, 0, -0.6), "elL": Vector3(-2.1, 0, 0), "shR": Vector3(-0.9, 0, 0.6), "elR": Vector3(-2.1, 0, 0), "head": Vector3(0.2, 0, 0), "spine": Vector3(0.12, 0, 0)}]]},
	"look_back": {"len": 2.0, "keys": [[0.5, {"chest": Vector3(0, 0.35, 0), "neck": Vector3(0, 0.45, 0), "head": Vector3(0, 0.55, 0)}], [1.4, {"chest": Vector3(0, 0.35, 0), "neck": Vector3(0, 0.45, 0), "head": Vector3(0.05, 0.6, 0)}]]},
	"sneeze": {"len": 1.4, "keys": [[0.3, {"head": Vector3(-0.3, 0, 0), "spine": Vector3(-0.1, 0, 0), "shR": Vector3(-0.9, 0, 0.3), "elR": Vector3(-2.2, 0, 0)}], [0.5, {"head": Vector3(0.45, 0, 0), "spine": Vector3(0.35, 0, 0), "shR": Vector3(-1.1, 0, 0.35), "elR": Vector3(-2.45, 0, 0)}], [0.9, {"head": Vector3(0.25, 0, 0), "spine": Vector3(0.15, 0, 0), "shR": Vector3(-1.0, 0, 0.3), "elR": Vector3(-2.4, 0, 0)}]]},
	"key_turn": {"len": 1.5, "keys": [[0.4, {"shR": Vector3(-1.25, 0, -0.05), "elR": Vector3(-0.5, 0, 0), "head": Vector3(0.15, 0, 0)}], [1.0, {"shR": Vector3(-1.25, 0, 0.05), "elR": Vector3(-0.6, 0, 0), "head": Vector3(0.15, 0, 0)}]]},
	"switch": {"len": 1.0, "keys": [[0.4, {"shR": Vector3(-1.6, 0, -0.25), "elR": Vector3(-0.35, 0, 0)}], [0.6, {"shR": Vector3(-1.55, 0, -0.25), "elR": Vector3(-0.4, 0, 0)}]]},
	"pat": {"len": 1.5, "keys": [[0.3, {"shR": Vector3(-0.5, 0, 0.1), "elR": Vector3(-0.9, 0, 0)}], [0.55, {"shR": Vector3(-0.35, 0, 0.1), "elR": Vector3(-0.6, 0, 0)}], [0.8, {"shR": Vector3(-0.5, 0, 0.1), "elR": Vector3(-0.9, 0, 0)}], [1.05, {"shR": Vector3(-0.35, 0, 0.1), "elR": Vector3(-0.6, 0, 0)}]]},
	"pull": {"len": 1.4, "keys": [[0.35, {"shL": Vector3(-1.2, 0, 0.2), "shR": Vector3(-1.2, 0, -0.2), "elL": Vector3(-0.2, 0, 0), "elR": Vector3(-0.2, 0, 0), "spine": Vector3(0.45, 0, 0)}], [0.85, {"shL": Vector3(-0.4, 0, 0.2), "shR": Vector3(-0.4, 0, -0.2), "elL": Vector3(-1.6, 0, 0), "elR": Vector3(-1.6, 0, 0), "spine": Vector3(-0.1, 0, 0)}]]},
	"wave": {"len": 1.8, "keys": [[0.35, {"shR": Vector3(-0.4, 0, -2.3), "elR": Vector3(-1.0, 0, 0)}], [0.7, {"shR": Vector3(-0.4, 0, -2.3), "elR": Vector3(-1.6, 0, 0)}], [1.05, {"shR": Vector3(-0.4, 0, -2.3), "elR": Vector3(-1.0, 0, 0)}], [1.4, {"shR": Vector3(-0.4, 0, -2.3), "elR": Vector3(-1.5, 0, 0)}]]},
	"hat_tip": {"len": 1.6, "keys": [[0.45, {"shR": Vector3(-2.3, 0, -0.25), "elR": Vector3(-2.3, 0, 0), "head": Vector3(0.25, 0, 0), "neck": Vector3(0.1, 0, 0)}], [1.0, {"shR": Vector3(-2.35, 0, -0.25), "elR": Vector3(-2.4, 0, 0), "head": Vector3(0.3, 0, 0), "neck": Vector3(0.12, 0, 0)}]]},
	"cross_arms": {"len": 3.0, "keys": [[0.5, {"shL": Vector3(-0.9, 0, -0.5), "elL": Vector3(-1.9, 0, 0), "shR": Vector3(-0.9, 0, 0.5), "elR": Vector3(-1.9, 0, 0)}], [2.5, {"shL": Vector3(-0.9, 0, -0.5), "elL": Vector3(-1.9, 0, 0), "shR": Vector3(-0.9, 0, 0.5), "elR": Vector3(-1.9, 0, 0)}]]},
}
# arms for what is being carried (over the clips), and where the thing sits: [bone, offset in the
# body's frame, hangs upright from the hand]
const HOLD_ARMS := {
	"box": {"shL": Vector3(-1.05, 0, 0.3), "elL": Vector3(-1.25, 0, 0), "shR": Vector3(-1.05, 0, -0.3), "elR": Vector3(-1.25, 0, 0)},
	"suitcase": {"shR": Vector3(0.05, 0, -0.32), "elR": Vector3(-0.05, 0, 0)},
	"doll": {"shR": Vector3(-0.75, 0, 0.15), "elR": Vector3(-1.5, 0, 0)},
	"cushion": {"shL": Vector3(-0.75, 0, -0.35), "elL": Vector3(-1.85, 0, 0), "shR": Vector3(-0.75, 0, 0.35), "elR": Vector3(-1.85, 0, 0), "head": Vector3(0.12, 0, 0)},
	# a book hugged to the chest with one arm; open in both hands to read it
	"book": {"shL": Vector3(-0.6, 0, -0.45), "elL": Vector3(-2.1, 0, 0)},
	# the hands themselves go onto the book's edges by IK (_ik_targets); these only start the arms there
	"book_open": {"shL": Vector3(-0.8, 0, 0.15), "elL": Vector3(-1.3, 0, 0), "shR": Vector3(-0.8, 0, -0.15), "elR": Vector3(-1.3, 0, 0)},
	"book_open_stand": {"shL": Vector3(-0.6, 0, 0.15), "elL": Vector3(-1.7, 0, 0), "shR": Vector3(-0.6, 0, -0.15), "elR": Vector3(-1.7, 0, 0)},
}
# [bone (or "hands": between them), offset in the body's frame, optional tilt (Euler, body frame)]
const HOLD_AT := {
	"box": ["spine_02", Vector3(0, -0.14, 0.3)],
	"suitcase": ["hand_r", Vector3(-0.05, -0.02, 0)],
	"doll": ["hand_r", Vector3(0, -0.06, 0.05)],
	"book": ["spine_02", Vector3(0.04, 0.0, 0.15), Vector3(PI / 2 - 0.15, 0, 0)],
	"book_open": ["spine_02", Vector3(0, -0.09, 0.26), Vector3(-0.8, 0, 0)],
	"cushion": ["spine_02", Vector3(0, -0.06, 0.2)],
	"backpack": ["spine_02", Vector3(0, -0.02, -0.17)],
}
# random life while standing idle
const IDLE_GESTURES := {"clara": ["hair", "look_back", "stretch"], "davi": ["glasses", "glasses", "cross_arms"]}

var who := "clara"
var outfits := {}         # "day"/"night" -> {root, skel, body, maps, tree, ik...}
var cur_outfit := ""
var pose := "stand":
	set(v):
		if v != pose:
			pose = v
			_pose_changed()
var speed := 0.0
var style := "normal"     # normal | hypno | hurry
var tremble := 0.0
var eyes_wide := 0.0
var asleep := false
var cur := {}             # joint -> Euler the procedural layer is at
var wj := {}              # joint -> 0..1 how much the procedural layer overrides the clip
var hips_y := 0.0
var gait := 0.0
var t := 0.0
var blink := 0.0
var blink_t := 3.0
var extra_tint := Color(1, 1, 1)  # ghosts reuse the rig with their own materials
var ref_pelvis := 0.804           # LOOKS ref_pelvis of this person
var pelvis_d := 0.0               # rest pelvis height minus the MPFB one the seated / lying drops assume
var look_target = null            # world point the head turns to (null: straight ahead)
var look_yaw := 0.0               # how far (rad, signed) the target is outside what the neck can reach
var sleep_side := 1.0             # asleep the head rolls to this side
var hand_target = null            # world point for the right hand (petting, the bowl), null: free
var hand_target_l = null
var ground_ik := true             # feet onto the floor / steps under them
var seat_back := false            # walked up to the front of the seat: the sit clip moves the hips back
var seat_lift := 0.0              # seat height above the floor she stands on, over the default
var seat_deep := 0.0              # walked up to a seat: extra share of the clip's way back (longer legs sit further in)
var idle_anim := "idle"
# the library's Walk_Loop leans forward with bent elbows and fists (a fighter's walk); the formal
# walk is upright with the arms loose
var walk_anim := "walk_formal"
var jog_anim := "jog"
var has_clips := false
var _pt0 := -100.0                # pose transition: start time, length, where each joint came from
var _pdur := 0.5
var _from := {}
var _wfrom := {}
var _hips_from := 0.0
var _add := {}                    # joint -> additive Euler (breathing, tremble, sleep, idle noise)
var _state = "loco"
var _slot := "a"
var _slot_anim := {"a": "", "b": ""}
var _shot := ""
var _shot_t := -100.0
var _gest := ""
var _gest_t := 0.0
var _idle_t := 0.0
var _look_v := Vector3.ZERO       # look spring: rotation vector and its velocity
var _look_vel := Vector3.ZERO
var _breath_ph := 0.0
var _breath_amp := 0.015
var _sleep_k := 0.0
var _feet_w := 0.0
var _stance_w := 0.0              # 0..1 how much of the plain stance replaces the clip's legs
var _move_k := 0.0                # 0..1 idle -> walk blend, eased (speed jumps when she stops or turns)
var _hand_w := 0.0
var _hand_w_l := 0.0
var _book_w := 0.0
var _belly_w := 0.0                 # lying on her back: free hands IK'd onto the sheet by the hips
var _mood := {"joy": 0.0, "surprised": 0.0, "sorrow": 0.0, "eye_joy": 0.0}
var _mood_want := {"joy": 0.0, "surprised": 0.0, "sorrow": 0.0, "eye_joy": 0.0}
var _mood_hold := 0.0
var _talk_text := ""
var _talk_t := 0.0
var _talk_dur := 0.0
var _mouth := {"mouth_a": 0.0, "mouth_i": 0.0, "mouth_o": 0.0}
var _noise_ph := Vector3(randf() * 10.0, randf() * 10.0, randf() * 10.0)
var held := {}                    # "hand" / "back" -> [node, kind]
var hold_tune := {}               # dev (--holdtune): kind -> arms, over HOLD_ARMS
var grip_tune := {}               # dev (--holdtune "_grip"): the book grip's numbers
var _hold_cur := {}               # joint -> Euler of the holding arms (blends in and out)
var _hold_w := {}                 # joint -> 0..1
var _beat := 0.0                  # a knock: the forearm snaps toward the door and back
var jerky := 0.0                  # > 0: the procedural pose only updates this many times a second
var _jerk_t := 0.0
var _mods := 0                       # modifier passes since the pose last changed
var _final: Array[Transform3D] = []   # skeleton-space bone poses as last modified (the skeleton
                                      # reports the unmodified ones outside the modifier pass)


func _init(character := "clara", ids := {}) -> void:
	who = character
	if ids.is_empty():
		ids = {"day": "%s_day" % character, "night": "%s_night" % character}
		if ResourceLoader.exists("res://assets/models/people/%s_bath.glb" % character):
			ids["bath"] = "%s_bath" % character
	for k in ids.keys():
		outfits[k] = {"id": ids[k]}


func _ready() -> void:
	for k in outfits.keys():
		var o: Dictionary = outfits[k]
		var ps: PackedScene = load("res://assets/models/people/%s.glb" % o["id"])
		var inst: Node3D = ps.instantiate()
		inst.visible = false
		add_child(inst)
		o["root"] = inst
		var skel: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
		o["skel"] = skel
		o["maps"] = _bone_maps(skel)
		_dress(inst, k)
		_build_layers(k)
	_measure(outfits[outfits.keys()[0]])
	for j in JOINTS:
		cur[j] = Vector3.ZERO
		wj[j] = 1.0
		_add[j] = Vector3.ZERO
	set_outfit(outfits.keys()[0])
	snap_pose("stand")
	if who == "davi":
		_build_glasses()


func _bone_maps(skel: Skeleton3D) -> Dictionary:
	var m := {"idx": {}, "rest_rot": {}, "rest_pos": {}, "g": {}, "pg": {}, "hang": {}}
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i)
		m["idx"][n] = i
		var rest := skel.get_bone_rest(i)
		m["rest_rot"][i] = rest.basis.get_rotation_quaternion()
		m["rest_pos"][i] = rest.origin
		m["g"][i] = skel.get_bone_global_rest(i).basis.orthonormalized()
		var p := skel.get_bone_parent(i)
		m["pg"][i] = skel.get_bone_global_rest(p).basis.orthonormalized() if p >= 0 else Basis.IDENTITY
	# arms rest in an A-pose: measure how far each upper arm is raised from hanging straight down
	for side in ["l", "r"]:
		var ua: int = m["idx"].get("upperarm_" + side, -1)
		var la: int = m["idx"].get("lowerarm_" + side, -1)
		if ua >= 0 and la >= 0:
			var a := skel.get_bone_global_rest(ua).origin
			var b := skel.get_bone_global_rest(la).origin
			var d := (b - a).normalized()
			var ang := atan2(d.x, -d.y)  # >0: hand out toward +x
			m["hang"][side] = Quaternion(Vector3(0, 0, 1), -ang)
			# MPFB rests with the elbows bent forward: straighten the forearm onto the upper arm line
			var h: int = m["idx"].get("hand_" + side, -1)
			if h >= 0:
				var c := skel.get_bone_global_rest(h).origin
				var f := (c - b).normalized()
				m["straight_" + side] = Quaternion(f, d)
	return m


func _measure(o: Dictionary) -> void:
	var look: Dictionary = LOOKS.get(who, {})
	if not look.get("anime", false):
		return
	var skel: Skeleton3D = o["skel"]
	var gp := func(n: String) -> Vector3:
		var i := skel.find_bone(n)
		return skel.get_bone_global_rest(i).origin if i >= 0 else Vector3.ZERO
	ref_pelvis = float(look["ref_pelvis"])
	pelvis_d = (gp.call("pelvis") as Vector3).y - ref_pelvis
	# head_world: the middle of the skull, ~0.56 of the way from the head bone to the top of the hair
	var top := 0.0
	for mi in (o["root"] as Node).find_children("*", "MeshInstance3D", true, false):
		var n := str(mi.name).to_lower()
		if n.ends_with("_body") or n.ends_with("_hair"):
			var ab: AABB = (mi as MeshInstance3D).mesh.get_aabb()
			top = maxf(top, ab.position.y + ab.size.y)
	o["head_off"] = maxf(0.08, (top - (gp.call("head") as Vector3).y) * 0.56)


func _toon_data(id: String) -> Dictionary:
	var f := FileAccess.open("res://assets/models/people/%s.toon.json" % id, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func _toon_material(src: BaseMaterial3D, spec: Dictionary, part: String, key: String) -> Material:
	var blend: bool = spec.get("alpha", "MASK") == "BLEND"
	var m := ShaderMaterial.new()
	m.shader = TOON_BLEND if blend else TOON
	var tex: Texture2D = src.albedo_texture if src else null
	var col: Color = src.albedo_color if src else Color(1, 1, 1)
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("albedo", col)
	m.set_shader_parameter("alpha_cut", float(spec.get("cutoff", 0.5)))
	var sh: Array = spec.get("shade", [1, 1, 1])
	var shade := Color(sh[0], sh[1], sh[2])
	match part:
		"hair":
			# VRoid leaves the hair shade white: use a warm darker band instead
			shade = Color(0.72, 0.58, 0.62)
			m.set_shader_parameter("ring_strength", 0.35)
			m.set_shader_parameter("rim_strength", 0.18)
		"eyes", "eyebrows", "eyelashes":
			shade = Color(1, 1, 1)
			m.set_shader_parameter("shade_amount", 0.85)
			m.set_shader_parameter("rim_strength", 0.0)
		"cloth":
			m.set_shader_parameter("rim_strength", 0.14)
		_:
			m.set_shader_parameter("rim_strength", 0.22)
	m.set_shader_parameter("shade_color", shade)
	# MToon: a positive shift lights more of the surface (VRoid faces use ~0.7 so they stay clean)
	m.set_shader_parameter("shade_shift", clampf(-float(spec.get("shift", 0.0)), -0.8, 0.3))
	m.set_shader_parameter("shade_soft", maxf(0.03, (1.0 - float(spec.get("toony", 0.9))) * 0.6))
	if blend:
		# irises under highlights, brows and eyelines on top
		m.render_priority = 1 if "iris" in key else (2 if "highlight" in key else 3)
	if part in ["body", "cloth", "hair"] and not "mouth" in key:
		var ol := ShaderMaterial.new()
		ol.shader = OUTLINE
		ol.set_shader_parameter("albedo_tex", tex)
		ol.set_shader_parameter("albedo", col)
		ol.set_shader_parameter("width", {"body": 0.0014, "cloth": 0.0018, "hair": 0.0012}[part])
		ol.set_shader_parameter("alpha_cut", float(spec.get("cutoff", 0.5)))
		m.next_pass = ol
	return m


func _dress_anime(root: Node, outfit: String) -> void:
	var o: Dictionary = outfits[outfit]
	var toon := _toon_data(o["id"])
	var blinkers: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var n := m.name.to_lower()
		var part := n.get_slice("_", n.get_slice_count("_") - 1)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if part in ["eyes", "eyebrows", "eyelashes"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if part == "body":
			o["body"] = m
		elif part == "cloth":
			o["cloth"] = m
		elif part == "eyes":
			o["eyes"] = m
		if m.find_blend_shape_by_name("eyes_closed") >= 0:
			blinkers.append(m)
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si) as BaseMaterial3D
			var key: String = src.resource_name if src else ""
			m.set_surface_override_material(si, _toon_material(src, toon.get(key, {}), part, key.to_lower()))
	o["blink"] = blinkers


func _dress(root: Node, outfit: String) -> void:
	# only characters listed as anime (the ghosts fall back to Clara's realistic colours below)
	if LOOKS.get(who, {}).get("anime", false):
		_dress_anime(root, outfit)
		return
	var look: Dictionary = LOOKS.get(who, LOOKS["clara"])
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var n := m.name.to_lower()
		var src := m.mesh.surface_get_material(0) as BaseMaterial3D
		var tex: Texture2D = src.albedo_texture if src else null
		var nrm: Texture2D = src.normal_texture if src else null
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		if nrm:
			mat.normal_enabled = true
			mat.normal_texture = nrm
		if n.ends_with("_body"):
			mat.albedo_color = look["skin"] * extra_tint
			mat.roughness = 0.55
			mat.subsurf_scatter_enabled = true
			mat.subsurf_scatter_strength = 0.35
			mat.subsurf_scatter_skin_mode = true
			mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
			if nrm == null:
				mat.normal_enabled = false
			outfits[outfit]["body"] = m
		elif n.ends_with("_hair") or n.ends_with("_eyebrows") or n.ends_with("_eyelashes"):
			var hc: Color = look["hair_night" if outfit == "night" else "hair"]
			mat.albedo_color = hc if not n.ends_with("_eyelashes") else Color(0.15, 0.1, 0.08)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.35
			mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE_AND_TO_ONE
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.roughness = 0.5
			mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
			mat.backlight_enabled = true
			mat.backlight = Color(0.25, 0.18, 0.12)
			if n.ends_with("_eyebrows") or n.ends_with("_eyelashes"):
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.ends_with("_eyes"):
			outfits[outfit]["eyes"] = m
			mat.albedo_texture = load("res://assets/models/people/eyes/%s_eye.png" % look["eyes"])
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR  # the cornea shell is transparent
			mat.alpha_scissor_threshold = 0.5
			mat.roughness = 0.08
			mat.clearcoat_enabled = true
			mat.clearcoat = 1.0
			mat.clearcoat_roughness = 0.02
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif n.ends_with("_teeth"):
			mat.albedo_color = Color(0.9, 0.86, 0.8)
			mat.roughness = 0.3
		elif n.ends_with("_tongue"):
			mat.albedo_color = Color(0.7, 0.35, 0.35)
			mat.roughness = 0.35
		else:
			mat.roughness = 0.85
			mat.albedo_color = extra_tint
		m.material_override = mat


## Davi's round wire spectacles, glued to the head bone (offset measured from the eye mesh)
var glasses: Node3D


func _build_glasses() -> void:
	# lens spacing / size from the eye mesh (both eyes, whites included) of the first outfit
	var sep := 0.032
	var r := 0.0195
	var tx := 0.071
	var em0: MeshInstance3D = outfits[outfits.keys()[0]].get("eyes")
	var anime: bool = LOOKS.get(who, {}).get("anime", false)
	if anime and em0:
		var w := em0.mesh.get_aabb().size.x
		sep = w * 0.34
		r = w * 0.18
		tx = w * 0.63
	glasses = Node3D.new()
	glasses.name = "glasses"
	add_child(glasses)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.12, 0.1, 0.08)
	metal.metallic = 0.9
	metal.roughness = 0.35
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.85, 0.9, 0.95, 0.12)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.02
	glass.metallic_specular = 0.9
	for sx in [-1.0, 1.0]:
		var rim := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r - 0.001
		tm.outer_radius = r + 0.001
		tm.rings = 32
		tm.ring_segments = 6
		rim.mesh = tm
		rim.material_override = metal
		rim.rotation = Vector3(PI / 2, 0, 0)
		rim.position = Vector3(sep * sx, 0, 0)
		glasses.add_child(rim)
		var lens := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = r - 0.0007
		cm.bottom_radius = r - 0.0007
		cm.height = 0.0015
		cm.radial_segments = 24
		lens.mesh = cm
		lens.material_override = glass
		lens.rotation = Vector3(PI / 2, 0, 0)
		lens.position = rim.position
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glasses.add_child(lens)
		var temple := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.0018, 0.0018, 0.1)
		temple.mesh = bm
		temple.material_override = metal
		temple.position = Vector3(tx * sx, 0.004, -0.05)
		temple.rotation = Vector3(0, 0.06 * sx, 0)
		glasses.add_child(temple)
	var bridge := MeshInstance3D.new()
	var tb := TorusMesh.new()
	tb.inner_radius = maxf(0.004, sep - r - 0.0006)
	tb.outer_radius = maxf(0.0053, sep - r + 0.0007)
	tb.rings = 16
	tb.ring_segments = 4
	bridge.mesh = tb
	bridge.material_override = metal
	bridge.rotation = Vector3(PI / 2, 0, 0)
	bridge.position = Vector3(0, 0.004, 0)
	bridge.scale = Vector3(1, 1, 0.5)
	glasses.add_child(bridge)
	# per outfit: the glasses' transform relative to the head bone, from the eye mesh at rest
	for k in outfits.keys():
		var o: Dictionary = outfits[k]
		var em: MeshInstance3D = o.get("eyes")
		var skel: Skeleton3D = o["skel"]
		var hi: int = o["maps"]["idx"].get("head", -1)
		if em == null or hi < 0:
			continue
		var ab := em.mesh.get_aabb()
		# the anime face is flatter around the eyes and the nose sticks out further
		var c := ab.get_center() + Vector3(0, 0.002, ab.size.z / 2.0 + (0.025 if anime else 0.012))
		var rest := skel.get_bone_global_rest(hi)
		o["glasses_local"] = rest.affine_inverse() * Transform3D(Basis.IDENTITY, c)


## Clara's towel turban for the bath (tools/blender/build_turban.py): sized to the hair and glued to
## the head bone like the glasses; the hair underneath is hidden
var turban: Node3D


## the bath outfit's towel is a dress: in the tub its skirt would stick out of the water over the
## bent knees, so it is cut there (the dress template's skirt below the hips is UV.y > 0.64)
func hide_skirt(on: bool) -> void:
	if not outfits.has("bath") or not outfits["bath"].has("cloth"):
		return
	var m: MeshInstance3D = outfits["bath"]["cloth"]
	for si in m.mesh.get_surface_count():
		var mat := m.get_surface_override_material(si) as ShaderMaterial
		while mat:
			mat.set_shader_parameter("hide_v", 0.64 if on else 9.0)
			mat = mat.next_pass as ShaderMaterial


## the shoes are their own surface of each outfit's cloth (VRoid "Shoes_"): cut away whole in bed,
## the body's own feet are under them
func hide_shoes(on: bool) -> void:
	for k in outfits.keys():
		var m: MeshInstance3D = outfits[k].get("cloth")
		if m == null:
			continue
		for si in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(si)
			if src == null or not src.resource_name.to_lower().contains("shoes"):
				continue
			var mat := m.get_surface_override_material(si) as ShaderMaterial
			while mat:
				mat.set_shader_parameter("hide_v", -1.0 if on else 9.0)
				mat = mat.next_pass as ShaderMaterial


func set_turban(on: bool) -> void:
	if on and turban == null and ResourceLoader.exists("res://assets/models/people/turban.glb"):
		turban = (load("res://assets/models/people/turban.glb") as PackedScene).instantiate()
		add_child(turban)
		var tm := StandardMaterial3D.new()
		tm.albedo_texture = load("res://assets/textures/gen/towel_cream.png")
		tm.albedo_color = Color(0.98, 0.93, 0.86)
		tm.uv1_scale = Vector3(4, 4, 1)
		tm.roughness = 0.95
		tm.rim_enabled = true
		tm.rim = 0.25
		for mi in turban.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = tm
	if turban:
		turban.visible = on
	for k in outfits:
		for mi in (outfits[k]["root"] as Node).find_children("*_hair", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).visible = not on


func _update_turban(sk: Skeleton3D, idx: Dictionary) -> void:
	if turban == null or not turban.visible:
		return
	var o: Dictionary = outfits[cur_outfit]
	if not o.has("turban_local"):
		# skull centre and width from the hair mesh at rest, in the head bone's frame
		var hair: MeshInstance3D = null
		for mi in (o["root"] as Node).find_children("*_hair", "MeshInstance3D", true, false):
			hair = mi
		var hi: int = idx["head"]
		var rest := sk.get_bone_global_rest(hi)
		var c := rest.origin + Vector3(0, float(o.get("head_off", 0.08)), 0)
		var w := 0.2
		if hair:
			var ab := hair.mesh.get_aabb()
			w = minf(ab.size.x, 0.26)
		# the model's twist points along +x: turn it to the forehead
		o["turban_local"] = rest.affine_inverse() * Transform3D(Basis(Vector3.UP, -PI / 2).scaled(Vector3.ONE * w * 1.0), c + Vector3(0, 0.05, -0.02))
	turban.global_transform = sk.global_transform * bone_global(idx["head"]) * (o["turban_local"] as Transform3D)


func _update_glasses() -> void:
	if glasses == null:
		return
	var o: Dictionary = outfits[cur_outfit]
	if not o.has("glasses_local"):
		glasses.visible = false
		return
	glasses.visible = not asleep
	var skel: Skeleton3D = o["skel"]
	var hi: int = o["maps"]["idx"].get("head", -1)
	glasses.global_transform = skel.global_transform * skel.get_bone_global_pose(hi) * (o["glasses_local"] as Transform3D)


func set_outfit(o: String) -> void:
	if not outfits.has(o):
		o = outfits.keys()[0]
	if o != cur_outfit:
		_final.clear()
	cur_outfit = o
	for k in outfits.keys():
		var od: Dictionary = outfits[k]
		var on: bool = k == o
		(od["root"] as Node3D).visible = on
		if od.has("tree"):
			(od["tree"] as AnimationTree).active = on
		for mn in ["mod", "ik_feet", "ik_hand_r", "ik_hand_l", "grip", "springs"]:
			if od.has(mn):
				(od[mn] as SkeletonModifier3D).active = on
	if outfits[o].has("springs"):
		(outfits[o]["springs"] as SpringBoneSimulator3D).reset()


# ------------------------------------------------------------------------------------ layers


func _build_layers(k: String) -> void:
	var o: Dictionary = outfits[k]
	var skel: Skeleton3D = o["skel"]
	var lib_path := "res://assets/anims/%s.res" % o["id"]
	if ResourceLoader.exists(lib_path):
		var lib: AnimationLibrary = load(lib_path)
		has_clips = true
		var ap := AnimationPlayer.new()
		ap.name = "Clips"
		skel.add_child(ap)
		ap.root_node = NodePath("..")
		ap.add_animation_library("", lib)
		o["lib"] = lib
		var tree := AnimationTree.new()
		tree.name = "Mixer"
		skel.add_child(tree)
		tree.root_node = NodePath("..")
		tree.anim_player = tree.get_path_to(ap)
		tree.tree_root = _blend_tree()
		tree.active = false
		o["tree"] = tree
		var sit: Animation = lib.get_animation("sit_idle")
		o["sit_pel"] = sit.get_meta("pelvis_first", Vector3.ZERO) if sit else Vector3.ZERO
	var mod := HumanPoseMod.new()
	mod.name = "Pose"
	mod.rig = self
	mod.outfit = k
	skel.add_child(mod)
	o["mod"] = mod
	# feet and hands: two-bone IK toward target nodes placed by _modify
	var targets := {}
	for tn in ["foot_l", "foot_r", "knee_l", "knee_r", "hand_r", "elbow_r", "hand_l", "elbow_l"]:
		var n3 := Node3D.new()
		n3.name = "ik_%s_%s" % [k, tn]
		add_child(n3)
		targets[tn] = n3
	o["ik_t"] = targets
	var feet := TwoBoneIK3D.new()
	feet.name = "FeetIK"
	skel.add_child(feet)
	feet.setting_count = 2
	for si in 2:
		var sd: String = ["l", "r"][si]
		feet.set_root_bone_name(si, "thigh_" + sd)
		feet.set_middle_bone_name(si, "calf_" + sd)
		feet.set_end_bone_name(si, "foot_" + sd)
		feet.set_target_node(si, feet.get_path_to(targets["foot_" + sd]))
		feet.set_pole_node(si, feet.get_path_to(targets["knee_" + sd]))
	feet.influence = 0.0
	o["ik_feet"] = feet
	for sd in ["r", "l"]:
		var hand := TwoBoneIK3D.new()
		hand.name = "HandIK_" + sd
		skel.add_child(hand)
		hand.setting_count = 1
		hand.set_root_bone_name(0, "upperarm_" + sd)
		hand.set_middle_bone_name(0, "lowerarm_" + sd)
		hand.set_end_bone_name(0, "hand_" + sd)
		hand.set_target_node(0, hand.get_path_to(targets["hand_" + sd]))
		hand.set_pole_node(0, hand.get_path_to(targets["elbow_" + sd]))
		hand.influence = 0.0
		o["ik_hand_" + sd] = hand
	# after the hand IK: the wrists and fingers around what the hands hold
	var grip := HumanPoseMod.new()
	grip.name = "Grip"
	grip.rig = self
	grip.outfit = k
	grip.post = true
	skel.add_child(grip)
	o["grip"] = grip
	_build_springs(o)
	for mn in ["mod", "ik_feet", "ik_hand_r", "ik_hand_l", "grip"]:
		(o[mn] as SkeletonModifier3D).active = false


func _blend_tree() -> AnimationNodeBlendTree:
	var bt := AnimationNodeBlendTree.new()
	var an := func(nm: String) -> AnimationNodeAnimation:
		var a := AnimationNodeAnimation.new()
		a.animation = nm
		return a
	bt.add_node("idle", an.call(idle_anim))
	bt.add_node("walk", an.call(walk_anim))
	bt.add_node("jog", an.call(jog_anim))
	bt.add_node("walk_ts", AnimationNodeTimeScale.new())
	bt.add_node("jog_ts", AnimationNodeTimeScale.new())
	var run := AnimationNodeBlend2.new()
	run.sync = true
	bt.add_node("run", run)
	var move := AnimationNodeBlend2.new()
	move.sync = true
	bt.add_node("move", move)
	bt.add_node("slot_a", an.call("idle"))
	bt.add_node("slot_b", an.call("idle"))
	var st := AnimationNodeTransition.new()
	st.add_input("loco")
	st.add_input("a")
	st.add_input("b")
	st.xfade_time = 0.4
	bt.add_node("state", st)
	bt.add_node("act", an.call("idle"))
	var shot := AnimationNodeOneShot.new()
	shot.fadein_time = 0.2
	shot.fadeout_time = 0.3
	bt.add_node("shot", shot)
	bt.connect_node("walk_ts", 0, "walk")
	bt.connect_node("jog_ts", 0, "jog")
	bt.connect_node("run", 0, "walk_ts")
	bt.connect_node("run", 1, "jog_ts")
	bt.connect_node("move", 0, "idle")
	bt.connect_node("move", 1, "run")
	bt.connect_node("state", 0, "move")
	bt.connect_node("state", 1, "slot_a")
	bt.connect_node("state", 2, "slot_b")
	bt.connect_node("shot", 0, "state")
	bt.connect_node("shot", 1, "act")
	bt.connect_node("output", 0, "shot")
	return bt


## spring bones on the VRoid secondary chains: hair, and the skirt's coat bones
func _build_springs(o: Dictionary) -> void:
	var sk: Skeleton3D = o["skel"]
	var roots := []
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		if not n.begins_with("J_Sec_") or "Bust" in n:
			continue
		var par := sk.get_bone_parent(i)
		if par >= 0 and sk.get_bone_name(par).begins_with("J_Sec_"):
			continue
		var leaf := i
		while sk.get_bone_children(leaf).size() > 0:
			leaf = sk.get_bone_children(leaf)[0]
		if leaf != i:
			roots.append([n, sk.get_bone_name(leaf), "Skirt" in n])
	if roots.is_empty():
		return
	var sim := SpringBoneSimulator3D.new()
	sim.name = "Springs"
	sk.add_child(sim)
	sim.setting_count = roots.size()
	for k in roots.size():
		var r: Array = roots[k]
		sim.set_root_bone_name(k, r[0])
		sim.set_end_bone_name(k, r[1])
		var skirt: bool = r[2]
		sim.set_stiffness(k, 1.4 if skirt else 1.2)
		sim.set_drag(k, 0.5 if skirt else 0.45)
		sim.set_gravity(k, 0.25 if skirt else 0.3)
		sim.set_radius(k, 0.03 if skirt else 0.012)
		sim.set_enable_all_child_collisions(k, true)
	# colliders: the skull keeps the hair off the face, the legs push the skirt
	var head := SpringBoneCollisionSphere3D.new()
	head.bone_name = "head"
	head.radius = 0.075
	head.position_offset = Vector3(0, 0.07, 0.005)
	sim.add_child(head)
	for sd in ["l", "r"]:
		for b in ["thigh_", "calf_"]:
			var cap := SpringBoneCollisionCapsule3D.new()
			cap.bone_name = b + sd
			cap.radius = 0.075 if b == "thigh_" else 0.055
			cap.height = 0.42
			cap.position_offset = Vector3(0, 0.2, 0)
			sim.add_child(cap)
	sim.active = false
	o["springs"] = sim


func reset_springs() -> void:
	if outfits.has(cur_outfit) and outfits[cur_outfit].has("springs"):
		(outfits[cur_outfit]["springs"] as SpringBoneSimulator3D).reset()


# ------------------------------------------------------------------------------------ poses


func snap_pose(p: String) -> void:
	pose = p
	var d: Dictionary = POSES.get(p, POSES["stand"])
	var mask: Array = _mask(p)
	for j in JOINTS:
		cur[j] = d[j]
		_from[j] = d[j]
		wj[j] = 1.0 if (j in mask) else 0.0
		_wfrom[j] = wj[j]
	hips_y = d["hips_y"]
	_hips_from = hips_y
	_pt0 = -100.0
	_mods = 0
	if outfits.has(cur_outfit) and outfits[cur_outfit].has("tree"):
		var st = POSE_MIX.get(p, [null, []])[0]
		_set_state(st, true)
		(outfits[cur_outfit]["tree"] as AnimationTree).set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	reset_springs()


## joints the procedural layer drives in this pose (all of them without clips)
func _mask(p: String) -> Array:
	if not has_clips:
		return JOINTS
	var mix: Array = POSE_MIX.get(p, [null, []])
	return JOINTS if mix[0] == null else mix[1]


func _pose_changed() -> void:
	if cur.is_empty():
		return
	for j in JOINTS:
		_from[j] = cur[j]
		_wfrom[j] = wj[j]
	_hips_from = hips_y
	_pt0 = t
	_mods = 0
	_pdur = 0.9 if (pose in SLOW_POSES) else 0.55
	if not has_clips:
		return
	var st = POSE_MIX.get(pose, [null, []])[0]
	var was_seated: bool = _state in SEATED
	var seated: bool = st in SEATED
	if seated and not was_seated:
		play_once("sit_down", 0.2, 0.35)
	elif was_seated and not seated and (st == "loco" or st == null):
		play_once("stand_up", 0.15, 0.3)
	_set_state(st)


## every joint has reached the pose (and the clip blend is done)
func pose_settled(tol := 0.02) -> bool:
	# the bones (bone_global) only show the pose after the modifier has run on it
	if t < _pt0 + _pdur + 0.2 or _mods < 2:
		return false
	var d: Dictionary = POSES.get(pose, POSES["stand"])
	for j in JOINTS:
		var e: Vector3 = (cur[j] as Vector3) - (d[j] as Vector3)
		if maxf(absf(e.x), maxf(absf(e.y), absf(e.z))) > tol:
			return false
	return absf(hips_y - float(d["hips_y"])) < 0.005


## 0..1 chest rise of the breathing cycle, scaled by how deep it is (asleep: 1)
func breath_rise() -> float:
	return (sin(_breath_ph) * 0.5 + 0.5) * clampf(_breath_amp / 0.03, 0.0, 1.0)


func head_world() -> Vector3:
	var o: Dictionary = outfits[cur_outfit]
	var skel: Skeleton3D = o["skel"]
	var i: int = o["maps"]["idx"].get("head", -1)
	if i < 0:
		return global_position + Vector3.UP * 1.6
	return skel.global_transform * (bone_global(i) * Vector3(0, float(o.get("head_off", 0.08)), 0))


func bone_world(bone: String) -> Transform3D:
	var o: Dictionary = outfits[cur_outfit]
	var skel: Skeleton3D = o["skel"]
	var i: int = o["maps"]["idx"].get(bone, -1)
	if i < 0:
		return global_transform
	return skel.global_transform * bone_global(i)


static func _e(v: Vector3) -> Quaternion:
	return Quaternion(Basis.from_euler(v, EULER_ORDER_XYZ))


## the local rotation that turns a bone by q_model (model axes, from its rest)
func _proc_local(m: Dictionary, i: int, q_model: Quaternion) -> Quaternion:
	var g: Basis = m["g"][i]
	return (m["rest_rot"][i] as Quaternion) * Quaternion(g.inverse() * Basis(q_model) * g)


# ------------------------------------------------------------------------------------ clips


func _set_state(st, instant := false) -> void:
	if not outfits.has(cur_outfit):
		return
	var o: Dictionary = outfits[cur_outfit]
	if not o.has("tree"):
		return
	var tree: AnimationTree = o["tree"]
	var bt: AnimationNodeBlendTree = tree.tree_root
	var name: String = "loco" if st == null else str(st)
	_state = name if st != null else null
	if st == null:
		_state = null
	if name == "loco":
		tree.set("parameters/state/transition_request", "loco")
		return
	var lib: AnimationLibrary = o["lib"]
	if not lib.has_animation(name):
		tree.set("parameters/state/transition_request", "loco")
		return
	# reuse the slot already playing it, else load the idle slot and cross-fade to it
	var cur_in := str(tree.get("parameters/state/current_state"))
	if cur_in in ["a", "b"] and _slot_anim[cur_in] == name:
		return
	var slot := "b" if cur_in == "a" else "a"
	(bt.get_node("slot_" + slot) as AnimationNodeAnimation).animation = name
	_slot_anim[slot] = name
	tree.set("parameters/state/transition_request", slot)


## a mocap one-shot over whatever the body is doing (sit_down, stand_up, hit, interact, chest_open...)
func play_once(clip: String, fade_in := 0.2, fade_out := 0.3) -> void:
	if not outfits.has(cur_outfit) or not outfits[cur_outfit].has("tree"):
		return
	var o: Dictionary = outfits[cur_outfit]
	var lib: AnimationLibrary = o["lib"]
	if not lib.has_animation(clip):
		return
	var tree: AnimationTree = o["tree"]
	var bt: AnimationNodeBlendTree = tree.tree_root
	(bt.get_node("act") as AnimationNodeAnimation).animation = clip
	var shot := bt.get_node("shot") as AnimationNodeOneShot
	shot.fadein_time = fade_in
	shot.fadeout_time = fade_out
	tree.set("parameters/shot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_shot = clip
	_shot_t = t


func shot_playing() -> bool:
	if not outfits.has(cur_outfit) or not outfits[cur_outfit].has("tree"):
		return false
	return bool((outfits[cur_outfit]["tree"] as AnimationTree).get("parameters/shot/active"))


## a procedural gesture (GESTURES) over the clips
func gesture(name: String) -> void:
	if GESTURES.has(name):
		_gest = name
		_gest_t = 0.0
		_idle_t = 0.0


func beat() -> void:
	_beat = 1.0


func gesturing() -> bool:
	return _gest != ""


## carry a prop: kind box | suitcase | doll | book (in the hands) or backpack (on the back). The node
## is reparented to the rig and follows the hand / chest every frame; drop_held gives it back.
func hold(node: Node3D, kind: String) -> void:
	var slot := "back" if kind == "backpack" else "hand"
	drop_held(slot)
	if node.get_parent():
		node.get_parent().remove_child(node)
	add_child(node)
	held[slot] = [node, kind]


func drop_held(slot := "hand") -> Node3D:
	if not held.has(slot):
		return null
	var n: Node3D = held[slot][0]
	held.erase(slot)
	return n


func holding(slot := "hand") -> String:
	return str(held[slot][1]) if held.has(slot) else ""


func _place_held(sk: Skeleton3D, idx: Dictionary) -> void:
	var yaw_b := Basis(Vector3.UP, global_rotation.y)
	for slot in held:
		var n: Node3D = held[slot][0]
		if not is_instance_valid(n):
			continue
		var at: Array = HOLD_AT.get(held[slot][1], ["hand_r", Vector3.ZERO])
		var p: Vector3
		if at[0] == "hands":
			var a := sk.global_transform * sk.get_bone_global_pose(idx["hand_l"]).origin
			var b := sk.global_transform * sk.get_bone_global_pose(idx["hand_r"]).origin
			p = (a + b) * 0.5
		else:
			p = sk.global_transform * sk.get_bone_global_pose(idx.get(at[0], 0)).origin
		var tilt := Basis.from_euler(at[2]) if at.size() > 2 else Basis.IDENTITY
		var off: Vector3 = at[1]
		if held[slot][1] == "book_open" and _state not in SEATED:
			# reading standing up: the book higher, at the chest
			off = Vector3(0, 0.02, 0.26)
		n.global_transform = Transform3D(yaw_b * tilt, p + yaw_b * off)


func set_loco_anims(idle: String, walk: String, jog: String) -> void:
	idle_anim = idle
	walk_anim = walk
	jog_anim = jog
	for k in outfits:
		if outfits[k].has("tree"):
			var bt: AnimationNodeBlendTree = (outfits[k]["tree"] as AnimationTree).tree_root
			(bt.get_node("idle") as AnimationNodeAnimation).animation = idle
			(bt.get_node("walk") as AnimationNodeAnimation).animation = walk
			(bt.get_node("jog") as AnimationNodeAnimation).animation = jog


func _drive_mixer(o: Dictionary) -> void:
	var tree: AnimationTree = o["tree"]
	var lib: AnimationLibrary = o["lib"]
	var wa: Animation = lib.get_animation(walk_anim)
	var ja: Animation = lib.get_animation(jog_anim)
	var lw := wa.length
	var lj := ja.length
	var dw := float(wa.get_meta("speed", 1.0)) * lw      # metres per cycle at normal speed
	var dj := float(ja.get_meta("speed", 2.4)) * lj
	var b := clampf((speed - 1.3) / 0.9, 0.0, 1.0) if style == "hurry" or speed > 1.3 else 0.0
	var cyc := speed / maxf(0.05, lerpf(dw, dj, b))     # cycles per second, both clips in step
	tree.set("parameters/walk_ts/scale", cyc * lw)
	tree.set("parameters/jog_ts/scale", cyc * lj)
	tree.set("parameters/run/blend_amount", b)
	tree.set("parameters/move/blend_amount", _move_k)


# ------------------------------------------------------------------------------------ face


## the mouth moves through the vowels of a line for its duration
func talk(text: String, dur: float) -> void:
	_talk_text = text.to_lower()
	_talk_t = 0.0
	_talk_dur = clampf(dur * 0.8, 0.6, float(text.length()) / 9.0)


## a mood on the face for a while: joy | surprised | sorrow | eye_joy (^^)
func set_mood(name: String, amount := 1.0, hold := 2.0) -> void:
	for k in _mood_want:
		_mood_want[k] = 0.0
	if _mood_want.has(name):
		_mood_want[name] = amount
	_mood_hold = hold


func _face(o: Dictionary, dt: float) -> void:
	blink_t -= dt
	if blink_t < 0:
		blink = 1.0
		blink_t = randf_range(2.5, 6.0)
	blink = maxf(0.0, blink - dt * 9.0)
	_mood_hold -= dt
	if _mood_hold < 0:
		for k in _mood_want:
			_mood_want[k] = 0.0
	for k in _mood:
		_mood[k] = move_toward(_mood[k], _mood_want[k], dt * 3.0)
	# talking: A / I / O from the vowels, closed on consonants
	var want := {"mouth_a": 0.0, "mouth_i": 0.0, "mouth_o": 0.0}
	if _talk_t < _talk_dur and _talk_text != "":
		_talk_t += dt
		var ci := int(_talk_t / _talk_dur * _talk_text.length())
		var ch := _talk_text.substr(clampi(ci, 0, _talk_text.length() - 1), 1)
		if ch in ["a", "á", "ã", "â", "e", "é", "ê"]:
			want["mouth_a"] = 0.75 if ch.begins_with("a") or ch in ["á", "ã", "â"] else 0.45
		elif ch in ["i", "í"]:
			want["mouth_i"] = 0.6
		elif ch in ["o", "ó", "õ", "ô", "u", "ú"]:
			want["mouth_o"] = 0.65
	if _sleep_k > 0.01:
		want["mouth_a"] = maxf(want["mouth_a"], 0.18 * _sleep_k)
	for k in _mouth:
		_mouth[k] = move_toward(_mouth[k], want[k], dt * 14.0)
	var closed := 1.0 if asleep else blink
	closed = clampf(closed - eyes_wide * 0.35, -0.35, 1.0)
	if _mood["joy"] > 0.3 or _mood["eye_joy"] > 0.3:
		closed = minf(closed, 0.0)
	var vals := {"eyes_closed": closed, "joy": _mood["joy"], "surprised": maxf(_mood["surprised"], eyes_wide * 0.4), "sorrow": _mood["sorrow"], "eye_joy": _mood["eye_joy"]}
	vals.merge(_mouth)
	if not o.has("shapes"):
		var sh := []
		for mi in (o["root"] as Node).find_children("*", "MeshInstance3D", true, false):
			var mesh := mi as MeshInstance3D
			var d := {}
			for k in vals:
				var idx := mesh.find_blend_shape_by_name(k)
				if idx >= 0:
					d[k] = idx
			if not d.is_empty():
				sh.append([mesh, d])
		o["shapes"] = sh
	for pair in o["shapes"]:
		var mesh: MeshInstance3D = pair[0]
		var d: Dictionary = pair[1]
		for k in d:
			mesh.set_blend_shape_value(d[k], vals[k])


# ------------------------------------------------------------------------------------ per frame


func update(dt: float) -> void:
	if cur_outfit == "":
		return
	t += dt
	var o: Dictionary = outfits[cur_outfit]
	var d: Dictionary = POSES.get(pose, POSES["stand"])
	var mask: Array = _mask(pose)
	# each joint eases from where it was to the pose, after its own delay
	for j in JOINTS:
		var k := clampf((t - _pt0 - float(DELAY[j])) / _pdur, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		cur[j] = (_from[j] as Vector3).lerp(d[j], k)
		wj[j] = lerpf(_wfrom[j], 1.0 if j in mask else 0.0, k)
	var kh := clampf((t - _pt0) / _pdur, 0.0, 1.0)
	hips_y = lerpf(_hips_from, d["hips_y"], kh * kh * (3.0 - 2.0 * kh))
	# breathing: slow and deep asleep
	var sleeping := asleep and pose in ["lie", "lieSide"]
	_breath_amp = lerpf(_breath_amp, 0.03 if sleeping else 0.015, 1.0 - exp(-1.5 * dt))
	_breath_ph += dt * (1.05 if sleeping else 1.6)
	var breathe := sin(_breath_ph) * _breath_amp
	var tr := (randf() - 0.5) * 0.04 * tremble if tremble > 0 else 0.0
	var hyp := 1.0 if style == "hypno" else 0.0
	_sleep_k = lerpf(_sleep_k, 1.0 if sleeping else 0.0, 1.0 - exp(-1.2 * dt))
	# standing still the head never quite stops
	var still := clampf(1.0 - speed / 0.3, 0.0, 1.0) * (1.0 - _sleep_k) * (0.0 if pose in SLOW_POSES else 1.0)
	var nz := Vector3(sin(t * 0.37 + _noise_ph.x) + sin(t * 0.91 + _noise_ph.y) * 0.5, sin(t * 0.29 + _noise_ph.y) + sin(t * 0.73 + _noise_ph.z) * 0.5, sin(t * 0.43 + _noise_ph.z)) * 0.025 * still
	for j in JOINTS:
		_add[j] = Vector3.ZERO
	_add["spine"] = Vector3(breathe + hyp * 0.1 + tr, 0, 0)
	_add["chest"] = Vector3(breathe * 0.5, 0, 0)
	_add["neck"] = Vector3(hyp * 0.3, 0, hyp * 0.2) + nz * 0.5
	_add["head"] = Vector3(tr, sleep_side * 0.5 * _sleep_k, tr * 0.5) + nz
	# sleepwalking: arms held out in front, over the clip walk
	if hyp > 0.0 and has_clips:
		for j in ARMS:
			wj[j] = maxf(wj[j], 1.0)
		cur["shL"] = Vector3(-1.2, 0, 0.12)
		cur["shR"] = Vector3(-1.2, 0, -0.12)
		cur["elL"] = Vector3(-0.1, 0, 0)
		cur["elR"] = Vector3(-0.1, 0, 0)
	# carrying something: the arms go to it (and back when it is let go) in ~0.3 s
	var hk := holding()
	# reading standing up: the book comes up to the chest (sat, it rests low over the lap)
	if hk == "book_open" and _state not in SEATED:
		hk = "book_open_stand"
	var ha: Dictionary = hold_tune.get(hk, HOLD_ARMS.get(hk, {}))
	var ka2 := 1.0 - exp(-10.0 * dt)
	for j in ARMS + ["head"]:
		if not ha.has(j) and not _hold_cur.has(j):
			continue
		if ha.has(j):
			_hold_cur[j] = (_hold_cur.get(j, cur[j]) as Vector3).lerp(ha[j], ka2)
			_hold_w[j] = move_toward(_hold_w.get(j, 0.0), 1.0, dt * 4.0)
		else:
			_hold_w[j] = move_toward(_hold_w.get(j, 0.0), 0.0, dt * 4.0)
		var hw: float = _hold_w[j]
		hw = hw * hw * (3.0 - 2.0 * hw)
		cur[j] = (cur[j] as Vector3).lerp(_hold_cur[j], hw)
		wj[j] = lerpf(wj[j], 1.0, hw)
		if hw <= 0.0:
			_hold_cur.erase(j)
			_hold_w.erase(j)
	# procedural gestures
	if _gest != "":
		_gest_t += dt
		var gd: Dictionary = GESTURES[_gest]
		var glen: float = gd["len"]
		if _gest_t >= glen:
			_gest = ""
		else:
			var env := minf(clampf(_gest_t / 0.3, 0, 1), clampf((glen - _gest_t) / 0.35, 0, 1))
			env = env * env * (3.0 - 2.0 * env)
			var keys: Array = gd["keys"]
			var ka: Array = keys[0]
			var kb: Array = keys[0]
			for kk in keys:
				if float(kk[0]) <= _gest_t:
					ka = kk
					kb = kk
				else:
					kb = kk
					break
			var f := 0.0 if kb == ka else clampf((_gest_t - float(ka[0])) / (float(kb[0]) - float(ka[0])), 0, 1)
			var pa: Dictionary = ka[1]
			var pb: Dictionary = kb[1]
			for j in pa:
				var v: Vector3 = (pa[j] as Vector3).lerp(pb.get(j, pa[j]), f * f * (3.0 - 2.0 * f))
				cur[j] = (cur[j] as Vector3).lerp(v, env)
				wj[j] = maxf(wj[j], env)
	# a little life while standing around
	if pose == "stand" and speed < 0.05 and _gest == "" and not shot_playing() and not asleep:
		_idle_t += dt
		if _idle_t > randf_range(7.0, 16.0) and IDLE_GESTURES.has(who):
			gesture(IDLE_GESTURES[who][randi() % IDLE_GESTURES[who].size()])
	else:
		_idle_t = 0.0
	_beat = maxf(0.0, _beat - dt * 9.0)
	if pose == "knock" or pose == "window_press":
		var b := sin(_beat * PI) * 0.45
		cur["elR"] = (cur["elR"] as Vector3) + Vector3(b, 0, 0)
		if pose == "window_press":
			cur["elL"] = (cur["elL"] as Vector3) + Vector3(b * 0.5, 0, 0)
	# stalking (the Visitor in the yard): strides far too long, slow cadence, straight back, arms
	# pinned to the sides: the procedural walk over every joint
	if style == "stalk":
		for j in JOINTS:
			wj[j] = 1.0
		cur["shL"] = Vector3(0, 0, -0.02)
		cur["shR"] = Vector3(0, 0, 0.02)
		cur["elL"] = Vector3.ZERO
		cur["elR"] = Vector3.ZERO
	# on its back: the same diagonal pairs, the knees and elbows pumping hard
	if pose == "spider":
		gait += speed / 0.75 * TAU * dt
		var sp := sin(gait)
		cur["thL"] = (cur["thL"] as Vector3) + Vector3(sp * 0.4, 0, 0)
		cur["thR"] = (cur["thR"] as Vector3) + Vector3(-sp * 0.4, 0, 0)
		cur["knL"] = (cur["knL"] as Vector3) + Vector3(maxf(0.0, -sp) * 0.5, 0, 0)
		cur["knR"] = (cur["knR"] as Vector3) + Vector3(maxf(0.0, sp) * 0.5, 0, 0)
		cur["shL"] = (cur["shL"] as Vector3) + Vector3(-sp * 0.45, 0, 0)
		cur["shR"] = (cur["shR"] as Vector3) + Vector3(sp * 0.45, 0, 0)
		cur["elL"] = (cur["elL"] as Vector3) + Vector3(-maxf(0.0, sp) * 0.5, 0, 0)
		cur["elR"] = (cur["elR"] as Vector3) + Vector3(-maxf(0.0, -sp) * 0.5, 0, 0)
		cur["head"] = (cur["head"] as Vector3) + Vector3(0, sin(gait * 0.5) * 0.25, sin(gait * 1.7) * 0.15)
	# crawling: diagonal pairs of limbs step together
	if pose == "crawl":
		gait += speed / 0.55 * TAU * dt
		var sg := sin(gait)
		cur["thL"] = (cur["thL"] as Vector3) + Vector3(sg * 0.35, 0, 0)
		cur["thR"] = (cur["thR"] as Vector3) + Vector3(-sg * 0.35, 0, 0)
		cur["shL"] = (cur["shL"] as Vector3) + Vector3(-sg * 0.35, 0, 0)
		cur["shR"] = (cur["shR"] as Vector3) + Vector3(sg * 0.35, 0, 0)
		cur["head"] = (cur["head"] as Vector3) + Vector3(0, sin(gait * 0.5) * 0.15, 0)
	# old procedural walk for the rigs without clips (and the stalk)
	if not has_clips or style == "stalk":
		var stride := 2.3 if style == "stalk" else (1.25 if style == "hurry" else 0.95)
		gait += (speed / stride) * TAU * dt
	# the idle stands ~3-4 cm lower than the walk: switching on the frame the speed changes (a stop,
	# the end of a turn on the spot) made the hips jump, so the blend eases over ~0.25 s
	_move_k = lerpf(_move_k, clampf(speed / 0.35, 0.0, 1.0), 1.0 - exp(-9.0 * dt))
	if o.has("tree"):
		_drive_mixer(o)
	_face(o, dt)
	# feet onto the floor whenever the clips have the legs (standing, walking, seated, crouched)
	_feet_w = move_toward(_feet_w, 1.0 if ground_ik and has_clips and wj["thL"] < 0.3 and _state != null else 0.0, dt * 3.0)
	# the plain stance fades out as the walk blends in (same ramp as the mixer's move blend)
	var still_k := 1.0 - _move_k if _state == "loco" else 1.0
	var stance_on: bool = has_clips and _state in STANCE_STATES and wj["thL"] < 0.3 and not shot_playing()
	_stance_w = move_toward(_stance_w, still_k if stance_on else 0.0, dt * 4.0)
	_hand_w = move_toward(_hand_w, 1.0 if hand_target != null else 0.0, dt * 2.5)
	_hand_w_l = move_toward(_hand_w_l, 1.0 if hand_target_l != null else 0.0, dt * 2.5)
	_book_w = move_toward(_book_w, 1.0 if holding() == "book_open" else 0.0, dt * 2.5)
	_belly_w = move_toward(_belly_w, 1.0 if pose == "lie" else 0.0, dt * 1.5)


## after the hand IK: an open book held at its outer edges, each hand behind the cover with the fingers
## spread under it toward the spine, the thumb over the pages. The wrist turns so the palm faces the
## book (frames built from the hand's own finger bones, so any skeleton works)
func _post_modify(outfit: String, _dt: float) -> void:
	if _book_w <= 0.001 or not held.has("hand") or not is_instance_valid(held["hand"][0]):
		return
	var o: Dictionary = outfits[outfit]
	var sk: Skeleton3D = o["skel"]
	var idx: Dictionary = o["maps"]["idx"]
	var bk: Basis = (held["hand"][0] as Node3D).global_transform.basis.orthonormalized()
	var skb := sk.global_transform.basis.orthonormalized()
	var w := _book_w * _book_w * (3.0 - 2.0 * _book_w)
	for sd in ["r", "l"]:
		var hi: int = idx.get("hand_" + sd, -1)
		var mi := sk.find_bone("middle_01_" + sd)
		var ii := sk.find_bone("index_01_" + sd)
		var pi2 := sk.find_bone("pinky_01_" + sd)
		if hi < 0 or mi < 0 or ii < 0 or pi2 < 0:
			continue
		var hg := sk.get_bone_global_pose(hi)
		# the hand's frame in its own space: fingers, thumb side, palm normal
		var f_l := (hg.affine_inverse() * sk.get_bone_global_pose(mi).origin).normalized()
		var s_l := hg.affine_inverse() * sk.get_bone_global_pose(ii).origin - hg.affine_inverse() * sk.get_bone_global_pose(pi2).origin
		var n_l := f_l.cross(s_l).normalized() * (float(grip_tune.get("nr", 1.0)) if sd == "r" else float(grip_tune.get("nl", 1.0)))
		s_l = n_l.cross(f_l).normalized()
		# where they should point, in the skeleton's space: fingers in toward the spine and up the page,
		# the palm onto the back cover
		var inward := bk.x * (1.0 if sd == "r" else -1.0)
		var f_w: Vector3 = (inward * float(grip_tune.get("fin", 0.9)) + bk.z * float(grip_tune.get("fup", 0.3))).normalized()
		var n_w: Vector3 = bk.y
		n_w = (n_w - f_w * n_w.dot(f_w)).normalized()
		var f_s := skb.inverse() * f_w
		var n_s := skb.inverse() * n_w
		var want := Basis(n_s.cross(f_s).normalized(), f_s, n_s) * Basis(s_l, f_l, n_l).inverse()
		var hb := hg.basis.orthonormalized()
		var nb := Basis(hb.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), w))
		var pi3 := sk.get_bone_parent(hi)
		var pg := sk.get_bone_global_pose(pi3).basis.orthonormalized() if pi3 >= 0 else Basis.IDENTITY
		sk.set_bone_pose_rotation(hi, (pg.inverse() * nb).get_rotation_quaternion())
		# fingers: from straight, a gentle curl toward the palm (they lie flat under the cover)
		var curl: float = grip_tune.get("curl", 0.15)
		var tlift: float = grip_tune.get("tlift", 0.3)
		var tcurl: float = grip_tune.get("tcurl", 0.25)
		var hn := sk.get_bone_global_pose(hi).basis.orthonormalized()
		# the thumb rises from the palm's plane through the book, over the edge onto the page
		var t1 := sk.find_bone("thumb_01_" + sd)
		var t3 := sk.find_bone("thumb_03_" + sd)
		var t_ax := Vector3.ZERO
		if t1 >= 0 and t3 >= 0:
			var tdir := sk.get_bone_global_pose(t3).origin - sk.get_bone_global_pose(t1).origin
			t_ax = tdir.cross(hn * n_l).normalized()
		for fn in ["index", "middle", "ring", "pinky", "thumb"]:
			for seg in [1, 2, 3]:
				var bi := sk.find_bone("%s_0%d_%s" % [fn, seg, sd])
				if bi < 0:
					continue
				var par := sk.get_bone_global_pose(sk.get_bone_parent(bi)).basis.orthonormalized()
				var rest := sk.get_bone_rest(bi).basis.orthonormalized()
				# the curl axis: across the hand (global), so each joint folds toward the palm
				var ax_s: Vector3 = (hn * f_l).cross(hn * n_l).normalized()
				var a := curl * (0.7 if seg == 1 else 1.0)
				if fn == "thumb":
					ax_s = t_ax
					a = tlift if seg == 1 else tcurl
				var ax_l := (par.inverse() * ax_s).normalized()
				var q_rest := rest.get_rotation_quaternion()
				var q_new := Quaternion(ax_l, a) * q_rest
				sk.set_bone_pose_rotation(bi, sk.get_bone_pose_rotation(bi).slerp(q_new, w))


## called by HumanPoseMod on the active outfit's skeleton, after the clips
var _held_pose := {}


func _modify(outfit: String, dt: float) -> void:
	var o: Dictionary = outfits[outfit]
	# the Shadow's jerks: the pose holds, then snaps to where it should be ~10 times a second
	if jerky > 0.0:
		_jerk_t -= dt
		if _jerk_t > 0.0 and not _held_pose.is_empty():
			for j in JOINTS:
				cur[j] = _held_pose.get(j, cur[j])
		else:
			_jerk_t = 1.0 / jerky
			for j in JOINTS:
				_held_pose[j] = cur[j]
	else:
		_held_pose.clear()
	var sk: Skeleton3D = o["skel"]
	var m: Dictionary = o["maps"]
	var idx: Dictionary = m["idx"]
	var hang: Dictionary = m["hang"]
	var stalk := style == "stalk"
	var w := minf(1.0, speed / 0.5) if (not has_clips or stalk) else 0.0
	var g := gait
	var leg_a := (0.95 if stalk else 0.5) * w
	var arm_a := (0.0 if stalk else 0.35 - (0.3 if style == "hypno" else 0.0)) * w
	var gadd := {
		"hips": Vector3(0, sin(g) * 0.08 * w, sin(g) * 0.04 * w), "chest": Vector3(0, -sin(g) * 0.1 * w, 0),
		"thL": Vector3(sin(g) * leg_a, 0, 0), "thR": Vector3(-sin(g) * leg_a, 0, 0),
		"knL": Vector3(maxf(0.0, sin(g - 1.2)) * 0.9 * w, 0, 0), "knR": Vector3(maxf(0.0, -sin(g - 1.2)) * 0.9 * w, 0, 0),
		"shL": Vector3(-sin(g) * arm_a, 0, 0), "shR": Vector3(sin(g) * arm_a, 0, 0),
		"elL": Vector3(-maxf(0.0, sin(g)) * 0.3 * w, 0, 0), "elR": Vector3(-maxf(0.0, -sin(g)) * 0.3 * w, 0, 0),
	}
	for j in JOINTS:
		var i: int = idx.get(BONES[j], -1)
		if i < 0:
			continue
		var e: Vector3 = (cur[j] as Vector3) + (gadd.get(j, Vector3.ZERO) as Vector3)
		var wt: float = wj[j]
		var q := _e(e + _add[j])
		if j == "shL":
			q = q * (hang.get("l", Quaternion.IDENTITY) as Quaternion)
		elif j == "shR":
			q = q * (hang.get("r", Quaternion.IDENTITY) as Quaternion)
		elif j == "elL":
			q = q * (m.get("straight_l", Quaternion.IDENTITY) as Quaternion)
		elif j == "elR":
			q = q * (m.get("straight_r", Quaternion.IDENTITY) as Quaternion)
		var qp := _proc_local(m, i, q)
		if (j == "shL" or j == "shR") and has_clips and wt > 0.001:
			# the arm's pose is meant against the chest: the clips move the clavicles (shrugs, a seated
			# lean) and would carry a rest-relative arm off sideways
			var ci: int = idx.get("spine_03", -1)
			var par := sk.get_bone_parent(i)
			if ci >= 0 and par >= 0:
				var chest_g := sk.get_bone_global_pose(ci).basis.orthonormalized()
				var want := chest_g * (m["g"][ci] as Basis).inverse() * Basis(q) * (m["g"][i] as Basis)
				qp = (sk.get_bone_global_pose(par).basis.orthonormalized().inverse() * want).get_rotation_quaternion()
		if wt >= 0.999 or not has_clips or stalk:
			sk.set_bone_pose_rotation(i, qp)
		else:
			var qm := sk.get_bone_pose_rotation(i)
			if wt > 0.001:
				qm = qm.slerp(qp, wt)
			# the additive layers still ride on the clip
			if (_add[j] as Vector3).length_squared() > 1e-8:
				qm = qm * Quaternion((m["g"][i] as Basis).inverse() * Basis(_e(_add[j] * (1.0 - wt))) * (m["g"][i] as Basis))
			sk.set_bone_pose_rotation(i, qm)
	# feet stay roughly flat in the procedural poses: counter the knee and hip
	for sd in ["L", "R"]:
		var fi: int = idx.get("foot_" + sd.to_lower(), -1)
		if fi < 0:
			continue
		var th: Vector3 = cur["th" + sd]
		var kn: Vector3 = cur["kn" + sd]
		var gk := maxf(0.0, (1.0 if sd == "L" else -1.0) * sin(g - 1.2)) * 0.3 * w
		var qf := _proc_local(m, fi, _e(Vector3(-(th.x + kn.x) * 0.35 - gk, 0, 0)))
		var wf: float = wj["kn" + sd]
		sk.set_bone_pose_rotation(fi, qf if wf >= 0.999 or not has_clips else sk.get_bone_pose_rotation(fi).slerp(qf, wf))
	# pelvis: the procedural drop, or the clip's with the seat height corrected
	var pi: int = idx.get("pelvis", -1)
	if pi >= 0:
		var pb: Basis = m["pg"][pi]
		var rest_p: Vector3 = m["rest_pos"][pi]
		var drop := hips_y - pelvis_d * clampf(-hips_y / 0.3, 0.0, 1.0)
		var bob := absf(sin(g)) * 0.03 * w
		var pp := rest_p + pb.inverse() * Vector3(0, drop - bob, 0)
		var pm := sk.get_bone_pose_position(pi) if has_clips else pp
		if has_clips and (_state in SEATED or _shot in ["sit_down", "stand_up"]):
			# the library's chair is lower and further back than our seats: move the seated pelvis
			# to where the procedural sit puts it, in proportion to how far down the clip is
			var sp: Vector3 = o.get("sit_pel", Vector3.ZERO)
			if sp.y < -0.05:
				var down := (pb * (pm - rest_p)).y
				var f := clampf(down / sp.y, 0.0, 1.0)
				# the seated pelvis height comes from the seat alone (the MPFB references differ per person)
				var want_drop: float = SEAT_PELVIS + seat_lift - (pelvis_d + ref_pelvis)
				# placed right on the seat (snap): the hips go over the feet; walked up: the clip's way back
				var back := -seat_deep if seat_back else 1.0
				pm += pb.inverse() * Vector3(-sp.x * back, want_drop - sp.y, -sp.z * back) * f
		sk.set_bone_pose_position(pi, pm.lerp(pp, wj["hips"]))
	_plain_stance(sk, m)
	_look(o, sk, m, dt)
	_ik_targets(o, sk, m)
	_update_glasses()
	if not held.is_empty():
		_place_held(sk, m["idx"])
	_mods += 1
	if turban and turban.visible and _final.size() > 0:
		_update_turban(sk, m["idx"])
	var n := sk.get_bone_count()
	if _final.size() != n:
		_final.resize(n)
	for i in n:
		_final[i] = sk.get_bone_global_pose(i)


## standing still: the legs and hips of the clip go back to the rest (feet under the hips, side by
## side) and the pelvis over them; the clip keeps the spine, arms and head (breathing, sway). The
## clips also carry the shoulders high: in the standing / walking clips the clavicles drop halfway.
func _plain_stance(sk: Skeleton3D, m: Dictionary) -> void:
	if not LOOKS.get(who, {}).get("anime", false):
		return
	var idx: Dictionary = m["idx"]
	var w := _stance_w
	if w > 0.001:
		for bn in STANCE_BONES:
			var i: int = idx.get(bn, -1)
			if i < 0:
				continue
			var want: Quaternion = m["rest_rot"][i]
			if bn.begins_with("thigh_"):
				# the clip tips the pelvis back and the trunk forward over it: keep its pelvis (the trunk
				# stays upright) and hang the thighs straight down in the body's frame instead
				var par := sk.get_bone_parent(i)
				want = (sk.get_bone_global_pose(par).basis.orthonormalized().inverse() * (m["g"][i] as Basis)).get_rotation_quaternion()
			sk.set_bone_pose_rotation(i, sk.get_bone_pose_rotation(i).slerp(want, w))
		var pi: int = idx.get("pelvis", -1)
		if pi >= 0:
			var pb: Basis = m["pg"][pi]
			var rest_p: Vector3 = m["rest_pos"][pi]
			var d := pb * (sk.get_bone_pose_position(pi) - rest_p)
			d = Vector3(d.x * (1.0 - w), d.y, d.z * (1.0 - w))
			sk.set_bone_pose_position(pi, rest_p + pb.inverse() * d)
	if _state == "loco" and wj["shL"] < 0.3 and wj["shR"] < 0.3:
		for bn in ["clavicle_l", "clavicle_r"]:
			var ci: int = idx.get(bn, -1)
			if ci >= 0:
				sk.set_bone_pose_rotation(ci, sk.get_bone_pose_rotation(ci).slerp(m["rest_rot"][ci], 0.5))


## a bone's skeleton-space pose as the modifiers left it (the procedural poses included)
func bone_global(i: int) -> Transform3D:
	var sk: Skeleton3D = outfits[cur_outfit]["skel"]
	if i >= 0 and i < _final.size():
		return _final[i]
	return sk.get_bone_global_pose(i)


## the look chain: one damped spring on the rotation from the face to the target, shared by the
## chest, neck and head, with the eyes taking what is left (up to ~20 degrees)
func _look(o: Dictionary, sk: Skeleton3D, m: Dictionary, dt: float) -> void:
	var idx: Dictionary = m["idx"]
	var hi: int = idx.get("head", -1)
	if hi < 0:
		return
	var want := Vector3.ZERO
	var to_t := Vector3.ZERO
	var hg := sk.get_bone_global_pose(hi)
	var fwd := (hg.basis * ((m["g"][hi] as Basis).inverse() * Vector3(0, 0, 1))).normalized()
	look_yaw = 0.0
	# walking, the head keeps to the way: a glance aside turns it less and never bends the back
	var wk := clampf((speed - 0.2) / 0.5, 0.0, 1.0) if pose == "stand" else 0.0
	if look_target != null:
		to_t = sk.global_transform.affine_inverse() * (look_target as Vector3) - hg.origin
		if to_t.length() > 0.15:
			# people look down with the eyes more than the neck: keep the head between -35 and +30 degrees
			var hz := Vector2(to_t.x, to_t.z).length()
			var lying := pose in SLOW_POSES and pose != "kneel" and pose != "pet"
			if hz > 0.05 and not lying:
				var el := clampf(atan2(to_t.y, hz), deg_to_rad(lerpf(-35, -15, wk)), deg_to_rad(lerpf(30, 15, wk)))
				to_t = Vector3(to_t.x / hz * cos(el), sin(el), to_t.z / hz * cos(el))
			to_t = to_t.normalized()
			var ang := fwd.angle_to(to_t)
			var axis := fwd.cross(to_t)
			var lim := deg_to_rad(lerpf(80, 50, wk))
			if axis.length() > 1e-4:
				want = axis.normalized() * minf(ang, lim)
			# outside the neck's reach: the body has to turn (signed, around the model's up)
			var fy := Vector2(fwd.x, fwd.z)
			var ty := Vector2(to_t.x, to_t.z)
			if fy.length() > 0.2 and ty.length() > 0.2:
				# Vector2.angle_to on (x, z) turns the other way round from the yaw (+z toward +x)
				var yaw := -fy.angle_to(ty)
				look_yaw = signf(yaw) * maxf(0.0, absf(yaw) - deg_to_rad(65))
	var k := 45.0
	_look_vel += ((want - _look_v) * k - _look_vel * 2.0 * sqrt(k)) * dt
	_look_v += _look_vel * dt
	var amt := _look_v.length()
	if amt < 1e-4:
		return
	var axis2 := _look_v / amt
	var lying := pose in SLOW_POSES and pose != "kneel" and pose != "pet"
	var chain := [["neck_01", 0.4], ["head", 0.6]] if lying else [["spine_03", 0.15 * (1.0 - wk)], ["neck_01", 0.3 + 0.1 * wk], ["head", 0.55 + 0.05 * wk]]
	for pair in chain:
		var bi: int = idx.get(pair[0], -1)
		if bi < 0:
			continue
		var part := Quaternion(axis2, amt * float(pair[1]))
		var par := sk.get_bone_parent(bi)
		var pg := sk.get_bone_global_pose(par) if par >= 0 else Transform3D.IDENTITY
		var bg := sk.get_bone_global_pose(bi)
		sk.set_bone_pose_rotation(bi, (pg.basis.orthonormalized().inverse() * (Basis(part) * bg.basis.orthonormalized())).get_rotation_quaternion())
	# eyes: the rest of the way
	if look_target != null and to_t != Vector3.ZERO:
		var hg2 := sk.get_bone_global_pose(hi)
		var fwd2 := (hg2.basis * ((m["g"][hi] as Basis).inverse() * Vector3(0, 0, 1))).normalized()
		var res := fwd2.angle_to(to_t)
		var ax := fwd2.cross(to_t)
		if ax.length() > 1e-4 and res > 0.01:
			var qe := Quaternion(ax.normalized(), minf(res, 0.35) * 0.8)
			for en in ["J_Adj_L_FaceEye", "J_Adj_R_FaceEye"]:
				var ei: int = idx.get(en, -1)
				if ei < 0:
					continue
				var epar := sk.get_bone_parent(ei)
				var epg := sk.get_bone_global_pose(epar)
				var eg := sk.get_bone_global_pose(ei)
				sk.set_bone_pose_rotation(ei, (epg.basis.orthonormalized().inverse() * (Basis(qe) * eg.basis.orthonormalized())).get_rotation_quaternion())


## IK targets: each foot onto the ground right under it (steps), the pelvis lowered for the lower one;
## the hands onto hand_target / hand_target_l
func _ik_targets(o: Dictionary, sk: Skeleton3D, m: Dictionary) -> void:
	var tg: Dictionary = o["ik_t"]
	var idx: Dictionary = m["idx"]
	var fwd := global_transform.basis.z.normalized()
	var feet: TwoBoneIK3D = o["ik_feet"]
	feet.influence = _feet_w
	if _feet_w > 0.001 and is_inside_tree():
		var space := get_world_3d().direct_space_state
		var offs := {}
		var low := 0.0
		for sd in ["l", "r"]:
			var fp := sk.global_transform * sk.get_bone_global_pose(idx["foot_" + sd]).origin
			var q := PhysicsRayQueryParameters3D.create(fp + Vector3(0, 0.45, 0), fp - Vector3(0, 0.5, 0), HouseBuilder.LAYER_WORLD)
			var hit := space.intersect_ray(q)
			var off := 0.0
			if hit:
				off = float(hit["position"].y) - global_position.y
				# a step is under ~0.22 m: anything higher is furniture (the sofa seat), not floor
				if absf(off) > 0.25:
					off = 0.0
			offs[sd] = [fp, off]
			low = minf(low, off)
		# standing / walking: lower the hips for the foot that has to reach down (seated they stay put)
		if _state == "loco" and not shot_playing():
			var pi: int = idx["pelvis"]
			var pb: Basis = m["pg"][pi]
			sk.set_bone_pose_position(pi, sk.get_bone_pose_position(pi) + pb.inverse() * (global_transform.basis.inverse() * Vector3(0, low, 0)))
		for sd in ["l", "r"]:
			var fp2: Vector3 = offs[sd][0]
			(tg["foot_" + sd] as Node3D).global_position = fp2 + Vector3(0, offs[sd][1], 0)
			var kp := sk.global_transform * sk.get_bone_global_pose(idx["calf_" + sd]).origin
			(tg["knee_" + sd] as Node3D).global_position = kp + fwd * 0.6
	for sd in ["r", "l"]:
		var ik: TwoBoneIK3D = o["ik_hand_" + sd]
		var tgt = hand_target if sd == "r" else hand_target_l
		var wv := _hand_w if sd == "r" else _hand_w_l
		var side := global_transform.basis.x.normalized() * (-1.0 if sd == "r" else 1.0)
		var belly := tgt == null and _belly_w > 0.001
		# an open book: each hand on the middle of its outer edge (the elbows go out, not into the body)
		if tgt == null and _book_w > 0.001 and held.has("hand") and is_instance_valid(held["hand"][0]):
			var gx: float = grip_tune.get("wx", 0.19)
			tgt = (held["hand"][0] as Node3D).global_transform * Vector3(-gx if sd == "r" else gx, grip_tune.get("wy", -0.045), grip_tune.get("wz", 0.0))
			wv = _book_w
		if belly:
			# arm stretched out along the body, the whole arm lying on the sheet: the hand at almost full
			# reach toward the feet (a little out from the hip) and at the height of the mattress top
			var gp := func(b: String) -> Vector3: return sk.global_transform * sk.get_bone_global_pose(idx[b]).origin
			var sh: Vector3 = gp.call("upperarm_" + sd)
			var reach: float = (sh.distance_to(gp.call("lowerarm_" + sd)) + (gp.call("lowerarm_" + sd) as Vector3).distance_to(gp.call("hand_" + sd))) * 0.97
			var down: Vector3 = gp.call("pelvis") - gp.call("spine_02")
			down.y = 0.0
			var dir := (down.normalized() * cos(0.2) + Vector3(side.x, 0, side.z).normalized() * sin(0.2)).normalized()
			# the mattress top is where her back lies: ~0.1 under the pelvis bone; the wrist sits on it
			# (the bed's collider is the frame, not the mattress, so no ray)
			var hy: float = (gp.call("pelvis") as Vector3).y - 0.03
			var dy := clampf(sh.y - hy, 0.0, reach * 0.9)
			tgt = sh + dir * sqrt(reach * reach - dy * dy)
			tgt.y = hy
			wv = _belly_w
		ik.influence = wv
		if tgt != null:
			(tg["hand_" + sd] as Node3D).global_position = tgt
			var ep := sk.global_transform * sk.get_bone_global_pose(idx["lowerarm_" + sd]).origin
			# lying: the (barely bent) elbow points out and up, never down into the mattress
			var pole := side * 0.4 + Vector3(0, 0.15, 0) if belly else side * 0.4 - Vector3(0, 0.3, 0)
			(tg["elbow_" + sd] as Node3D).global_position = ep + pole
