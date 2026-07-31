extends Resource
class_name WeaponData

@export var display_name: String = ""
@export var model_scene: PackedScene
@export var fire_sound: AudioStream
@export var reload_sound: AudioStream
@export var damage: float = 25.0
@export var fire_rate: float = 8.0 ## rounds per second
@export var is_automatic: bool = true
@export var mag_size: int = 30
@export var reload_time: float = 2.0
@export var weapon_range: float = 120.0 ## named weapon_range, not range - that shadows GDScript's built-in range()
@export var starting_reserve_ammo: int = 90
## Which body locomotion set the character carries this weapon with - see
## LocomotionSets. A rifle is held in two hands across the chest and a handgun in
## one at the waist, so the whole run/strafe set differs, not just the arms.
## Names that aren't a known set fall back to the rifle one.
@export var locomotion_set: StringName = &"rifle"

## Whether the character's off hand is pulled onto the weapon's foregrip. False
## for a handgun: the pistol locomotion clips carry it in one hand and swing the
## other arm, and forcing that hand onto the grip fights the animation.
@export var uses_support_hand: bool = true

@export_group("Weapon fitting")
## Longest dimension of the weapon in metres once fitted - its real-world length,
## since the character holding it is life-sized. Not a screen-space fudge factor.
@export var weapon_length := 0.85
## Which point on the weapon the trigger hand closes around, as a fraction of its
## own bounding box: X along the barrel from the breech end, Y up from the bottom.
## The default is where a pistol grip sits on essentially every gun in the pack,
## so most weapons need no tuning at all.
@export var grip_anchor := Vector2(0.3, 0.18)
## Where the support hand rests, in the same bounding-box fractions as
## grip_anchor - the handguard on a rifle. This is the socket the support arm's
## IK drives the hand onto, so it holds whatever the animation does. Set it equal
## to grip_anchor for a one-handed weapon.
@export var foregrip_anchor := Vector2(0.62, 0.45)
## Fine adjustment in metres, applied after grip_anchor lands the weapon in the
## hand. Camera axes: +X right, +Y up, -Z toward the crosshair.
@export var grip_position := Vector3.ZERO
@export var grip_rotation_degrees := Vector3.ZERO
## Correction, in metres of camera space, for weapons whose sight line isn't at
## the top centre of their bounding box. Only needed if ADS looks off-centre.
@export var sight_nudge := Vector3.ZERO
