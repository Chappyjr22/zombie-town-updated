extends SceneTree
## Extracts Mixamo's "Rifle Aiming Idle" into a standalone Animation resource the
## player loads over its body model's `idle` clip at runtime.
##
## Run from the project root:
##   (stage the FBX - see below)
##   godot --headless --path . --script tools/build_aim_idle.gd
##
## Why a loose .res rather than rebuilding mixamo_soldier.glb: the body model is
## the game's main character asset, and rewriting it in place to change one clip
## risks the whole thing for a small gain. An Animation is a plain resource, and
## its track paths ("Skeleton3D:mixamorig_*") already address the soldier's
## skeleton, so it drops straight onto that model with no retargeting.
##
## Staging: the source lives under the .gdignore'd raw-source folder, so copy it
## to assets/models/characters/_clip_import/rifle_aiming_idle.fbx, run
## `godot --import`, run this, then delete the folder again. It is 140MB.

const STAGING_DIR := "res://assets/models/characters/_clip_import"
const OUTPUT_DIR := "res://assets/animations"

## Output name to staged FBX. Add a row, stage the file, re-run.
const CLIPS := {
	"rifle_aim_idle": "rifle_aiming_idle.fbx",
	"rifle_sprint": "sprint_forward.fbx",
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var written := 0
	for output_name in CLIPS:
		if _extract(output_name, CLIPS[output_name]):
			written += 1
	if written == 0:
		_fail("Nothing extracted. Stage the FBXs and run `godot --import` first.")
		return
	quit()


func _extract(output_name: String, source_file: String) -> bool:
	var source_path := STAGING_DIR.path_join(source_file)
	if not ResourceLoader.exists(source_path):
		push_warning("%s is not imported; skipping %s." % [source_path, output_name])
		return false
	var scene := (load(source_path) as PackedScene).instantiate()
	root.add_child(scene)
	var animation_player := _find_first(scene, "AnimationPlayer") as AnimationPlayer
	if animation_player == null:
		push_warning("%s has no AnimationPlayer." % source_path)
		return false

	var clip_name := _pick_source_clip(animation_player)
	if clip_name == &"":
		push_warning("%s has no usable animation." % source_path)
		return false
	var animation: Animation = animation_player.get_animation(clip_name).duplicate()
	animation.resource_name = output_name
	animation.loop_mode = Animation.LOOP_LINEAR

	var output_path := OUTPUT_DIR.path_join(output_name + ".res")
	var error := ResourceSaver.save(animation, output_path)
	if error != OK:
		push_warning("Could not write %s: %s" % [output_path, error_string(error)])
		return false
	print(
		"Wrote ", output_path,
		" from '", clip_name, "' (", snappedf(animation.length, 0.01), "s, ",
		animation.get_track_count(), " tracks)"
	)
	scene.queue_free()
	root.remove_child(scene)
	return true


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
