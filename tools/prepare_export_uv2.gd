extends SceneTree

## 使用编辑器二进制的解 UV2 功能，保存发行模板可直接读取的数据，不重写源场景。
const UV2 = preload("res://scripts/lightmap_uv2.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/classroom_static.tscn") as PackedScene
	var classroom := scene.instantiate()
	root.add_child(classroom) # classroom._ready() 用现有算法补齐 UV2。
	await process_frame
	var meshes: Dictionary = {}
	for node in classroom.find_children("*", "MeshInstance3D", true, false):
		var item := node as MeshInstance3D
		if item.mesh == null:
			continue
		if not UV2.has_uv2(item.mesh):
			push_error("Export mesh has no UV2: " + str(classroom.get_path_to(item)))
			quit(1)
			return
		meshes[str(classroom.get_path_to(item))] = item.mesh
	var cache := Resource.new()
	cache.set_meta("meshes", meshes)
	var result := ResourceSaver.save(cache, UV2.EXPORT_CACHE, ResourceSaver.FLAG_COMPRESS)
	classroom.queue_free()
	await process_frame
	if result != OK:
		push_error("Cannot save export UV2 cache: %s" % result)
		quit(1)
		return
	print("PASS: prepared export UV2 for %d classroom meshes." % meshes.size())
	quit(0)
