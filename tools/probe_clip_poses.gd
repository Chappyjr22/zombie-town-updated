extends SceneTree
## Scores staged Mixamo FBX clips on how well they hold a rifle pointed at the
## crosshair, so an idle can be picked on evidence rather than by name.
##
##   godot --path . --script tools/probe_clip_poses.gd
##
## Run WITHOUT --headless: the animation mixer only writes bone poses on a real
## process frame.
##
## "forward" is how closely the grip-hand-to-foregrip-hand line points down
## camera-forward: 1.0 is a rifle aimed at the crosshair, 0.0 is one carried
## square across the chest.

const CLIP_DIR := "res://assets/models/characters/_clip_import"
const SAMPLES := 12


func _initialize() -> void:
	_run()


func _run() -> void:
	for file_name in DirAccess.get_files_at(CLIP_DIR):
		if not file_name.ends_with(".fbx"):
			continue
		var scene := (load(CLIP_DIR.path_join(file_name)) as PackedScene).instantiate() as Node3D
		root.add_child(scene)
		scene.rotation_degrees = Vector3(0.0, 180.0, 0.0)
		var skeleton := _find_first(scene, "Skeleton3D") as Skeleton3D
		var animation_player := _find_first(scene, "AnimationPlayer") as AnimationPlayer
		for animation_name in animation_player.get_animation_list():
			if String(animation_name).begins_with("Take"):
				continue
			var length := animation_player.get_animation(animation_name).length
			var worst := 1.0
			var total := 0.0
			var grip_travel := AABB()
			var first_sample := true
			for sample in SAMPLES:
				animation_player.play(animation_name)
				animation_player.seek(length * float(sample) / float(SAMPLES), true)
				await process_frame
				await process_frame
				skeleton.force_update_all_bone_transforms()
				var right := _bone_position(scene, skeleton, "mixamorig_RightHand")
				var left := _bone_position(scene, skeleton, "mixamorig_LeftHand")
				var forwardness := -(left - right).normalized().z
				worst = minf(worst, forwardness)
				total += forwardness
				# How far the grip hand wanders over the clip. The weapon is bolted
				# to it, so a big number here means the gun leaves the screen.
				if first_sample:
					grip_travel = AABB(right, Vector3.ZERO)
					first_sample = false
				else:
					grip_travel = grip_travel.expand(right)
			print(
				file_name.rpad(28),
				" ", animation_name.rpad(12),
				" length=", ("%.2f" % length).rpad(7),
				" mean forward=", "%.2f" % (total / float(SAMPLES)),
				" worst=", ("%.2f" % worst).rpad(7),
				" grip travel=", grip_travel.size.snapped(Vector3.ONE * 0.01)
			)
		scene.queue_free()
		root.remove_child(scene)
	quit()


func _bone_position(scene: Node3D, skeleton: Skeleton3D, bone_name: String) -> Vector3:
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index < 0:
		return Vector3.ZERO
	return scene.transform * (
		skeleton.transform * skeleton.get_bone_global_pose(bone_index).origin
	)


func _find_first(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var result := _find_first(child, type_name)
		if result:
			return result
	return null
