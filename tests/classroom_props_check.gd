extends SceneTree

const CAPTURE_DIR := "res://.local/captures/classroom-props"

## 地板木条：第一条缝离前墙（z = -5）约 0.30 米，条宽约 0.307 米，第三块木条的中心在离墙 0.77 米处。
const FRONT_WALL_Z := -5.0
const FLOOR_PLANK_CENTRE_3 := 0.769

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/classroom_static.tscn") as PackedScene
	_expect(packed != null, "静态教室场景无法加载")
	if packed == null:
		_finish()
		return
	var classroom := packed.instantiate() as Node3D
	root.add_child(classroom)
	await process_frame
	await process_frame

	var door := classroom.get_node_or_null("Walls/Door") as Node3D
	var clock := classroom.get_node_or_null("Walls/Clock") as DigitalClock
	var equipment := classroom.get_node_or_null("Walls/WallAVSecurity") as Node3D
	_expect(door != null, "缺少大门节点")
	_expect(clock != null, "缺少电子钟同步脚本")
	_expect(equipment != null, "缺少墙面监控/播音组件")
	if door != null:
		_expect(door.get_node_or_null("LeafLeft") is MeshInstance3D, "左门扇不是网格模型")
		_expect(door.get_node_or_null("LeafRight") is MeshInstance3D, "右门扇不是网格模型")
		_expect(door.get_node_or_null("LeafRight/Recess") == null, "门洞内衬应保持独立")
		_expect(door.get_node_or_null("Recess") is MeshInstance3D, "缺少门洞暗色内衬")
		_expect(door.get_node_or_null("TransomRail") is MeshInstance3D, "缺少亮窗横梁")
		_expect(door.get_node_or_null("LatticeL3") is MeshInstance3D, "缺少亮窗斜格")
		_check_door_closed(door)
		_check_door_fittings(door)
		_check_transom_lattice(door)
	if clock != null:
		var now := Time.get_time_dict_from_system(false)
		var expected := "%02d:%02d" % [int(now.hour), int(now.minute)]
		_expect(clock.get_display_text() == expected,
			"电子钟未同步系统时间：%s != %s" % [clock.get_display_text(), expected])
		_expect(clock.get_node_or_null("Display") is Label3D, "电子钟缺少数字显示")
	if equipment != null:
		_expect(equipment.get_node_or_null("CameraBase") is MeshInstance3D, "缺少半球监控底座")
		_expect(equipment.get_node_or_null("Dome") is MeshInstance3D, "缺少监控烟色球罩")
		_expect(equipment.get_node_or_null("Lens") is MeshInstance3D, "缺少监控镜头")
		_expect(equipment.get_node_or_null("Speaker/Housing") is MeshInstance3D, "缺少广播音箱")
		_expect(equipment.get_node_or_null("ControlBox") is MeshInstance3D, "缺少设备接线盒")
	_check_air_conditioner(classroom)

	await _capture_details(classroom)
	classroom.queue_free()
	await process_frame
	_finish()


func _capture_details(classroom: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		print("SKIP: 可视截图需要启用渲染窗口。")
		return
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	var camera := Camera3D.new()
	camera.fov = 50.0
	camera.near = 0.03
	camera.current = true
	classroom.add_child(camera)

	await _capture_view(camera, Vector2i(900, 1100), Vector3(-2.55, 1.35, -2.40),
		Vector3(-4.95, 1.25, -2.40), "door-detail.png")
	camera.fov = 38.0
	await _capture_view(camera, Vector2i(1200, 700), Vector3(-3.30, 1.85, -2.40),
		Vector3(-4.95, 2.08, -2.40), "door-transom-detail.png")
	camera.fov = 42.0
	await _capture_view(camera, Vector2i(1200, 900), Vector3(-3.55, 1.45, -2.62),
		Vector3(-4.95, 1.32, -2.72), "door-window-detail.png")
	camera.fov = 56.0
	await _capture_view(camera, Vector2i(1400, 900), Vector3(-1.9, 2.7, -2.6),
		Vector3(-4.94, 2.7, -2.92), "wall-equipment-detail.png")
	camera.fov = 58.0
	await _capture_view(camera, Vector2i(1400, 900), Vector3(-1.20, 1.55, 0.60),
		Vector3(4.80, 1.05, -4.60), "air-conditioner-corner.png")
	camera.fov = 42.0
	await _capture_view(camera, Vector2i(1000, 1000), Vector3(2.30, 1.25, -4.05),
		Vector3(4.85, 0.95, -4.70), "air-conditioner-detail.png")


func _capture_view(
	camera: Camera3D, size: Vector2i, from: Vector3, look_at: Vector3, filename: String
) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	camera.global_position = from
	camera.look_at(look_at, Vector3.UP)
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_expect(image != null and not image.is_empty(), "截图渲染为空：" + filename)
	if image != null and not image.is_empty():
		var path := CAPTURE_DIR.path_join(filename)
		_expect(image.save_png(path) == OK, "截图保存失败：" + path)
		print("CAPTURE: ", ProjectSettings.globalize_path(path))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)


## 运行时 lightmap_uv2 会把 BoxMesh 换成 ArrayMesh，所以尺寸从 AABB 取。
func _box_size(item: MeshInstance3D) -> Vector3:
	if item.mesh == null:
		return Vector3.ZERO
	var box := item.mesh as BoxMesh
	if box != null:
		return box.size
	return item.mesh.get_aabb().size


## 两扇门必须关着，并在中间留一道对开缝。
func _check_door_closed(door: Node3D) -> void:
	var leaf_left := door.get_node_or_null("LeafLeft") as MeshInstance3D
	var leaf_right := door.get_node_or_null("LeafRight") as MeshInstance3D
	if leaf_left == null or leaf_right == null:
		return
	_expect(absf(leaf_left.rotation.y) < 0.01 and absf(leaf_right.rotation.y) < 0.01,
		"大门应保持关闭：两扇门扇都不能绕门轴旋转")
	_expect(leaf_right.position.x > leaf_left.position.x, "左右门扇位置颠倒")
	_expect(absf(leaf_left.position.z - leaf_right.position.z) < 0.001, "两扇门扇不在同一门面")
	var seam := (leaf_right.position.x - _box_size(leaf_right).x / 2.0) \
		- (leaf_left.position.x + _box_size(leaf_left).x / 2.0)
	_expect(seam >= -0.001 and seam <= 0.02,
		"对开缝应留在 0~20 毫米之间，当前 %d 毫米" % int(round(seam * 1000.0)))
	_expect(_box_size(leaf_left).x + _box_size(leaf_right).x > 1.75, "两扇门合起来未盖住 1.8 米门洞")


## 把手（两侧各一只，含底座与手柄）、右门扇小窗。
func _check_door_fittings(door: Node3D) -> void:
	var handles: Array[Node3D] = []
	for handle_name in ["HandleLeft", "HandleRight"]:
		var handle := door.get_node_or_null(handle_name) as MeshInstance3D
		_expect(handle != null, "缺少门把手：" + handle_name)
		if handle == null:
			continue
		handles.append(handle)
		_expect(handle.get_node_or_null("Lever") is MeshInstance3D, "门把手缺少手柄：" + handle_name)
		_expect(handle.get_node_or_null("Rose") is MeshInstance3D, "门把手缺少底座：" + handle_name)
		_expect(handle.position.y > 0.9 and handle.position.y < 1.15,
			"门把手高度不在 0.9~1.15 米：%s" % handle_name)
	if handles.size() == 2:
		var left := handles[0]
		var right := handles[1]
		_expect(left.position.x < 0.0 and right.position.x > 0.0, "左右把手应分在对开缝两侧")
		var left_lever := left.get_node_or_null("Lever") as Node3D
		var right_lever := right.get_node_or_null("Lever") as Node3D
		_expect(left_lever != null and left_lever.position.x < 0.0, "左门柄应朝门轴一侧")
		_expect(right_lever != null and right_lever.position.x > 0.0, "右门柄应朝门轴一侧")
	# 右门扇小窗：玻璃 + 压条 + 暗色窗洞边
	var window_glass := door.get_node_or_null("LeafRight/WindowGlass") as MeshInstance3D
	_expect(window_glass != null, "右门扇缺少小窗玻璃")
	_expect(door.get_node_or_null("LeafRight/WindowTrimTop") is MeshInstance3D, "小窗缺少上压条")
	_expect(door.get_node_or_null("LeafRight/WindowTrimLeft") is MeshInstance3D, "小窗缺少侧压条")
	_expect(door.get_node_or_null("LeafRight/WindowReveal") is MeshInstance3D, "小窗缺少窗洞暗边")
	var leaf_right := door.get_node_or_null("LeafRight") as MeshInstance3D
	if window_glass != null and leaf_right != null:
		var glass_size := _box_size(window_glass)
		_expect(glass_size.x > 0.15 and glass_size.y > 0.25, "小窗尺寸过小，读不出是窗")
		_expect(window_glass.position.x < 0.0, "小窗应偏向对开缝一侧")
		var centre_y := leaf_right.position.y + window_glass.position.y
		_expect(centre_y > 1.2 and centre_y < 1.75, "小窗应在门扇上半部（1.2~1.75 米）")


## 亮窗斜格：左右两组杆件在同一交叉点相交成菱形，杆端搭到上下横梁。
func _check_transom_lattice(door: Node3D) -> void:
	var rail := door.get_node_or_null("TransomRail") as MeshInstance3D
	var head := door.get_node_or_null("FrameTop") as MeshInstance3D
	if rail == null or head == null:
		return
	var rail_top := rail.position.y + _box_size(rail).y / 2.0
	var head_bottom := head.position.y - _box_size(head).y / 2.0
	var left_bars: Array[MeshInstance3D] = []
	var right_bars: Array[MeshInstance3D] = []
	for child in door.get_children():
		if not (child is MeshInstance3D):
			continue
		var bar := child as MeshInstance3D
		if String(bar.name).begins_with("LatticeL"):
			left_bars.append(bar)
		elif String(bar.name).begins_with("LatticeR"):
			right_bars.append(bar)
	_expect(left_bars.size() >= 5, "亮窗斜格少于 5 组，菱形太稀")
	_expect(left_bars.size() == right_bars.size(), "亮窗斜格左右两组数量不一致")
	if left_bars.is_empty() or right_bars.size() != left_bars.size():
		return
	left_bars.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool: return a.position.x < b.position.x)
	right_bars.sort_custom(func(a: MeshInstance3D, b: MeshInstance3D) -> bool: return a.position.x < b.position.x)
	var span := left_bars[left_bars.size() - 1].position.x - left_bars[0].position.x
	_expect(span > 1.2, "亮窗斜格没有铺满门宽")
	for index in left_bars.size():
		var bar_l := left_bars[index]
		var bar_r := right_bars[index]
		var label := "第 %d 组斜格" % (index + 1)
		_expect(absf(bar_l.position.x - bar_r.position.x) < 0.001
			and absf(bar_l.position.y - bar_r.position.y) < 0.001, label + "没有交在同一点上")
		_expect(absf(bar_l.rotation.z + bar_r.rotation.z) < 0.001, label + "左右角度不对称")
		var degrees := absf(rad_to_deg(bar_l.rotation.z))
		_expect(degrees > 20.0 and degrees < 70.0, label + "角度不像菱形交叉")
		var tip := absf(sin(bar_l.rotation.z)) * _box_size(bar_l).x / 2.0
		var top := bar_l.position.y + tip
		var bottom := bar_l.position.y - tip
		_expect(absf(top - head_bottom) < 0.02 and absf(bottom - rail_top) < 0.02,
			label + "没有顶到上下横梁，菱形会断开")


## 右前角（窗墙与前墙的交角）应立着一台柜式空调。
func _check_air_conditioner(classroom: Node3D) -> void:
	var unit := classroom.get_node_or_null("AirConditioner") as Node3D
	_expect(unit != null, "缺少右前角的柜式空调")
	if unit == null:
		return
	var shell := unit.get_node_or_null("Shell") as MeshInstance3D
	_expect(shell != null, "空调缺少主体外壳")
	_expect(unit.get_node_or_null("UpperPanel") is MeshInstance3D, "空调缺少上部面板")
	_expect(unit.get_node_or_null("Display") is MeshInstance3D, "空调缺少显示条")
	_expect(unit.get_node_or_null("StileLeft") is MeshInstance3D
		and unit.get_node_or_null("StileRight") is MeshInstance3D, "空调缺少两侧立柱")
	var origin := unit.global_position
	_expect(origin.x > 4.2 and origin.z < -4.2, "空调不在右前角：%s" % origin)
	if shell == null:
		return
	var shell_size := _box_size(shell)
	var bottom := shell.global_position.y - shell_size.y / 2.0
	var top := shell.global_position.y + shell_size.y / 2.0
	_expect(shell_size.y > 1.5 and shell_size.y < 2.0, "空调高度不像柜机：%.2f 米" % shell_size.y)
	_expect(shell_size.x < 0.8 and shell_size.z < 0.5, "空调占地过大：%.2f × %.2f 米" % [shell_size.x, shell_size.z])
	_expect(bottom < 0.1 and top > 1.6, "空调没有落地或没有立到墙角高度：%.2f ~ %.2f 米" % [bottom, top])
	# 地板木条宽约 0.307 米、第一条缝离前墙约 0.30 米，所以第三块木条的中心在离前墙 0.77 米处；
	# 空调右边要正好落在那条中心线上（look 向 +X 时，画面右边对应世界 +Z）。
	var right_edge := origin.z + shell_size.x / 2.0
	_expect(absf(right_edge - (FRONT_WALL_Z + FLOOR_PLANK_CENTRE_3)) < 0.02,
		"空调右边没有落在第三块木板中间：%.3f 米" % right_edge)
	# 出风面板在正面中上部
	var outlet := unit.get_node_or_null("OutletBack") as MeshInstance3D
	_expect(outlet != null, "空调缺少出风面板")
	_expect(unit.get_node_or_null("Louver1") is MeshInstance3D, "出风面板缺少导风叶")
	if outlet != null:
		var outlet_centre := origin.y + outlet.position.y
		_expect(outlet_centre > 1.15 and outlet_centre < 1.7, "出风面板不在正面中上部：%.2f 米" % outlet_centre)
		_expect(_box_size(outlet).x > 0.3 and _box_size(outlet).y > 0.2, "出风面板太小")
	var panel := unit.get_node_or_null("UpperPanel") as Node3D
	if panel != null:
		_expect(panel.global_position.x < origin.x, "空调正面应朝向教室内")
		_expect(panel.global_position.x < 4.78, "空调正面贴住了墙，摆不进角落")


func _finish() -> void:
	if _failures.is_empty():
		print("PASS: closed door (handles, window, diamond transom), corner air conditioner, clock and wall equipment checks completed.")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: ", failure)
	quit(1)
