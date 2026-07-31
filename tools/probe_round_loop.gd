extends SceneTree
## Drives the round loop and checks it actually runs.
##
##   godot --headless --path . --script tools/probe_round_loop.gd
##
## Loading the level without errors only proves it parsed. This checks the things
## that would silently not happen: rounds starting, zombies arriving from the
## spawn markers, the population cap holding, kills being counted, points being
## awarded at the right rate, and the round advancing once it's cleared.
##
## Time is compressed with `Engine.time_scale` so a several-minute round loop
## runs in seconds. Everything here is driven by `_process` deltas and
## SceneTreeTimers, both of which scale, so the behaviour is the same - just
## faster.

const LEVEL_PATH := "res://scenes/levels/test_arena.tscn"
const TIME_SCALE := 12.0

var failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	Engine.time_scale = TIME_SCALE
	# Physics ticks have to speed up with the clock, or each step covers
	# TIME_SCALE/60 seconds of movement - 0.2s at 12x - and a falling body clears
	# the arena's 1m-thick floor between two steps. The first run of this probe
	# reported the player 559m below the map for exactly that reason, which is a
	# artifact of the harness and not something that happens at normal speed.
	Engine.physics_ticks_per_second = int(60.0 * TIME_SCALE)
	root.add_child((load(LEVEL_PATH) as PackedScene).instantiate())
	await process_frame

	var director := root.get_tree().get_first_node_in_group("round_director") as RoundDirector
	var player := root.get_tree().get_first_node_in_group("player")
	_check(director != null, "round director is in the level")
	_check(player != null, "player is in the level")
	if director == null or player == null:
		_finish()
		return

	_check_tuning()
	# Before round 1 arrives. A live horde shoves the player around - measured at
	# 167m over the course of this probe - and a moving shooter makes the trace
	# untestable.
	await _check_shooting_awards_points(director, player)

	print("\n--- round 1 ---")
	await _wait(6.0)
	_check(director.current_round == 1, "round 1 started (got %d)" % director.current_round)
	_check(
		RoundDirector.round_count(1) == 10,
		"round 1 owes 10 zombies (got %d)" % RoundDirector.round_count(1)
	)

	# Zombies trickle in on a 0.7-1.6s timer, so a few seconds in there should be
	# some on the ground but not the whole round.
	await _wait(8.0)
	var alive := director.alive_count()
	print("  alive after ~8s: %d, still pending: %d" % [alive, director.pending_spawns])
	_check(alive > 0, "zombies actually spawned")
	_check(
		alive <= RoundDirector.MAX_ALIVE,
		"population is within the cap of %d" % RoundDirector.MAX_ALIVE
	)
	_check_spawn_distance(director, player)

	print("\n--- kills and points ---")
	var points_before: int = player.points
	var killed := _kill_all_zombies()
	_check(killed > 0, "killed %d zombies" % killed)
	await _wait(1.0)
	var gained: int = player.points - points_before
	# Killed by hand rather than by shooting, so these go through Zombie.die()
	# without the weapon's hit_confirmed - points come from the shot, so none
	# should have been awarded here. This is checking the wiring is not backwards.
	print("  points gained from direct kills: %d (expected 0 - points come from shots)" % gained)
	_check(director.kills >= killed, "director counted the kills (%d)" % director.kills)

	# The award path proper, exercised the way the weapon controller drives it.
	var expected := RoundDirector.points_for_hit(director.current_round, &"head", true)
	player.award_points(expected)
	_check(
		player.points == points_before + gained + expected,
		"award_points credited %d" % expected
	)

	# The director is held still for this. Regen takes ~20s of game time to
	# observe, the breather is 8s, and a round 2 zombie reaching the player
	# mid-test would reset the delay and fail the check for the wrong reason.
	director.set_process(false)
	await _check_regen(player)
	director.set_process(true)

	print("\n--- round advance ---")
	# The round was cleared by the kills above, so the breather applies rather
	# than the full ROUND_LENGTH.
	await _wait(RoundDirector.ROUND_BREATHER + 3.0)
	_check(
		director.current_round == 2,
		"cleared round advanced to 2 (now %d)" % director.current_round
	)
	_check(
		RoundDirector.round_count(2) == 12,
		"round 2 owes 12 zombies (got %d)" % RoundDirector.round_count(2)
	)
	await _wait(10.0)
	_check(director.alive_count() > 0, "round 2 is spawning")
	# Round 2 zombies must be tougher than round 1's, or the ramp isn't wired to
	# the spawner at all - the curve being right on paper proves nothing.
	var toughest := 0.0
	for zombie in root.get_tree().get_nodes_in_group("zombies"):
		if zombie is Zombie:
			toughest = maxf(toughest, (zombie as Zombie).max_health)
	_check(
		is_equal_approx(toughest, RoundDirector.health_for_round(2)),
		"round 2 zombies spawned with %.0f health (expected %.0f)"
			% [toughest, RoundDirector.health_for_round(2)]
	)

	_finish()


## The curves, checked against the values they were ported from. These are the
## numbers that decide whether the game is playable, and a typo in one would be
## invisible until someone played twenty rounds.
func _check_tuning() -> void:
	print("\n--- tuning ---")
	_check(RoundDirector.round_count(1) == 10, "round 1: 10 zombies")
	_check(RoundDirector.round_count(20) == 48, "round 20: 48 zombies")
	_check(
		is_equal_approx(RoundDirector.round_multiplier(1), 1.0),
		"round 1 multiplier is 1.0"
	)
	_check(
		is_equal_approx(RoundDirector.round_multiplier(11), 2.5),
		"round 11 multiplier is 2.5 (got %.2f)" % RoundDirector.round_multiplier(11)
	)
	_check(
		is_equal_approx(RoundDirector.health_for_round(1), 100.0),
		"round 1 zombie health is 100"
	)
	# 100 + 9*30 + 1*45: the second, steeper term starts biting from round 10.
	_check(
		is_equal_approx(RoundDirector.health_for_round(10), 415.0),
		"round 10 zombie health is 415 (got %.0f)" % RoundDirector.health_for_round(10)
	)
	_check(
		is_equal_approx(RoundDirector.damage_for_round(1), 13.7),
		"round 1 zombie hits for 13.7 (got %.1f)" % RoundDirector.damage_for_round(1)
	)
	# A killing headshot is the chip award plus the head bonus: 10 + 90.
	_check(
		RoundDirector.points_for_hit(1, &"head", true) == 100,
		"round 1 killing headshot pays 100 (got %d)"
			% RoundDirector.points_for_hit(1, &"head", true)
	)
	_check(
		RoundDirector.points_for_hit(1, &"body", true) == 60,
		"round 1 killing body shot pays 60 (got %d)"
			% RoundDirector.points_for_hit(1, &"body", true)
	)
	_check(
		RoundDirector.points_for_hit(1, &"body", false) == 10,
		"round 1 non-killing hit pays 10 (got %d)"
			% RoundDirector.points_for_hit(1, &"body", false)
	)


## Spawns are meant to favour markers far from the player, so nothing appears in
## the player's lap. Checked as a floor on the closest live zombie's spawn side
## rather than exactly, since the pick is randomised by design.
func _check_spawn_distance(director: RoundDirector, player: Node) -> void:
	var closest := INF
	var furthest := 0.0
	print("  player at %v" % player.global_position)
	for zombie in root.get_tree().get_nodes_in_group("zombies"):
		if not (zombie is Node3D):
			continue
		var distance := (zombie as Node3D).global_position.distance_to(player.global_position)
		closest = minf(closest, distance)
		if distance > furthest:
			furthest = distance
			print("    furthest so far: %v (%.1fm)" % [(zombie as Node3D).global_position, distance])
	if closest == INF:
		return
	print("  closest %.1fm, furthest %.1fm" % [closest, furthest])
	# The arena is 60m square and spawn markers sit at most 26m out, so anything
	# beyond the diagonal means a zombie has been flung rather than placed.
	_check(furthest < 80.0, "no zombie has been flung off the map")
	_check(director.alive_count() > 0, "population reported while zombies exist")


## The path that actually matters: a shot that connects has to classify the hit,
## damage the zombie, and pay the player. Every piece of that spans three scripts
## and none of the checks above touch it - killing zombies by hand deliberately
## bypasses it.
func _check_shooting_awards_points(director: RoundDirector, player: Node) -> void:
	print("\n--- shooting pays out ---")
	var controller: WeaponController = player.weapon_controller
	var camera: Camera3D = player.camera
	if controller == null or camera == null:
		_check(false, "player exposes a weapon controller and camera")
		return

	# The player is frozen too. It gets shoved around by contact - by the test
	# zombie here, and by a whole horde later - and a shooter that drifts between
	# staging and firing makes this untestable.
	player.set_physics_process(false)
	await _wait(0.2)

	var expected_chip := RoundDirector.points_for_hit(director.current_round, &"body", false)

	# A shot that wounds. Given far more health than one round can take off.
	var tough := await _place_test_zombie(director, camera, player, 100000.0)
	var before: int = player.points
	controller._hitscan()
	await _wait(0.2)
	var chip: int = player.points - before
	_check(
		chip == expected_chip,
		"a hit that doesn't kill paid %d (expected %d)" % [chip, expected_chip]
	)
	tough.queue_free()

	# A shot that kills, on a fresh target rather than the wounded one. The frozen
	# zombie still drifts a little under the solver, and re-using it meant the
	# second shot sometimes missed - which reads identically to the award being
	# broken, so it has to be ruled out rather than tolerated.
	var frail := await _place_test_zombie(director, camera, player, 1.0)
	before = player.points
	controller._hitscan()
	await _wait(0.2)
	var kill_award: int = player.points - before
	_check(frail.is_dead(), "the zombie died to the shot")
	_check(
		kill_award > expected_chip,
		"the killing shot paid %d, more than the %d chip award" % [kill_award, expected_chip]
	)
	frail.queue_free()
	player.set_physics_process(true)
	await process_frame


## Health has to come back after a lull, and - just as importantly - must not
## start coming back during one. A regen that ignores its delay would quietly
## make the game unloseable.
func _check_regen(player: Node) -> void:
	print("\n--- health regen ---")
	player.take_damage(50.0)
	var wounded: float = player.health
	_check(wounded < player.max_health, "took damage (at %.0f)" % wounded)

	await _wait(Player.REGEN_DELAY * 0.5)
	_check(
		is_equal_approx(player.health, wounded),
		"no healing during the %.1fs delay (at %.0f)" % [Player.REGEN_DELAY, player.health]
	)

	# Past the delay, then long enough to climb well clear of it.
	await _wait(Player.REGEN_DELAY + 2.0)
	_check(
		player.health > wounded,
		"healing after the delay (%.0f -> %.0f)" % [wounded, player.health]
	)
	await _wait(10.0)
	_check(
		is_equal_approx(player.health, player.max_health),
		"healed back to full (at %.0f)" % player.health
	)


## Parks a zombie squarely on the firing ray and confirms the trace reaches it,
## so a later "no points" result can't be a silent miss.
func _place_test_zombie(
	director: RoundDirector,
	camera: Camera3D,
	player: Node,
	health: float
) -> Zombie:
	var forward := -camera.global_transform.basis.z
	var target_point := camera.global_position + forward * 5.0
	var zombie := (
		load("res://scenes/zombies/scary_zombie.tscn") as PackedScene
	).instantiate() as Zombie
	zombie.max_health = health
	# Placed and frozen BEFORE entering the tree - the same fix the director
	# needed. A body added first sits at its parent's origin for one frame and
	# gets shoved out by the solver. The capsule rises from the zombie's origin,
	# so the origin drops half a body height to put its middle on the ray rather
	# than its feet.
	zombie.position = director.to_local(target_point - Vector3(0.0, 0.9, 0.0))
	zombie.set_physics_process(false)
	director.add_child(zombie)
	await _wait(0.2)

	var space := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		camera.global_position,
		camera.global_position + forward * 40.0
	)
	query.exclude = [player.get_rid()]
	var seen := space.intersect_ray(query)
	_check(
		seen and seen.collider == zombie,
		"the camera ray reaches the %.0f-health test zombie (hit %s)"
			% [health, seen.collider.name if seen else "nothing"]
	)
	return zombie


func _kill_all_zombies() -> int:
	var killed := 0
	for zombie in root.get_tree().get_nodes_in_group("zombies"):
		if zombie is Zombie and not (zombie as Zombie).is_dead():
			(zombie as Zombie).take_damage(999999.0)
			killed += 1
	return killed


## Waits `seconds` of *game* time, which `Engine.time_scale` makes a fraction of
## that in wall clock. Passing ignore_time_scale here would wait real seconds
## while the game ran 12x faster, so every duration in this probe would mean
## twelve times what it says - which is exactly the mistake that made the first
## run report 22 zombies in a 10-zombie round.
func _wait(seconds: float) -> void:
	await root.get_tree().create_timer(seconds, true, false, false).timeout


func _check(condition: bool, label: String) -> void:
	print("  %s %s" % ["PASS" if condition else "FAIL", label])
	if not condition:
		failures += 1


func _finish() -> void:
	print("\n%d failures" % failures)
	quit(1 if failures > 0 else 0)
