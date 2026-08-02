extends Interactable
class_name AmmoBuyStation

## Flat-price ammo refill for one weapon. Refuses if the player doesn't own
## that weapon yet - buy the gun itself from a WallBuyStation first.

@export var weapon: WeaponData
@export var price: int = 500


func _ready() -> void:
	super._ready()
	cost = price


func prompt_text(_player: Node) -> String:
	return "Buy %s ammo - %d points" % [weapon.display_name, price]


func _can_interact(player: Node) -> bool:
	var controller: WeaponController = player.weapon_controller
	return controller != null and controller.owns_weapon(weapon) and player.points >= cost


func _apply(player: Node) -> void:
	player.weapon_controller.refill_weapon(weapon)
