extends Node3D
## test_arena.tscn's own setup - manual-testing convenience, not shipped
## gameplay. Fills the player's loadout with every weapon in the game (cycle
## with number keys/scroll wheel) so hand-position/grip work doesn't need a
## wall-buy run first. Pause is off for this scene specifically
## (Player.pause_enabled, set directly on the node in this .tscn) and
## RoundDirector's autostart is off too (also set directly in this .tscn) -
## one hand-placed zombie, not endless waves, is what a hand-position/ragdoll
## test actually needs.
##
## Fills loadout here in code rather than as a direct property override on
## the WeaponController node in the .tscn: that node sits four levels deep
## inside the instanced Player scene (CameraRig/SpringArm3D/Camera3D/
## WeaponController), and a hand-authored nested-instance override at that
## depth is easy to get subtly wrong with no way to visually confirm it
## worked. This runs after WeaponController's own _ready() (children ready
## before parents; TestArena is the scene root) already equipped slot 0 from
## the original loadout, and slot 0 here is still the same pistol, so nothing
## needs re-equipping.

const WEAPON_PATHS := [
	"res://resources/weapons/pistol.tres",
	"res://resources/weapons/revolver.tres",
	"res://resources/weapons/submachine_gun.tres",
	"res://resources/weapons/assault_rifle.tres",
	"res://resources/weapons/assault_rifle_2.tres",
	"res://resources/weapons/bullpup.tres",
	"res://resources/weapons/sniper_rifle.tres",
	"res://resources/weapons/shotgun.tres",
	"res://resources/weapons/flare_gun.tres",
	"res://resources/weapons/ray_gun.tres",
	"res://resources/weapons/ray_gun_mk2.tres",
	"res://resources/weapons/thundergun.tres",
	"res://resources/weapons/wunderwaffe.tres",
	"res://resources/weapons/war_machine.tres",
]


func _ready() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var controller: WeaponController = player.weapon_controller
	if controller == null:
		return
	var loadout: Array[WeaponData] = []
	for path in WEAPON_PATHS:
		loadout.append(load(path))
	controller.loadout = loadout
	controller.weapon_cap = loadout.size()
