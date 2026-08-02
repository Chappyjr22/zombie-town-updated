extends CharacterBody3D
class_name Player

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.5
const CROUCH_SPEED := 2.2
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const CROUCH_LERP_SPEED := 10.0
const LOCOMOTION_BLEND_SPEED := 10.0
const STANCE_BLEND_SPEED := 8.0

## Target real-world duration for the holster/draw one-shots played on a weapon
## switch, whatever the raw Mixamo clip's own length happens to be - both get
## sped up (AnimationNodeTimeScale, same idiom as reload) to fit. Split
## unevenly because only the holster half is gameplay-blocking -
## WeaponController's _switch_timer waits on play_holster_animation()'s
## return value - while the draw half is purely cosmetic and keeps playing
## after the new weapon is already usable, so it can afford the larger share.
const HOLSTER_ANIMATION_DURATION := 1.2
const DRAW_ANIMATION_DURATION := 1.3

## Clips loaded over the soldier model's own at runtime, as loose Animation
## resources so the model itself is never rewritten. From Mixamo's Rifle 8-Way and
## Pistol/Handgun Locomotion Packs; see tools/build_clips.gd and LocomotionSets.
##
## The model's stock locomotion is mostly empty-handed - measured, its strafes
## carry the hands 0.04m above the hips against 0.43m for a weapon held ready, so
## stepping sideways dropped the rifle to the character's waist. The packs are
## weapon-held throughout, which also retires two workarounds: a sprint clip that
## had to be sourced separately because the model shipped none, and a strafe that
## had to be mirrored because Mixamo only sold one side.
##
## Every set is installed at startup and the blend tree is re-pointed when the
## weapon changes, rather than loading clips mid-game - a switch is a keypress and
## should not touch the disk.
const INSTALLED_SETS: Array[StringName] = [&"rifle", &"pistol"]
## Used until a weapon says otherwise, and the fallback if another set turns out
## to be missing clips.
const DEFAULT_SET := &"rifle"

## Spine bones the look pitch is spread across, lowest first. Sharing it over
## three joints curves the torso the way a person actually leans, where putting it
## all on one would visibly hinge the character in half.
const SPINE_PITCH_BONES: Array[StringName] = [
	&"mixamorig_Spine",
	&"mixamorig_Spine1",
	&"mixamorig_Spine2",
]

## What the first-person camera tracks - see _update_first_person_camera().
const FPS_HEAD_BONE := &"mixamorig_Head"

## Aim correction: how fast the torso eases into the measured error, and how far
## it is allowed to twist. Both exist because the correction moves the weapon it
## was measured from, so the loop needs damping and a ceiling.
const AIM_YAW_CORRECTION_SPEED := 0.25
## Third person only - a bounded amount so a bad reading twists the torso
## rather than spinning it, since the player can actually see this torso from
## outside. First person has no such ceiling to respect (see
## MAX_AIM_YAW_FIRST_PERSON) - found by probe while wiring up first-person
## ADS: aim_yaw was pinning at this exact clamp during ADS in first person
## (the camera's new head-height position needs more correction than
## third-person's over-the-shoulder one ever did) and staying pinned rather
## than settling, leaving the sight visibly misaligned from the crosshair
## for as long as ADS was held - not a slow convergence, a permanent
## steady-state error against a wall this low.
const MAX_AIM_YAW := deg_to_rad(40.0)
## First person: the player is looking out through the head, not at the
## torso from outside, so an extreme twist here costs nothing visually the
## way it would in third person - there's nothing for MAX_AIM_YAW's ceiling
## to protect. Not fully unclamped (PI) regardless, since the correction
## still cascades down the same arm chain the hands are posed from, and an
## extreme enough twist could plausibly contort the visible forearms/hands
## even if the spine itself is unseen. First guess, not eye-tuned - watch
## the arms specifically (not just the sight alignment) if this needs
## adjusting.
const MAX_AIM_YAW_FIRST_PERSON := deg_to_rad(90.0)

## How far the camera can be pitched. Tighter than a first-person limit: swinging
## a third-person camera to vertical puts it inside the floor or directly overhead.
const CAMERA_PITCH_MIN := deg_to_rad(-65.0)
const CAMERA_PITCH_MAX := deg_to_rad(40.0)

## Health comes back on its own after a lull, so a bad round isn't a run-ending
## injury - the pressure comes from being swarmed, not from chip damage you can
## never undo. Ported from the browser build: 5.5s clear of damage, then 10% of
## max per second.
const REGEN_DELAY := 5.5
const REGEN_FRACTION_PER_SECOND := 0.10

## Quick Revive (scripts/economy/perk_machine.gd). Solo play has no one to revive
## you, so going down with the perk owned self-revives on a timer instead of
## ending the game outright - going down without it is unchanged (permanent
## freeze, see take_damage). Invincible rather than making zombies path away
## during the window: simpler, and doesn't touch scripts/ai/zombie.gd at all.
const DOWNED_DURATION := 5.0
const REVIVE_HEALTH_FRACTION := 0.5
const REVIVE_INVINCIBILITY_DURATION := 4.0

@export var max_health: float = 100.0
## Off for test_arena.tscn's player instance - Esc there is meant to release
## the mouse for editor use, not open a menu mid-test. On (the default)
## everywhere else, including town.tscn.
@export var pause_enabled := true
## Mixamo authors this character facing +Z while Godot gameplay forward is -Z, so
## the body is turned to face the direction the player is aiming and moving.
@export var model_yaw_offset_degrees := 180.0
## How much of the camera pitch the torso follows, so the character visibly aims
## where the camera is pointed. Under 1.0 because a full match bends the spine
## further than a person would - a concern for someone watching this torso from
## third person, same as MAX_AIM_YAW's ceiling on the yaw side (see that
## const's own comment). First person uses spine_pitch_share_first_person
## instead, same reasoning as the yaw clamp: nothing about this torso is
## visible to the first-person player themselves, so there's nothing left for
## an incomplete match to protect, and a full 1.0 here was needed alongside
## the yaw fix to actually close ADS's sight-alignment residual - stopping
## short on pitch left the same kind of steady-state gap the yaw clamp did,
## just on the vertical axis instead of horizontal.
@export_range(0.0, 1.0, 0.05) var spine_pitch_share := 0.75
@export_range(0.0, 1.0, 0.05) var spine_pitch_share_first_person := 1.0
## How far back the camera sits normally, and while aiming. Pulling in over the
## shoulder to aim is the usual third-person shooter language for "aiming".
@export_range(0.5, 8.0, 0.1) var camera_distance := 3.0
@export_range(0.5, 8.0, 0.1) var camera_aim_distance := 1.4
@export_range(1.0, 30.0, 0.5) var camera_zoom_speed := 10.0
## How far right of the character's centreline the camera sits while aiming.
## Shrunk from the hip-fire offset (CameraRig's own authored X, ~0.45) rather
## than kept there: WeaponController's ADS sight-alignment nudge only
## translates the camera, and at ADS's close spring_length a translation big
## enough to cancel out the full hip-fire shoulder offset would be a bigger,
## more visible shift than shrinking the offset itself ahead of time. This is
## the shoulder pulling in toward the sight, not a separate system - the two
## are meant to be tuned together.
@export_range(0.0, 0.6, 0.01) var camera_aim_shoulder_offset := 0.15

## True first person - see toggle_perspective() and _update_camera_distance().
## Reuses the same world model/weapon everyone else sees rather than a
## separate viewmodel asset (see docs/ASSET_PIPELINE.md's "two character
## assets" section on why a viewmodel can't be carved from this model), so
## switching modes is purely a camera change, nothing about the body or
## weapon rig differs between the two.
var is_first_person := false
## Up from the live FPS_HEAD_BONE position to the camera, in first person -
## the bone sits at the neck/skull joint, not out at the eyes, so this is
## what actually reaches eye height. Applied fresh every frame in
## _update_first_person_camera(), on top of wherever the bone currently is -
## not a fixed offset from the capsule, which is what this used to be before
## it turned out not to track a sprinting body's own head movement. First
## guess, not eye-tuned yet - same live-tuning workflow as
## WeaponController.support_hand_rotation_degrees: select Player in the
## Remote scene tree while playing and drag this.
@export_range(0.0, 0.4, 0.01) var fps_eye_height_offset := 0.15
## How far in front of the live FPS_HEAD_BONE position the first-person
## camera sits. mixamo_soldier.glb is one skinned mesh with no separable head
## surface (see the probe run when this was built - checked before assuming
## a split-mesh/shader-based head-hide was on the table), so nothing can hide
## the skull from a camera placed at its centre the way a proper first-person
## rig normally would. Pushing the camera forward past the face is the cheap
## alternative: clears the skull for a forward-facing view, at the cost of
## still clipping into the mesh if the camera pitches to look straight down
## at the chest/collar. First guess, not eye-tuned.
@export_range(0.0, 0.3, 0.01) var fps_forward_offset := 0.16
## Left/right from the live FPS_HEAD_BONE position in first person - +X is
## the character's right (their own left is +X per the model-facing
## convention in scripts/player/locomotion_sets.gd's own header, but
## CameraRig isn't flipped by model_yaw_offset_degrees the way Model is, so
## this is simply screen-right for positive values). 0 is dead centre between
## the eyes; nudge it toward whichever eye/cheek the head bone actually sits
## under if centre reads off. First guess, not eye-tuned.
@export_range(-0.15, 0.15, 0.01) var fps_x_offset := 0.07

@onready var camera_rig: Node3D = $CameraRig
@onready var spring_arm: SpringArm3D = $CameraRig/SpringArm3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model: Node3D = $Model
@onready var camera: Camera3D = $CameraRig/SpringArm3D/Camera3D
@onready var anim_player: AnimationPlayer = NodeUtils.find_first_of_type(model, "AnimationPlayer")
@onready var weapon_controller: WeaponController = $CameraRig/SpringArm3D/Camera3D/WeaponController
@onready var hud: HUD = $HUD
@onready var crosshair: Crosshair = $HUD/Crosshair

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_crouching := false
var health: float
var is_dead := false
## True from a down (health hit 0 with Quick Revive owned) until the self-revive
## timer finishes. Distinct from is_dead: incapacitated but recoverable.
var is_downed := false
## True during the post-revive grace window - see REVIVE_INVINCIBILITY_DURATION.
var is_invincible := false
## Perks owned this session, granted by scripts/economy/perk_machine.gd. Never
## reset between rounds (RoundDirector doesn't touch player state), matching
## how perks work in the game this is based on - they last until you die.
var perks: Dictionary = {}
## Stamin-Up multiplies this instead of the WALK/SPRINT/CROUCH speed consts
## directly, since those are shared constants, not per-player state.
var speed_multiplier := 1.0
## Spendable currency, earned by hitting and killing zombies. The buy systems -
## wall weapons, the mystery box, map gates - all price against this. Starts at
## 500 rather than 0 - enough for a first ammo buy or a start toward a wall
## weapon before any points have been earned. A one-time game-start amount,
## not a per-round refill: RoundDirector never resets player state between
## rounds (see its own CLAUDE.md), so this only ever applies once.
var points := 500
## Power-up drops (scripts/economy/power_up_drop.gd), ported from
## zombie-town-online's DROPS/buffs. Timed buffs count down in _process()
## rather than needing their own timers/signals - matches the source's own
## `for(const k in buffs) if(buffs[k]>0) buffs[k]=Math.max(0,buffs[k]-dt)`.
## Not reset between rounds, same as points/perks above.
const POWER_UP_DURATION := 30.0
var instakill_remaining := 0.0
var doublepoints_remaining := 0.0
var firesale_remaining := 0.0

## Every Interactable (scripts/economy/interactable.gd) the player is currently
## standing inside the range of. Nearest one gets the HUD prompt and the
## "interact" keypress - see _update_interaction().
var _nearby_interactables: Array = []
var _current_interactable: Node = null
var time_since_damaged := 0.0
var was_on_floor := true
var active_full_body_animation: StringName = &""
var airborne_animation: StringName = &""
var animation_tree: AnimationTree
var body_skeleton: Skeleton3D
## Yaw the torso is currently twisted by to bring the weapon onto the crosshair.
var aim_yaw := 0.0
var animation_blend_tree: AnimationNodeBlendTree
var fire_animation_node: AnimationNodeAnimation
var draw_animation_node: AnimationNodeAnimation
var draw_shot_node: AnimationNodeOneShot
var holster_animation_node: AnimationNodeAnimation
var holster_shot_node: AnimationNodeOneShot
## True once a weapon has actually been equipped through _on_weapon_changed, as
## opposed to _ready()'s catch-up call for the starting weapon - see that
## function's comment.
var _has_equipped_weapon := false
## CameraRig's authored hip-fire X offset, captured once - _update_camera_distance
## lerps camera_rig.position.x back to this when not aiming.
var _camera_rig_hip_x := 0.0
var locomotion_blend := Vector2.ZERO
var sprint_blend := 0.0
## Set every physics frame in _physics_process(). WeaponController reads this
## to refuse firing while sprinting (owner.is_sprinting - same direct-query
## pattern as has_instakill()) - matches ordinary FPS convention, and the
## rifle set already released spine-aim during a sprint for a related reason
## (see _apply_spine_aim's own comment), so the gun visually swinging loose
## while sprinting was already true before this made it also unfireable.
var is_sprinting := false
var stance_blend := 0.0
## Locomotion set the body is currently carrying its weapon with.
var current_set: StringName = DEFAULT_SET
## Whether that set has sprint clips of its own. When it doesn't, sprinting stays
## on the normal tier and the stride is sped up to match instead.
var set_has_sprint := true
## Every blend point in the three blend squares, as `{node, tier, key}`, so a
## weapon switch re-points them at another set's clips. `tier` is empty for the
## squares' centre idles, whose key indexes the set definition directly.
var blend_points: Array[Dictionary] = []
## Set while the landing clip plays, so locomotion doesn't cut it off. A flag
## rather than a test against the clip's name, because a set may use one clip for
## more than one thing - the pistol pack has a single jump.
var is_playing_landing := false

signal health_changed(current: float, max: float)
signal points_changed(total: int, delta: int)
signal died
signal downed(duration: float)
signal revived
signal interactable_changed(prompt_text: String) ## empty string means "hide the prompt"
signal paused_changed(is_paused: bool)
signal perk_granted(key: StringName)
signal perspective_changed(is_first_person: bool)


func _ready() -> void:
	# Everything this script does to bones - the head scale, the spine pitch - is
	# overwritten if the AnimationTree runs after it, and by default it does: it's
	# added as a child at runtime, and children process after their parent. Higher
	# priority means later, so this orders the frame as
	# AnimationTree -> player -> WeaponController's support-arm IK.
	process_priority = 10
	_camera_rig_hip_x = camera_rig.position.x
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health = max_health
	add_to_group("player")
	collision_layer = PhysicsLayers.ACTORS
	# WORLD only, not ACTORS - deliberately one-way. zombie.gd keeps ACTORS in
	# its own mask, so a zombie still can't walk through the player or through
	# each other. But move_and_slide()'s push comes from whichever body is
	# doing the resolving: with both sides checking ACTORS, the player's own
	# move_and_slide was resolving against every overlapping zombie capsule
	# every physics frame, and a horde converging from multiple directions
	# could ratchet that into real displacement - measured at 167m over one
	# probe run. Dropping ACTORS here means the player never runs that
	# resolution at all, so a crowd can visually crowd the player (capsules
	# may overlap) but can never shove it. Zombies remain solid to the player
	# from the zombie's own side, so walking into one from a standstill still
	# meets resistance - it just can't compound as your own solver's fight.
	collision_mask = PhysicsLayers.WORLD
	model.rotation_degrees.y = model_yaw_offset_degrees
	body_skeleton = NodeUtils.find_first_of_type(model, "Skeleton3D") as Skeleton3D
	# The arm only needs to stop at walls, not at the player or at zombies - it
	# would otherwise slam the camera forward every time something walked behind.
	spring_arm.collision_mask = PhysicsLayers.WORLD
	spring_arm.spring_length = camera_distance
	if anim_player:
		_install_extra_clips()
		_configure_animation_loops()
		anim_player.animation_finished.connect(_on_animation_finished)
		_setup_animation_tree()
	if weapon_controller:
		weapon_controller.fired.connect(_on_weapon_fired)
		weapon_controller.reload_started.connect(_on_reload_started)
		weapon_controller.weapon_changed.connect(_on_weapon_changed)
		weapon_controller.hit_confirmed.connect(_on_hit_confirmed)
		# The starting weapon is equipped in WeaponController._ready(), which runs
		# before this - children are readied first - so that first weapon_changed
		# was already missed and the stance has to be caught up on by hand.
		_on_weapon_changed(weapon_controller.current_weapon, weapon_controller.current_slot)
		# Unconditional: without it the body holds nothing, so other players would
		# see an unarmed soldier miming a rifle once multiplayer exists.
		weapon_controller.attach_world_model(body_skeleton, &"mixamorig_RightHand")
	# The HUD binds itself to both and owns every readout from there, so gameplay
	# never has to know what's on screen.
	hud.bind_player(self, weapon_controller)
	health_changed.emit(health, max_health)
	# Catches up the points display on the starting 500, same reason
	# health_changed is emitted here - the HUD only updates from signals, and
	# without this it would sit on the scene's placeholder "0" text until the
	# first point is earned.
	points_changed.emit(points, points)


## Reapplied every frame because the AnimationTree rewrites the bone poses each
## time it runs - see the process_priority note in _ready.
func _process(delta: float) -> void:
	_apply_spine_aim()
	_update_camera_distance(delta)
	_update_first_person_camera()
	_update_regen(delta)
	_update_interaction()
	instakill_remaining = maxf(0.0, instakill_remaining - delta)
	doublepoints_remaining = maxf(0.0, doublepoints_remaining - delta)
	firesale_remaining = maxf(0.0, firesale_remaining - delta)


## True while movement/actions should be locked out - dead or downed. Kept
## separate from is_invincible, which only blocks damage: a player who just
## finished reviving should be able to move and shoot immediately.
func _is_incapacitated() -> bool:
	return is_dead or is_downed


## Picks the nearest in-range Interactable (scripts/economy/interactable.gd),
## tells the HUD about it if it changed, and fires it on an "interact" press.
## Interactables register themselves via their own Area3D body_entered/exited
## rather than the player scanning for them, so this is just a pick-nearest
## over an already-short list.
func _update_interaction() -> void:
	var nearest: Node = null
	var nearest_dist := INF
	for interactable in _nearby_interactables:
		if not is_instance_valid(interactable):
			continue
		var d := global_position.distance_to(interactable.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = interactable
	if nearest != _current_interactable:
		_current_interactable = nearest
		interactable_changed.emit(nearest.prompt_text(self) if nearest else "")
	if nearest and not _is_incapacitated() and Input.is_action_just_pressed("interact"):
		nearest.attempt_purchase(self)
		# Cost or ownership may have just changed what the prompt should say.
		interactable_changed.emit(nearest.prompt_text(self))


func register_interactable(interactable: Node) -> void:
	if not _nearby_interactables.has(interactable):
		_nearby_interactables.append(interactable)


func unregister_interactable(interactable: Node) -> void:
	_nearby_interactables.erase(interactable)
	if _current_interactable == interactable:
		_current_interactable = null
		interactable_changed.emit("")


## Heals back to full once the player has been out of trouble long enough. The
## delay is the whole mechanic - it rewards breaking contact, which is what makes
## kiting a round the right way to play it.
func _update_regen(delta: float) -> void:
	if is_dead or health >= max_health:
		return
	time_since_damaged += delta
	if time_since_damaged < REGEN_DELAY:
		return
	health = minf(max_health, health + max_health * REGEN_FRACTION_PER_SECOND * delta)
	health_changed.emit(health, max_health)


## Pulls the camera in over the shoulder while aiming and lets it back out
## again - and, on the same lerp, shrinks the shoulder offset itself. Only X:
## Y is owned by _update_crouch and, in first person, X/Y/Z both end up owned
## by _update_first_person_camera() instead - see that function's own comment
## for why. spring_length is the one part of this still shared across both
## perspectives: first person collapses it to (near) zero, putting the camera
## at CameraRig's own origin instead of on a boom behind it, which
## _update_first_person_camera() then repositions off the head bone.
func _update_camera_distance(delta: float) -> void:
	var aiming := weapon_controller != null and weapon_controller.is_aiming
	var t := 1.0 - exp(-camera_zoom_speed * delta)
	spring_arm.spring_length = lerpf(
		spring_arm.spring_length,
		0.0 if is_first_person else (camera_aim_distance if aiming else camera_distance),
		t
	)
	if is_first_person:
		return
	camera_rig.position.x = lerpf(
		camera_rig.position.x,
		camera_aim_shoulder_offset if aiming else _camera_rig_hip_x,
		t
	)
	camera_rig.position.z = lerpf(camera_rig.position.z, 0.0, t)


## Overrides camera_rig.position (all three axes) in first person, off the
## live head bone rather than a fixed offset from the capsule.
##
## The first version used a fixed capsule-relative offset, the same way
## _update_crouch's third-person Y always has - simpler, and avoids coupling
## the camera to whatever a locomotion clip happens to be doing with the
## head/neck. That was also the problem: a fixed offset only lines up with
## the actual head while the body is roughly in its idle pose. The rifle
## sprint clip in particular swings the whole upper body well off that
## (`scripts/player/CLAUDE.md`'s "rifle set's sprint is empty-handed" gap
## covers the same clip's arm swing for a different reason), and a camera
## that hasn't moved with it looks like it's clipped *out* through the face
## and chest instead of staying enveloped. Tracking the bone directly means
## the camera moves exactly as far as the head mesh does, every frame,
## whatever clip is currently blended in - so they stay coincident instead of
## agreeing only at a rest pose.
##
## fps_eye_height_offset/fps_forward_offset/fps_x_offset are still applied on
## top, now as a small nudge off the bone (which sits at the neck/skull
## joint, not out at the eyes) rather than off the capsule top - the same
## three tuned values carry over, they just mean something slightly
## different now.
##
## No lerp: the head bone's own position is already smoothed by whatever
## animation is blended in, and trailing a second lerp behind an already-
## moving target would lag the camera behind fast motion (a sprint's own bob
## cycle) instead of fixing that. Toggling into first person snaps straight
## to the head bone's current position rather than easing in, which is the
## one small cost - a same-frame pop when pressing the key, not a lag while
## already moving.
func _update_first_person_camera() -> void:
	if not is_first_person or body_skeleton == null:
		return
	var head_index := body_skeleton.find_bone(FPS_HEAD_BONE)
	if head_index < 0:
		return
	var head_world: Vector3 = (
		body_skeleton.global_transform * body_skeleton.get_bone_global_pose(head_index)
	).origin
	camera_rig.position = to_local(head_world) + Vector3(
		fps_x_offset, fps_eye_height_offset, -fps_forward_offset
	)


## Leans the torso with the look pitch, so the weapon the hands are holding tracks
## up and down with the crosshair.
##
## Without it the body aims wherever the clip was authored to aim, and since the
## shot itself comes from the camera, the weapon visibly disagrees with where the
## bullets go. Applied about the skeleton's own X axis rather than each bone's,
## because Mixamo's per-bone axes point in whatever direction they were authored,
## and spread over three joints so the character curves rather than hinging.
##
## Yaw closes the gap between where the weapon points and where the camera looks.
## The weapon's direction comes from `_align_world_model()`, which lays it along
## the line between the character's hands - so it swings off to one side as soon
## as a movement clip changes that line. Shots are unaffected either way (they
## trace from the camera), but a weapon visibly pointing somewhere else is worse
## than a slightly overturned torso.
func _apply_spine_aim() -> void:
	if body_skeleton == null or _is_incapacitated():
		return
	var active_pitch_share := (
		spine_pitch_share_first_person if is_first_person else spine_pitch_share
	)
	var pitch_share := (
		-spring_arm.rotation.x * active_pitch_share / float(SPINE_PITCH_BONES.size())
	)
	# Unwound while sprinting rather than corrected. The sprint clip swings both
	# arms, so the weapon follows a swinging hand and closing the gap would need
	# about 70 degrees of twist - it just pins at the clamp and the character runs
	# hunched. You aren't aiming mid-sprint anyway, so the torso is let go instead.
	var target := 0.0 if sprint_blend > 0.5 else aim_yaw + _measure_aim_yaw_error()
	# Eased, because the correction turns the weapon the error was measured from.
	# Clamped, so a bad reading twists the torso a bounded amount rather than
	# spinning it - which is exactly what happened the first time this was tried.
	# The bound itself is perspective-dependent - see MAX_AIM_YAW_FIRST_PERSON's
	# own comment.
	var max_yaw := MAX_AIM_YAW_FIRST_PERSON if is_first_person else MAX_AIM_YAW
	aim_yaw = clampf(
		lerpf(aim_yaw, target, AIM_YAW_CORRECTION_SPEED),
		-max_yaw,
		max_yaw
	)
	var yaw_share := aim_yaw / float(SPINE_PITCH_BONES.size())
	if is_zero_approx(pitch_share) and is_zero_approx(yaw_share):
		return

	for bone_name in SPINE_PITCH_BONES:
		var bone_index := body_skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var parent := body_skeleton.get_bone_parent(bone_index)
		var parent_basis := (
			body_skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
		)
		var posed := (
			Basis(Vector3.UP, yaw_share)
			* Basis(Vector3.RIGHT, pitch_share)
			* body_skeleton.get_bone_global_pose(bone_index).basis
		)
		body_skeleton.set_bone_pose_rotation(
			bone_index,
			(parent_basis.inverse() * posed).orthonormalized().get_rotation_quaternion()
		)


## Signed horizontal angle from where the weapon points to where the camera looks.
##
## The barrel comes from `WeaponController.get_barrel_direction()`, which measures
## it off the weapon's own geometry. Taking the model's local -Z instead is what
## sank the first attempt at this - that axis stops being the barrel once the
## weapon has been turned into the hand.
func _measure_aim_yaw_error() -> float:
	if weapon_controller == null:
		return 0.0
	var barrel := weapon_controller.get_barrel_direction()
	var view := -camera.global_transform.basis.z
	barrel.y = 0.0
	view.y = 0.0
	if barrel.length_squared() < 0.0001 or view.length_squared() < 0.0001:
		return 0.0
	return barrel.normalized().signed_angle_to(view.normalized(), Vector3.UP)


## Loads every locomotion set's clips over the soldier model's own.
##
## Which files to load comes from LocomotionSets rather than from a directory
## scan: exported builds turn loose `.res` files into `.remap`, so scanning works
## in the editor and quietly finds nothing in a shipped game.
##
## Clips are installed under set-namespaced names because the packs collide - both
## contain an "idle" - and because holding both in the library at once is what
## makes a weapon switch a matter of re-pointing the tree.
##
## Missing clips are skipped rather than fatal: the model's own animations still
## play, they just read worse than the pack's.
func _install_extra_clips() -> void:
	var library := anim_player.get_animation_library(&"")
	for locomotion_set in INSTALLED_SETS:
		var paths := LocomotionSets.clip_paths(locomotion_set)
		var missing := 0
		for clip_name in paths:
			if not ResourceLoader.exists(paths[clip_name]):
				missing += 1
				continue
			if library.has_animation(clip_name):
				library.remove_animation(clip_name)
			library.add_animation(clip_name, load(paths[clip_name]))
		if missing > 0:
			push_warning(
				(
					"%d of the %d '%s' locomotion clips are missing; run"
					+ " `godot --headless --path . --script tools/build_clips.gd -- %s`."
				) % [missing, paths.size(), locomotion_set, locomotion_set]
			)
		# Optional and outside the missing-clips warning above: a set with no draw
		# clip yet just keeps its instant weapon swap - see _on_weapon_changed.
		var draw_path := LocomotionSets.draw_clip_path(locomotion_set)
		var draw_name := LocomotionSets.draw_clip_installed_name(locomotion_set)
		if draw_path != "" and ResourceLoader.exists(draw_path):
			if library.has_animation(draw_name):
				library.remove_animation(draw_name)
			library.add_animation(draw_name, load(draw_path))
		# Same, for the outgoing weapon's holster one-shot - see
		# play_holster_animation().
		var holster_path := LocomotionSets.holster_clip_path(locomotion_set)
		var holster_name := LocomotionSets.holster_clip_installed_name(locomotion_set)
		if holster_path != "" and ResourceLoader.exists(holster_path):
			if library.has_animation(holster_name):
				library.remove_animation(holster_name)
			library.add_animation(holster_name, load(holster_path))


## Turns a confirmed hit into points. The award scales with the round, so the
## rate the economy pays keeps up with what zombies cost to kill - see
## RoundDirector.points_for_hit.
func _on_hit_confirmed(part: StringName, killed: bool) -> void:
	var director := get_tree().get_first_node_in_group("round_director") as RoundDirector
	var round_number: int = director.current_round if director else 1
	award_points(RoundDirector.points_for_hit(round_number, part, killed))


func award_points(amount: int) -> void:
	if amount == 0:
		return
	if doublepoints_remaining > 0.0:
		amount *= 2
	points += amount
	points_changed.emit(points, amount)


## Read by WeaponController - see its own comment at the call site - rather
## than exposing the raw timer, so the "what counts as active" threshold
## lives in exactly one place.
func has_instakill() -> bool:
	return instakill_remaining > 0.0


## Used by every economy purchase (scripts/economy/*.gd). Refuses rather than
## going negative - callers are expected to check affordability via
## Interactable._can_interact() before calling this, this is the enforcement.
func spend_points(amount: int) -> bool:
	if amount <= 0 or points < amount:
		return false
	points -= amount
	points_changed.emit(points, -amount)
	return true


## One-time grant from scripts/economy/perk_machine.gd. Perks that adjust an
## ongoing rate (reload speed, move speed, damage) are read from `perks`/
## `speed_multiplier` at the point of use rather than applied here, so nothing
## needs undoing if perks were ever lost - Juggernog's health boost is the one
## exception, since "how much max health you have" has nowhere else to live.
func grant_perk(key: StringName) -> void:
	if perks.get(key, false):
		return
	perks[key] = true
	if key == &"jugg":
		max_health = 250.0
		health = max_health
		health_changed.emit(health, max_health)
	perk_granted.emit(key)


func take_damage(amount: float) -> void:
	if is_dead or is_downed or is_invincible:
		return
	health -= amount
	time_since_damaged = 0.0
	health_changed.emit(health, max_health)
	if health <= 0.0:
		if perks.get(&"revive", false):
			_go_down()
		else:
			_die()
	# No hit reaction. The clip is a full-body flinch that interrupts whatever the
	# player was doing - aiming, sprinting - and taking control away every time a
	# zombie connects feels worse than showing nothing. Damage feedback belongs on
	# the HUD instead.


func _die() -> void:
	is_dead = true
	hud.visible = false
	airborne_animation = &""
	_play_full_body_animation([&"death"], 1.0, true)
	died.emit()
	# TODO: no death/respawn flow yet - player just stops taking further damage.


## Quick Revive's actual effect - see the const block up top for why this
## exists instead of just dying. Movement/fire/reload are locked out via
## _is_incapacitated(); health regen (_update_regen) also checks is_dead only,
## not is_downed, but that's harmless - health is about to be overwritten by
## _finish_revive() regardless of what regen does to it in the meantime.
func _go_down() -> void:
	is_downed = true
	airborne_animation = &""
	# No dedicated downed/crawl clip exists on this model (checked
	# ASSET_MANIFEST.md - only the zombie models ship one). crouch_idle is the
	# closest held pose available and isn't configured to loop, so it plays
	# once and holds on its last frame - which is what a static "down" pose
	# needs anyway.
	_play_full_body_animation([&"crouch_idle"], 1.0, true)
	downed.emit(DOWNED_DURATION)
	# process_always=false - SceneTreeTimer defaults to counting through a
	# pause, which would auto-revive a downed player while they're sitting in
	# the pause menu instead of waiting for them to resume.
	get_tree().create_timer(DOWNED_DURATION, false).timeout.connect(_finish_revive)


func _finish_revive() -> void:
	is_downed = false
	active_full_body_animation = &""
	health = max_health * REVIVE_HEALTH_FRACTION
	# Otherwise regen (_update_regen) could start topping this up immediately -
	# time_since_damaged has been counting since the original hit that caused
	# the down, which by DOWNED_DURATION later is usually already past
	# REGEN_DELAY.
	time_since_damaged = 0.0
	health_changed.emit(health, max_health)
	is_invincible = true
	revived.emit()
	get_tree().create_timer(REVIVE_INVINCIBILITY_DURATION, false).timeout.connect(
		func() -> void: is_invincible = false
	)


## Pauses/unpauses the whole SceneTree - which is what actually freezes
## zombies, the round timer, and every other node's default process_mode,
## with no per-system changes needed. HUD's PauseOverlay (and only that
## overlay - see hud.tscn) is set to PROCESS_MODE_ALWAYS so its own buttons
## stay clickable while everything else is frozen.
func _set_paused(value: bool) -> void:
	get_tree().paused = value
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if value else Input.MOUSE_MODE_CAPTURED
	paused_changed.emit(value)


## Called by HUD's Resume button - see _set_paused for why toggling
## get_tree().paused is what this actually needs to do.
func resume() -> void:
	_set_paused(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity := MOUSE_SENSITIVITY
		if weapon_controller:
			sensitivity *= weapon_controller.get_mouse_sensitivity_multiplier()
		# Yaw turns the body, not the camera. The character always faces where the
		# camera looks, which is what makes the directional walk/strafe blend space
		# meaningful and keeps shots going where the crosshair is.
		rotate_y(-event.relative.x * sensitivity)
		spring_arm.rotate_x(-event.relative.y * sensitivity)
		spring_arm.rotation.x = clampf(
			spring_arm.rotation.x,
			CAMERA_PITCH_MIN,
			CAMERA_PITCH_MAX
		)
	elif event.is_action_pressed("ui_cancel"):
		if not pause_enabled:
			# test_arena.tscn only - Esc just releases the mouse for editor use
			# (the pre-pause-menu behavior), not the actual pause menu, so a
			# test session isn't interrupted by a menu every time the cursor
			# needs freeing.
			var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED
			return
		# Game over already released the mouse and shows its own overlay -
		# pausing on top of that would just be a second menu fighting the first.
		if is_dead:
			return
		_set_paused(not get_tree().paused)
	elif event.is_action_pressed("toggle_perspective"):
		toggle_perspective()


## Bound to toggle_perspective (V). A plain assignment would do the same
## thing, but the HUD needs to know too - crosshair.gd hides the reticle
## while aiming in first person, since the weapon's own sight is the aim
## reference at that point, not a screen-centre dot (see
## _update_ads_sight_alignment() in scripts/weapons/weapon_controller.gd for
## the nudge that actually lines the camera up with it).
func toggle_perspective() -> void:
	is_first_person = not is_first_person
	perspective_changed.emit(is_first_person)


func _physics_process(delta: float) -> void:
	if _is_incapacitated():
		velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED * delta)
		velocity.z = move_toward(velocity.z, 0.0, WALK_SPEED * delta)
		if not is_on_floor():
			velocity.y -= gravity * delta
			move_and_slide()
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = JUMP_VELOCITY

	_update_crouch(delta)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	is_sprinting = (
		not is_crouching
		and Input.is_action_pressed("sprint")
		and input_dir.y < 0.0
	)
	var speed := WALK_SPEED
	if is_crouching:
		speed = CROUCH_SPEED
	elif is_sprinting:
		speed = SPRINT_SPEED
	speed *= speed_multiplier

	if move_dir.length() > 0.0:
		velocity.x = move_dir.x * speed
		velocity.z = move_dir.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

	var just_landed := is_on_floor() and not was_on_floor
	was_on_floor = is_on_floor()
	var movement_amount := clampf(
		Vector2(velocity.x, velocity.z).length() / SPRINT_SPEED,
		0.0,
		1.0
	)
	crosshair.set_movement_amount(movement_amount)
	_update_animation(delta, just_landed, input_dir)


func _update_crouch(delta: float) -> void:
	is_crouching = Input.is_action_pressed("crouch")
	var target_height := CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	var shape: CapsuleShape3D = collision_shape.shape
	shape.height = move_toward(shape.height, target_height, CROUCH_LERP_SPEED * delta)
	collision_shape.position.y = shape.height / 2.0
	# The rig rides the capsule so crouching lowers the camera with the character.
	# Only Y - X is the over-the-shoulder offset that keeps the character out of
	# the middle of the screen, and it has to stay put.
	#
	# Skipped outright in first person, not just left to be overwritten:
	# _update_first_person_camera() owns camera_rig.position there instead (all
	# three axes, off the live head bone - see that function's own comment for
	# why a fixed offset like this one couldn't track a sprinting body's own
	# head movement). This runs on the physics tick, that one on the idle tick
	# - two different clocks - so "runs later in the same frame, so it wins"
	# doesn't hold the way it would if both were on the same one. Actually
	# leaving this write in was found racing the other function directly: this
	# would win on whichever tick happened to land last, which is why ADS's
	# sight alignment (reading camera_rig's position through the camera)
	# measured an erratically growing residual instead of converging smoothly
	# - not a bug in the alignment math itself, this was fighting it for the
	# property underneath.
	if is_first_person:
		return
	camera_rig.position.y = shape.height - 0.3


func _update_animation(
	delta: float,
	just_landed: bool,
	input_dir: Vector2
) -> void:
	if anim_player == null:
		return
	# Death/downed hold the body, and the landing clip is allowed to finish
	# before locomotion takes back over.
	if _is_incapacitated() or is_playing_landing:
		return
	if not is_on_floor():
		# Tracked by key rather than by clip name, because a set may use one clip
		# for more than one of these - the pistol pack has a single jump.
		var desired_air_animation: StringName = (
			&"jump_up" if velocity.y > 0.0 else &"jump_loop"
		)
		if desired_air_animation != airborne_animation:
			airborne_animation = desired_air_animation
			_play_full_body_animation([_set_clip(desired_air_animation)], 1.0, true)
		return
	if just_landed:
		airborne_animation = &""
		is_playing_landing = true
		_play_full_body_animation([_set_clip(&"jump_down")], 1.0, true)
		return
	if active_full_body_animation != &"":
		return
	_set_animation_tree_active(true)
	_update_locomotion_blend(delta, input_dir)


## The installed name of one of the current set's clips - `idle`, `crouch_idle`,
## `jump_up`, `jump_loop` or `jump_down`.
func _set_clip(key: StringName) -> StringName:
	return LocomotionSets.installed_name(current_set, LocomotionSets.get_set(current_set)[key])


func _find_animation(names: Array) -> StringName:
	for requested_name in names:
		if anim_player.has_animation(requested_name):
			return requested_name
		for available_name in anim_player.get_animation_list():
			if (
				available_name == requested_name
				or available_name.ends_with("|" + String(requested_name))
			):
				return available_name
	return &""


func _configure_animation_loops() -> void:
	for requested_name in _looping_clip_names():
		var loop_animation := _find_animation([requested_name])
		if loop_animation != &"":
			anim_player.get_animation(loop_animation).loop_mode = Animation.LOOP_LINEAR
	var one_shots: Array[StringName] = [&"fire", &"fire_move", &"reload", &"death"]
	for locomotion_set in INSTALLED_SETS:
		var definition := LocomotionSets.get_set(locomotion_set)
		one_shots.append(LocomotionSets.installed_name(locomotion_set, definition.jump_up))
		one_shots.append(LocomotionSets.installed_name(locomotion_set, definition.jump_down))
		# Raw Mixamo imports for draw/holster come in LOOP_LINEAR like every other
		# clip in the pack, but these two play inside a one-shot node
		# (DrawShot/HolsterShot), not the locomotion blend - a one-shot only
		# fades back out once the animation it's playing actually finishes,
		# and a looping clip never does. Without this, drawing or holstering a
		# weapon holds that pose forever instead of handing back to locomotion.
		var draw_clip := LocomotionSets.draw_clip_installed_name(locomotion_set)
		if draw_clip != &"":
			one_shots.append(draw_clip)
		var holster_clip := LocomotionSets.holster_clip_installed_name(locomotion_set)
		if holster_clip != &"":
			one_shots.append(holster_clip)
	for requested_name in one_shots:
		var one_shot_animation := _find_animation([requested_name])
		if one_shot_animation != &"":
			anim_player.get_animation(one_shot_animation).loop_mode = Animation.LOOP_NONE


func _setup_animation_tree() -> void:
	if not _has_locomotion_clips():
		push_warning("Player AnimationTree was not created because directional clips are missing.")
		return

	animation_blend_tree = AnimationNodeBlendTree.new()
	# Three squares, one per speed tier. Moving normally is a jog rather than a
	# walk, so "normal" is the default gait and "sprint" is what holding shift
	# blends toward.
	var normal_space := _create_directional_blend_space(&"normal", &"idle")
	var sprint_space := _create_directional_blend_space(&"sprint", &"idle")
	var crouch_space := _create_directional_blend_space(&"crouch", &"crouch_idle")
	var sprint_blend_node := AnimationNodeBlend2.new()
	var stance_node := AnimationNodeBlend2.new()
	# Speeds the whole locomotion stack up when the set has no sprint of its own,
	# so the character's stride matches the ground they're covering rather than
	# skating along at jog cadence. Left at 1.0 the rest of the time.
	var locomotion_speed := AnimationNodeTimeScale.new()
	fire_animation_node = _create_animation_node(&"fire")
	var fire_shot := AnimationNodeOneShot.new()
	fire_shot.fadein_time = 0.06
	fire_shot.fadeout_time = 0.12
	_configure_upper_body_filter(fire_shot, &"fire")
	var reload_animation_node := _create_animation_node(&"reload")
	var reload_speed := AnimationNodeTimeScale.new()
	var reload_shot := AnimationNodeOneShot.new()
	reload_shot.fadein_time = 0.12
	reload_shot.fadeout_time = 0.2
	_configure_upper_body_filter(reload_shot, &"reload")
	# Empty until a set actually has a draw clip on disk - _on_weapon_changed
	# only ever requests this one-shot once it's found a real clip to point it
	# at, so an empty animation here is never played.
	draw_animation_node = AnimationNodeAnimation.new()
	var draw_speed := AnimationNodeTimeScale.new()
	draw_shot_node = AnimationNodeOneShot.new()
	draw_shot_node.fadein_time = 0.1
	draw_shot_node.fadeout_time = 0.15
	# Same shape as draw - empty/unused until play_holster_animation() finds a
	# real clip to point it at.
	holster_animation_node = AnimationNodeAnimation.new()
	var holster_speed := AnimationNodeTimeScale.new()
	holster_shot_node = AnimationNodeOneShot.new()
	holster_shot_node.fadein_time = 0.08
	holster_shot_node.fadeout_time = 0.12

	animation_blend_tree.add_node(&"NormalSpace", normal_space)
	animation_blend_tree.add_node(&"SprintSpace", sprint_space)
	animation_blend_tree.add_node(&"SprintBlend", sprint_blend_node)
	animation_blend_tree.add_node(&"CrouchSpace", crouch_space)
	animation_blend_tree.add_node(&"StanceBlend", stance_node)
	animation_blend_tree.add_node(&"LocomotionSpeed", locomotion_speed)
	animation_blend_tree.add_node(&"FireAnimation", fire_animation_node)
	animation_blend_tree.add_node(&"FireShot", fire_shot)
	animation_blend_tree.add_node(&"ReloadAnimation", reload_animation_node)
	animation_blend_tree.add_node(&"ReloadSpeed", reload_speed)
	animation_blend_tree.add_node(&"ReloadShot", reload_shot)
	animation_blend_tree.add_node(&"DrawAnimation", draw_animation_node)
	animation_blend_tree.add_node(&"DrawSpeed", draw_speed)
	animation_blend_tree.add_node(&"DrawShot", draw_shot_node)
	animation_blend_tree.add_node(&"HolsterAnimation", holster_animation_node)
	animation_blend_tree.add_node(&"HolsterSpeed", holster_speed)
	animation_blend_tree.add_node(&"HolsterShot", holster_shot_node)

	animation_blend_tree.connect_node(&"SprintBlend", 0, &"NormalSpace")
	animation_blend_tree.connect_node(&"SprintBlend", 1, &"SprintSpace")
	animation_blend_tree.connect_node(&"StanceBlend", 0, &"SprintBlend")
	animation_blend_tree.connect_node(&"StanceBlend", 1, &"CrouchSpace")
	animation_blend_tree.connect_node(&"LocomotionSpeed", 0, &"StanceBlend")
	animation_blend_tree.connect_node(&"FireShot", 0, &"LocomotionSpeed")
	animation_blend_tree.connect_node(&"FireShot", 1, &"FireAnimation")
	animation_blend_tree.connect_node(&"ReloadSpeed", 0, &"ReloadAnimation")
	animation_blend_tree.connect_node(&"ReloadShot", 0, &"FireShot")
	animation_blend_tree.connect_node(&"ReloadShot", 1, &"ReloadSpeed")
	animation_blend_tree.connect_node(&"DrawSpeed", 0, &"DrawAnimation")
	animation_blend_tree.connect_node(&"DrawShot", 0, &"ReloadShot")
	animation_blend_tree.connect_node(&"DrawShot", 1, &"DrawSpeed")
	animation_blend_tree.connect_node(&"HolsterSpeed", 0, &"HolsterAnimation")
	animation_blend_tree.connect_node(&"HolsterShot", 0, &"DrawShot")
	animation_blend_tree.connect_node(&"HolsterShot", 1, &"HolsterSpeed")
	animation_blend_tree.connect_node(&"output", 0, &"HolsterShot")

	# The blend points were created empty; this is what fills their clip names in.
	_apply_locomotion_set(current_set)

	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(anim_player)
	animation_tree.tree_root = animation_blend_tree
	animation_tree.active = true


## A nine-point blend square for one speed tier: a clip per direction plus the
## idle at the centre.
##
## The blend points are created without clip names and filled in by
## `_apply_locomotion_set()`, which is also what a weapon switch calls - so a
## pistol changes the whole square rather than rebuilding the tree.
##
## Every clip is weapon-held, which is the whole point: the model's own strafes
## are empty-handed and dropped the weapon to the character's hips.
func _create_directional_blend_space(
	tier: StringName,
	idle_key: StringName
) -> AnimationNodeBlendSpace2D:
	var blend_space := AnimationNodeBlendSpace2D.new()
	blend_space.min_space = Vector2(-1.0, -1.0)
	blend_space.max_space = Vector2(1.0, 1.0)
	blend_space.x_label = "Strafe"
	blend_space.y_label = "Forward / Back"
	# Independent, because the eight clips are separate captures with their own
	# stride timings - syncing them to a shared phase makes the feet skate.
	blend_space.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_INDEPENDENT
	blend_space.add_blend_point(_create_blend_point(&"", idle_key), Vector2.ZERO, -1, &"idle")
	for direction in LocomotionSets.DIRECTIONS:
		blend_space.add_blend_point(
			_create_blend_point(tier, direction),
			LocomotionSets.DIRECTIONS[direction],
			-1,
			direction
		)
	return blend_space


## An empty animation node, registered so `_apply_locomotion_set()` can find it
## again. An empty `tier` marks a square's centre idle, whose key names an entry
## in the set definition directly rather than one inside a tier.
func _create_blend_point(tier: StringName, key: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	blend_points.append({"node": node, "tier": tier, "key": key})
	return node


## Points every blend square at one set's clips.
##
## Refused wholesale if any clip is missing, rather than applied partially: a
## square with a few dead points is a character who freezes when they strafe,
## which is harder to diagnose than simply keeping the stance they had.
func _apply_locomotion_set(locomotion_set: StringName) -> bool:
	var definition := LocomotionSets.get_set(locomotion_set)
	var resolved: Array[StringName] = []
	for point in blend_points:
		var clip: StringName = (
			definition[point.key] if point.tier == &"" else definition[point.tier][point.key]
		)
		var installed := LocomotionSets.installed_name(locomotion_set, clip)
		if not anim_player.has_animation(installed):
			push_warning(
				"Locomotion set '%s' is missing '%s'; staying on '%s'."
				% [locomotion_set, installed, current_set]
			)
			return false
		resolved.append(installed)

	for index in blend_points.size():
		blend_points[index].node.animation = resolved[index]
	current_set = locomotion_set
	set_has_sprint = LocomotionSets.has_distinct_sprint(locomotion_set)
	return true


## Swaps the body's stance to match the weapon being carried, and plays a draw
## one-shot if that set has one on disk yet - see LocomotionSets.SETS' "draw"
## key. Skipped on the very first call, which is _ready() catching this
## listener up on the starting weapon rather than an actual switch; nothing is
## drawn "from" at game start.
func _on_weapon_changed(weapon: WeaponData, _slot: int) -> void:
	if weapon == null or blend_points.is_empty():
		return
	if weapon.locomotion_set != current_set:
		_apply_locomotion_set(weapon.locomotion_set)
	if _has_equipped_weapon:
		_play_draw_animation(weapon.locomotion_set)
	_has_equipped_weapon = true


## No-op until a draw clip actually exists for this set - see the SETS comment
## in locomotion_sets.gd. Filtered to the upper body each call, same as
## fire/reload, rather than once at tree-setup time, because the clip (and
## therefore its track list) may not exist yet when the tree is first built.
func _play_draw_animation(locomotion_set: StringName) -> void:
	if _is_incapacitated() or animation_tree == null or not animation_tree.active:
		return
	var draw_name := LocomotionSets.draw_clip_installed_name(locomotion_set)
	if draw_name == &"" or not anim_player.has_animation(draw_name):
		return
	draw_animation_node.animation = draw_name
	_configure_upper_body_filter(draw_shot_node, draw_name)
	animation_tree.set(
		"parameters/DrawSpeed/scale",
		anim_player.get_animation(draw_name).length / DRAW_ANIMATION_DURATION
	)
	animation_tree.set(
		"parameters/DrawShot/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)


## Called by WeaponController.equip_slot() before it actually swaps weapons -
## see that function's own comment. Returns how long the caller should wait
## before performing the swap: HOLSTER_ANIMATION_DURATION if a clip was found
## and played (the sped-up duration actually being played, not the raw clip's
## own length - see that constant's comment), 0.0 if there's nothing to play
## (no clip for this set yet, or animation is otherwise unavailable), which
## tells the caller to swap instantly exactly as it did before this existed.
## Public (no leading underscore) since WeaponController calls it via owner.
func play_holster_animation(locomotion_set: StringName) -> float:
	if _is_incapacitated() or animation_tree == null or not animation_tree.active:
		return 0.0
	var holster_name := LocomotionSets.holster_clip_installed_name(locomotion_set)
	if holster_name == &"" or not anim_player.has_animation(holster_name):
		return 0.0
	holster_animation_node.animation = holster_name
	_configure_upper_body_filter(holster_shot_node, holster_name)
	animation_tree.set(
		"parameters/HolsterSpeed/scale",
		anim_player.get_animation(holster_name).length / HOLSTER_ANIMATION_DURATION
	)
	animation_tree.set(
		"parameters/HolsterShot/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)
	return HOLSTER_ANIMATION_DURATION


func _create_animation_node(
	animation_name: StringName,
	timeline_length := 0.0
) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = _find_animation([animation_name])
	if timeline_length > 0.0:
		node.use_custom_timeline = true
		node.stretch_time_scale = true
		node.timeline_length = timeline_length
		node.loop_mode = Animation.LOOP_LINEAR
	return node


func _configure_upper_body_filter(one_shot: AnimationNodeOneShot, source_name: StringName) -> void:
	var source_animation_name := _find_animation([source_name])
	var source_animation := anim_player.get_animation(source_animation_name)
	one_shot.filter_enabled = true
	for track_index in source_animation.get_track_count():
		var track_path := source_animation.track_get_path(track_index)
		if _is_upper_body_track(track_path):
			one_shot.set_filter_path(track_path, true)


func _is_upper_body_track(track_path: NodePath) -> bool:
	if track_path.get_subname_count() == 0:
		return false
	var bone_name := String(track_path.get_subname(0))
	for lower_body_token in ["Hips", "UpLeg", "Leg", "Foot", "Toe"]:
		if bone_name.contains(lower_body_token):
			return false
	return bone_name.begins_with("mixamorig_")


## Whether the tree can be built at all. Only the default set is required: a
## second set that failed to convert should cost that weapon its stance, not cost
## the game its animation.
func _has_locomotion_clips() -> bool:
	var required: Array[StringName] = [&"fire", &"fire_move", &"reload"]
	required.append_array(LocomotionSets.clip_paths(DEFAULT_SET).keys())
	return _has_animations(required)


## Locomotion loops; one-shots are listed separately in _configure_animation_loops.
func _looping_clip_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for locomotion_set in INSTALLED_SETS:
		var definition := LocomotionSets.get_set(locomotion_set)
		names.append(LocomotionSets.installed_name(locomotion_set, definition.idle))
		names.append(LocomotionSets.installed_name(locomotion_set, definition.crouch_idle))
		names.append(LocomotionSets.installed_name(locomotion_set, definition.jump_loop))
		for tier in LocomotionSets.TIERS:
			for direction in LocomotionSets.DIRECTIONS:
				names.append(
					LocomotionSets.installed_name(locomotion_set, definition[tier][direction])
				)
	return names


func _has_animations(animation_names: Array) -> bool:
	for animation_name in animation_names:
		if _find_animation([animation_name]) == &"":
			return false
	return true


func _update_locomotion_blend(
	delta: float,
	input_dir: Vector2
) -> void:
	locomotion_blend = locomotion_blend.lerp(
		input_dir,
		minf(delta * LOCOMOTION_BLEND_SPEED, 1.0)
	)
	# A set without its own sprint stays on the normal tier - see
	# LocomotionSets.has_distinct_sprint - and covers the extra ground by running
	# its stride faster instead.
	sprint_blend = move_toward(
		sprint_blend,
		1.0 if (is_sprinting and set_has_sprint) else 0.0,
		delta * STANCE_BLEND_SPEED
	)
	var stride_scale := (
		SPRINT_SPEED / WALK_SPEED if (is_sprinting and not set_has_sprint) else 1.0
	)
	stance_blend = move_toward(
		stance_blend,
		1.0 if is_crouching else 0.0,
		delta * STANCE_BLEND_SPEED
	)
	animation_tree.set("parameters/NormalSpace/blend_position", locomotion_blend)
	animation_tree.set("parameters/SprintSpace/blend_position", locomotion_blend)
	animation_tree.set("parameters/CrouchSpace/blend_position", locomotion_blend)
	animation_tree.set("parameters/SprintBlend/blend_amount", sprint_blend)
	animation_tree.set("parameters/StanceBlend/blend_amount", stance_blend)
	animation_tree.set("parameters/LocomotionSpeed/scale", stride_scale)


func _play_full_body_animation(
	animation_names: Array,
	speed := 1.0,
	force_restart := false
) -> void:
	if anim_player == null:
		return
	var resolved_name := _find_animation(animation_names)
	if resolved_name == &"":
		return
	if (
		not force_restart
		and active_full_body_animation == resolved_name
		and anim_player.is_playing()
	):
		return
	active_full_body_animation = resolved_name
	_set_animation_tree_active(false)
	anim_player.speed_scale = speed
	anim_player.play(resolved_name, 0.15)


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name != active_full_body_animation:
		return
	if animation_name == _find_animation([&"death"]):
		return
	# Downed holds on the crouch_idle pose (see _go_down) until _finish_revive
	# clears active_full_body_animation itself - reactivating locomotion here
	# would let the character pop back to a standing idle mid-down.
	if is_downed:
		return
	active_full_body_animation = &""
	is_playing_landing = false
	# Bug found by testing: jump_up is a one-shot, and its own clip length has
	# no relationship to how long the actual jump arc takes - if it finishes
	# before the character reaches the peak (still rising, still airborne),
	# this fired with is_on_floor() still false and nothing here cleared
	# airborne_animation. _update_animation()'s airborne branch only
	# re-triggers a clip when desired_air_animation != airborne_animation, so
	# the very next frame recomputed the same "jump_up" (still rising) it had
	# already stored, matched it, and skipped playing anything at all -
	# leaving animation_tree.active permanently false with nothing driving
	# the pose until landing happened to force a fresh jump_down and recover
	# it from there. Clearing it here too, not just below, means the airborne
	# branch always sees a real mismatch and re-requests whatever's actually
	# appropriate (most likely jump_loop by then) on the very next frame
	# instead of silently going nowhere for the rest of the arc.
	airborne_animation = &""
	if is_on_floor():
		_set_animation_tree_active(true)


func _set_animation_tree_active(value: bool) -> void:
	if animation_tree == null or animation_tree.active == value:
		return
	if value:
		anim_player.stop()
	animation_tree.active = value


func _on_weapon_fired() -> void:
	# The crosshair pulse is the HUD's, connected to `fired` in bind_player.
	if _is_incapacitated() or animation_tree == null or not animation_tree.active:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	fire_animation_node.animation = _find_animation([
		&"fire_move" if horizontal_speed > 0.5 else &"fire"
	])
	animation_tree.set(
		"parameters/FireShot/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)


func _on_reload_started(duration: float) -> void:
	if _is_incapacitated() or animation_tree == null or not animation_tree.active:
		return
	var reload_animation := _find_animation([&"reload"])
	var playback_speed := 1.0
	if reload_animation != &"" and duration > 0.0:
		playback_speed = anim_player.get_animation(reload_animation).length / duration
	animation_tree.set("parameters/ReloadSpeed/scale", playback_speed)
	animation_tree.set(
		"parameters/ReloadShot/request",
		AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE
	)
