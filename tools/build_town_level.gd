extends SceneTree
## Generates scenes/levels/town.tscn: a port of "Town" from the earlier three.js
## prototype (chappyjr22/zombie-town-online, public/index.html:1339-2336,
## buildTown()), rebuilt as real Godot geometry instead of runtime-procedural JS.
##
##   godot --headless --path . --script tools/build_town_level.gd
##
## Coordinates, footprints, and collision extents are ported 1:1 from the JS
## source (same 1-unit-per-meter scale, same BND=42 perimeter) so the layout
## plays the same. Two things are deliberately simplified rather than ported
## part-for-part, both noted inline where they happen: the wrecked bus (JS
## hand-tuned ~90 lines of individual glass panes/mirrors) becomes a blockout
## shell at the same footprint, and street clutter (dumpster/bench/crate/etc.)
## becomes 1-3 primitive parts instead of JS's 10-20, since Poly Haven has no
## matching CC0 models for these and hand-modeling that much per-rivet detail
## isn't worth it for background props. Buildings keep close to full fidelity
## since they're what the player actually navigates and takes cover behind.
##
## Buy stations / perk machines / Pack-a-Punch are ported as labeled, inert
## Marker3D placeholders only - no such systems exist in scripts/ yet
## (confirmed absent; see scripts/ai/CLAUDE.md and scripts/ui/CLAUDE.md).
##
## Existing scene is never overwritten, so re-running this can't undo tuning.

const SCENE_PATH := "res://scenes/levels/town.tscn"
const TEX_DIR := "res://assets/textures/town"
const VEHICLE_DIR := "res://assets/models/vehicles"

const BND := 42.0

var level_root: Node3D
var geometry_root: Node3D ## NavigationRegion3D - all static geometry nests under this so its own bake sees it.
var mat_cache: Dictionary = {}
var vehicle_cache: Dictionary = {}
var vehicle_names := ["Cop", "SUV", "NormalCar1", "Taxi", "SportsCar"]
var vehicle_index := 0


func _initialize() -> void:
	_generate()


## GDScript allows await in any function - _initialize() runs this as a
## coroutine, which is what baking needs (see the comment above the bake call).
func _generate() -> void:
	if ResourceLoader.exists(SCENE_PATH):
		push_warning("%s already exists - not overwriting. Delete it first to regenerate." % SCENE_PATH)
		quit()
		return

	level_root = Node3D.new()
	level_root.name = "Town"

	_build_environment()
	_build_ground()
	_build_bar()
	_build_bank()
	_build_church()
	_build_diner()
	_build_store()
	_build_fountain()
	_build_bus()
	_place_cars()
	_place_clutter()
	_place_fence()
	_place_ash()
	_place_economy()
	_place_player_and_spawns()

	# pack() only serializes nodes whose owner chain reaches level_root - nodes
	# added via add_child() alone are dropped as scene-external helpers.
	_claim_ownership(level_root, level_root)

	# Baking needs the geometry's collision shapes registered with the physics
	# server, which only happens once the nodes are actually inside a live
	# SceneTree and a couple of process frames have run.
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


## Recursively claims every child so pack() serializes them. Stops descending
## into an instanced sub-scene's own children (Player, vehicle models) so
## those stay clean "instance=" references instead of being flattened.
func _claim_ownership(owner_root: Node, node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_root
		if child.scene_file_path == "":
			_claim_ownership(owner_root, child)


# ---------- materials ----------

func _material(slug: String) -> StandardMaterial3D:
	if mat_cache.has(slug):
		return mat_cache[slug]
	var mat := StandardMaterial3D.new()
	var base := TEX_DIR.path_join(slug).path_join(slug)
	var diff := load(base + "_diff_1k.jpg")
	var nor := load(base + "_nor_gl_1k.jpg")
	var rough := load(base + "_rough_1k.jpg")
	if diff:
		mat.albedo_texture = diff
	if nor:
		mat.normal_enabled = true
		mat.normal_texture = nor
	if rough:
		mat.roughness_texture = rough
	mat.uv1_triplanar = false
	mat_cache[slug] = mat
	return mat


func _tiled_material(slug: String, tiles_x: float, tiles_y: float) -> StandardMaterial3D:
	# Poly Haven textures are ~1m-scale photographs; walls/floors are bigger
	# than that, so repeat the UVs instead of stretching one tile across them.
	var key := "%s@%s,%s" % [slug, tiles_x, tiles_y]
	if mat_cache.has(key):
		return mat_cache[key]
	var base := _material(slug)
	var mat: StandardMaterial3D = base.duplicate()
	mat.uv1_scale = Vector3(tiles_x, tiles_y, 1)
	mat_cache[key] = mat
	return mat


func _window_material() -> StandardMaterial3D:
	if mat_cache.has("window"):
		return mat_cache["window"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.08, 0.1, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.4
	mat.roughness = 0.15
	mat_cache["window"] = mat
	return mat


# ---------- primitive helpers (bx/cyl/wallRun/roofSlab/floorSlab equivalents) ----------

func _box(parent: Node3D, name: String, size: Vector3, pos: Vector3, mat: Material, collide: bool = true) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mesh := MeshInstance3D.new()
	mesh.name = name
	mesh.mesh = box
	mesh.set_surface_override_material(0, mat)

	if not collide:
		mesh.position = pos
		parent.add_child(mesh)
		return mesh

	var body := StaticBody3D.new()
	body.name = name
	parent.add_child(body)
	body.position = pos
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	return mesh


func _cyl(parent: Node3D, name: String, top_r: float, bottom_r: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var body := StaticBody3D.new()
	body.name = name
	parent.add_child(body)
	body.position = pos

	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bottom_r
	cyl.height = height
	mesh.mesh = cyl
	mesh.set_surface_override_material(0, mat)
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var cyl_shape := CylinderShape3D.new()
	cyl_shape.radius = max(top_r, bottom_r)
	cyl_shape.height = height
	shape.shape = cyl_shape
	body.add_child(shape)
	return mesh


## A single wall segment, axis-aligned between (ax,az) and (bx,bz).
func _wall_seg(parent: Node3D, ax: float, az: float, bx: float, bz: float, h: float, mat: Material, y0: float = 0.0) -> void:
	var horiz := absf(bx - ax) > absf(bz - az)
	var w: float = absf(bx - ax) if horiz else 0.34
	var d: float = 0.34 if horiz else absf(bz - az)
	if w < 0.02 or d < 0.02:
		return
	var cx := (ax + bx) / 2.0
	var cz := (az + bz) / 2.0
	_box(parent, "Wall", Vector3(w, h, d), Vector3(cx, y0 + h / 2.0, cz), mat)


## Wall run with door/window gaps. Each gap: {c, w, sill (optional), head (optional, default 2.3)}.
func _wall_run(parent: Node3D, ax: float, az: float, bx: float, bz: float, h: float, mat: Material, gaps: Array = [], y0: float = 0.0) -> void:
	var horiz := absf(bx - ax) > absf(bz - az)
	var s: float = ax if horiz else az
	var e: float = bx if horiz else bz
	var list := gaps.duplicate()
	list.sort_custom(func(p, q): return p.c < q.c)
	var cur := s
	for g in list:
		var a: float = g.c - g.w / 2.0
		var b: float = g.c + g.w / 2.0
		if a > cur:
			if horiz:
				_wall_seg(parent, cur, az, a, bz, h, mat, y0)
			else:
				_wall_seg(parent, ax, cur, bx, a, h, mat, y0)
		var head: float = g.get("head", 2.3)
		if h > head:
			if horiz:
				_wall_seg(parent, a, az, b, bz, h - head, mat, y0 + head)
			else:
				_wall_seg(parent, ax, a, bx, b, h - head, mat, y0 + head)
		if g.has("sill") and g.sill > 0.0:
			var sill: float = g.sill
			if horiz:
				_wall_seg(parent, a, az, b, bz, sill, mat, y0)
			else:
				_wall_seg(parent, ax, a, bx, b, sill, mat, y0)
			# A gap with a sill is a window, not a door - block the opening
			# above the sill so it can't just be climbed through instead of
			# paying for the building's one real door (see scripts/economy).
			var window_h: float = head - sill
			if window_h > 0.05:
				if horiz:
					_box(parent, "Window", Vector3(b - a, window_h, 0.1), Vector3(g.c, y0 + sill + window_h / 2.0, az), _window_material())
				else:
					_box(parent, "Window", Vector3(0.1, window_h, b - a), Vector3(ax, y0 + sill + window_h / 2.0, g.c), _window_material())
		cur = b
	if cur < e:
		if horiz:
			_wall_seg(parent, cur, az, e, bz, h, mat, y0)
		else:
			_wall_seg(parent, ax, cur, bx, e, h, mat, y0)


func _roof_slab(parent: Node3D, x1: float, z1: float, x2: float, z2: float, h: float, mat: Material) -> void:
	_box(parent, "Roof", Vector3(x2 - x1 + 0.9, 0.42, z2 - z1 + 0.9), Vector3((x1 + x2) / 2.0, h + 0.21, (z1 + z2) / 2.0), mat)
	_box(parent, "RoofCap", Vector3(x2 - x1 + 1.1, 0.5, z2 - z1 + 1.1), Vector3((x1 + x2) / 2.0, h + 0.62, (z1 + z2) / 2.0), mat)


func _floor_slab(parent: Node3D, x1: float, z1: float, x2: float, z2: float, y: float, mat: Material) -> void:
	_box(parent, "Floor", Vector3(x2 - x1, 0.18, z2 - z1), Vector3((x1 + x2) / 2.0, y - 0.09, (z1 + z2) / 2.0), mat)


func _room_light(parent: Node3D, pos: Vector3, color: Color, energy: float, light_range: float) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.shadow_enabled = false # interior dressing lights - see perf notes in the plan
	parent.add_child(l)


## Straight staircase: the visible step boxes are dressing only (no collision -
## a dozen stacked 0.16m colliders is not something move_and_slide climbs
## cleanly); a single sloped box is the actual walkable surface, same split
## the JS source used (addRamp for movement vs. separate boxes just "to see").
func _staircase(parent: Node3D, x1: float, x2: float, z1: float, z2: float, y0: float, y1: float, mat: Material, flip: bool = false) -> void:
	var steps := 14
	for i in range(steps):
		var za: float = lerp(z1, z2, float(i) / steps)
		var zb: float = lerp(z1, z2, float(i + 1) / steps)
		var zz := (za + zb) / 2.0
		var yy: float = lerp(y0, y1, float(i + 1) / steps)
		_box(parent, "Step%d" % i, Vector3(x2 - x1, 0.16, zb - za + 0.05), Vector3((x1 + x2) / 2.0, yy - 0.08, zz), mat, false)
	var ramp_body := StaticBody3D.new()
	ramp_body.name = "StairRamp"
	parent.add_child(ramp_body)
	var span := z2 - z1
	var rise := y1 - y0
	ramp_body.position = Vector3((x1 + x2) / 2.0, (y0 + y1) / 2.0, (z1 + z2) / 2.0)
	# Rotating around +X tilts the local +Z end DOWNWARD (right-hand rule), so
	# climbing in +Z (the un-flipped case) needs a NEGATIVE angle to put the
	# high end (y1) at the far end (z2) instead of the near one.
	ramp_body.rotation.x = -atan2(rise, span) * (1.0 if not flip else -1.0)
	var ramp_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(x2 - x1, 0.2, sqrt(span * span + rise * rise))
	ramp_shape.shape = box_shape
	ramp_body.add_child(ramp_shape)


## Fills a wall_run gap with a purchasable door instead of leaving it open -
## previously every gap without a sill was freely walkable, which is exactly
## what scripts/economy/CLAUDE.md's level-integration note means by "a paid
## door only means something if there's no free way around it." (ax,az,bx,bz)
## is the same wall-line convention _wall_run itself takes; gap_c/gap_w locate
## this specific opening within it.
func _place_door(parent: Node3D, ax: float, az: float, bx: float, bz: float, gap_c: float, gap_w: float, h: float, y0: float, mat: Material, price: int) -> void:
	var horiz := absf(bx - ax) > absf(bz - az)
	var door_pos: Vector3
	var door_size: Vector3
	if horiz:
		door_pos = Vector3(gap_c, y0 + h / 2.0, az)
		door_size = Vector3(gap_w, h, 0.3)
	else:
		door_pos = Vector3(ax, y0 + h / 2.0, gap_c)
		door_size = Vector3(0.3, h, gap_w)
	var door_body := _box(parent, "Door", door_size, door_pos, mat).get_parent() as StaticBody3D

	var door := BuyableDoor.new()
	door.name = "BuyableDoor"
	door.price = price
	door.door_body = door_body
	parent.add_child(door)
	door.position = door_pos
	var range_shape := CollisionShape3D.new()
	var range_box := BoxShape3D.new()
	range_box.size = door_size + Vector3(1.8, 0.6, 1.8)
	range_shape.shape = range_box
	door.add_child(range_shape)


func _place_wall_buy(parent: Node3D, pos: Vector3, rot_y: float, weapon_path: String, price: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.12, 0.11)
	var station := WallBuyStation.new()
	station.name = "WallBuyStation"
	station.weapon = load(weapon_path)
	station.full_cost = price
	parent.add_child(station)
	station.position = pos
	station.rotation.y = rot_y
	_box(station, "Backing", Vector3(1.4, 1.0, 0.1), Vector3(0, 0, 0), mat, false)
	var range_shape := CollisionShape3D.new()
	var range_box := BoxShape3D.new()
	range_box.size = Vector3(2.6, 2.4, 2.6)
	range_shape.shape = range_box
	station.add_child(range_shape)
	_sign(station, station.weapon.display_name, Vector3(0, 0.7, -0.06), 0.0)


func _place_ammo_buy(parent: Node3D, pos: Vector3, rot_y: float, weapon_path: String, price: int) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.11, 0.1, 0.09)
	var station := AmmoBuyStation.new()
	station.name = "AmmoBuyStation"
	station.weapon = load(weapon_path)
	station.price = price
	parent.add_child(station)
	station.position = pos
	station.rotation.y = rot_y
	_box(station, "Backing", Vector3(0.9, 0.6, 0.08), Vector3(0, 0, 0), mat, false)
	var range_shape := CollisionShape3D.new()
	var range_box := BoxShape3D.new()
	range_box.size = Vector3(2.2, 2.2, 2.2)
	range_shape.shape = range_box
	station.add_child(range_shape)


## Simple vending-machine silhouette: body, glowing face/top, a bottle prop -
## same technique as every other prop in this file, kept intentionally plain
## (visual detailing is being handled separately, outside this session - see
## the ChatGPT/art-vs-gameplay split in the commit history around this point).
func _place_perk_machine(parent: Node3D, pos: Vector3, rot_y: float, key: StringName, perk_name: String, color: Color, price: int) -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.14, 0.15, 0.16)
	shell.metallic = 0.4
	shell.roughness = 0.5
	var glow := StandardMaterial3D.new()
	glow.albedo_color = color
	glow.emission_enabled = true
	glow.emission = color
	glow.emission_energy_multiplier = 1.4

	var machine := PerkMachine.new()
	machine.name = "PerkMachine_" + String(key)
	machine.perk_key = key
	machine.perk_name = perk_name
	machine.price = price
	parent.add_child(machine)
	machine.position = pos
	machine.rotation.y = rot_y

	_box(machine, "Body", Vector3(1.3, 2.1, 0.9), Vector3(0, 1.05, 0), shell)
	_box(machine, "Face", Vector3(1.05, 1.5, 0.1), Vector3(0, 1.35, -0.48), glow, false)
	_box(machine, "Top", Vector3(1.4, 0.22, 1.0), Vector3(0, 2.28, 0), glow, false)
	_cyl(machine, "Bottle", 0.12, 0.15, 0.55, Vector3(-0.21, 1.38, -0.57), glow)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.6, -1.0)
	light.light_color = color
	light.light_energy = 1.0
	light.omni_range = 9.0
	light.shadow_enabled = false
	machine.add_child(light)
	_sign(machine, perk_name, Vector3(0, 2.6, 0), 0.0)

	var range_shape := CollisionShape3D.new()
	var range_box := BoxShape3D.new()
	range_box.size = Vector3(2.6, 2.6, 2.6)
	range_shape.shape = range_box
	machine.add_child(range_shape)


func _place_pack_a_punch(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.09, 0.1, 0.14)
	shell.metallic = 0.5
	shell.roughness = 0.35
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.55, 0.25, 0.85)
	glow.emission_enabled = true
	glow.emission = Color(0.55, 0.25, 0.85)
	glow.emission_energy_multiplier = 2.0

	var machine := PackAPunchMachine.new()
	machine.name = "PackAPunch"
	parent.add_child(machine)
	machine.position = pos
	machine.rotation.y = rot_y

	_box(machine, "Body", Vector3(1.9, 1.9, 1.2), Vector3(0, 1.3, 0), shell)
	_box(machine, "Hood", Vector3(2.2, 0.3, 1.5), Vector3(0, 2.4, 0), shell, false)
	_box(machine, "Panel", Vector3(1.3, 0.95, 0.06), Vector3(0, 1.55, -0.63), glow, false)
	for sx in [-0.79, 0.79]:
		_cyl(machine, "Coil", 0.17, 0.19, 0.94, Vector3(sx, 2.99, 0.08), shell)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.4, 0)
	light.light_color = Color(0.55, 0.25, 0.85)
	light.light_energy = 1.4
	light.omni_range = 10.0
	light.shadow_enabled = false
	machine.add_child(light)
	_sign(machine, "Pack-a-Punch", Vector3(0, 3.0, 0), 0.0)

	var range_shape := CollisionShape3D.new()
	var range_box := BoxShape3D.new()
	range_box.size = Vector3(3.0, 3.0, 3.0)
	range_shape.shape = range_box
	machine.add_child(range_shape)


## A simple chest - four wonder weapons the player can't wall-buy, ported from
## zombie-town-online's own weapon table (see scripts/weapons/CLAUDE.md).
## Placed on the opposite side of the fountain from Pack-a-Punch, at the same
## 7.2m distance, clear of its 3.5m radius - not verified against the actual
## street/building layout in-editor, since this session has no way to look at
## the level visually. Check it isn't clipping anything and nudge the
## position if it is.
func _place_mystery_box(parent: Node3D, pos: Vector3, rot_y: float) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.22, 0.14)
	wood.roughness = 0.8
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.16, 0.15, 0.14)
	metal.metallic = 0.6
	metal.roughness = 0.4
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(0.85, 0.66, 0.23)
	glow.emission_enabled = true
	glow.emission = Color(0.85, 0.66, 0.23)
	glow.emission_energy_multiplier = 1.6

	var box := MysteryBox.new()
	box.name = "MysteryBox"
	var weapons := "res://resources/weapons/"
	var wonder_weapons: Array[WeaponData] = [
		load(weapons + "ray_gun.tres"),
		load(weapons + "ray_gun_mk2.tres"),
		load(weapons + "thundergun.tres"),
		load(weapons + "wunderwaffe.tres"),
		load(weapons + "war_machine.tres"),
	]
	box.wonder_weapons = wonder_weapons
	parent.add_child(box)
	box.position = pos
	box.rotation.y = rot_y

	_box(box, "Crate", Vector3(1.3, 1.0, 1.3), Vector3(0, 0.5, 0), wood)
	for corner_x in [-0.6, 0.6]:
		for corner_z in [-0.6, 0.6]:
			_box(box, "Corner", Vector3(0.1, 1.0, 0.1), Vector3(corner_x, 0.5, corner_z), metal, false)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 2.2, 0)
	light.light_color = Color(0.85, 0.66, 0.23)
	light.light_energy = 1.2
	light.omni_range = 8.0
	light.shadow_enabled = false
	box.add_child(light)
	_sign(box, "Mystery Box", Vector3(0, 1.5, 0), 0.0)

	var range_shape := CollisionShape3D.new()
	var range_box := BoxShape3D.new()
	range_box.size = Vector3(2.8, 2.6, 2.8)
	range_shape.shape = range_box
	box.add_child(range_shape)


func _sign(parent: Node3D, text: String, pos: Vector3, rot_y: float) -> void:
	var label := Label3D.new()
	label.text = text.to_upper()
	label.position = pos
	label.rotation.y = rot_y
	label.pixel_size = 0.01
	label.modulate = Color(0.91, 0.79, 0.55)
	label.outline_size = 4
	label.font_size = 48
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = true
	label.no_depth_test = false
	parent.add_child(label)


## Radial gradient texture, cached by name. Used for the flame quad (bright
## center fading to transparent edge, instead of a hard-edged rectangle) and
## the ground scorch decal.
func _radial_texture(cache_key: String, colors: PackedColorArray, offsets: PackedFloat32Array, size: int = 64) -> GradientTexture2D:
	if mat_cache.has(cache_key):
		return mat_cache[cache_key]
	var gradient := Gradient.new()
	gradient.colors = colors
	gradient.offsets = offsets
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = size
	tex.height = size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.02)
	mat_cache[cache_key] = tex
	return tex


## Layered fire: flame + ember + smoke particles (each with turbulence/scale
## curves so they flicker and drift instead of moving uniformly), a flickering
## FireLight, a ground scorch decal, and crackle SFX. Godot's GPUParticles3D
## animates all of this on the GPU every frame on its own - no per-frame
## script needed beyond the light flicker (see scripts/environment/CLAUDE.md).
func _fire_effect(parent: Node3D, pos: Vector3, particle_scale: float = 1.0) -> void:
	var flame_tex := _radial_texture(
		"flame_tex",
		PackedColorArray([Color(1.0, 0.95, 0.6, 1.0), Color(1.0, 0.55, 0.1, 0.85), Color(0.5, 0.05, 0.0, 0.0)]),
		PackedFloat32Array([0.0, 0.45, 1.0])
	)

	var flames := GPUParticles3D.new()
	flames.name = "Fire"
	flames.position = pos
	flames.amount = 24
	flames.lifetime = 0.9
	flames.emitting = true

	var flame_process := ParticleProcessMaterial.new()
	flame_process.direction = Vector3(0, 1, 0)
	flame_process.spread = 18.0
	flame_process.initial_velocity_min = 0.6 * particle_scale
	flame_process.initial_velocity_max = 1.2 * particle_scale
	flame_process.gravity = Vector3(0, 1.4, 0) # drifts up instead of falling
	flame_process.turbulence_enabled = true
	flame_process.turbulence_noise_strength = 0.5 * particle_scale
	flame_process.turbulence_noise_scale = 2.5
	flame_process.turbulence_influence_min = 0.15
	flame_process.turbulence_influence_max = 0.45
	var flame_scale_curve := Curve.new()
	flame_scale_curve.add_point(Vector2(0.0, 0.25))
	flame_scale_curve.add_point(Vector2(0.25, 1.0))
	flame_scale_curve.add_point(Vector2(1.0, 0.0))
	var flame_scale_curve_tex := CurveTexture.new()
	flame_scale_curve_tex.curve = flame_scale_curve
	flame_process.scale_min = 0.3 * particle_scale
	flame_process.scale_max = 0.5 * particle_scale
	flame_process.scale_curve = flame_scale_curve_tex
	var flame_ramp := Gradient.new()
	flame_ramp.colors = PackedColorArray([Color(1.0, 0.92, 0.55, 0.9), Color(1.0, 0.4, 0.06, 0.75), Color(0.45, 0.05, 0.0, 0.0)])
	flame_ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var flame_ramp_tex := GradientTexture1D.new()
	flame_ramp_tex.gradient = flame_ramp
	flame_process.color_ramp = flame_ramp_tex
	flames.process_material = flame_process

	var flame_quad := QuadMesh.new()
	flame_quad.size = Vector2(0.5, 0.5) * particle_scale
	var flame_mat := StandardMaterial3D.new()
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame_mat.vertex_color_use_as_albedo = true
	flame_mat.albedo_texture = flame_tex
	flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.5, 0.1)
	flame_mat.emission_energy_multiplier = 3.0
	flame_quad.surface_set_material(0, flame_mat)
	flames.draw_pass_1 = flame_quad
	parent.add_child(flames)

	# Embers: small bright sparks that fly higher/faster than the flame body.
	var embers := GPUParticles3D.new()
	embers.name = "Embers"
	embers.position = pos
	embers.amount = 10
	embers.lifetime = 1.6
	embers.emitting = true
	var ember_process := ParticleProcessMaterial.new()
	ember_process.direction = Vector3(0, 1, 0)
	ember_process.spread = 25.0
	ember_process.initial_velocity_min = 0.8 * particle_scale
	ember_process.initial_velocity_max = 1.6 * particle_scale
	ember_process.gravity = Vector3(0, 0.3, 0)
	ember_process.turbulence_enabled = true
	ember_process.turbulence_noise_strength = 0.8 * particle_scale
	ember_process.turbulence_noise_scale = 3.5
	ember_process.scale_min = 0.03
	ember_process.scale_max = 0.06
	var ember_ramp := Gradient.new()
	ember_ramp.colors = PackedColorArray([Color(1.0, 0.95, 0.7, 1.0), Color(1.0, 0.4, 0.05, 0.0)])
	var ember_ramp_tex := GradientTexture1D.new()
	ember_ramp_tex.gradient = ember_ramp
	ember_process.color_ramp = ember_ramp_tex
	embers.process_material = ember_process
	var ember_quad := QuadMesh.new()
	ember_quad.size = Vector2(0.05, 0.05)
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_mat.vertex_color_use_as_albedo = true
	ember_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ember_mat.emission_enabled = true
	ember_mat.emission = Color(1.0, 0.6, 0.15)
	ember_mat.emission_energy_multiplier = 4.0
	ember_quad.surface_set_material(0, ember_mat)
	embers.draw_pass_1 = ember_quad
	parent.add_child(embers)

	# Smoke: sparse, slow, drifts higher above the flame than embers do.
	var smoke := GPUParticles3D.new()
	smoke.name = "Smoke"
	smoke.position = pos + Vector3(0, 0.3 * particle_scale, 0)
	smoke.amount = 6
	smoke.lifetime = 3.0
	smoke.emitting = true
	var smoke_process := ParticleProcessMaterial.new()
	smoke_process.direction = Vector3(0, 1, 0)
	smoke_process.spread = 12.0
	smoke_process.initial_velocity_min = 0.3 * particle_scale
	smoke_process.initial_velocity_max = 0.6 * particle_scale
	smoke_process.gravity = Vector3(0, 0.2, 0)
	smoke_process.scale_min = 0.5 * particle_scale
	smoke_process.scale_max = 1.0 * particle_scale
	var smoke_ramp := Gradient.new()
	smoke_ramp.colors = PackedColorArray([Color(0.5, 0.5, 0.5, 0.0), Color(0.35, 0.34, 0.33, 0.16), Color(0.2, 0.19, 0.18, 0.0)])
	smoke_ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var smoke_ramp_tex := GradientTexture1D.new()
	smoke_ramp_tex.gradient = smoke_ramp
	smoke_process.color_ramp = smoke_ramp_tex
	smoke.process_material = smoke_process
	var smoke_quad := QuadMesh.new()
	smoke_quad.size = Vector2(0.8, 0.8) * particle_scale
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_quad.surface_set_material(0, smoke_mat)
	smoke.draw_pass_1 = smoke_quad
	parent.add_child(smoke)

	var fire_light := FireLight.new()
	fire_light.name = "FireLight"
	fire_light.position = pos
	fire_light.light_color = Color(1.0, 0.5, 0.15)
	fire_light.base_energy = 1.3 * particle_scale
	fire_light.omni_range = 9.0 * particle_scale
	fire_light.shadow_enabled = false
	parent.add_child(fire_light)

	var scorch_tex := _radial_texture(
		"scorch_tex",
		PackedColorArray([Color(0.02, 0.02, 0.02, 0.75), Color(0.05, 0.04, 0.03, 0.4), Color(0.06, 0.05, 0.04, 0.0)]),
		PackedFloat32Array([0.0, 0.5, 1.0])
	)
	var scorch := MeshInstance3D.new()
	scorch.name = "Scorch"
	var scorch_quad := QuadMesh.new()
	scorch_quad.size = Vector2(1.8, 1.8) * particle_scale
	scorch.mesh = scorch_quad
	var scorch_mat := StandardMaterial3D.new()
	scorch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	scorch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	scorch_mat.albedo_texture = scorch_tex
	scorch.set_surface_override_material(0, scorch_mat)
	scorch.position = Vector3(pos.x, 0.02, pos.z)
	scorch.rotation.x = -PI / 2.0
	parent.add_child(scorch)

	var crackle := AudioStreamPlayer3D.new()
	crackle.name = "FireCrackle"
	crackle.stream = load("res://assets/audio/environment/fire-crackle.ogg")
	crackle.position = pos
	crackle.unit_size = 6.0
	crackle.max_distance = 20.0
	crackle.autoplay = true
	parent.add_child(crackle)


func _marker(parent: Node3D, name: String, pos: Vector3) -> Marker3D:
	var m := Marker3D.new()
	m.name = name
	m.position = pos
	parent.add_child(m)
	return m


# ---------- environment / ground ----------

func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "DirectionalLight3D"
	sun.transform = Transform3D(Basis().rotated(Vector3.RIGHT, deg_to_rad(-55)), Vector3(-40, 60, -25))
	sun.light_color = Color(0.58, 0.67, 0.87)
	sun.light_energy = 0.4 # a dim moon, not a sun - see the dark BG_COLOR environment below
	sun.shadow_enabled = true
	level_root.add_child(sun)

	var moon := OmniLight3D.new()
	moon.name = "Hemisphere"
	moon.position = Vector3(0, 30, 0)
	moon.light_color = Color(0.18, 0.23, 0.39)
	moon.light_energy = 0.18
	moon.omni_range = 90.0
	moon.shadow_enabled = false
	level_root.add_child(moon)

	var env_node := WorldEnvironment.new()
	var environment := Environment.new()
	# Flat dark-navy background instead of a procedural daytime sky, matching
	# the JS source's scene.background = 0x0a0c14 night setting.
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.039, 0.047, 0.078)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.07, 0.08, 0.12)
	environment.ambient_light_energy = 0.5
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.04, 0.047, 0.078)
	environment.fog_density = 0.02
	# Bloom on the fire particles/emissive materials is what makes them read
	# as fire rather than orange smudges - without glow they're just flat color.
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
	nav_region.navigation_mesh.cell_height = 0.25 # matches the project's default nav map cell_height
	nav_region.navigation_mesh.agent_height = 1.8
	nav_region.navigation_mesh.agent_radius = 0.4
	nav_region.navigation_mesh.agent_max_climb = 0.3
	nav_region.navigation_mesh.agent_max_slope = 46.0
	nav_region.navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	# Default SOURCE_GEOMETRY_ROOT_NODE_CHILDREN: bakes from every StaticBody3D
	# collider under this node, which is why all level geometry below nests
	# under geometry_root (this node) rather than the scene level_root directly.
	level_root.add_child(nav_region)
	geometry_root = nav_region

	var ground_mat := _tiled_material("asphalt_02", 60, 60)
	_box(geometry_root, "Ground", Vector3(240, 1, 240), Vector3(0, -0.5, 0), ground_mat)


# ---------- buildings ----------
# Coordinates ported 1:1 from zombie-town-online public/index.html:1339-2336.

func _build_bar() -> void:
	var g := Node3D.new()
	g.name = "Bar"
	geometry_root.add_child(g)
	var brick := _tiled_material("brick_wall_10", 4, 2)
	var plank := _tiled_material("brown_planks_08", 3, 3)
	var roof := _tiled_material("grey_roof_01", 4, 2)

	var x1 := -30.0
	var x2 := -14.0
	var z1 := -26.0
	var z2 := -6.0
	var h := 8.6
	var f2 := 4.0

	# Reduced to one entrance (east wall, facing the fountain/crossroads) so the
	# door below actually gates the building - see scripts/economy/CLAUDE.md.
	# The other three former doors are now windows (sill + blocking pane, added
	# by _wall_run itself); the balcony gap was already a window.
	_wall_run(g, x1, z1, x2, z1, h, brick, [{c = -22.0, w = 3.0, sill = 1.0}])
	_wall_run(g, x1, z2, x2, z2, h, brick, [{c = -20.0, w = 3.4, sill = 1.0}])
	_wall_run(g, x1, z1, x1, z2, h, brick, [{c = -14.0, w = 2.6, sill = 1.0}])
	_wall_run(g, x2, z1, x2, z2, h, brick, [{c = -16.0, w = 3.4}, {c = -10.5, w = 3.2, sill = 4.0}])
	_place_door(g, x2, z1, x2, z2, -16.0, 3.4, h, 0.0, brick, 900)
	_roof_slab(g, x1, z1, x2, z2, h, roof)
	_floor_slab(g, x1 + 0.2, z1 + 0.2, x2 - 0.2, z2 - 0.2, 0.04, plank)
	# Second floor covers the north half; staircase on the west wall.
	_floor_slab(g, x1 + 0.2, -15.7, x2 - 0.2, z2 - 0.2, f2, plank)
	_staircase(g, x1 + 0.3, x1 + 4.3, -21.4, -15.7, 0.1, f2, plank)
	# Balcony over the street, east side.
	_floor_slab(g, x2 - 0.2, -13.0, x2 + 4.4, -8.0, f2, plank)
	_box(g, "BalconyRailFront", Vector3(4.6, 1.0, 0.14), Vector3(x2 + 2.1, f2 + 1.0, -13.0), plank)
	_box(g, "BalconyRailBack", Vector3(4.6, 1.0, 0.14), Vector3(x2 + 2.1, f2 + 1.0, -8.0), plank)
	_box(g, "BalconyRailSide", Vector3(0.14, 1.0, 5.0), Vector3(x2 + 4.3, f2 + 1.0, -10.5), plank)
	# Bar counter and stools.
	_box(g, "Counter", Vector3(6.0, 1.1, 0.9), Vector3(-22.0, 0.6, -9.0), plank)
	for i in range(4):
		_cyl(g, "Stool%d" % i, 0.22, 0.22, 0.75, Vector3(-24.5 + i * 1.7, 0.42, -10.4), plank)
	_room_light(g, Vector3(-22, 3.2, -12), Color(1.0, 0.69, 0.4), 0.85, 20)
	_room_light(g, Vector3(-22, f2 + 2.4, -9), Color(1.0, 0.69, 0.4), 0.6, 16)
	_sign(g, "Saloon", Vector3(-13.6, 6.6, -14), -PI / 2)


func _build_bank() -> void:
	var g := Node3D.new()
	g.name = "Bank"
	geometry_root.add_child(g)
	var stucco := _tiled_material("beige_wall_001", 4, 2)
	var tile := _tiled_material("checkered_pavement_tiles", 3, 3)
	var concrete := _tiled_material("brushed_concrete", 2, 4)
	var roof := _tiled_material("grey_roof_01", 4, 2)

	var x1 := 14.0
	var x2 := 31.0
	var z1 := -22.0
	var z2 := -6.0
	var h := 9.2

	# Reduced to one entrance (west wall, under the columned portico) - see the
	# matching note in _build_bar().
	_wall_run(g, x1, z1, x2, z1, h, stucco, [{c = 22.0, w = 2.8, sill = 1.0}])
	_wall_run(g, x1, z2, x2, z2, h, stucco, [{c = 24.0, w = 3.4, sill = 1.0}])
	_wall_run(g, x1, z1, x1, z2, h, stucco, [{c = -16.0, w = 3.4}, {c = -9.0, w = 2.6, sill = 1.0}])
	_place_door(g, x1, z1, x1, z2, -16.0, 3.4, h, 0.0, stucco, 1200)
	_wall_run(g, x2, z1, x2, z2, h, stucco, [{c = -13.0, w = 2.4, sill = 1.0}])
	_roof_slab(g, x1, z1, x2, z2, h, roof)
	_floor_slab(g, x1 + 0.2, z1 + 0.2, x2 - 0.2, z2 - 0.2, 0.04, tile)
	for i in range(4):
		_cyl(g, "Column%d" % i, 0.45, 0.5, 7.6, Vector3(x1 - 1.6, 3.8, z1 + 3 + i * 3.6), concrete)
	_box(g, "Portico", Vector3(3.2, 0.7, 15), Vector3(x1 - 1.6, 7.9, -14), concrete)
	# Vault - a distinct gunmetal material (not the fence's corrugated iron) and
	# an upright door disc with a frame and crossed wheel handle, so it reads
	# as a vault rather than a shed. _cyl()'s cylinder axis runs vertical
	# (like a drum), which is wrong for a door set into a wall - it needs its
	# flat face toward the opening, built by hand here instead.
	var vault_metal := StandardMaterial3D.new()
	vault_metal.albedo_color = Color(0.16, 0.17, 0.19)
	vault_metal.metallic = 0.85
	vault_metal.roughness = 0.25
	_wall_run(g, 24.0, -21.6, 30.6, -21.6, 4.6, vault_metal, [])
	_wall_run(g, 24.0, -17.0, 30.6, -17.0, 4.6, vault_metal, [{c = 27.3, w = 2.6}])
	_wall_run(g, 24.0, -21.6, 24.0, -17.0, 4.6, vault_metal, [])
	_box(g, "VaultFrame", Vector3(2.9, 2.9, 0.15), Vector3(27.3, 1.7, -17.0), vault_metal)
	var door_body := StaticBody3D.new()
	door_body.name = "VaultDoor"
	g.add_child(door_body)
	door_body.position = Vector3(27.3, 1.7, -16.85)
	door_body.rotation.x = PI / 2.0
	var door_mesh := MeshInstance3D.new()
	var door_cyl := CylinderMesh.new()
	door_cyl.top_radius = 1.15
	door_cyl.bottom_radius = 1.15
	door_cyl.height = 0.3
	door_mesh.mesh = door_cyl
	door_mesh.set_surface_override_material(0, vault_metal)
	door_body.add_child(door_mesh)
	var door_shape := CollisionShape3D.new()
	var door_cyl_shape := CylinderShape3D.new()
	door_cyl_shape.radius = 1.15
	door_cyl_shape.height = 0.3
	door_shape.shape = door_cyl_shape
	door_body.add_child(door_shape)
	_box(g, "VaultWheelH", Vector3(1.5, 0.1, 0.1), Vector3(27.3, 1.7, -16.68), vault_metal, false)
	_box(g, "VaultWheelV", Vector3(0.1, 1.5, 0.1), Vector3(27.3, 1.7, -16.68), vault_metal, false)
	# Teller counter.
	_box(g, "Counter", Vector3(9.0, 1.2, 0.8), Vector3(20.0, 0.6, -11.5), concrete)
	_room_light(g, Vector3(20, 4.2, -14), Color(0.85, 0.89, 1.0), 0.7, 22)
	_room_light(g, Vector3(27.3, 3.0, -19.3), Color(1.0, 0.82, 0.54), 0.5, 10)
	_sign(g, "Bank", Vector3(13.6, 7.2, -14), PI / 2)


func _build_church() -> void:
	var g := Node3D.new()
	g.name = "Church"
	geometry_root.add_child(g)
	var stucco := _tiled_material("beige_wall_001", 3, 2)
	var tile := _tiled_material("checkered_pavement_tiles", 2, 3)
	var plank := _tiled_material("brown_planks_08", 3, 1)
	var roof := _tiled_material("ceramic_roof_01", 3, 3)

	var x1 := -9.0
	var x2 := 9.0
	var z1 := 20.0
	var z2 := 36.0
	var h := 10.5

	# Already down to one entrance (south, no sill) - the rest were already
	# windows (sill set), which _wall_run now blocks with a pane on its own.
	_wall_run(g, x1, z1, x2, z1, h, stucco, [{c = 0.0, w = 3.6}])
	_place_door(g, x1, z1, x2, z1, 0.0, 3.6, h, 0.0, stucco, 1500)
	_wall_run(g, x1, z2, x2, z2, h, stucco, [{c = 0.0, w = 3.0, sill = 2.2}])
	_wall_run(g, x1, z1, x1, z2, h, stucco, [{c = 26.0, w = 2.4, sill = 2.0}, {c = 32.0, w = 2.4, sill = 2.0}])
	_wall_run(g, x2, z1, x2, z2, h, stucco, [{c = 26.0, w = 2.4, sill = 2.0}, {c = 32.0, w = 2.4, sill = 2.0}])
	_roof_slab(g, x1, z1, x2, z2, h, roof)
	_floor_slab(g, x1 + 0.2, z1 + 0.2, x2 - 0.2, z2 - 0.2, 0.04, tile)
	for i in range(5):
		_box(g, "Pew%d" % i, Vector3(9, 0.5, 0.5), Vector3(0, 0.55, 24 + i * 2.2), plank)
	_box(g, "Altar", Vector3(3.0, 1.0, 1.4), Vector3(0, 0.5, 34), plank)
	# Tower.
	var tx := 0.0
	var tz := 32.5
	_box(g, "Tower", Vector3(5.2, 16, 5.2), Vector3(tx, 8 + 10.5, tz), stucco)
	_box(g, "TowerRoof", Vector3(3.4, 3.6, 3.4), Vector3(tx, 26.2, tz), roof)
	_room_light(g, Vector3(0, 6.5, 28), Color(1.0, 0.81, 0.6), 0.75, 26)
	_sign(g, "First Church", Vector3(0, 9.0, 19.6), 0.0)


func _build_diner() -> void:
	var g := Node3D.new()
	g.name = "Diner"
	geometry_root.add_child(g)
	var siding := _tiled_material("brown_planks_03", 3, 2)
	var tile := _tiled_material("checkered_pavement_tiles", 3, 2)
	var concrete := _tiled_material("brushed_concrete", 3, 1)
	var roof := _tiled_material("grey_roof_01", 3, 2)

	var x1 := -31.0
	var x2 := -17.0
	var z1 := 8.0
	var z2 := 20.0
	var h := 6.4

	# Reduced to one entrance (east wall, facing the sign) - see the matching
	# note in _build_bar().
	_wall_run(g, x1, z1, x2, z1, h, siding, [{c = -24.0, w = 3.0, sill = 1.0}])
	_wall_run(g, x1, z2, x2, z2, h, siding, [{c = -24.0, w = 2.6, sill = 1.0}])
	_wall_run(g, x1, z1, x1, z2, h, siding, [{c = 14.0, w = 2.4, sill = 1.0}])
	_wall_run(g, x2, z1, x2, z2, h, siding, [{c = 14.0, w = 3.4}, {c = 18.0, w = 2.6, sill = 1.0}])
	_place_door(g, x2, z1, x2, z2, 14.0, 3.4, h, 0.0, siding, 900)
	_roof_slab(g, x1, z1, x2, z2, h, roof)
	_floor_slab(g, x1 + 0.2, z1 + 0.2, x2 - 0.2, z2 - 0.2, 0.04, tile)
	_box(g, "Counter", Vector3(11, 1.05, 0.9), Vector3(-24, 0.55, 11), concrete)
	for i in range(4):
		_cyl(g, "Stool%d" % i, 0.24, 0.24, 0.8, Vector3(-28 + i * 2.2, 0.45, 12.3), concrete)
	_room_light(g, Vector3(-24, 3.4, 14), Color(1.0, 0.94, 0.75), 0.85, 20)
	_sign(g, "Diner", Vector3(-16.6, 5.0, 14), -PI / 2)


func _build_store() -> void:
	var g := Node3D.new()
	g.name = "GeneralStore"
	geometry_root.add_child(g)
	var brick := _tiled_material("brick_wall_10", 3, 2)
	var plank := _tiled_material("brown_planks_08", 3, 2)
	var roof := _tiled_material("grey_roof_01", 3, 2)

	var x1 := 17.0
	var x2 := 31.0
	var z1 := 8.0
	var z2 := 20.0
	var h := 6.4

	# Reduced to one entrance (west wall, under the sign) - see the matching
	# note in _build_bar().
	_wall_run(g, x1, z1, x2, z1, h, brick, [{c = 24.0, w = 3.0, sill = 1.0}])
	_wall_run(g, x1, z2, x2, z2, h, brick, [{c = 24.0, w = 2.6, sill = 1.0}])
	_wall_run(g, x1, z1, x1, z2, h, brick, [{c = 14.0, w = 3.4}, {c = 18.0, w = 2.4, sill = 1.0}])
	_place_door(g, x1, z1, x1, z2, 14.0, 3.4, h, 0.0, brick, 900)
	_wall_run(g, x2, z1, x2, z2, h, brick, [{c = 14.0, w = 2.4, sill = 1.0}])
	_roof_slab(g, x1, z1, x2, z2, h, roof)
	_floor_slab(g, x1 + 0.2, z1 + 0.2, x2 - 0.2, z2 - 0.2, 0.04, plank)
	for i in range(4):
		_box(g, "Shelf%d" % i, Vector3(0.7, 2.0, 5.0), Vector3(19 + i * 3.2, 1.0, 15), plank)
	_box(g, "Counter", Vector3(4.0, 1.1, 0.9), Vector3(24, 0.55, 9.6), plank)
	_room_light(g, Vector3(24, 3.4, 14), Color(1.0, 0.85, 0.63), 0.8, 20)
	_sign(g, "General Store", Vector3(17.4, 5.0, 14), PI / 2)


func _build_fountain() -> void:
	var g := Node3D.new()
	g.name = "Fountain"
	geometry_root.add_child(g)
	var concrete := _material("brushed_concrete")
	var water_mat := StandardMaterial3D.new()
	water_mat.albedo_color = Color(0.09, 0.22, 0.26, 0.85)
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water_mat.metallic = 0.2
	water_mat.roughness = 0.1

	_cyl(g, "Base", 3.3, 3.5, 1.0, Vector3(0, 0.5, 0), concrete)
	_cyl(g, "Wall", 3.0, 3.0, 0.94, Vector3(0, 0.56, 0), concrete)
	var water := MeshInstance3D.new()
	water.name = "Water"
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 2.86
	water_mesh.bottom_radius = 2.86
	water_mesh.height = 0.02
	water.mesh = water_mesh
	water.set_surface_override_material(0, water_mat)
	water.position = Vector3(0, 1.035, 0)
	g.add_child(water)
	_cyl(g, "Spout", 0.34, 0.7, 2.6, Vector3(0, 2.2, 0), concrete)
	_cyl(g, "SpoutBasin", 1.1, 1.1, 0.24, Vector3(0, 2.9, 0), concrete)
	_room_light(g, Vector3(0, 1.6, 0), Color(1.0, 0.55, 0.2), 1.1, 14)
	_fire_effect(g, Vector3(0, 3.0, 0), 1.65)


func _build_bus() -> void:
	# Simplified from the JS's ~90-line hand-tuned glass/mirror/trim geometry
	# to a blockout at the same overall bounds, position, and collider footprint -
	# see the file header note on why. Distinct paint/window/roof/light bands
	# (cosmetic overlays on the one collision shell) keep it reading as a bus
	# instead of a single flat-colored box.
	var g := Node3D.new()
	g.name = "WreckedBus"
	geometry_root.add_child(g)
	g.position = Vector3(-2, 0, -31)
	g.rotation.y = 0.16

	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.6, 0.48, 0.17)
	paint.metallic = 0.3
	paint.roughness = 0.55
	var chassis_mat := StandardMaterial3D.new()
	chassis_mat.albedo_color = Color(0.1, 0.1, 0.11)
	chassis_mat.roughness = 0.7
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.05, 0.08, 0.1, 0.7)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.metallic = 0.6
	glass.roughness = 0.15
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.42, 0.34, 0.12)
	roof_mat.roughness = 0.6
	var light_mat := StandardMaterial3D.new()
	light_mat.albedo_color = Color(1.0, 0.9, 0.6)
	light_mat.emission_enabled = true
	light_mat.emission = Color(1.0, 0.85, 0.4)
	light_mat.emission_energy_multiplier = 1.5
	var tail_mat := StandardMaterial3D.new()
	tail_mat.albedo_color = Color(0.6, 0.05, 0.05)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(0.8, 0.05, 0.05)
	tail_mat.emission_energy_multiplier = 1.2

	# The one collision box - full bus bounds, matching the original footprint.
	_box(g, "Shell", Vector3(2.85, 3.1, 10.7), Vector3(0, 1.55, 0), paint)
	# Cosmetic-only overlays (collide=false) so they don't stack redundant colliders.
	_box(g, "Chassis", Vector3(2.87, 0.7, 10.72), Vector3(0, 0.35, 0), chassis_mat, false)
	_box(g, "WindowBandL", Vector3(0.05, 0.9, 9.6), Vector3(1.44, 2.0, 0), glass, false)
	_box(g, "WindowBandR", Vector3(0.05, 0.9, 9.6), Vector3(-1.44, 2.0, 0), glass, false)
	_box(g, "Windshield", Vector3(2.6, 0.9, 0.05), Vector3(0, 2.0, -5.36), glass, false)
	_box(g, "RearWindow", Vector3(2.6, 0.9, 0.05), Vector3(0, 2.0, 5.36), glass, false)
	_box(g, "RoofCap", Vector3(2.7, 0.3, 10.5), Vector3(0, 3.05, 0), roof_mat, false)
	_box(g, "Headlight_L", Vector3(0.3, 0.2, 0.05), Vector3(-0.8, 0.8, -5.36), light_mat, false)
	_box(g, "Headlight_R", Vector3(0.3, 0.2, 0.05), Vector3(0.8, 0.8, -5.36), light_mat, false)
	_box(g, "Taillight_L", Vector3(0.25, 0.35, 0.05), Vector3(-1.0, 1.1, 5.36), tail_mat, false)
	_box(g, "Taillight_R", Vector3(0.25, 0.35, 0.05), Vector3(1.0, 1.1, 5.36), tail_mat, false)

	# Wheels: axis rotated 90 around Z so the round face points sideways
	# (like a real wheel) instead of up/down (like a drum on its end).
	for wx in [-1.3, 1.3]:
		for wz in [-3.75, 3.65]:
			var wheel_body := StaticBody3D.new()
			wheel_body.name = "Wheel"
			g.add_child(wheel_body)
			wheel_body.position = Vector3(wx, 0.53, wz)
			wheel_body.rotation.z = PI / 2.0
			var wheel_mesh := MeshInstance3D.new()
			var wheel_cyl := CylinderMesh.new()
			wheel_cyl.top_radius = 0.53
			wheel_cyl.bottom_radius = 0.53
			wheel_cyl.height = 0.32
			wheel_mesh.mesh = wheel_cyl
			wheel_mesh.set_surface_override_material(0, chassis_mat)
			wheel_body.add_child(wheel_mesh)


# ---------- cars ----------

func _vehicle_scene(name: String) -> Node3D:
	if vehicle_cache.has(name):
		return (vehicle_cache[name] as PackedScene).instantiate()
	var path := VEHICLE_DIR.path_join(name + ".fbx")
	var packed: PackedScene = load(path)
	vehicle_cache[name] = packed
	return packed.instantiate()


func _place_cars() -> void:
	var g := Node3D.new()
	g.name = "Cars"
	geometry_root.add_child(g)
	# (x, z, rot) - rot ignored from the JS source's color arg slot; JS itself
	# used explicit rotation per car via a separate table, keep flat headings.
	var placements := [
		Vector3(-8, -14, 0.35), Vector3(9, -16, 1.72), Vector3(-9, 6, 1.5),
		Vector3(11, 4, 0.1), Vector3(22, 26, 0.9), Vector3(-24, -30, 2.4),
	]
	for p in placements:
		var name: String = vehicle_names[vehicle_index % vehicle_names.size()]
		vehicle_index += 1
		var body := StaticBody3D.new()
		body.name = "Car_" + name
		g.add_child(body)
		body.position = Vector3(p.x, 0, p.y)
		body.rotation.y = p.z

		var model := _vehicle_scene(name)
		body.add_child(model)

		var shape := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = Vector3(2.3, 1.6, 4.48)
		shape.shape = box_shape
		shape.position.y = 0.8
		body.add_child(shape)


# ---------- street clutter ----------
# Simplified primitive shapes (see file header) at the JS source's exact
# coordinates/rotations/footprints.

func _place_clutter() -> void:
	var g := Node3D.new()
	g.name = "Clutter"
	geometry_root.add_child(g)
	var metal := _material("corrugated_iron")
	var plank := _material("brown_planks_03")
	var concrete := _material("brushed_concrete")

	# Dumpsters.
	for p in [Vector2(-13.5, 2.5), Vector2(15.6, -3), Vector2(6, 22)]:
		_box(g, "Dumpster", Vector3(2.3, 1.3, 1.2), Vector3(p.x, 0.65, p.y), metal)

	# Sandbag stacks (flattened cylinders stand in for the JS's sphere sacks).
	for p in [Vector2(-6, 10), Vector2(6, 10), Vector2(14, -26), Vector2(-10, -28)]:
		_cyl(g, "Sandbags", 1.5, 1.5, 0.6, Vector3(p.x, 0.3, p.y), plank)

	# Rubble piles.
	for p in [Vector2(-20, 26), Vector2(20, -30), Vector2(-32, 0), Vector2(33, 2)]:
		_box(g, "Rubble", Vector3(2.2, 0.6, 2.2), Vector3(p.x, 0.3, p.y), concrete)

	# Benches.
	for p in [Vector3(-4, 4, PI), Vector3(4, 4, PI), Vector3(-12, -2, PI / 2)]:
		var bench := _box(g, "BenchSeat", Vector3(2.25, 0.12, 0.5), Vector3(p.x, 0.5, p.y), plank)
		bench.get_parent().rotation.y = p.z

	# Trashcans.
	for p in [Vector2(-11, -4), Vector2(12, -6), Vector2(-16, 12), Vector2(18, 6)]:
		_cyl(g, "Trashcan", 0.38, 0.34, 0.92, Vector3(p.x, 0.46, p.y), metal)

	# Crates.
	var crates := [
		[-13.0, 4.0, 1.2], [-11.7, 4.5, 1.05], [13.0, -6.0, 1.25], [25.7, 24.0, 1.35],
		[-26.0, 24.0, 1.3], [-3.0, -24.0, 1.2], [-1.5, -25.0, 1.0], [20.0, 16.0, 1.2],
	]
	for c in crates:
		_box(g, "Crate", Vector3(c[2], c[2], c[2]), Vector3(c[0], c[2] / 2.0, c[1]), plank)

	# Poles.
	for p in [Vector2(-12, -24), Vector2(12, -24), Vector2(-12, 16), Vector2(12, 16), Vector2(0, -38)]:
		_cyl(g, "Pole", 0.14, 0.21, 8.5, Vector3(p.x, 4.25, p.y), plank)

	# Hedges.
	for p in [Vector2(-9, 17), Vector2(9, 17)]:
		var hedge_mat := StandardMaterial3D.new()
		hedge_mat.albedo_color = Color(0.24, 0.34, 0.16)
		_box(g, "Hedge", Vector3(7, 1.2, 1.2), Vector3(p.x, 0.6, p.y), hedge_mat)

	# Phone booths.
	for p in [Vector2(-10.5, -6), Vector2(10.5, 8)]:
		var booth_mat := StandardMaterial3D.new()
		booth_mat.albedo_color = Color(0.14, 0.29, 0.44)
		_box(g, "PhoneBooth", Vector3(1.1, 2.36, 1.1), Vector3(p.x, 1.18, p.y), booth_mat)

	# Streetlamps.
	var lamp_mat := _material("corrugated_iron")
	for p in [
		Vector2(-10, -19), Vector2(10, -10), Vector2(-10, 12), Vector2(10, 12),
		Vector2(0, -22), Vector2(-24, 4), Vector2(24, -2),
	]:
		_cyl(g, "Streetlamp", 0.08, 0.14, 5.4, Vector3(p.x, 2.7, p.y), lamp_mat)
		_room_light(g, Vector3(p.x, 5.2, p.y), Color(1.0, 0.66, 0.24), 1.2, 16)

	# Fire barrels.
	for p in [Vector2(-6, -19), Vector2(16, 20), Vector2(-20, 32), Vector2(28, -28)]:
		_cyl(g, "FireBarrel", 0.42, 0.38, 1.05, Vector3(p.x, 0.53, p.y), metal)
		_room_light(g, Vector3(p.x, 1.4, p.y), Color(1.0, 0.48, 0.13), 1.3, 8)
		_fire_effect(g, Vector3(p.x, 1.02, p.y), 0.68)


func _place_fence() -> void:
	var g := Node3D.new()
	g.name = "PerimeterFence"
	geometry_root.add_child(g)
	var mat := _tiled_material("corrugated_iron", 8, 1)
	var runs := [
		[-BND, -BND, -7.0, -BND], [7.0, -BND, BND, -BND],
		[-BND, BND, -7.0, BND], [7.0, BND, BND, BND],
		[-BND, -BND, -BND, -7.0], [-BND, 7.0, -BND, BND],
		[BND, -BND, BND, -7.0], [BND, 7.0, BND, BND],
	]
	for r in runs:
		var x1: float = r[0]
		var z1: float = r[1]
		var x2: float = r[2]
		var z2: float = r[3]
		var horiz := absf(x2 - x1) > absf(z2 - z1)
		var w: float = absf(x2 - x1) if horiz else 0.1
		var d: float = 0.1 if horiz else absf(z2 - z1)
		_box(g, "Fence", Vector3(w, 2.9, d), Vector3((x1 + x2) / 2.0, 1.45, (z1 + z2) / 2.0), mat)


## Map-wide drifting ash, ported from the JS source's 500-point ember field.
## Purely atmospheric - one particle system covering the whole play area, no
## per-fire cost.
func _place_ash() -> void:
	var ash := GPUParticles3D.new()
	ash.name = "Ash"
	ash.amount = 220
	ash.lifetime = 14.0
	ash.emitting = true
	ash.visibility_aabb = AABB(Vector3(-BND, 0, -BND), Vector3(BND * 2, 26, BND * 2))

	var process_mat := ParticleProcessMaterial.new()
	process_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_mat.emission_box_extents = Vector3(BND, 13, BND)
	process_mat.direction = Vector3(0, -1, 0)
	process_mat.spread = 15.0
	process_mat.initial_velocity_min = 0.15
	process_mat.initial_velocity_max = 0.4
	process_mat.gravity = Vector3(0, -0.05, 0)
	process_mat.turbulence_enabled = true
	process_mat.turbulence_noise_strength = 0.3
	process_mat.turbulence_noise_scale = 1.2
	process_mat.scale_min = 0.05
	process_mat.scale_max = 0.11
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.73, 0.66, 0.55, 0.0), Color(0.73, 0.66, 0.55, 0.5), Color(0.73, 0.66, 0.55, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	process_mat.color_ramp = ramp_tex
	ash.process_material = process_mat

	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.surface_set_material(0, mat)
	ash.draw_pass_1 = quad
	level_root.add_child(ash)


# ---------- buy stations / perks / Pack-a-Punch: inert placeholders ----------

## Wall/ammo buy and perk/Pack-a-Punch machine placement. Positions are the
## original JS source's own coordinates, corrected: addWallBuy/addAmmoBuy take
## (x,y,z) - a direct match for Godot - but addPerkMachine/addPackAPunch take
## (x,z,y0), which an earlier pass here had mapped straight into Vector3(x,y,z)
## without reordering (e.g. Juggernog ended up at y=-9, z=4.0 - underground -
## instead of y=4.0, z=-9, its actual position on the bar's upstairs).
##
## The old repo's 6 wall-buy + 2 ammo-buy slots don't match this game's 8-weapon
## roster, so they're repurposed: the player starts with just a pistol
## (player.tscn's loadout) and every other weapon needs one of these 7 wall-buy
## slots (including one of the two ammo-buy slots, promoted) - the 8th and
## last slot stays a plain ammo refill for the starting pistol.
func _place_economy() -> void:
	var weapons := "res://resources/weapons/"
	_place_wall_buy(level_root, Vector3(13.7, 2.3, -12.5), -PI / 2, weapons + "sniper_rifle.tres", 1500)
	_place_wall_buy(level_root, Vector3(-26.0, 2.2, -6.2), PI, weapons + "shotgun.tres", 1200)
	_place_wall_buy(level_root, Vector3(-16.7, 2.2, 10.5), PI / 2, weapons + "submachine_gun.tres", 1000)
	_place_wall_buy(level_root, Vector3(5.5, 2.4, 19.7), PI, weapons + "bullpup.tres", 1300)
	_place_wall_buy(level_root, Vector3(16.7, 2.2, 10.5), -PI / 2, weapons + "assault_rifle.tres", 1500)
	_place_wall_buy(level_root, Vector3(-13.7, 2.2, -19.5), PI / 2, weapons + "assault_rifle_2.tres", 1600)
	_place_wall_buy(level_root, Vector3(30.7, 2.2, -9.0), -PI / 2, weapons + "revolver.tres", 1000)
	_place_ammo_buy(level_root, Vector3(-20.0, 2.2, 20.3), 0.0, weapons + "pistol.tres", 250)
	# Flare Gun: a real CC0 model already in the project (assets/models/weapons/
	# cc0/flare-gun.glb, part of the same pack as every other current weapon -
	# see ASSET_MANIFEST.md) that had never been wired to a WeaponData or
	# placed anywhere. Put 2m along the same wall as the pistol ammo buy above
	# rather than a fresh spot, since that position is already confirmed clear -
	# still worth a look in-editor to check the two don't crowd each other.
	_place_wall_buy(level_root, Vector3(-20.0, 2.2, 22.3), 0.0, weapons + "flare_gun.tres", 1400)

	_place_perk_machine(level_root, Vector3(-28.6, 4.0, -9.0), -PI / 2, &"jugg", "Juggernog", Color(0.64, 0.14, 0.12), 2500)
	_place_perk_machine(level_root, Vector3(18.0, 0.0, -20.8), PI, &"speed", "Speed Cola", Color(0.22, 0.66, 0.24), 3000)
	# Just outside the church's south wall (a porch, not gated by its door) -
	# "near spawn" in the JS source's own comment, so the cheapest, most
	# essential perk is reachable before the player has paid for anything.
	_place_perk_machine(level_root, Vector3(-6.0, 0.0, 18.9), 0.0, &"revive", "Quick Revive", Color(0.29, 0.66, 0.85), 1500)
	_place_perk_machine(level_root, Vector3(-7.9, 0.0, 28.0), -PI / 2, &"dtap", "Double Tap", Color(0.85, 0.66, 0.23), 2000)
	_place_perk_machine(level_root, Vector3(29.9, 0.0, 12.0), PI / 2, &"stamin", "Stamin-Up", Color(0.84, 0.84, 0.23), 2000)
	_place_perk_machine(level_root, Vector3(-27.0, 0.0, 8.9), PI, &"mule", "Mule Kick", Color(0.85, 0.46, 0.16), 4000)

	# Beside the fountain, not gated by any door - matches the JS source's own
	# placement ("beside the burning fountain").
	_place_pack_a_punch(level_root, Vector3(0.0, 0.0, -7.2), PI)
	# Opposite side of the fountain, same distance - see _place_mystery_box's
	# own comment about not having verified this against the level visually.
	_place_mystery_box(level_root, Vector3(0.0, 0.0, 7.2), 0.0)


# ---------- player start + zombie spawns ----------

func _place_player_and_spawns() -> void:
	var player: Node3D = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	player.name = "Player"
	player.position = Vector3(0, 0, 14)
	player.rotation.y = PI
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

	var spawns := [
		[-38, -38], [38, -38], [-38, 38], [38, 38], [0, -40], [0, 40], [-40, 0], [40, 0],
		[-26, -38], [26, 38], [-38, 22], [38, -22],
	]
	for i in range(spawns.size()):
		var s: Array = spawns[i]
		_marker(director, "Spawn%d" % (i + 1), Vector3(s[0], 0, s[1]))
