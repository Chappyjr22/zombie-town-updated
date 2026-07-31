extends SceneTree
## Locates each weapon's pistol grip by measuring the shape of its underside,
## which is what WeaponData.grip_anchor addresses.
##
##   godot --headless --path . --script tools/probe_weapon_grip.gd
##
## The weapon is put in the canonical held frame (barrel down -Z) and sliced
## along the barrel. Printing the lowest point in each slice draws the underside
## profile: the receiver is flat, and the pistol grip and magazine hang below it
## as dips. The rearmost dip is the pistol grip, and its position as a fraction
## of the weapon's length is grip_anchor.x.

const RESOURCE_DIR := "res://resources/weapons"
const SLICES := 20


func _initialize() -> void:
	for file_name in DirAccess.get_files_at(RESOURCE_DIR):
		if not file_name.ends_with(".tres"):
			continue
		var weapon := load(RESOURCE_DIR.path_join(file_name)) as WeaponData
		if weapon == null or weapon.model_scene == null:
			continue
		var model := weapon.model_scene.instantiate() as Node3D
		root.add_child(model)
		_report(file_name.get_basename(), model, weapon)
		model.queue_free()
		root.remove_child(model)
	quit()


func _report(name: String, model: Node3D, weapon: WeaponData) -> void:
	var controller := WeaponController.new()
	var bounds := _measure(model)
	var largest: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var scale_factor: float = weapon.weapon_length / largest
	var fit := Transform3D(
		(
			Basis.from_euler(weapon.grip_rotation_degrees * (PI / 180.0))
			* controller._canonical_weapon_basis(bounds)
		).scaled(Vector3.ONE * scale_factor),
		Vector3.ZERO
	)
	controller.free()
	var held: AABB = fit * bounds

	var lowest := PackedFloat32Array()
	lowest.resize(SLICES)
	lowest.fill(INF)
	for mesh_node in NodeUtils.find_all_of_type(model, "MeshInstance3D"):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var to_held: Transform3D = (
			fit * model.global_transform.affine_inverse() * mesh_instance.global_transform
		)
		for surface in mesh_instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = (
				mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			)
			for vertex in vertices:
				var point: Vector3 = to_held * vertex
				# Fraction along the barrel, measured from the breech end.
				var fraction := (held.end.z - point.z) / held.size.z
				var slice := clampi(int(fraction * SLICES), 0, SLICES - 1)
				lowest[slice] = minf(lowest[slice], point.y)

	print("\n", name, "  (length ", weapon.weapon_length, "m, height ",
		snappedf(held.size.y, 0.001), "m)")
	print("  fraction along barrel -> lowest point, metres below the weapon's vertical centre")
	var line := ""
	for slice in SLICES:
		var fraction := (float(slice) + 0.5) / SLICES
		var depth: float = lowest[slice] - held.get_center().y
		line += "%.2f:%+.3f  " % [fraction, depth]
		if slice % 5 == 4:
			print("    ", line)
			line = ""


func _measure(model: Node3D) -> AABB:
	var combined := AABB()
	var found_any := false
	for mesh_node in NodeUtils.find_all_of_type(model, "MeshInstance3D"):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var to_model: Transform3D = (
			model.global_transform.affine_inverse() * mesh_instance.global_transform
		)
		var mesh_bounds: AABB = mesh_instance.mesh.get_aabb()
		for corner_index in 8:
			var corner: Vector3 = mesh_bounds.position + Vector3(
				mesh_bounds.size.x * float(corner_index & 1),
				mesh_bounds.size.y * float((corner_index >> 1) & 1),
				mesh_bounds.size.z * float((corner_index >> 2) & 1)
			)
			var model_corner: Vector3 = to_model * corner
			if not found_any:
				combined = AABB(model_corner, Vector3.ZERO)
				found_any = true
			else:
				combined = combined.expand(model_corner)
	return combined
