extends Node3D
class_name WeaponController

## Weapon logic, and the weapon the player character holds.
##
## The game is third person, so there is exactly one weapon in the world: it hangs
## off the character's right hand and everyone - the player included - sees the
## same one. Nothing here is a viewmodel.
##
## It was first person for a while, which is why `docs/ARCHITECTURE.md` has a
## section on why that was abandoned. The short version: the player model is a
## third-person character, and a first-person viewmodel is a different asset that
## can't reliably be derived from one. Going third person made the assets and the
## camera agree instead of fighting.

## Bones the weapon is fitted against on the body.
const GRIP_HAND_BONE := &"mixamorig_RightHand"
const SUPPORT_HAND_BONE := &"mixamorig_LeftHand"
const SUPPORT_UPPER_ARM_BONE := &"mixamorig_LeftArm"
const SUPPORT_FOREARM_BONE := &"mixamorig_LeftForeArm"

@export var starting_weapon: WeaponData

@export_group("Weapon in hand")
## Fine adjustment to how the weapon sits in the body's hand. The orientation is
## measured from the body's own pose rather than authored - see _align_world_model.
@export var world_model_position := Vector3(0.0, 0.02, 0.0)
@export var world_model_rotation_degrees := Vector3.ZERO

@export_group("Aim down sights")
@export_range(20.0, 90.0, 1.0) var ads_fov := 55.0
@export_range(1.0, 30.0, 0.5) var ads_transition_speed := 12.0
@export_range(0.1, 1.0, 0.05) var ads_mouse_sensitivity_multiplier := 0.65

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
## Support arm chain on the body, resolved when the weapon is attached.
var support_upper_index := -1
var support_forearm_index := -1
var support_hand_index := -1

var hip_camera_fov := 75.0
var is_aiming := false
var aim_blend := 0.0
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


func _ready() -> void:
	# Last in the frame: after the AnimationTree has written the pose and after the
	# player has pitched the spine, since the support arm is solved from a shoulder
	# both of those move. See the matching note in scripts/player/player.gd.
	process_priority = 20
	camera = get_parent() as Camera3D
	if camera:
		hip_camera_fov = camera.fov
	if starting_weapon:
		equip(starting_weapon)


func equip(weapon: WeaponData) -> void:
	current_weapon = weapon
	ammo_in_mag = weapon.mag_size
	reserve_ammo = weapon.starting_reserve_ammo
	is_reloading = false
	fire_cooldown = 0.0
	_set_aiming(false)
	if world_model_skeleton:
		attach_world_model(world_model_skeleton, GRIP_HAND_BONE)
	ammo_changed.emit(ammo_in_mag, reserve_ammo)


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

	world_model = current_weapon.model_scene.instantiate()
	world_model_attachment.add_child(world_model)
	_fit_to_grip(world_model)
	# Deferred: the orientation is read off the body's animated pose, and nothing
	# has posed it yet on the frame the weapon is attached.
	world_model_aligned = false


## Turns the weapon to lie along the line between the body's hands.
##
## _fit_to_grip leaves it pointing down -Z in its own frame, but it hangs off a
## wrist whose orientation is whatever Mixamo happened to author. Reading the
## direction off the body's own hands means the weapon points where the animation
## is holding it, in any clip, rather than at an angle guessed against that frame.
func _align_world_model() -> void:
	var grip_index := world_model_skeleton.find_bone(GRIP_HAND_BONE)
	var support_index := world_model_skeleton.find_bone(SUPPORT_HAND_BONE)
	if grip_index < 0 or support_index < 0:
		world_model_aligned = true
		return
	var grip_pose := world_model_skeleton.get_bone_global_pose(grip_index)
	var barrel := (
		world_model_skeleton.get_bone_global_pose(support_index).origin - grip_pose.origin
	)
	if barrel.length_squared() < 0.0001:
		return
	var into_hand := grip_pose.basis.orthonormalized().inverse()
	world_model.transform = Transform3D(
		Basis.looking_at((into_hand * barrel).normalized(), into_hand * Vector3.UP)
		* Basis.from_euler(world_model_rotation_degrees * (PI / 180.0)),
		world_model_position
	) * world_model.transform
	world_model_aligned = true


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
	muzzle_in_mesh = muzzle.position if muzzle != null else foregrip.position + along_barrel
	sight_in_mesh = grip.position + along_barrel * 0.5 + Vector3.UP * 0.04
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
	foregrip_in_mesh = out_of_fit * Vector3(
		held_bounds.get_center().x,
		held_bounds.position.y + current_weapon.foregrip_anchor.y * held_bounds.size.y,
		held_bounds.end.z - current_weapon.foregrip_anchor.x * held_bounds.size.z
	)
	# Top-centre of the bounds is where iron sights and rail optics sit on every
	# model in the pack; sight_nudge covers anything unusual.
	sight_in_mesh = out_of_fit * (
		Vector3(
			held_bounds.get_center().x,
			held_bounds.end.y,
			held_bounds.get_center().z
		) + current_weapon.sight_nudge
	)
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
	var basis := Basis(images[0], images[1], images[2])
	# Which way the width axis has to face for a right-handed (unmirrored) basis
	# depends on how barrel/up/width happened to land on x/y/z, so derive it from
	# the determinant rather than assuming.
	if basis.determinant() < 0.0:
		images[width_axis] = -images[width_axis]
		basis = Basis(images[0], images[1], images[2])
	return basis


## Bends the body's support arm so its hand closes on the weapon's handguard.
##
## The weapon is fitted to the grip hand, so the other one lands wherever the clip
## put it - and Mixamo's hand spacing was authored around its own rifle, not this
## one, so it floats short of the weapon. Solving for it means any weapon is held
## with both hands whatever the animation is doing.
##
## Standard two-bone solve: set the elbow's angle from the law of cosines so the
## chain spans exactly the distance to the target, then swing the whole arm so the
## hand lands on it. The pole decides which way the elbow breaks; without one the
## solve is free to fold the arm through the character's chest.
func _solve_support_arm_ik() -> void:
	if world_model == null or support_upper_index < 0:
		return
	var skeleton := world_model_skeleton
	var into_skeleton: Transform3D = (
		(skeleton.get_parent() as Node3D).global_transform * skeleton.transform
	).affine_inverse()
	var target: Vector3 = into_skeleton * (world_model.global_transform * foregrip_in_mesh)

	var shoulder: Vector3 = skeleton.get_bone_global_pose(support_upper_index).origin
	var elbow_pose := skeleton.get_bone_global_pose(support_forearm_index)
	var hand: Vector3 = skeleton.get_bone_global_pose(support_hand_index).origin
	var upper_length := shoulder.distance_to(elbow_pose.origin)
	var lower_length := elbow_pose.origin.distance_to(hand)
	if upper_length < 0.0001 or lower_length < 0.0001:
		return
	# Elbow points down and away from the weapon, which is where a support arm
	# naturally breaks.
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
		support_forearm_index,
		Basis(bend_axis.normalized(), desired_elbow - current_elbow) * elbow_pose.basis
	)
	skeleton.force_update_all_bone_transforms()

	var swung_hand: Vector3 = skeleton.get_bone_global_pose(support_hand_index).origin
	_set_bone_global_basis(
		support_upper_index,
		Basis(Quaternion(
			(swung_hand - shoulder).normalized(),
			(target - shoulder).normalized()
		)) * skeleton.get_bone_global_pose(support_upper_index).basis
	)
	skeleton.force_update_all_bone_transforms()

	# Position only - the hand's own rotation is left to the clip, which already
	# poses it gripping a rifle handguard.
	#
	# Forcing the hand's basis to match the weapon's was tried and made it worse:
	# Mixamo hand bones run +Y down the fingers, so aligning the hand to the
	# weapon points the fingers straight up and drapes the hand over the top of
	# the barrel instead of wrapping it. If the palm ever does need turning, the
	# correction has to map hand-+Y onto the barrel (about -90 degrees on X),
	# not onto the weapon's up axis.


## Bone poses are local to the parent, so a rotation worked out in skeleton space
## has to be brought back down through the parent to be applied.
func _set_bone_global_basis(bone_index: int, global_basis: Basis) -> void:
	var parent := world_model_skeleton.get_bone_parent(bone_index)
	var parent_basis := (
		world_model_skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis()
	)
	world_model_skeleton.set_bone_pose_rotation(
		bone_index,
		(parent_basis.inverse() * global_basis).orthonormalized().get_rotation_quaternion()
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
	# After the player's own _process, which pitches the spine and so moves the
	# shoulder the arm is solved from. Parents process before children.
	_solve_support_arm_ik()

	if fire_cooldown > 0.0:
		fire_cooldown -= delta

	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0.0:
			_finish_reload()
		return

	if current_weapon == null:
		return

	var wants_fire := (
		Input.is_action_pressed("fire")
		if current_weapon.is_automatic
		else Input.is_action_just_pressed("fire")
	)
	if wants_fire and fire_cooldown <= 0.0:
		_try_fire()

	if Input.is_action_just_pressed("reload"):
		_try_reload()


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


# --------------------------------------------------------------- weapon logic


func _try_fire() -> void:
	if ammo_in_mag <= 0:
		return
	ammo_in_mag -= 1
	fire_cooldown = 1.0 / current_weapon.fire_rate
	_play_sound(current_weapon.fire_sound)
	_hitscan()
	recoil_velocity += Vector2(
		recoil_pitch_degrees,
		recoil_yaw_degrees * randf_range(-1.0, 1.0)
	) * recoil_stiffness * 0.08
	fired.emit()
	ammo_changed.emit(ammo_in_mag, reserve_ammo)


## Fired in two stages, because the camera is behind the player rather than at
## their eye.
##
## First a ray from the camera finds what is actually under the crosshair - that's
## what the player is pointing at. Then the damaging shot is traced from the
## weapon to that point. Firing straight down the camera ray instead would start
## the shot metres behind the character and hit anything standing between the two,
## and would let the player shoot through a wall they're backed against.
func _hitscan() -> void:
	if camera == null:
		return
	var space_state := camera.get_world_3d().direct_space_state
	# `owner` is the WeaponController's scene root - the Player CharacterBody3D it's
	# nested under in player.tscn. Excluded from both traces so the shooter's own
	# capsule can never be what stops the shot.
	var exclude: Array[RID] = []
	if owner and owner is CollisionObject3D:
		exclude = [owner.get_rid()]

	var camera_origin := camera.global_position
	var camera_forward := -camera.global_transform.basis.z
	var aim_point := camera_origin + camera_forward * current_weapon.weapon_range
	var sighting := space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
		camera_origin,
		aim_point
	))
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
	var query := PhysicsRayQueryParameters3D.create(muzzle, aim_point)
	query.exclude = exclude
	var result := space_state.intersect_ray(query)
	if result and result.has("collider") and result.collider.has_method("take_damage"):
		result.collider.take_damage(current_weapon.damage)


func _try_reload() -> void:
	if is_reloading or ammo_in_mag >= current_weapon.mag_size or reserve_ammo <= 0:
		return
	is_reloading = true
	_set_aiming(false)
	reload_timer = current_weapon.reload_time
	_play_sound(current_weapon.reload_sound)
	reload_started.emit(current_weapon.reload_time)


func _finish_reload() -> void:
	var needed := current_weapon.mag_size - ammo_in_mag
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
