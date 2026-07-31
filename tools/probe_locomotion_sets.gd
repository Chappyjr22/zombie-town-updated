extends SceneTree
## Measures every clip a locomotion set maps to, so a set can be checked before
## it's played.
##
##   godot --path . --script tools/probe_locomotion_sets.gd
##
## Run WITHOUT --headless: the animation mixer only writes bone poses on a real
## process frame.
##
## Three numbers per direction, averaged over the clip:
##
## - **hands**: how high the hands are carried above the hips. A weapon held ready
##   sits around +0.4m; arms hanging at the sides read near zero. This is the
##   number that caught the model's stock strafes dropping the rifle to the waist.
## - **fwd**: how squarely the grip-hand-to-support-hand line points down the
##   character's facing. Meaningful for a two-handed set only - for a handgun the
##   off hand isn't on the weapon, so it's noise.
## - **drift**: how far the hips travel over the clip. Should be near zero;
##   anything larger means build_clips.gd failed to strip the root motion and the
##   character will surge and snap back on every loop.

const MODEL_PATH := "res://assets/models/characters/mixamo_soldier.glb"
const SAMPLES := 8


func _initialize() -> void:
	_run()


func _run() -> void:
	var model := (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var skeleton := _find_first(model, "Skeleton3D") as Skeleton3D
	var animation_player := _find_first(model, "AnimationPlayer") as AnimationPlayer
	var library := animation_player.get_animation_library(&"")

	for set_name in [&"rifle", &"pistol"]:
		var paths := LocomotionSets.clip_paths(set_name)
		for installed in paths:
			if ResourceLoader.exists(paths[installed]):
				library.add_animation(installed, load(paths[installed]))

		var definition := LocomotionSets.get_set(set_name)
		print("\n=== %s ===" % set_name)
		print("%-28s %-26s %8s %6s %7s" % ["slot", "clip", "hands", "fwd", "drift"])
		for key in ["idle", "crouch_idle", "jump_loop"]:
			await _report(
				animation_player, skeleton, set_name, String(key), definition[key]
			)
		for tier in LocomotionSets.TIERS:
			for direction in LocomotionSets.DIRECTIONS:
				await _report(
					animation_player,
					skeleton,
					set_name,
					"%s / %s" % [tier, direction],
					definition[tier][direction]
				)
	quit()


func _report(
	animation_player: AnimationPlayer,
	skeleton: Skeleton3D,
	set_name: StringName,
	slot: String,
	clip: StringName
) -> void:
	var installed := LocomotionSets.installed_name(set_name, clip)
	if not animation_player.has_animation(installed):
		print("%-28s %-26s  MISSING" % [slot, clip])
		return
	var length := animation_player.get_animation(installed).length
	var height_total := 0.0
	var forward_total := 0.0
	var hips_min := Vector3(INF, INF, INF)
	var hips_max := Vector3(-INF, -INF, -INF)
	for sample in SAMPLES:
		animation_player.play(installed)
		animation_player.seek(length * float(sample) / float(SAMPLES), true)
		await process_frame
		await process_frame
		skeleton.force_update_all_bone_transforms()
		var hips := _bone(skeleton, "mixamorig_Hips")
		var grip := _bone(skeleton, "mixamorig_RightHand")
		var support := _bone(skeleton, "mixamorig_LeftHand")
		height_total += (grip.y + support.y) * 0.5 - hips.y
		# The model faces +Z in its own space.
		forward_total += (support - grip).normalized().z
		hips_min = hips_min.min(hips)
		hips_max = hips_max.max(hips)
	var drift := Vector2(hips_max.x - hips_min.x, hips_max.z - hips_min.z).length()
	print("%-28s %-26s %+7.3fm %+6.2f %6.3fm" % [
		slot,
		clip,
		height_total / float(SAMPLES),
		forward_total / float(SAMPLES),
		drift,
	])


func _bone(skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var index := skeleton.find_bone(bone_name)
	if index < 0:
		return Vector3.ZERO
	return skeleton.get_bone_global_pose(index).origin


func _find_first(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var result := _find_first(child, type_name)
		if result:
			return result
	return null
