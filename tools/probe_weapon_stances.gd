extends SceneTree
## Walks the player's whole loadout and reports the stance each weapon puts the
## body into.
##
##   godot --path . --script tools/probe_weapon_stances.gd
##
## Run WITHOUT --headless: the animation mixer only writes bone poses on a real
## process frame, and the weapon is aligned off those poses.
##
## Per weapon:
##
## - **set**: which locomotion set it selected, and the clip the forward blend
##   point ended up pointing at. A pistol should say `pistol`.
## - **support**: whether the off hand is being pulled onto the weapon.
## - **barrel·view**: how well the weapon's barrel agrees with where the camera is
##   looking, as a dot product. 1.0 is pointing exactly down the crosshair. This
##   is the number that used to sit near -1 when the barrel was being read off the
##   wrong axis.

const LEVEL_PATH := "res://scenes/levels/test_arena.tscn"
const SETTLE_FRAMES := 12


func _initialize() -> void:
	_run()


func _run() -> void:
	root.add_child((load(LEVEL_PATH) as PackedScene).instantiate())
	for frame in SETTLE_FRAMES:
		await process_frame

	var player := root.get_tree().get_first_node_in_group("player")
	if player == null:
		print("No player in the level.")
		quit(1)
		return
	var controller: WeaponController = player.weapon_controller
	var camera: Camera3D = player.camera

	print("%-2s %-14s %-9s %-22s %-8s %s" % [
		"#", "weapon", "set", "forward clip", "support", "barrel·view"
	])
	# The last two entries revisit a rifle and a handgun after the other kind has
	# been held, because the weapon is aligned off the body's live pose one frame
	# after equipping - so a switch that crosses stances is the case most likely to
	# catch a bad alignment.
	var order: Array[int] = []
	order.assign(range(controller.loadout.size()))
	order.append_array([0, controller.loadout.size() - 1, 0])
	for slot in order:
		controller.equip_slot(slot)
		for frame in SETTLE_FRAMES:
			await process_frame
		var forward_clip := &"?"
		for point in player.blend_points:
			if point.tier == &"normal" and point.key == &"forward":
				forward_clip = point.node.animation
		var barrel: Vector3 = controller.get_barrel_direction()
		var view: Vector3 = -camera.global_transform.basis.z
		print("%-2d %-14s %-9s %-22s %-8s %+.2f" % [
			slot,
			controller.current_weapon.display_name,
			player.current_set,
			forward_clip,
			"yes" if controller.current_weapon.uses_support_hand else "no",
			barrel.normalized().dot(view.normalized()),
		])
	quit()
