extends CharacterBody3D
class_name Zombie

enum State { IDLE, CHASE, ATTACK, DEAD }

@export var max_health: float = 100.0
@export var move_speed: float = 3.0
@export var attack_range: float = 1.6
@export var attack_damage: float = 15.0
@export var attack_cooldown: float = 1.2
## No stealth mechanic exists anywhere in this game - a zombie spawned into a
## round should always know where the player is and start closing the
## distance immediately. Bug found by testing: the old default (25.0) was
## smaller than the distance from every spawn marker on both levels to the
## player's own start position (test_arena's closest spawn is ~29m out,
## town.tscn's spawns run up to ~57m), so every zombie sat frozen in IDLE from
## the moment it spawned until the player happened to close that gap - looked
## exactly like "zombies aren't pathing" but was really "zombies can't even
## see the player yet." Set high enough to be effectively unlimited for
## either level rather than tuned to a specific map size.
@export var detection_range: float = 1000.0
@export var corpse_lifetime: float = 20.0 ## seconds a ragdolled corpse stays before queue_free(). Set to 0 to keep forever.
## Playtest showed zombies chasing with their backs to the player - the model's
## authored front doesn't match the -Z forward that look_at() (used for facing
## the player) assumes. 180 is a first guess since it looked like an exact
## backward mismatch, not an arbitrary angle; if it's still wrong, select the
## Model node under this zombie scene and adjust its Y rotation in
## the Inspector directly.
@export var model_yaw_offset_degrees := 180.0

## How close to the head bone a shot has to land to count as a headshot. Sized
## against the head bone's origin, which sits at the base of the skull, so this
## covers the head and not much neck.
const HEADSHOT_RADIUS := 0.28
## Both remaining rigs (scary_zombie, cop_zombie) are Mixamo and use this name.
const HEAD_BONE_NAMES := ["mixamorig_Head"]

## Wider than the movement capsule ($CollisionShape3D, kept tight so crowds of
## zombies don't shove each other around even harder - see "Zombies shove the
## player" in scripts/ai/CLAUDE.md). A zombie's outstretched arms reach well
## past that capsule, so shots landing on them need a separate, more generous
## target to land on at all; classify_hit() still scores head vs. body off the
## live head bone regardless of which hitbox the shot actually landed on.
## Default is a reasonable average - each scene overrides it to fit its own
## model's measured silhouette (see PhysicsLayers.HITBOX's own comment).
@export var hitbox_size: Vector3 = Vector3(2.0, 1.9, 0.6)
@export var hitbox_center: Vector3 = Vector3(0, 0.8, 0)

var health: float
var state: State = State.IDLE
var attack_timer: float = 0.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var locked_animation: StringName = &""
var attack_animation_index := 0
var navigation_agent: NavigationAgent3D
var _head_bone_index := -1
## Set by RoundDirector before add_child() - see _spawn_one()'s own comment on
## why things get set before entering the tree, not after. Defaults to Run so
## a hand-placed zombie (test_arena.tscn, or anything not spawned through the
## round loop) behaves exactly as it always has.
var gait: StringName = &"Run"
var hitbox_area: Area3D

## Emitted once, when this zombie dies. `RoundDirector` counts rounds off this,
## so it must fire exactly once - `die()` is guarded by the DEAD state.
signal died(zombie: Zombie)

@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var model: Node3D = $Model
@onready var anim_player: AnimationPlayer = NodeUtils.find_first_of_type(model, "AnimationPlayer")
@onready var skeleton: Skeleton3D = NodeUtils.find_first_of_type(model, "Skeleton3D")
## "Create Physical Skeleton" creates this as a child of Skeleton3D, holding
## the actual PhysicalBone3D nodes - modern Godot's real owner of
## physical_bones_start/stop_simulation(). Skeleton3D itself still exposes
## same-named convenience methods, but calling them silently did nothing in
## testing (no error, bones just sat inert instead of falling) - calling them
## on this node directly instead is what actually works.
@onready var physical_bone_simulator: PhysicalBoneSimulator3D = (
	NodeUtils.find_first_of_type(model, "PhysicalBoneSimulator3D")
)


func _ready() -> void:
	health = max_health
	add_to_group("zombies")
	collision_layer = PhysicsLayers.ACTORS
	collision_mask = PhysicsLayers.WORLD | PhysicsLayers.ACTORS

	# "Create Physical Skeleton" in the editor adds PhysicalBone3D nodes that
	# exist (and can collide) immediately, even before physical_bones_start_simulation()
	# is ever called - they were still on the default layer, which overlapped
	# this zombie's own standing capsule collider from frame one, so it
	# exploded on its own the instant the scene loaded, with no death involved.
	# Isolating them onto the RAGDOLL layer here, not just in die(), fixes that.
	_isolate_ragdoll_bones()
	if physical_bone_simulator:
		physical_bone_simulator.physical_bones_stop_simulation()
	model.rotation_degrees.y = model_yaw_offset_degrees
	if anim_player:
		_install_run_override()
		_configure_animation_loops()
		anim_player.animation_finished.connect(_on_animation_finished)
	if skeleton:
		for bone_name in HEAD_BONE_NAMES:
			_head_bone_index = skeleton.find_bone(bone_name)
			if _head_bone_index >= 0:
				break
	_setup_navigation()
	_setup_hitbox()


## Optional: assets/animations/zombies/run.res, if present, replaces the
## model's own baked-in Run clip. Built with the same FBX->res pipeline as
## the player's locomotion packs (tools/build_clips.gd, just pointed at a
## "zombies" output folder instead of a player locomotion set) - the track
## paths address bones by name ("Skeleton3D:mixamorig_*"), which both this
## rig and the player's share, so nothing about the extraction needed to
## change for a different skeleton. Installed under the exact name "Run" so
## _find_animation()'s exact-match check picks it over the model's own
## differently-prefixed baked-in clip (e.g. "Armature|Run") without every
## _play_anim([.... &"Run" ....]) call site needing to know it exists.
## Purely additive - nothing here changes if the file doesn't exist.
const RUN_OVERRIDE_PATH := "res://assets/animations/zombies/run.res"


func _install_run_override() -> void:
	if not ResourceLoader.exists(RUN_OVERRIDE_PATH):
		return
	var library := anim_player.get_animation_library(&"")
	if library.has_animation(&"Run"):
		library.remove_animation(&"Run")
	library.add_animation(&"Run", load(RUN_OVERRIDE_PATH))


## A wider, hitscan-only Area3D on the HITBOX layer - see this var's own doc
## comment and PhysicsLayers.HITBOX for why the movement capsule alone isn't
## enough. collision_mask is 0: this only needs to be found BY a raycast, it
## never needs to detect anything itself.
func _setup_hitbox() -> void:
	var area := Area3D.new()
	area.name = "HitboxArea"
	area.collision_layer = PhysicsLayers.HITBOX
	area.collision_mask = 0
	add_child(area)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = hitbox_size
	shape.shape = box
	shape.position = hitbox_center
	area.add_child(shape)
	hitbox_area = area


## Adds the pathfinding agent in code rather than to each zombie scene
## variant, so they can't drift apart on it.
##
## Whether it's actually used is decided per frame by `_has_navigation_mesh()`:
## the flat test arena has no baked navmesh and doesn't need one, and a level
## without one should still get zombies that walk at you rather than zombies that
## stand still waiting for a path that will never come.
func _setup_navigation() -> void:
	navigation_agent = NavigationAgent3D.new()
	navigation_agent.name = "NavigationAgent3D"
	# Sized to the capsule. The separation radius keeps a round from stacking
	# every zombie into the same column as they funnel toward the player.
	navigation_agent.radius = 0.45
	navigation_agent.height = 1.8
	navigation_agent.path_desired_distance = 0.6
	navigation_agent.target_desired_distance = attack_range * 0.8
	navigation_agent.avoidance_enabled = false
	add_child(navigation_agent)


func _has_navigation_mesh() -> bool:
	if navigation_agent == null:
		return false
	var map := navigation_agent.get_navigation_map()
	return map.is_valid() and not NavigationServer3D.map_get_regions(map).is_empty()


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
		var dir := _chase_direction(target, to_target)
		velocity.x = dir.x * move_speed
		velocity.z = dir.z * move_speed
		# Faces where it is going, not where the player is - otherwise a zombie
		# routing around a building walks sideways with its head turned.
		var facing := global_position + dir
		look_at(Vector3(facing.x, global_position.y, facing.z), Vector3.UP)

	move_and_slide()
	_update_animation()


## Which way to walk this frame: around obstacles where the level has a navmesh,
## straight at the player where it doesn't.
func _chase_direction(target: Node3D, to_target: Vector3) -> Vector3:
	if not _has_navigation_mesh():
		return to_target.normalized()
	navigation_agent.target_position = target.global_position
	if navigation_agent.is_navigation_finished():
		return to_target.normalized()
	var step := navigation_agent.get_next_path_position() - global_position
	step.y = 0.0
	# A degenerate step means the agent is standing on its own waypoint; walking
	# at the player beats stalling until the next path update.
	if step.length_squared() < 0.0001:
		return to_target.normalized()
	return step.normalized()


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
	var attack_variants := [&"Attack", &"Bite", &"BiteAlt", &"NeckBite"]
	var selected_attack: StringName = attack_variants[
		attack_animation_index % attack_variants.size()
	]
	attack_animation_index += 1
	_play_anim(
		[selected_attack, &"Attack", &"Idle_Attack", &"Punch"],
		true,
		true
	)
	if target.has_method("take_damage"):
		target.take_damage(attack_damage)


func take_damage(amount: float, hit_impulse: Vector3 = Vector3.ZERO) -> void:
	if state == State.DEAD:
		return
	health -= amount
	if health <= 0.0:
		die(hit_impulse)
	# No hit-reaction animation - it interrupted the chase/attack the zombie
	# was already doing every time it took chip damage, which read as
	# stuttery with several zombies converging and shooting overlapping.
	# Matches the same call made for the player - see player.gd's take_damage.


func is_dead() -> bool:
	return state == State.DEAD


## Whether a shot that landed at `world_position` hit the head, measured against
## the live head bone rather than a height threshold - so a crouched, lunging or
## mid-death-animation zombie is still scored on where its head actually is.
##
## Falls back to body on a rig with no recognisable head bone, which costs the
## player a bonus rather than handing them one for a miss.
func classify_hit(world_position: Vector3) -> StringName:
	if skeleton == null or _head_bone_index < 0:
		return &"body"
	var head := skeleton.global_transform * skeleton.get_bone_global_pose(_head_bone_index).origin
	return &"head" if head.distance_to(world_position) <= HEADSHOT_RADIUS else &"body"


func die(_hit_impulse: Vector3 = Vector3.ZERO) -> void:
	if state == State.DEAD:
		return
	state = State.DEAD
	died.emit(self)
	set_physics_process(false)
	if collision_shape:
		collision_shape.disabled = true
	# Bug found by testing: a dead zombie kept blocking hitscan shots aimed at
	# anything standing behind it, because only the movement capsule above got
	# disabled here - HitboxArea (a separate, wider Area3D specifically so
	# shots can land on outstretched arms; see that var's own comment) was
	# never touched and stayed on PhysicsLayers.HITBOX forever, discoverable
	# by a raycast for the full corpse_lifetime. Moving it off that layer
	# (rather than just disabling its CollisionShape3D) is what actually
	# removes it from consideration - collide_with_areas raycasts test layers,
	# not per-shape disabled state.
	if hitbox_area:
		hitbox_area.collision_layer = 0

	# Physics ragdoll (PhysicalBoneSimulator3D) kept stretching limbs into long
	# spikes on this rig even after excluding finger/tongue/eyelid bones - a
	# deeper joint/shape mismatch that needs hands-on tuning in the editor to
	# fix properly. Falling back to the model's own authored "Death" clip
	# instead: no physics tuning needed, and it's guaranteed to look right
	# since it's professionally animated. `_play_anim` leaves it holding on
	# its last frame once finished, which is exactly the collapsed pose we
	# want for a corpse. Revisit physics ragdoll later if it's worth another
	# pass - see PhysicsLayers.RAGDOLL / _isolate_ragdoll_bones /
	# _ragdoll_bone_names below, still here but unused for now.
	_play_anim([&"Death", &"DeathAlt"], true, true)

	if corpse_lifetime > 0.0:
		# process_always=false so a corpse doesn't clean itself up mid-pause.
		get_tree().create_timer(corpse_lifetime, false).timeout.connect(queue_free)


## This rig has small detail bones beyond the main skeleton (fingers, tongue,
## eyelids, IK pole targets) - simulating physics on all of them made the
## corpse's mesh stretch into long spikes, since a lightweight bone like a
## tongue segment gets flung around by physics forces and drags its narrow
## skin weighting into a thin stretched blob. Excluding them by name pattern
## and simulating only the main body chain (torso/limbs/head) avoids that.
const RAGDOLL_EXCLUDE_PATTERNS := [
	"tongue", "eyelid", "pinky", "middle", "index", "thumb", "poletarget", "_end",
]


func _ragdoll_bone_names() -> Array:
	var names: Array = []
	if skeleton == null:
		return names
	for i in range(skeleton.get_bone_count()):
		var bone_name: String = skeleton.get_bone_name(i)
		var lower := bone_name.to_lower()
		var excluded := false
		for pattern in RAGDOLL_EXCLUDE_PATTERNS:
			if lower.contains(pattern):
				excluded = true
				break
		if not excluded:
			names.append(bone_name)
	return names


## Ragdoll bones only collide with the world (ground), never the player or
## other zombies - otherwise they overlap a living actor's capsule (either
## this zombie's own, from the moment "Create Physical Skeleton" adds them, or
## another actor's at death since zombies die at melee range) and the physics
## engine violently shoves them apart instead of just resting/falling over.
func _isolate_ragdoll_bones() -> void:
	if skeleton == null:
		return
	for physical_bone in NodeUtils.find_all_of_type(skeleton, "PhysicalBone3D"):
		physical_bone.collision_layer = PhysicsLayers.RAGDOLL
		physical_bone.collision_mask = PhysicsLayers.WORLD


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


func _find_animation(names: Array) -> StringName:
	if anim_player == null:
		return &""
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


func _play_anim(
	names: Array,
	lock_until_finished := false,
	force_restart := false
) -> void:
	var animation_name := _find_animation(names)
	if animation_name == &"":
		return
	if (
		not force_restart
		and anim_player.current_animation == animation_name
		and anim_player.is_playing()
	):
		return
	if lock_until_finished:
		locked_animation = animation_name
	anim_player.play(animation_name, 0.12)


func _configure_animation_loops() -> void:
	for requested_name in [
		&"Idle",
		&"Idle_Attack",
		&"Walk",
		&"Run",
		&"Crawl",
		&"CrawlRun",
	]:
		var animation_name := _find_animation([requested_name])
		if animation_name != &"":
			anim_player.get_animation(animation_name).loop_mode = Animation.LOOP_LINEAR
	for requested_name in [
		&"Attack",
		&"Bite",
		&"BiteAlt",
		&"NeckBite",
		&"Death",
		&"DeathAlt",
	]:
		var animation_name := _find_animation([requested_name])
		if animation_name != &"":
			anim_player.get_animation(animation_name).loop_mode = Animation.LOOP_NONE


func _on_animation_finished(animation_name: StringName) -> void:
	if animation_name == locked_animation:
		locked_animation = &""


func _update_animation() -> void:
	if locked_animation != &"":
		return
	match state:
		State.CHASE:
			# gait ([&"Walk"] or [&"Run"], assigned by RoundDirector before this
			# zombie entered the tree - see that var's own comment) is tried
			# first; Run is still the fallback if a rig is somehow missing the
			# assigned clip, matching the pre-gait default.
			_play_anim([gait, &"Run", &"Walk"])
		State.IDLE:
			_play_anim([&"Idle"])
		State.ATTACK:
			_play_anim([&"Idle_Attack", &"Idle"])
