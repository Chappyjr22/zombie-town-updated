extends Interactable
class_name PerkMachine

## Grants a perk once (refuses a repeat purchase). Costs/effects match
## zombie-town-online's PERKS table. Jugg and Quick Revive are applied inside
## Player.grant_perk() itself (health has nowhere else to live, and Quick
## Revive is a state-machine change, not a stat); the rate-based perks below
## set a multiplier on the relevant controller instead.

@export var perk_key: StringName
@export var perk_name: String
@export var price: int = 2000


func _ready() -> void:
	super._ready()
	cost = price


func prompt_text(player: Node) -> String:
	if player.perks.get(perk_key, false):
		return "%s (owned)" % perk_name
	return "Buy %s - %d points" % [perk_name, price]


func _can_interact(player: Node) -> bool:
	return not player.perks.get(perk_key, false) and player.points >= cost


func _apply(player: Node) -> void:
	player.grant_perk(perk_key)
	var controller: WeaponController = player.weapon_controller
	match perk_key:
		&"speed":
			if controller:
				controller.reload_speed_multiplier = 0.5
		&"stamin":
			player.speed_multiplier = 1.25
		&"mule":
			if controller:
				controller.weapon_cap = 3
		&"dtap":
			if controller:
				controller.dtap_multiplier = 1.5
		# jugg and revive: handled entirely inside player.grant_perk()/take_damage().
