extends SceneTree
## Generates scenes/levels/test_kenney_town.tscn: a small demo neighborhood
## block built from the free Kenney "City Kit (Suburban)" pack
## (assets/models/props/city-kit-suburban/ - see ASSET_MANIFEST.md), to prove
## out laying out real downloaded assets into a walkable street before
## committing to replacing the main procedural town.tscn with anything.
##
##   godot --headless --path . --script tools/build_test_kenney_town.gd
##
## Not a replacement for town.tscn or its build tool (tools/build_town_level.gd)
## - this is a standalone proving ground, same spirit as scenes/levels/test_arena.tscn.
##
## SCALE is the load-bearing number here: measured by probe, the kit's models
## run ~0.9-1.8m footprint / ~0.75-1.25m tall - a toy/diorama scale, smaller
## than the 1.8m player capsule, not the 1-unit-per-meter scale the rest of
## this project's assets use. 6.0 was picked to land single-story houses in a
## believable 4.4-11m range; see ASSET_MANIFEST.md's own note on this pack.
const SCALE := 6.0

const KIT_DIR := "res://assets/models/props/city-kit-suburban/"
const SCENE_PATH := "res://scenes/levels/test_kenney_town.tscn"

## Two facing rows of houses either side of a shared street centreline (Z=0).
## Picked for silhouette variety across the alphabet rather than any
## particular reason - swap freely. Different letters per row so the two
## sides don't look like mirror images of each other.
const NORTH_ROW := ["building-type-b", "building-type-e", "building-type-h", "building-type-k", "building-type-n", "building-type-q"]
const SOUTH_ROW := ["building-type-a", "building-type-d", "building-type-g", "building-type-j", "building-type-m", "building-type-p"]
const LOT_GAP := 3.0 ## Real-world metres between adjacent building footprints.
const SETBACK := 5.0 ## How far back from the street centreline each house sits.

var level_root: Node3D
var geometry_root: Node3D
var mesh_cache: Dictionary = {} ## path -> Mesh, so repeated instances (trees, fences) don't reload.


func _initialize() -> void:
	_generate()


func _generate() -> void:
	if ResourceLoader.exists(SCENE_PATH):
		push_warning("%s already exists - not overwriting. Delete it first to regenerate." % SCENE_PATH)
		quit()
		return

	level_root = Node3D.new()
	level_root.name = "TestKenneyTown"

	_build_environment()
	_build_ground()
	geometry_root = NavigationRegion3D.new()
	geometry_root.name = "NavigationRegion3D"
	geometry_root.navigation_mesh = NavigationMesh.new()
	level_root.add_child(geometry_root)

	_build_street()
	_place_player_and_light_test_zombie()

	_claim_ownership(level_root, level_root)

	root.add_child(level_root)
	await process_frame
	await process_frame
	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationMeshGenerator.parse_source_geometry_data(geometry_root.navigation_mesh, source_geometry, geometry_root)
	NavigationMeshGenerator.bake_from_source_geometry_data(geometry_root.navigation_mesh, source_geometry)
	print("Baked nav mesh: %d vertices, %d polygons" % [
		geometry_root.navigation_mesh.get_vertices().size(), geometry_root.navigation_mesh.get_polygon_count()
	])

	var packed := PackedScene.new()
	packed.pack(level_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://scenes/levels"))
	var err := ResourceSaver.save(packed, SCENE_PATH)
	if err != OK:
		push_error("Failed to save %s: %s" % [SCENE_PATH, err])
		quit(1)
		return
	print("Wrote ", SCENE_PATH)
	quit()


func _claim_ownership(owner_root: Node, node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_root
		if child.scene_file_path == "":
			_claim_ownership(owner_root, child)


# ---------------------------------------------------------------- environment


func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.transform = Transform3D(
		Basis(Vector3(1, 0, 0), deg_to_rad(-50.0)) * Basis(Vector3(0, 1, 0), deg_to_rad(25.0)),
		Vector3.ZERO
	)
	sun.shadow_enabled = true
	level_root.add_child(sun)

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky
	world_env.environment = env
	level_root.add_child(world_env)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	level_root.add_child(ground)

	# Sized with margin around the two facing rows (~67m wide each, centred on
	# X=0) - the original single-row layout ran past a same-sized ground plane
	# because it started at X=0 instead of being centred, not because the
	# ground was too small.
	var size := Vector3(100.0, 1.0, 50.0)
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.34, 0.28)
	mesh_instance.material_override = mat
	mesh_instance.position.y = -0.5
	ground.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position.y = -0.5
	ground.add_child(collision)


# --------------------------------------------------------------------- street


## Builds two rows of houses facing each other across a shared street
## centreline (Z=0), each row centred on X=0 so it can't run past a
## same-sized ground plane the way a single row starting at X=0 did. Every
## lot is authored assuming its own local +Z is "toward the street"; the row
## builder rotates the whole lot 180 degrees for the row on the far side, so
## the same per-lot logic (driveway/path/fence/tree placement) works for
## both without duplicating it.
func _build_street() -> void:
	var street := Node3D.new()
	street.name = "Street"
	geometry_root.add_child(street)

	var row_span: float = max(_measure_row_width(NORTH_ROW), _measure_row_width(SOUTH_ROW))
	_build_row(street, NORTH_ROW, SETBACK, PI, row_span) ## far side, faces -Z (toward street)
	_build_row(street, SOUTH_ROW, -SETBACK, 0.0, row_span) ## near side, faces +Z (toward street)


func _measure_row_width(names: Array) -> float:
	var total := 0.0
	for i in names.size():
		total += _measure_raw(names[i]).size.x * SCALE
		if i < names.size() - 1:
			total += LOT_GAP
	return total


func _build_row(parent: Node3D, names: Array, z_position: float, facing_y_rotation: float, row_span: float) -> void:
	var cursor_x := -row_span * 0.5
	for i in names.size():
		var building_name: String = names[i]
		var bounds := _measure_raw(building_name)
		var scaled_width := bounds.size.x * SCALE
		var scaled_depth := bounds.size.z * SCALE
		var lot_x := cursor_x + scaled_width * 0.5

		var lot := Node3D.new()
		lot.name = "Lot%d_%s_%s" % [i, ("north" if z_position > 0.0 else "south"), building_name]
		lot.position = Vector3(lot_x, 0.0, z_position)
		lot.rotation.y = facing_y_rotation
		parent.add_child(lot)

		var building := _instance_with_collision(building_name)
		building.scale = Vector3.ONE * SCALE
		# Bounds are measured in the model's own unscaled local space, so the
		# offset needed to sit its base on the ground (rather than however
		# its origin happens to be authored) is bounds.position.y, scaled.
		building.position.y = -bounds.position.y * SCALE
		lot.add_child(building)

		var driveway := _instance_no_collision("driveway-short")
		driveway.scale = Vector3.ONE * SCALE
		driveway.position = Vector3(0.0, 0.0, scaled_depth * 0.5 + SETBACK * 0.5)
		lot.add_child(driveway)

		var path := _instance_no_collision("path-short")
		path.scale = Vector3.ONE * SCALE
		path.position = Vector3(0.0, 0.0, scaled_depth * 0.5 + 0.6)
		lot.add_child(path)

		if i < names.size() - 1:
			var fence := _instance_with_collision("fence-2x2")
			fence.scale = Vector3.ONE * SCALE
			fence.position = Vector3(scaled_width * 0.5 + LOT_GAP * 0.5, 0.0, 0.0)
			lot.add_child(fence)

		if i % 2 == 0:
			var tree := _instance_no_collision("tree-large")
			tree.scale = Vector3.ONE * SCALE
			tree.position = Vector3(-scaled_width * 0.3, 0.0, SETBACK * 0.5)
			lot.add_child(tree)

		cursor_x += scaled_width + LOT_GAP


# ----------------------------------------------------------------- instancing


func _load_mesh(model_name: String) -> Mesh:
	if mesh_cache.has(model_name):
		return mesh_cache[model_name]
	var scene: PackedScene = load(KIT_DIR + model_name + ".glb")
	var instance: Node3D = scene.instantiate()
	var mesh: Mesh = _find_mesh(instance)
	instance.free()
	mesh_cache[model_name] = mesh
	return mesh


func _find_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for child in node.get_children():
		var found := _find_mesh(child)
		if found != null:
			return found
	return null


## Measures a model's own local-space AABB straight from its mesh, before any
## scale is applied - the same raw numbers the probe that picked SCALE used.
func _measure_raw(model_name: String) -> AABB:
	return _load_mesh(model_name).get_aabb()


## For anything the player should be blocked by (buildings, fences) -
## trimesh rather than a box, so a building's own modelled door opening
## actually lets the player through it instead of the collision being a
## sealed box around the whole silhouette.
func _instance_with_collision(model_name: String) -> Node3D:
	var body := StaticBody3D.new()
	body.name = model_name
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _load_mesh(model_name)
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	collision.shape = mesh_instance.mesh.create_trimesh_shape()
	body.add_child(collision)
	return body


## For decorative ground-level pieces (driveways, paths, trees) nobody
## needs to collide with.
func _instance_no_collision(model_name: String) -> Node3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = model_name
	mesh_instance.mesh = _load_mesh(model_name)
	return mesh_instance


# ------------------------------------------------------------- player/zombie


func _place_player_and_light_test_zombie() -> void:
	# Spawn in the street itself, between the two facing rows, rather than
	# behind one row looking at the other - this is a street scene now, not
	# a single row viewed from in front.
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "Player"
	player.position = Vector3(0.0, 1.0, 0.0)
	player.set("pause_enabled", false)
	level_root.add_child(player)

	var zombie: Node3D = (load("res://scenes/zombies/scary_zombie.tscn") as PackedScene).instantiate()
	zombie.name = "TestZombie"
	zombie.position = Vector3(15.0, 1.0, 0.0)
	level_root.add_child(zombie)
