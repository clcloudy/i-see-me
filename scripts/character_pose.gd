extends Node3D
## 静态姿态人物（D 人物，CHAR-001）。挂在人物场景根节点上：
## 根节点原点在地面、朝向局部 -Z，子节点 Model 为 Quaternius GLB 实例，
## 根节点保留 ViewAnchor 视点锚点（坐姿 1.36、站姿 1.7，与第一周镜头约定一致）。
##
## 姿态为纯静态：只旋转骨骼 + 整体下沉模型，无动画、无口型、无表情。
## 角度表来自 2026-10-17 第一周验证（膝盖角度经批量渲染扫描校准，勿凭感觉改）。
## 注意：该 GLB 的骨架带 100x 缩放，骨骼局部坐标是厘米级——
## 绝对不要往骨骼位置字段写米制数值，会放大 100 倍沉入地板；高度只用 Model 节点整体下沉。

enum Pose { STAND, SIT, HEAD_DOWN, HEAD_UP, REBUT, WRITING }

const SEATED_HIP_HEIGHT := 0.47  # 坐姿时髋部世界高度（座面 0.45 + 余量）
const SEATED_POSES: Array[Pose] = [Pose.SIT, Pose.HEAD_DOWN, Pose.HEAD_UP, Pose.WRITING]

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
