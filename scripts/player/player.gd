extends CharacterBody3D

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.5
const CROUCH_SPEED := 2.2
const JUMP_VELOCITY := 4.5
const MOUSE_SENSITIVITY := 0.0025
const PITCH_LIMIT := deg_to_rad(89.0)

const STAND_HEIGHT := 1.8
const CROUCH_HEIGHT := 1.1
const CROUCH_LERP_SPEED := 10.0

## Visual layer the third-person body mesh is moved onto so the local camera can
## exclude it (see _hide_own_body_from_camera). Any layer other than 1 (the
## default everything-else layer) works; just has to not collide with something
## else's chosen layer later.
const BODY_VISUAL_LAYER := 2

@export var max_health: float = 100.0

@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model: Node3D = $Model
@onready var camera: Camera3D = $Head/Camera3D
@onready var anim_player: AnimationPlayer = NodeUtils.find_first_of_type(model, "AnimationPlayer")

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_crouching := false
var health: float
var is_dead := false
var was_on_floor := true

signal health_changed(current: float, max: float)
signal died


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health = max_health
	add_to_group("player")
	_hide_own_body_from_camera()


func _hide_own_body_from_camera() -> void:
	for mesh in NodeUtils.find_all_of_type(model, "MeshInstance3D"):
		mesh.layers = 1 << (BODY_VISUAL_LAYER - 1)
	camera.set_cull_mask_value(BODY_VISUAL_LAYER, false)


func take_damage(amount: float) -> void:
	if is_dead:
		return
	health -= amount
	health_changed.emit(health, max_health)
	if health <= 0.0:
		is_dead = true
		died.emit()
		# TODO: no death/respawn flow yet - player just stops taking further damage.


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		head.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		head.rotation.x = clamp(head.rotation.x, -PITCH_LIMIT, PITCH_LIMIT)
	elif event.is_action_pressed("ui_cancel"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and not is_crouching:
		velocity.y = JUMP_VELOCITY

	_update_crouch(delta)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var move_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := WALK_SPEED
	if is_crouching:
		speed = CROUCH_SPEED
	elif Input.is_action_pressed("sprint") and input_dir.y < 0.0:
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
	_update_animation(just_landed)


func _update_crouch(delta: float) -> void:
	is_crouching = Input.is_action_pressed("crouch")
	var target_height := CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	var shape: CapsuleShape3D = collision_shape.shape
	shape.height = move_toward(shape.height, target_height, CROUCH_LERP_SPEED * delta)
	collision_shape.position.y = shape.height / 2.0
	head.position.y = shape.height - 0.15


func _update_animation(just_landed: bool) -> void:
	if anim_player == null:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if not is_on_floor():
		_play_anim(["Jump_Idle", "Jump"])
	elif just_landed:
		_play_anim(["Jump_Land", "Idle"])
	elif is_crouching:
		_play_anim(["Duck", "Idle"])
	elif horizontal_speed > 0.5:
		_play_anim(["Run_Gun", "Run"])
	else:
		_play_anim(["Idle_Shoot", "Idle"])


func _play_anim(names: Array) -> void:
	NodeUtils.play_first_available_animation(anim_player, names)
