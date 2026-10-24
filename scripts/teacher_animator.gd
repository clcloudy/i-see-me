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
	# 2026-10-24 补全任务五缺失动作 17~21
	CHALK_DOWN,   # 放下粉笔：把粉笔送回讲台粉笔盒，再转回面向学生
	BOOK_PLACE,   # 把课本放到讲台上
	POINT,        # 明确指向某处（点名“点到你”）
	WALK,         # 讲台 ↔ 黑板走路（原地循环腿 + 场景位移，起停带缓冲）
	BOOK_FLIP,    # 讲课中翻课本（两页）
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
## 是否说话（嘴部口型开合）。板书动作背对教室时自动闭嘴。
@export var talking: bool = true
## 口型语速倍率（1 = 正常）。
@export var speech_speed: float = 1.0
## 转身速度（板书动作会转 180°；数值越大转身越快）。
@export var turn_speed: float = 3.5
## 手部目标点平滑速度（越大越跟手，越小过渡越柔）。
@export var target_smoothing: float = 12.0
## 讲台台面锚点（Marker3D）。放课本、放粉笔的目标点；不设时按身体前方推算。
@export var lectern_node: Node3D
## 粉笔盒锚点。不设时取讲台台面右侧。
@export var chalk_box_node: Node3D
## “指向”动作的目标（如主角座位）。不设时指向正前方 0.5 m。
@export var point_target: Node3D

signal action_changed(new_action: int)
signal emotion_changed(new_emotion: int)
signal action_finished(new_action: int)
signal walk_finished

const ACTION_LABELS := {
	Action.LECTURE: "讲课",
	Action.ASK: "提问",
	Action.CALL_ROLL: "点名",
	Action.WRITE_BOARD: "板书",
	Action.CHALK_DOWN: "放下粉笔",
	Action.BOOK_PLACE: "放课本",
	Action.POINT: "指向你",
	Action.WALK: "走路",
	Action.BOOK_FLIP: "翻课本",
}

## 一次性动作时长（秒）。0 表示循环/保持。
const ACTION_DURATION := {
	Action.LECTURE: 0.0,
	Action.ASK: 0.0,
	Action.CALL_ROLL: 0.0,
	Action.WRITE_BOARD: 0.0,
	Action.CHALK_DOWN: 1.60,
	Action.BOOK_PLACE: 2.00,
	Action.POINT: 0.0,
	Action.WALK: 0.0,
	Action.BOOK_FLIP: 2.60,
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

## 面部表情：情绪决定笑意、挑眉/皱眉与眯眼，动作只决定是否开口说话。
## brow_raise 单位是米，brow_tilt 是度（正值 = 眉内侧上挑 = 难过/犹豫）。
const FACE_CONFIG := {
	Emotion.NEUTRAL: {
		"smile": 0.12, "brow_raise": 0.0, "brow_tilt": 0.0, "squint": 0.10, "speak_energy": 1.0,
	},
	Emotion.EXCITED: {
		"smile": 0.45, "brow_raise": 0.0045, "brow_tilt": -6.0, "squint": 0.04, "speak_energy": 1.22,
	},
	Emotion.DOWN: {
		"smile": -0.42, "brow_raise": -0.003, "brow_tilt": 9.0, "squint": 0.34, "speak_energy": 0.72,
	},
	Emotion.PUZZLED: {
		"smile": -0.05, "brow_raise": 0.003, "brow_tilt": -12.0, "squint": 0.16, "speak_energy": 0.9,
		"brow_raise_r": 0.006,
	},
	Emotion.HAPPY: {
		"smile": 0.62, "brow_raise": 0.0035, "brow_tilt": -4.0, "squint": 0.30, "speak_energy": 1.05,
	},
}

## 四指弯曲权重：近节 / 中节 / 远节。这是真人握持时各节的相对弯曲量。
const FINGER_CURL := {
	"Index": [1.0, 1.05, 0.80],
	"Middle": [1.06, 1.05, 0.85],
	"Ring": [1.12, 1.02, 0.85],
	"Pinky": [1.16, 0.98, 0.80],
}
## 各动作的手指弯曲量（0 伸直，1 握拳）。
const GRIP_CURL := {
	Action.LECTURE: 0.18,
	Action.ASK: 0.12,
	Action.CALL_ROLL: 0.12,
	Action.WRITE_BOARD: 0.72,
}
## 握持时各指的分工倍率（在 GRIP_CURL 基础上再乘）。
## 捏粉笔：食指、中指夹住笔身，无名指和小指收进掌心；托册子：四指平均些。
const HOLD_SCALES := {
	"pinch": {"Index": 0.92, "Middle": 1.00, "Ring": 1.16, "Pinky": 1.22, "thumb": 1.45, "thumb_tip": 1.25},
	"hold": {"Index": 0.82, "Middle": 0.88, "Ring": 0.95, "Pinky": 1.00, "thumb": 1.2, "thumb_tip": 1.1},
}
const CHALK_LENGTH := 0.11
const CHALK_RADIUS := 0.0075
const ROSTER_SIZE := Vector3(0.20, 0.28, 0.012)

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
var _face: TeacherFace
var _head_idx: int = -1
var _grip_frame: Dictionary = {}
## 2026-10-24：讲台道具与一次性动作状态
var _textbook: Node3D
var _chalk_box: Node3D
var _page_pivot: Node3D
var _page: MeshInstance3D
var _action_time: float = 0.0
var _action_done: bool = false
var _book_placed: bool = false
var _chalk_dropped: bool = false
var _walking: bool = false
var _walk_from := Vector3.ZERO
var _walk_to := Vector3.ZERO
var _walk_duration: float = 1.0
var _walk_elapsed: float = 0.0
var _walk_end_action: int = Action.LECTURE
var _walk_phase: float = 0.0
var _walk_yaw: float = 0.0


func _ready() -> void:
	_model = get_node_or_null("Model")
	_emo = EMOTION_CONFIG[Emotion.NEUTRAL].duplicate()
	_time = phase_offset
	# 父类负责找骨架、统一材质、便装配色、身高缩放，并调用一次 apply_pose()。
	super._ready()
	_create_props()
	_head_idx = _skeleton.find_bone("Head") if _skeleton != null else -1
	if _skeleton != null and _head_idx != -1:
		_face = TeacherFace.new()
		_face.name = "Face"
		add_child(_face)
		_face.setup(_skeleton, _head_idx, _model)
		apply_pose()
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
	_action_time += delta
	var dur := float(ACTION_DURATION.get(action, 0.0))
	if dur > 0.0 and _action_time >= dur and not _action_done:
		_action_done = true
		action_finished.emit(action)
	if _walking:
		_step_walk(delta)
	var desired_yaw := 0.0
	if action == Action.WRITE_BOARD:
		desired_yaw = 180.0
	elif action == Action.CHALK_DOWN:
		# 从黑板前转身回讲台/学生：后半段转回 0°。
		desired_yaw = 180.0 * (1.0 - smoothstep(0.45, 1.0, _action_u()))
	elif action == Action.WALK:
		desired_yaw = _walk_yaw
	var step := 1.0 - exp(-delta * turn_speed)
	_model_yaw = rad_to_deg(lerp_angle(deg_to_rad(_model_yaw), deg_to_rad(desired_yaw), step))
	apply_pose()


## 切换动作（带平滑过渡）。immediate=true 时转身和手位立即到位。
func set_action(new_action: Action, immediate: bool = false) -> void:
	_action_time = 0.0
	_action_done = false
	if new_action != Action.WALK:
		_walking = false
	if new_action == Action.BOOK_PLACE:
		_book_placed = false
	if new_action == Action.CHALK_DOWN:
		_chalk_dropped = false
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
	set_action((action + 1) % ACTION_LABELS.size())


func cycle_emotion() -> void:
	set_emotion((emotion + 1) % 5)


func get_action_label() -> String:
	return ACTION_LABELS.get(action, "?")


func get_emotion_label() -> String:
	return EMOTION_LABELS.get(emotion, "?")


## 一次性动作进度（0~1）。循环动作返回 0。
func _action_u() -> float:
	var dur := float(ACTION_DURATION.get(action, 0.0))
	if dur <= 0.0001:
		return 0.0
	return clampf(_action_time / dur, 0.0, 1.0)


## 跳到一次性动作的指定秒数并立即重算一帧（无头测试与截图用）。
func seek_action(seconds: float) -> void:
	_action_time = maxf(seconds, 0.0)
	_action_done = false
	apply_pose()


## 截图用：在固定时间点连续重算若干帧，让表情与手位平滑收敛。
func warm_action(seconds: float, steps: int = 6) -> void:
	_action_time = maxf(seconds, 0.0)
	_action_done = false
	for i in steps:
		_frame_delta = 0.05
		apply_pose()


## 讲台 ↔ 黑板走路：带缓起缓停的位移 + 原地走路循环。
## 场景层不再需要匀移，调用本方法即可；到点后自动切到 end_action。
func walk_to(target_world: Vector3, duration: float = 1.8, end_action: Action = Action.LECTURE) -> void:
	var dir := target_world - global_position
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	_walk_from = global_position
	_walk_to = target_world
	_walk_duration = maxf(duration, 0.15)
	_walk_elapsed = 0.0
	_walk_phase = 0.0
	_walk_end_action = end_action
	_walk_yaw = rad_to_deg(atan2(-dir.x, -dir.z))
	_walking = true
	_action_time = 0.0
	_action_done = false
	if action != Action.WALK:
		action = Action.WALK
		action_changed.emit(action)


func _step_walk(delta: float) -> void:
	_walk_elapsed += delta
	var k := smoothstep(0.0, 1.0, clampf(_walk_elapsed / _walk_duration, 0.0, 1.0))
	global_position = _walk_from.lerp(_walk_to, k)
	_walk_phase = _walk_elapsed * TAU * 1.8
	if _walk_elapsed >= _walk_duration:
		_walking = false
		walk_finished.emit()
		set_action(_walk_end_action, true)


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
	if action == Action.WALK and _walking:
		_pose_walk_legs()

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

	# 2026-10-24 新增动作需要双手持物/指向，单独处理，避免打断原四个动作的手势。
	if _special_arms(frame):
		_update_props(frame)
		_update_face()
		return

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
	# 掌心朝向：手先摆到位，再沿手指轴滚手腕把掌面转向动作需要的一侧。
	_align_palm("R", _palm_dir(frame))
	# 记录把住道具前的手掌坐标系：弯曲手指后指根会转，坐标必须用弯曲前的。
	_grip_frame = _hand_frame("R")
	var scales: Dictionary = {}
	if action == Action.WRITE_BOARD:
		scales = HOLD_SCALES["pinch"]
	elif action == Action.CALL_ROLL:
		scales = HOLD_SCALES["hold"]
	_curl_fingers("R", float(GRIP_CURL.get(action, 0.18)), _grip_frame, scales)

	# 左手：疑惑托腮、激昂双手张开（板书时都不做，避免和黑板打架），其余自然下垂。
	if emotion == Emotion.PUZZLED and action != Action.WRITE_BOARD:
		var head_world := _bone_world("Head")
		# 托腮点压在脸颊外侧偏下：太高会挡住眼睛/嘴，看不出表情。
		var chin := head_world + fwd * 0.05 - right * 0.085 - up * 0.115
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
	# 左手始终略弯，直挺挺的五指张开像假人。
	_curl_fingers("L", 0.12 if action != Action.WRITE_BOARD else 0.08,
		_hand_frame("L"))

	_update_props(frame)
	_update_face()


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
		Action.CHALK_DOWN:
			return 14.0
		Action.BOOK_PLACE:
			return 10.0
		Action.POINT:
			return 2.0
		Action.WALK:
			return 3.0
		Action.BOOK_FLIP:
			return 5.0
	return 0.0


func _action_head_pitch() -> float:
	match action:
		Action.WRITE_BOARD:
			return -10.0  # 抬头看黑板
		Action.ASK:
			return 2.0
		Action.BOOK_FLIP, Action.BOOK_PLACE:
			return 10.0  # 低头看手里的书
		Action.POINT:
			return -2.0
	return 0.0


# ---------------------------------------------------------------- 新增动作（2026-10-24）

## 走路腿部：原地循环，位移由 walk_to() 驱动。
func _pose_walk_legs() -> void:
	var swing := sin(_walk_phase)
	_rot("UpperLeg.L", Vector3(-swing * 24.0, 0, 0))
	_rot("UpperLeg.R", Vector3(swing * 24.0, 0, 0))
	_rot("LowerLeg.L", Vector3(maxf(0.0, swing) * 30.0, 0, 0))
	_rot("LowerLeg.R", Vector3(maxf(0.0, -swing) * 30.0, 0, 0))
	_rot("Hips", Vector3(0, 0, swing * 1.5))


## 新增动作的双手。返回 true 表示本帧已完全处理双手（原逻辑跳过）。
func _special_arms(frame: Dictionary) -> bool:
	if action == Action.WALK:
		_walk_arms(frame)
		return true
	if action != Action.CHALK_DOWN and action != Action.BOOK_PLACE \
			and action != Action.BOOK_FLIP and action != Action.POINT:
		return false

	var u := _action_u()
	var fwd: Vector3 = frame["forward"]
	var right: Vector3 = frame["right"]
	var up: Vector3 = frame["up"]
	var sh_r: Vector3 = frame["shoulder_r"]
	var sh_l: Vector3 = frame["shoulder_l"]
	var pole_r := (Vector3.DOWN * 1.1 + right * 0.9 - fwd * 0.15).normalized()
	var pole_l := (Vector3.DOWN * 1.1 - right * 0.9 - fwd * 0.15).normalized()

	if action == Action.POINT:
		var target := _point_target_world(frame)
		var dir := (target - sh_r).normalized()
		_ik_hand_to_world(sh_r + dir * 0.47 + up * 0.01, "R", pole_r)
		_aim_hand("R", dir)
		_align_palm("R", Vector3.DOWN)
		_grip_frame = _hand_frame("R")
		# 只留食指伸直，其余三指与拇指收起：明确的“指向你”。
		_curl_fingers("R", 0.95, _grip_frame, {}, ["Index"])
		_aim_arm("L")
		_aim_hand("L", Vector3.DOWN)
		_curl_fingers("L", 0.12, _hand_frame("L"))
		return true

	if action == Action.CHALK_DOWN:
		var start := sh_r + fwd * 0.25 + right * 0.14 + up * 0.18
		var tray := _chalk_tray()
		var target := start.lerp(tray, smoothstep(0.0, 0.68, u))
		if u > 0.70:
			target = target.lerp(sh_r + Vector3.DOWN * 0.42 + right * 0.08,
				smoothstep(0.70, 1.0, u))
		_ik_hand_to_world(target, "R", pole_r)
		_aim_hand("R", (fwd * 0.4 - up * 0.8).normalized())
		_align_palm("R", Vector3.DOWN)
		_grip_frame = _hand_frame("R")
		_curl_fingers("R", 0.72 if u < 0.70 else 0.14, _grip_frame, HOLD_SCALES["pinch"])
		_chalk_dropped = u >= 0.70
		_aim_arm("L")
		_aim_hand("L", Vector3.DOWN)
		_curl_fingers("L", 0.12, _hand_frame("L"))
		return true

	# BOOK_PLACE / BOOK_FLIP：双手持书
	var place := smoothstep(0.42, 0.88, u) if action == Action.BOOK_PLACE else 0.0
	var center := _book_hold_center(frame)
	center = center.lerp(_lectern_top() + up * 0.02, place)
	if action == Action.BOOK_PLACE and u >= 0.88:
		_book_placed = true
	var release := smoothstep(0.88, 1.0, u) if action == Action.BOOK_PLACE else 0.0
	var half := 0.105
	var r_target := center + right * half + up * 0.012
	var flip := action == Action.BOOK_FLIP
	if flip:
		r_target = _flip_hand_target(center, frame, u)
	var l_target := center - right * half + up * 0.012
	var natural_r := sh_r + Vector3.DOWN * 0.40 + right * 0.07
	var natural_l := sh_l + Vector3.DOWN * 0.40 - right * 0.07

	_ik_hand_to_world(r_target.lerp(natural_r, release), "R", pole_r)
	_aim_hand("R", (fwd * 0.35 - up * 0.65).normalized())
	_align_palm("R", -right)
	_grip_frame = _hand_frame("R")
	if flip:
		_curl_fingers("R", 0.45, _grip_frame, HOLD_SCALES["pinch"])
	else:
		_curl_fingers("R", 0.55 * (1.0 - release) + 0.12, _grip_frame, HOLD_SCALES["hold"])

	_ik_hand_to_world(l_target.lerp(natural_l, release), "L", pole_l)
	_aim_hand("L", (fwd * 0.35 - up * 0.65).normalized())
	_align_palm("L", right)
	_curl_fingers("L", 0.55 * (1.0 - release) + 0.12, _hand_frame("L"), HOLD_SCALES["hold"])

	_place_held_book(center, frame)
	if flip:
		_place_flipping_page(center, frame, u)
	return true


func _walk_arms(frame: Dictionary) -> void:
	var fwd: Vector3 = frame["forward"]
	var right: Vector3 = frame["right"]
	var up: Vector3 = frame["up"]
	var swing := sin(_walk_phase) if _walking else 0.0
	var r_target: Vector3 = frame["shoulder_r"] + Vector3.DOWN * 0.40 + right * 0.07 + fwd * (0.10 * swing)
	var l_target: Vector3 = frame["shoulder_l"] + Vector3.DOWN * 0.40 - right * 0.07 - fwd * (0.10 * swing)
	_ik_hand_to_world(r_target, "R", (Vector3.DOWN + right * 0.9).normalized())
	_aim_hand("R", Vector3.DOWN)
	_align_palm("R", -right)
	_curl_fingers("R", 0.22, _hand_frame("R"))
	_ik_hand_to_world(l_target, "L", (Vector3.DOWN - right * 0.9).normalized())
	_aim_hand("L", Vector3.DOWN)
	_align_palm("L", right)
	_curl_fingers("L", 0.22, _hand_frame("L"))


func _lectern_top() -> Vector3:
	if lectern_node != null:
		return lectern_node.global_position
	return global_position + _body_frame()["forward"] * 0.45 + Vector3.UP * 0.82


func _chalk_tray() -> Vector3:
	if chalk_box_node != null:
		return chalk_box_node.global_position + Vector3.UP * 0.03
	return _lectern_top() + _body_frame()["right"] * 0.18 + Vector3.UP * 0.02


func _point_target_world(frame: Dictionary) -> Vector3:
	if point_target != null:
		return point_target.global_position
	return frame["shoulder_r"] + frame["forward"] * 1.2 - Vector3.UP * 0.15


func _book_hold_center(frame: Dictionary) -> Vector3:
	var sh_mid: Vector3 = ((frame["shoulder_r"] as Vector3) + (frame["shoulder_l"] as Vector3)) * 0.5
	return sh_mid + frame["forward"] * 0.22 - frame["up"] * 0.10


func _place_held_book(center: Vector3, frame: Dictionary) -> void:
	if _textbook == null:
		return
	var basis := Basis(frame["right"], frame["up"], frame["forward"])
	_textbook.global_transform = Transform3D(basis, center)
	_textbook.visible = show_props


## 翻页：两页，每页绕书脊（局部 Z）转 180°。右手跟着页角从右扫到左。
func _flip_hand_target(center: Vector3, frame: Dictionary, u: float) -> Vector3:
	var right: Vector3 = frame["right"]
	var up: Vector3 = frame["up"]
	var fwd: Vector3 = frame["forward"]
	var k := 0.0
	var active := false
	if u >= 0.12 and u < 0.40:
		k = smoothstep(0.12, 0.40, u)
		active = true
	elif u >= 0.55 and u < 0.83:
		k = smoothstep(0.55, 0.83, u)
		active = true
	if not active:
		return center + right * 0.095 + up * 0.02
	var sweep := lerpf(0.095, -0.085, k)
	var lift := 0.02 + 0.075 * sin(PI * k)
	return center + right * sweep + up * lift + fwd * (-0.015 * sin(PI * k))


func _place_flipping_page(center: Vector3, frame: Dictionary, u: float) -> void:
	if _page_pivot == null or _page == null:
		return
	var k := 0.0
	if u >= 0.12 and u < 0.40:
		k = smoothstep(0.12, 0.40, u)
	elif u >= 0.55 and u < 0.83:
		k = smoothstep(0.55, 0.83, u)
	elif u >= 0.40 and u < 0.55:
		k = 1.0
	var visible := u >= 0.12 and u < 0.85
	_page_pivot.visible = show_props and visible
	if not _page_pivot.visible:
		return
	var right: Vector3 = frame["right"]
	var up: Vector3 = frame["up"]
	var fwd: Vector3 = frame["forward"]
	var book_basis := Basis(right, up, fwd)
	var angle := PI * k
	var spine := center - right * 0.10
	_page_pivot.global_transform = Transform3D(
		book_basis * Basis(Vector3.BACK, angle), spine + up * 0.016
	)



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
	# 粉笔：八棱柱，比盒子更像真的粉笔，也方便绕自身轴摆放。
	var chalk_mesh := CylinderMesh.new()
	chalk_mesh.top_radius = CHALK_RADIUS
	chalk_mesh.bottom_radius = CHALK_RADIUS * 0.86
	chalk_mesh.height = CHALK_LENGTH
	chalk_mesh.radial_segments = 8
	chalk_mesh.rings = 1
	_chalk = MeshInstance3D.new()
	_chalk.name = "PropChalk"
	_chalk.mesh = chalk_mesh
	_chalk.material_override = _prop_material(Color(0.93, 0.93, 0.88))
	_chalk.visible = false
	add_child(_chalk)

	var cover_mesh := BoxMesh.new()
	cover_mesh.size = ROSTER_SIZE
	_roster_cover = MeshInstance3D.new()
	_roster_cover.name = "PropRosterCover"
	_roster_cover.mesh = cover_mesh
	_roster_cover.material_override = _prop_material(Color(0.16, 0.22, 0.33))
	_roster_cover.visible = false
	add_child(_roster_cover)

	var paper_mesh := BoxMesh.new()
	paper_mesh.size = Vector3(ROSTER_SIZE.x * 0.93, ROSTER_SIZE.y * 0.95, 0.008)
	_roster_paper = MeshInstance3D.new()
	_roster_paper.name = "PropRosterPaper"
	_roster_paper.mesh = paper_mesh
	_roster_paper.material_override = _prop_material(Color(0.95, 0.94, 0.90))
	_roster_paper.visible = false
	add_child(_roster_paper)

	# 2026-10-24：讲台课本、粉笔盒、翻页用的单页
	_textbook = PropKit.textbook()
	add_child(_textbook)
	_textbook.visible = false
	_chalk_box = PropKit.chalk_box()
	add_child(_chalk_box)
	_chalk_box.visible = false
	_page_pivot = Node3D.new()
	_page_pivot.name = "PropPagePivot"
	add_child(_page_pivot)
	_page = PropKit.page()
	_page.position = Vector3(0.10, 0.0, 0.0)
	_page_pivot.add_child(_page)
	_page_pivot.visible = false


func _prop_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


## 每帧把粉笔/点名册摆进右手；关掉 show_props 时全部隐藏。
## 位置不再用固定偏移，而是取弯曲后真实的拇指/食指关节，所以无论手摆到哪都握得住。
func _update_props(frame: Dictionary) -> void:
	if _chalk == null or _roster_cover == null or _roster_paper == null:
		return
	var u := _action_u()
	var show_chalk := show_props and (action == Action.WRITE_BOARD
		or (action == Action.CHALK_DOWN and u < 0.70))
	var show_roster := show_props and action == Action.CALL_ROLL
	_chalk.visible = show_chalk
	_roster_cover.visible = show_roster
	_roster_paper.visible = show_roster
	if show_chalk and not _grip_frame.is_empty():
		_place_chalk()
	if show_roster and not _grip_frame.is_empty():
		_place_roster()

	# 讲台道具：粉笔盒常驻；课本放下后留在讲台；翻页纸只在翻页动作里出现。
	if _chalk_box != null:
		_chalk_box.visible = show_props
		if _chalk_box.visible:
			var box_pos := _chalk_box_node_pos()
			if chalk_box_node != null:
				_chalk_box.global_transform = chalk_box_node.global_transform
			else:
				_chalk_box.global_transform = Transform3D(Basis.IDENTITY, box_pos)
	if _textbook != null:
		var holding := action == Action.BOOK_PLACE or action == Action.BOOK_FLIP
		if not holding:
			_textbook.visible = show_props and _book_placed
			if _textbook.visible:
				var basis := Basis(frame["right"], Vector3.UP, frame["forward"])
				_textbook.global_transform = Transform3D(basis, _lectern_top() + Vector3.UP * 0.02)
		# 持书时由 _special_arms() 每帧摆放，这里不覆盖。
	if _page_pivot != null:
		_page_pivot.visible = show_props and action == Action.BOOK_FLIP \
			and _action_u() >= 0.12 and _action_u() < 0.85


func _chalk_box_node_pos() -> Vector3:
	if chalk_box_node != null:
		return chalk_box_node.global_position
	return _lectern_top() + _body_frame()["right"] * 0.18 + Vector3.UP * 0.01


## 粉笔：夹在拇指指尖与食指中节之间，笔身沿手指斜向伸出。
## 笔尖指向“手指方向 + 掌心法线”的合方向——正好是写字时粉笔自然探出的角度。
func _place_chalk() -> void:
	var f := _grip_frame
	var palm: Vector3 = f["palm"]
	var finger: Vector3 = f["finger"]
	var index2 := _bone_world("Index2.R")
	var index3 := _bone_world("Index3.R")
	# 粉笔压在食指中节的掌侧凹槽里（拇指再压上去），比取拇指指尖中点稳定：
	# 拇指再弯也够不到食指时，笔也不会浮在虎口外。
	var grip: Vector3 = (index2 + index3) * 0.5 - palm * 0.012
	var axis := (finger * 0.70 + palm * 0.38).normalized()
	# 用世界向上做滚转基准，保证粉笔八棱面的朝向稳定
	var up := Vector3.UP
	var y_axis := (up - axis * up.dot(axis))
	if y_axis.length_squared() < 0.01:
		y_axis = (Vector3.RIGHT - axis * axis.x)
	y_axis = y_axis.normalized()
	var basis := Basis(axis, y_axis, axis.cross(y_axis))
	# 捏点之后露出约 10 cm，笔尾留在虎口里
	var center := grip + axis * 0.055
	_chalk.global_transform = Transform3D(basis, center)


## 点名册：托在掌心上，册面法线朝掌心外侧，长边顺着手指。
## 手指弯曲后正好扣住近端书脊，拇指压在上表面。
func _place_roster() -> void:
	var f := _grip_frame
	var palm: Vector3 = f["palm"]
	var finger: Vector3 = f["finger"]
	var hand: Vector3 = f["hand"]
	var basis := Basis(finger.cross(palm).normalized(), finger, palm)
	# 册子背面要贴在指背高度上，否则手指会穿出封面：
	# 逐节（含指尖）测量离掌平面的高度，取最高点再留 4mm。
	var support := 0.0
	for finger_name in ["Index", "Middle", "Ring", "Pinky"]:
		for seg in [2, 3, 4]:
			support = maxf(support, (_bone_world("%s%d.R" % [finger_name, seg]) - hand).dot(palm))
		support = maxf(support, (_bone_tip_world("%s4.R" % finger_name) - hand).dot(palm))
	var back := support + 0.004
	var center := hand + palm * (back + ROSTER_SIZE.z * 0.5) + finger * 0.09
	_roster_cover.global_transform = Transform3D(basis, center)
	_roster_paper.global_transform = Transform3D(basis, center - palm * (ROSTER_SIZE.z * 0.5 + 0.002))


# ---------------------------------------------------------------- 手掌坐标系与握持

## 手掌坐标系：全部用当前姿态下的骨骼位置实测，不依赖模型 rest 朝向。
## finger 指根→指尖的平均方向；thumb 腕→拇指根；palm 掌心外法线（右手 拇指×手指）。
func _hand_frame(side: String) -> Dictionary:
	var hand := _bone_world("Hand." + side)
	var index := _bone_world("Index2." + side)
	var middle := _bone_world("Middle2." + side)
	var ring := _bone_world("Ring2." + side)
	var pinky := _bone_world("Pinky2." + side)
	var thumb := _bone_world("Thumb2." + side)
	var finger := ((index + middle + ring + pinky) * 0.25 - hand)
	var thumb_dir := (thumb - hand)
	if finger.length_squared() < 1e-8 or thumb_dir.length_squared() < 1e-8:
		return {}
	finger = finger.normalized()
	thumb_dir = thumb_dir.normalized()
	# 右手：掌心朝上、手指前伸时拇指在小指一侧的外侧（旋后），所以掌法线 = 拇指 × 手指；
	# 左手镜像，叉积顺序相反。
	var palm := thumb_dir.cross(finger) if side == "R" else finger.cross(thumb_dir)
	palm = palm.normalized()
	return {
		"hand": hand, "finger": finger, "thumb": thumb_dir, "palm": palm,
		"knuckle": palm.cross(finger).normalized(),
	}


## 掌心转向：手已摆好后，绕手指轴滚腕，把掌面法线转到目标方向。
func _align_palm(side: String, desired_world: Vector3) -> void:
	var f := _hand_frame(side)
	if f.is_empty():
		return
	var axis: Vector3 = f["finger"]
	var cur: Vector3 = f["palm"]
	var proj_cur := cur - axis * cur.dot(axis)
	var proj_des := desired_world - axis * desired_world.dot(axis)
	if proj_cur.length_squared() < 1e-6 or proj_des.length_squared() < 1e-6:
		return
	var angle := rad_to_deg(proj_cur.normalized().signed_angle_to(proj_des.normalized(), axis))
	_roll_hand(side, angle)


## 五指弯曲：每节绕“掌心法线 × 手指方向”的轴旋转，正角度即弯向掌心。
func _curl_fingers(side: String, amount: float, frame: Dictionary, scales: Dictionary = {},
		skip: Array = []) -> void:
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
			_bend_bone_world(
				"%s%d.%s" % [finger_name, seg + 2, side], axis,
				base * float(weights[seg]) * scale
			)
	if skip.has("Thumb"):
		return
	# 拇指对掌：绕“掌心法线 × 拇指方向”弯，指尖压向食指一侧。
	# 捏细长物（粉笔）时拇指要压得更狠，否则笔会浮在虎口外。
	var thumb_axis: Vector3 = (frame["palm"] as Vector3).cross(frame["thumb"] as Vector3)
	_bend_bone_world("Thumb2." + side, thumb_axis, base * 0.55 * float(scales.get("thumb", 1.0)))
	_bend_bone_world("Thumb3." + side, thumb_axis, base * 0.60 * float(scales.get("thumb_tip", 1.0)))


## 绕世界轴旋转某根骨骼（与 _roll_hand 同一套 L' = L·(G⁻¹QG) 换算）。
func _bend_bone_world(bone: String, axis_world: Vector3, angle_deg: float) -> void:
	if absf(angle_deg) < 0.01:
		return
	var idx := _skeleton.find_bone(bone)
	if idx == -1:
		return
	var axis := (_skeleton.global_transform.basis.inverse() * axis_world).normalized()
	var gpose := _skeleton.get_bone_global_pose(idx)
	var grot := gpose.basis.get_rotation_quaternion()
	var local_delta := grot.inverse() * Quaternion(axis, deg_to_rad(angle_deg)) * grot
	_skeleton.set_bone_pose_rotation(idx, _skeleton.get_bone_pose_rotation(idx) * local_delta)


## 末端骨骼的指尖位置。末节骨骼没有子骨，拿不到真实长度：
## 沿它自己的 +Y（骨骼生长方向）延伸上一节长度的 0.8 倍近似远节指骨。
func _bone_tip_world(bone: String) -> Vector3:
	var idx := _skeleton.find_bone(bone)
	if idx == -1:
		return Vector3.ZERO
	var pose := _skeleton.get_bone_global_pose(idx)
	var dir := pose.basis.y.normalized()
	var seg := 0.006
	var parent := _skeleton.get_bone_parent(idx)
	if parent != -1:
		var parent_pose := _skeleton.get_bone_global_pose(parent)
		seg = pose.origin.distance_to(parent_pose.origin) * 0.8
	return _skeleton.global_transform * (pose.origin + dir * seg)


# ---------------------------------------------------------------- 面部

func _update_face() -> void:
	if _face == null or _head_idx == -1:
		return
	var cfg: Dictionary = FACE_CONFIG[emotion]
	var expr := {
		"smile": cfg["smile"],
		"brow_raise": cfg["brow_raise"],
		"brow_tilt": cfg["brow_tilt"],
		"squint": cfg["squint"],
		"speak": talking and action != Action.WRITE_BOARD,
		"speak_energy": cfg["speak_energy"],
		"speak_speed": maxf(0.2, time_scale * speech_speed * float(_emo.get("speed", 1.0))),
	}
	if cfg.has("brow_raise_r"):
		expr["brow_raise_r"] = cfg["brow_raise_r"]
	var head_xf: Transform3D = _skeleton.global_transform * _skeleton.get_bone_global_pose(_head_idx)
	_face.update_face(clampf(_frame_delta, 0.0, 0.05), head_xf, expr)


## 掌心朝向：每个动作给一个世界方向，_align_palm 负责把手腕顺过来。
## 讲课/提问掌心偏上（开放、欢迎发言）；点名朝上托册；板书掌心朝黑板。
func _palm_dir(frame: Dictionary) -> Vector3:
	var fwd: Vector3 = frame["forward"]
	var up: Vector3 = frame["up"]
	match action:
		Action.LECTURE:
			return (up * 0.55 + fwd * 0.75).normalized()
		Action.ASK:
			return (up * 0.85 + fwd * 0.30).normalized()
		Action.CALL_ROLL:
			return (up * 0.80 + fwd * 0.25).normalized()
		Action.WRITE_BOARD:
			return fwd
	return up
