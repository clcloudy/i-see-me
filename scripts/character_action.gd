class_name CharacterAction
extends "res://scripts/character_pose.gd"
## 主角与同学的 16 项程序化动作（D 人物，2026-10-24）。
##
## 对应《任务五课堂对话流程与镜头》第六节缺失动作清单 1~16 项。全部为运行时
## 程序化动画：每帧从 rest 重建骨骼，再用两骨 IK 把双手放到目标点，因此男女骨架、
## 不同身高缩放、不同便装配色共用同一套动作。不依赖 AnimationPlayer、不烘焙轨道、
## 不引用外部动画素材。
##
## 动作分三类：
##   主角站立：SIT_TO_STAND / STAND_TO_SIT / STAND_TALK / LOOK_AROUND / STAND_INPUT
##   主角坐姿：HAND_ON_DESK / HAND_RETRACT
##   同学坐姿：LAUGH_SHAKE / NOD_FULL / PICK_PEN / LOOK_BACK / HEAD_SHAKE /
##             DRAW_GRID / LOWER_BOOK / WHISPER_LOOP / QUIET_SETTLE
##
## 用法：把根节点脚本换成本脚本（或在场景里沿用 character_pose 再附加），
## 运行时调用 play_clip(Clip.STAND_TALK, true)。一次性动作结束时发出 clip_finished。
## 口型/表情复用教师方案（scripts/teacher_face.gd），无嘴模型也能说话。

enum Clip {
	NONE,           # 静止（站立）
	SIT_TO_STAND,   # 1 坐→站连贯起身
	STAND_TO_SIT,   # 1 站→坐
	STAND_TALK,     # 3 站立说话手势循环（2 口型/表情见 face）
	LOOK_AROUND,    # 4 四处看循环（2~3 个视线落点）
	HAND_ON_DESK,   # 5 坐姿手扶桌边
	HAND_RETRACT,   # 5 手慢慢收回
	STAND_INPUT,    # 6 输入回答时的站立细节
	LAUGH_SHAKE,    # 7 E02 掩嘴低笑，肩膀轻抖
	NOD_FULL,       # 8 E03 完整点头
	PICK_PEN,       # 9 弯腰捡笔→放回→轻指
	LOOK_BACK,      # 10 回头抬眼看向主角
	HEAD_SHAKE,     # 11 看着黑板轻轻摇头
	DRAW_GRID,      # 12 低头画小方格→擦掉一条线
	LOWER_BOOK,     # 13 手持课本→放低到桌面
	WHISPER_LOOP,   # 14 交头接耳循环
	QUIET_SETTLE,   # 15 交头接耳→忽然安静（转回前方）
	DESK_PEN_IDLE,  # 17 桌面持笔：手放桌上、持笔、面前有书（2026-10-26 追补）
}

## 表情预设：smile / brow_raise（米）/ brow_tilt（度，正=内侧上挑）/ squint。
const EXPRESSIONS := {
	"neutral":  {"smile": 0.10, "brow_raise": 0.0, "brow_tilt": 0.0, "squint": 0.10},
	"confident": {"smile": 0.28, "brow_raise": 0.0015, "brow_tilt": -3.0, "squint": 0.06},
	"nervous":  {"smile": -0.18, "brow_raise": 0.0025, "brow_tilt": 8.0, "squint": 0.24},
	"warm":     {"smile": 0.40, "brow_raise": 0.0020, "brow_tilt": -2.0, "squint": 0.20},
	"amused":   {"smile": 0.34, "brow_raise": 0.0030, "brow_tilt": -4.0, "squint": 0.14},
	"focused":  {"smile": 0.02, "brow_raise": -0.0010, "brow_tilt": 2.0, "squint": 0.10},
	"doubt":    {"smile": -0.08, "brow_raise": 0.0010, "brow_tilt": -9.0, "squint": 0.16},
}

## 每个动作的基础信息。seated = 是否坐在椅子上；duration 秒；loop 循环。
const CLIP_INFO := {
	Clip.NONE:          {"label": "静止站立", "seated": false, "duration": 1.0, "loop": true},
	Clip.SIT_TO_STAND:  {"label": "起身", "seated": true, "duration": 0.80, "loop": false},
	Clip.STAND_TO_SIT:  {"label": "坐下", "seated": false, "duration": 0.85, "loop": false},
	Clip.STAND_TALK:    {"label": "站立说话", "seated": false, "duration": 4.0, "loop": true},
	Clip.LOOK_AROUND:   {"label": "四处看", "seated": false, "duration": 7.4, "loop": true},
	Clip.HAND_ON_DESK:  {"label": "手扶桌边", "seated": true, "duration": 2.0, "loop": true},
	Clip.HAND_RETRACT:  {"label": "手慢慢收回", "seated": true, "duration": 1.40, "loop": false},
	Clip.STAND_INPUT:   {"label": "站着输入", "seated": false, "duration": 10.0, "loop": true},
	Clip.LAUGH_SHAKE:   {"label": "掩嘴低笑", "seated": true, "duration": 1.15, "loop": false},
	Clip.NOD_FULL:      {"label": "轻轻点头", "seated": true, "duration": 1.25, "loop": false},
	Clip.PICK_PEN:      {"label": "弯腰捡笔", "seated": true, "duration": 4.20, "loop": false},
	Clip.LOOK_BACK:     {"label": "回头抬眼", "seated": true, "duration": 1.50, "loop": false},
	Clip.HEAD_SHAKE:    {"label": "看着黑板摇头", "seated": true, "duration": 1.80, "loop": false},
	Clip.DRAW_GRID:     {"label": "画方格擦线", "seated": true, "duration": 5.20, "loop": true},
	Clip.LOWER_BOOK:    {"label": "放低课本", "seated": true, "duration": 2.20, "loop": false},
	Clip.WHISPER_LOOP:  {"label": "交头接耳", "seated": true, "duration": 3.40, "loop": true},
	Clip.QUIET_SETTLE:  {"label": "忽然安静", "seated": true, "duration": 0.55, "loop": false},
	Clip.DESK_PEN_IDLE: {"label": "桌面持笔", "seated": true, "duration": 8.00, "loop": true},
}

## 四处看的视线落点（秒, 头部偏航角）。两端停留，中间慢转。
const LOOK_KEYS := [
	[0.0, 0.0], [0.9, -36.0], [2.1, -36.0], [2.5, -30.0],
	[3.8, 28.0], [5.0, 28.0], [5.4, 22.0], [6.6, 4.0], [7.4, 0.0],
]
## 输入回答时的视线：低头看输入框，偶尔抬眼看老师。
const INPUT_KEYS := [
	[0.0, 0.0], [1.8, 0.0], [2.3, -14.0], [3.3, -14.0], [3.8, 0.0],
	[5.6, 3.0], [6.1, 13.0], [7.0, 13.0], [7.6, 0.0], [10.0, 0.0],
]

@export var clip: Clip = Clip.NONE
## 是否播放（关掉后停在当前帧，便于截图）。
@export var playing: bool = true
## 动作节奏倍率。
@export var speed: float = 1.0
## 相位偏移（秒），同场景多个同学错开动作。
@export var phase_offset: float = 0.0
## 是否生成口型/表情面片。低配或远景可关掉。
@export var face_enabled: bool = true
## 是否显示动作道具（笔、课本、本子、铅笔、橡皮）。
@export var show_props: bool = true
## 是否说话（口型开合）。WHISPER_LOOP 内部还会按说话/停顿分段。
@export var speaking: bool = true
## 基础表情预设，见 EXPRESSIONS。
@export var expression: String = "neutral"
## 交头接耳方向：+1 向右邻座，-1 向左邻座。
@export_range(-1, 1) var whisper_side: int = 1
## 课桌台面高度（米），桌面持笔动作按它摆放书本/笔/手。
## 教室课桌台面 0.775（课桌中心 0.75、厚 0.05）；动作预览的小桌台面 0.74。
@export var desk_height: float = 0.775

signal clip_changed(new_clip: int)
signal clip_finished

var _rig: PoseRig
var _model: Node3D
var _time: float = 0.0
var _frame_delta: float = 0.0
var _finished: bool = false
var _snap: bool = true
var _stand_hip: float = 0.90

var _cur := {}          # 平滑后的躯干/头颈角度与世界手位
var _seated_now: float = 0.0
var _face: TeacherFace
var _head_idx: int = -1
var _face_ready: bool = false

var _pen: Node3D
var _book: Node3D
var _notebook: Node3D
var _pencil: Node3D
var _eraser: Node3D
var _grip_frame := {}


func _ready() -> void:
	_model = get_node_or_null("Model")
	# 父类负责找骨架、统一材质、便装配色、身高缩放；它会调用一次 apply_pose()，
	# 此时 _rig 尚未建立，重写版本会直接返回。
	super._ready()
	if _skeleton == null:
		return
	_rig = PoseRig.new(_skeleton)
	_measure_stand_hip()
	_head_idx = _skeleton.find_bone("Head")
	if face_enabled and _head_idx != -1:
		_face = TeacherFace.new()
		_face.name = "Face"
		add_child(_face)
		_face.setup(_skeleton, _head_idx, _model)
	_create_props()
	_time = phase_offset
	apply_pose()
	set_process(true)


## 站立时髋部世界高度（含身高缩放）。坐/站过渡用它做目标，不写死数值。
func _measure_stand_hip() -> void:
	_rig.reset_all()
	if _model != null:
		_model.position.y = 0.0
	_stand_hip = _rig.hip_world_y()


func _process(delta: float) -> void:
	if not playing:
		_frame_delta = 0.0
		return
	_frame_delta = delta
	var info: Dictionary = CLIP_INFO[clip]
	_time += delta * speed
	var dur := float(info["duration"])
	if not bool(info["loop"]) and _time >= dur and not _finished:
		_finished = true
		clip_finished.emit()
	apply_pose()


# ---------------------------------------------------------------- 对外接口

## 切换动作。restart=true 时即使同名也从头播放。
func play_clip(new_clip: Clip, restart: bool = false) -> void:
	if new_clip == clip and not restart:
		return
	clip = new_clip
	_time = phase_offset
	_finished = false
	_snap = true
	clip_changed.emit(clip)
	if not playing:
		apply_pose()


func set_expression_preset(preset: String) -> void:
	expression = preset if EXPRESSIONS.has(preset) else "neutral"


func get_clip_label() -> String:
	return String(CLIP_INFO[clip]["label"])


func is_seated_clip() -> bool:
	return bool(CLIP_INFO[clip]["seated"])


func get_clip_duration() -> float:
	return float(CLIP_INFO[clip]["duration"])


func is_looping() -> bool:
	return bool(CLIP_INFO[clip]["loop"])


func get_phase() -> float:
	var dur := get_clip_duration()
	if dur <= 0.0001:
		return 0.0
	return fmod(_time, dur) / dur if is_looping() else clampf(_time / dur, 0.0, 1.0)


## 跳到动作内的指定秒数并立即重算一帧（无头测试与截图用，不依赖真实帧率）。
func seek(seconds: float) -> void:
	_time = maxf(seconds, 0.0)
	_snap = true
	_finished = (not is_looping()) and _time >= get_clip_duration()
	apply_pose()


## 截图用：在固定时间点连续重算若干帧，让口型/表情与平滑过渡收敛。
func warm(seconds: float, steps: int = 6) -> void:
	_time = maxf(seconds, 0.0)
	_snap = true
	for i in steps:
		_frame_delta = 0.05
		apply_pose()


## 当前嘴张开比例（测试用）。
func get_mouth_open() -> float:
	return _face.get_mouth_open() if _face != null else 0.0


# ---------------------------------------------------------------- 每帧姿态

func apply_pose() -> void:
	if _rig == null:
		return
	if _model != null:
		_model.position.y = 0.0
	_rig.reset_all()
	var u := get_phase()
	var t := _time
	var base := _base_pose(u, t)
	_seated_now = float(base["seated"])
	# 腿：坐姿/站立之间按 seated 权重插值，小腿收正同步混合。
	_rig.blend_seated_legs(_seated_now, leg_variation * 2.5, leg_variation * 2.0)

	var torso := _smooth_vec("torso", base["torso"], 14.0)
	var neck := _smooth_vec("neck", base["neck"], 14.0)
	var head := _smooth_vec("head", base["head"], 14.0)
	var hips_rot := _smooth_vec("hips", base["hips"], 10.0)
	_rig.rot("Hips", hips_rot)
	_rig.rot("Torso", torso)
	_rig.rot("Neck", neck)
	_rig.rot("Head", head)

	# 先把模型落到目标髋高，再解手部 IK：手的目标点是世界坐标（桌面/地面/嘴边），
	# 若先解 IK 再整体下沉，手会跟着身体一起掉到目标点下方。
	var hip := _smooth_float("hip", float(base["hip"]), 10.0)
	_ground(hip)

	var frame := _rig.body_frame()
	var arms := _arm_specs(u, t, frame)
	_apply_arm("R", arms["r"], frame)
	_apply_arm("L", arms["l"], frame)

	_update_props(u)
	_update_face(u, t)
	_snap = false


func _ground(hip_target: float) -> void:
	if _model == null:
		return
	var hips_y := _rig.hip_world_y()
	_model.position.y = hip_target - hips_y


func _smooth_vec(key: String, target: Vector3, rate: float) -> Vector3:
	if _snap or not _cur.has(key):
		_cur[key] = target
		return target
	var v: Vector3 = (_cur[key] as Vector3).lerp(target, 1.0 - exp(-_frame_delta * rate))
	_cur[key] = v
	return v


func _smooth_float(key: String, target: float, rate: float) -> float:
	if _snap or not _cur.has(key):
		_cur[key] = target
		return target
	var v := lerpf(float(_cur[key]), target, 1.0 - exp(-_frame_delta * rate))
	_cur[key] = v
	return v


# ---------------------------------------------------------------- 基础角度

func _base_pose(u: float, t: float) -> Dictionary:
	var seated := 1.0 if is_seated_clip() else 0.0
	var hip := SEATED_HIP_HEIGHT if seated > 0.5 else _stand_hip
	var hips := Vector3.ZERO
	var torso := Vector3.ZERO
	var neck := Vector3.ZERO
	var head := Vector3.ZERO
	var side := float(whisper_side)

	match clip:
		Clip.SIT_TO_STAND:
			var k := _ease(u)
			seated = 1.0 - k
			hip = lerpf(SEATED_HIP_HEIGHT, _stand_hip, k)
			torso = Vector3(20.0 * sin(PI * k), 0, 1.5 * sin(PI * k))
			neck = Vector3(7.0 * sin(PI * k), -5.0, 0)
			head = Vector3(3.0 * sin(PI * k), -3.0, 0)
		Clip.STAND_TO_SIT:
			var k := _ease(u)
			seated = k
			hip = lerpf(_stand_hip, SEATED_HIP_HEIGHT, k)
			torso = Vector3(14.0 * sin(PI * k), 0, -1.0 * sin(PI * k))
			neck = Vector3(5.0 * sin(PI * k), -3.0, 0)
			head = Vector3(2.0 * sin(PI * k), -2.0, 0)
		Clip.STAND_TALK:
			torso = Vector3(2.0, 1.4 * sin(t * 0.55), 1.2 * sin(t * 0.47))
			neck = Vector3(2.0 + 0.8 * sin(t * 0.9), -14.0 + 2.0 * sin(t * 0.72), 0.5 * sin(t * 0.6))
			head = Vector3(2.0 + 1.4 * sin(t * 1.1), -8.0 + 3.0 * sin(t * 0.86), 1.0)
			hips = Vector3(0, 0.8 * sin(t * 0.5), 0.7 * sin(t * 0.5))
		Clip.LOOK_AROUND:
			var yaw := _keys(u, LOOK_KEYS)
			torso = Vector3(1.0, yaw * 0.22, 0)
			neck = Vector3(1.5, yaw * 0.55 + 2.0 * sin(t * 0.7), 0)
			head = Vector3(1.0 + 1.2 * sin(t * 0.9), yaw * 0.30, 1.5 * sin(t * 0.5))
			hips = Vector3(0, yaw * 0.06, 0.5 * sin(t * 0.5))
		Clip.HAND_ON_DESK:
			torso = Vector3(5.0, -4.0, 2.0)
			neck = Vector3(8.0, -6.0, 0.5)
			head = Vector3(4.0, -3.0, 0.5)
		Clip.HAND_RETRACT:
			var k := _ease(u)
			torso = Vector3(5.0 * (1.0 - k), -4.0 * (1.0 - k), 2.0 * (1.0 - k))
			neck = Vector3(8.0 * (1.0 - k), -6.0 * (1.0 - k), 0.5)
			head = Vector3(4.0 * (1.0 - k), -3.0 * (1.0 - k), 0.5)
		Clip.STAND_INPUT:
			var look := _keys(u, INPUT_KEYS)
			torso = Vector3(3.0 + 1.0 * sin(t * 0.8), 1.0 * sin(t * 0.4), 1.4 * sin(t * 0.45))
			neck = Vector3(8.0 + 3.0 * sin(t * 0.5), look * 0.5, 0.4)
			head = Vector3(6.0 + 5.0 * sin(t * 0.5), look * 0.5, 0.8)
			hips = Vector3(0, 0.6 * sin(t * 0.4), 0.9 * sin(t * 0.45))
		Clip.LAUGH_SHAKE:
			var shake := 2.4 * sin(t * 17.0) * (1.0 - u * 0.75)
			torso = Vector3(9.0, -5.0, 2.5 + shake)
			neck = Vector3(16.0, -7.0, shake * 0.5)
			head = Vector3(9.0 + shake * 0.4, -4.0, shake * 0.6)
			hips = Vector3(0, 0, shake * 0.8)
		Clip.NOD_FULL:
			var nod := 17.0 * sin(PI * u) + 3.0 * sin(2.0 * PI * u)
			torso = Vector3(2.0 + 2.0 * sin(PI * u), 0, 0)
			neck = Vector3(6.0 + nod * 0.55, 0, 0)
			head = Vector3(2.0 + nod * 0.45, 0, 0)
		Clip.PICK_PEN:
			var bend := _keys(u, [[0.0, 0.0], [0.14, 1.0], [0.42, 1.0], [0.55, 0.0], [1.0, 0.0]])
			# 向右侧弯腰（避开课桌），不是把脸埋进桌面。
			torso = Vector3(10.0 * bend + 3.0, 8.0 * bend, -48.0 * bend)
			neck = Vector3(18.0 * bend + 4.0, 8.0 * bend, 12.0 * bend)
			head = Vector3(10.0 * bend + 3.0, 4.0 * bend, 6.0 * bend)
		Clip.LOOK_BACK:
			var env := _ease(clampf(u / 0.25, 0.0, 1.0)) * (1.0 - _ease(clampf((u - 0.72) / 0.28, 0.0, 1.0)))
			torso = Vector3(2.0, 18.0 * env, 0)
			neck = Vector3(-4.0 - 3.0 * env, 30.0 * env, 0)
			head = Vector3(-4.0 * env, 16.0 * env, 0)
		Clip.HEAD_SHAKE:
			var env := _ease(clampf(u / 0.15, 0.0, 1.0)) * (1.0 - _ease(clampf((u - 0.8) / 0.2, 0.0, 1.0)))
			var yaw := 12.0 * sin(u * 2.0 * PI * 2.4) * env
			torso = Vector3(1.0, yaw * 0.16, 0)
			neck = Vector3(-3.0, yaw * 0.55, 0)
			head = Vector3(-2.0, yaw * 0.35, -1.0 * env)
		Clip.DRAW_GRID:
			var writing := 1.0
			if u > 0.66 and u < 0.80:
				writing = 0.35
			torso = Vector3(9.0, 0, 1.0)
			neck = Vector3(10.0 * writing + 4.0, 3.0 * sin(t * 2.1) * writing, 0)
			head = Vector3(6.0 * writing + 3.0, 2.0 * sin(t * 2.1) * writing, 0)
		Clip.LOWER_BOOK:
			var k := _ease(clampf((u - 0.12) / 0.64, 0.0, 1.0))
			torso = Vector3(3.0 + 4.0 * k, 0, 0)
			neck = Vector3(6.0 + 5.0 * k, 0, 0)
			head = Vector3(3.0 + 4.0 * k, 0, 0)
		Clip.WHISPER_LOOP:
			var lean := 0.55 + 0.45 * sin(t * 1.05)
			var nod := 2.5 * sin(t * 3.4)
			torso = Vector3(2.0, 8.0 * side * lean, 1.4 * side)
			neck = Vector3(3.0 + nod * 0.5, 24.0 * side * lean, 0)
			head = Vector3(1.0 + nod, 10.0 * side * lean, 2.0 * side)
		Clip.QUIET_SETTLE:
			var env := 1.0 - _ease(u)
			torso = Vector3(2.0, 8.0 * side * env, 1.4 * side * env)
			neck = Vector3(3.0, 24.0 * side * env, 0)
			head = Vector3(1.0, 10.0 * side * env, 2.0 * side * env)
		Clip.DESK_PEN_IDLE:
			# 坐在课桌前：身体略前倾、低头看桌上的书，右手持笔在书上慢慢写，
			# 左手平放在桌面。幅度刻意压小，满座时不会像在抽搐。
			var breathe := sin(t * 0.8)
			var stir := 0.5 + 0.5 * sin(t * 1.9)
			torso = Vector3(8.0 + 0.6 * breathe, 1.2 * sin(t * 0.35), 1.0)
			neck = Vector3(13.0 + 0.9 * breathe, 2.0 * sin(t * 0.42), 0.0)
			head = Vector3(8.0 + 0.7 * breathe + 1.1 * stir, 1.5 * sin(t * 0.5), 0.8)
		_:
			torso = Vector3(1.0, 1.0 * sin(t * 0.5), 0)
			neck = Vector3(0, 0.8 * sin(t * 0.4), 0)
			head = Vector3(0, 0.5 * sin(t * 0.4), 0)
			hips = Vector3(0, 0, 0.3 * sin(t * 0.4))

	return {
		"seated": seated, "hip": hip, "hips": hips,
		"torso": torso, "neck": neck, "head": head,
	}


# ---------------------------------------------------------------- 手臂目标

func _arm_specs(u: float, t: float, frame: Dictionary) -> Dictionary:
	var natural_r := _natural_spec("R", frame)
	var natural_l := _natural_spec("L", frame)
	var lap_r := _hand_at(_lap_point(frame, "R"), Vector3.DOWN, frame["forward"], 0.14)
	var lap_l := _hand_at(_lap_point(frame, "L"), Vector3.DOWN, frame["forward"], 0.14)
	var desk_r := _hand_at(_desk_point(frame, 0.16, 0.36, 0.755), Vector3.DOWN, frame["forward"], 0.08)
	var side := float(whisper_side)

	match clip:
		Clip.SIT_TO_STAND:
			var k := _ease(u)
			var push := 1.0 - _ease(clampf((u - 0.55) / 0.40, 0.0, 1.0))
			var knee_r: Vector3 = _rig.bone_world("LowerLeg.R") + frame["forward"] * 0.06 + frame["up"] * 0.02
			var knee_l: Vector3 = _rig.bone_world("LowerLeg.L") + frame["forward"] * 0.06 + frame["up"] * 0.02
			var r := _hand_at(knee_r, Vector3.DOWN, frame["forward"], 0.30)
			r = _mix_spec(r, natural_r, 1.0 - push)
			var l := _hand_at(knee_l, Vector3.DOWN, frame["forward"], 0.30)
			l = _mix_spec(l, natural_l, 1.0 - push)
			return {"r": r, "l": l}
		Clip.STAND_TO_SIT:
			var reach := sin(PI * _ease(u))
			var k := _ease(clampf((u - 0.6) / 0.4, 0.0, 1.0))
			var knee_r: Vector3 = _rig.bone_world("LowerLeg.R") + frame["forward"] * 0.05
			var knee_l: Vector3 = _rig.bone_world("LowerLeg.L") + frame["forward"] * 0.05
			var r := _mix_spec(natural_r, _hand_at(knee_r, Vector3.DOWN, frame["forward"], 0.24), reach)
			r = _mix_spec(r, lap_r, k)
			var l := _mix_spec(natural_l, _hand_at(knee_l, Vector3.DOWN, frame["forward"], 0.24), reach)
			l = _mix_spec(l, lap_l, k)
			return {"r": r, "l": l}
		Clip.STAND_TALK:
			var sh: Vector3 = frame["shoulder_r"]
			var r_target: Vector3 = sh \
				+ frame["forward"] * (0.26 + 0.02 * sin(t * 2.2)) \
				+ frame["right"] * (0.17 + 0.05 * sin(t * 1.3)) \
				+ frame["up"] * (-0.17 + 0.04 * sin(t * 1.7))
			# 掌心朝向讲台/听者，手指自然向上张开：一眼能看出是在说话，而不是伸手要东西。
			var r := _hand_at(r_target,
				(frame["forward"] * 0.85 + frame["up"] * 0.35).normalized(),
				(frame["up"] * 0.78 + frame["forward"] * 0.30
					+ frame["right"] * 0.12 * sin(t * 1.3)).normalized(), 0.18)
			var l_target: Vector3 = frame["shoulder_l"] \
				+ frame["forward"] * 0.10 - frame["right"] * 0.06 \
				+ Vector3.DOWN * 0.32 + frame["up"] * 0.03 * sin(t * 1.1)
			var l := _hand_at(l_target, -frame["right"], Vector3.DOWN, 0.18)
			return {"r": r, "l": l}
		Clip.LOOK_AROUND:
			var base_r := _root_point(frame, 0.17, 0.035, 0.94)
			var base_l := _root_point(frame, 0.17, -0.035, 0.93)
			var r := _hand_at(base_r, -frame["right"], (frame["forward"] * 0.6 + frame["up"] * 0.3).normalized(), 0.42)
			var l := _hand_at(base_l, frame["right"], (frame["forward"] * 0.6 + frame["up"] * 0.3).normalized(), 0.46)
			return {"r": r, "l": l}
		Clip.HAND_ON_DESK:
			return {"r": desk_r, "l": lap_l}
		Clip.HAND_RETRACT:
			var k := _ease(u)
			var r := _mix_spec(desk_r, lap_r, k)
			return {"r": r, "l": lap_l}
		Clip.STAND_INPUT:
			# 站在座位旁输入：双手在腰前轻扣，重心缓慢左右移，偶尔抬眼看老师。
			var base_r := _root_point(frame, 0.17, 0.035, 0.95 + 0.005 * sin(t * 0.9))
			var base_l := _root_point(frame, 0.17, -0.035, 0.94 + 0.005 * sin(t * 0.9))
			var r := _hand_at(base_r, -frame["right"],
				(frame["forward"] * 0.6 + frame["up"] * 0.25).normalized(), 0.40)
			var l := _hand_at(base_l, frame["right"],
				(frame["forward"] * 0.6 + frame["up"] * 0.25).normalized(), 0.44)
			return {"r": r, "l": l}
		Clip.LAUGH_SHAKE:
			# 手腕放在嘴右侧，手指横向掠过嘴唇、掌心朝嘴：只遮嘴，不遮眼睛。
			var mouth: Vector3 = _mouth_point(frame) + frame["right"] * 0.03 + frame["up"] * -0.006
			var r := _hand_at(mouth, -frame["forward"],
				(-frame["right"] * 0.92 + frame["up"] * 0.20 + frame["forward"] * 0.10).normalized(), 0.72)
			return {"r": r, "l": lap_l}
		Clip.NOD_FULL:
			return {"r": lap_r, "l": lap_l}
		Clip.PICK_PEN:
			var floor_p := _root_point(frame, 0.46, 0.20, 0.10)
			var desk_p := _desk_point(frame, 0.26, 0.34, 0.745)
			var r := lap_r
			if u < 0.14:
				r = _mix_spec(lap_r, _hand_at(floor_p, Vector3.DOWN, frame["forward"], 0.10), _ease(u / 0.14))
			elif u < 0.42:
				r = _hand_at(floor_p, Vector3.DOWN, frame["forward"], 0.22 if u < 0.20 else 0.42)
			elif u < 0.55:
				r = _mix_spec(_hand_at(floor_p, Vector3.DOWN, frame["forward"], 0.42),
					_hand_at(desk_p, Vector3.DOWN, frame["forward"], 0.42), _ease((u - 0.42) / 0.13))
			elif u < 0.70:
				r = _hand_at(desk_p, Vector3.DOWN, frame["forward"], 0.30)
			elif u < 0.86:
				var point_p: Vector3 = desk_p + frame["up"] * 0.075 + frame["forward"] * 0.04
				r = _hand_at(point_p, Vector3.DOWN, (frame["forward"] * 0.5 - frame["up"] * 0.8).normalized(), 0.95, ["Index"])
			else:
				var point_p: Vector3 = desk_p + frame["up"] * 0.075 + frame["forward"] * 0.04
				r = _mix_spec(_hand_at(point_p, Vector3.DOWN, (frame["forward"] * 0.5 - frame["up"] * 0.8).normalized(), 0.95, ["Index"]),
					lap_r, _ease((u - 0.86) / 0.14))
			var l := lap_l
			if u > 0.14 and u < 0.55:
				l = _hand_at(_lap_point(frame, "L") + frame["forward"] * 0.02, Vector3.DOWN, frame["forward"], 0.22)
			return {"r": r, "l": l}
		Clip.LOOK_BACK:
			return {"r": lap_r, "l": lap_l}
		Clip.HEAD_SHAKE:
			return {"r": lap_r, "l": lap_l}
		Clip.DRAW_GRID:
			var note := _desk_point(frame, 0.04, 0.33, 0.765)
			var drawing := 1.0
			if u > 0.66 and u < 0.80:
				drawing = 0.25
			var wobble: Vector3 = frame["right"] * (0.030 * sin(t * 3.1)) \
				+ frame["forward"] * (0.024 * sin(t * 1.7)) \
				+ frame["up"] * (0.004 + 0.002 * sin(t * 5.3))
			var r_target: Vector3 = note + wobble * drawing + frame["up"] * (0.03 * (1.0 - drawing))
			var r := _hand_at(r_target, Vector3.DOWN, (frame["forward"] * 0.55 - frame["up"] * 0.7).normalized(), 0.32)
			var l := lap_l
			if u > 0.62 and u < 0.84:
				var erase_k := sin(PI * clampf((u - 0.62) / 0.22, 0.0, 1.0))
				var erase_p: Vector3 = note + frame["right"] * (0.02 - 0.04 * erase_k) + frame["forward"] * 0.02
				l = _mix_spec(lap_l, _hand_at(erase_p + frame["up"] * 0.03, Vector3.DOWN, frame["forward"], 0.34), erase_k)
			return {"r": r, "l": l}
		Clip.LOWER_BOOK:
			var hold := _ease(clampf(u / 0.12, 0.0, 1.0))
			var place := _ease(clampf((u - 0.45) / 0.38, 0.0, 1.0))
			var release := _ease(clampf((u - 0.82) / 0.18, 0.0, 1.0))
			var chest: Vector3 = _rig.bone_world("Torso") + frame["forward"] * 0.24 + frame["up"] * 0.16
			var desk := _desk_point(frame, 0.02, 0.34, 0.79)
			var center: Vector3 = chest.lerp(desk, place)
			var half := 0.115
			var r_target: Vector3 = center + frame["right"] * half + frame["up"] * 0.02
			var l_target: Vector3 = center - frame["right"] * half + frame["up"] * 0.02
			var r := _hand_at(r_target, -frame["right"], frame["forward"], 0.55)
			var l := _hand_at(l_target, frame["right"], frame["forward"], 0.55)
			r = _mix_spec(r, lap_r, release)
			l = _mix_spec(l, lap_l, release)
			r = _mix_spec(natural_r, r, hold)
			l = _mix_spec(natural_l, l, hold)
			return {"r": r, "l": l}
		Clip.WHISPER_LOOP:
			var burst := fmod(t, 3.4) < 1.65
			var r := lap_r
			if side > 0 and burst:
				var mouth: Vector3 = _mouth_point(frame) + frame["right"] * 0.03 + frame["up"] * -0.006
				r = _mix_spec(lap_r, _hand_at(mouth, -frame["forward"],
					(-frame["right"] * 0.90 + frame["up"] * 0.25 + frame["forward"] * 0.10).normalized(), 0.52),
					0.65 + 0.35 * sin(t * 2.2))
			elif side < 0 and burst:
				r = _hand_at(_lap_point(frame, "R") + frame["forward"] * 0.06 + frame["up"] * 0.05,
					Vector3.DOWN, frame["forward"], 0.30)
			var l := lap_l
			if side < 0 and burst:
				var mouth_l: Vector3 = _mouth_point(frame) - frame["right"] * 0.03 + frame["up"] * -0.006
				l = _mix_spec(lap_l, _hand_at(mouth_l, -frame["forward"],
					(frame["right"] * 0.90 + frame["up"] * 0.25 + frame["forward"] * 0.10).normalized(), 0.52), 0.9)
			return {"r": r, "l": l}
		Clip.QUIET_SETTLE:
			var env := 1.0 - _ease(u)
			var r := lap_r
			var l := lap_l
			if side > 0:
				var mouth: Vector3 = _mouth_point(frame) + frame["right"] * 0.03 + frame["up"] * -0.006
				r = _mix_spec(lap_r, _hand_at(mouth, -frame["forward"],
					(-frame["right"] * 0.90 + frame["up"] * 0.25 + frame["forward"] * 0.10).normalized(), 0.52), env * 0.6)
			return {"r": r, "l": l}
		Clip.DESK_PEN_IDLE:
			# 桌面高度按教室实际课桌（台面 0.775 m）取点：书在身前 0.62 m，
			# 右手在书上 0.55 m 处持笔写字，左手平放在书左侧的桌面。
			# 指骨沿笔杆方向，笔尖才会落在书面上（见 _place_writing_pen）。
			var stir := 0.5 + 0.5 * sin(t * 1.9)
			var wobble: Vector3 = frame["right"] * (0.010 * sin(t * 2.3) * stir) \
				+ frame["forward"] * (0.008 * cos(t * 1.7) * stir) \
				+ frame["up"] * (0.003 * sin(t * 3.1) * stir)
			var r_target: Vector3 = _desk_point(frame, 0.06, 0.50, desk_height + 0.080) + wobble
			var r := _hand_at(r_target, Vector3.DOWN,
				(frame["forward"] * 0.98 - frame["up"] * 0.20).normalized(), 0.35)
			var l_target: Vector3 = _desk_point(frame, -0.18, 0.52, desk_height + 0.020)
			var l := _hand_at(l_target, Vector3.DOWN,
				(frame["forward"] * 0.90 - frame["up"] * 0.35).normalized(), 0.12)
			return {"r": r, "l": l}
		_:
			return {"r": natural_r, "l": natural_l}


func _natural_spec(side: String, frame: Dictionary) -> Dictionary:
	var side_sign := 1.0 if side == "R" else -1.0
	var sh: Vector3 = frame["shoulder_r"] if side == "R" else frame["shoulder_l"]
	var target: Vector3 = sh + Vector3.DOWN * 0.40 + frame["right"] * side_sign * 0.07 + frame["forward"] * 0.01
	return _hand_at(target, -frame["right"] * side_sign, Vector3.DOWN, 0.14)


func _hand_at(target: Vector3, palm: Vector3, finger: Vector3, curl: float,
		skip: Array = []) -> Dictionary:
	return {"target": target, "palm": palm, "finger": finger, "curl": curl, "skip": skip}


func _mix_spec(a: Dictionary, b: Dictionary, k: float) -> Dictionary:
	var f := clampf(k, 0.0, 1.0)
	return {
		"target": (a["target"] as Vector3).lerp(b["target"], f),
		"palm": (a["palm"] as Vector3).lerp(b["palm"], f).normalized(),
		"finger": (a["finger"] as Vector3).lerp(b["finger"], f).normalized(),
		"curl": lerpf(float(a["curl"]), float(b["curl"]), f),
		"skip": b["skip"] if f > 0.5 else a["skip"],
	}


func _apply_arm(side: String, spec: Dictionary, frame: Dictionary) -> void:
	var smoothed_key := "hand_" + side.to_lower()
	var target: Vector3 = _smooth_vec(smoothed_key, spec["target"], 16.0)
	var side_sign := 1.0 if side == "R" else -1.0
	var pole: Vector3 = (Vector3.DOWN * 1.15 + frame["right"] * 0.9 * side_sign - frame["forward"] * 0.12).normalized()
	_rig.ik_hand_to_world(target, side, pole)
	_rig.aim_hand(side, spec["finger"])
	_rig.align_palm(side, spec["palm"])
	_grip_frame[side] = _rig.hand_frame(side)
	if spec["skip"].is_empty():
		_rig.curl_fingers(side, float(spec["curl"]), _grip_frame[side])
	else:
		_rig.curl_fingers(side, float(spec["curl"]), _grip_frame[side], {}, spec["skip"])


# ---------------------------------------------------------------- 世界点位

func _root_point(frame: Dictionary, fwd: float, right: float, y: float) -> Vector3:
	var p: Vector3 = global_position + frame["forward"] * fwd + frame["right"] * right
	p.y = global_position.y + y
	return p


func _lap_point(frame: Dictionary, side: String) -> Vector3:
	var side_sign := 1.0 if side == "R" else -1.0
	return _root_point(frame, 0.18, 0.11 * side_sign, 0.60)


func _desk_point(frame: Dictionary, right_off: float, fwd_off: float, y: float) -> Vector3:
	return _root_point(frame, fwd_off, right_off, y)


func _mouth_point(frame: Dictionary) -> Vector3:
	# 手骨原点是手腕，不是掌心。用实测嘴面片的位置再往前 4.5 cm，
	# 手掌正好盖在嘴前，不会插进头里；首帧面片尚未摆放时退回头部骨近似。
	if _face != null and _face_ready:
		return _face.get_mouth_world() + frame["forward"] * 0.045 - frame["up"] * 0.016
	var head_xf := _rig.head_world()
	return head_xf.origin + frame["forward"] * 0.145 - frame["up"] * 0.064


# ---------------------------------------------------------------- 道具

func _create_props() -> void:
	_pen = PropKit.pen()
	add_child(_pen)
	_book = PropKit.textbook()
	add_child(_book)
	_notebook = PropKit.notebook()
	add_child(_notebook)
	_pencil = PropKit.pencil()
	add_child(_pencil)
	_eraser = PropKit.eraser()
	add_child(_eraser)
	for p in [_pen, _book, _notebook, _pencil, _eraser]:
		p.visible = false


func _update_props(u: float) -> void:
	var show := show_props
	var pen_visible := show and (clip == Clip.PICK_PEN or clip == Clip.DESK_PEN_IDLE)
	var book_visible := show and (clip == Clip.LOWER_BOOK or clip == Clip.DESK_PEN_IDLE)
	var note_visible := show and clip == Clip.DRAW_GRID
	_pen.visible = pen_visible
	_book.visible = book_visible
	_notebook.visible = note_visible
	_pencil.visible = note_visible
	_eraser.visible = note_visible
	if not show:
		return
	var frame := _rig.body_frame()
	if pen_visible:
		if clip == Clip.DESK_PEN_IDLE:
			_place_writing_pen(frame)
		else:
			_place_pick_pen(u, frame)
	if book_visible:
		if clip == Clip.DESK_PEN_IDLE:
			_place_desk_book(frame)
		else:
			_place_lowered_book(u, frame)
	if note_visible:
		_place_drawing_props(u, frame)


## 桌面持笔：摊开的课本平放在课桌前（台面 0.775 m，书心在身前 0.62 m）。
func _place_desk_book(frame: Dictionary) -> void:
	var book := _desk_point(frame, 0.0, 0.62, desk_height + 0.014)
	var basis := Basis(frame["right"], frame["up"], frame["forward"])
	_book.global_transform = Transform3D(basis, book)


## 写字时的笔：笔杆从指间出发、笔尖（局部 +X 端）落在书面上。
## 通用握持（_place_in_hand）按“手指 + 掌心”合成笔杆方向，写字俯角下笔尖会
## 插进书本与桌面 16 cm；这里把笔根放在指间握点，笔杆方向直接指向书面落点，
## 笔尖高度由目标点保证，手抬高或晃动时笔尖始终贴纸。
func _place_writing_pen(frame: Dictionary) -> void:
	var grip: Vector3 = (_rig.bone_world("Index2.R") + _rig.bone_world("Index3.R")) * 0.5
	var tip_target: Vector3 = _desk_point(frame, 0.06, 0.68, desk_height + 0.029)
	var delta: Vector3 = tip_target - grip
	var axis: Vector3 = (frame["forward"] * 0.82 - frame["up"] * 0.57).normalized()
	if delta.length() > 0.001:
		axis = delta.normalized()
	var y_axis: Vector3 = frame["up"] - axis * frame["up"].dot(axis)
	if y_axis.length_squared() < 0.01:
		y_axis = frame["right"]
	y_axis = y_axis.normalized()
	var z_axis: Vector3 = axis.cross(y_axis).normalized()
	_pen.global_transform = Transform3D(Basis(axis, y_axis, z_axis), grip - axis * 0.010)


func _place_pick_pen(u: float, frame: Dictionary) -> void:
	var floor_p := _root_point(frame, 0.46, 0.20, 0.012)
	var desk_p := _desk_point(frame, 0.26, 0.34, 0.760)
	var axis: Vector3 = frame["forward"]
	var y_axis := Vector3.UP
	var basis := Basis(axis, y_axis, axis.cross(y_axis).normalized())
	if u < 0.18:
		_pen.global_transform = Transform3D(basis, floor_p)
	elif u < 0.70:
		_place_in_hand(_pen, "R", 0.035)
	else:
		_pen.global_transform = Transform3D(basis, desk_p)


func _place_lowered_book(u: float, frame: Dictionary) -> void:
	var place := _ease(clampf((u - 0.45) / 0.38, 0.0, 1.0))
	var chest: Vector3 = _rig.bone_world("Torso") + frame["forward"] * 0.24 + frame["up"] * 0.16
	var desk := _desk_point(frame, 0.02, 0.34, 0.795)
	var center: Vector3 = chest.lerp(desk, place)
	var basis := Basis(frame["right"], frame["up"], frame["forward"])
	_book.global_transform = Transform3D(basis, center)


func _place_drawing_props(u: float, frame: Dictionary) -> void:
	var note := _desk_point(frame, 0.04, 0.33, 0.760)
	var basis := Basis(frame["right"], frame["up"], frame["forward"])
	_notebook.global_transform = Transform3D(basis, note)
	_place_in_hand(_pencil, "R", 0.035)
	# 橡皮：擦线时在左手，其余时间放在本子右上角
	if u > 0.60 and u < 0.86:
		_place_in_hand(_eraser, "L", 0.006)
		_eraser.visible = true
	else:
		_eraser.visible = true
		_eraser.global_transform = Transform3D(basis, note + frame["right"] * 0.085 + frame["forward"] * 0.10 + frame["up"] * 0.014)


## 把长条道具（笔/铅笔）夹进手里：压在食指中节掌侧，笔身沿手指方向探出。
func _place_in_hand(prop: Node3D, side: String, offset: float) -> void:
	var f: Dictionary = _grip_frame.get(side, {})
	if f.is_empty():
		prop.visible = false
		return
	prop.visible = true
	var palm: Vector3 = f["palm"]
	var finger: Vector3 = f["finger"]
	var index2 := _rig.bone_world("Index2." + side)
	var index3 := _rig.bone_world("Index3." + side)
	var grip := (index2 + index3) * 0.5 - palm * 0.010
	var axis: Vector3 = (finger * 0.72 + palm * 0.35).normalized()
	var y_axis := palm - axis * palm.dot(axis)
	if y_axis.length_squared() < 0.01:
		y_axis = Vector3.UP - axis * axis.y
	y_axis = y_axis.normalized()
	var z_axis := axis.cross(y_axis).normalized()
	prop.global_transform = Transform3D(Basis(axis, y_axis, z_axis), grip + axis * offset)


# ---------------------------------------------------------------- 面部

func _update_face(u: float, t: float) -> void:
	if _face == null:
		return
	var preset: Dictionary = EXPRESSIONS.get(expression, EXPRESSIONS["neutral"])
	var expr := {
		"smile": float(preset["smile"]),
		"brow_raise": float(preset["brow_raise"]),
		"brow_tilt": float(preset["brow_tilt"]),
		"squint": float(preset["squint"]),
		"speak": _is_speaking(t),
		"speak_energy": 1.0,
		"speak_speed": maxf(0.2, speed),
	}
	match clip:
		Clip.LAUGH_SHAKE:
			expr["smile"] = 0.34
			expr["squint"] = 0.30 + 0.10 * sin(t * 17.0)
		Clip.NOD_FULL:
			expr["smile"] = 0.18
		Clip.HEAD_SHAKE:
			expr["smile"] = -0.06
			expr["brow_tilt"] = -9.0
		Clip.PICK_PEN:
			expr["squint"] = 0.14
		Clip.LOOK_BACK:
			expr["brow_raise"] = 0.002
		Clip.DRAW_GRID:
			expr["squint"] = 0.18
			expr["smile"] = 0.0
		Clip.WHISPER_LOOP, Clip.QUIET_SETTLE:
			expr["smile"] = 0.20
		Clip.DESK_PEN_IDLE:
			expr["smile"] = 0.0
			expr["squint"] = 0.16
	var head_xf := _rig.head_world()
	_face.update_face(clampf(_frame_delta, 0.0, 0.05), head_xf, expr)
	_face_ready = true


func _is_speaking(t: float) -> bool:
	match clip:
		Clip.STAND_TALK, Clip.STAND_INPUT:
			return speaking
		Clip.WHISPER_LOOP:
			return speaking and fmod(t, 3.4) < 1.65
		Clip.NOD_FULL, Clip.LAUGH_SHAKE:
			return false
		_:
			return false


# ---------------------------------------------------------------- 小工具

func _ease(x: float) -> float:
	return smoothstep(0.0, 1.0, clampf(x, 0.0, 1.0))


## 关键帧插值：keys = [[time, value], ...]，段内用 smoothstep 缓动。
func _keys(u: float, keys: Array) -> float:
	if keys.is_empty():
		return 0.0
	var total := float(keys[keys.size() - 1][0])
	if total <= 0.0001:
		return float(keys[0][1])
	var time := u * total
	for i in range(keys.size() - 1):
		var t0 := float(keys[i][0])
		var t1 := float(keys[i + 1][0])
		if time <= t1 or i == keys.size() - 2:
			if t1 - t0 <= 0.0001:
				return float(keys[i + 1][1])
			var k := smoothstep(t0, t1, clampf(time, t0, t1))
			return lerpf(float(keys[i][1]), float(keys[i + 1][1]), k)
	return float(keys[keys.size() - 1][1])
