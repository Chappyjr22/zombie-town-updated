extends Node3D
class_name RoundDirector

## Runs the round loop: how many zombies come, how hard they hit, and when the
## next round starts.
##
## Lives in the level rather than in an autoload, because rounds belong to a
## match and the project has no autoloads (`PhysicsLayers` and `NodeUtils` are
## static `class_name` helpers). It also lines up with how multiplayer has to
## work - see docs/MULTIPLAYER.md - where the host owns this and relays results
## rather than every peer simulating its own rounds.
##
## The tuning below is ported wholesale from the browser build of this game
## (zombie-town-online), where it was play-tested over a lot of rounds. The
## curves are deliberately unchanged; the point of porting was to keep the
## difficulty ramp that already felt right, not to re-derive it.

## Zombies in a round. Two more every round, so round 1 is 10 and round 20 is 48.
const BASE_COUNT := 10
const COUNT_PER_ROUND := 2

## What a kill is worth, as a multiplier on the base awards. Zombies get tougher
## every round, so they have to pay better or the economy stalls out.
const POINTS_MULTIPLIER_PER_ROUND := 0.15

## Points awards, before the round multiplier. Every shot that connects pays
## something, so a player with a weak gun on a high round can still earn - that
## chip damage is the floor of the economy. A kill pays on top of the hit that
## caused it, so a killing headshot is 10 + 90.
const POINTS_HIT := 10.0
const POINTS_KILL_BODY := 50.0
const POINTS_KILL_HEAD := 90.0


## What a hit is worth all-in: the chip award, plus the kill bonus if it killed.
static func points_for_hit(round_number: int, part: StringName, killed: bool) -> int:
	var amount := POINTS_HIT
	if killed:
		amount += POINTS_KILL_HEAD if part == &"head" else POINTS_KILL_BODY
	return int(roundf(amount * round_multiplier(round_number)))

## Zombie health: a flat climb, with a second steeper term from round 10 that
## stops high rounds becoming trivial once the player has good weapons.
const HEALTH_BASE := 100.0
const HEALTH_PER_ROUND := 30.0
const HEALTH_LATE_ROUND_START := 9
const HEALTH_PER_LATE_ROUND := 45.0

## Zombie speed, in m/s. Ramps from a shamble to a sprint and then stops. The
## random spread per zombie is what breaks up the conga line - without it a whole
## round arrives as a single clump.
const SPEED_BASE := 1.5
const SPEED_PER_ROUND := 0.07
const SPEED_MIN := 1.4
const SPEED_MAX := 4.0
const SPEED_VARIANCE := Vector2(0.85, 1.15)

## Zombie melee. Damage climbs with the round so late rounds stay lethal even
## though the player has more health and better positioning.
const DAMAGE_BASE := 13.0
const DAMAGE_PER_ROUND := 0.7

## How many can be alive at once. The cap is what keeps a high round from
## becoming a framerate problem instead of a difficulty one - the rest of the
## round queues up behind it.
const MAX_ALIVE := 30

## Chance a spawned zombie is a shambling walker instead of a runner, so early
## rounds read as a slow, manageable shamble and later rounds read as an
## actual sprint - a mix, not every zombie flipping from walk to run on the
## same round. Flat at 100% through round WALK_CHANCE_FLAT_ROUNDS (the very
## first rounds are walkers only, full stop), then a straight-line ramp down
## to WALK_CHANCE_MIN, timed to land exactly on WALK_CHANCE_FLOOR_ROUND - not
## a fast early drop-off, since a round-20 game where a third of zombies
## still amble over would be a much easier fight than the health/speed/damage
## curves above are assuming.
const WALK_CHANCE_BASE := 1.0
const WALK_CHANCE_MIN := 0.05
const WALK_CHANCE_FLAT_ROUNDS := 3
const WALK_CHANCE_FLOOR_ROUND := 10
## A walker's own move_speed is this fraction of what speed_for_round() would
## otherwise give it - walking at a runner's pace would slide the feet across
## the ground instead of actually stepping.
const WALK_SPEED_FRACTION := 0.55

## Gap between spawns, randomised so they trickle in rather than arriving in
## lockstep. Re-checked on this interval while the population is capped.
const SPAWN_INTERVAL := Vector2(0.7, 1.6)
const SPAWN_RETRY_INTERVAL := 1.5

## The next round starts on this timer whether or not the current one is cleared,
## so hiding from the last two zombies of a round doesn't stall the game.
const ROUND_LENGTH := 150.0

## How long the breather is once a round is actually cleared. The browser build
## made you wait out the full 150s or press a key to skip; that key doesn't exist
## here, and standing in an empty map for two minutes is not a mechanic worth
## porting. Clearing a round fast should be rewarded with the next one, not with
## a wait.
const ROUND_BREATHER := 8.0

## How far a spawn is nudged off its marker, so a spawn point doesn't stamp every
## zombie on the same square metre.
const SPAWN_JITTER := 2.5

## Candidate spawn points sampled per spawn; the one furthest from the player
## wins. Sampling beats sorting here - it keeps spawns mostly-distant without
## making them predictable, which is what picking the single furthest would do.
const SPAWN_CANDIDATES := 7

## Zombie scenes to spawn from, picked at random. All three share the AI contract
## in zombie.gd.
@export var zombie_scenes: Array[PackedScene] = []
## Where zombies come from. Any Marker3D under this node is used; failing that,
## the director falls back to a ring around the origin so a level without markers
## still runs instead of silently spawning nothing.
@export var spawn_points_from_children := true
@export var fallback_spawn_radius := 30.0
## Rounds begin automatically. Turn off to drive `start_round()` from a lobby.
@export var autostart := true
@export var autostart_delay := 3.0

var current_round := 0
var pending_spawns := 0
var spawn_timer := 0.0
var round_timer := 0.0
var running := false
var kills := 0

var _spawn_points: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()

## `total` is how many the round will spawn, not how many are alive.
signal round_started(round_number: int, total: int)
## Fired once when the last zombie of a round dies and none are left to spawn.
signal round_cleared(round_number: int)
## `alive` counts zombies in the world; `pending` counts ones still to come.
signal population_changed(alive: int, pending: int)
## Seconds until the next round starts on its own.
signal round_timer_changed(seconds_left: float)


func _ready() -> void:
	_rng.randomize()
	add_to_group("round_director")
	_collect_spawn_points()
	if autostart:
		# A beat before the first round so the player isn't fighting during the
		# level's first frames, while the navmesh and models are still settling.
		# process_always=false so this respects a pause - SceneTreeTimer defaults
		# to counting through one, which would spawn a round on schedule under a
		# paused menu instead of waiting for the player to actually resume.
		get_tree().create_timer(autostart_delay, false).timeout.connect(start_round)


func _process(delta: float) -> void:
	if not running:
		return
	_update_spawning(delta)
	round_timer -= delta
	round_timer_changed.emit(maxf(round_timer, 0.0))
	if round_timer <= 0.0:
		start_round()


func start_round() -> void:
	running = true
	current_round += 1
	pending_spawns = round_count(current_round)
	spawn_timer = 0.0
	round_timer = ROUND_LENGTH
	round_started.emit(current_round, pending_spawns)
	_emit_population()


## Zombies in a given round.
static func round_count(round_number: int) -> int:
	return BASE_COUNT + (round_number - 1) * COUNT_PER_ROUND


## What a kill in this round is worth, as a multiplier on the base award.
static func round_multiplier(round_number: int) -> float:
	return 1.0 + float(maxi(round_number, 1) - 1) * POINTS_MULTIPLIER_PER_ROUND


static func health_for_round(round_number: int) -> float:
	return (
		HEALTH_BASE
		+ float(round_number - 1) * HEALTH_PER_ROUND
		+ float(maxi(0, round_number - HEALTH_LATE_ROUND_START)) * HEALTH_PER_LATE_ROUND
	)


static func damage_for_round(round_number: int) -> float:
	return DAMAGE_BASE + float(round_number) * DAMAGE_PER_ROUND


func speed_for_round(round_number: int) -> float:
	var base := clampf(
		SPEED_BASE + float(round_number - 1) * SPEED_PER_ROUND,
		SPEED_MIN,
		SPEED_MAX
	)
	return base * _rng.randf_range(SPEED_VARIANCE.x, SPEED_VARIANCE.y)


static func walk_chance_for_round(round_number: int) -> float:
	if round_number <= WALK_CHANCE_FLAT_ROUNDS:
		return WALK_CHANCE_BASE
	var ramp_rounds := WALK_CHANCE_FLOOR_ROUND - WALK_CHANCE_FLAT_ROUNDS
	var t := float(round_number - WALK_CHANCE_FLAT_ROUNDS) / float(ramp_rounds)
	return lerpf(WALK_CHANCE_BASE, WALK_CHANCE_MIN, clampf(t, 0.0, 1.0))


func alive_count() -> int:
	var alive := 0
	for zombie in get_tree().get_nodes_in_group("zombies"):
		if zombie is Zombie and not zombie.is_dead():
			alive += 1
	return alive


## Alive plus not-yet-spawned - what the HUD calls "remaining", since from the
## player's side a zombie that hasn't walked in yet is still one they have to
## deal with.
func remaining_count() -> int:
	return alive_count() + pending_spawns


func _update_spawning(delta: float) -> void:
	if pending_spawns <= 0:
		return
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	# Held back rather than dropped: the round still owes these zombies, they just
	# wait for room. Re-checked on a slower timer so a capped population isn't
	# re-testing every frame.
	if alive_count() >= MAX_ALIVE:
		spawn_timer = SPAWN_RETRY_INTERVAL
		return
	_spawn_one()
	pending_spawns -= 1
	spawn_timer = _rng.randf_range(SPAWN_INTERVAL.x, SPAWN_INTERVAL.y)
	_emit_population()


func _spawn_one() -> void:
	if zombie_scenes.is_empty() or _spawn_points.is_empty():
		return
	var scene: PackedScene = zombie_scenes[_rng.randi() % zombie_scenes.size()]
	var zombie := scene.instantiate() as Zombie
	if zombie == null:
		push_warning("A scene in zombie_scenes is not a Zombie; skipping.")
		return

	# Set before add_child, because zombie.gd copies max_health into health in
	# _ready() - assigning afterwards would leave it on the scene's default.
	zombie.max_health = health_for_round(current_round)
	zombie.move_speed = speed_for_round(current_round)
	zombie.attack_damage = damage_for_round(current_round)
	# A mix of walkers and runners rather than every zombie on the same gait -
	# see walk_chance_for_round()/WALK_SPEED_FRACTION's own comments.
	if _rng.randf() < walk_chance_for_round(current_round):
		zombie.gait = &"Walk"
		zombie.move_speed *= WALK_SPEED_FRACTION

	var origin := _pick_spawn_point()
	zombie.died.connect(_on_zombie_died)
	# Positioned BEFORE it enters the tree, not after.
	#
	# A body added with add_child() exists at its parent's origin for the frame
	# between being added and being moved, and the physics engine resolves that
	# frame's overlaps before the move lands. With the director at the middle of
	# the map that is exactly where the player stands, so every spawn briefly
	# shared a capsule with them and the solver blasted them apart - measured at
	# 4,800 m/s, straight off the map. Local, because global_position needs a
	# node that is already in the tree.
	zombie.position = to_local(origin)
	add_child(zombie)

	var player := _nearest_player()
	if player == null:
		return
	var target := player.global_position
	var facing := Vector3(target.x, zombie.global_position.y, target.z)
	# look_at throws when the target coincides with the node's own position, which
	# a spawn marker sitting under the player would do.
	if zombie.global_position.distance_squared_to(facing) > 0.0001:
		zombie.look_at(facing, Vector3.UP)


## Samples a handful of spawn points and takes whichever is furthest from the
## player, so zombies come from across the map instead of materialising behind
## the player's shoulder.
func _pick_spawn_point() -> Vector3:
	var player := _nearest_player()
	var best: Vector3 = _spawn_points[_rng.randi() % _spawn_points.size()]
	if player != null:
		var origin := player.global_position
		var best_distance := -1.0
		for candidate_index in SPAWN_CANDIDATES:
			var candidate: Vector3 = _spawn_points[_rng.randi() % _spawn_points.size()]
			var distance := Vector2(candidate.x - origin.x, candidate.z - origin.z).length()
			if distance > best_distance:
				best_distance = distance
				best = candidate
	return best + Vector3(
		_rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER),
		0.0,
		_rng.randf_range(-SPAWN_JITTER, SPAWN_JITTER)
	)


func _nearest_player() -> Node3D:
	for node in get_tree().get_nodes_in_group("player"):
		if node is Node3D:
			return node as Node3D
	return null


func _collect_spawn_points() -> void:
	_spawn_points.clear()
	if spawn_points_from_children:
		for child in get_children():
			if child is Marker3D:
				_spawn_points.append((child as Marker3D).global_position)
	if not _spawn_points.is_empty():
		return
	# No markers placed. A ring keeps the level playable rather than failing
	# silently with a round that spawns nothing.
	push_warning(
		"RoundDirector has no Marker3D children; falling back to a %.0fm ring."
		% fallback_spawn_radius
	)
	for index in 12:
		var angle := TAU * float(index) / 12.0
		_spawn_points.append(
			global_position
			+ Vector3(cos(angle), 0.0, sin(angle)) * fallback_spawn_radius
		)


func _on_zombie_died(zombie: Zombie) -> void:
	kills += 1
	_maybe_drop_power_up(zombie.global_position)
	_emit_population()
	# Deferred: the zombie that just died is still in the "zombies" group for the
	# rest of this frame, so counting now would report one too many alive and the
	# round would never read as cleared.
	_check_round_cleared.call_deferred()


## Ported from zombie-town-online's maybeDrop(): a small random chance per
## kill, but a *guaranteed* drop every POWER_UP_GUARANTEED_EVERY kills so a
## long unlucky streak can't leave a run completely without one. kills is
## already incremented by the time this runs, matching the source's own
## `game.kills++` before `maybeDrop()`.
const POWER_UP_DROP_CHANCE := 0.028
const POWER_UP_GUARANTEED_EVERY := 60
const POWER_UP_KINDS: Array[StringName] = [
	&"maxammo", &"instakill", &"doublepoints", &"nuke", &"firesale"
]


func _maybe_drop_power_up(at: Vector3) -> void:
	var guaranteed := kills % POWER_UP_GUARANTEED_EVERY == 0
	if not guaranteed and _rng.randf() > POWER_UP_DROP_CHANCE:
		return
	var drop := PowerUpDrop.new()
	drop.kind = POWER_UP_KINDS[_rng.randi() % POWER_UP_KINDS.size()]
	# Local position, set before add_child() - not after. See _spawn_one()'s
	# own comment above for why: a body placed after entering the tree exists
	# at its parent's origin for a frame first.
	drop.position = to_local(at)
	add_child(drop)


func _check_round_cleared() -> void:
	if pending_spawns > 0 or alive_count() > 0:
		return
	round_cleared.emit(current_round)
	# Never extends the round - a round already inside its last few seconds keeps
	# the shorter of the two, so clearing late doesn't buy extra time.
	round_timer = minf(round_timer, ROUND_BREATHER)


func _emit_population() -> void:
	population_changed.emit(alive_count(), pending_spawns)
