extends Node3D
class_name WeaponController

## Weapon logic, and the weapon the player character holds.
##
## There is exactly one weapon in the world, whether the player is currently
## looking at it in third person or first (Player.is_first_person just moves
## the camera - see scripts/player/CLAUDE.md): it hangs off the character's
## right hand and everyone - the player included - sees the same one. Nothing
## here is a viewmodel.
##
## A conventional first-person viewmodel (arms only, animated in camera space)
## was tried and abandoned - it's a different asset from this third-person
## character and can't reliably be derived from one, see
## `docs/ARCHITECTURE.md`. First person here is the camera moving to this same
## world model's own head instead, not a second asset.

## Bones the weapon is fitted against on the body.
const GRIP_HAND_BONE := &"mixamorig_RightHand"
const GRIP_FOREARM_BONE := &"mixamorig_RightForeArm"
## Only resolved/used for _solve_grip_arm_ik() - see that function's own
## comment for why the grip arm needs a two-bone solve at all now, when it
## never did before first-person ADS existed.
const GRIP_UPPER_ARM_BONE := &"mixamorig_RightArm"
const SUPPORT_HAND_BONE := &"mixamorig_LeftHand"
const SUPPORT_UPPER_ARM_BONE := &"mixamorig_LeftArm"
const SUPPORT_FOREARM_BONE := &"mixamorig_LeftForeArm"

## Everything the player is carrying, in slot order. Number keys select directly;
## the scroll wheel cycles. The first entry is what they start holding. Empty
## slots are `null` - the player starts with just a pistol (see player.tscn) and
## fills the rest via scripts/economy/wall_buy_station.gd.
@export var loadout: Array[WeaponData] = []
## How many non-null loadout slots grant_weapon() will fill before it starts
## replacing the currently-equipped weapon instead. Raised to 3 by Mule Kick
## (PerkMachine key "mule").
var weapon_cap := 2

@export_group("Weapon in hand")
## Fine adjustment to how the weapon sits in the body's hand. The orientation is
## measured from the body's own pose rather than authored - see _align_world_model.
@export var world_model_position := Vector3(0.0, 0.02, 0.0)
@export var world_model_rotation_degrees := Vector3.ZERO
## Extra rotation on top of the hand-+Y-onto-barrel correction in
## _solve_support_arm_ik(), for closing the last gap between "roughly wraps
## the foregrip" and actually sitting on it. Eye-tuned in the editor via the
## Remote scene tree's live inspector - see that function's comment.
@export var support_hand_rotation_degrees := Vector3(-15.0, -60.0, 20.0)

@export_group("Aim down sights")
@export_range(20.0, 90.0, 1.0) var ads_fov := 55.0
@export_range(1.0, 30.0, 0.5) var ads_transition_speed := 12.0
@export_range(0.1, 1.0, 0.05) var ads_mouse_sensitivity_multiplier := 0.65
## How far _update_ads_sight_alignment() will nudge the camera to close the
## gap between the crosshair and the weapon's sight - not something tighter,
## because CameraRig's own over-the-shoulder offset (0.45m on X alone) is
## part of what this is correcting for in third person - the sight is
## genuinely that far from the camera's default sightline, not just
## animation jitter. Third person only now - see ads_sight_target's own
## comment for why first person replaced this correction outright instead of
## reusing it with a bigger allowance (which is what this const used to be
## for - ADS_SIGHT_CLAMP_FIRST_PERSON, before it turned out the nudge
## approach itself couldn't work for first person, not just needed a bigger
## number).
const ADS_SIGHT_CLAMP_THIRD_PERSON := 0.6
## First person only: where the weapon's sight should land in camera-local
## space once ADS engages, replacing the bone-driven hold outright rather
## than correcting it - see _apply_first_person_weapon_hold()'s own comment for why
## a correction (which is what _update_ads_sight_alignment() is, and what
## first person used before this existed) can't work here: once the weapon
## is following an animated bone, nudging the *camera* to close the gap
## just moves the target by the same amount next frame, so the gap can
## never actually close, only get chased. X/Z at 0 puts the sight exactly on
## the crosshair (dead centre, where the camera always looks) *by
## construction*, for every weapon, regardless of that weapon's own
## sight_in_mesh - no per-weapon tuning needed for alignment the way third
## person's sight_nudge is; the hold's own position is solved backwards from
## this target instead. Z is eye relief - how far in front of the camera the
## sight sits (camera looks down its own -Z, so this is negative); more
## negative pulls it further away, showing more of the sight picture at the
## cost of a smaller sight in frame. X/Y should generally stay 0 (dead
## centre) - only nonzero for an intentionally offset sight picture (e.g. a
## scope mounted off to one side), not something ordinary irons should need.
@export var ads_sight_target := Vector3(0.0, 0.0, -0.35)
## Cosmetic only - the alignment above doesn't depend on this at all, since
## the hold's position is solved backwards from wherever this rotation
## points to still land the sight on ads_sight_target. Controls how the gun
## looks angled/canted relative to the camera, not whether it's aimed
## correctly.
@export var ads_hold_rotation_degrees := Vector3.ZERO
## Toggle live while playing (Remote scene tree, this node) to see exactly
## what sight_nudge/ads_sight_target are actually doing, instead of
## alt-tabbing and squinting at the render every time one changes. Draws two
## small spheres in world space, updated every frame: green at
## get_sight_position() (where the code currently thinks the sight is,
## given the weapon's live geometry and current sight_nudge), orange at
## camera.global_transform * ads_sight_target (where first-person ADS is
## trying to put it). They should sit exactly on top of each other once
## aim_blend reaches 1 in first person - if they don't, that's the actual
## bug to chase, not a tuning problem. See _update_debug_sight_marker()'s
## own comment.
@export var debug_show_sight_marker := false

@export_group("First person hip-fire")
## Where the weapon sits relative to the camera in first person while *not*
## aiming - same camera-anchored idea as the ADS hold (see
## _apply_first_person_weapon_hold()'s own comment for why hip-fire needs
## this too, not just ADS), but a plain fixed offset rather than solved
## backwards from a target - hip-fire doesn't need the sight lined up with
## anything, just a natural-looking carry position. Camera axes: +X right,
## +Y up, -Z forward.
##
## Constrained by real arm length, unlike the ADS hold - _solve_grip_arm_ik()
## has to actually reach this point every frame, and a two-bone chain can't
## stretch. Measured by probe on the AK-47: the grip arm's own upper+forearm
## bone lengths sum to ~0.478m of reach from the shoulder, and the shoulder
## sits roughly 0.41m from the first-person camera. A first guess of
## (0.15, -0.22, -0.4) put the target 0.735m from the shoulder - beyond
## reach entirely, which left the hand visibly short of the gun by ~0.23m
## (found by probe, not by eye - the gap doesn't show up unless something is
## specifically measuring hand-to-grip distance). This value keeps the
## target within reach with some margin for a natural, not-fully-extended
## arm. Still a first guess for the *look* of the carry, not eye-tuned - if
## you move this, sanity-check the new distance from the shoulder is
## comfortably under ~0.45m before spending time on how it looks, or you'll
## be tuning a pose the arm physically can't reach.
@export var hip_fire_hold_position := Vector3(-0.05, -0.30, -0.05)
## Cosmetic, same as ads_hold_rotation_degrees - how the gun looks angled in
## the hip-fire carry, no effect on anything functional.
@export var hip_fire_hold_rotation_degrees := Vector3(-5.0, 10.0, 0.0)
## Sideways/vertical sway amount while moving, in camera-local metres - a
## classic figure-8 bob (horizontal sine, vertical sine at double
## frequency, so it dips on every step rather than every stride). Zero
## while standing still (driven by owner.velocity's horizontal speed - see
## that function's own comment). Fades out on its own as aim_blend rises
## toward ADS, since interpolate_with() at weight 1.0 uses the ADS hold
## exclusively - no separate "stop bobbing while aiming" logic needed.
@export var hip_fire_bob_amount := Vector2(0.012, 0.018)
## How fast the bob cycles per metre/second of horizontal speed - higher
## means quicker footsteps read as a quicker bob.
@export var hip_fire_bob_frequency := 4.0

@export_group("Recoil")
## Firing kicks the view up and off to the side, and a spring settles it back.
## Nothing is held in front of the view, so recoil reads through the camera -
## which is also what makes automatic fire feel like it has weight.
@export_range(0.0, 10.0, 0.05) var recoil_pitch_degrees := 1.2
@export_range(0.0, 10.0, 0.05) var recoil_yaw_degrees := 0.4
@export_range(10.0, 400.0, 5.0) var recoil_stiffness := 120.0
@export_range(1.0, 60.0, 0.5) var recoil_damping := 14.0

var camera: Camera3D
var current_weapon: WeaponData
var current_slot := 0
## -1 when no switch is in flight. Set by equip_slot() when the outgoing
## weapon's set has a holster clip to play first - see that function and
## _process()'s mid-switch guard. _switch_timer counts down the clip's own
## length (returned by Player.play_holster_animation()), not a fixed guess.
var _pending_slot := -1
var _switch_timer := 0.0
## Ammo left in each slot, so switching away and back is not a free reload.
var _stored_ammo := {}

## Pack-a-Punch tier per slot (0 = none), same non-mutating per-slot pattern as
## _stored_ammo. Never written to the WeaponData resource itself - load()
## caches and shares one instance across every reference to a given .tres, so
## mutating current_weapon.damage directly would upgrade that weapon for
## everyone holding it, not just this slot.
var _pack_level := {}
const PACK_DAMAGE_MULTIPLIER := [1.0, 2.0, 3.4]
const PACK_CAPACITY_MULTIPLIER := [1.0, 1.0, 1.5]
const PACK_COST := [5000, 15000]
## Speed Cola (PerkMachine key "speed") multiplies reload duration by this.
var reload_speed_multiplier := 1.0
## Double Tap (PerkMachine key "dtap") multiplies damage by this. The perk's
## original games alternate between "fires faster" and "hits harder" across
## versions; damage was picked here since it reuses _effective_damage() rather
## than touching fire_cooldown timing.
var dtap_multiplier := 1.0

var world_model_attachment: BoneAttachment3D
var world_model: Node3D
var world_model_skeleton: Skeleton3D
var world_model_aligned := true

## Sockets on the weapon, in its mesh's own coordinates: where the support hand
## closes, and where the sight line sits. Both are measured in _fit_to_grip.
var foregrip_in_mesh := Vector3.ZERO
var sight_in_mesh := Vector3.ZERO
var barrel_in_mesh := Vector3.FORWARD
var muzzle_in_mesh := Vector3.ZERO
## Where the grip hand closes, in mesh coordinates - same shape as
## foregrip_in_mesh, only used by _solve_grip_arm_ik() (first-person ADS
## only - see that function's own comment for why the grip arm needs this at
## all when it's normally just bone-attached, no IK).
var grip_in_mesh := Vector3.ZERO
## sight_in_mesh split into a fit-time base point and the transform that
## carries it into mesh space, so current_weapon.sight_nudge - which the
## socket path adds directly in mesh space and the bounding-box path adds
## *before* its own out-of-fit transform, see _fit_to_grip's own comment -
## can be re-applied every frame in _recompute_sight_in_mesh() instead of
## being baked in once at equip time. Without this, tuning sight_nudge live
## in the Remote inspector (the whole point of it being an @export) needed a
## weapon switch after every drag to actually see the result - identity/zero
## until the first fit sets them for real.
var _sight_fit_base := Vector3.ZERO
var _sight_fit_transform := Transform3D.IDENTITY
## Support arm chain on the body, resolved when the weapon is attached.
var support_upper_index := -1
var support_forearm_index := -1
var support_hand_index := -1
## Grip arm chain - only resolved/used by _solve_grip_arm_ik(), which only
## runs in first person. Unlike the support arm, this arm doesn't normally
## need IK at all: the weapon is bone-attached to GRIP_HAND_BONE, so hand
## and weapon are coincident by construction. It only stops being coincident
## once _apply_first_person_weapon_hold() has decoupled the weapon from that
## bone - which it now does throughout first person, hip-fire included, not
## just while aiming.
var grip_upper_index := -1
var grip_forearm_index := -1
var grip_hand_index := -1
## Accumulates while moving in first-person hip-fire, drives
## hip_fire_bob_amount's sway - see _apply_first_person_weapon_hold()'s own
## comment. Deliberately time-since-equip, not wall-clock time, so the bob
## always starts at a consistent phase (foot "down") right as movement
## begins, rather than picking up mid-cycle from whatever the clock happened
## to read.
var _hip_fire_bob_time := 0.0
## Rotation from *raw mesh coordinates* (the space sight_in_mesh/
## grip_in_mesh/foregrip_in_mesh/barrel_in_mesh are all measured in) to
## "canonical" - barrel down -Z, sights up +Y - with no hand/bone pose
## entangled in it. Cached in attach_world_model(), right after _fit_to_grip()
## sets world_model.transform and before _align_world_model() ever touches
## it. This is NOT the same rotation as world_model.transform.basis ends up
## being after _align_world_model() runs: that function *post-multiplies* a
## second rotation onto it that re-aims the weapon along the line between the
## character's current hands, which depends on wherever the grip hand bone's
## animated pose happened to be at the one moment alignment ran - a real bug,
## found by testing (using that entangled rotation for the first-person hold
## put the barrel 110-170 degrees off the camera's own forward, despite the
## *sight* still reading as perfectly aligned - the hold's position solve
## absorbs whatever rotation it's given and still lands the sight exactly on
## target regardless, which is exactly why a badly-oriented gun didn't show
## up as a position error). _apply_first_person_weapon_hold() needs this
## pure, hand-independent rotation instead - the camera IS the reference
## frame for everything held in first person, nothing about a bone's
## incidental pose at alignment time belongs in it.
var _world_model_canonical_basis := Basis.IDENTITY

var hip_camera_fov := 75.0
var is_aiming := false
var aim_blend := 0.0
## Current smoothed camera nudge toward the weapon's sight, in world space -
## see _update_ads_sight_alignment.
var _ads_camera_offset := Vector3.ZERO
## SpringArm3D - camera.get_parent() - found in _ready(). The ADS nudge lands
## here rather than on the camera (SpringArm3D repositions its own direct
## child every frame - see the comment in _ready) or on CameraRig two levels
## up (player.gd's _update_crouch() writes camera_rig.position.y every
## physics tick unconditionally, which fought this for the same property).
## Nothing else touches SpringArm3D's own position, only its rotation (mouse
## look pitch) and spring_length (collision/ADS zoom).
var _ads_offset_node: Node3D
var _ads_offset_base_position := Vector3.ZERO
var recoil_offset := Vector2.ZERO
var recoil_velocity := Vector2.ZERO

var ammo_in_mag: int = 0
var reserve_ammo: int = 0
var fire_cooldown: float = 0.0
var is_reloading: bool = false
var reload_timer: float = 0.0

@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

signal ammo_changed(ammo_in_mag: int, reserve_ammo: int)
signal fired
signal reload_started(duration: float)
signal aim_changed(is_aiming: bool)
signal weapon_changed(weapon: WeaponData, slot: int)
## A shot that connected with something damageable. `part` is &"head" or &"body";
## `killed` is whether this shot finished it. The player turns these into points
## and the HUD turns them into a hitmarker - the controller deliberately knows
## about neither.
signal hit_confirmed(part: StringName, killed: bool)


func _ready() -> void:
	# Last in the frame: after the AnimationTree has written the pose and after the
	# player has pitched the spine, since the support arm is solved from a shoulder
	# both of those move. See the matching note in scripts/player/player.gd.
	process_priority = 20
	camera = get_parent() as Camera3D
	if camera:
		hip_camera_fov = camera.fov
		# See _ads_offset_node's own comment for why this is the camera's
		# parent (SpringArm3D) rather than the camera itself or CameraRig.
		_ads_offset_node = camera.get_parent() as Node3D
		if _ads_offset_node:
			_ads_offset_base_position = _ads_offset_node.position
	if not loadout.is_empty():
		equip_slot(0)


## Switches to a slot, remembering how much ammo the outgoing weapon had left.
##
## Without that bookkeeping, switching away and back would refill the magazine,
## which is a free reload.
## Holsters the current weapon first if its set has a holster clip
## (LocomotionSets), deferring the actual swap until that finishes - see
## _pending_slot's own comment and _process()'s mid-switch guard. Graceful
## fallback if there's no clip (every set but rifle, currently): swaps
## instantly, exactly as before this existed.
##
## Bug found by testing: a second switch requested while the first was still
## holstering (raw Mixamo draw/holster clips run ~2s - not fast) used to be
## silently refused outright, rather than queued or replacing the first -
## `_pending_slot != -1` bailed unconditionally. Mashing through several
## weapons quickly (exactly what test_arena's full loadout invites) meant the
## first press won and every later one vanished with no feedback, reading as
## the game being stuck rather than as input being dropped. Now a different
## target *replaces* the pending one (current_weapon hasn't actually changed
## yet, so this is just re-requesting the same holster clip against a new
## destination - restarts the one-shot rather than queuing a second one), and
## requesting the slot still actually in hand cancels back to it instead of
## queuing a pointless swap-to-self. Nothing is ever silently dropped now.
##
## The self-cancel also has to check current_weapon != null, not just
## slot == current_slot: current_slot defaults to 0, and _ready() calls
## equip_slot(0) to equip the starting weapon - without that check, that
## very first call matched trivially (0 == 0) and no-opped, so
## current_weapon stayed null forever. That cascaded silently: no world
## model (invisible weapon), _process()'s current_weapon == null guard
## blocking both firing and _update_weapon_switching() (so no key/scroll
## input could ever recover it either), and the HUD's own current_weapon
## != null catch-up guard in bind_player() never firing, leaving hud.tscn's
## placeholder weapon-name text ("AK-47") on screen the entire time - which
## is what actually surfaced this: reported as "I only have an AK and it's
## invisible and I can't shoot," none of which was really about the AK at
## all.
func equip_slot(slot: int) -> void:
	if slot < 0 or slot >= loadout.size() or loadout[slot] == null:
		return
	if slot == _pending_slot:
		return
	if slot == current_slot and current_weapon != null:
		_pending_slot = -1
		return
	var delay := 0.0
	if current_weapon != null and owner and owner.has_method("play_holster_animation"):
		delay = owner.play_holster_animation(current_weapon.locomotion_set)
	if delay > 0.0:
		_pending_slot = slot
		_switch_timer = delay
		return
	_pending_slot = -1
	_perform_equip_slot(slot)


func _perform_equip_slot(slot: int) -> void:
	if current_weapon != null:
		_stored_ammo[current_slot] = Vector2i(ammo_in_mag, reserve_ammo)
	current_slot = slot
	equip(loadout[slot])


## Steps through the loadout, wrapping at both ends and skipping empty slots.
func cycle_weapon(direction: int) -> void:
	if loadout.size() < 2:
		return
	var slot := current_slot
	for _step in loadout.size():
		slot = wrapi(slot + direction, 0, loadout.size())
		if loadout[slot] != null:
			equip_slot(slot)
			return


func equip(weapon: WeaponData) -> void:
	current_weapon = weapon
	# Picked up where this weapon was left, or full (at this slot's current
	# pack tier) if it hasn't been carried yet.
	var carried: Vector2i = _stored_ammo.get(
		current_slot,
		Vector2i(_effective_mag_size(), _effective_reserve_cap())
	)
	ammo_in_mag = carried.x
	reserve_ammo = carried.y
	is_reloading = false
	fire_cooldown = 0.0
	_set_aiming(false)
	if world_model_skeleton:
		attach_world_model(world_model_skeleton, GRIP_HAND_BONE)
	ammo_changed.emit(ammo_in_mag, reserve_ammo)
	weapon_changed.emit(weapon, current_slot)


func owns_weapon(weapon: WeaponData) -> bool:
	return loadout.has(weapon)


## Wall-buy purchase (scripts/economy/wall_buy_station.gd calls this after
## confirming the player doesn't already own `weapon`). Fills an empty slot
## within weapon_cap if there is one, otherwise replaces the weapon currently
## in hand - the same "buying swaps your current gun" rule the game this is
## based on uses, rather than a separate drop prompt.
func grant_weapon(weapon: WeaponData) -> void:
	var filled := 0
	for carried_weapon in loadout:
		if carried_weapon != null:
			filled += 1
	var empty_slot := loadout.find(null)
	if filled < weapon_cap and empty_slot != -1:
		loadout[empty_slot] = weapon
		equip_slot(empty_slot)
	else:
		loadout[current_slot] = weapon
		# Otherwise equip() would seed ammo from whatever the replaced weapon
		# had stored at this slot, which means nothing for a different gun.
		_stored_ammo.erase(current_slot)
		equip(weapon)


func pack_level() -> int:
	return _pack_level.get(current_slot, 0)


## Refills one owned weapon to its current pack tier's full capacity - used by
## scripts/economy/wall_buy_station.gd when the player already owns what
## they're buying (a wall buy becomes an ammo refill in that case). Computed
## from `weapon`/`slot` directly rather than _effective_mag_size(), which
## reads current_weapon/current_slot - the weapon being refilled usually isn't
## the one currently in hand.
## Max Ammo power-up (scripts/economy/power_up_drop.gd) - every carried
## weapon at once, not just the one in hand.
func refill_all_ammo() -> void:
	for weapon in loadout:
		if weapon != null:
			refill_weapon(weapon)


func refill_weapon(weapon: WeaponData) -> void:
	var slot := loadout.find(weapon)
	if slot == -1:
		return
	var tier: int = _pack_level.get(slot, 0)
	var mag := roundi(weapon.mag_size * PACK_CAPACITY_MULTIPLIER[tier])
	var reserve := roundi(weapon.starting_reserve_ammo * PACK_CAPACITY_MULTIPLIER[tier])
	if slot == current_slot:
		ammo_in_mag = mag
		reserve_ammo = reserve
		ammo_changed.emit(ammo_in_mag, reserve_ammo)
	else:
		_stored_ammo[slot] = Vector2i(mag, reserve)


## Pack-a-Punch purchase. Tops the held weapon's ammo up to its new capacity,
## same as a freshly-bought wall weapon would have - packing is meant to feel
## like an upgrade, not just a multiplier that quietly applies next reload.
func pack_upgrade() -> void:
	_pack_level[current_slot] = mini(pack_level() + 1, PACK_DAMAGE_MULTIPLIER.size() - 1)
	ammo_in_mag = _effective_mag_size()
	reserve_ammo = _effective_reserve_cap()
	ammo_changed.emit(ammo_in_mag, reserve_ammo)


## The Insta-Kill power-up (scripts/economy/power_up_drop.gd) overrides this
## outright rather than multiplying it - the source data makes every hit
## lethal regardless of what the gun would otherwise deal, not "hits harder."
## Checked on `owner` (the Player - see _hitscan()'s own exclude-list comment
## for why that's what `owner` is here) rather than duplicating the timer on
## WeaponController, since Insta-Kill is a player-wide buff, not a
## per-weapon one.
func _effective_damage() -> float:
	if owner and owner.has_method("has_instakill") and owner.has_instakill():
		return 999999.0
	return current_weapon.damage * PACK_DAMAGE_MULTIPLIER[pack_level()] * dtap_multiplier


func _effective_mag_size() -> int:
	return roundi(current_weapon.mag_size * PACK_CAPACITY_MULTIPLIER[pack_level()])


func _effective_reserve_cap() -> int:
	return roundi(current_weapon.starting_reserve_ammo * PACK_CAPACITY_MULTIPLIER[pack_level()])


# ---------------------------------------------------------------- weapon model


## Hangs the weapon off the body's hand. This is both what other players see and,
## because the camera is at this body's own head, what the player sees.
func attach_world_model(skeleton: Skeleton3D, bone_name: StringName) -> void:
	if world_model_attachment:
		world_model_attachment.queue_free()
		world_model_attachment = null
		world_model = null
	world_model_skeleton = skeleton
	if skeleton == null or current_weapon == null or current_weapon.model_scene == null:
		return

	world_model_attachment = BoneAttachment3D.new()
	world_model_attachment.name = "WeaponAttachment"
	skeleton.add_child(world_model_attachment)
	world_model_attachment.bone_name = bone_name
	if world_model_attachment.bone_idx < 0:
		push_warning("Body has no %s bone; the weapon has nothing to hang from." % bone_name)
		return

	support_upper_index = skeleton.find_bone(SUPPORT_UPPER_ARM_BONE)
	support_forearm_index = skeleton.find_bone(SUPPORT_FOREARM_BONE)
	support_hand_index = skeleton.find_bone(SUPPORT_HAND_BONE)
	if support_upper_index < 0 or support_forearm_index < 0 or support_hand_index < 0:
		push_warning("Body is missing part of the support arm; it won't reach the handguard.")
		support_upper_index = -1

	grip_upper_index = skeleton.find_bone(GRIP_UPPER_ARM_BONE)
	grip_forearm_index = skeleton.find_bone(GRIP_FOREARM_BONE)
	grip_hand_index = skeleton.find_bone(GRIP_HAND_BONE)
	if grip_upper_index < 0 or grip_forearm_index < 0 or grip_hand_index < 0:
		grip_upper_index = -1

	world_model = current_weapon.model_scene.instantiate()
	world_model_attachment.add_child(world_model)
	_fit_to_grip(world_model)
	# Cached here, before _align_world_model() gets a chance to post-multiply
	# its own hand-relative rotation on top - see the var's own comment for
	# why that matters.
	_world_model_canonical_basis = world_model.transform.basis
	_apply_weapon_tint(world_model, current_weapon.tint_color)
	# Deferred: the orientation is read off the body's animated pose, and nothing
	# has posed it yet on the frame the weapon is attached.
	world_model_aligned = false


## A crude reskin for weapons with no model of their own yet - the five
## mystery-box wonder weapons currently reuse an existing wall-buy weapon's
## mesh (see mystery_box.gd), and need *something* to read as "not that gun"
## at a glance until real models exist. Alpha 0 means "don't bother": every
## existing weapon defaults tint_color to that and pays no extra draw cost.
## An overlay pass rather than replacing the original material - the model's
## own textures/shading stay intact underneath a colored glow instead of
## being erased by it.
func _apply_weapon_tint(model: Node3D, tint: Color) -> void:
	if tint.a <= 0.0:
		return
	var overlay := StandardMaterial3D.new()
	overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	overlay.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	overlay.albedo_color = tint
	for descendant in _find_mesh_instances(model):
		descendant.material_overlay = overlay


func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_find_mesh_instances(child))
	return found


## Turns the weapon to lie along the line between the body's hands.
##
## _fit_to_grip leaves it pointing down -Z in its own frame, but it hangs off a
## wrist whose orientation is whatever Mixamo happened to author. Reading the
## direction off the body's own hands means the weapon points where the animation
## is holding it, in any clip, rather than at an angle guessed against that frame.
func _align_world_model() -> void:
	var grip_index := world_model_skeleton.find_bone(GRIP_HAND_BONE)
	# A two-handed weapon lies along the line between the hands. A handgun is held
	# in one, so there is no second point to measure against - it extends the
	# forearm instead, which is how a pistol is actually pointed.
	var two_handed := current_weapon == null or current_weapon.uses_support_hand
	var reference_index := world_model_skeleton.find_bone(
		SUPPORT_HAND_BONE if two_handed else GRIP_FOREARM_BONE
	)
	if grip_index < 0 or reference_index < 0:
		world_model_aligned = true
		return
	var grip_pose := world_model_skeleton.get_bone_global_pose(grip_index)
	var reference: Vector3 = world_model_skeleton.get_bone_global_pose(reference_index).origin
	var barrel := (reference - grip_pose.origin) if two_handed else (grip_pose.origin - reference)
	if barrel.length_squared() < 0.0001:
		return
	var into_hand := grip_pose.basis.orthonormalized().inverse()
	world_model.transform = Transform3D(
		Basis.looking_at((into_hand * barrel).normalized(), into_hand * Vector3.UP)
		* Basis.from_euler(world_model_rotation_degrees * (PI / 180.0)),
		world_model_position
	) * world_model.transform
	world_model_aligned = true


## First person only (both hip-fire and ADS): pins the weapon to a transform
## relative to the camera instead of letting it keep following the animated
## grip-hand bone the way third person always does.
##
## Originally ADS-only - the bone-driven hold specifically made ADS
## impossible to hold still, and unaligned itself depending on which way the
## camera looked: the weapon's position came from wherever GRIP_HAND_BONE
## happened to be this frame, and that bone is driven by whatever
## locomotion/idle clip is currently blended in - a system built to look
## alive from a few metres away in third person, not to hold a precision
## sight picture a few centimetres from the camera. `Player._apply_spine_aim()`'s
## torso correction tries to fight the same clip into pointing the barrel at
## the camera every frame and never fully won (see `scripts/player/CLAUDE.md`'s
## ADS residual note, from before this existed) - chasing that further wasn't
## the answer, it was the wrong tool for this job. A camera-anchored hold
## sidesteps the fight entirely: nothing here depends on the skeleton's
## current pose at all, so there's nothing left for an idle clip to disagree
## with.
##
## Extended to hip-fire once it became clear the same mismatch was still
## there the rest of the time: `Player._update_first_person_camera()` tracks
## the head bone rigidly regardless of aim state, so a bone-driven hip-fire
## weapon was *also* drifting relative to a camera that never moved with it -
## just never fixed, because it never got the same scrutiny ADS did.
##
## The two holds are computed differently. **ADS's own position is solved
## *backwards* from `ads_sight_target`** instead of being a fixed offset
## someone has to eyeball per weapon: given a rotation
## (`ads_hold_rotation_degrees`, purely cosmetic - a look, not a correction)
## and the requirement that `sight_in_mesh` land exactly on `ads_sight_target`
## once transformed by the hold, the hold's origin is the one value that
## satisfies it - exact crosshair alignment by construction, no per-weapon
## `sight_nudge`-style tuning needed for it specifically (unlike third
## person's own nudge-based alignment, which can only get within its clamp
## of correct). **Hip-fire has no such target to solve for** - nothing needs
## to land on the crosshair while not aiming - so `hip_fire_hold_position` is
## just a fixed offset, plus `hip_fire_bob_amount`'s figure-8 sway driven by
## `owner.velocity`'s horizontal speed (classic sine bob: horizontal at the
## base frequency, vertical at double - dips on every step, not every
## stride). Both reuse `_world_model_canonical_basis` for their rotation
## (never `world_model.transform.basis`/anything bone-derived - see that
## var's own comment for the bug that came from getting this wrong once
## already).
##
## The two holds are blended by `aim_blend` via `Transform3D.interpolate_with()`
## - at 0 it's pure hip-fire hold (bob included), at 1 it's pure ADS hold (bob
## excluded automatically, since interpolate_with() at weight 1.0 ignores the
## first transform entirely - no separate "stop bobbing while aiming" logic
## needed). No blend *into* first person from the bone-driven pose on
## toggling `is_first_person` on - the weapon snaps into the held pose the
## same frame, matching `_update_first_person_camera()`'s own accepted pop on
## toggle rather than adding transition machinery for what's a deliberate,
## infrequent user action.
##
## Runs before `_solve_support_arm_ik()`/`_solve_grip_arm_ik()`, which both
## target `world_model`'s current transform and need to react to the *held*
## pose for this frame, not last frame's - see `_process()`'s own ordering.
func _apply_first_person_weapon_hold(delta: float) -> void:
	if world_model == null or camera == null or current_weapon == null:
		return
	if not (owner and bool(owner.get("is_first_person"))):
		return
	var hold_basis := _world_model_canonical_basis
	var ads_basis := Basis.from_euler(ads_hold_rotation_degrees * (PI / 180.0)) * hold_basis
	var ads_hold := camera.global_transform * Transform3D(
		ads_basis, ads_sight_target - ads_basis * sight_in_mesh
	)

	var speed := 0.0
	if owner is CharacterBody3D:
		var body_velocity: Vector3 = (owner as CharacterBody3D).velocity
		speed = Vector2(body_velocity.x, body_velocity.z).length()
	_hip_fire_bob_time += delta * speed * hip_fire_bob_frequency
	var bob := Vector3(
		sin(_hip_fire_bob_time) * hip_fire_bob_amount.x,
		absf(sin(_hip_fire_bob_time * 2.0)) * hip_fire_bob_amount.y,
		0.0
	)
	var hip_basis := Basis.from_euler(hip_fire_hold_rotation_degrees * (PI / 180.0)) * hold_basis
	var hip_hold := camera.global_transform * Transform3D(hip_basis, hip_fire_hold_position + bob)

	world_model.global_transform = hip_hold.interpolate_with(ads_hold, aim_blend)


## Seats the weapon in the hand using the `Grip` and `Foregrip` markers on its
## scene, if it has them.
##
## Two markers give both the position and the direction: the grip goes where the
## trigger hand closes, and the line from grip to foregrip *is* the barrel. That
## replaces guessing at both from the silhouette, which is what the fallback below
## does and what kept putting the hand on the magazine instead of the rail.
##
## Markers are placed in the weapon's own .tscn, so they're dragged into position
## in the editor against the actual model rather than derived from numbers.
func _fit_from_sockets(model: Node3D) -> bool:
	var grip := model.get_node_or_null("Grip") as Node3D
	var foregrip := model.get_node_or_null("Foregrip") as Node3D
	if grip == null or foregrip == null:
		return false

	# Measured before model.transform is reassigned below, while it's still
	# identity, so this lands in the same raw mesh space as grip.position/
	# along_barrel/etc. - not the fitted frame _fit_to_grip's own bounding-box
	# path measures held_bounds in (see that function's own comment).
	var raw_bounds := _measure_local_bounds(model)

	# The barrel comes from the Muzzle marker's own facing - its -Z - not from a
	# line between sockets.
	#
	# Grip and Foregrip mark where the *wrist bones* go, so both are deliberately
	# offset from the weapon: the grip sits below the bore, and the foregrip is
	# pushed out to the side by the thickness of a hand. Any line drawn between
	# them therefore runs uphill and off to one side, and squaring that to
	# horizontal tips the weapon down and yaws it - which is exactly what it did.
	# A muzzle socket has no such problem because it is on the bore by definition.
	var muzzle := model.get_node_or_null("Muzzle") as Node3D
	var along_barrel := (
		-muzzle.transform.basis.z if muzzle != null
		else foregrip.position - grip.position
	)
	if along_barrel.length_squared() < 0.000001:
		push_warning("%s has its weapon sockets stacked on one another." % model.name)
		return false

	# Turn the weapon so the grip-to-foregrip line runs down -Z, then slide it so
	# the grip marker lands on the origin - which is the hand.
	var fit_basis := (
		Basis.from_euler(current_weapon.grip_rotation_degrees * (PI / 180.0))
		* Basis.looking_at(along_barrel.normalized(), Vector3.UP).inverse()
	)
	model.transform = Transform3D(
		fit_basis,
		current_weapon.grip_position - fit_basis * grip.position
	)

	foregrip_in_mesh = foregrip.position
	grip_in_mesh = grip.position
	muzzle_in_mesh = muzzle.position if muzzle != null else foregrip.position + along_barrel
	# Along the barrel: same as before, roughly centred between grip and
	# muzzle. Height: biased toward the model's own measured top - a flat
	# "+0.04 above the grip" (the original formula) landed near grip height
	# on every weapon, nowhere close to an actual top-mounted rail/sight
	# (found via probe on the M4A1: heuristic point at Y=-0.061 with the
	# model's own bounds running all the way to Y=+0.088 - the rail, not
	# the grip, is what a real sight sits near). raw_bounds is measured
	# above in the same raw mesh space grip.position/along_barrel already
	# are. Matches _fit_to_grip's own bounding-box fallback below, which
	# already uses the exact top of its (differently-measured) bounds for
	# the same reason - "top-centre of the bounds is where iron sights and
	# rail optics sit on every model in the pack" per that path's own
	# comment; this just brings the socket-marker path in line with it
	# instead of using a fixed, ungrounded constant. Still only a starting
	# guess - current_weapon.sight_nudge remains the per-weapon correction
	# for whatever this doesn't land exactly on.
	var sight_y := (
		raw_bounds.position.y + raw_bounds.size.y
		if raw_bounds.size.y > 0.0001
		else grip.position.y + 0.04
	)
	var along_barrel_point := grip.position + along_barrel * 0.5
	_sight_fit_base = Vector3(along_barrel_point.x, sight_y, along_barrel_point.z)
	_sight_fit_transform = Transform3D.IDENTITY
	_recompute_sight_in_mesh()
	barrel_in_mesh = along_barrel.normalized()
	# These models are authored at real-world scale, so nothing is resized.
	return true


## Scales the weapon so its longest dimension matches weapon_length, turns it to
## point down -Z, and slides it so grip_anchor - its pistol grip - sits on the
## origin, which is where the hand closes.
##
## The fallback for weapons with no sockets: everything is inferred from the
## model's own bounding box. Workable, but it can only guess where a grip is from
## the shape of the underside, so prefer markers.
func _fit_to_grip(model: Node3D) -> void:
	if _fit_from_sockets(model):
		return
	var bounds := _measure_local_bounds(model)
	if bounds.size == Vector3.ZERO:
		return
	var largest_dimension: float = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	if largest_dimension <= 0.0001:
		return

	var scale_factor: float = current_weapon.weapon_length / largest_dimension
	var fit_basis := (
		Basis.from_euler(current_weapon.grip_rotation_degrees * (PI / 180.0))
		* _canonical_weapon_basis(bounds)
	)
	var fit_transform := Transform3D(fit_basis.scaled(Vector3.ONE * scale_factor), Vector3.ZERO)
	# Bounds re-measured after rotating and scaling, so the anchor fractions are
	# read off the weapon as it will actually be held: -Z is down the barrel.
	var held_bounds: AABB = fit_transform * bounds
	var grip_point := Vector3(
		held_bounds.get_center().x,
		held_bounds.position.y + current_weapon.grip_anchor.y * held_bounds.size.y,
		held_bounds.end.z - current_weapon.grip_anchor.x * held_bounds.size.z
	)
	model.transform = Transform3D(
		fit_transform.basis,
		current_weapon.grip_position - grip_point
	)

	# Both sockets are stashed in the *mesh's* own coordinates rather than the
	# fitted frame, so `world_model.global_transform * socket` locates them no
	# matter what _align_world_model later multiplies onto the model.
	var out_of_fit := fit_transform.affine_inverse()
	grip_in_mesh = out_of_fit * grip_point
	foregrip_in_mesh = out_of_fit * Vector3(
		held_bounds.get_center().x,
		held_bounds.position.y + current_weapon.foregrip_anchor.y * held_bounds.size.y,
		held_bounds.end.z - current_weapon.foregrip_anchor.x * held_bounds.size.z
	)
	# Top-centre of the bounds is where iron sights and rail optics sit on every
	# model in the pack; sight_nudge covers anything unusual.
	_sight_fit_base = Vector3(
		held_bounds.get_center().x,
		held_bounds.end.y,
		held_bounds.get_center().z
	)
	_sight_fit_transform = out_of_fit
	_recompute_sight_in_mesh()
	# The barrel, kept as a direction in mesh coordinates for the same reason as
	# the sockets. Reading it off the model's local -Z at runtime does NOT work:
	# _align_world_model post-multiplies a rotation, so -Z stops being the barrel
	# the moment the weapon is turned into the hand. Measuring it here, before any
	# of that, is what makes the aim correction in player.gd trustworthy.
	barrel_in_mesh = (out_of_fit.basis * Vector3.FORWARD).normalized()


## Works out which way an arbitrarily-authored weapon model is facing from the
## shape of its bounding box, and returns the rotation that puts it in a canonical
## frame: barrel down -Z, sights up +Y.
##
## Every gun is long, moderately tall, and thin, so the longest bounding-box axis
## is the barrel, the shortest is the weapon's width, and the remaining one is its
## height. The models in the pack are authored with their origin at the breech, so
## the muzzle is on whichever side of the origin the bulk sits. Weapons that don't
## fit that description get corrected by grip_rotation_degrees.
func _canonical_weapon_basis(bounds: AABB) -> Basis:
	var extents := [bounds.size.x, bounds.size.y, bounds.size.z]
	var barrel_axis := 0
	var width_axis := 0
	for axis in 3:
		if extents[axis] > extents[barrel_axis]:
			barrel_axis = axis
		if extents[axis] < extents[width_axis]:
			width_axis = axis
	var up_axis := 3 - barrel_axis - width_axis

	var barrel_sign := signf(bounds.get_center()[barrel_axis])
	if is_zero_approx(barrel_sign):
		barrel_sign = 1.0

	var images := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	images[barrel_axis] = Vector3.FORWARD * barrel_sign
	images[up_axis] = Vector3.UP
	images[width_axis] = images[up_axis].cross(images[barrel_axis])
	var weapon_basis := Basis(images[0], images[1], images[2])
	# Which way the width axis has to face for a right-handed (unmirrored) basis
	# depends on how barrel/up/width happened to land on x/y/z, so derive it from
	# the determinant rather than assuming.
	if weapon_basis.determinant() < 0.0:
		images[width_axis] = -images[width_axis]
		weapon_basis = Basis(images[0], images[1], images[2])
	return weapon_basis


## Skeleton-space transform for converting a world-space point into a point
## relative to world_model_skeleton's own parent - shared by both arm solves
## and _solve_grip_arm_ik(), since both need to turn a world-space weapon
## socket into a skeleton-space IK target the same way.
func _into_skeleton_space() -> Transform3D:
	return (
		(world_model_skeleton.get_parent() as Node3D).global_transform
		* world_model_skeleton.transform
	).affine_inverse()


## Standard two-bone solve: set the elbow's angle from the law of cosines so the
## chain spans exactly the distance to the target, then swing the whole arm so the
## hand lands on it. The pole decides which way the elbow breaks; without one the
## solve is free to fold the arm through the character's chest.
##
## Shared by _solve_support_arm_ik() (always active, for the off hand to
## reach the foregrip - the weapon is fitted to the grip hand, so the other
## one lands wherever the clip put it, floating short of a weapon Mixamo's
## hand spacing was never authored for) and _solve_grip_arm_ik()
## (first person only, for the grip hand to reach the weapon once
## _apply_first_person_weapon_hold() has decoupled it from the bone it's
## normally attached to instead). `target` is in skeleton space - see
## _into_skeleton_space().
func _solve_two_bone_arm(
	upper_index: int, forearm_index: int, hand_index: int, target: Vector3
) -> void:
	var skeleton := world_model_skeleton
	var shoulder: Vector3 = skeleton.get_bone_global_pose(upper_index).origin
	var elbow_pose := skeleton.get_bone_global_pose(forearm_index)
	var hand: Vector3 = skeleton.get_bone_global_pose(hand_index).origin
	var upper_length := shoulder.distance_to(elbow_pose.origin)
	var lower_length := elbow_pose.origin.distance_to(hand)
	if upper_length < 0.0001 or lower_length < 0.0001:
		return
	# Elbow points down and away from the weapon, which is where an arm
	# naturally breaks, holding a rifle or reaching to steady one.
	var pole := target + Vector3(0.0, -0.5, 0.0) + (shoulder - target).normalized() * 0.2

	# Clamped just inside full extension and full fold, so the solve never has to
	# divide by a degenerate triangle.
	var reach := clampf(
		shoulder.distance_to(target),
		absf(upper_length - lower_length) + 0.001,
		upper_length + lower_length - 0.001
	)
	var desired_elbow := acos(clampf(
		(upper_length * upper_length + lower_length * lower_length - reach * reach)
		/ (2.0 * upper_length * lower_length),
		-1.0,
		1.0
	))
	var current_elbow := (shoulder - elbow_pose.origin).normalized().angle_to(
		(hand - elbow_pose.origin).normalized()
	)
	var bend_axis := (hand - shoulder).cross(pole - shoulder)
	if bend_axis.length_squared() < 0.000001:
		bend_axis = (hand - shoulder).cross(Vector3.UP)
	_set_bone_global_basis(
		forearm_index,
		Basis(bend_axis.normalized(), desired_elbow - current_elbow) * elbow_pose.basis
	)
	skeleton.force_update_all_bone_transforms()

	var swung_hand: Vector3 = skeleton.get_bone_global_pose(hand_index).origin
	_set_bone_global_basis(
		upper_index,
		Basis(Quaternion(
			(swung_hand - shoulder).normalized(),
			(target - shoulder).normalized()
		)) * skeleton.get_bone_global_pose(upper_index).basis
	)
	skeleton.force_update_all_bone_transforms()


## Bends the body's support arm so its hand closes on the weapon's handguard.
## See _solve_two_bone_arm()'s own comment for the solve itself.
func _solve_support_arm_ik() -> void:
	if world_model == null or support_upper_index < 0:
		return
	if current_weapon != null and not current_weapon.uses_support_hand:
		return
	var into_skeleton := _into_skeleton_space()
	var target: Vector3 = into_skeleton * (world_model.global_transform * foregrip_in_mesh)
	_solve_two_bone_arm(support_upper_index, support_forearm_index, support_hand_index, target)

	var skeleton := world_model_skeleton
	# The hand's rotation is corrected to wrap the palm around the foregrip
	# instead of just holding whatever pose the clip authored.
	#
	# Forcing the hand's basis to match the weapon's outright was tried before
	# and made it worse: Mixamo hand bones run +Y down the fingers, so aligning
	# the hand to the weapon's own basis points the fingers straight up and
	# drapes the hand over the top of the barrel instead of wrapping it. This
	# maps hand-local +Y onto the barrel direction specifically instead (in
	# skeleton space, matching the target/shoulder math above) -
	# support_hand_rotation_degrees is the remaining tunable offset, since
	# "onto the barrel" gets the wrap roughly right but not exactly - eye-tuned
	# in the editor (see that var's own comment).
	#
	# Built fresh from barrel_local every frame, not as a delta nudged onto
	# whatever the hand's current basis happens to be - an earlier version
	# read the hand's own current finger direction and corrected from there,
	# which compounds: next frame's "current" already includes this frame's
	# fudge, so the fudge doesn't get applied once, it gets applied again on
	# top of itself, every frame, forever. The two-bone solve above avoids
	# this the same way - desired_elbow - current_elbow is a delta to a
	# freshly *measured* target, not an accumulation.
	var barrel_world := get_barrel_direction()
	if barrel_world.length_squared() > 0.0001:
		var barrel_local: Vector3 = (into_skeleton.basis * barrel_world).normalized()
		var up_hint := Vector3.UP if absf(barrel_local.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
		var hand_x := barrel_local.cross(up_hint).normalized()
		var hand_z := hand_x.cross(barrel_local).normalized()
		var target_basis := Basis(hand_x, barrel_local, hand_z)
		var fudge := Basis.from_euler(support_hand_rotation_degrees * (PI / 180.0))
		_set_bone_global_basis(support_hand_index, fudge * target_basis)
		skeleton.force_update_all_bone_transforms()


## First person only (hip-fire and ADS both). The grip hand never needed IK
## before this: the weapon is bone-attached to GRIP_HAND_BONE, so hand and
## weapon are coincident by construction, same as third person always is.
## It only stops being coincident once _apply_first_person_weapon_hold() has
## pinned the weapon to the camera instead - without this, the hand would
## keep following its own animated pose while the gun it's supposedly
## holding sits locked in place a few centimetres away. No hand-rotation
## wrap the way the support hand gets - the grip hand's own animated grip
## pose already reads fine once its position is corrected; only the support
## hand ever needed a rebuilt-from-scratch rotation to stop draping over the
## barrel.
func _solve_grip_arm_ik() -> void:
	if world_model == null or grip_upper_index < 0:
		return
	if not (owner and bool(owner.get("is_first_person"))):
		return
	var into_skeleton := _into_skeleton_space()
	var target: Vector3 = into_skeleton * (world_model.global_transform * grip_in_mesh)
	_solve_two_bone_arm(grip_upper_index, grip_forearm_index, grip_hand_index, target)


## Bone poses are local to the parent, so a rotation worked out in skeleton space
## has to be brought back down through the parent to be applied.
func _set_bone_global_basis(bone_index: int, target_global_basis: Basis) -> void:
	var parent := world_model_skeleton.get_bone_parent(bone_index)
	var parent_basis := (
		world_model_skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	)
	world_model_skeleton.set_bone_pose_rotation(
		bone_index,
		(parent_basis.inverse() * target_global_basis).orthonormalized().get_rotation_quaternion()
	)


func _measure_local_bounds(model: Node3D) -> AABB:
	var combined := AABB()
	var found_any := false
	for mesh_node in NodeUtils.find_all_of_type(model, "MeshInstance3D"):
		var mesh_instance := mesh_node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var to_model: Transform3D = (
			model.global_transform.affine_inverse() * mesh_instance.global_transform
		)
		var mesh_bounds: AABB = mesh_instance.mesh.get_aabb()
		for corner_index in 8:
			var corner: Vector3 = mesh_bounds.position + Vector3(
				mesh_bounds.size.x * float(corner_index & 1),
				mesh_bounds.size.y * float((corner_index >> 1) & 1),
				mesh_bounds.size.z * float((corner_index >> 2) & 1)
			)
			var model_corner: Vector3 = to_model * corner
			if not found_any:
				combined = AABB(model_corner, Vector3.ZERO)
				found_any = true
			else:
				combined = combined.expand(model_corner)
	return combined


# ------------------------------------------------------------------- per frame


func _process(delta: float) -> void:
	_update_aim(delta)
	_update_recoil(delta)
	if not world_model_aligned and world_model:
		_align_world_model()
	# Before _apply_first_person_weapon_hold(), which reads
	# current_weapon.sight_nudge through sight_in_mesh to solve the ADS half
	# of the hold - so a live edit (Remote inspector, WeaponController's
	# Loadout array) shows up the same frame instead of needing a weapon
	# switch to re-trigger the one-time fit.
	_recompute_sight_in_mesh()
	# After the player's own _process, which pitches the spine and so moves the
	# shoulder the arms are solved from - parents process before children -
	# and after the sight recompute above, since it reads sight_in_mesh.
	# Before both arm solves below: first person pins world_model here
	# (hip-fire and ADS both), and both solves target wherever world_model
	# ends up this frame, not last frame's.
	_apply_first_person_weapon_hold(delta)
	_solve_support_arm_ik()
	_solve_grip_arm_ik()
	# Third person only now (see that function's own comment) - after both
	# arm solves for the same reason they run after the hold: needs the
	# weapon's fully resolved pose for this frame, not last frame's.
	_update_ads_sight_alignment(delta)
	# Last: reads get_sight_position(), which depends on everything above
	# having already settled for this frame.
	_update_debug_sight_marker()

	if fire_cooldown > 0.0:
		fire_cooldown -= delta

	# Mid-switch: the old weapon is being holstered (see equip_slot()'s own
	# comment) and the new one hasn't actually equipped yet, so there's
	# nothing to fire, reload, or switch away from further until it lands.
	if _pending_slot != -1:
		_switch_timer -= delta
		if _switch_timer <= 0.0:
			var slot := _pending_slot
			_pending_slot = -1
			_perform_equip_slot(slot)
		return

	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_finish_reload()
		return

	if current_weapon == null:
		return

	# Matches ordinary FPS convention, and asked for specifically alongside
	# the pistol sprint clip - see Player.is_sprinting's own comment.
	var sprinting: bool = bool(owner and owner.get("is_sprinting"))
	var wants_fire := (
		not sprinting
		and (
			Input.is_action_pressed("fire") if current_weapon.is_automatic
			else Input.is_action_just_pressed("fire")
		)
	)
	if wants_fire and fire_cooldown <= 0.0:
		_try_fire()

	if Input.is_action_just_pressed("reload"):
		_try_reload()

	_update_weapon_switching()


## Number keys pick a slot directly, the scroll wheel steps through. Ignored
## mid-reload so a switch can't be used to cancel one and keep the rounds.
func _update_weapon_switching() -> void:
	if is_reloading:
		return
	for slot in mini(loadout.size(), 9):
		if Input.is_action_just_pressed("weapon_slot_%d" % (slot + 1)):
			equip_slot(slot)
			return
	if Input.is_action_just_pressed("weapon_next"):
		cycle_weapon(1)
	elif Input.is_action_just_pressed("weapon_previous"):
		cycle_weapon(-1)


func _update_aim(delta: float) -> void:
	_set_aiming(
		current_weapon != null
		and not is_reloading
		and Input.is_action_pressed("aim")
	)
	aim_blend = move_toward(aim_blend, 1.0 if is_aiming else 0.0, delta * ads_transition_speed)
	if camera == null:
		return
	camera.fov = lerpf(
		camera.fov,
		ads_fov if is_aiming else hip_camera_fov,
		1.0 - exp(-ads_transition_speed * delta)
	)




## Applied to the camera rather than the head, so it stacks on top of the player's
## own look pitch without fighting the mouse for it.
func _update_recoil(delta: float) -> void:
	recoil_velocity += (
		-recoil_stiffness * recoil_offset - recoil_damping * recoil_velocity
	) * delta
	recoil_offset += recoil_velocity * delta
	if camera:
		camera.rotation.x = deg_to_rad(recoil_offset.x)
		camera.rotation.y = deg_to_rad(recoil_offset.y)


func _set_aiming(value: bool) -> void:
	if is_aiming == value:
		return
	is_aiming = value
	aim_changed.emit(is_aiming)


func get_mouse_sensitivity_multiplier() -> float:
	return ads_mouse_sensitivity_multiplier if is_aiming else 1.0


## Which way the weapon is actually pointing, in world space.
##
## Derived from barrel_in_mesh rather than from the model's local -Z, which stops
## being the barrel once _align_world_model has turned the weapon into the hand.
func get_barrel_direction() -> Vector3:
	if world_model == null:
		return Vector3.ZERO
	return (world_model.global_transform.basis * barrel_in_mesh).normalized()


## Where the weapon's own sight actually is right now, in world space. Used by
## _update_ads_sight_alignment to pull the camera onto it - see sight_in_mesh
## and WeaponData.sight_nudge for how the point itself is measured.
func get_sight_position() -> Vector3:
	if world_model == null:
		return camera.global_position if camera else Vector3.ZERO
	return world_model.global_transform * sight_in_mesh


## Re-applies current_weapon.sight_nudge to _sight_fit_base every frame (see
## that var's own comment) rather than only once at fit time, so dragging it
## live in the Remote inspector shows up immediately instead of needing a
## weapon switch to re-trigger the one-time fit.
func _recompute_sight_in_mesh() -> void:
	if current_weapon == null:
		return
	sight_in_mesh = _sight_fit_transform * (_sight_fit_base + current_weapon.sight_nudge)


## The game has no viewmodel - aiming down sights means nudging the real camera
## until the crosshair (dead centre of screen, along the camera's own -Z) lines
## up with the weapon's sight, instead of pulling a separate aim camera into
## place. Blended by aim_blend, so it fades in with the rest of ADS rather than
## snapping, and eases toward its target rather than tracking it exactly -
## both because a hard snap reads as a glitch and because the sight's position
## still jitters slightly frame to frame with the body's own animation.
##
## The nudge lands on _ads_offset_node (SpringArm3D) rather than the camera
## itself or CameraRig two levels up - see that var's comment for why both of
## those are already owned by something else.
##
## Third person only. First person used to share this - nudge the camera to
## close the gap - but that can't actually work once the weapon is following
## an animated bone: closing the gap moves the camera, which moves the
## (bone-attached) weapon by the same amount, so the gap never shrinks, it
## just gets chased every frame (confirmed by probe: the residual plateaued
## rather than converging, no matter how generous the clamp). First person
## now replaces the bone-driven hold outright during ADS instead
## (_apply_first_person_weapon_hold(), off ads_sight_target) rather than
## correcting it, which sidesteps the problem instead of solving it harder. Third
## person never had this issue - correcting the camera doesn't move a
## third-person weapon that isn't itself derived from the camera.
func _update_ads_sight_alignment(delta: float) -> void:
	if camera == null or _ads_offset_node == null:
		return
	var target_offset := Vector3.ZERO
	var first_person := owner and bool(owner.get("is_first_person"))
	if aim_blend > 0.001 and world_model != null and current_weapon != null and not first_person:
		var camera_origin := camera.global_position
		var camera_forward := -camera.global_transform.basis.z
		var to_sight := get_sight_position() - camera_origin
		var perp := to_sight - camera_forward * to_sight.dot(camera_forward)
		# Clamped rather than trusted outright - a weapon mid-switch or a spine
		# aim correction that hasn't converged yet could otherwise fling the
		# camera somewhere absurd for a frame.
		if perp.length() > ADS_SIGHT_CLAMP_THIRD_PERSON:
			perp = perp.normalized() * ADS_SIGHT_CLAMP_THIRD_PERSON
		target_offset = perp * aim_blend
	_ads_camera_offset = _ads_camera_offset.lerp(
		target_offset, 1.0 - exp(-ads_transition_speed * delta)
	)
	var offset_parent := _ads_offset_node.get_parent() as Node3D
	var offset_in_local_space := (
		offset_parent.global_transform.basis.inverse() * _ads_camera_offset if offset_parent
		else _ads_camera_offset
	)
	_ads_offset_node.position = _ads_offset_base_position + offset_in_local_space


# --------------------------------------------------------------- weapon logic


func _try_fire() -> void:
	if ammo_in_mag <= 0:
		return
	ammo_in_mag -= 1
	fire_cooldown = 1.0 / current_weapon.fire_rate
	_play_sound(current_weapon.fire_sound)
	_spawn_muzzle_flash()
	_hitscan()
	recoil_velocity += Vector2(
		recoil_pitch_degrees,
		recoil_yaw_degrees * randf_range(-1.0, 1.0)
	) * recoil_stiffness * 0.08
	fired.emit()
	ammo_changed.emit(ammo_in_mag, reserve_ammo)


## One trigger pull fires pellet_count rays (1 for everything but a shotgun),
## each independently jittered within pellet_spread_degrees of the crosshair
## and sharing the damage evenly - see WeaponData.pellet_count. A weapon with
## cone_kill_range set (the Thundergun) skips this entirely - see _fire_cone.
func _hitscan() -> void:
	if camera == null or current_weapon == null:
		return
	if current_weapon.cone_kill_range > 0.0:
		_fire_cone()
		return
	var pellets := maxi(current_weapon.pellet_count, 1)
	var pellet_damage := _effective_damage() / float(pellets)
	var camera_forward := -camera.global_transform.basis.z
	for i in pellets:
		var direction := (
			camera_forward if current_weapon.pellet_spread_degrees <= 0.0
			else _random_cone_direction(camera_forward, current_weapon.pellet_spread_degrees)
		)
		_fire_pellet(direction, pellet_damage)


## The Thundergun. Not a ray at all - every zombie within cone_kill_range and
## cone_kill_angle_degrees of the muzzle dies outright, full stop, no falloff.
## The original dealt 0 direct damage and killed through a knockback impulse
## that flung zombies off the map; this project's ragdoll never got past
## round 7 of tuning (see scripts/ai/CLAUDE.md) and currently plays a canned
## death animation instead of simulating one, so there's no impulse system to
## sell that with. A flat, enormous damage number gets the actual gameplay
## promise - anything this close in front of you is dead - without pretending
## to be physics it can't currently do.
##
## Aimed with camera_forward, not get_barrel_direction() - unlike every other
## weapon here, this one is gameplay-affecting on its direction (it decides
## who dies), and testing found the two-handed world-model alignment that
## get_barrel_direction() depends on can be unreliable for several frames
## after equipping (support-hand IK/alignment settling - the same system
## _apply_spine_aim() already only trusts loosely, see scripts/player/
## CLAUDE.md). The muzzle *position* still comes from the world model, purely
## for where the cone/tracer visually originates - only the direction needed
## the more reliable source.
func _fire_cone() -> void:
	if world_model == null or camera == null:
		return
	var muzzle := world_model.global_transform * muzzle_in_mesh
	var forward := -camera.global_transform.basis.z
	if forward.length_squared() < 0.0001:
		return
	var cos_half_angle := cos(deg_to_rad(current_weapon.cone_kill_angle_degrees))
	for target in get_tree().get_nodes_in_group("zombies"):
		if not (target is Node3D) or not target.has_method("take_damage"):
			continue
		if target.has_method("is_dead") and target.is_dead():
			continue
		var to_target: Vector3 = (target as Node3D).global_position - muzzle
		var distance := to_target.length()
		if distance < 0.001 or distance > current_weapon.cone_kill_range:
			continue
		if to_target.normalized().dot(forward) < cos_half_angle:
			continue
		var part: StringName = (
			target.classify_hit((target as Node3D).global_position)
			if target.has_method("classify_hit") else &"body"
		)
		target.take_damage(current_weapon.cone_kill_damage)
		var killed: bool = target.has_method("is_dead") and target.is_dead()
		hit_confirmed.emit(part, killed)
	_spawn_tracer(muzzle, muzzle + forward * current_weapon.cone_kill_range)


## A random direction within half_angle_degrees of forward, uniform over the
## cone's solid angle (not clustered toward its edge, which sampling theta
## linearly would do) - used to scatter shotgun pellets.
func _random_cone_direction(forward: Vector3, half_angle_degrees: float) -> Vector3:
	var up_hint := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.999 else Vector3.RIGHT
	var right := forward.cross(up_hint).normalized()
	var up := right.cross(forward).normalized()
	var half_angle := deg_to_rad(half_angle_degrees)
	var theta := acos(1.0 - randf() * (1.0 - cos(half_angle)))
	var phi := randf_range(0.0, TAU)
	return (forward * cos(theta) + (right * cos(phi) + up * sin(phi)) * sin(theta)).normalized()


## Fired in two stages, because the camera is behind the player rather than at
## their eye.
##
## First a ray from the camera finds what is actually under the crosshair - that's
## what the player is pointing at. Then the damaging shot is traced from the
## weapon to that point. Firing straight down the camera ray instead would start
## the shot metres behind the character and hit anything standing between the two,
## and would let the player shoot through a wall they're backed against.
func _fire_pellet(camera_forward: Vector3, pellet_damage: float) -> void:
	var space_state := camera.get_world_3d().direct_space_state
	# `owner` is the WeaponController's scene root - the Player CharacterBody3D it's
	# nested under in player.tscn. Excluded from both traces so the shooter's own
	# capsule can never be what stops the shot.
	var exclude: Array[RID] = []
	if owner and owner is CollisionObject3D:
		exclude = [owner.get_rid()]

	var camera_origin := camera.global_position
	var aim_point := camera_origin + camera_forward * current_weapon.weapon_range
	var sighting_query := PhysicsRayQueryParameters3D.create(camera_origin, aim_point)
	# A zombie's actual hitbox (PhysicsLayers.HITBOX) is a wider Area3D than
	# its movement capsule - see scripts/ai/zombie.gd's _setup_hitbox() - so
	# both traces need collide_with_areas or a shot aimed at a reaching arm
	# would sight past the zombie entirely.
	sighting_query.collide_with_areas = true
	var sighting := space_state.intersect_ray(sighting_query)
	if sighting:
		aim_point = sighting.position
	if sighting and sighting.has("rid") and exclude.has(sighting.rid):
		aim_point = camera_origin + camera_forward * current_weapon.weapon_range

	# From the muzzle when the weapon declares one, so shots leave the barrel
	# rather than the middle of the receiver.
	var muzzle := (
		world_model.global_transform * muzzle_in_mesh if world_model
		else camera_origin
	)
	# aim_point is the sighting ray's surface intersection - found from the
	# CAMERA's origin. This ray starts at the MUZZLE, a different point, so it
	# approaches that same coordinate from a different angle; a ray that
	# terminates exactly on a target's surface can numerically graze past the
	# volume it was aimed at instead of crossing into it (found by testing at
	# close range, where the angular difference between the two origins is
	# largest relative to the target's size - probe_round_loop.gd's shooting
	# check went from reliable to a coin-flip once the player's default
	# loadout and hitbox setup changed the exact numbers involved). Extending
	# a little past aim_point along the same line fixes it without needing the
	# two rays to agree on geometry they were never guaranteed to.
	var muzzle_to_aim := aim_point - muzzle
	var extended_aim_point := (
		aim_point + muzzle_to_aim.normalized() * 0.15
		if muzzle_to_aim.length_squared() > 0.0001
		else aim_point
	)
	# Penetration: the ray keeps going past a live zombie it hits (excluded
	# from there on, continuing from its hit point) up to penetration_count
	# more times. 0 - every weapon before this existed - stops at the first
	# hit, same as always: the loop below runs once and returns on its own
	# first non-continue path regardless. World geometry (or anything without
	# take_damage) always stops it outright, penetration or not - a wall
	# behind a zombie isn't supposed to get shot through too.
	#
	# The first segment's own endpoint is extended_aim_point - just past
	# whatever's actually under the crosshair, which is right for a single
	# target but far too short for a second one standing behind it (that 0.15m
	# overshoot exists to clear the FIRST target's own surface, not to reach a
	# second). Any penetrating segment after the first reaches instead for
	# camera_max_range, the undocked full weapon_range point computed before
	# the sighting ray potentially shortened aim_point to the first hit.
	var camera_max_range := camera_origin + camera_forward * current_weapon.weapon_range
	var segment_start := muzzle
	var segment_end := extended_aim_point
	var shots_left := current_weapon.penetration_count + 1
	while shots_left > 0:
		shots_left -= 1
		var query := PhysicsRayQueryParameters3D.create(segment_start, segment_end)
		query.exclude = exclude
		query.collide_with_areas = true
		var result := space_state.intersect_ray(query)
		# Drawn for every pellet/segment regardless of whether it connects - a
		# miss still has to leave the barrel and go somewhere, out to
		# extended_aim_point if nothing was actually in its way.
		_spawn_tracer(segment_start, result.position if result else extended_aim_point)
		if result and result.has("position"):
			_spawn_impact(result.position, result.get("normal", Vector3.UP))
		if not (result and result.has("collider")):
			return

		var target: Node = result.collider
		if not target.has_method("take_damage"):
			# A HitboxArea hit resolves to its owning Zombie, which is its parent.
			target = target.get_parent()
		if not (target and target.has_method("take_damage")):
			return
		# A target already dead from an earlier pellet in this same trigger pull
		# stays dead - take_damage on it is a no-op in zombie.gd, but without this
		# check every remaining pellet would still report killed=true and stack
		# up kill-bonus points for one kill. (A zombie already dead before this
		# shot was ever fired can't be hit at all any more - its hitbox comes
		# off PhysicsLayers.HITBOX on death, see zombie.gd's die().)
		if target.has_method("is_dead") and target.is_dead():
			return
		# Classified before the damage lands, because a zombie that dies to this shot
		# stops animating - and the head bone this is measured against moves when it
		# does. Asking afterwards would score the corpse's pose, not the shot.
		var part: StringName = (
			target.classify_hit(result.position) if target.has_method("classify_hit")
			else &"body"
		)
		target.take_damage(pellet_damage)
		var killed: bool = target.has_method("is_dead") and target.is_dead()
		hit_confirmed.emit(part, killed)

		if current_weapon.splash_radius > 0.0:
			_apply_splash_damage(result.position, target)
		if current_weapon.chain_count > 0:
			_apply_chain_damage(target, pellet_damage)

		if shots_left <= 0 or not result.has("rid"):
			return
		exclude.append(result.rid)
		segment_start = result.position
		segment_end = camera_max_range


## Damage tapering linearly from splash_damage at the impact point to 0 at
## splash_radius, applied to every other zombie in range - Ray Gun/Ray Gun
## Mark II/War Machine. Independent of the direct hit's own damage (War
## Machine deals 0 direct - every kill is the splash, never the primary hit -
## see WeaponData.splash_damage). The primary target already took its own hit
## above and is excluded here rather than double-dipped.
func _apply_splash_damage(origin: Vector3, primary_target: Node) -> void:
	var base_damage := current_weapon.splash_damage
	for target in get_tree().get_nodes_in_group("zombies"):
		if target == primary_target or not (target is Node3D) or not target.has_method("take_damage"):
			continue
		if target.has_method("is_dead") and target.is_dead():
			continue
		var distance: float = (target as Node3D).global_position.distance_to(origin)
		if distance > current_weapon.splash_radius:
			continue
		var splash_damage := base_damage * (1.0 - distance / current_weapon.splash_radius)
		if splash_damage <= 0.0:
			continue
		var part: StringName = (
			target.classify_hit((target as Node3D).global_position)
			if target.has_method("classify_hit") else &"body"
		)
		target.take_damage(splash_damage)
		var killed: bool = target.has_method("is_dead") and target.is_dead()
		hit_confirmed.emit(part, killed)


## Chain lightning - Wunderwaffe DG-2. Hops to the nearest not-yet-hit zombie
## within chain_radius of the last target struck, up to chain_count times,
## each hop dealing the same damage as the initial hit (the source data this
## was ported from has no separate falloff term for chained hits).
func _apply_chain_damage(primary_target: Node, damage: float) -> void:
	var hit_already := {primary_target: true}
	var from: Node3D = primary_target as Node3D
	for i in current_weapon.chain_count:
		var nearest: Node3D = null
		var nearest_distance := current_weapon.chain_radius
		for candidate in get_tree().get_nodes_in_group("zombies"):
			if hit_already.has(candidate) or not (candidate is Node3D):
				continue
			if not candidate.has_method("take_damage"):
				continue
			if candidate.has_method("is_dead") and candidate.is_dead():
				continue
			var distance: float = (candidate as Node3D).global_position.distance_to(from.global_position)
			if distance < nearest_distance:
				nearest = candidate
				nearest_distance = distance
		if nearest == null:
			break
		hit_already[nearest] = true
		var part: StringName = (
			nearest.classify_hit(nearest.global_position) if nearest.has_method("classify_hit")
			else &"body"
		)
		nearest.take_damage(damage)
		var killed: bool = nearest.has_method("is_dead") and nearest.is_dead()
		hit_confirmed.emit(part, killed)
		from = nearest


# ------------------------------------------------------------------------ vfx


const MUZZLE_FLASH_LIFETIME := 0.06
const TRACER_LIFETIME := 0.05
const IMPACT_LIFETIME := 0.35
## World metres, not the model's own scale - kept small since a tracer should
## read as a fast streak, not a beam.
const TRACER_RADIUS := 0.01

static var _glow_texture: GradientTexture2D


## A soft white circle, generated once and shared by every flash/spark rather
## than shipped as a texture asset. Deliberately primitives-and-generated-
## textures only, no new art: muzzle flash, tracers, and impact sparks are
## gameplay feedback this system already owned (see this file's own header
## comment), but new texture/model assets are ChatGPT's side of the project,
## not this session's.
static func _get_glow_texture() -> GradientTexture2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1.0, 0.5)
		_glow_texture.width = 32
		_glow_texture.height = 32
	return _glow_texture


func _unshaded_additive_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = color
	material.albedo_texture = _get_glow_texture()
	return material


## Brief light and glow at the muzzle - one per trigger pull, not one per
## pellet, so a shotgun blast reads as a single flash rather than eight.
## Parented under the tree root rather than the world model or the scene: the
## world model is bone-attached and would drag the flash along with the next
## frame's recoil/animation, and current_scene isn't guaranteed to be set in
## every context (e.g. a bare probe scene) the way the root always is.
func _spawn_muzzle_flash() -> void:
	if world_model == null or not is_inside_tree():
		return
	var origin := world_model.global_transform * muzzle_in_mesh
	var tree_root := get_tree().root

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.35)
	light.light_energy = 6.0
	light.omni_range = 4.0
	tree_root.add_child(light)
	light.global_position = origin
	_expire(light, MUZZLE_FLASH_LIFETIME)

	var sprite := Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture = _get_glow_texture()
	sprite.material_override = _unshaded_additive_material(Color(1.0, 0.8, 0.4))
	sprite.pixel_size = 0.01
	tree_root.add_child(sprite)
	sprite.global_position = origin
	_expire(sprite, MUZZLE_FLASH_LIFETIME)


## A thin streak from the muzzle to wherever the shot ended up, drawn for
## every pellet - a shotgun blast fans out into several short streaks rather
## than reading as one line.
func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	if not is_inside_tree():
		return
	var span := to - from
	var length := span.length()
	if length < 0.01:
		return

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(TRACER_RADIUS, TRACER_RADIUS, length)
	mesh.mesh = box
	mesh.material_override = _unshaded_additive_material(Color(1.0, 0.9, 0.6))
	get_tree().root.add_child(mesh)
	mesh.global_transform = Transform3D(
		Basis.looking_at(span.normalized(), Vector3.UP), from + span * 0.5
	)
	_expire(mesh, TRACER_LIFETIME)


## A brief spark burst where a shot actually lands - world geometry or a
## zombie alike, since either way something physical stopped the ray.
func _spawn_impact(at: Vector3, normal: Vector3) -> void:
	if not is_inside_tree():
		return

	var particles := GPUParticles3D.new()
	particles.amount = 10
	particles.lifetime = IMPACT_LIFETIME
	particles.one_shot = true
	particles.explosiveness = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	particles.draw_pass_1 = quad
	particles.material_override = _unshaded_additive_material(Color(1.0, 0.85, 0.5))

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = normal if normal.length_squared() > 0.0001 else Vector3.UP
	process_material.spread = 40.0
	process_material.initial_velocity_min = 1.5
	process_material.initial_velocity_max = 3.5
	process_material.gravity = Vector3(0.0, -9.8, 0.0)
	process_material.scale_min = 0.5
	process_material.scale_max = 1.0
	particles.process_material = process_material

	get_tree().root.add_child(particles)
	particles.global_position = at
	particles.emitting = true
	_expire(particles, IMPACT_LIFETIME + 0.1)


## Frees a spawned VFX node after lifetime seconds. Timed off the node's own
## tree rather than this controller's, since these deliberately outlive
## anything happening to the weapon - a reload or weapon switch shouldn't cut
## a tracer or muzzle flash short. process_always=false so pausing mid-shot
## freezes an in-flight tracer/flash instead of quietly expiring it under the
## pause menu.
func _expire(node: Node, lifetime: float) -> void:
	var timer := node.get_tree().create_timer(lifetime, false)
	timer.timeout.connect(node.queue_free)


# ---------------------------------------------------------------- debug


var _debug_sight_marker: MeshInstance3D
var _debug_target_marker: MeshInstance3D


## See debug_show_sight_marker's own comment for what the two spheres mean.
## Built lazily on first use rather than in _ready(), since most sessions
## will never turn this on; freed rather than just hidden once turned back
## off, so it doesn't sit around costing a draw call for the rest of the
## session on the (likely) chance it never gets turned on again.
func _update_debug_sight_marker() -> void:
	if not debug_show_sight_marker or world_model == null or camera == null:
		if _debug_sight_marker:
			_debug_sight_marker.queue_free()
			_debug_sight_marker = null
		if _debug_target_marker:
			_debug_target_marker.queue_free()
			_debug_target_marker = null
		return
	if _debug_sight_marker == null:
		_debug_sight_marker = _make_debug_marker(Color(0.2, 1.0, 0.3))
	if _debug_target_marker == null:
		_debug_target_marker = _make_debug_marker(Color(1.0, 0.6, 0.1))
	_debug_sight_marker.global_position = get_sight_position()
	_debug_target_marker.global_position = camera.global_transform * ads_sight_target


func _make_debug_marker(color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.015
	sphere.height = 0.03
	sphere.radial_segments = 12
	sphere.rings = 6
	marker.mesh = sphere
	marker.material_override = _unshaded_additive_material(color)
	get_tree().root.add_child(marker)
	return marker


func _try_reload() -> void:
	if is_reloading or ammo_in_mag >= _effective_mag_size() or reserve_ammo <= 0:
		return
	is_reloading = true
	_set_aiming(false)
	var duration := current_weapon.reload_time * reload_speed_multiplier
	reload_timer = duration
	_play_sound(current_weapon.reload_sound)
	reload_started.emit(duration)


func _finish_reload() -> void:
	var needed := _effective_mag_size() - ammo_in_mag
	var taken := mini(needed, reserve_ammo)
	ammo_in_mag += taken
	reserve_ammo -= taken
	is_reloading = false
	ammo_changed.emit(ammo_in_mag, reserve_ammo)


func _play_sound(stream: AudioStream) -> void:
	if stream == null:
		return
	audio_player.stream = stream
	audio_player.pitch_scale = randf_range(0.96, 1.04)
	audio_player.play()
