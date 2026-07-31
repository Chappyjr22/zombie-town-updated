extends SceneTree
## Scores every clip on the player model for whether it holds a weapon up.
##
##   godot --path . --script tools/probe_body_clips.gd
##
## Run WITHOUT --headless: the animation mixer only writes bone poses on a real
## process frame.
##
## Two numbers per clip, both averaged over the clip:
##
## - **hands above hips**: how high the hands are carried. A weapon held ready
##   sits around chest height; arms hanging at the sides read near zero or below.
## - **forward**: how squarely the grip-hand-to-support-hand line points down the
##   character's facing. 1.0 is a weapon aimed ahead, 0.0 is carried across the
##   chest, negative is pointing behind.
##
## A clip needs both to be usable for a shooter. High hands with low forward is a
## patrol carry; low hands is arms-down and wrong however it's pointed.

## This scores the clips baked into the model itself. For the clips the game
## actually plays - the locomotion packs, grouped by which direction each one
## covers - use tools/probe_locomotion_sets.gd instead.
const MODEL_PATH := "res://assets/models/characters/mixamo_soldier.glb"
const SAMPLES := 8


func _initialize() -> void:
	_run()


func _run() -> void:
	var model := (load(MODEL_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	var skeleton := _find_first(model, "Skeleton3D") as Skeleton3D
	var animation_player := _find_first(model, "AnimationPlayer") as AnimationPlayer

	print("clip                    hands above hips   forward")
	for clip_name in animation_player.get_animation_list():
		var length := animation_player.get_animation(clip_name).length
		var height_total := 0.0
		var forward_total := 0.0
		for sample in SAMPLES:
			animation_player.play(clip_name)
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
		print("%-22s  %+6.3f m           %+.2f" % [
			clip_name,
			height_total / float(SAMPLES),
			forward_total / float(SAMPLES),
		])
	quit()


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
