class_name NodeUtils
extends RefCounted

## Recursively finds the first descendant of the given class (e.g. "AnimationPlayer",
## "Skeleton3D") by class name rather than a hardcoded node path. Used for reaching
## into imported model scenes (glTF/FBX) whose exact internal hierarchy isn't known
## ahead of time.
static func find_first_of_type(root: Node, type_name: String) -> Node:
	if root == null:
		return null
	for child in root.get_children():
		if child.get_class() == type_name:
			return child
		var found := find_first_of_type(child, type_name)
		if found:
			return found
	return null


## Same idea as find_first_of_type, but collects every match instead of stopping
## at the first one (e.g. every MeshInstance3D in a model with multiple parts).
static func find_all_of_type(root: Node, type_name: String) -> Array:
	var results: Array = []
	_collect_of_type(root, type_name, results)
	return results


static func _collect_of_type(root: Node, type_name: String, results: Array) -> void:
	if root == null:
		return
	for child in root.get_children():
		if child.get_class() == type_name:
			results.append(child)
		_collect_of_type(child, type_name, results)


## Plays the first animation in `names` that exists on `anim_player`, trying both
## the plain clip name and the "SomeArmature|Name" baked-clip naming the
## Quaternius models use (see ASSET_MANIFEST.md for each model's actual clip
## names - they vary between models, hence checking a list of candidates).
static func play_first_available_animation(anim_player: AnimationPlayer, names: Array) -> void:
	if anim_player == null:
		return
	for n in names:
		if anim_player.has_animation(n):
			anim_player.play(n)
			return
		for lib_name in anim_player.get_animation_list():
			if lib_name.ends_with("|" + n) or lib_name == n:
				anim_player.play(lib_name)
				return
