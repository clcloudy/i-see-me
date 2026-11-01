extends SceneTree

## 烘焙自检：确认光照贴图里真的烘进了整间教室，而不是只有房间外壳。
##
## 运行：Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/lightmap_check.gd
##
## 判据：
##   1. 烘焙网格实例数 ≥ 600。只烘到房间外壳时是 23；整间教室（含家具/窗/幕布）约 665。
##      低于这个数通常意味着烘焙前没跑 `tools/prepare_lightmap_uv2.gd`。
##   2. `assets/lightmaps/classroom.exr.import` 的 `slices/vertical` 必须等于贴图实际层数，
##      否则运行时会按错误的层数切片（改几何导致层数变化时最容易踩）。

const MIN_USERS := 600
const IMPORT_PATH := "res://assets/lightmaps/classroom.exr.import"


func _initialize() -> void:
	var data: LightmapGIData = load("res://assets/lightmaps/classroom.lmbake")
	if data == null:
		push_error("assets/lightmaps/classroom.lmbake 加载失败")
		quit(1)
		return
	var users := data.get_user_count()
	var textures := data.get_lightmap_textures()
	var layers := 0
	var size := Vector2i.ZERO
	if textures.size() > 0:
		layers = textures[0].get_layers()
		size = Vector2i(textures[0].get_width(), textures[0].get_height())
	print("LIGHTMAP users=%d atlas=%dx%d layers=%d" % [users, size.x, size.y, layers])

	var ok := true
	if users < MIN_USERS:
		ok = false
		push_error("烘焙只覆盖 %d 个网格（应 ≥ %d）：烘焙前先跑 tools/prepare_lightmap_uv2.gd。" % [users, MIN_USERS])

	var slices := _read_slices_vertical()
	if slices != layers:
		ok = false
		push_error("classroom.exr.import 的 slices/vertical=%d 与贴图层数 %d 不一致，运行时切片会错位。" % [slices, layers])

	print("LIGHTMAP CHECK: %s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)


func _read_slices_vertical() -> int:
	var file := FileAccess.open(IMPORT_PATH, FileAccess.READ)
	if file == null:
		return -1
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line.begins_with("slices/vertical="):
			return int(line.split("=")[1])
	return -1
