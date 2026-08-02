class_name LocomotionSets
extends RefCounted

## Which body animations a weapon is carried with, and what each pack calls them.
##
## A weapon names its set through `WeaponData.locomotion_set`, so drawing a pistol
## puts the character into a pistol stance rather than leaving them holding a
## handgun like a rifle.
##
## The mapping is explicit per set rather than a shared naming convention, because
## the packs genuinely differ: the rifle pack ships a clip for all eight
## directions at three speeds, while the pistol pack has no sprint and no
## crouch-walk at all, and calls its diagonals "arcs". Pretending otherwise would
## mean silently loading clips that don't exist.
##
## Directions are named from the character's point of view. The model faces +Z, so
## its left is +X - which is how each pack's clips were identified: by measuring
## which way the hips actually travel. See tools/build_clips.gd.

## Blend-square position for each direction. Diagonals sit on the unit circle
## rather than the corners, so holding two keys moves the blend the same distance
## from centre as holding one.
const DIRECTIONS := {
	&"forward": Vector2(0.0, -1.0),
	&"forward_left": Vector2(-0.707, -0.707),
	&"forward_right": Vector2(0.707, -0.707),
	&"left": Vector2(-1.0, 0.0),
	&"right": Vector2(1.0, 0.0),
	&"backward": Vector2(0.0, 1.0),
	&"backward_left": Vector2(-0.707, 0.707),
	&"backward_right": Vector2(0.707, 0.707),
}

## Speed tiers the animation tree blends between. "normal" is the default gait,
## which is a jog rather than a walk - the player moves at 4.5 m/s.
const TIERS: Array[StringName] = [&"normal", &"sprint", &"crouch"]

## Optional per-set key for the one-shot played when a weapon from that set is
## drawn (see player.gd's _on_weapon_changed). Deliberately left out of
## clip_paths()'s hard requirements - a set with no draw clip on disk yet just
## keeps the instant swap it has today; _install_extra_clips() already skips
## missing files rather than failing, so this needs no fallback logic of its
## own beyond that.
const SETS := {
	&"rifle": {
		"dir": "res://assets/animations/rifle",
		"draw": &"draw",
		"holster": &"holster",
		## Not the 8-way pack's own `idle_aiming`, which is also on disk. This one
		## is a separate Mixamo download that carries the weapon 6.8cm higher with
		## the hands 5.8cm further apart - a braced hold rather than a relaxed one.
		##
		## The pack's idle is not better integrated despite coming from the pack:
		## measured against the average pose of the eight normal-tier clips it has
		## to crossfade with, the two sit 0.293m and 0.317m away respectively, and
		## 2.4cm is nothing across a ~0.1s blend. Swap the name here to compare.
		"idle": &"idle_aiming_braced",
		"crouch_idle": &"idle_crouching_aiming",
		"jump_up": &"jump_up",
		"jump_loop": &"jump_loop",
		"jump_down": &"jump_down",
		"normal": {
			&"forward": &"run_forward",
			&"forward_left": &"run_forward_left",
			&"forward_right": &"run_forward_right",
			&"left": &"run_left",
			&"right": &"run_right",
			&"backward": &"run_backward",
			&"backward_left": &"run_backward_left",
			&"backward_right": &"run_backward_right",
		},
		"sprint": {
			&"forward": &"sprint_forward",
			&"forward_left": &"sprint_forward_left",
			&"forward_right": &"sprint_forward_right",
			&"left": &"sprint_left",
			&"right": &"sprint_right",
			&"backward": &"sprint_backward",
			&"backward_left": &"sprint_backward_left",
			&"backward_right": &"sprint_backward_right",
		},
		"crouch": {
			&"forward": &"walk_crouching_forward",
			&"forward_left": &"walk_crouching_forward_left",
			&"forward_right": &"walk_crouching_forward_right",
			&"left": &"walk_crouching_left",
			&"right": &"walk_crouching_right",
			&"backward": &"walk_crouching_backward",
			&"backward_left": &"walk_crouching_backward_left",
			&"backward_right": &"walk_crouching_backward_right",
		},
	},
	## The pistol pack covers less ground than the rifle one, so two things are
	## deliberately reused rather than left missing:
	##
	## - **Crouch repeats the walk set**, so the character keeps a pistol stance
	##   while the capsule shrinks, but doesn't visually crouch. There is no
	##   pistol crouch-walk; `kneeling_idle` is a kneel, not a gait.
	## - **The strafes are shared across tiers.** There is one pair, not one per
	##   speed.
	##
	## "Arc" clips are curving runs, which is what stands in for the diagonals -
	## `walk_arc` drifts x -0.397 (the character's right) and `walk_arc_2` +0.479
	## (their left), which is how each was identified.
	##
	## **Sprint is one clip (forward only) reused across all eight directions**,
	## not eight distinct captures the way the rifle pack has - only one was
	## pulled. Still counts as "distinct" from normal (has_distinct_sprint()
	## just compares the two dictionaries), so it gets the real sprint-blend
	## crossfade instead of the timescale-speedup fallback; strafing/backing up
	## while sprinting will look like the forward clip played sideways until
	## real per-direction captures replace it.
	&"pistol": {
		"dir": "res://assets/animations/pistol",
		"draw": &"draw",
		"idle": &"idle",
		"crouch_idle": &"kneeling_idle",
		"jump_up": &"jump",
		"jump_loop": &"jump_2",
		"jump_down": &"jump",
		"normal": {
			&"forward": &"run",
			&"forward_left": &"run_arc_2",
			&"forward_right": &"run_arc",
			&"left": &"strafe",
			&"right": &"strafe_2",
			&"backward": &"run_backward",
			&"backward_left": &"run_backward_arc",
			&"backward_right": &"run_backward_arc_2",
		},
		"sprint": {
			&"forward": &"sprint",
			&"forward_left": &"sprint",
			&"forward_right": &"sprint",
			&"left": &"sprint",
			&"right": &"sprint",
			&"backward": &"sprint",
			&"backward_left": &"sprint",
			&"backward_right": &"sprint",
		},
		"crouch": {
			&"forward": &"walk",
			&"forward_left": &"walk_arc_2",
			&"forward_right": &"walk_arc",
			&"left": &"strafe",
			&"right": &"strafe_2",
			&"backward": &"walk_backward",
			&"backward_left": &"walk_backward_arc",
			&"backward_right": &"walk_backward_arc_2",
		},
	},
}


## Falls back to the rifle set for an unknown name, so a weapon with a typo in its
## `locomotion_set` still animates rather than freezing in a T-pose.
static func get_set(set_name: StringName) -> Dictionary:
	if SETS.has(set_name):
		return SETS[set_name]
	push_warning("Unknown locomotion set '%s'; using rifle." % set_name)
	return SETS[&"rifle"]


## Every animation this set needs, as `res://` paths keyed by the name the clip is
## installed under. Names are namespaced by set so both can be loaded at once and
## swapped without reloading anything.
static func clip_paths(set_name: StringName) -> Dictionary:
	var definition := get_set(set_name)
	var paths := {}
	for key in ["idle", "crouch_idle", "jump_up", "jump_loop", "jump_down"]:
		paths[installed_name(set_name, definition[key])] = (
			"%s/%s.res" % [definition.dir, definition[key]]
		)
	for tier in TIERS:
		for direction in DIRECTIONS:
			var clip: StringName = definition[tier][direction]
			paths[installed_name(set_name, clip)] = "%s/%s.res" % [definition.dir, clip]
	return paths


## Both packs contain a clip called "idle", so the set name has to be part of the
## installed name or one would overwrite the other.
static func installed_name(set_name: StringName, clip: StringName) -> StringName:
	return StringName("%s_%s" % [set_name, clip])


## The draw clip's own path, or "" if this set defines none yet. Kept separate
## from clip_paths() on purpose: that dictionary feeds _has_locomotion_clips()'s
## all-or-nothing check, and a missing draw clip should cost a weapon its draw
## animation, not the entire locomotion tree.
static func draw_clip_path(set_name: StringName) -> String:
	var definition := get_set(set_name)
	if not definition.has("draw"):
		return ""
	return "%s/%s.res" % [definition.dir, definition["draw"]]


static func draw_clip_installed_name(set_name: StringName) -> StringName:
	var definition := get_set(set_name)
	if not definition.has("draw"):
		return &""
	return installed_name(set_name, definition["draw"])


## Same shape as draw_clip_path/draw_clip_installed_name above, for the
## one-shot played on the *outgoing* weapon before a switch - see
## WeaponController.equip_slot() and Player.play_holster_animation().
static func holster_clip_path(set_name: StringName) -> String:
	var definition := get_set(set_name)
	if not definition.has("holster"):
		return ""
	return "%s/%s.res" % [definition.dir, definition["holster"]]


static func holster_clip_installed_name(set_name: StringName) -> StringName:
	var definition := get_set(set_name)
	if not definition.has("holster"):
		return &""
	return installed_name(set_name, definition["holster"])


## Whether the set's sprint tier is actually its own clips rather than a repeat of
## the normal ones.
##
## It matters because the blend squares run independently, so crossfading a tier
## into a copy of itself blends the clip against a phase-shifted version of
## itself - the legs mush together for the length of the transition. A set without
## a real sprint is better off staying on the normal tier and just running its
## stride faster.
static func has_distinct_sprint(set_name: StringName) -> bool:
	var definition := get_set(set_name)
	return definition["sprint"] != definition["normal"]
