extends SceneTree
## Renders the player's third-person view out of the real test arena, so changes
## to the body, the weapon in its hand, or the camera can be checked against what
## the game actually draws.
##
##   godot --path . --script tools/render_player_view.gd
##
## Needs a real rendering device, so run it WITHOUT --headless. Writes to
## previews/ (gitignored).
##
## Renders large: small dark previews hide seams and holes, which is how a broken
## arms mesh got signed off more than once before this was widened.

const OUTPUT_DIR := "res://previews"
const CAPTURE_SIZE := Vector2i(1920, 1080)
## Frames to let animation and camera settle before each capture.
const SETTLE_FRAMES := 8


func _initialize() -> void:
	_run()


func _run() -> void:
	DisplayServer.window_set_size(CAPTURE_SIZE)
	var arena := (load("res://scenes/levels/test_arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	var player := arena.get_node("Player")
	var controller: WeaponController = player.get_node("CameraRig/SpringArm3D/Camera3D/WeaponController")

	# Long enough for the character to fall to the ground and settle into idle,
	# otherwise every capture catches it mid-fall in the jump pose.
	for frame in 90:
		await process_frame
	await _capture("tp_idle.png")
	_report(player, controller)
	await _capture_body(player, "body_idle.png")

	# Driven through real input rather than by poking state, so the player's own
	# physics and animation run exactly as they do in game.
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for frame in 50:
		await process_frame
	await _capture("tp_sprint.png")
	Input.action_release("move_forward")
	Input.action_release("sprint")

	for frame in 40:
		await process_frame
	Input.action_press("aim")
	for frame in 40:
		await process_frame
	await _capture("tp_ads.png")
	Input.action_release("aim")

	Input.action_press("fire")
	for frame in 10:
		await process_frame
	await _capture("tp_fire.png")
	Input.action_release("fire")

	Input.action_press("reload")
	await process_frame
	Input.action_release("reload")
	for frame in 45:
		await process_frame
	await _capture("tp_reload.png")
	await _capture_body(player, "body_reload.png")

	print("Saved third-person previews.")
	quit()


func _report(player: Node3D, controller: WeaponController) -> void:
	print("  camera at ", player.get_node("CameraRig").position.snapped(Vector3.ONE * 0.001))
	print("  ammo ", controller.ammo_in_mag, "/", controller.reserve_ammo)
	if controller.world_model:
		print(
			"  weapon in hand at ",
			controller.to_local(controller.world_model.global_position).snapped(
				Vector3.ONE * 0.001
			)
		)


## The same body from outside, which is what other players see and the only way to
## check the weapon is actually held rather than merely in frame.
func _capture_body(player: Node3D, file_name: String) -> void:
	var debug_camera := Camera3D.new()
	player.add_child(debug_camera)
	debug_camera.fov = 50.0
	debug_camera.transform = Transform3D(Basis(), Vector3(1.5, 1.7, 1.2)).looking_at(
		Vector3(0.0, 1.3, 0.0),
		Vector3.UP
	)
	debug_camera.current = true
	await _capture(file_name)
	debug_camera.queue_free()
	player.get_node("CameraRig/SpringArm3D/Camera3D").current = true


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
