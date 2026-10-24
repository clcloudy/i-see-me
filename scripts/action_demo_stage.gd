class_name ActionDemoStage
extends RefCounted
## 动作演示场景的共用布景（2026-10-24）。
##
## 四个演示场景（主角 / 同学 / 教师 / 道具）只需要角色和动作，布景统一在这里生成：
## 地面、背景、冷暖两盏灯、椅子、课桌、讲台、黑板、3D 标签与 HUD。
## 全部用基础网格，不引用外部素材。

const BG := Color(0.66, 0.73, 0.78)
const FLOOR := Color(0.55, 0.55, 0.56)
const WOOD := Color(0.55, 0.42, 0.30)
const WOOD_DARK := Color(0.38, 0.29, 0.21)
const BOARD := Color(0.13, 0.22, 0.19)


static func build(parent: Node3D, cam_pos: Vector3, look_at: Vector3,
		floor_size: float = 12.0) -> Camera3D:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.82, 0.87, 0.93)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-48, 32, 0)
	key.light_energy = 1.15
	key.shadow_enabled = true
	parent.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, -135, 0)
	fill.light_energy = 0.35
	fill.light_color = Color(0.85, 0.90, 1.0)
	parent.add_child(fill)

	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(floor_size, floor_size)
	floor_mi.mesh = plane
	floor_mi.material_override = PropKit.material(FLOOR)
	parent.add_child(floor_mi)

	# 背景墙，避免镜头里出现纯色虚空
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(floor_size, 3.0, 0.08)
	wall.mesh = wall_mesh
	wall.position = Vector3(0, 1.5, -3.6)
	wall.material_override = PropKit.material(Color(0.72, 0.75, 0.77))
	parent.add_child(wall)

	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.near = 0.05
	cam.far = 50.0
	parent.add_child(cam)
	cam.current = true
	cam.look_at_from_position(cam_pos, look_at, Vector3.UP)
	return cam


## 教室椅：座面 0.45 m，椅背在 +Z 一侧（角色面向 -Z）。
static func chair(parent: Node3D, pos: Vector3, with_back: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "DemoChair"
	root.position = pos
	parent.add_child(root)
	var seat := MeshInstance3D.new()
	var seat_mesh := BoxMesh.new()
	seat_mesh.size = Vector3(0.42, 0.045, 0.42)
	seat.mesh = seat_mesh
	seat.position.y = 0.45
	seat.material_override = PropKit.material(WOOD)
	root.add_child(seat)
	if with_back:
		var back := MeshInstance3D.new()
		var back_mesh := BoxMesh.new()
		back_mesh.size = Vector3(0.42, 0.42, 0.045)
		back.mesh = back_mesh
		back.position = Vector3(0, 0.68, 0.20)
		back.material_override = PropKit.material(WOOD_DARK)
		root.add_child(back)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var leg_mesh := BoxMesh.new()
			leg_mesh.size = Vector3(0.035, 0.45, 0.035)
			leg.mesh = leg_mesh
			leg.position = Vector3(0.17 * sx, 0.225, 0.17 * sz)
			leg.material_override = PropKit.material(WOOD_DARK)
			root.add_child(leg)
	return root


## 课桌：桌面 0.72 m。
static func desk(parent: Node3D, pos: Vector3, size: Vector3 = Vector3(1.05, 0.04, 0.52)) -> Node3D:
	var root := Node3D.new()
	root.name = "DemoDesk"
	root.position = pos
	parent.add_child(root)
	var top := MeshInstance3D.new()
	var top_mesh := BoxMesh.new()
	top_mesh.size = size
	top.mesh = top_mesh
	top.position.y = 0.72
	top.material_override = PropKit.material(Color(0.68, 0.54, 0.39))
	root.add_child(top)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var leg_mesh := BoxMesh.new()
			leg_mesh.size = Vector3(0.045, 0.72, 0.045)
			leg.mesh = leg_mesh
			leg.position = Vector3((size.x * 0.5 - 0.06) * sx, 0.36, (size.z * 0.5 - 0.06) * sz)
			leg.material_override = PropKit.material(WOOD_DARK)
			root.add_child(leg)
	return root


## 黑板：+Z 面朝向教室。
static func blackboard(parent: Node3D, pos: Vector3, size: Vector3 = Vector3(2.2, 1.25, 0.06)) -> Node3D:
	var root := Node3D.new()
	root.name = "DemoBoard"
	root.position = pos
	parent.add_child(root)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	board.mesh = bm
	board.material_override = PropKit.material(BOARD)
	root.add_child(board)
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = size + Vector3(0.08, 0.08, 0.02)
	frame.mesh = fm
	frame.position = Vector3(0, 0, -0.02)
	frame.material_override = PropKit.material(WOOD_DARK)
	root.add_child(frame)
	return root


## 讲台。
static func podium(parent: Node3D, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "DemoPodium"
	root.position = pos
	parent.add_child(root)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.92, 0.5)
	body.mesh = bm
	body.position.y = 0.46
	body.material_override = PropKit.material(WOOD)
	root.add_child(body)
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.98, 0.04, 0.56)
	top.mesh = tm
	top.position.y = 0.94
	top.material_override = PropKit.material(WOOD_DARK)
	root.add_child(top)
	return root


## 3D 文字标签（面向相机）。
static func label(parent: Node3D, text: String, pos: Vector3,
		font_size: int = 44, color: Color = Color(0.12, 0.16, 0.24)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.position = pos
	l.font_size = font_size
	l.outline_size = 8
	l.modulate = color
	l.outline_modulate = Color(1, 1, 1, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	parent.add_child(l)
	return l


## 屏幕 HUD（左下角说明 + 当前动作）。
static func hud(parent: Node3D) -> Label:
	var layer := CanvasLayer.new()
	parent.add_child(layer)
	var l := Label.new()
	l.name = "DemoHUD"
	l.position = Vector2(24, 20)
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.09, 0.14))
	l.add_theme_constant_override("outline_size", 8)
	layer.add_child(l)
	return l
