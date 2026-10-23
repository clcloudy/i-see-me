class_name TeacherAnimator
extends "res://scripts/character_pose.gd"
## 教师动态动作 + 情绪叠加控制（D 人物，2026-10-23）。
##
## 在静态姿态脚本 character_pose.gd 的基础上，为教师提供“动作 × 情绪”两层动效：
##   动作：讲课 LECTURE / 提问 ASK / 点名 CALL_ROLL / 板书 WRITE_BOARD
##   情绪：普通 NEUTRAL / 激昂 EXCITED / 失落 DOWN / 疑惑 PUZZLED / 开心 HAPPY
## 动作决定身体朝向、右手手势、头部扫描方式；情绪只叠加躯干/头颈幅度与手势节奏，
## 两者可任意组合，切换时自动平滑过渡（情绪参数插值、手部目标点平滑、身体转向插值）。
##
## 实现说明：全部为运行时程序化动画（不依赖 AnimationPlayer 与烘焙轨道），
## 每帧从 rest 重建骨骼姿态，再用两骨 IK 把右手放到动作目标点，因此任意骨架通用。
## 道具（粉笔、点名册）是脚本生成的低多边形 Mesh，不引用外部素材。

enum Action {
	LECTURE,      # 讲课：面向学生，右手在胸前做开合手势，视线缓慢扫视
	ASK,          # 提问：身体略前倾，右手前伸发问
	CALL_ROLL,    # 点名：右手持点名册，头部左右停留式扫视
	WRITE_BOARD,  # 板书：转身面向黑板，右手抬高来回书写，手持粉笔
}

enum Emotion {
	NEUTRAL,  # 普通
	EXCITED,  # 激昂
	DOWN,     # 失落
	PUZZLED,  # 疑惑（左手托腮）
	HAPPY,    # 开心
}

## 当前动作。运行时改这个值不会自动过渡，请优先调用 set_action()。
@export var action: Action = Action.LECTURE
## 当前情绪。运行时改这个值不会自动过渡，请优先调用 set_emotion()。
@export var emotion: Emotion = Emotion.NEUTRAL
## 是否播放循环动效。关闭后停在当前帧，便于截图或做静态摆拍。
@export var playing: bool = true
## 整体节奏倍率（1 = 正常语速；激昂情绪内部还会再乘一次速度系数）。
@export var time_scale: float = 1.0
## 相位偏移（秒），用于同场景多个教师错开动作，避免“整齐划一”。
@export var phase_offset: float = 0.0
## 是否显示粉笔/点名册道具。
@export var show_props: bool = true
## 转身速度（板书动作会转 180°；数值越大转身越快）。
@export var turn_speed: float = 3.5
## 手部目标点平滑速度（越大越跟手，越小过渡越柔）。
@export var target_smoothing: float = 12.0

signal action_changed(new_action: int)
signal emotion_changed(new_emotion: int)

const ACTION_LABELS := {
	Action.LECTURE: "讲课",
	Action.ASK: "提问",
	Action.CALL_ROLL: "点名",
	Action.WRITE_BOARD: "板书",
}

const EMOTION_LABELS := {
	Emotion.NEUTRAL: "普通",
	Emotion.EXCITED: "激昂",
	Emotion.DOWN: "失落",
	Emotion.PUZZLED: "疑惑",
	Emotion.HAPPY: "开心",
}

## 情绪只描述姿态倾向与节奏，不改变动作本身的目标点。
## torso_pitch/neck_pitch/head_pitch：正值低头/前倾，负值抬头/后仰。
## head_roll：歪头（疑惑）；head_yaw：偏头看别处。
## sway：躯干左右轻摆倍率；amp：手势幅度倍率；speed：手势节奏倍率；bounce：整体上下微跳。
const EMOTION_CONFIG := {
	Emotion.NEUTRAL: {
		"torso_pitch": 0.0, "torso_roll": 0.0, "neck_pitch": 0.0,
		"head_pitch": 0.0, "head_roll": 0.0, "head_yaw": 0.0, "head_nod": 0.0,
		"sway": 1.0, "amp": 1.0, "speed": 1.0, "bounce": 0.0, "lift": 0.0,
	},
	Emotion.EXCITED: {
		"torso_pitch": -6.0, "torso_roll": 0.0, "neck_pitch": -6.0,
		"head_pitch": -8.0, "head_roll": 0.0, "head_yaw": 0.0, "head_nod": 4.0,
		"sway": 2.0, "amp": 1.7, "speed": 1.45, "bounce": 0.018, "lift": 0.05,
	},
	Emotion.DOWN: {
		"torso_pitch": 10.0, "torso_roll": 1.5, "neck_pitch": 12.0,
		"head_pitch": 10.0, "head_roll": 3.0, "head_yaw": -4.0, "head_nod": 0.0,
		"sway": 0.45, "amp": 0.55, "speed": 0.70, "bounce": 0.0, "lift": -0.05,
	},
	Emotion.PUZZLED: {
		"torso_pitch": 3.0, "torso_roll": 0.0, "neck_pitch": -2.0,
		"head_pitch": -1.0, "head_roll": 12.0, "head_yaw": -10.0, "head_nod": 0.0,
		"sway": 0.7, "amp": 0.85, "speed": 0.9, "bounce": 0.0, "lift": 0.0,
	},
	Emotion.HAPPY: {
		"torso_pitch": -3.0, "torso_roll": 0.0, "neck_pitch": -4.0,
		"head_pitch": -5.0, "head_roll": 0.0, "head_yaw": 0.0, "head_nod": 2.5,
		"sway": 1.5, "amp": 1.3, "speed": 1.2, "bounce": 0.024, "lift": 0.07,
	},
}

var _emo: Dictionary = {}
var _time: float = 0.0
var _model: Node3D
var _model_yaw: float = 0.0
var _frame_delta: float = 0.0
var _smooth_hand := Vector3.ZERO
var _has_smooth_hand: bool = false
var _chalk: MeshInstance3D
var _roster_cover: MeshInstance3D
var _roster_paper: MeshInstance3D


func _ready() -> void:
	_model = get_node_or_null("Model")
	_emo = EMOTION_CONFIG[Emotion.NEUTRAL].duplicate()
	_time = phase_offset
	# 父类负责找骨架、统一材质、便装配色、身高缩放，并调用一次 apply_pose()。
	super._ready()
	_create_props()
	set_process(true)


func _process(delta: float) -> void:
	if not playing:
		_frame_delta = 0.0
		return
	_frame_delta = delta
	var target_cfg: Dictionary = EMOTION_CONFIG[emotion]
	var blend := 1.0 - exp(-delta * 5.0)
	for key in target_cfg:
		_emo[key] = lerpf(float(_emo[key]), float(target_cfg[key]), blend)
	_time += delta * time_scale * float(_emo["speed"])
	var desired_yaw := 180.0 if action == Action.WRITE_BOARD else 0.0
	var step := 1.0 - exp(-delta * turn_speed)
	_model_yaw = rad_to_deg(lerp_angle(deg_to_rad(_model_yaw), deg_to_rad(desired_yaw), step))
	apply_pose()


## 切换动作（带平滑过渡）。immediate=true 时转身和手位立即到位。
func set_action(new_action: Action, immediate: bool = false) -> void:
	if new_action == action:
		if immediate:
			_snap_turn()
		return
	action = new_action
	if immediate:
		_snap_turn()
	action_changed.emit(action)


## 立即把身体转向目标朝向（跳过转身插值），并按当前动作重算一帧姿态。
func _snap_turn() -> void:
	_model_yaw = 180.0 if action == Action.WRITE_BOARD else 0.0
	_has_smooth_hand = false
	if _model != null:
		_model.rotation_degrees.y = 180.0 + _model_yaw
	apply_pose()


## 切换情绪（参数在约 0.3~0.5 秒内插值到位）。
func set_emotion(new_emotion: Emotion) -> void:
	if new_emotion == emotion:
		return
	emotion = new_emotion
	emotion_changed.emit(emotion)


## 同时设置动作与情绪，流程脚本最常用的入口。
func set_state(new_action: Action, new_emotion: Emotion, immediate: bool = false) -> void:
	set_action(new_action, immediate)
	set_emotion(new_emotion)


## 按顺序循环到下一个动作 / 情绪（演示场景与键盘调试用）。
func cycle_action() -> void:
	set_action((action + 1) % 4)


func cycle_emotion() -> void:
	set_emotion((emotion + 1) % 5)


func get_action_label() -> String:
	return ACTION_LABELS.get(action, "?")


func get_emotion_label() -> String:
	return EMOTION_LABELS.get(emotion, "?")


## 把教师摆到黑板前，便于板书动作对准（可选调用）。
## 黑板场景约定：+Z 面朝向教室。教师站在黑板正面 distance 米处，
## root 局部 +Z 指向黑板（板书时模型会再转 180° 面向它）。
## 只改水平位置与朝向，y 保持当前值（讲台高度由场景决定）。
func align_to_blackboard(board: Node3D, distance: float = 0.47) -> void:
	if board == null:
		return
	var normal := board.global_transform.basis.z.normalized()
	var target := board.global_position + normal * distance
	var z_axis := -normal
	var y_axis := Vector3.UP
	var x_axis := y_axis.cross(z_axis).normalized()
	var basis := Basis(x_axis, y_axis, z_axis).orthonormalized()
	global_transform = Transform3D(basis, Vector3(target.x, global_position.y, target.z))


## 覆盖父类的静态姿态：每帧重建完整的动态姿态。
func apply_pose() -> void:
	if _skeleton == null:
		return
	if _emo.is_empty():
		_emo = EMOTION_CONFIG[Emotion.NEUTRAL].duplicate()
	_reset_all_bones()
	if _model != null:
		_model.rotation_degrees.y = 180.0 + _model_yaw
		_model.position.y = float(_emo["bounce"]) * absf(sin(_time * 2.4))

	var t := _time
	var amp := float(_emo["amp"])
	var sway := sin(t * 1.1) * float(_emo["sway"])
	var breath := sin(t * 1.7) * 0.6
	var action_pitch := _action_torso_pitch()
	var head_yaw := _head_scan(t) + float(_emo["head_yaw"])
	var head_pitch_extra := _action_head_pitch()
	var head_nod := float(_emo["head_nod"]) * sin(t * 2.8)

	# 躯干与头颈：动作给基础倾向，情绪再叠加。先转躯干，肩位随之前移，
	# 后面的手部 IK 才能正确读到肩关节位置。
	_rot("Hips", Vector3(0.0, sway * 1.2, sway * 0.8))
	_rot("Torso", Vector3(
		action_pitch + float(_emo["torso_pitch"]) + breath * 0.4,
		sway * 0.8,
		float(_emo["torso_roll"])
	))
	_rot("Neck", Vector3(
		float(_emo["neck_pitch"]) + action_pitch * 0.20,
		head_yaw * 0.35,
		float(_emo["head_roll"]) * 0.4
	))
	_rot("Head", Vector3(
		float(_emo["head_pitch"]) + head_pitch_extra + head_nod + breath * 0.2,
		head_yaw * 0.65,
		float(_emo["head_roll"]) * 0.6
	))

	var frame := _body_frame()
	var fwd: Vector3 = frame["forward"]
	var right: Vector3 = frame["right"]
	var up: Vector3 = frame["up"]

	# 右手：动作手势 + 手部目标点平滑。
	var hand_target := _hand_target(t, amp, frame)
	if not _has_smooth_hand or _frame_delta <= 0.0:
		_smooth_hand = hand_target
		_has_smooth_hand = true
	else:
		_smooth_hand = _smooth_hand.lerp(hand_target, 1.0 - exp(-_frame_delta * target_smoothing))
	var pole := (Vector3.DOWN * 1.1 + right * 0.9 - fwd * 0.15).normalized()
	_ik_hand_to_world(_smooth_hand, "R", pole)
	_aim_hand("R", _finger_dir(frame))
	if action == Action.ASK:
		# 发问手势：手掌翻向上（沿手指轴滚 90°），避免看起来像“举手示意停止”。
		_roll_hand("R", 90.0)

	# 左手：疑惑托腮、激昂双手张开（板书时都不做，避免和黑板打架），其余自然下垂。
	if emotion == Emotion.PUZZLED and action != Action.WRITE_BOARD:
		var head_world := _bone_world("Head")
		var chin := head_world + fwd * 0.06 - right * 0.055 - up * 0.07
		var left_pole := (Vector3.DOWN + right * -1.0 + fwd * 0.2).normalized()
		_ik_hand_to_world(chin, "L", left_pole)
		_aim_hand("L", (up * 0.8 + fwd * 0.35).normalized())
	elif emotion == Emotion.EXCITED and action != Action.WRITE_BOARD:
		# 激昂：左手也抬起做开放手势，和右手形成“双手陈述”的幅度。
		var sh_l: Vector3 = frame["shoulder_l"]
		var target_l := sh_l \
			+ fwd * (0.22 + 0.02 * sin(t * 1.6)) \
			+ right * -0.10 \
			+ up * (0.02 + 0.05 * sin(t * 1.25))
		var pole_l := (Vector3.DOWN + right * -0.9 - fwd * 0.15).normalized()
		_ik_hand_to_world(target_l, "L", pole_l)
		_aim_hand("L", (fwd * 0.60 + up * 0.60).normalized())
	else:
		_aim_arm("L")
		# 自然下垂时让手指朝下，避免手背翻向前方像在“摊手”。
		_aim_hand("L", Vector3.DOWN)

	_update_props(frame)


func _action_torso_pitch() -> float:
	match action:
		Action.LECTURE:
			return 2.0
		Action.ASK:
			return 7.0
		Action.CALL_ROLL:
			return 3.0
		Action.WRITE_BOARD:
			return 6.0  # 略微前倾，够到黑板
	return 0.0


func _action_head_pitch() -> float:
	match action:
		Action.WRITE_BOARD:
			return -10.0  # 抬头看黑板
		Action.ASK:
			return 2.0
	return 0.0


## 头部扫描：讲课缓慢扫视；点名左右停留；提问基本直视；板书专注黑板。
func _head_scan(t: float) -> float:
	match action:
		Action.LECTURE:
			return 12.0 * sin(t * 0.55)
		Action.ASK:
			return 3.0 * sin(t * 0.9)
		Action.CALL_ROLL:
			var s := sin(t * 0.45)
			# 指数 <1 让两端停留更久，像真的在逐个看人。
			return 28.0 * signf(s) * pow(absf(s), 0.45)
	return 0.0


## 右手目标点（世界坐标）。距离是米制，肩关节到手骨约 0.42 m，
## 超出范围时 IK 会自动把手收在可达边缘，手势仍然成立。
func _hand_target(t: float, amp: float, frame: Dictionary) -> Vector3:
	var sh: Vector3 = frame["shoulder_r"]
	var fwd: Vector3 = frame["forward"]
	var right: Vector3 = frame["right"]
	var up: Vector3 = frame["up"]
	var lift := float(_emo["lift"])
	match action:
		Action.LECTURE:
			return sh \
				+ fwd * (0.28 + 0.03 * sin(t * 1.9)) \
				+ right * (0.07 + 0.09 * sin(t * 1.15) * amp) \
				+ up * (lift + 0.05 * sin(t * 2.3) * amp)
		Action.ASK:
			return sh \
				+ fwd * (0.30 + 0.015 * sin(t * 2.0)) \
				+ right * 0.10 \
				+ up * (lift - 0.09 + 0.02 * sin(t * 2.2) * amp)
		Action.CALL_ROLL:
			return sh \
				+ fwd * 0.27 \
				+ right * 0.12 \
				+ up * (lift - 0.06 + 0.015 * sin(t * 1.6) * amp)
		Action.WRITE_BOARD:
			return sh \
				+ fwd * 0.19 \
				+ right * (0.10 + 0.10 * sin(t * 2.4) * amp) \
				+ up * (lift + 0.30 + 0.045 * sin(t * 4.8) * amp)
	return sh + fwd * 0.3


## 手指朝向：决定手掌“打开”的方向，让手势不像是握拳。
func _finger_dir(frame: Dictionary) -> Vector3:
	var fwd: Vector3 = frame["forward"]
	var up: Vector3 = frame["up"]
	match action:
		Action.LECTURE:
			return (fwd * 0.75 + up * 0.35).normalized()
		Action.ASK:
			return (fwd * 0.70 + up * 0.45).normalized()
		Action.CALL_ROLL:
			return (fwd * 0.70 + up * 0.40).normalized()
		Action.WRITE_BOARD:
			return (fwd * 0.25 + up * 0.95).normalized()
	return up


## 身体坐标系：由左右肩关节实时求“右/上/前”，与模型朝向和转身同步。
func _body_frame() -> Dictionary:
	var l := _bone_world("UpperArm.L")
	var r := _bone_world("UpperArm.R")
	# 骨架节点带 100x 缩放和导入旋转，basis.y 不一定是世界“上”，
	# 身体方向一律用世界坐标计算：右 = 左肩→右肩，前 = 上 × 右。
	var right := (r - l).normalized()
	var up := Vector3.UP
	var fwd := up.cross(right).normalized()
	if right.length_squared() < 0.5 or fwd.length_squared() < 0.5:
		right = Vector3.RIGHT
		fwd = Vector3.FORWARD
	return {
		"right": right,
		"up": up,
		"forward": fwd,
		"shoulder_r": r,
		"shoulder_l": l,
	}


## 两骨 IK：把 hand 骨原点送到世界目标点。与父类 _ik_hand_to_mouth 同一套解析解，
## 极向（肘部朝向）由调用方给出，全部在骨架空间计算，任意骨架通用。
func _ik_hand_to_world(target_world: Vector3, side: String, pole_world: Vector3) -> void:
	var upper_idx := _skeleton.find_bone("UpperArm." + side)
	var lower_idx := _skeleton.find_bone("LowerArm." + side)
	var hand_idx := _skeleton.find_bone("Hand." + side)
	if upper_idx == -1 or lower_idx == -1 or hand_idx == -1:
		return
	var inv := _skeleton.global_transform.affine_inverse()
	var target := inv * target_world
	var s_pos := _skeleton.get_bone_global_pose(upper_idx).origin
	var elbow_rest := _skeleton.get_bone_global_pose(lower_idx).origin
	var hand_rest := _skeleton.get_bone_global_pose(hand_idx).origin
	var l1 := s_pos.distance_to(elbow_rest)
	var l2 := elbow_rest.distance_to(hand_rest)
	if l1 < 0.0001 or l2 < 0.0001:
		return
	var st := target - s_pos
	var d := clampf(st.length(), absf(l1 - l2) * 1.05 + 0.001, (l1 + l2) * 0.98)
	var st_dir := st.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var alpha := acos(cos_a)
	var pole := (inv.basis * pole_world).normalized()
	var pole_in_plane := pole - st_dir * pole.dot(st_dir)
	if pole_in_plane.length_squared() < 0.000001:
		pole_in_plane = (inv.basis * Vector3.UP) - st_dir * (inv.basis * Vector3.UP).dot(st_dir)
	pole_in_plane = pole_in_plane.normalized()
	var elbow := s_pos + st_dir * (cos(alpha) * l1) + pole_in_plane * (sin(alpha) * l1)
	_aim_bone_toward(upper_idx, lower_idx, (elbow - s_pos).normalized())
	var elbow_now := _skeleton.get_bone_global_pose(lower_idx).origin
	_aim_bone_toward(lower_idx, hand_idx, (target - elbow_now).normalized())


## 让手掌指向某个世界方向（用中指骨作为手的前方），用于张开手掌/握粉笔。
func _aim_hand(side: String, dir_world: Vector3) -> void:
	var hand_idx := _skeleton.find_bone("Hand." + side)
	var finger_idx := _skeleton.find_bone("Middle2." + side)
	if hand_idx == -1 or finger_idx == -1 or dir_world.length_squared() < 0.5:
		return
	var inv_basis := _skeleton.global_transform.affine_inverse().basis
	_aim_bone_toward(hand_idx, finger_idx, (inv_basis * dir_world).normalized())


## 绕“手指方向”滚动手腕（世界轴），用于把掌心翻向上/下。
## 与 _aim_bone_toward 同一套四元数基准：L' = L_now · (G⁻¹·Q·G)。
func _roll_hand(side: String, angle_deg: float) -> void:
	if absf(angle_deg) < 0.01:
		return
	var hand_idx := _skeleton.find_bone("Hand." + side)
	var finger_idx := _skeleton.find_bone("Middle2." + side)
	if hand_idx == -1 or finger_idx == -1:
		return
	var hand_pos := _skeleton.get_bone_global_pose(hand_idx).origin
	var finger_pos := _skeleton.get_bone_global_pose(finger_idx).origin
	var axis := (finger_pos - hand_pos).normalized()
	if axis.length_squared() < 0.5:
		return
	var gpose := _skeleton.get_bone_global_pose(hand_idx)
	var grot := gpose.basis.get_rotation_quaternion()
	var q := Quaternion(axis, deg_to_rad(angle_deg))
	var local_delta := grot.inverse() * q * grot
	var current := _skeleton.get_bone_pose_rotation(hand_idx)
	_skeleton.set_bone_pose_rotation(hand_idx, current * local_delta)


func _reset_all_bones() -> void:
	for i in _skeleton.get_bone_count():
		_skeleton.set_bone_pose_rotation(i, _skeleton.get_bone_rest(i).basis.get_rotation_quaternion())


func _rot(bone: String, euler_deg: Vector3) -> void:
	var idx := _skeleton.find_bone(bone)
	if idx == -1:
		return
	var delta := Quaternion.from_euler(Vector3(
		deg_to_rad(euler_deg.x), deg_to_rad(euler_deg.y), deg_to_rad(euler_deg.z)
	))
	_skel_set_rot(idx, delta)


func _bone_world(bone: String) -> Vector3:
	var idx := _skeleton.find_bone(bone)
	if idx == -1:
		return Vector3.ZERO
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(idx).origin


func _create_props() -> void:
	var chalk_mesh := BoxMesh.new()
	chalk_mesh.size = Vector3(0.16, 0.016, 0.016)
	_chalk = MeshInstance3D.new()
	_chalk.name = "PropChalk"
	_chalk.mesh = chalk_mesh
	_chalk.material_override = _prop_material(Color(0.93, 0.93, 0.88))
	_chalk.visible = false
	add_child(_chalk)

	var cover_mesh := BoxMesh.new()
	cover_mesh.size = Vector3(0.24, 0.32, 0.014)
	_roster_cover = MeshInstance3D.new()
	_roster_cover.name = "PropRosterCover"
	_roster_cover.mesh = cover_mesh
	_roster_cover.material_override = _prop_material(Color(0.16, 0.22, 0.33))
	_roster_cover.visible = false
	add_child(_roster_cover)

	var paper_mesh := BoxMesh.new()
	paper_mesh.size = Vector3(0.22, 0.30, 0.004)
	_roster_paper = MeshInstance3D.new()
	_roster_paper.name = "PropRosterPaper"
	_roster_paper.mesh = paper_mesh
	_roster_paper.material_override = _prop_material(Color(0.95, 0.94, 0.90))
	_roster_paper.visible = false
	add_child(_roster_paper)


func _prop_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


## 每帧把粉笔/点名册摆到右手和身体坐标系里；关掉 show_props 时全部隐藏。
func _update_props(frame: Dictionary) -> void:
	if _chalk == null or _roster_cover == null or _roster_paper == null:
		return
	var show_chalk := show_props and action == Action.WRITE_BOARD
	var show_roster := show_props and action == Action.CALL_ROLL
	_chalk.visible = show_chalk
	_roster_cover.visible = show_roster
	_roster_paper.visible = show_roster
	if not (show_chalk or show_roster):
		return
	var hand := _bone_world("Hand.R")
	var fwd: Vector3 = frame["forward"]
	var right: Vector3 = frame["right"]
	var up: Vector3 = frame["up"]
	if show_chalk:
		# 粉笔放在指尖位置，略微向下斜着抵住黑板，像被拇指和食指捏住。
		var axis := (fwd * 0.92 - up * 0.30).normalized()
		var y_axis := (up - axis * up.dot(axis)).normalized()
		var basis := Basis(axis, y_axis, axis.cross(y_axis))
		_chalk.global_transform = Transform3D(
			basis, hand + fwd * 0.09 + up * 0.095 + right * 0.045
		)
	if show_roster:
		# 点名册：封面朝学生，纸面朝教师自己（法线 -forward）；手正好握在上边缘。
		var basis := Basis(right, up, right.cross(up))
		_roster_cover.global_transform = Transform3D(basis, hand + fwd * 0.02 - up * 0.16)
		_roster_paper.global_transform = Transform3D(basis, hand - fwd * 0.005 - up * 0.16)
