extends Node3D
class_name WeaponController

## Positions the equipped weapon model relative to the camera. Untested outside
## the editor - the FBX models weren't authored with a defined grip point, so
## this offset/rotation almost certainly needs visual tuning once someone can
## actually look at it in Godot.
@export var view_model_offset := Vector3(0.25, -0.25, -0.5)
@export var view_model_scale := 1.0
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
		current_model.position = view_model_offset
		current_model.scale = Vector3.ONE * view_model_scale

	ammo_changed.emit(ammo_in_mag, reserve_ammo)


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
	var target := origin - camera.global_transform.basis.z * current_weapon.range
	var query := PhysicsRayQueryParameters3D.create(origin, target)
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
