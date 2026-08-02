extends Interactable
class_name WallBuyStation

## Grants weapon into the player's loadout, or refills its ammo at half price
## if already owned - matching the JS source's own `own ? cost/2 : cost` rule.

@export var weapon: WeaponData
@export var full_cost: int = 1200


func _current_cost(player: Node) -> int:
	var controller: WeaponController = player.weapon_controller
	if controller and controller.owns_weapon(weapon):
		return int(round(full_cost / 2.0))
	return full_cost


func _can_interact(player: Node) -> bool:
	return player.points >= _current_cost(player)


func prompt_text(player: Node) -> String:
	var controller: WeaponController = player.weapon_controller
	var owned := controller != null and controller.owns_weapon(weapon)
	var label := ("Buy %s ammo" % weapon.display_name) if owned else ("Buy %s" % weapon.display_name)
	return "%s - %d points" % [label, _current_cost(player)]


## Overrides attempt_purchase() rather than just _apply(), since the cost
## itself depends on ownership - the base class's fixed `cost` export isn't
## enough here.
func attempt_purchase(player: Node) -> void:
	var controller: WeaponController = player.weapon_controller
	if controller == null:
		return
	var price := _current_cost(player)
	if player.points < price or not player.spend_points(price):
		return
	if controller.owns_weapon(weapon):
		controller.refill_weapon(weapon)
	else:
		controller.grant_weapon(weapon)
