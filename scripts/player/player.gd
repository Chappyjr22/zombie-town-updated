extends CharacterBody3D

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
## resources so the model itself is never rewritten. See tools/build_clips.gd.
##
## - "idle": the stock one carries the rifle across the chest, which reads as a
##   patrol rather than a soldier ready to fire.
## - "sprint": the consolidated model has no sprint clip at all, so sprinting used
##   to play "run" and looked identical to jogging.
const EXTRA_CLIPS := {
	&"idle": "res://assets/animations/rifle_aim_idle.res",
	&"sprint": "res://assets/animations/rifle_sprint.res",
}

## Spine bones the look pitch is spread across, lowest first. Sharing it over
## three joints curves the torso the way a person actually leans, where putting it
## all on one would visibly hinge the character in half.
const SPINE_PITCH_BONES: Array[StringName] = [
	&"mixamorig_Spine",
	&"mixamorig_Spine1",
	&"mixamorig_Spine2",
]

## How far the camera can be pitched up and down. Tighter than a first-person
## limit: swinging a third-person camera to vertical puts it inside the floor or
## directly overhead, neither of which is usable.
const CAMERA_PITCH_MIN := deg_to_rad(-65.0)
const CAMERA_PITCH_MAX := deg_to_rad(40.0)

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
@onready var crosshair: Crosshair = $HUD/Crosshair

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_crouching := false
var health: float
var is_dead := false
var was_on_floor := true
var active_full_body_animation: StringName = &""
var airborne_animation: StringName = &""
var animation_tree: AnimationTree
var body_skeleton: Skeleton3D
var animation_blend_tree: AnimationNodeBlendTree
var fire_animation_node: AnimationNodeAnimation
var locomotion_blend := Vector2.ZERO
var sprint_blend := 0.0
var stance_blend := 0.0

signal health_changed(current: float, max: float)
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
		weapon_controller.aim_changed.connect(crosshair.set_aiming)
		crosshair.set_aiming(weapon_controller.is_aiming)
		# Unconditional: without it the body holds nothing, so other players would
		# see an unarmed soldier miming a rifle once multiplayer exists.
		weapon_controller.attach_world_model(body_skeleton, &"mixamorig_RightHand")


## Reapplied every frame because the AnimationTree rewrites the bone poses each
## time it runs - see the process_priority note in _ready.
func _process(delta: float) -> void:
	_apply_spine_pitch()
	_update_camera_distance(delta)


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
## Pitch only. A matching yaw correction - measuring how far the barrel sits from
## the view and turning the torso to close it - was tried and reverted: the
## weapon's local -Z stops being the barrel once `_align_world_model()` has turned
## it, so the error came out wrong and the correction chased it. See this folder's
## CLAUDE.md before attempting it again.
func _apply_spine_pitch() -> void:
	if body_skeleton == null or is_dead:
		return
	var share := -spring_arm.rotation.x * spine_pitch_share / float(SPINE_PITCH_BONES.size())
	if is_zero_approx(share):
		return
	for bone_name in SPINE_PITCH_BONES:
		var bone_index := body_skeleton.find_bone(bone_name)
		if bone_index < 0:
			continue
		var parent := body_skeleton.get_bone_parent(bone_index)
		var parent_basis := (
			body_skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
		)
		var posed := Basis(Vector3.RIGHT, share) * body_skeleton.get_bone_global_pose(
			bone_index
		).basis
		body_skeleton.set_bone_pose_rotation(
			bone_index,
			(parent_basis.inverse() * posed).orthonormalized().get_rotation_quaternion()
		)


## Installs the clips the soldier model doesn't ship with, or ships wrong. Any
## that are missing are skipped rather than fatal - the model's own clips still
## work, they just read worse.
func _install_extra_clips() -> void:
	var library := anim_player.get_animation_library(&"")
	for clip_name in EXTRA_CLIPS:
		var path: String = EXTRA_CLIPS[clip_name]
		if not ResourceLoader.exists(path):
			push_warning("%s is missing; run tools/build_clips.gd." % path)
			continue
		var existing := _find_animation([clip_name])
		if existing != &"":
			library.remove_animation(existing)
		library.add_animation(clip_name, load(path))


func take_damage(amount: float) -> void:
	if is_dead:
		return
	health -= amount
	health_changed.emit(health, max_health)
	if health <= 0.0:
		is_dead = true
		crosshair.visible = false
		airborne_animation = &""
		_play_full_body_animation([&"death"])
		died.emit()
		# TODO: no death/respawn flow yet - player just stops taking further damage.
	else:
		airborne_animation = &""
		_play_full_body_animation([&"hit"], 1.0, true)


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
	if active_full_body_animation in [
		_find_animation([&"hit"]),
		_find_animation([&"death"]),
		_find_animation([&"jump_land"]),
	]:
		return
	if not is_on_floor():
		var desired_air_animation := &"jump_start" if velocity.y > 0.0 else &"jump_air"
		if desired_air_animation != airborne_animation:
			airborne_animation = desired_air_animation
			_play_full_body_animation([desired_air_animation])
		return
	if just_landed:
		airborne_animation = &""
		_play_full_body_animation([&"jump_land"])
		return
	if active_full_body_animation != &"":
		return
	_set_animation_tree_active(true)
	_update_locomotion_blend(delta, input_dir, is_sprinting)


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
	for requested_name in [
		&"idle",
		&"walk",
		&"sprint",
		&"run",
		&"crouch_idle",
		&"crouch_walk",
		&"jump_air",
		&"move_back",
		&"strafe_left",
		&"strafe_right",
	]:
		var loop_animation := _find_animation([requested_name])
		if loop_animation != &"":
			anim_player.get_animation(loop_animation).loop_mode = Animation.LOOP_LINEAR
	for requested_name in [
		&"jump_start",
		&"jump_land",
		&"fire",
		&"fire_move",
		&"reload",
		&"hit",
		&"death",
	]:
		var one_shot_animation := _find_animation([requested_name])
		if one_shot_animation != &"":
			anim_player.get_animation(one_shot_animation).loop_mode = Animation.LOOP_NONE


func _setup_animation_tree() -> void:
	if not _has_animations([
		&"idle",
		&"run",
		&"sprint",
		&"move_back",
		&"strafe_left",
		&"strafe_right",
		&"crouch_idle",
		&"crouch_walk",
		&"fire",
		&"fire_move",
		&"reload",
	]):
		push_warning("Player AnimationTree was not created because directional clips are missing.")
		return

	animation_blend_tree = AnimationNodeBlendTree.new()
	# Moving normally is a jog, not a walk - "run" is the jog, and "sprint" is the
	# clip installed over the top by _install_extra_clips. The model ships no
	# sprint of its own, which is why holding shift used to look identical to
	# moving normally.
	var walk_space := _create_directional_blend_space(&"run")
	var run_space := _create_directional_blend_space(&"sprint")
	var crouch_space := _create_crouch_blend_space()
	var run_blend := AnimationNodeBlend2.new()
	var stance_node := AnimationNodeBlend2.new()
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

	animation_blend_tree.add_node(&"WalkSpace", walk_space)
	animation_blend_tree.add_node(&"RunSpace", run_space)
	animation_blend_tree.add_node(&"RunBlend", run_blend)
	animation_blend_tree.add_node(&"CrouchSpace", crouch_space)
	animation_blend_tree.add_node(&"StanceBlend", stance_node)
	animation_blend_tree.add_node(&"FireAnimation", fire_animation_node)
	animation_blend_tree.add_node(&"FireShot", fire_shot)
	animation_blend_tree.add_node(&"ReloadAnimation", reload_animation_node)
	animation_blend_tree.add_node(&"ReloadSpeed", reload_speed)
	animation_blend_tree.add_node(&"ReloadShot", reload_shot)

	animation_blend_tree.connect_node(&"RunBlend", 0, &"WalkSpace")
	animation_blend_tree.connect_node(&"RunBlend", 1, &"RunSpace")
	animation_blend_tree.connect_node(&"StanceBlend", 0, &"RunBlend")
	animation_blend_tree.connect_node(&"StanceBlend", 1, &"CrouchSpace")
	animation_blend_tree.connect_node(&"FireShot", 0, &"StanceBlend")
	animation_blend_tree.connect_node(&"FireShot", 1, &"FireAnimation")
	animation_blend_tree.connect_node(&"ReloadSpeed", 0, &"ReloadAnimation")
	animation_blend_tree.connect_node(&"ReloadShot", 0, &"FireShot")
	animation_blend_tree.connect_node(&"ReloadShot", 1, &"ReloadSpeed")
	animation_blend_tree.connect_node(&"output", 0, &"ReloadShot")

	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(anim_player)
	animation_tree.tree_root = animation_blend_tree
	animation_tree.active = true


func _create_directional_blend_space(forward_animation: StringName) -> AnimationNodeBlendSpace2D:
	var blend_space := AnimationNodeBlendSpace2D.new()
	# Sprint strides faster than a jog, so the shared directional clips get
	# stretched to whichever cadence this tier runs at.
	var cycle_length := 0.6 if forward_animation == &"sprint" else 0.85
	blend_space.min_space = Vector2(-1.0, -1.0)
	blend_space.max_space = Vector2(1.0, 1.0)
	blend_space.x_label = "Strafe"
	blend_space.y_label = "Forward / Back"
	blend_space.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_INDEPENDENT
	blend_space.add_blend_point(_create_animation_node(&"idle"), Vector2.ZERO, -1, &"idle")
	blend_space.add_blend_point(
		_create_animation_node(forward_animation, cycle_length),
		Vector2(0.0, -1.0),
		-1,
		&"forward"
	)
	blend_space.add_blend_point(
		_create_animation_node(&"move_back", cycle_length),
		Vector2(0.0, 1.0),
		-1,
		&"back"
	)
	blend_space.add_blend_point(
		_create_animation_node(&"strafe_left", cycle_length),
		Vector2(-1.0, 0.0),
		-1,
		&"left"
	)
	blend_space.add_blend_point(
		_create_animation_node(&"strafe_right", cycle_length),
		Vector2(1.0, 0.0),
		-1,
		&"right"
	)
	return blend_space


func _create_crouch_blend_space() -> AnimationNodeBlendSpace2D:
	var blend_space := AnimationNodeBlendSpace2D.new()
	blend_space.min_space = Vector2(-1.0, -1.0)
	blend_space.max_space = Vector2(1.0, 1.0)
	blend_space.x_label = "Strafe"
	blend_space.y_label = "Forward / Back"
	blend_space.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_INDEPENDENT
	blend_space.add_blend_point(
		_create_animation_node(&"crouch_idle"),
		Vector2.ZERO,
		-1,
		&"idle"
	)
	for point in [
		{"name": &"forward", "position": Vector2(0.0, -1.0)},
		{"name": &"back", "position": Vector2(0.0, 1.0)},
		{"name": &"left", "position": Vector2(-1.0, 0.0)},
		{"name": &"right", "position": Vector2(1.0, 0.0)},
	]:
		blend_space.add_blend_point(
			_create_animation_node(&"crouch_walk", 1.15),
			point.position,
			-1,
			point.name
		)
	return blend_space


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
	sprint_blend = move_toward(
		sprint_blend,
		1.0 if is_sprinting else 0.0,
		delta * STANCE_BLEND_SPEED
	)
	stance_blend = move_toward(
		stance_blend,
		1.0 if is_crouching else 0.0,
		delta * STANCE_BLEND_SPEED
	)
	animation_tree.set("parameters/WalkSpace/blend_position", locomotion_blend)
	animation_tree.set("parameters/RunSpace/blend_position", locomotion_blend)
	animation_tree.set("parameters/CrouchSpace/blend_position", locomotion_blend)
	animation_tree.set("parameters/RunBlend/blend_amount", sprint_blend)
	animation_tree.set("parameters/StanceBlend/blend_amount", stance_blend)


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
	if animation_name == _find_animation([&"hit"]) and not is_on_floor():
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
	crosshair.pulse()
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
