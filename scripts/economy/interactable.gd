extends Area3D
class_name Interactable

## Base for anything the player can walk up to and press "interact" (E) on -
## wall buys, ammo buys, perk machines, Pack-a-Punch, buyable doors. Range is
## this node's own CollisionShape3D child (added by whatever places it, see
## tools/build_town_level.gd). Subclasses override prompt_text()/
## _can_interact()/_apply(); registering with the player and running the
## points-spend/refusal flow is shared here.

@export var cost: int = 0


func _ready() -> void:
	collision_layer = 0
	collision_mask = PhysicsLayers.ACTORS
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("register_interactable"):
		body.register_interactable(self)


func _on_body_exited(body: Node3D) -> void:
	if body.has_method("unregister_interactable"):
		body.unregister_interactable(self)


## What the HUD prompt shows. Override per subclass - the base cost isn't
## enough context on its own (owned/afford/maxed states all read differently).
func prompt_text(_player: Node) -> String:
	return ""


func _can_interact(player: Node) -> bool:
	return player.points >= cost


## Called by Player._update_interaction() on an "interact" press while this is
## the nearest in-range Interactable. Spends points and applies the effect;
## subclasses override _apply(), not this, so the afford-check/spend flow
## can't be forgotten by a new subclass.
func attempt_purchase(player: Node) -> void:
	if not _can_interact(player):
		return
	if not player.spend_points(cost):
		return
	_apply(player)


func _apply(_player: Node) -> void:
	pass
