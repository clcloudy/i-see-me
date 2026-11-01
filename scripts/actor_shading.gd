class_name ActorShading
extends RefCounted

## 角色反照率压暗。
##
## 为什么需要：教室的 9 盏 Static 聚光灯运行时不再照静态面（静态面吃光照贴图），
## 但**仍然照亮动态网格**，而人物正是动态网格。9 盏灯的直射是线性累加的，
## 没有真实世界的曝光适应，所以皮肤、白衬衫、袜子在灯正下方会被推到接近纯白，
## 颜色信息全丢——人物看起来像个白模。
##
## Quaternius 的角色材质是纯色、没有贴图（皮肤 #cead86、白 #b4b4b4），
## 本身并不算亮，过曝完全来自照度。这里按一个系数压 albedo 来抵消多余的照度：
## 这是补偿而不是根治，根治要降灯的能量并重烘，见 docs/光照与烘焙.md。
##
## 只改内存中的导入材质，不动 .glb 源文件；和 `character_pose._unify_materials` 同一套路。
## 用材质上的 meta 去重：同一份材质被几十个角色实例共享，重复乘会越乘越黑。

## 压暗系数。1.0 = 不改。
## 2026-11-01 扫描过 0.60 / 0.42 / 0.28 / 0.16：0.42 以上皮肤仍然顶白、衣服颜色分辨不出；
## 0.16 开始像欠曝、暗部丢细节；0.28 皮肤回到肉色且有明暗层次，取 0.30 留一点余量。
## 改这个值需要重新看一遍截图（离灯远的角色会更暗，讲台与角落是下限）。
const ALBEDO_DIM := 0.30

const META_KEY := "actor_albedo_dim"


static func dim(root: Node, factor: float = ALBEDO_DIM) -> void:
	if is_equal_approx(factor, 1.0):
		return
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var item := node as MeshInstance3D
		if item == null or item.mesh == null:
			continue
		for i in item.mesh.get_surface_count():
			_apply(item.mesh.surface_get_material(i), factor)
		# outfit 改色会复制出独立的 override 材质，它们没有压暗过，需要单独处理。
		for i in item.get_surface_override_material_count():
			_apply(item.get_surface_override_material(i), factor)


static func _apply(mat: Material, factor: float) -> void:
	if not (mat is BaseMaterial3D):
		return
	if mat.has_meta(META_KEY):
		return
	var base := mat as BaseMaterial3D
	var c := base.albedo_color
	base.albedo_color = Color(c.r * factor, c.g * factor, c.b * factor, c.a)
	mat.set_meta(META_KEY, factor)
