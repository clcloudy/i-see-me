class_name LightmapUV2
extends RefCounted

## 给静态场景里的网格补第二套 UV（UV2），并统一 GI Mode，供 LightmapGI 烘焙。
## 编辑器烘焙与运行时加载走同一段代码，保证两次生成的 UV2 布局一致。

const TEXEL_SIZE := 0.05


static func prepare(scene_root: Node, texel_size: float = TEXEL_SIZE) -> int:
	var cache: Dictionary = {}
	var converted := 0
	for node in scene_root.find_children("*", "MeshInstance3D", true, false):
		var item := node as MeshInstance3D
		if item == null or item.mesh == null:
			continue
		if item.mesh.get_surface_count() == 0:
			continue
		item.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		var arrays: Array = item.mesh.surface_get_arrays(0)
		if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
			continue
		var existing: Variant = arrays[Mesh.ARRAY_TEX_UV2]
		if existing != null and not (existing as PackedVector2Array).is_empty():
			continue
		var key := _cache_key(item)
		var baked_mesh: ArrayMesh = cache.get(key)
		if baked_mesh == null:
			baked_mesh = ArrayMesh.new()
			baked_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			if baked_mesh.lightmap_unwrap(item.global_transform, texel_size) != OK:
				continue
			cache[key] = baked_mesh
		item.mesh = baked_mesh
		converted += 1
	return converted


static func has_uv2(mesh: Mesh) -> bool:
	if mesh == null or mesh.get_surface_count() == 0:
		return false
	var arrays: Array = mesh.surface_get_arrays(0)
	if arrays.is_empty():
		return false
	var uv2: Variant = arrays[Mesh.ARRAY_TEX_UV2]
	return uv2 != null and not (uv2 as PackedVector2Array).is_empty()


static func _cache_key(item: MeshInstance3D) -> String:
	var scale := item.global_transform.basis.get_scale()
	return "%s|%.3f|%.3f|%.3f" % [str(item.mesh.get_rid()), scale.x, scale.y, scale.z]
