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
## How many separate rays one trigger pull fires. 1 for every hitscan weapon
## except a shotgun - damage above is the total if every pellet connects, split
## evenly across pellet_count rather than being per-pellet on its own, so
## Pack-a-Punch and Double Tap keep multiplying one number regardless of how
## many rays it's spread across.
@export var pellet_count: int = 1
## Half-angle in degrees of the cone pellets scatter within. 0 keeps every
## pellet on the same line as pellet_count 1 would anyway; only meaningful once
## pellet_count > 1.
@export var pellet_spread_degrees: float = 0.0
@export_group("Wonder weapon")
## 0 disables splash entirely - every current wall-buy weapon. Set together
## on the mystery-box exclusives that had it in the source data (Ray Gun/Ray
## Gun Mark II/War Machine) to damage everything else within splash_radius of
## the hit, tapering linearly to zero at the edge rather than applying in
## full throughout it. splash_damage is independent of `damage` above, not a
## fraction of it - the source data gives each its own number (War Machine is
## 0 direct damage, 420 splash: every kill is the splash, never the direct
## hit), so this does too.
@export var splash_damage: float = 0.0
@export var splash_radius: float = 0.0
## How many extra zombies a hit arcs to beyond the one actually struck, each
## within chain_radius of the previous target and each other - Wunderwaffe
## DG-2's signature. 0 means a hit never chains (every weapon but that one).
@export var chain_count: int = 0
@export var chain_radius: float = 9.0
## How many extra zombies one pellet can hit *beyond* the first, continuing
## in a straight line past whoever it just hit. 0 (every current weapon)
## stops the ray at the first hit, same as before this existed.
@export var penetration_count: int = 0
## Non-zero turns this into a cone weapon instead of a hitscan ray - the
## Thundergun. It deals cone_kill_damage (flat, no falloff) to every zombie
## within cone_kill_range and within half-angle cone_kill_angle_degrees of
## the barrel, instead of tracing a ray at all. The original had 0 direct
## damage and killed purely through a knockback impulse this project's
## ragdoll can't currently express (canned death animation only - see
## scripts/ai/CLAUDE.md's ragdoll history) - a large flat damage number
## reproduces "anything this close in front of you dies" without needing
## working ragdoll physics to sell the knockback itself.
@export var cone_kill_range: float = 0.0
@export var cone_kill_angle_degrees: float = 30.0
@export var cone_kill_damage: float = 100000.0
## Tints the equipped world model - see WeaponController._apply_weapon_tint().
## A placeholder differentiator, not a real reskin: none of the five box
## weapons has its own model yet, so each currently reuses an existing
## wall-buy weapon's mesh (see mystery_box.gd's own comment) and needs
## *something* to read as "not that gun" at a glance until real models exist.
## (1,1,1,0) (fully transparent) means "no tint, don't add the overlay pass
## at all" - every existing weapon's default.
@export var tint_color: Color = Color(1.0, 1.0, 1.0, 0.0)

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
