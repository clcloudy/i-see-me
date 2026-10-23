extends Node3D
## 静态姿态人物（D 人物，CHAR-001）。挂在人物场景根节点上：
## 根节点原点在地面、朝向局部 -Z，子节点 Model 为 Quaternius GLB 实例，
## 根节点保留 ViewAnchor 视点锚点（坐姿 1.36、站姿 1.7，与第一周镜头约定一致）。
##
## 姿态为纯静态：只旋转骨骼 + 整体下沉模型，无动画、无口型、无表情。
## 角度表来自 2026-10-17 第一周验证（膝盖角度经批量渲染扫描校准，勿凭感觉改）。
## 注意：该 GLB 的骨架带 100x 缩放，骨骼局部坐标是厘米级——
## 绝对不要往骨骼位置字段写米制数值，会放大 100 倍沉入地板；高度只用 Model 节点整体下沉。

enum Pose {
	STAND, SIT, HEAD_DOWN, HEAD_UP, REBUT, WRITING,
	# 10.22 任务书新增：课堂对话与事件姿态
	STAND_TALK,     # 站起看向讲台说话（主角答问）
	WHISPER_L,      # 坐姿向左邻居交头接耳（议论纷纷）
	WHISPER_R,      # 坐姿向右邻居交头接耳
	COVER_MOUTH,    # 坐姿低头掩嘴低笑（E02，右臂 IK 到嘴边）
	SIDE_GLANCE_L,  # 坐姿侧脸看向左侧声源（E02 另一人）
	SIDE_GLANCE_R,  # 坐姿侧脸看向右侧声源
	NOD,            # 坐姿轻轻点头（E03）
	LOOK_AROUND,    # 站立四处看（主角躲避老师视线）
}

const SEATED_HIP_HEIGHT := 0.47  # 坐姿时髋部世界高度（座面 0.45 + 余量）
const SEATED_POSES: Array[Pose] = [
	Pose.SIT, Pose.HEAD_DOWN, Pose.HEAD_UP, Pose.WRITING,
	Pose.WHISPER_L, Pose.WHISPER_R, Pose.COVER_MOUTH,
	Pose.SIDE_GLANCE_L, Pose.SIDE_GLANCE_R, Pose.NOD,
]

# 基础片段：坐姿腿部折叠。手臂下垂不写死角度——男女骨架手臂静止朝向不同
# （男 T-pose、女 A-pose），固定角在女性模型上会变成手臂张开；
# 改为运行时按各骨架实际骨骼变换自动瞄准（见 _aim_arms）。
const SEATED_LEGS := {
	"UpperLeg.L": Vector3(-90, 0, 0), "UpperLeg.R": Vector3(-90, 0, 0),
	"LowerLeg.L": Vector3(110, 0, 0), "LowerLeg.R": Vector3(110, 0, 0),
}
const POSE_OVERRIDES := {
	Pose.STAND: {},
	Pose.SIT: {},
	Pose.HEAD_DOWN: {"Neck": Vector3(25, 0, 0), "Head": Vector3(15, 0, 0)},
	Pose.HEAD_UP: {"Neck": Vector3(-15, 0, 0), "Head": Vector3(-10, 0, 0)},
	Pose.REBUT: {"UpperArm.R": Vector3(0, 0, 65), "LowerArm.R": Vector3(0, -110, 0)},
	Pose.WRITING: {
		"Torso": Vector3(12, 0, 0),
		"UpperArm.R": Vector3(-25, 0, 10), "LowerArm.R": Vector3(0, -75, 0),
	},
	# 10.22 对话/事件姿态（角度经渲染验证后校准；yaw 符号若反了改这里）
	Pose.STAND_TALK: {
		"Neck": Vector3(2, -16, 0), "Head": Vector3(2, -8, 0),
		"UpperArm.R": Vector3(-15, 0, 22), "LowerArm.R": Vector3(0, 30, 0),
	},
	Pose.WHISPER_L: {"Torso": Vector3(0, -8, 0), "Neck": Vector3(4, -22, 0), "Head": Vector3(2, -10, 0)},
	Pose.WHISPER_R: {"Torso": Vector3(0, 8, 0), "Neck": Vector3(4, 22, 0), "Head": Vector3(2, 10, 0)},
	Pose.COVER_MOUTH: {"Neck": Vector3(18, -8, 0), "Head": Vector3(10, -4, 0)},
	Pose.SIDE_GLANCE_L: {"Neck": Vector3(-2, -28, 0), "Head": Vector3(0, -12, 0)},
	Pose.SIDE_GLANCE_R: {"Neck": Vector3(-2, 28, 0), "Head": Vector3(0, 12, 0)},
	Pose.NOD: {"Torso": Vector3(4, 0, 0), "Neck": Vector3(9, 0, 0), "Head": Vector3(4, 0, 0)},
	Pose.LOOK_AROUND: {"Torso": Vector3(0, -6, 0), "Neck": Vector3(0, -25, 0), "Head": Vector3(0, -10, 0)},
}

@export var pose: Pose = Pose.STAND

var _skeleton: Skeleton3D


func _ready() -> void:
	_skeleton = _find_skeleton(self)
	if _skeleton == null:
		push_error("CharacterPose (%s): Skeleton3D not found under Model." % name)
		return
	_unify_materials(self)
	apply_pose()


## 也可由主开发在运行时调用来切换姿态（当前流程为静态，通常只在 _ready 执行一次）。
func apply_pose() -> void:
	_char_position_y(0.0)
	for i in _skeleton.get_bone_count():
		_skeleton.set_bone_pose_rotation(i, _skeleton.get_bone_rest(i).basis.get_rotation_quaternion())
	var bone_angles: Dictionary = {}
	if SEATED_POSES.has(pose):
		bone_angles.merge(SEATED_LEGS, true)
	bone_angles.merge(POSE_OVERRIDES[pose], true)
	for bone_name in bone_angles:
		var idx := _skeleton.find_bone(bone_name)
		if idx == -1:
			push_warning("CharacterPose (%s): bone missing: %s" % [name, bone_name])
			continue
		var e: Vector3 = bone_angles[bone_name]
		var delta := Quaternion.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
		_skel_set_rot(idx, delta)
	if not POSE_OVERRIDES[pose].has("UpperArm.R"):
		_aim_arm("R")
	if not POSE_OVERRIDES[pose].has("UpperArm.L"):
		_aim_arm("L")
	if pose == Pose.COVER_MOUTH:
		# 掩嘴：手臂下垂后，用两骨 IK 把右手精确放到嘴边（男女骨架通用）
		_ik_hand_to_mouth("R")
	if SEATED_POSES.has(pose):
		await get_tree().process_frame
		await get_tree().process_frame
		var hips := _skeleton.find_bone("Hips")
		var hips_world_y := (_skeleton.global_transform * _skeleton.get_bone_global_pose(hips)).origin.y
		_char_position_y(SEATED_HIP_HEIGHT - hips_world_y)


func _skel_set_rot(idx: int, delta: Quaternion) -> void:
	_skeleton.set_bone_pose_rotation(idx, delta * _skeleton.get_bone_pose_rotation(idx))


## 让一侧手臂自然下垂（略向外 0.15）。
## 做法：取肩→肘当前方向 cur，旋转到目标方向（重力反方向 + 沿 cur 方向少量外展），
## 换算成 UpperArm 骨骼空间的增量四元数。按每具骨架实时计算，男女骨架通用。
func _aim_arm(side: String) -> void:
	var upper_idx := _skeleton.find_bone("UpperArm." + side)
	var lower_idx := _skeleton.find_bone("LowerArm." + side)
	if upper_idx == -1 or lower_idx == -1:
		return
	var gpose := _skeleton.get_bone_global_pose(upper_idx)
	var lower_pos := _skeleton.get_bone_global_pose(lower_idx).origin
	var cur := (lower_pos - gpose.origin).normalized()
	if cur.length_squared() < 0.5:
		return
	# 世界方向转到骨骼空间（骨架节点带 100x 缩放与 90° 旋转，必须走变换）
	var down := (_skeleton.global_transform.basis.orthonormalized().inverse() * Vector3.DOWN).normalized()
	var target := (down + cur * 0.15).normalized()
	var q_world := Quaternion(cur, target)
	var grot := gpose.basis.get_rotation_quaternion()
	var local_delta := grot.inverse() * q_world * grot
	var rest_rot := _skeleton.get_bone_rest(upper_idx).basis.get_rotation_quaternion()
	# 推导：L' = L · (G⁻¹·Q·G)，即 rest 在左、局部增量在右
	_skeleton.set_bone_pose_rotation(upper_idx, rest_rot * local_delta)


## 两骨 IK：把一侧手放到嘴边（E02 掩嘴低笑用）。
## 解析解：先按肩→嘴距离与臂长解出肘位置（肘极向=外下后，姿态自然），
## 再依次把上臂、前臂瞄准方向。全部在骨架空间计算，男女骨架通用。
func _ik_hand_to_mouth(side: String) -> void:
	var upper_idx := _skeleton.find_bone("UpperArm." + side)
	var lower_idx := _skeleton.find_bone("LowerArm." + side)
	var hand_idx := _skeleton.find_bone("Hand." + side)
	var head_idx := _skeleton.find_bone("Head")
	if upper_idx == -1 or lower_idx == -1 or hand_idx == -1 or head_idx == -1:
		_aim_arm(side)
		return
	# 嘴部目标：头骨前方 0.085、略高于原点 0.005（世界方向 → 骨架空间）
	var fwd := -(self.global_transform.basis.z).normalized()
	var up := self.global_transform.basis.y.normalized()
	var head_world := _skeleton.global_transform * _skeleton.get_bone_global_pose(head_idx).origin
	var mouth_world := head_world + fwd * 0.085 + up * 0.005
	var inv := _skeleton.global_transform.affine_inverse()
	var target := inv * mouth_world
	var s_pos := _skeleton.get_bone_global_pose(upper_idx).origin
	var elbow_rest := _skeleton.get_bone_global_pose(lower_idx).origin
	var hand_rest := _skeleton.get_bone_global_pose(hand_idx).origin
	var l1 := s_pos.distance_to(elbow_rest)
	var l2 := elbow_rest.distance_to(hand_rest)
	if l1 < 0.0001 or l2 < 0.0001:
		return
	var st := target - s_pos
	var d := st.length()
	if d < 0.0001:
		return
	# 超出臂长时把目标拉回可达范围（手停在嘴前一点，仍像掩嘴）
	d = clampf(d, absf(l1 - l2) * 1.05 + 0.001, (l1 + l2) * 0.98)
	var st_dir := (target - s_pos).normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var alpha := acos(cos_a)
	# 肘极向：外侧 + 下方 + 略后（在骨架空间表达）
	var fwd_skel := (inv.basis * fwd).normalized()
	var up_skel := (inv.basis * up).normalized()
	var right_skel := (inv.basis * self.global_transform.basis.x).normalized()
	var side_sign := 1.0 if side == "R" else -1.0
	var pole := (right_skel * side_sign * 0.9 - up_skel * 1.3 - fwd_skel * 0.15).normalized()
	var pole_in_plane := pole - st_dir * pole.dot(st_dir)
	if pole_in_plane.length_squared() < 0.000001:
		pole_in_plane = up_skel - st_dir * up_skel.dot(st_dir)
	pole_in_plane = pole_in_plane.normalized()
	var elbow := s_pos + st_dir * (cos(alpha) * l1) + pole_in_plane * (sin(alpha) * l1)
	# 两步顺序瞄准（每步都基于最新全局姿态，等价于解析 IK）
	_aim_bone_toward(upper_idx, lower_idx, (elbow - s_pos).normalized())
	var elbow_now := _skeleton.get_bone_global_pose(lower_idx).origin
	_aim_bone_toward(lower_idx, hand_idx, (target - elbow_now).normalized())


## 把 bone 的全局朝向旋转到 child 落在 target_dir 上（骨架空间方向）。
## 与 _aim_arm 同一套换算，但基准用**当前姿态旋转**（此函数会在手臂已被
## _aim_arm 旋转后再次调用，用 rest 会丢掉已有增量导致方向错乱）：
## L' = L_now · (G⁻¹·Q·G)。
func _aim_bone_toward(bone_idx: int, child_idx: int, target_dir: Vector3) -> void:
	var gpose := _skeleton.get_bone_global_pose(bone_idx)
	var child_pos := _skeleton.get_bone_global_pose(child_idx).origin
	var cur := (child_pos - gpose.origin).normalized()
	if cur.length_squared() < 0.5 or target_dir.length_squared() < 0.5:
		return
	var q := Quaternion(cur, target_dir.normalized())
	var grot := gpose.basis.get_rotation_quaternion()
	var local_delta := grot.inverse() * q * grot
	var current := _skeleton.get_bone_pose_rotation(bone_idx)
	_skeleton.set_bone_pose_rotation(bone_idx, current * local_delta)


## 整体高度只通过移动 Model 子节点实现（根节点保持地面原点不动）。
func _char_position_y(y: float) -> void:
	var model := get_node_or_null("Model") as Node3D
	if model != null:
		model.position.y = y


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


## 运行时把所有材质统一为粗糙、无高光（Compatibility 渲染器友好，与灰盒教室观感一致）。
## 只改内存中的导入材质，不修改 .glb 源文件。
func _unify_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			_style(mi.get_surface_override_material(i))
		if mi.mesh is ArrayMesh:
			var am := mi.mesh as ArrayMesh
			for i in am.get_surface_count():
				_style(am.surface_get_material(i))
	for child in node.get_children():
		_unify_materials(child)


func _style(mat: Material) -> void:
	if mat is BaseMaterial3D:
		var bm := mat as BaseMaterial3D
		bm.roughness = 1.0
		bm.metallic = 0.0
		bm.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		bm.cull_mode = BaseMaterial3D.CULL_BACK
