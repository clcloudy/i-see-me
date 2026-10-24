class_name PropKit
extends RefCounted
## 课堂小道具的程序化建模（D 人物，2026-10-24）。
##
## 24 项缺失动作里有 3 项是道具：桌边滚落的笔、讲台课本/粉笔盒、画方格同学的
## 铅笔/橡皮/本子。这里全部用 Godot 基础网格生成，不引用外部素材、不增加下载依赖；
## 尺寸按真实文具（米）建模，材质与教室其他程序化道具一致：粗糙、无高光。
##
## 返回的 Node3D 原点都在道具的“握持/放置中心”，朝向统一为：
##   +X = 长边方向，+Y = 朝上，+Z = 厚度方向。调用方只需摆位置和旋转。

static func material(color: Color, double_sided: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if double_sided:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func mesh_node(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func box(size: Vector3, mat: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	return mesh_node("Box", bm, mat)


# ---------------------------------------------------------------- 22 笔

## 圆珠笔：笔杆 + 笔帽 + 笔尖，全长 0.142 m，沿 +X。
static func pen(body_color: Color = Color(0.16, 0.20, 0.30)) -> Node3D:
	var root := Node3D.new()
	root.name = "PropPen"
	var body := CylinderMesh.new()
	body.top_radius = 0.0045
	body.bottom_radius = 0.0045
	body.height = 0.128
	body.radial_segments = 10
	body.rings = 1
	var mi := mesh_node("Body", body, material(body_color))
	# 圆柱默认沿 Y；转到 +X。
	mi.rotation_degrees.z = 90.0
	root.add_child(mi)

	var cap := CylinderMesh.new()
	cap.top_radius = 0.0052
	cap.bottom_radius = 0.0052
	cap.height = 0.032
	cap.radial_segments = 10
	var cap_mi := mesh_node("Cap", cap, material(body_color * Color(0.72, 0.72, 0.72, 1.0)))
	cap_mi.rotation_degrees.z = 90.0
	cap_mi.position.x = -0.050
	root.add_child(cap_mi)

	var clip := box(Vector3(0.028, 0.0022, 0.004), material(Color(0.72, 0.73, 0.75)))
	clip.position = Vector3(-0.042, 0.0055, 0.0)
	root.add_child(clip)

	var tip := CylinderMesh.new()
	tip.top_radius = 0.0045
	tip.bottom_radius = 0.0007
	tip.height = 0.012
	tip.radial_segments = 8
	var tip_mi := mesh_node("Tip", tip, material(Color(0.10, 0.10, 0.11)))
	tip_mi.rotation_degrees.z = -90.0
	tip_mi.position.x = 0.070
	root.add_child(tip_mi)
	root.set_meta("length", 0.142)
	return root


# ---------------------------------------------------------------- 23 讲台课本 / 粉笔盒

## 课本：封面、书页、书脊，合上状态。原点在书中心。
static func textbook(cover_color: Color = Color(0.42, 0.52, 0.40),
		size: Vector3 = Vector3(0.21, 0.027, 0.285)) -> Node3D:
	var root := Node3D.new()
	root.name = "PropTextbook"
	var cover := box(size, material(cover_color))
	root.add_child(cover)
	var pages_size := Vector3(size.x - 0.012, size.y * 0.62, size.z - 0.012)
	var pages := box(pages_size, material(Color(0.95, 0.94, 0.89)))
	pages.position = Vector3(0.003, size.y * 0.10, 0.0)
	root.add_child(pages)
	# 书脊颜色略深，放在 -X 侧
	var spine := box(Vector3(0.012, size.y * 1.02, size.z), material(cover_color * Color(0.78, 0.78, 0.78, 1.0)))
	spine.position.x = -size.x * 0.5
	root.add_child(spine)
	root.set_meta("size", size)
	return root


## 单页纸（翻页动画用）：薄片，绕自身 -X 侧（书脊）旋转。
static func page(width: float = 0.20, depth: float = 0.275) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 0.0012, depth)
	var mi := mesh_node("PropPage", bm, material(Color(0.97, 0.96, 0.92), true))
	return mi


## 粉笔盒：浅口纸盒 + 三根粉笔。原点在盒底中心。
static func chalk_box() -> Node3D:
	var root := Node3D.new()
	root.name = "PropChalkBox"
	var w := 0.110
	var d := 0.068
	var h := 0.030
	var bottom := box(Vector3(w, 0.004, d), material(Color(0.38, 0.28, 0.20)))
	bottom.position.y = 0.003
	root.add_child(bottom)
	var side_mat := material(Color(0.55, 0.42, 0.30))
	var front := box(Vector3(w, h, 0.006), side_mat)
	front.position = Vector3(0, h * 0.5, -d * 0.5)
	root.add_child(front)
	var back := box(Vector3(w, h, 0.006), side_mat)
	back.position = Vector3(0, h * 0.5, d * 0.5)
	root.add_child(back)
	var left := box(Vector3(0.006, h, d), side_mat)
	left.position = Vector3(-w * 0.5, h * 0.5, 0)
	root.add_child(left)
	var right := box(Vector3(0.006, h, d), side_mat)
	right.position = Vector3(w * 0.5, h * 0.5, 0)
	root.add_child(right)
	var chalk_colors := [Color(0.96, 0.96, 0.93), Color(0.93, 0.90, 0.72), Color(0.80, 0.88, 0.94)]
	for i in 3:
		var chalk := CylinderMesh.new()
		chalk.top_radius = 0.0078
		chalk.bottom_radius = 0.0074
		chalk.height = 0.078
		chalk.radial_segments = 8
		var mi := mesh_node("Chalk%d" % i, chalk, material(chalk_colors[i]))
		mi.rotation_degrees.z = 90.0
		mi.position = Vector3(0.0, 0.033, -0.020 + i * 0.020)
		root.add_child(mi)
	root.set_meta("top", Vector3(0, h, 0))
	return root


# ---------------------------------------------------------------- 24 铅笔 / 橡皮 / 本子

## 铅笔：六棱笔杆 + 木质笔尖 + 石墨芯，全长 0.175 m，沿 +X。
static func pencil() -> Node3D:
	var root := Node3D.new()
	root.name = "PropPencil"
	var body := CylinderMesh.new()
	body.top_radius = 0.0038
	body.bottom_radius = 0.0038
	body.height = 0.150
	body.radial_segments = 6
	body.rings = 1
	var mi := mesh_node("Body", body, material(Color(0.85, 0.66, 0.18)))
	mi.rotation_degrees.z = 90.0
	root.add_child(mi)
	var wood := CylinderMesh.new()
	wood.top_radius = 0.0038
	wood.bottom_radius = 0.0007
	wood.height = 0.020
	wood.radial_segments = 6
	var wood_mi := mesh_node("Wood", wood, material(Color(0.80, 0.66, 0.47)))
	wood_mi.rotation_degrees.z = -90.0
	wood_mi.position.x = 0.085
	root.add_child(wood_mi)
	var lead := CylinderMesh.new()
	lead.top_radius = 0.0011
	lead.bottom_radius = 0.0004
	lead.height = 0.007
	lead.radial_segments = 6
	var lead_mi := mesh_node("Lead", lead, material(Color(0.15, 0.15, 0.16)))
	lead_mi.rotation_degrees.z = -90.0
	lead_mi.position.x = 0.0975
	root.add_child(lead_mi)
	var eraser_cap := CylinderMesh.new()
	eraser_cap.top_radius = 0.0039
	eraser_cap.bottom_radius = 0.0039
	eraser_cap.height = 0.008
	eraser_cap.radial_segments = 10
	var cap_mi := mesh_node("Ferrule", eraser_cap, material(Color(0.70, 0.70, 0.72)))
	cap_mi.rotation_degrees.z = 90.0
	cap_mi.position.x = -0.079
	root.add_child(cap_mi)
	root.set_meta("length", 0.175)
	return root


## 橡皮：白灰色小方块，原点在中心。
static func eraser() -> Node3D:
	var root := Node3D.new()
	root.name = "PropEraser"
	var mi := box(Vector3(0.046, 0.021, 0.024), material(Color(0.88, 0.48, 0.47)))
	root.add_child(mi)
	return root


## 本子：封面 + 内页 + 横向浅线，打开状态略微鼓页。原点在中心。
static func notebook(size: Vector3 = Vector3(0.19, 0.012, 0.26)) -> Node3D:
	var root := Node3D.new()
	root.name = "PropNotebook"
	var cover := box(size, material(Color(0.28, 0.38, 0.55)))
	root.add_child(cover)
	var page_size := Vector3(size.x - 0.008, size.y * 0.55, size.z - 0.008)
	var pages := box(page_size, material(Color(0.96, 0.96, 0.93)))
	pages.position.y = size.y * 0.30
	root.add_child(pages)
	# 横线：几条极薄的白/灰线，低成本但在近景能看出是横格本
	var line_mat := material(Color(0.72, 0.76, 0.80))
	for i in 5:
		var line := box(Vector3(page_size.x * 0.86, 0.0006, 0.0012), line_mat)
		line.position = Vector3(0.0, size.y * 0.58, -0.09 + i * 0.045)
		root.add_child(line)
	return root
