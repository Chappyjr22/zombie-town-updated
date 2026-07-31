extends SceneTree

const TARGETS := [
	"res://assets/models/characters/_fpsarms_probe/source/fpsarms.fbx",
	"res://assets/models/characters/mixamo_soldier.glb",
	"res://assets/models/characters/mixamo_soldier_arms.glb",
	"res://assets/models/weapons/AssaultRifle_1.fbx",
]


func _initialize() -> void:
	for path in TARGETS:
		print("\n================ ", path, " ================")
		var packed := load(path) as PackedScene
		if packed == null:
			print("  !! could not load")
			continue
		var model := packed.instantiate()
		root.add_child(model)
		_dump_tree(model, 0)
		_dump_meshes(model)
		_dump_skeleton(model)
		_dump_animations(model)
		model.queue_free()
		root.remove_child(model)
	quit()


func _dump_tree(node: Node, depth: int) -> void:
	print("  ", "  ".repeat(depth), node.name, " [", node.get_class(), "]")
	if depth > 2:
		return
	for child in node.get_children():
		_dump_tree(child, depth + 1)


func _dump_meshes(model: Node) -> void:
	for node in _find_all(model, "MeshInstance3D"):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		print("  MESH ", mesh_instance.name, " surfaces=", mesh_instance.mesh.get_surface_count())
		for surface in mesh_instance.mesh.get_surface_count():
			var arrays := mesh_instance.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var material := mesh_instance.mesh.surface_get_material(surface)
			var material_name := material.resource_name if material else "<none>"
			print(
				"    surface ", surface,
				"  verts=", vertices.size(),
				"  tris=", indices.size() / 3,
				"  material=", material_name,
				"  has_bones=", arrays[Mesh.ARRAY_BONES] != null
			)
		if mesh_instance.skin:
			print("    skin binds=", mesh_instance.skin.get_bind_count())


func _dump_skeleton(model: Node) -> void:
	for node in _find_all(model, "Skeleton3D"):
		var skeleton := node as Skeleton3D
		print("  SKELETON ", skeleton.name, " bones=", skeleton.get_bone_count())
		var names := PackedStringArray()
		for bone in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(bone))
		print("    ", ", ".join(names))


func _dump_animations(model: Node) -> void:
	for node in _find_all(model, "AnimationPlayer"):
		var animation_player := node as AnimationPlayer
		print("  ANIMPLAYER ", animation_player.name)
		for animation_name in animation_player.get_animation_list():
			var animation := animation_player.get_animation(animation_name)
			print(
				"    ", animation_name,
				"  length=", animation.length,
				"  tracks=", animation.get_track_count()
			)


func _find_all(node: Node, type_name: String, out: Array = []) -> Array:
	if node.is_class(type_name):
		out.append(node)
	for child in node.get_children():
		_find_all(child, type_name, out)
	return out
