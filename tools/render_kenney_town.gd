extends SceneTree
## Renders scenes/levels/test_kenney_town.tscn from a few angles so the layout and
## materials can actually be looked at, not just probed numerically. Same pattern as
## tools/render_player_view.gd.
##
##   godot --path . --script tools/render_kenney_town.gd
##
## Needs a real rendering device, so run it WITHOUT --headless. Writes to
## previews/ (gitignored).

const OUTPUT_DIR := "res://previews"
const CAPTURE_SIZE := Vector2i(1920, 1080)
const SETTLE_FRAMES := 8


func _initialize() -> void:
	_run()


func _run() -> void:
	DisplayServer.window_set_size(CAPTURE_SIZE)
	var town := (load("res://scenes/levels/test_kenney_town.tscn") as PackedScene).instantiate()
	root.add_child(town)

	for frame in 20:
		await process_frame

	# Wide overhead shot: whole street should be visible in one frame. Layout
	# is centred on X=0 (two facing rows either side of Z=0), not X=35 - keep
	# this in sync with tools/build_test_kenney_town.gd's ROW centring.
	var overhead := Camera3D.new()
	root.add_child(overhead)
	overhead.fov = 70.0
	overhead.transform = Transform3D(Basis(), Vector3(0.0, 70.0, 45.0)).looking_at(
		Vector3(0.0, 0.0, 0.0), Vector3.UP
	)
	overhead.current = true
	await _capture("kenney_overhead.png")

	# Street-level shot standing in the street looking down its length.
	var street_level := Camera3D.new()
	root.add_child(street_level)
	street_level.fov = 70.0
	street_level.transform = Transform3D(Basis(), Vector3(-15.0, 1.7, 0.0)).looking_at(
		Vector3(15.0, 1.7, 0.0), Vector3.UP
	)
	street_level.current = true
	await _capture("kenney_streetlevel.png")

	# Close-up on a single building to check texture/material.
	var closeup := Camera3D.new()
	root.add_child(closeup)
	closeup.fov = 50.0
	closeup.transform = Transform3D(Basis(), Vector3(0.0, 2.5, -2.0)).looking_at(
		Vector3(0.0, 3.0, -5.0), Vector3.UP
	)
	closeup.current = true
	await _capture("kenney_closeup.png")

	print("Saved kenney town previews.")
	quit()


func _capture(file_name: String) -> void:
	for frame in SETTLE_FRAMES:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var error := image.save_png(
		ProjectSettings.globalize_path(OUTPUT_DIR.path_join(file_name))
	)
	if error != OK:
		push_error("Could not save %s: %s" % [file_name, error_string(error)])
