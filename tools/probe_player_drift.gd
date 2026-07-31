extends SceneTree
## Reports where the player actually is, once a second, at normal speed.
##
##   godot --headless --path . --script tools/probe_player_drift.gd
##
## A standing player with no input should not move. This exists because the round
## loop probe found the player hundreds of metres below the map and thousands out
## along +Z, and the first job is to establish whether that happens at normal
## speed or is an artifact of that probe's compressed clock.

const LEVEL_PATH := "res://scenes/levels/test_arena.tscn"
const SAMPLES := 10


func _initialize() -> void:
	_run()


func _run() -> void:
	root.add_child((load(LEVEL_PATH) as PackedScene).instantiate())
	await process_frame
	var player := root.get_tree().get_first_node_in_group("player")
	if player == null:
		print("no player")
		quit(1)
		return

	var start: Vector3 = player.global_position
	print("start %v  (time_scale %.1f, physics %d Hz)" % [
		start, Engine.time_scale, Engine.physics_ticks_per_second
	])
	for sample in SAMPLES:
		await root.get_tree().create_timer(1.0).timeout
		var here: Vector3 = player.global_position
		print("  t+%ds  pos %v  vel %v  on_floor %s  zombies %d" % [
			sample + 1,
			here,
			player.velocity,
			player.is_on_floor(),
			root.get_tree().get_nodes_in_group("zombies").size(),
		])
	var drift: Vector3 = player.global_position - start
	print("drift over %ds: %v (%.2fm)" % [SAMPLES, drift, drift.length()])
	quit(0 if drift.length() < 2.0 else 1)
