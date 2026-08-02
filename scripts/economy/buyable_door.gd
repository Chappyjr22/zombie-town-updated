extends Interactable
class_name BuyableDoor

## Blocks one building's entrance until bought. The actual solid mesh+collider
## is a separate StaticBody3D sibling (door_body, wired up by whoever places
## this - see tools/build_town_level.gd) rather than living on this Area3D,
## since an Area3D never blocks movement no matter what layer it's on.

@export var price: int = 750
## A plain (non-@export) reference wouldn't survive a scene save/load round
## trip - only exported properties get serialized into the .tscn, and
## tools/build_town_level.gd's generator saves this scene to disk once and
## never re-runs it, so every real load of town.tscn would otherwise see this
## as null and never actually remove the blocking door.
@export var door_body: StaticBody3D


func _ready() -> void:
	super._ready()
	cost = price


func prompt_text(_player: Node) -> String:
	return "Open door - %d points" % price


func _apply(_player: Node) -> void:
	if door_body:
		door_body.queue_free()
	queue_free()
