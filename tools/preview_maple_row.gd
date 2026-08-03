extends SceneTree
## One-off sanity-check render of the generated maple_row.tscn layout - an
## overhead shot of the whole plus-shape plus a couple of ground-level looks
## down an arm, so the layout can actually be seen without the editor.
## Run WITHOUT --headless:
##   godot --path . --script tools/preview_maple_row.gd

const OUTPUT_DIR := "res://previews"

func _initialize() -> void:
	var scene: Node3D = (load("res://scenes/levels/maple_row.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	DisplayServer.window_set_size(Vector2i(1600, 900))

	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true

	# Overhead of the whole plus-shape.
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 140.0
	cam.transform = Transform3D(Basis(Vector3(1, 0, 0), deg_to_rad(-90.0)), Vector3(0, 80, 0))
	await _capture("maple_row_overhead.png")

	# Angled view of the plaza and one arm.
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 60.0
	cam.transform = Transform3D(Basis(), Vector3(-30, 25, 30)).looking_at(Vector3(-15, 3, 0), Vector3.UP)
	await _capture("maple_row_angled.png")

	# Street-level look down the west arm toward the corner store.
	cam.transform = Transform3D(Basis(), Vector3(-5, 1.7, 0)).looking_at(Vector3(-49, 2, 0), Vector3.UP)
	await _capture("maple_row_streetlevel.png")

	print("Saved previews to %s/maple_row_*.png" % OUTPUT_DIR)
	quit()


func _capture(file_name: String) -> void:
	for frame in 6:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var error := image.save_png(ProjectSettings.globalize_path(OUTPUT_DIR.path_join(file_name)))
	if error != OK:
		push_error("Could not save %s: %s" % [file_name, error_string(error)])
