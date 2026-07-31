extends SceneTree
## Generates a .tscn per weapon that instances the model and adds the two sockets
## the weapon controller seats it by.
##
##   godot --headless --path . --script tools/build_weapon_scenes.gd
##
## The markers are only *seeded* here, from geometry that can be identified
## reliably: the `Trigger` part gives the grip, and the far end of the model along
## the barrel gives the foregrip. Drag them into their final place in the editor
## against the actual mesh - that is the whole point of having sockets rather than
## inferring a grip from the silhouette, which is what the fallback path does and
## what kept landing the hand on the magazine.
##
## Existing scenes are never overwritten, so re-running this can't undo tuning.

const MODEL_DIR := "res://assets/models/weapons/cc0"
const SCENE_DIR := "res://scenes/weapons"

## How far below the trigger the hand's centre sits, and how far back - a trigger
## finger reaches forward of the palm.
const GRIP_BELOW_TRIGGER := 0.055
const GRIP_BEHIND_TRIGGER := 0.02
## Where the support hand starts, as a fraction of the distance from the grip to
## the muzzle end.
const FOREGRIP_FRACTION := 0.45


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_DIR))
	for file_name in DirAccess.get_files_at(MODEL_DIR):
		if not file_name.ends_with(".glb"):
			continue
		_build(file_name.get_basename())
	quit()


func _build(weapon_name: String) -> void:
	var scene_path := SCENE_DIR.path_join(weapon_name + ".tscn")
	if ResourceLoader.exists(scene_path):
		_add_missing_sockets(weapon_name, scene_path)
		return

	var model_path := MODEL_DIR.path_join(weapon_name + ".glb")
	var model := (load(model_path) as PackedScene).instantiate() as Node3D
	root.add_child(model)

	var bounds := _bounds_of(model, "")
	var trigger := _bounds_of(model, "Trigger")
	# Which way the barrel points: the muzzle is the end further from the trigger,
	# since a trigger always sits toward the back of a firearm.
	var trigger_z: float = trigger.get_center().z if trigger.size != Vector3.ZERO else bounds.get_center().z
	var muzzle_z: float = (
		bounds.end.z
		if absf(bounds.end.z - trigger_z) > absf(bounds.position.z - trigger_z)
		else bounds.position.z
	)
	var forward := signf(muzzle_z - trigger_z)

	var grip := Vector3(
		bounds.get_center().x,
		trigger.get_center().y - GRIP_BELOW_TRIGGER if trigger.size != Vector3.ZERO
			else bounds.position.y + bounds.size.y * 0.25,
		trigger_z - GRIP_BEHIND_TRIGGER * forward
	)
	var foregrip := Vector3(
		grip.x,
		grip.y + GRIP_BELOW_TRIGGER * 0.7,
		lerpf(grip.z, muzzle_z, FOREGRIP_FRACTION)
	)

	var scene_root := Node3D.new()
	scene_root.name = weapon_name.to_pascal_case()
	var instanced := (load(model_path) as PackedScene).instantiate()
	scene_root.add_child(instanced)
	instanced.owner = scene_root
	var muzzle := Vector3(grip.x, foregrip.y, muzzle_z)
	for socket in [
		{"name": "Grip", "at": grip},
		{"name": "Foregrip", "at": foregrip},
		{"name": "Muzzle", "at": muzzle},
	]:
		var marker := Marker3D.new()
		marker.name = socket.name
		marker.position = socket.at
		scene_root.add_child(marker)
		marker.owner = scene_root

	var packed := PackedScene.new()
	packed.pack(scene_root)
	var error := ResourceSaver.save(packed, scene_path)
	if error != OK:
		push_error("Could not write %s: %s" % [scene_path, error_string(error)])
		return
	print(
		"wrote  ", scene_path,
		"  grip=", grip.snapped(Vector3.ONE * 0.001),
		"  foregrip=", foregrip.snapped(Vector3.ONE * 0.001),
		"  muzzle toward ", "+Z" if forward > 0.0 else "-Z"
	)
	model.queue_free()
	root.remove_child(model)


## Adds any socket a scene is missing, leaving every existing one untouched.
##
## Sockets get added over time - `Muzzle` arrived after the first pass - and the
## ones already in a scene have been dragged into place by hand against the model.
## Re-seeding those would throw that away, so this only fills gaps.
func _add_missing_sockets(weapon_name: String, scene_path: String) -> void:
	var scene_root := (load(scene_path) as PackedScene).instantiate() as Node3D
	root.add_child(scene_root)
	var grip := scene_root.get_node_or_null("Grip") as Node3D
	var foregrip := scene_root.get_node_or_null("Foregrip") as Node3D
	if grip == null or foregrip == null or scene_root.get_node_or_null("Muzzle") != null:
		print("kept   ", scene_path, " (nothing to add)")
		scene_root.queue_free()
		root.remove_child(scene_root)
		return

	# Seeded on the model's own centre line, NOT on the line through the two hand
	# sockets - those are wrist positions, offset below and to the side of the bore
	# by the thickness of a hand, so a line through them is neither level nor
	# straight down the weapon.
	#
	# The marker is rotated to face down the barrel, and that facing is what the
	# controller reads as the barrel direction.
	var bounds := _bounds_of(scene_root, "")
	var muzzle_z: float = (
		bounds.end.z
		if absf(bounds.end.z - grip.position.z) > absf(bounds.position.z - grip.position.z)
		else bounds.position.z
	)
	var muzzle := Marker3D.new()
	muzzle.name = "Muzzle"
	muzzle.transform = Transform3D(
		Basis.looking_at(Vector3(0.0, 0.0, signf(muzzle_z - grip.position.z)), Vector3.UP),
		Vector3(bounds.get_center().x, bounds.get_center().y, muzzle_z)
	)
	scene_root.add_child(muzzle)
	muzzle.owner = scene_root

	var packed := PackedScene.new()
	packed.pack(scene_root)
	var error := ResourceSaver.save(packed, scene_path)
	if error != OK:
		push_error("Could not update %s: %s" % [scene_path, error_string(error)])
	else:
		print("added  Muzzle to ", scene_path, " at ", muzzle.position.snapped(Vector3.ONE * 0.001))
	scene_root.queue_free()
	root.remove_child(scene_root)


## Bounds of the whole model, or of just the meshes whose name contains `filter`.
func _bounds_of(model: Node3D, filter: String) -> AABB:
	var combined := AABB()
	var found := false
	for mesh_node in NodeUtils.find_all_of_type(model, "MeshInstance3D"):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		if filter != "" and not String(mesh_instance.name).contains(filter):
			continue
		var to_model: Transform3D = (
			model.global_transform.affine_inverse() * mesh_instance.global_transform
		)
		var mesh_bounds: AABB = mesh_instance.mesh.get_aabb()
		for corner in 8:
			var point: Vector3 = to_model * (mesh_bounds.position + Vector3(
				mesh_bounds.size.x * float(corner & 1),
				mesh_bounds.size.y * float((corner >> 1) & 1),
				mesh_bounds.size.z * float((corner >> 2) & 1)
			))
			if not found:
				combined = AABB(point, Vector3.ZERO)
				found = true
			else:
				combined = combined.expand(point)
	return combined
