class_name PoseRig
extends RefCounted
## 程序化姿态工具（D 人物，2026-10-24）。
##
## 把 character_pose.gd / teacher_animator.gd 里验证过的骨骼数学集中成一个小工具：
## 重置骨骼、欧拉角叠加、手臂自然下垂、坐姿小腿收正、两骨解析 IK、手掌坐标系、
## 手指弯曲。仅供运行时程序化动画脚本（CharacterAction、TeacherAnimator 扩展）使用，
## 不参与场景树，也不改变任何静态姿态资源。
##
## 约定：模型骨架带 100x 缩放，所有位置都是“骨骼空间”，跨空间换算一律走
## skeleton.global_transform，绝不把米制数值直接写进骨骼坐标。

const SEATED_HIP_HEIGHT := 0.47
const SEATED_LEGS := {
	"UpperLeg.L": Vector3(-90, 0, 0), "UpperLeg.R": Vector3(-90, 0, 0),
	"LowerLeg.L": Vector3(110, 0, 0), "LowerLeg.R": Vector3(110, 0, 0),
}
## 坐姿小腿统一朝向（女模校准值，男女共用）：朝下、略向前。
const SHIN_DIR := Vector3(0.0, 0.386, -0.922)
## 五指各节的弯曲权重（近节 / 中节 / 远节）。
const FINGER_CURL := {
	"Index": [1.0, 1.05, 0.80],
	"Middle": [1.06, 1.05, 0.85],
	"Ring": [1.12, 1.02, 0.85],
	"Pinky": [1.16, 0.98, 0.80],
}

var skeleton: Skeleton3D


func _init(skel: Skeleton3D) -> void:
	skeleton = skel


# ---------------------------------------------------------------- 骨骼基础

func reset_all() -> void:
	for i in skeleton.get_bone_count():
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_rest(i).basis.get_rotation_quaternion())


func has_bone(bone_name: String) -> bool:
	return skeleton.find_bone(bone_name) != -1


## 在当前姿态上叠加欧拉角（度）。
func rot(bone_name: String, euler_deg: Vector3) -> void:
	var idx := skeleton.find_bone(bone_name)
	if idx == -1:
		return
	var delta := Quaternion.from_euler(Vector3(
		deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)
	))
	skeleton.set_bone_pose_rotation(idx, delta * skeleton.get_bone_pose_rotation(idx))


## 绕世界轴旋转某根骨骼：L' = L_now · (G⁻¹·Q·G)。
func bend_bone_world(bone_name: String, axis_world: Vector3, angle_deg: float) -> void:
	if absf(angle_deg) < 0.01:
		return
	var idx := skeleton.find_bone(bone_name)
	if idx == -1:
		return
	var axis := (skeleton.global_transform.basis.inverse() * axis_world).normalized()
	var gpose := skeleton.get_bone_global_pose(idx)
	var grot := gpose.basis.get_rotation_quaternion()
	var local_delta := grot.inverse() * Quaternion(axis, deg_to_rad(angle_deg)) * grot
	skeleton.set_bone_pose_rotation(idx, skeleton.get_bone_pose_rotation(idx) * local_delta)


func bone_world(bone_name: String) -> Vector3:
	var idx := skeleton.find_bone(bone_name)
	if idx == -1:
		return Vector3.ZERO
	return skeleton.global_transform * skeleton.get_bone_global_pose(idx).origin


func bone_tip_world(bone_name: String) -> Vector3:
	var idx := skeleton.find_bone(bone_name)
	if idx == -1:
		return Vector3.ZERO
	var pose := skeleton.get_bone_global_pose(idx)
	var dir := pose.basis.y.normalized()
	var seg := 0.006
	var parent := skeleton.get_bone_parent(idx)
	if parent != -1:
		seg = pose.origin.distance_to(skeleton.get_bone_global_pose(parent).origin) * 0.8
	return skeleton.global_transform * (pose.origin + dir * seg)


func head_world() -> Transform3D:
	var idx := skeleton.find_bone("Head")
	if idx == -1:
		return skeleton.global_transform
	return skeleton.global_transform * skeleton.get_bone_global_pose(idx)


## 髋部世界高度，用于把模型整体落到座面/地面。
func hip_world_y() -> float:
	var idx := skeleton.find_bone("Hips")
	if idx == -1:
		return 0.0
	return (skeleton.global_transform * skeleton.get_bone_global_pose(idx).origin).y


## 身体坐标系（世界）：右 = 左肩→右肩，上 = 世界 +Y，前 = 上 × 右。
## 不用 skeleton.basis.y——该骨架带 100x 缩放与导入旋转，basis.y 不是世界“上”。
func body_frame() -> Dictionary:
	var l := bone_world("UpperArm.L")
	var r := bone_world("UpperArm.R")
	var right := (r - l).normalized()
	var up := Vector3.UP
	var fwd := up.cross(right).normalized()
	if right.length_squared() < 0.5 or fwd.length_squared() < 0.5:
		right = Vector3.RIGHT
		fwd = Vector3.FORWARD
	return {
		"right": right, "up": up, "forward": fwd,
		"shoulder_r": r, "shoulder_l": l,
	}


# ---------------------------------------------------------------- 腿

func apply_seated_legs() -> void:
	for bone_name in SEATED_LEGS:
		rot(bone_name, SEATED_LEGS[bone_name])
	aim_shin("L", 0.0, 0.0, 1.0)
	aim_shin("R", 0.0, 0.0, 1.0)


## 腿从坐姿弯到站立。seated 1 = 完全坐姿，0 = 站立。
## 角度直接插值；小腿收正按 seated 权重混合，避免站立时脚背朝前。
func blend_seated_legs(seated: float, lean: float = 0.0, turn: float = 0.0) -> void:
	var s := clampf(seated, 0.0, 1.0)
	if s <= 0.001:
		return
	rot("UpperLeg.L", Vector3(-90.0 * s, 0, 0))
	rot("UpperLeg.R", Vector3(-90.0 * s, 0, 0))
	rot("LowerLeg.L", Vector3(110.0 * s, 0, 0))
	rot("LowerLeg.R", Vector3(110.0 * s, 0, 0))
	aim_shin("L", lean, turn - 0.6, s)
	aim_shin("R", lean, turn + 0.6, s)


## 坐姿小腿收正。weight < 1 时与当前小腿朝向做球面插值（用于起身过渡）。
func aim_shin(side: String, lean_deg: float = 0.0, turn_deg: float = 0.0, weight: float = 1.0) -> void:
	var lower_idx := skeleton.find_bone("LowerLeg." + side)
	if lower_idx == -1:
		return
	var y := SHIN_DIR.normalized()
	y = y.rotated(Vector3.RIGHT, deg_to_rad(lean_deg)).rotated(Vector3.UP, deg_to_rad(turn_deg)).normalized()
	var z := Vector3.RIGHT.cross(y).normalized()
	var x := y.cross(z).normalized()
	var target := Basis(x, y, z)
	var origin := skeleton.get_bone_global_pose(lower_idx).origin
	if weight >= 0.999:
		skeleton.set_bone_global_pose(lower_idx, Transform3D(target, origin))
		return
	# 骨骼全局 basis 带 100x 缩放，做球面插值前必须正交归一，否则 Quaternion 转换报错。
	var current := skeleton.get_bone_global_pose(lower_idx).basis.orthonormalized()
	skeleton.set_bone_global_pose(lower_idx, Transform3D(
		current.slerp(target, clampf(weight, 0.0, 1.0)).orthonormalized(), origin
	))


## 原地走路腿部循环（教师用）。phase 单位为弧度。
func walk_legs(phase: float, amount_deg: float = 24.0) -> void:
	var swing := sin(phase)
	var lift_l := maxf(0.0, -sin(phase))
	var lift_r := maxf(0.0, sin(phase))
	rot("UpperLeg.L", Vector3(swing * amount_deg, 0, 0))
	rot("UpperLeg.R", Vector3(-swing * amount_deg, 0, 0))
	rot("LowerLeg.L", Vector3(lift_l * amount_deg * 1.6, 0, 0))
	rot("LowerLeg.R", Vector3(lift_r * amount_deg * 1.6, 0, 0))


# ---------------------------------------------------------------- 手臂

## 让一侧手臂自然下垂（略向外 0.15）。
func aim_arm(side: String) -> void:
	var upper_idx := skeleton.find_bone("UpperArm." + side)
	var lower_idx := skeleton.find_bone("LowerArm." + side)
	if upper_idx == -1 or lower_idx == -1:
		return
	var gpose := skeleton.get_bone_global_pose(upper_idx)
	var lower_pos := skeleton.get_bone_global_pose(lower_idx).origin
	var cur := (lower_pos - gpose.origin).normalized()
	if cur.length_squared() < 0.5:
		return
	var down := (skeleton.global_transform.basis.orthonormalized().inverse() * Vector3.DOWN).normalized()
	var target := (down + cur * 0.15).normalized()
	_aim_bone_to_dir(upper_idx, cur, target, true)


## 把 bone 的全局朝向旋转到 child 落在 target_dir 上（骨架空间方向）。
## use_rest=true 时以 rest 为基准重写上臂（用于自然下垂），
## 否则在当前姿态上叠加（IK 第二步必须用当前姿态）。
func _aim_bone_to_dir(bone_idx: int, cur: Vector3, target_dir: Vector3, use_rest: bool) -> void:
	if cur.length_squared() < 0.5 or target_dir.length_squared() < 0.5:
		return
	var gpose := skeleton.get_bone_global_pose(bone_idx)
	var q := Quaternion(cur, target_dir.normalized())
	var grot := gpose.basis.get_rotation_quaternion()
	var local_delta := grot.inverse() * q * grot
	if use_rest:
		var rest_rot := skeleton.get_bone_rest(bone_idx).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(bone_idx, rest_rot * local_delta)
	else:
		skeleton.set_bone_pose_rotation(
			bone_idx, skeleton.get_bone_pose_rotation(bone_idx) * local_delta
		)


## 把 bone 朝向改为让 child 指向 target_dir（当前姿态叠加）。
func aim_bone_toward(bone_idx: int, child_idx: int, target_dir: Vector3) -> void:
	var gpose := skeleton.get_bone_global_pose(bone_idx)
	var child_pos := skeleton.get_bone_global_pose(child_idx).origin
	var cur := (child_pos - gpose.origin).normalized()
	_aim_bone_to_dir(bone_idx, cur, target_dir.normalized(), false)


## 两骨解析 IK：把手骨原点送到世界目标点，肘部朝 pole_world 一侧。
func ik_hand_to_world(target_world: Vector3, side: String, pole_world: Vector3) -> void:
	var upper_idx := skeleton.find_bone("UpperArm." + side)
	var lower_idx := skeleton.find_bone("LowerArm." + side)
	var hand_idx := skeleton.find_bone("Hand." + side)
	if upper_idx == -1 or lower_idx == -1 or hand_idx == -1:
		return
	var inv := skeleton.global_transform.affine_inverse()
	var target := inv * target_world
	var s_pos := skeleton.get_bone_global_pose(upper_idx).origin
	var elbow_rest := skeleton.get_bone_global_pose(lower_idx).origin
	var hand_rest := skeleton.get_bone_global_pose(hand_idx).origin
	var l1 := s_pos.distance_to(elbow_rest)
	var l2 := elbow_rest.distance_to(hand_rest)
	if l1 < 0.0001 or l2 < 0.0001:
		return
	var st := target - s_pos
	var d := st.length()
	if d < 0.0001:
		return
	d = clampf(d, absf(l1 - l2) * 1.05 + 0.001, (l1 + l2) * 0.98)
	var st_dir := (target - s_pos).normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var alpha := acos(cos_a)
	var pole := (inv.basis * pole_world).normalized()
	var pole_in_plane := pole - st_dir * pole.dot(st_dir)
	if pole_in_plane.length_squared() < 0.000001:
		var up_skel := inv.basis * Vector3.UP
		pole_in_plane = up_skel - st_dir * up_skel.dot(st_dir)
	pole_in_plane = pole_in_plane.normalized()
	var elbow := s_pos + st_dir * (cos(alpha) * l1) + pole_in_plane * (sin(alpha) * l1)
	_aim_bone_toward_rest(upper_idx, lower_idx, (elbow - s_pos).normalized())
	var elbow_now := skeleton.get_bone_global_pose(lower_idx).origin
	aim_bone_toward(lower_idx, hand_idx, (target - elbow_now).normalized())


## IK 第一步用 rest 基准：每帧都从 rest 重建，避免累积。
func _aim_bone_toward_rest(bone_idx: int, child_idx: int, target_dir: Vector3) -> void:
	var gpose := skeleton.get_bone_global_pose(bone_idx)
	var child_pos := skeleton.get_bone_global_pose(child_idx).origin
	var cur := (child_pos - gpose.origin).normalized()
	_aim_bone_to_dir(bone_idx, cur, target_dir.normalized(), true)


## 手掌指向世界方向（用中指骨作为手的前方）。
func aim_hand(side: String, dir_world: Vector3) -> void:
	var hand_idx := skeleton.find_bone("Hand." + side)
	var finger_idx := skeleton.find_bone("Middle2." + side)
	if hand_idx == -1 or finger_idx == -1 or dir_world.length_squared() < 0.5:
		return
	var inv_basis := skeleton.global_transform.affine_inverse().basis
	aim_bone_toward(hand_idx, finger_idx, (inv_basis * dir_world).normalized())


## 绕手指轴滚手腕（世界轴），把掌心翻向目标。
func roll_hand(side: String, angle_deg: float) -> void:
	if absf(angle_deg) < 0.01:
		return
	var hand_idx := skeleton.find_bone("Hand." + side)
	var finger_idx := skeleton.find_bone("Middle2." + side)
	if hand_idx == -1 or finger_idx == -1:
		return
	var hand_pos := skeleton.get_bone_global_pose(hand_idx).origin
	var finger_pos := skeleton.get_bone_global_pose(finger_idx).origin
	var axis := (finger_pos - hand_pos).normalized()
	if axis.length_squared() < 0.5:
		return
	var gpose := skeleton.get_bone_global_pose(hand_idx)
	var grot := gpose.basis.get_rotation_quaternion()
	var q := Quaternion(axis, deg_to_rad(angle_deg))
	var local_delta := grot.inverse() * q * grot
	skeleton.set_bone_pose_rotation(
		hand_idx, skeleton.get_bone_pose_rotation(hand_idx) * local_delta
	)


## 手掌坐标系：全部按当前姿态骨骼位置实测。
## finger 指根→指尖平均方向；thumb 腕→拇指根；palm 掌心外法线（右手 拇指×手指）。
func hand_frame(side: String) -> Dictionary:
	var hand := bone_world("Hand." + side)
	var index := bone_world("Index2." + side)
	var middle := bone_world("Middle2." + side)
	var ring := bone_world("Ring2." + side)
	var pinky := bone_world("Pinky2." + side)
	var thumb := bone_world("Thumb2." + side)
	var finger := ((index + middle + ring + pinky) * 0.25 - hand)
	var thumb_dir := (thumb - hand)
	if finger.length_squared() < 1e-8 or thumb_dir.length_squared() < 1e-8:
		return {}
	finger = finger.normalized()
	thumb_dir = thumb_dir.normalized()
	var palm := thumb_dir.cross(finger) if side == "R" else finger.cross(thumb_dir)
	palm = palm.normalized()
	return {
		"hand": hand, "finger": finger, "thumb": thumb_dir, "palm": palm,
		"knuckle": palm.cross(finger).normalized(),
	}


func align_palm(side: String, desired_world: Vector3) -> void:
	var f := hand_frame(side)
	if f.is_empty():
		return
	var axis: Vector3 = f["finger"]
	var cur: Vector3 = f["palm"]
	var proj_cur := cur - axis * cur.dot(axis)
	var proj_des := desired_world - axis * desired_world.dot(axis)
	if proj_cur.length_squared() < 1e-6 or proj_des.length_squared() < 1e-6:
		return
	var angle := rad_to_deg(proj_cur.normalized().signed_angle_to(proj_des.normalized(), axis))
	roll_hand(side, angle)


## 五指弯曲：每节绕“掌心法线 × 手指方向”旋转，正角度弯向掌心。
## skip 可指定伸直的手指（指向手势用）。
func curl_fingers(side: String, amount: float, frame: Dictionary,
		scales: Dictionary = {}, skip: Array = []) -> void:
	if amount <= 0.001 or frame.is_empty():
		return
	var axis: Vector3 = (frame["palm"] as Vector3).cross(frame["finger"] as Vector3)
	var base := amount * 55.0
	for finger_name in FINGER_CURL:
		if skip.has(finger_name):
			continue
		var weights: Array = FINGER_CURL[finger_name]
		var scale := float(scales.get(finger_name, 1.0))
		for seg in 3:
			bend_bone_world(
				"%s%d.%s" % [finger_name, seg + 2, side], axis,
				base * float(weights[seg]) * scale
			)
	if skip.has("Thumb"):
		return
	var thumb_axis: Vector3 = (frame["palm"] as Vector3).cross(frame["thumb"] as Vector3)
	bend_bone_world("Thumb2." + side, thumb_axis, base * 0.55 * float(scales.get("thumb", 1.0)))
	bend_bone_world("Thumb3." + side, thumb_axis, base * 0.60 * float(scales.get("thumb_tip", 1.0)))


## 握持时手指弯曲量（0 伸直，1 握拳）。
const GRIP_PINCH := {"Index": 0.92, "Middle": 1.00, "Ring": 1.16, "Pinky": 1.22, "thumb": 1.45, "thumb_tip": 1.25}
const GRIP_HOLD := {"Index": 0.82, "Middle": 0.88, "Ring": 0.95, "Pinky": 1.00, "thumb": 1.2, "thumb_tip": 1.1}
