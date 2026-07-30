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

@export var max_health: float = 100.0

@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_crouching := false
var health: float
var is_dead := false

signal health_changed(current: float, max: float)
signal died


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	health = max_health
	add_to_group("player")


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


func _update_crouch(delta: float) -> void:
	is_crouching = Input.is_action_pressed("crouch")
	var target_height := CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	var shape: CapsuleShape3D = collision_shape.shape
	shape.height = move_toward(shape.height, target_height, CROUCH_LERP_SPEED * delta)
	collision_shape.position.y = shape.height / 2.0
	head.position.y = shape.height - 0.15
