class_name Config
extends RefCounted
## Balance of the seven nights. Port of Config.ts.

const LAST_NIGHT := 7
## the day Davi moves in (afternoon)
const DAVI_DAY := 4
## the hound hunts the cat from this night on
const HOUND_FROM := 2

## which ghosts walk on each night (the hound is the cat's own enemy and is handled separately)
const NIGHT_THREATS := {
	1: ["shadow"],
	2: ["shadow", "whisperer"],
	3: ["shadow", "whisperer", "drowner"],
	4: ["shadow", "whisperer", "drowner", "doll"],
	5: ["shadow", "whisperer", "drowner", "doll", "visitor"],
	6: ["shadow", "whisperer", "drowner", "doll", "visitor"],
	7: ["shadow", "whisperer", "drowner", "doll", "visitor", "thing"],
}

## the threat that is new on each night
const NEW_ON_NIGHT := {1: "shadow", 2: "whisperer", 3: "drowner", 4: "doll", 5: "visitor", 6: null, 7: "thing"}

const NIGHT_LENGTH_MIN := {1: 6.0, 2: 7.5, 3: 8.5, 4: 9.5, 5: 10.5, 6: 11.0, 7: 12.0}
const NIGHT_SPEED := {1: 0.78, 2: 0.86, 3: 0.94, 4: 1.0, 5: 1.05, 6: 1.12, 7: 1.1}


## is this ghost (or the hound) the new one on that night? Its "como vencer" card stays up all night.
static func is_new_on(id: String, n: int) -> bool:
	return NEW_ON_NIGHT.get(n) == id or (id == "hound" and n == HOUND_FROM)
