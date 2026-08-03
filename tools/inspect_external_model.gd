extends SceneTree
## Measures and renders an arbitrary external .glb (e.g. a Meshy AI export still
## sitting in Downloads) before it's trusted or copied into assets/ - same
## discipline established across the Meshy evaluation in docs/ASSET_PIPELINE.md:
## never judge a generated model by its in-app preview alone.
##
## Prints real-world bounds, triangle/vertex count, and whether a normal map
## is actually present (Meshy's remesh step has been seen to drop it silently
## even when asked to keep it). Saves overhead/eye-level/close-up renders to
## res://previews/ (gitignored) so the result can actually be looked at.
##
## Needs a real rendering device, so run WITHOUT --headless:
##   godot --path . --script tools/inspect_external_model.gd -- "C:/path/to/model.glb" my_prefix
##
## The output prefix is optional - defaults to the input filename.

const OUTPUT_DIR := "res://previews"
const CAPTURE_SIZE := Vector2i(1600, 900)

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Usage: godot --path . --script tools/inspect_external_model.gd -- <path-to.glb> [output_prefix]")
		quit(1)
		return

	var glb_path: String = args[0]
	var prefix: String = args[1] if args.size() > 1 else glb_path.get_file().get_basename()

	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(glb_path, state)
	if err != OK:
		push_error("Failed to load %s: %s" % [glb_path, error_string(err)])
		quit(1)
		return

	var model := doc.generate_scene(state)
	root.add_child(model)
	# global_transform is unsafe to read until the node is actually in the
	# tree - same timing pitfall hit earlier this session on the Kenney probe.
	await process_frame

	var result := _walk_and_measure(model)
	print("\nTotals: %d verts, %d tris" % [result.verts, result.tris])

	_build_environment()
	await process_frame
	await process_frame
	await _render(result.aabb, prefix)

	print("\nSaved previews to %s/%s_*.png" % [OUTPUT_DIR, prefix])
	quit()


## Walks the tree, prints per-mesh stats, and returns the combined world-space
## AABB plus totals, so the render step can frame cameras automatically
## instead of hand-tuning distances per asset the way this session did four
## times over.
func _walk_and_measure(node: Node) -> Dictionary:
	var result := {"aabb": AABB(), "first": true, "verts": 0, "tris": 0}
	_measure(node, result)
	return result


func _measure(node: Node, result: Dictionary) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			var world_aabb: AABB = mi.global_transform * mi.mesh.get_aabb()
			if result.first:
				result.aabb = world_aabb
				result.first = false
			else:
				result.aabb = result.aabb.merge(world_aabb)

			print("\nMeshInstance: ", mi.name)
			print("  world AABB size (m): ", world_aabb.size.snapped(Vector3.ONE * 0.01))
			for i in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(i)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices = arrays[Mesh.ARRAY_INDEX]
				var idx_count = indices.size() if indices != null else 0
				result.verts += verts.size()
				result.tris += idx_count / 3
				print("  surface %d: %d verts, %d tris" % [i, verts.size(), idx_count / 3])
				var mat := mi.mesh.surface_get_material(i)
				if mat is BaseMaterial3D:
					var bm := mat as BaseMaterial3D
					print("  albedo: ", bm.albedo_texture.get_size() if bm.albedo_texture else "none",
						"  normal_enabled: ", bm.normal_enabled,
						"  normal_texture: ", ("present" if bm.normal_texture else "MISSING"))
	for child in node.get_children():
		_measure(child, result)


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-50.0)) * Basis(Vector3(0, 1, 0), deg_to_rad(25.0)), Vector3.ZERO)
	root.add_child(sun)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world_env.environment = env
	root.add_child(world_env)


func _render(bounds: AABB, prefix: String) -> void:
	DisplayServer.window_set_size(CAPTURE_SIZE)
	var center := bounds.get_center()
	var radius: float = bounds.size.length() * 0.5
	if radius <= 0.0:
		radius = 1.0

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 60.0
	cam.current = true

	cam.transform = Transform3D(Basis(), center + Vector3(0, radius * 1.3, radius * 1.1)).looking_at(center, Vector3.UP)
	await _capture("%s_overhead.png" % prefix)

	cam.transform = Transform3D(Basis(), center + Vector3(radius * 0.7, radius * 0.4, radius * 0.7)).looking_at(center, Vector3.UP)
	await _capture("%s_angled.png" % prefix)

	cam.fov = 45.0
	cam.transform = Transform3D(Basis(), center + Vector3(radius * 0.25, radius * 0.2, radius * 0.35)).looking_at(center, Vector3.UP)
	await _capture("%s_closeup.png" % prefix)


func _capture(file_name: String) -> void:
	for frame in 6:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR.path_join(file_name)))
	if error != OK:
		push_error("Could not save %s: %s" % [file_name, error_string(error)])
