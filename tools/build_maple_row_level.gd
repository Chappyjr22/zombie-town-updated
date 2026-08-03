extends SceneTree
## Generates scenes/levels/maple_row.tscn: the new "Maple Row" map - a plaza at
## the center of a plus-shaped street grid, with a residential rowhouse
## corridor down each of the four arms leading out to one anchor building
## per arm (corner store / school / garage / apartments). Design writeup and
## the reasoning behind the loop-not-dead-end layout lives in the session
## that planned it - this script is the physical layout only.
##
##   godot --headless --path . --script tools/build_maple_row_level.gd
##
## What this pass builds: ground, nav mesh, the plaza with its fountain, all
## four arms (road + rowhouse frontage, cosmetic sidewalks), the four anchor
## buildings (stacked from their ground/upper-floor modules where more than
## one exists), player start, and RoundDirector spawn markers around the
## perimeter.
##
## What this pass deliberately leaves out, as a follow-up: buyable doors
## gating the arms/plaza, wall-buy/perk/Pack-a-Punch/Mystery Box placement,
## and the back-alley perimeter loop behind the rowhouses. Same incremental
## split build_town_level.gd itself went through - the physical shell first,
## economy wired in afterward once the layout is confirmed to actually play.
##
## Every asset here is an unverified-in-editor Meshy AI generation (measured
## and rendered, never trusted from Meshy's own preview - see
## ASSET_MANIFEST.md's "Environment - Maple Row" section for the full
## per-asset measurement history). Door-facing axis on each building/rowhouse
## is an assumption (local -Z, matching the front-facade renders used to
## locate and cut each opening) - not yet confirmed by looking at this scene
## in the actual editor.

const SCENE_PATH := "res://scenes/levels/maple_row.tscn"
const ASSET_DIR := "res://assets/models/props/maple_row"

# ---------- layout constants ----------
const PLAZA_HALF := 10.0 ## plaza is a 20m x 20m square centered on the origin
const ARM_LENGTH := 40.0 ## plaza edge to the anchor building, per arm
const ARM_HALF_WIDTH := 5.0 ## 10m-wide arms, matching the street prompts
const ARM_OUTER := PLAZA_HALF + ARM_LENGTH ## 50.0 - distance from center to an arm's far end
const GROUND_HALF := ARM_OUTER + 25.0 ## margin beyond the arms for the buildings' own footprints

# ---------- measured asset footprints (W=X, H=Y, D=Z) ----------
# Source: tools/inspect_external_model.gd measurements, logged in
# ASSET_MANIFEST.md. Height is the one dimension Meshy's export dialog
# locks reliably - width/depth are each generation's own real size, accepted
# as measured rather than assumed from the original prompt text.
const ROWHOUSE_UNIT_SIZE := Vector3(7.55, 6.0, 3.25)
const ROWHOUSE_DAMAGED_SIZE := Vector3(6.87, 6.0, 2.84)
const CORNER_STORE_SIZE := Vector3(6.86, 4.0, 3.65)
const SCHOOL_GROUND_SIZE := Vector3(10.81, 4.5, 5.59)
const SCHOOL_UPPER_RAW_SIZE := Vector3(10.27, 4.5, 4.83) ## before the match-footprint scale below
const GARAGE_SIZE := Vector3(8.34, 5.0, 3.97)
const APARTMENT_GROUND_SIZE := Vector3(4.71, 3.0, 3.01)
const APARTMENT_UPPER_RAW_SIZE := Vector3(4.49, 3.0, 2.8) ## before the match-footprint scale below
const FOUNTAIN_RADIUS := 3.02
const FOUNTAIN_HEIGHT := 2.0

# school/apartment upper floors came back a slightly different footprint than
# their ground floor - scaled to match exactly before stacking, per the plan
# worked out with the user rather than re-generating again.
var school_upper_scale: Vector3 = Vector3(
	SCHOOL_GROUND_SIZE.x / SCHOOL_UPPER_RAW_SIZE.x, 1.0, SCHOOL_GROUND_SIZE.z / SCHOOL_UPPER_RAW_SIZE.z
)
var apartment_upper_scale: Vector3 = Vector3(
	APARTMENT_GROUND_SIZE.x / APARTMENT_UPPER_RAW_SIZE.x, 1.0, APARTMENT_GROUND_SIZE.z / APARTMENT_UPPER_RAW_SIZE.z
)

var level_root: Node3D
var geometry_root: Node3D ## NavigationRegion3D - see _build_ground()
var scene_cache: Dictionary = {}


func _initialize() -> void:
	_generate()


func _generate() -> void:
	if ResourceLoader.exists(SCENE_PATH):
		push_warning("%s already exists - not overwriting. Delete it first to regenerate." % SCENE_PATH)
		quit()
		return

	level_root = Node3D.new()
	level_root.name = "MapleRow"

	_build_environment()
	_build_ground()
	_build_plaza()
	_build_arm(true, -1.0) ## west arm: tiling along X, anchor at -X
	_build_arm(true, 1.0) ## east arm: tiling along X, anchor at +X
	_build_arm(false, -1.0) ## north arm: tiling along Z, anchor at -Z
	_build_arm(false, 1.0) ## south arm: tiling along Z, anchor at +Z
	_place_player_and_spawns()

	_claim_ownership(level_root, level_root)

	root.add_child(level_root)
	await process_frame
	await process_frame
	var source_geometry := NavigationMeshSourceGeometryData3D.new()
	NavigationMeshGenerator.parse_source_geometry_data(geometry_root.navigation_mesh, source_geometry, geometry_root)
	NavigationMeshGenerator.bake_from_source_geometry_data(geometry_root.navigation_mesh, source_geometry)
	print("Baked nav mesh: %d vertices, %d polygons" % [geometry_root.navigation_mesh.get_vertices().size(), geometry_root.navigation_mesh.get_polygon_count()])

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


# ---------- environment / ground ----------
# Same night/fog mood as town.tscn - same outbreak, different neighborhood.

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.transform = Transform3D(Basis().rotated(Vector3.RIGHT, deg_to_rad(-55)), Vector3(-40, 60, -25))
	sun.light_color = Color(0.58, 0.67, 0.87)
	sun.light_energy = 0.4
	sun.shadow_enabled = true
	level_root.add_child(sun)

	var moon := OmniLight3D.new()
	moon.name = "Hemisphere"
	moon.position = Vector3(0, 30, 0)
	moon.light_color = Color(0.18, 0.23, 0.39)
	moon.light_energy = 0.18
	moon.omni_range = 120.0
	moon.shadow_enabled = false
	level_root.add_child(moon)

	var env_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.039, 0.047, 0.078)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.07, 0.08, 0.12)
	environment.ambient_light_energy = 0.5
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.04, 0.047, 0.078)
	environment.fog_density = 0.015
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.15
	environment.glow_hdr_threshold = 1.0
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = environment
	level_root.add_child(env_node)


func _build_ground() -> void:
	var nav_region := NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	nav_region.navigation_mesh = NavigationMesh.new()
	nav_region.navigation_mesh.cell_size = 0.25
	nav_region.navigation_mesh.cell_height = 0.25
	nav_region.navigation_mesh.agent_height = 1.8
	nav_region.navigation_mesh.agent_radius = 0.4
	nav_region.navigation_mesh.agent_max_climb = 0.3
	nav_region.navigation_mesh.agent_max_slope = 46.0
	nav_region.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	level_root.add_child(nav_region)
	geometry_root = nav_region

	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.1, 0.1, 0.11)
	ground_mat.roughness = 0.95
	_box(geometry_root, "Ground", Vector3(GROUND_HALF * 2, 1, GROUND_HALF * 2), Vector3(0, -0.5, 0), ground_mat, true)


# ---------- shared primitive/instancing helpers ----------

func _box(parent: Node3D, name: String, size: Vector3, pos: Vector3, mat: Material, collide: bool) -> void:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = name
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.set_surface_override_material(0, mat)

	if not collide:
		mesh_inst.position = pos
		parent.add_child(mesh_inst)
		return

	var body := StaticBody3D.new()
	body.name = name
	parent.add_child(body)
	body.position = pos
	body.add_child(mesh_inst)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)


func _load_scene(glb_name: String) -> PackedScene:
	if scene_cache.has(glb_name):
		return scene_cache[glb_name]
	var packed: PackedScene = load(ASSET_DIR.path_join(glb_name + ".glb"))
	scene_cache[glb_name] = packed
	return packed


## Instances a Meshy building/rowhouse GLB with a matching box collider (its
## origin is Bottom, per the Meshy export convention used throughout this
## set, so the box sits centered above the node at size.y/2).
func _place_prop(parent: Node3D, glb_name: String, size: Vector3, pos: Vector3, yaw: float, model_scale: Vector3 = Vector3.ONE) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = glb_name.capitalize().replace(" ", "")
	parent.add_child(body)
	body.position = pos
	body.rotation.y = yaw

	var model := _load_scene(glb_name).instantiate()
	model.scale = model_scale
	body.add_child(model)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position.y = size.y / 2.0
	body.add_child(shape)
	return body


## Road/sidewalk dressing is cosmetic only - the flat Ground box already
## carries collision/nav for the whole map, and giving these their own
## slightly-different-height colliders risks stair-stepping the nav bake at
## every seam. Sits a couple centimeters above Ground's top face to avoid
## z-fighting.
func _place_ground_decal(parent: Node3D, glb_name: String, pos: Vector3, yaw: float, model_scale: Vector3) -> void:
	var model := _load_scene(glb_name).instantiate()
	model.position = pos + Vector3(0, 0.02, 0)
	model.rotation.y = yaw
	model.scale = model_scale
	parent.add_child(model)


# ---------- plaza ----------

func _build_plaza() -> void:
	var g := Node3D.new()
	g.name = "Plaza"
	geometry_root.add_child(g)

	var paving_mat := StandardMaterial3D.new()
	paving_mat.albedo_color = Color(0.16, 0.15, 0.15)
	paving_mat.roughness = 0.9
	_box(g, "PlazaPaving", Vector3(PLAZA_HALF * 2, 0.06, PLAZA_HALF * 2), Vector3(0, 0.03, 0), paving_mat, false)

	var body := StaticBody3D.new()
	body.name = "Fountain"
	g.add_child(body)
	var model := _load_scene("fountain").instantiate()
	body.add_child(model)
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = FOUNTAIN_RADIUS
	cyl.height = FOUNTAIN_HEIGHT
	shape.shape = cyl
	shape.position.y = FOUNTAIN_HEIGHT / 2.0
	body.add_child(shape)


# ---------- arms ----------

## along_x: true for the west/east arms (tiling along X, anchor building sits
## off to one side on X), false for the north/south arms (tiling along Z).
## dir: -1.0 or 1.0 - which end of that axis this arm extends toward.
func _build_arm(along_x: bool, dir: float) -> void:
	var arm_name := ("EastArm" if dir > 0 else "WestArm") if along_x else ("SouthArm" if dir > 0 else "NorthArm")
	var g := Node3D.new()
	g.name = arm_name
	geometry_root.add_child(g)

	var road_mat_scale_len := 5.0 ## road/sidewalk tile "length" along the arm, before scaling to fit
	var road_width := 6.0
	var sidewalk_width := 2.0

	var tiling_start := PLAZA_HALF
	var tiling_end := ARM_OUTER
	var span := tiling_end - tiling_start

	# Road + two sidewalk strips, tiled in 5m segments down the arm.
	var segments := int(ceil(span / road_mat_scale_len))
	var seg_len := span / float(segments)
	for i in range(segments):
		var center_tiling := tiling_start + seg_len * (i + 0.5)
		_place_ground_decal(g, "road_segment",
			_axis_vec(along_x, dir, center_tiling, 0.0),
			_facing_yaw(along_x, 0.0), Vector3(seg_len / 2.33, 1.0, road_width / 2.33))
		for side: float in [-1.0, 1.0]:
			var perp: float = side * (road_width / 2.0 + sidewalk_width / 2.0)
			_place_ground_decal(g, "sidewalk_segment",
				_axis_vec(along_x, dir, center_tiling, perp),
				_facing_yaw(along_x, 0.0), Vector3(seg_len / 1.61, 1.0, sidewalk_width / 1.04))

	# Rowhouse frontage, both sides of the arm.
	for side in [-1.0, 1.0]:
		_place_rowhouse_row(g, along_x, dir, tiling_start, tiling_end, side)

	# Anchor building at the arm's far end, front door facing back toward the plaza.
	_place_anchor_building(g, along_x, dir)


## Maps a (tiling-position, perpendicular-offset) pair onto world (X,Z),
## depending on which axis this arm tiles along and which direction it faces.
func _axis_vec(along_x: bool, dir: float, tiling: float, perp: float) -> Vector3:
	if along_x:
		return Vector3(dir * tiling, 0, perp)
	return Vector3(perp, 0, dir * tiling)


## The yaw that makes a prop's local -Z (its established "front", per the
## front-facade renders used to find/cut every door and window in this set)
## point along +perp_sign in the arm's perpendicular axis.
func _yaw_facing_perp(along_x: bool, perp_sign: float) -> float:
	if along_x:
		return PI if perp_sign < 0.0 else 0.0
	return -PI / 2.0 if perp_sign < 0.0 else PI / 2.0


## The yaw that makes a prop's local -Z point back toward the plaza (i.e.
## toward smaller |tiling| - used for the anchor buildings and, doubled with
## the appropriate sign, for the road/sidewalk decals' rotation so their own
## long axis lines up with the arm rather than across it).
func _facing_yaw(along_x: bool, unused: float) -> float:
	return PI / 2.0 if along_x else 0.0


func _place_rowhouse_row(parent: Node3D, along_x: bool, dir: float, tiling_start: float, tiling_end: float, side: float) -> void:
	var pos := tiling_start
	var i := 0
	var yaw := _yaw_facing_perp(along_x, side)
	while pos < tiling_end:
		var damaged := (i % 4 == 3)
		var size := ROWHOUSE_DAMAGED_SIZE if damaged else ROWHOUSE_UNIT_SIZE
		if pos + size.x > tiling_end:
			break
		var center_tiling := pos + size.x / 2.0
		var perp := side * (ARM_HALF_WIDTH + size.z / 2.0)
		_place_prop(parent, "rowhouse_damaged" if damaged else "rowhouse_unit", size,
			_axis_vec(along_x, dir, center_tiling, perp), yaw)
		pos += size.x
		i += 1


func _place_anchor_building(parent: Node3D, along_x: bool, dir: float) -> void:
	# Front door (local -Z) faces back toward the plaza, i.e. toward smaller
	# |tiling| - the opposite of the direction this arm extends outward, so
	# the yaw is the perpendicular-facing helper with the arm's own axis
	# treated as the "perpendicular" one time round.
	var door_yaw: float
	if along_x:
		door_yaw = -PI / 2.0 if dir > 0.0 else PI / 2.0
	else:
		door_yaw = PI if dir < 0.0 else 0.0

	if along_x and dir > 0.0:
		_place_school(parent, along_x, dir, door_yaw)
	elif along_x and dir < 0.0:
		_place_corner_store(parent, along_x, dir, door_yaw)
	elif not along_x and dir < 0.0:
		_place_apartments(parent, along_x, dir, door_yaw)
	else:
		_place_garage(parent, along_x, dir, door_yaw)


func _place_corner_store(parent: Node3D, along_x: bool, dir: float, yaw: float) -> void:
	var pos := _axis_vec(along_x, dir, ARM_OUTER + CORNER_STORE_SIZE.z / 2.0, 0.0)
	_place_prop(parent, "corner_store", CORNER_STORE_SIZE, pos, yaw)


func _place_school(parent: Node3D, along_x: bool, dir: float, yaw: float) -> void:
	var base := _axis_vec(along_x, dir, ARM_OUTER + SCHOOL_GROUND_SIZE.z / 2.0, 0.0)
	_place_prop(parent, "school_ground", SCHOOL_GROUND_SIZE, base, yaw)
	var upper_pos := base + Vector3(0, SCHOOL_GROUND_SIZE.y, 0)
	_place_prop(parent, "school_upper", SCHOOL_GROUND_SIZE, upper_pos, yaw, school_upper_scale)


func _place_garage(parent: Node3D, along_x: bool, dir: float, yaw: float) -> void:
	var pos := _axis_vec(along_x, dir, ARM_OUTER + GARAGE_SIZE.z / 2.0, 0.0)
	_place_prop(parent, "garage", GARAGE_SIZE, pos, yaw)


## Tallest building on the map, matching the plan's Pack-a-Punch payoff -
## ground floor plus three stacked upper modules, capped with a flat roof.
func _place_apartments(parent: Node3D, along_x: bool, dir: float, yaw: float) -> void:
	var base := _axis_vec(along_x, dir, ARM_OUTER + APARTMENT_GROUND_SIZE.z / 2.0, 0.0)
	_place_prop(parent, "apartment_ground", APARTMENT_GROUND_SIZE, base, yaw)
	var floor_y := APARTMENT_GROUND_SIZE.y
	for i in range(3):
		var upper_pos := base + Vector3(0, floor_y, 0)
		_place_prop(parent, "apartment_upper", APARTMENT_GROUND_SIZE, upper_pos, yaw, apartment_upper_scale)
		floor_y += APARTMENT_GROUND_SIZE.y

	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.08, 0.08, 0.09)
	roof_mat.roughness = 0.9
	_box(parent, "ApartmentRoof", Vector3(APARTMENT_GROUND_SIZE.x + 0.4, 0.3, APARTMENT_GROUND_SIZE.z + 0.4),
		base + Vector3(0, floor_y + 0.15, 0), roof_mat, true)


# ---------- player start + zombie spawns ----------

func _place_player_and_spawns() -> void:
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "Player"
	# Inside the corner store (west arm), facing out toward the plaza.
	player.position = Vector3(-(ARM_OUTER - 1.0), 0, 0)
	player.rotation.y = PI / 2.0
	level_root.add_child(player)

	var director := Node3D.new()
	director.name = "RoundDirector"
	director.set_script(load("res://scripts/ai/round_director.gd"))
	level_root.add_child(director)
	var zombie_scenes: Array[PackedScene] = [
		load("res://scenes/zombies/scary_zombie.tscn"),
		load("res://scenes/zombies/cop_zombie.tscn"),
	]
	director.zombie_scenes = zombie_scenes

	# Spread around the perimeter - both far ends of all four arms, plus the
	# four corners between arms - so RoundDirector's furthest-of-7-samples
	# pick (scripts/ai/CLAUDE.md) always has options spread away from the
	# player regardless of which arm they're in.
	var spawns := [
		Vector3(-ARM_OUTER + 3, 0, 0), Vector3(ARM_OUTER - 3, 0, 0),
		Vector3(0, 0, -ARM_OUTER + 3), Vector3(0, 0, ARM_OUTER - 3),
		Vector3(-ARM_OUTER + 3, 0, -ARM_OUTER + 3), Vector3(ARM_OUTER - 3, 0, -ARM_OUTER + 3),
		Vector3(-ARM_OUTER + 3, 0, ARM_OUTER - 3), Vector3(ARM_OUTER - 3, 0, ARM_OUTER - 3),
		Vector3(-PLAZA_HALF - 5, 0, -PLAZA_HALF - 5), Vector3(PLAZA_HALF + 5, 0, -PLAZA_HALF - 5),
		Vector3(-PLAZA_HALF - 5, 0, PLAZA_HALF + 5), Vector3(PLAZA_HALF + 5, 0, PLAZA_HALF + 5),
	]
	for i in range(spawns.size()):
		var m := Marker3D.new()
		m.name = "Spawn%d" % (i + 1)
		m.position = spawns[i]
		director.add_child(m)
