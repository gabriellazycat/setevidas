class_name HumanPoseMod
extends SkeletonModifier3D
## Runs after the clip mixer (AnimationTree) on one outfit's skeleton and hands the bones to
## HumanRig._modify: procedural poses blended over the clips per joint, breathing / sleep / tremble,
## the look chain and the foot IK targets. The IK and spring-bone modifiers come after it.
## With post = true it runs after the hand IK instead (HumanRig._post_modify: the hands' grip).

var rig: HumanRig
var outfit := ""
var post := false


func _process_modification_with_delta(delta: float) -> void:
	if rig != null and rig.cur_outfit == outfit:
		if post:
			rig._post_modify(outfit, delta)
		else:
			rig._modify(outfit, delta)
