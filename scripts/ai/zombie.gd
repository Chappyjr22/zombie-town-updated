extends CharacterBody3D
class_name Zombie

enum State { IDLE, CHASE, ATTACK, DEAD }

@export var max_health: float = 100.0
@export var move_speed: float = 3.0
@export var attack_range: float = 1.6
@export var attack_damage: float = 15.0
@export var attack_cooldown: float = 1.2
@export var detection_range: float = 25.0
@export var corpse_lifetime: float = 20.0 ## seconds a ragdolled corpse stays before queue_free(). Set to 0 to keep forever.

var health: float
var state: State = State.IDLE
var attack_timer: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model: Node3D = $Model
@onready var anim_player: AnimationPlayer = NodeUtils.find_first_of_type(model, "AnimationPlayer")
@onready var skeleton: Skeleton3D = NodeUtils.find_first_of_type(model, "Skeleton3D")


func _ready() -> void:
	health = max_health
	add_to_group("zombies")


func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	if attack_timer > 0.0:
		attack_timer -= delta

	var target := _find_nearest_player()
	if target == null:
		state = State.IDLE
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var to_target := target.global_position - global_position
	to_target.y = 0.0
	var distance := to_target.length()

	if distance > detection_range:
		state = State.IDLE
		velocity.x = 0.0
		velocity.z = 0.0
	elif distance <= attack_range:
		state = State.ATTACK
		velocity.x = 0.0
		velocity.z = 0.0
		look_at(Vector3(target.global_position.x, global_position.y, target.global_position.z), Vector3.UP)
		if attack_timer <= 0.0:
			_attack(target)
	else:
		state = State.CHASE
		var dir := to_target.normalized()
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		look_at(Vector3(target.global_position.x, global_position.y, target.global_position.z), Vector3.UP)

	move_and_slide()
	_update_animation()


func _find_nearest_player() -> Node3D:
	var players := get_tree().get_nodes_in_group("player")
	var nearest: Node3D = null
	var nearest_dist := INF
	for p in players:
		if not (p is Node3D):
			continue
		var d := global_position.distance_to(p.global_position)
		if d < nearest_dist:
			nearest_dist = d
			nearest = p
	return nearest


func _attack(target: Node3D) -> void:
	attack_timer = attack_cooldown
	_play_anim(["Attack", "Idle_Attack", "Punch"])
	if target.has_method("take_damage"):
		target.take_damage(attack_damage)


func take_damage(amount: float, hit_impulse: Vector3 = Vector3.ZERO) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if health <= 0.0:
		die(hit_impulse)
	else:
		_play_anim(["HitReact", "HitRecieve"])


func die(hit_impulse: Vector3 = Vector3.ZERO) -> void:
	state = State.DEAD
	set_physics_process(false)
	if anim_player:
		anim_player.stop()
	if collision_shape:
		collision_shape.disabled = true

	if skeleton:
		skeleton.physical_bones_start_simulation()
		var bone := _find_impulse_bone(skeleton)
		if bone and hit_impulse.length() > 0.0:
			bone.apply_central_impulse(hit_impulse)

	if corpse_lifetime > 0.0:
		get_tree().create_timer(corpse_lifetime).timeout.connect(queue_free)


func _find_impulse_bone(root: Node) -> PhysicalBone3D:
	var preferred_names := ["hips", "spine", "chest", "pelvis"]
	var fallback: PhysicalBone3D = null
	for child in root.get_children():
		if child is PhysicalBone3D:
			if fallback == null:
				fallback = child
			for n in preferred_names:
				if String(child.name).to_lower().contains(n):
					return child
		var nested := _find_impulse_bone(child)
		if nested and fallback == null:
			fallback = nested
	return fallback


func _play_anim(names: Array) -> void:
	NodeUtils.play_first_available_animation(anim_player, names)


func _update_animation() -> void:
	match state:
		State.CHASE:
			_play_anim(["Run", "Walk"])
		State.IDLE:
			_play_anim(["Idle"])
		State.ATTACK:
			pass # handled by _attack()
