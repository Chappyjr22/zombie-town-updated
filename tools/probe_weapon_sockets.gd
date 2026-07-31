extends SceneTree
## Measures each weapon model so its grip and foregrip sockets can be written down
## from numbers instead of guessed from a silhouette.
##
##   godot --headless --path . --script tools/probe_weapon_sockets.gd
##
## Prints two profiles along the weapon's length, in the model's own coordinates:
##
## - **bulk**: how much cross-section sits in each slice. The receiver end is
##   heavy, the muzzle end is thin, which is what identifies which way the barrel
##   points - the origin is not consistently at the breech across a pack.
## - **underside**: the lowest point in each slice. The receiver reads flat, and
##   the pistol grip and magazine hang below it as dips. The dip nearest the
##   heavy end is the pistol grip; the flat run past the magazine is the
##   handguard the support hand takes.

const MODEL_DIR := "res://assets/models/weapons/cc0"
const SLICES := 16


func _initialize() -> void:
	for file_name in DirAccess.get_files_at(MODEL_DIR):
		if not file_name.ends_with(".glb"):
			continue
		var model := (
			load(MODEL_DIR.path_join(file_name)) as PackedScene
		).instantiate() as Node3D
		root.add_child(model)
		_report(file_name.get_basename(), model)
		model.queue_free()
		root.remove_child(model)
	quit()


func _report(name: String, model: Node3D) -> void:
	var points := _collect_points(model)
	if points.is_empty():
		return
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)

	var bulk := PackedInt32Array()
	bulk.resize(SLICES)
	var lowest := PackedFloat32Array()
	lowest.resize(SLICES)
	lowest.fill(INF)
	for point in points:
		var slice := clampi(
			int((point.z - bounds.position.z) / bounds.size.z * SLICES),
			0,
			SLICES - 1
		)
		bulk[slice] += 1
		lowest[slice] = minf(lowest[slice], point.y)

	print("\n", name, "  length=", snappedf(bounds.size.z, 0.001),
		"m  height=", snappedf(bounds.size.y, 0.001),
		"m  z range ", snappedf(bounds.position.z, 0.001),
		" to ", snappedf(bounds.end.z, 0.001))
	var bulk_line := "  bulk:      "
	var under_line := "  underside: "
	for slice in SLICES:
		bulk_line += "%5d" % bulk[slice]
		under_line += ("  -  " if is_inf(lowest[slice]) else "%5.2f" % lowest[slice])
	print("  z:         " + _axis_labels(bounds))
	print(bulk_line)
	print(under_line)


func _axis_labels(bounds: AABB) -> String:
	var line := ""
	for slice in SLICES:
		line += "%5.2f" % (bounds.position.z + (float(slice) + 0.5) / SLICES * bounds.size.z)
	return line


func _collect_points(model: Node3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for mesh_node in NodeUtils.find_all_of_type(model, "MeshInstance3D"):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var to_model: Transform3D = (
			model.global_transform.affine_inverse() * mesh_instance.global_transform
		)
		for surface in mesh_instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = (
				mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			)
			for vertex in vertices:
				points.append(to_model * vertex)
	return points
