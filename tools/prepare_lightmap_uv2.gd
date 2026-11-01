@tool
extends EditorScript

## 烘焙前的一次性准备：给当前场景里没有 UV2 的网格现场解 UV2，并选中 LightmapGI。
##
## 为什么要单独跑：`scripts/lightmap_uv2.gd` 只在运行时 `classroom.gd::_ready()` 里被调用，
## 编辑器打开场景时不会跑，所以家具 / 窗 / 门 / 灯管 / 幕布在编辑器的烘焙里是"没有 UV2"的，
## 会被 LightmapGI 直接跳过（2026-10-23 那次烘焙就只烘到了房间外壳）。
## 这里调的是同一份 `prepare()`，UV 布局与运行时重建的一致。
##
## 注意：`EditorScript` 必须写 `@tool`，否则编辑器不会把它当工具脚本、脚本编辑器里没有 ▶ 运行按钮。
##
## 用法：3D 编辑器打开 `scenes/classroom_static.tscn` → 打开本脚本 → Ctrl+Shift+X（File > Run）。

const LightmapUV2Lib = preload("res://scripts/lightmap_uv2.gd")
const SCENE_PATH := "res://scenes/classroom_static.tscn"


func _run() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		printerr("[UV2] 编辑器里没有打开的场景。先打开 res://scenes/classroom_static.tscn 再运行。")
		return
	print("[UV2] 场景：%s" % root.name)

	var started := Time.get_ticks_msec()
	var converted := LightmapUV2Lib.prepare(root)
	var elapsed := (Time.get_ticks_msec() - started) / 1000.0

	var total := 0
	var ready := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var item := node as MeshInstance3D
		if item == null or item.mesh == null:
			continue
		total += 1
		if LightmapUV2Lib.has_uv2(item.mesh):
			ready += 1
	print("[UV2] %d/%d 个网格带 UV2（本次现场解开 %d 个，用时 %.1f 秒）" % [ready, total, converted, elapsed])
	if ready < total:
		printerr("[UV2] 还有 %d 个网格没有 UV2，烘焙会跳过它们。" % (total - ready))

	# 环境光自检：`environment_mode = Scene` 会把环境光一起烘进贴图。
	# 判据不写死数值：拿**磁盘上的 .tscn** 和**编辑器内存里的场景**比对。
	# 两者不一致就说明标签页里还是旧场景（烘完没保存、标签页没重开），这一烘白跑。
	# 这样以后改环境光不需要同步改这里。
	var world_env := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		var energy := world_env.environment.ambient_light_energy
		var on_disk := _ambient_energy_on_disk()
		if on_disk < 0.0:
			print("[UV2] 环境光能量 = %.2f（读不到 .tscn 里的值，跳过比对）" % energy)
		elif is_equal_approx(energy, on_disk):
			print("[UV2] 环境光能量 = %.2f，与磁盘上的场景一致" % energy)
		else:
			printerr("[UV2] 环境光能量 = %.2f，但磁盘上是 %.2f —— 编辑器里是旧场景，关掉 classroom_static 标签页重新打开再跑一次。" % [energy, on_disk])

	var gi := root.get_node_or_null("LightmapGI") as LightmapGI
	if gi == null:
		printerr("[UV2] 没找到 LightmapGI 节点，无法提示烘焙。")
		return
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(gi)
	print("[UV2] 已选中 LightmapGI：现在点 3D 视口顶部工具栏的「烘焙光照贴图」。")
	print("[UV2] 烘完不要保存场景——这些 UV2 只是内存态，运行时由同一段代码重建。")


## 读 .tscn 文本里 Environment 的 ambient_light_energy，用于判断编辑器内存态是否过期。
func _ambient_energy_on_disk() -> float:
	var file := FileAccess.open(SCENE_PATH, FileAccess.READ)
	if file == null:
		return -1.0
	var regex := RegEx.new()
	regex.compile("ambient_light_energy = ([0-9.]+)")
	var found := regex.search(file.get_as_text())
	if found == null:
		return -1.0
	return found.get_string(1).to_float()
