extends Interactable
class_name MysteryBox

## Grants a random weapon from wonder_weapons - the five mystery-box-exclusive
## weapons ported from zombie-town-online's PERKS-adjacent weapon table (Ray
## Gun, Ray Gun Mark II, Thundergun, Wunderwaffe DG-2, War Machine - see
## scripts/weapons/CLAUDE.md for the full source data and what got simplified
## porting it). Rerollable any number of times at cost each - "nine hundred
## and fifty a roll" per that source's own flavor text - default cost matches.

@export var wonder_weapons: Array[WeaponData] = []


func _ready() -> void:
	super._ready()
	if cost <= 0:
		cost = 950


## 10 points a roll during Fire Sale (scripts/economy/power_up_drop.gd)
## instead of the usual 950 - ported from the source's own
## `buffs.firesale>0?10:950`. Only the box gets this discount there, not
## wall-buys/perks, so that's all this touches too.
const FIRE_SALE_COST := 10


func _current_cost(player: Node) -> int:
	if player.firesale_remaining > 0.0:
		return FIRE_SALE_COST
	return cost


func prompt_text(player: Node) -> String:
	return "Open Mystery Box - %d points" % _current_cost(player)


func _can_interact(player: Node) -> bool:
	return player.points >= _current_cost(player)


## Overrides attempt_purchase() rather than just _apply(), since the cost
## itself is dynamic (Fire Sale) - same reason wall_buy_station.gd does this
## instead of relying on the base class's fixed `cost` export.
func attempt_purchase(player: Node) -> void:
	var price := _current_cost(player)
	if player.points < price or not player.spend_points(price):
		return
	_apply(player)


## Prefers a weapon the player doesn't already have, matching the source's own
## flavor text ("it will not hand you something you are already carrying") -
## but falls back to the full pool once every entry is owned, rather than
## refusing to grant anything at all once someone's collected the set.
func _apply(player: Node) -> void:
	var controller: WeaponController = player.weapon_controller
	if controller == null or wonder_weapons.is_empty():
		return
	var not_owned: Array[WeaponData] = []
	for weapon in wonder_weapons:
		if weapon != null and not controller.owns_weapon(weapon):
			not_owned.append(weapon)
	var pool := not_owned if not not_owned.is_empty() else wonder_weapons
	var chosen: WeaponData = pool[randi() % pool.size()]
	controller.grant_weapon(chosen)
