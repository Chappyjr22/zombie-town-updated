extends SceneTree
## Converts staged Mixamo FBX animations into loose Animation resources the player
## loads over its body model at runtime.
##
## Run from the project root:
##   (stage the FBXs - see below)
##   godot --headless --path . --import
##   godot --headless --path . --script tools/build_clips.gd
##
## Every .fbx in the staging folder is converted, named after its file. There is
## no table to maintain: drop a pack in, run it, and the clips appear.
##
## Why loose .res files rather than rebuilding mixamo_soldier.glb: the body model
## is the game's main character asset, and rewriting it in place to change clips
## risks the whole thing. An Animation is a plain resource, and its track paths
## ("Skeleton3D:mixamorig_*") already address the soldier's skeleton, so they drop
## straight onto that model with no retargeting.
##
## Staging: unzip a pack into assets/models/characters/_clip_import/, **excluding
## its bundled character mesh** - those are ~140MB and we already have the model.
## Delete the folder again afterwards.

const STAGING_DIR := "res://assets/models/characters/_clip_import"
const OUTPUT_DIR := "res://assets/animations/rifle"


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var written := 0
	var skipped := 0
	for file_name in DirAccess.get_files_at(STAGING_DIR):
		if not file_name.ends_with(".fbx"):
			continue
		if _extract(file_name.get_basename(), file_name):
			written += 1
		else:
			skipped += 1
	print("Wrote %d clips to %s (%d skipped)" % [written, OUTPUT_DIR, skipped])
	if written == 0:
		_fail("Nothing extracted. Stage the FBXs and run `godot --import` first.")
		return
	quit()


func _extract(output_name: String, source_file: String) -> bool:
	var source_path := STAGING_DIR.path_join(source_file)
	if not ResourceLoader.exists(source_path):
		push_warning("%s is not imported; skipping." % source_path)
		return false
	var scene := (load(source_path) as PackedScene).instantiate()
	root.add_child(scene)
	var animation_player := _find_first(scene, "AnimationPlayer") as AnimationPlayer
	if animation_player == null:
		push_warning("%s has no AnimationPlayer." % source_path)
		scene.queue_free()
		root.remove_child(scene)
		return false

	var clip_name := _pick_source_clip(animation_player)
	if clip_name == &"":
		push_warning("%s has no usable animation." % source_path)
		scene.queue_free()
		root.remove_child(scene)
		return false

	var animation: Animation = animation_player.get_animation(clip_name).duplicate()
	animation.resource_name = output_name
	animation.loop_mode = Animation.LOOP_LINEAR
	_strip_root_motion(animation)

	var error := ResourceSaver.save(animation, OUTPUT_DIR.path_join(output_name + ".res"))
	if error != OK:
		push_error("Could not write %s: %s" % [output_name, error_string(error)])
	scene.queue_free()
	root.remove_child(scene)
	return error == OK


## Pins the hips over the ground, keeping only their vertical bob.
##
## Mixamo clips travel: "sprint forward" carries the hips 3.5m over half a second.
## The character is moved by physics, not by the animation, so leaving that in
## makes the model surge forward and snap back every time the clip loops while the
## body - and the camera following it - moves at a steady speed.
##
## Vertical is deliberately kept: that bob is the character's stride, and
## flattening it makes them glide.
func _strip_root_motion(animation: Animation) -> void:
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		if String(animation.track_get_path(track)).get_slice(":", 1) != "mixamorig_Hips":
			continue
		var key_count := animation.track_get_key_count(track)
		if key_count == 0:
			continue
		var anchor: Vector3 = animation.track_get_key_value(track, 0)
		for key in key_count:
			var value: Vector3 = animation.track_get_key_value(track, key)
			animation.track_set_key_value(track, key, Vector3(anchor.x, value.y, anchor.z))


## Godot's FBX importer gives a Mixamo download two clips: the real motion, named
## "mixamo_com", and a "Take 001" stub that is just the bind pose. Picking the
## wrong one silently swaps the animation for a T-pose.
func _pick_source_clip(animation_player: AnimationPlayer) -> StringName:
	for candidate in animation_player.get_animation_list():
		if String(candidate).begins_with("mixamo"):
			return candidate
	for candidate in animation_player.get_animation_list():
		if not String(candidate).begins_with("Take"):
			return candidate
	return &""


func _find_first(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var result := _find_first(child, type_name)
		if result:
			return result
	return null


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
