extends Node3D
class_name WeaponController

## Where the weapon model's center lands relative to the camera, after scaling.
@export var view_model_offset := Vector3(0.25, -0.2, -0.4)
@export var target_view_model_size := 0.45 ## world-space size of the model's longest dimension after scaling
## First playtest showed the gun lying on its side (barrel pointing across the
## screen instead of away from the camera) - the FBX's own forward axis doesn't
## match Godot's -Z convention. Rather than guess blindly again: select the
## WeaponController node under Head/Camera3D in player.tscn, find "View Model
## Rotation Degrees" in the Inspector, and try 90/-90/180 on the Y value (run
## the scene after each change) until the barrel points forward. Edit it here
## once you find the right value so it's not lost.
@export var view_model_rotation_degrees := Vector3(0, 90, 0)
@export var starting_weapon: WeaponData

var camera: Camera3D
var current_weapon: WeaponData
var current_model: Node3D
var ammo_in_mag: int = 0
var reserve_ammo: int = 0
var fire_cooldown: float = 0.0
var is_reloading: bool = false
var reload_timer: float = 0.0

@onready var audio_player: AudioStreamPlayer3D = $AudioStreamPlayer3D

signal ammo_changed(ammo_in_mag: int, reserve_ammo: int)
signal reload_started(duration: float)


func _ready() -> void:
	camera = get_parent() as Camera3D
	if starting_weapon:
		equip(starting_weapon)


func equip(weapon: WeaponData) -> void:
	if current_model:
		current_model.queue_free()
		current_model = null

	current_weapon = weapon
	ammo_in_mag = weapon.mag_size
	reserve_ammo = weapon.starting_reserve_ammo
	is_reloading = false
	fire_cooldown = 0.0

	if weapon.model_scene:
		current_model = weapon.model_scene.instantiate()
		add_child(current_model)
		_fit_view_model(current_model)

	ammo_changed.emit(ammo_in_mag, reserve_ammo)


## Measures the model's actual mesh bounds and scales/positions it so its
## longest dimension matches target_view_model_size and its visual center
## lands at view_model_offset - regardless of how the source FBX/glTF was
## authored (scale, pivot location, units).
func _fit_view_model(model: Node3D) -> void:
	var combined := AABB()
	var found_any := false

	for mesh_instance in NodeUtils.find_all_of_type(model, "MeshInstance3D"):
		if not (mesh_instance is MeshInstance3D) or mesh_instance.mesh == null:
			continue
		var local_xform: Transform3D = model.global_transform.affine_inverse() * mesh_instance.global_transform
		var mesh_aabb: AABB = mesh_instance.mesh.get_aabb()
		for i in range(8):
			var corner := mesh_aabb.position + Vector3(
				mesh_aabb.size.x * float(i & 1),
				mesh_aabb.size.y * float((i >> 1) & 1),
				mesh_aabb.size.z * float((i >> 2) & 1)
			)
			var world_corner: Vector3 = local_xform * corner
			if not found_any:
				combined = AABB(world_corner, Vector3.ZERO)
				found_any = true
			else:
				combined = combined.expand(world_corner)

	if not found_any:
		return

	var largest_dim: float = max(combined.size.x, max(combined.size.y, combined.size.z))
	if largest_dim <= 0.0001:
		return

	var scale_factor := target_view_model_size / largest_dim
	model.scale = Vector3.ONE * scale_factor
	model.rotation_degrees = view_model_rotation_degrees

	# Uniform scale commutes with rotation, so this order doesn't matter here -
	# rotate-then-scale the AABB center to find where it actually lands, then
	# offset the model so that point sits at view_model_offset.
	var rotated_center: Vector3 = (
		Basis.from_euler(view_model_rotation_degrees * (PI / 180.0)) * (combined.get_center() * scale_factor)
	)
	model.position = view_model_offset - rotated_center


func _process(delta: float) -> void:
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


func _try_fire() -> void:
	if ammo_in_mag <= 0:
		return
	ammo_in_mag -= 1
	fire_cooldown = 1.0 / current_weapon.fire_rate
	_play_sound(current_weapon.fire_sound)
	_hitscan()
	ammo_changed.emit(ammo_in_mag, reserve_ammo)


func _hitscan() -> void:
	if camera == null:
		return
	var space_state := camera.get_world_3d().direct_space_state
	var origin := camera.global_position
	var target := origin - camera.global_transform.basis.z * current_weapon.weapon_range
	var query := PhysicsRayQueryParameters3D.create(origin, target)
	# `owner` is the WeaponController's scene root - the Player CharacterBody3D it's
	# nested under in player.tscn. Excluded so the ray can't clip the shooter's own
	# collision capsule when aiming down/close to their own body.
	if owner and owner is CollisionObject3D:
		query.exclude = [owner.get_rid()]
	var result := space_state.intersect_ray(query)
	if result and result.has("collider") and result.collider.has_method("take_damage"):
		result.collider.take_damage(current_weapon.damage)


func _try_reload() -> void:
	if is_reloading or ammo_in_mag >= current_weapon.mag_size or reserve_ammo <= 0:
		return
	is_reloading = true
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
