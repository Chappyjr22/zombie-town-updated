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

## Aim correction: how fast the torso eases into the measured error, and how far
## it is allowed to twist. Both exist because the correction moves the weapon it
## was measured from, so the loop needs damping and a ceiling.
const AIM_YAW_CORRECTION_SPEED := 0.25
const MAX_AIM_YAW := deg_to_rad(40.0)

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

@export var max_health: float = 100.0
## Mixamo authors this character facing +Z while Godot gameplay forward is -Z, so
## the body is turned to face the direction the player is aiming and moving.
@export var model_yaw_offset_degrees := 180.0
## How much of the camera pitch the torso follows, so the character visibly aims
## where the camera is pointed. Under 1.0 because a full match bends the spine
## further than a person would.
@export_range(0.0, 1.0, 0.05) var spine_pitch_share := 0.75
## How far back the camera sits normally, and while aiming. Pulling in over the
## shoulder to aim is the usual third-person shooter language for "aiming".
@export_range(0.5, 8.0, 0.1) var camera_distance := 3.0
@export_range(0.5, 8.0, 0.1) var camera_aim_distance := 1.4
@export_range(1.0, 30.0, 0.5) var camera_zoom_speed := 10.0

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
## Spendable currency, earned by hitting and killing zombies. The buy systems -
## wall weapons, the mystery box, map gates - all price against this.
var points := 0
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
var locomotion_blend := Vector2.ZERO
var sprint_blend := 0.0
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


func _ready() -> void:
	# Everything this script does to bones - the head scale, the spine pitch - is
	# overwritten if the AnimationTree runs after it, and by default it does: it's
	# added as a child at runtime, and children process after their parent. Higher
	# priority means later, so this orders the frame as
	# AnimationTree -> player -> WeaponController's support-arm IK.
	process_priority = 10
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health = max_health
	add_to_group("player")
	collision_layer = PhysicsLayers.ACTORS
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.ACTORS
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


## Reapplied every frame because the AnimationTree rewrites the bone poses each
## time it runs - see the process_priority note in _ready.
func _process(delta: float) -> void:
	_apply_spine_aim()
	_update_camera_distance(delta)
	_update_regen(delta)


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


## Pulls the camera in over the shoulder while aiming and lets it back out again.
func _update_camera_distance(delta: float) -> void:
	var aiming := weapon_controller != null and weapon_controller.is_aiming
	spring_arm.spring_length = lerpf(
		spring_arm.spring_length,
		camera_aim_distance if aiming else camera_distance,
		1.0 - exp(-camera_zoom_speed * delta)
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
	if body_skeleton == null or is_dead:
		return
	var pitch_share := (
		-spring_arm.rotation.x * spine_pitch_share / float(SPINE_PITCH_BONES.size())
	)
	# Unwound while sprinting rather than corrected. The sprint clip swings both
	# arms, so the weapon follows a swinging hand and closing the gap would need
	# about 70 degrees of twist - it just pins at the clamp and the character runs
	# hunched. You aren't aiming mid-sprint anyway, so the torso is let go instead.
	var target := 0.0 if sprint_blend > 0.5 else aim_yaw + _measure_aim_yaw_error()
	# Eased, because the correction turns the weapon the error was measured from.
	# Clamped, so a bad reading twists the torso a bounded amount rather than
	# spinning it - which is exactly what happened the first time this was tried.
	aim_yaw = clampf(
		lerpf(aim_yaw, target, AIM_YAW_CORRECTION_SPEED),
		-MAX_AIM_YAW,
		MAX_AIM_YAW
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
	for set_name in INSTALLED_SETS:
		var paths := LocomotionSets.clip_paths(set_name)
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
				) % [missing, paths.size(), set_name, set_name]
			)


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
	points += amount
	points_changed.emit(points, amount)


func take_damage(amount: float) -> void:
	if is_dead:
		return
	health -= amount
	time_since_damaged = 0.0
	health_changed.emit(health, max_health)
	if health <= 0.0:
		is_dead = true
		hud.visible = false
		airborne_animation = &""
		_play_full_body_animation([&"death"])
		died.emit()
		# TODO: no death/respawn flow yet - player just stops taking further damage.
	# No hit reaction. The clip is a full-body flinch that interrupts whatever the
	# player was doing - aiming, sprinting - and taking control away every time a
	# zombie connects feels worse than showing nothing. Damage feedback belongs on
	# the HUD instead.


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
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if is_dead:
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

	var is_sprinting := (
		not is_crouching
		and Input.is_action_pressed("sprint")
		and input_dir.y < 0.0
	)
	var speed := WALK_SPEED
	if is_crouching:
		speed = CROUCH_SPEED
	elif is_sprinting:
		speed = SPRINT_SPEED

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
	_update_animation(delta, just_landed, input_dir, is_sprinting)


func _update_crouch(delta: float) -> void:
	is_crouching = Input.is_action_pressed("crouch")
	var target_height := CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	var shape: CapsuleShape3D = collision_shape.shape
	shape.height = move_toward(shape.height, target_height, CROUCH_LERP_SPEED * delta)
	collision_shape.position.y = shape.height / 2.0
	# The rig rides the capsule so crouching lowers the camera with the character.
	# Only Y - X is the over-the-shoulder offset that keeps the character out of
	# the middle of the screen, and it has to stay put.
	camera_rig.position.y = shape.height - 0.3


func _update_animation(
	delta: float,
	just_landed: bool,
	input_dir: Vector2,
	is_sprinting: bool
) -> void:
	if anim_player == null:
		return
	# Death holds the body, and the landing clip is allowed to finish before
	# locomotion takes back over.
	if is_dead or is_playing_landing:
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
	_update_locomotion_blend(delta, input_dir, is_sprinting)


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
	for set_name in INSTALLED_SETS:
		var definition := LocomotionSets.get_set(set_name)
		one_shots.append(LocomotionSets.installed_name(set_name, definition.jump_up))
		one_shots.append(LocomotionSets.installed_name(set_name, definition.jump_down))
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
	animation_blend_tree.connect_node(&"output", 0, &"ReloadShot")

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
func _apply_locomotion_set(set_name: StringName) -> bool:
	var definition := LocomotionSets.get_set(set_name)
	var resolved: Array[StringName] = []
	for point in blend_points:
		var clip: StringName = (
			definition[point.key] if point.tier == &"" else definition[point.tier][point.key]
		)
		var installed := LocomotionSets.installed_name(set_name, clip)
		if not anim_player.has_animation(installed):
			push_warning(
				"Locomotion set '%s' is missing '%s'; staying on '%s'."
				% [set_name, installed, current_set]
			)
			return false
		resolved.append(installed)

	for index in blend_points.size():
		blend_points[index].node.animation = resolved[index]
	current_set = set_name
	set_has_sprint = LocomotionSets.has_distinct_sprint(set_name)
	return true


## Swaps the body's stance to match the weapon being carried.
func _on_weapon_changed(weapon: WeaponData, _slot: int) -> void:
	if weapon == null or blend_points.is_empty():
		return
	if weapon.locomotion_set != current_set:
		_apply_locomotion_set(weapon.locomotion_set)


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
	for set_name in INSTALLED_SETS:
		var definition := LocomotionSets.get_set(set_name)
		names.append(LocomotionSets.installed_name(set_name, definition.idle))
		names.append(LocomotionSets.installed_name(set_name, definition.crouch_idle))
		names.append(LocomotionSets.installed_name(set_name, definition.jump_loop))
		for tier in LocomotionSets.TIERS:
			for direction in LocomotionSets.DIRECTIONS:
				names.append(
					LocomotionSets.installed_name(set_name, definition[tier][direction])
				)
	return names


func _has_animations(animation_names: Array) -> bool:
	for animation_name in animation_names:
		if _find_animation([animation_name]) == &"":
			return false
	return true


func _update_locomotion_blend(
	delta: float,
	input_dir: Vector2,
	is_sprinting: bool
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
	active_full_body_animation = &""
	is_playing_landing = false
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
	if is_dead or animation_tree == null or not animation_tree.active:
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
	if is_dead or animation_tree == null or not animation_tree.active:
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
