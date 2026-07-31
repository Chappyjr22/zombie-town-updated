extends SceneTree
## Checks every locomotion set's table against what's actually on disk.
##
##   godot --headless --path . --script tools/verify_locomotion_sets.gd
##
## The set tables in scripts/player/locomotion_sets.gd name clips by hand, and a
## typo there doesn't fail loudly - the character just freezes in whichever
## direction the missing clip covered. Exits non-zero if anything is wrong.

const CHECKED_SETS: Array[StringName] = [&"rifle", &"pistol"]


func _initialize() -> void:
	var failures := 0
	for set_name in CHECKED_SETS:
		var definition := LocomotionSets.get_set(set_name)
		for tier in LocomotionSets.TIERS:
			if not definition.has(tier):
				print("MISSING TIER  %s / %s" % [set_name, tier])
				failures += 1
				continue
			for direction in LocomotionSets.DIRECTIONS:
				if not definition[tier].has(direction):
					print("MISSING       %s / %s / %s" % [set_name, tier, direction])
					failures += 1
		for key in ["idle", "crouch_idle", "jump_up", "jump_loop", "jump_down"]:
			if not definition.has(key):
				print("MISSING KEY   %s / %s" % [set_name, key])
				failures += 1

		var paths := LocomotionSets.clip_paths(set_name)
		for installed in paths:
			if not ResourceLoader.exists(paths[installed]):
				print("NO SUCH FILE  %s -> %s" % [installed, paths[installed]])
				failures += 1
		print("%-8s %d clips, %d distinct files" % [set_name, paths.size(), paths.size()])

	print("%d problems" % failures)
	quit(1 if failures > 0 else 0)
