class_name TeacherFace
extends Node3D
## 教师面部表情与口型（2026-10-23）。
##
## Quaternius 人物模型没有嘴部几何、没有下颌骨、也没有 blend shape，
## 脸只有「皮肤 / 头发 / 眉 / 眼」四个面。这里用程序化面片在脸前补出三组贴面件：
##   嘴（深色口腔 + 白色牙齿）—— 按音素序列开合，带笑意/撇嘴
##   眉（复制原模型的眉毛面片，略微放大外移）—— 抬起/压低/内侧倾斜
##   眼睑（肤色面片）—— 眨眼与眯眼
## 三组都挂在头骨的世界变换上，不写死世界坐标，所以任意身高/转身都成立。
##
## 尺寸在 setup() 时从头部网格实测（眼框、眉框、下巴），换模型只要头部网格
## 仍按 *_Head 命名、眼睛材质名仍以 Eye 开头即可；测不到就退回内置比例。

const MOUTH_SEGMENTS := 16
## 嘴最多张开的绝对高度（米）。
const MOUTH_MAX_HEIGHT := 0.021
## 骨骼空间 → 世界米的换算（该模型骨架带 100x 缩放，导入时实测）。
const BONE_TO_METER := 100.0
## 1 毫米在骨骼单位里的值（骨骼单位 × 100 = 米）。
const MM := 0.00001
const BLEND_RATE := 20.0

## 音素口型表：width 相对宽度，open 相对开口，smile 嘴角上扬系数。
const VISEMES: Array[Dictionary] = [
	{"width": 1.00, "open": 1.00, "smile": 0.05},   # A
	{"width": 1.04, "open": 0.55, "smile": 0.30},   # E
	{"width": 0.72, "open": 0.22, "smile": 0.18},   # I
	{"width": 0.60, "open": 0.82, "smile": -0.10},  # O
	{"width": 0.54, "open": 0.40, "smile": -0.05},  # U
	{"width": 0.90, "open": 0.02, "smile": 0.05},   # M / B / P
	{"width": 0.84, "open": 0.14, "smile": 0.10},   # F / V
	{"width": 0.80, "open": 0.26, "smile": 0.22},   # S / Z
	{"width": 0.96, "open": 0.10, "smile": 0.16},   # 停顿/换气
]

var _skel: Skeleton3D
var _head_idx: int = -1

var _mouth: MeshInstance3D
var _teeth: MeshInstance3D
var _brows: Array[MeshInstance3D] = []
var _brow_anchor: Array[Vector3] = []      # 头骨局部（米）
var _brow_side: Array[float] = []          # -1 / +1，用于对称倾斜
var _lids: Array[MeshInstance3D] = []
var _lid_anchor: Array[Vector3] = []       # 眼睛上缘中点（头骨局部米）

var _mouth_center := Vector3(0.0, 0.03, 0.098)
var _mouth_half_w: float = 0.027

var _rng := RandomNumberGenerator.new()
var _viseme: int = 8
var _viseme_timer: float = 0.0
var _viseme_duration: float = 0.12
var _mouth_open: float = 0.0
var _mouth_width: float = 0.95
var _mouth_smile: float = 0.12
var _mouth_h: float = 0.001
var _blink_wait: float = 2.4
var _blink_phase: float = -1.0
var _lid_base: float = 0.08
var _brow_raise_now: Array[float] = [0.0, 0.0]
var _brow_tilt_now: float = 0.0
var _built: bool = false
var _last_width: float = -1.0
var _last_smile: float = -99.0


## 绑定骨架与头部网格并生成全部面片。model 传人物根下的模型节点即可。
func setup(skeleton: Skeleton3D, head_bone: int, model: Node) -> void:
	_skel = skeleton
	_head_idx = head_bone
	_rng.seed = hash(str(head_bone)) + get_instance_id()
	_measure(model)
	_build_nodes()
	_built = true


## 每帧更新。head_world = Head 骨当前世界变换；expr 由 TeacherAnimator._update_face() 组装：
## smile / brow_raise / brow_raise_l|r（米）/ brow_tilt（度）/ squint / speak / speak_energy / speak_speed。
func update_face(delta: float, head_world: Transform3D, expr: Dictionary) -> void:
	if not _built or _skel == null:
		return
	var frame := Transform3D(head_world.basis.orthonormalized(), head_world.origin)
	_step_speech(delta, expr)
	_step_blink(delta)
	_step_expression(delta, expr)
	_place_mouth(frame)
	_place_brows(frame)
	_place_lids(frame)


## 供测试/调试：当前嘴张开比例（0 闭合，1 最大）。
func get_mouth_open() -> float:
	return _mouth_open


## 供测试/调试：基础眯眼比例，不含眨眼。
func get_squint() -> float:
	return _lid_base


## 供测试/调试：当前眨眼覆盖比例（0 全开，1 全闭）。
func get_eye_close() -> float:
	if _blink_phase < 0.0:
		return _lid_base
	return clampf(_lid_base + _blink_curve(_blink_phase) * (1.0 - _lid_base), 0.0, 1.0)


# ---------------------------------------------------------------- 口型

func _step_speech(delta: float, expr: Dictionary) -> void:
	var speaking := bool(expr.get("speak", false))
	var energy := float(expr.get("speak_energy", 1.0))
	var speed := float(expr.get("speak_speed", 1.0))
	if speaking:
		_viseme_timer -= delta * speed
		if _viseme_timer <= 0.0:
			_pick_viseme()
			_viseme_timer = _viseme_duration
	var v: Dictionary = VISEMES[_viseme]
	var target_open: float = float(v["open"]) * energy if speaking else 0.0
	var target_width: float = float(v["width"]) if speaking else 0.98
	# 闭合音要“干脆”，张开要“利落”；用略快的插值避免嘴一直半开。
	var rate := BLEND_RATE * (1.0 + 0.6 * (1.0 - target_open))
	var k := 1.0 - exp(-delta * rate)
	_mouth_open = lerpf(_mouth_open, target_open, k)
	_mouth_width = lerpf(_mouth_width, target_width, k)
	var smile := float(expr.get("smile", 0.1)) + (float(v["smile"]) if speaking else 0.0)
	_mouth_smile = lerpf(_mouth_smile, clampf(smile, -1.0, 1.0), 1.0 - exp(-delta * 8.0))


func _pick_viseme() -> void:
	var idx := _rng.randi() % VISEMES.size()
	# 连续闭合（M/B/P）会像在“抿嘴”，偶尔允许，但不连两次。
	if float(VISEMES[idx]["open"]) < 0.1 and float(VISEMES[_viseme]["open"]) < 0.15:
		idx = _rng.randi() % 5
	_viseme = idx
	_viseme_duration = _rng.randf_range(0.07, 0.15)


# ---------------------------------------------------------------- 眨眼 / 表情

func _step_blink(delta: float) -> void:
	if _blink_phase < 0.0:
		_blink_wait -= delta
		if _blink_wait <= 0.0:
			_blink_phase = 0.0
			_blink_wait = _rng.randf_range(2.0, 5.2)
	else:
		_blink_phase += delta
		if _blink_phase >= 0.18:
			_blink_phase = -1.0


## 0.09 秒闭合、0.09 秒睁开。
func _blink_curve(t: float) -> float:
	var half := 0.09
	if t < half:
		return t / half
	return clampf(1.0 - (t - half) / half, 0.0, 1.0)


func _step_expression(delta: float, expr: Dictionary) -> void:
	var target_lid: float = clampf(float(expr.get("squint", 0.03)), 0.0, 0.85)
	_lid_base = lerpf(_lid_base, target_lid, 1.0 - exp(-delta * 6.0))
	var raise_base: float = float(expr.get("brow_raise", 0.0))
	var extra: Array = [float(expr.get("brow_raise_l", 0.0)), float(expr.get("brow_raise_r", 0.0))]
	for i in _brow_raise_now.size():
		var target: float = raise_base + float(extra[i])
		_brow_raise_now[i] = lerpf(_brow_raise_now[i], target, 1.0 - exp(-delta * 7.0))
	var tilt: float = float(expr.get("brow_tilt", 0.0))
	_brow_tilt_now = lerpf(_brow_tilt_now, tilt, 1.0 - exp(-delta * 7.0))


# ---------------------------------------------------------------- 放置

func _place_mouth(frame: Transform3D) -> void:
	if _mouth == null:
		return
	var h: float = maxf(_mouth_open, 0.0) * MOUTH_MAX_HEIGHT
	if absf(h - _mouth_h) > 0.00004 or absf(_mouth_width - _last_width) > 0.004 \
			or absf(_mouth_smile - _last_smile) > 0.02:
		_rebuild_mouth(h)
		var teeth_h: float = minf(h * 0.42, 0.006) if _mouth_open > 0.22 else 0.0
		_rebuild_teeth(teeth_h)
		_last_width = _mouth_width
		_last_smile = _mouth_smile
		_mouth_h = h
	var pos := frame.origin + frame.basis * _mouth_center
	_mouth.global_transform = Transform3D(frame.basis, pos)
	if _teeth != null:
		_teeth.global_transform = Transform3D(frame.basis, pos + frame.basis * Vector3(0, 0, 0.0012))


func _place_brows(frame: Transform3D) -> void:
	for i in _brows.size():
		var anchor: Vector3 = _brow_anchor[i]
		var side: float = _brow_side[i]
		# 正值 = 眉内侧上挑（难过/犹豫）；head 局部 +Z 朝前，故取负号。
		var angle := deg_to_rad(-_brow_tilt_now * side)
		var basis := frame.basis * Basis(Vector3.BACK, angle)
		var pos := frame.origin + frame.basis * (anchor + Vector3(0.0, _brow_raise_now[i], 0.0))
		_brows[i].global_transform = Transform3D(basis, pos)


func _place_lids(frame: Transform3D) -> void:
	var lid: float = get_eye_close()
	for i in _lids.size():
		var anchor: Vector3 = _lid_anchor[i]
		var scale := Basis.from_scale(Vector3(1.0, maxf(lid, 0.001), 1.0))
		var basis := frame.basis * scale
		var pos := frame.origin + frame.basis * anchor
		_lids[i].global_transform = Transform3D(basis, pos)


# ---------------------------------------------------------------- 网格

func _rebuild_mouth(height: float) -> void:
	var hw: float = _mouth_half_w * _mouth_width
	var lift: float = _mouth_smile * _mouth_half_w * 0.28
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	var top := PackedVector3Array()
	var bot := PackedVector3Array()
	for i in MOUTH_SEGMENTS + 1:
		var u := -1.0 + 2.0 * float(i) / float(MOUTH_SEGMENTS)
		var curve := lift * u * u
		top.append(Vector3(u * hw, height * 0.34 + curve, 0.0))
		bot.append(Vector3(u * hw, -height * 0.66 + curve * 1.06, 0.0))
	for i in MOUTH_SEGMENTS:
		st.add_vertex(top[i])
		st.add_vertex(bot[i])
		st.add_vertex(top[i + 1])
		st.add_vertex(bot[i])
		st.add_vertex(bot[i + 1])
		st.add_vertex(top[i + 1])
	_mouth.mesh = st.commit()


func _rebuild_teeth(teeth_h: float) -> void:
	if _teeth == null:
		return
	if teeth_h <= 0.0002:
		_teeth.visible = false
		return
	_teeth.visible = true
	var hw: float = _mouth_half_w * _mouth_width * 0.72
	var h: float = maxf(_mouth_open, 0.0) * MOUTH_MAX_HEIGHT
	var lift: float = _mouth_smile * _mouth_half_w * 0.28
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	for i in MOUTH_SEGMENTS:
		var u0 := -1.0 + 2.0 * float(i) / float(MOUTH_SEGMENTS)
		var u1 := -1.0 + 2.0 * float(i + 1) / float(MOUTH_SEGMENTS)
		var c0 := lift * u0 * u0
		var c1 := lift * u1 * u1
		var top0 := Vector3(u0 * hw, h * 0.34 + c0 - h * 0.06, 0.0)
		var top1 := Vector3(u1 * hw, h * 0.34 + c1 - h * 0.06, 0.0)
		var bot0 := Vector3(u0 * hw, h * 0.34 + c0 - h * 0.06 - teeth_h, 0.0)
		var bot1 := Vector3(u1 * hw, h * 0.34 + c1 - h * 0.06 - teeth_h, 0.0)
		st.add_vertex(top0)
		st.add_vertex(bot0)
		st.add_vertex(top1)
		st.add_vertex(bot0)
		st.add_vertex(bot1)
		st.add_vertex(top1)
	_teeth.mesh = st.commit()


func _build_nodes() -> void:
	_mouth = _make_mesh_instance("FaceMouth", _prop_material(Color(0.18, 0.075, 0.09)))
	_teeth = _make_mesh_instance("FaceTeeth", _prop_material(Color(0.94, 0.93, 0.89)))
	_last_width = -1.0
	_rebuild_mouth(0.001)
	for i in _brow_meshes.size():
		var mi := MeshInstance3D.new()
		mi.name = "FaceBrow%d" % i
		mi.mesh = _brow_meshes[i]
		mi.material_override = _prop_material(_brow_color)
		add_child(mi)
		_brows.append(mi)
	for i in _lid_data.size():
		var mi := MeshInstance3D.new()
		mi.name = "FaceLid%d" % i
		mi.mesh = _lid_data[i]["mesh"]
		mi.material_override = _prop_material(_skin_color * Color(0.93, 0.93, 0.93, 1.0))
		add_child(mi)
		_lids.append(mi)


func _make_mesh_instance(node_name: String, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.material_override = mat
	add_child(mi)
	return mi


func _prop_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# 贴面片是单层三角面，关掉背面剔除，避免绕序不同导致整片看不见。
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


# ---------------------------------------------------------------- 量脸

var _brow_meshes: Array[ArrayMesh] = []
var _brow_color := Color(0.2431, 0.2039, 0.1608)
var _skin_color := Color(0.8078, 0.6784, 0.5255)
var _lid_data: Array[Dictionary] = []


## 从头部网格实测眼框、眉面片与下巴，换算到头骨局部（米）。
func _measure(model: Node) -> void:
	var head_rest := _skel.global_transform * _skel.get_bone_global_rest(_head_idx)
	var inv := head_rest.affine_inverse()
	var chin_y := INF
	var eye_min := {}
	var eye_max := {}
	var face_z: float = -INF
	for mi in _find_meshes(model):
		if not String(mi.name).ends_with("_Head"):
			continue
		var mesh := mi.mesh as ArrayMesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var mat := mesh.surface_get_material(s)
			if mat == null:
				continue
			var mat_name := String(mat.resource_name)
			var bm := mat as BaseMaterial3D
			var arr := mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var local := PackedVector3Array()
			local.resize(verts.size())
			for i in verts.size():
				local[i] = inv * (mi.global_transform * verts[i])
			if mat_name.begins_with("Skin"):
				if bm != null:
					_skin_color = bm.albedo_color
				for v in local:
					chin_y = minf(chin_y, v.y)
					face_z = maxf(face_z, v.z)
			elif mat_name.begins_with("Eyebrow"):
				if bm != null:
					_brow_color = bm.albedo_color
				_measure_brows(arr, local)
			elif mat_name.begins_with("Eye"):
				for v in local:
					var side := 0 if v.x < 0.0 else 1
					if not eye_min.has(side):
						eye_min[side] = v
						eye_max[side] = v
					else:
						eye_min[side] = (eye_min[side] as Vector3).min(v)
						eye_max[side] = (eye_max[side] as Vector3).max(v)

	var eye_y := 0.113
	var eye_z: float = face_z
	if eye_min.size() > 0:
		var sum := 0.0
		var zmax: float = -INF
		for side in eye_min:
			var lo: Vector3 = eye_min[side]
			var hi: Vector3 = eye_max[side]
			sum += (lo.y + hi.y) * 0.5
			zmax = maxf(zmax, hi.z)
			_lid_data.append(_make_lid(lo, hi))
			_lid_anchor.append(Vector3((lo.x + hi.x) * 0.5, hi.y + 0.3 * MM, zmax + 1.5 * MM) * BONE_TO_METER)
		eye_y = sum / float(eye_min.size())
		eye_z = zmax

	if chin_y == INF:
		chin_y = eye_y - 0.20
	# 嘴位于下巴到眼线之间约 60% 处（该低模脸下巴较长，实测比例）。
	# 贴面深度用眼框前沿做基准：整张脸的最大 z 会取到鼻尖/额头的顶点，嘴会浮在脸前。
	var mouth_y: float = chin_y + 0.56 * (eye_y - chin_y)
	_mouth_center = Vector3(0.0, mouth_y, eye_z + 1.6 * MM) * BONE_TO_METER
	# 嘴宽约等于两眼中心距的 0.6 倍（半宽 0.30 倍）。
	var sep: float = 0.088
	if eye_min.size() == 2:
		var centers: Array = []
		for side in eye_min:
			var lo: Vector3 = eye_min[side]
			var hi: Vector3 = eye_max[side]
			centers.append((lo.x + hi.x) * 0.5)
		sep = absf(float(centers[0]) - float(centers[1]))
	_mouth_half_w = maxf(sep * 0.30 * BONE_TO_METER, 0.018)


func _measure_brows(arr: Array, local: PackedVector3Array) -> void:
	var idxs: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var groups := {0: [], 1: []}
	for t in range(0, idxs.size(), 3):
		var a := local[idxs[t]]
		var b := local[idxs[t + 1]]
		var c := local[idxs[t + 2]]
		var cx: float = (a.x + b.x + c.x) / 3.0
		var side := 0 if cx < 0.0 else 1
		(groups[side] as Array).append([a, b, c])
	for side in [0, 1]:
		var tris: Array = groups[side]
		if tris.is_empty():
			continue
		var center := Vector3.ZERO
		var normal := Vector3.ZERO
		var count := 0
		for tri in tris:
			var a: Vector3 = tri[0]
			var b: Vector3 = tri[1]
			var c: Vector3 = tri[2]
			center += (a + b + c) / 3.0
			normal += (b - a).cross(c - a)
			count += 1
		center /= float(count)
		normal = normal.normalized()
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for tri in tris:
			for v in tri:
				var p: Vector3 = (v - center) * 1.12 + normal * 1.5 * MM
				st.set_normal(normal)
				st.add_vertex(p * BONE_TO_METER)
		_brow_meshes.append(st.commit())
		_brow_anchor.append((center + normal * 1.5 * MM) * BONE_TO_METER)
		_brow_side.append(-1.0 if side == 0 else 1.0)


## 眼睛上缘对齐的肤色面片：y 从 0 向下到 -高度，按 lid 比例缩放遮住眼睛。
func _make_lid(lo: Vector3, hi: Vector3) -> Dictionary:
	var w: float = (hi.x - lo.x) * 1.18 * BONE_TO_METER
	var h: float = (hi.y - lo.y) * 1.25 * BONE_TO_METER
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.BACK)
	var hw := w * 0.5
	st.add_vertex(Vector3(-hw, 0.0, 0.0))
	st.add_vertex(Vector3(-hw, -h, 0.0))
	st.add_vertex(Vector3(hw, 0.0, 0.0))
	st.add_vertex(Vector3(-hw, -h, 0.0))
	st.add_vertex(Vector3(hw, -h, 0.0))
	st.add_vertex(Vector3(hw, 0.0, 0.0))
	return {"mesh": st.commit()}


func _find_meshes(node: Node) -> Array:
	var out := []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out += _find_meshes(c)
	return out
