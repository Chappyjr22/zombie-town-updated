extends Interactable
class_name PackAPunchMachine

## Upgrades the currently-held weapon. Two tiers, costs/multipliers ported
## directly from the JS source's PACK_DMG/PACK_MAG/PACK_COST (see
## WeaponController's own constants). The cost is dynamic - it depends on
## which weapon is held and its current tier - so this overrides
## attempt_purchase() rather than using the base class's fixed `cost` export.


func _next_tier_cost(controller: WeaponController) -> int:
	var tier := controller.pack_level()
	if tier >= WeaponController.PACK_COST.size():
		return -1 # already at max tier
	return WeaponController.PACK_COST[tier]


func prompt_text(player: Node) -> String:
	var controller: WeaponController = player.weapon_controller
	if controller == null or controller.current_weapon == null:
		return "Pack-a-Punch"
	var next_cost := _next_tier_cost(controller)
	if next_cost == -1:
		return "%s (max upgrade)" % controller.current_weapon.display_name
	return "Upgrade %s - %d points" % [controller.current_weapon.display_name, next_cost]


func _can_interact(player: Node) -> bool:
	var controller: WeaponController = player.weapon_controller
	if controller == null or controller.current_weapon == null:
		return false
	var next_cost := _next_tier_cost(controller)
	return next_cost != -1 and player.points >= next_cost


func attempt_purchase(player: Node) -> void:
	var controller: WeaponController = player.weapon_controller
	if controller == null or controller.current_weapon == null:
		return
	var next_cost := _next_tier_cost(controller)
	if next_cost == -1 or not player.spend_points(next_cost):
		return
	controller.pack_upgrade()
