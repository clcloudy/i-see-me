class_name DialogueFlow
extends Node3D

## 课堂对话流程与时间轴控制器。
##
## 时序依据：仓库根目录《流程控制(veryimportant).md》的 0–11 步（2026-10-25 实现）。
## 阶段：intro → l1（第 0–7 步） → choice（第 8 步，唯一分支点）
##       → answer / struggle / avoid（第 8 步的分支演出） → ending（第 9–11 步） → l2 → complete。
##
## 数据全部来自 content/classroom_dialogue.json：
## - beats：L1 节拍，`step` 标记对应的流程步号；每拍可带 teacher / teacher_move / protagonist /
##   protagonist_clip / camera / free_look / cues / events / segments；
## - branch_avoid：躲避视线的第 8 步演出；
## - ending：第 9–11 步，带 `only_branch` 的节拍只在对应分支播放（E03 只在清晰回应后）；
## - segments：字幕分段（speaker + text + seconds + 可选 voice 配音 id）；
## - events：事件按时间戳触发（姿态/动作、台词、道具、词条）；可带 gaze，玩家转到该方向即提前触发；
## - voice / sfx：配音与音效清单（id → 文件名，root 统一前缀）。台词 id 未登记时报警并静默跳过，
##   文件缺失时只按预留时长走，不阻塞流程。
##
## 配音接口：节拍时长取 max(hold, 字幕结束, 音频长度 + padding)。文件就位即自动播放，无需改脚本。
##
## 时间基准：所有定时器以 time_scale 缩放（无头检查用）；定时器不随暂停推进
## （create_timer 的 process_always=false），配合 _generation 代守卫，跳过/重开立即使旧回调失效。

signal stage_changed(stage_id: StringName)

## 3D 场景内 UI 接入信号（不改动流程时序）：
##  - event_observed：一条「可被观察到的事件」发生，携带事件 id / 文案 / 世界坐标。
##  - sound_emitted：某个位置发出了动静（台词、走位、音效），携带世界坐标与强度。
signal event_observed(event_id: StringName, label: String, world_position: Vector3)
signal sound_emitted(world_position: Vector3, intensity: float)

const CHARACTER_POSE_PATH := "res://scripts/character_pose.gd"
const DEFAULT_CONTENT_PATH := "res://content/classroom_dialogue.json"
const REQUIRED_POSES := [
	"SIT", "SIDE_GLANCE_L", "SIDE_GLANCE_R", "COVER_MOUTH",
	"NOD", "WHISPER_L", "WHISPER_R", "HEAD_UP", "HEAD_DOWN",
	"READ", "PICK_UP", "LOOK_BACK_L", "LOOK_BACK_R", "LEAN_BACK",
]
const ACTION_IDS := {
	"LECTURE": TeacherAnimator.Action.LECTURE,
	"ASK": TeacherAnimator.Action.ASK,
	"CALL_ROLL": TeacherAnimator.Action.CALL_ROLL,
	"WRITE_BOARD": TeacherAnimator.Action.WRITE_BOARD,
	"CHALK_DOWN": TeacherAnimator.Action.CHALK_DOWN,
	"BOOK_PLACE": TeacherAnimator.Action.BOOK_PLACE,
	"POINT": TeacherAnimator.Action.POINT,
	"BOOK_FLIP": TeacherAnimator.Action.BOOK_FLIP,
}
## 程序化动作名 → CharacterAction.Clip。人物场景换成 CharacterAction 后自动生效，
## 仍是静态姿态场景时静默跳过，由 events.poses 的静态姿兜底。
const CLIP_IDS := {
	"NONE": CharacterAction.Clip.NONE,
	"SIT_TO_STAND": CharacterAction.Clip.SIT_TO_STAND,
	"STAND_TO_SIT": CharacterAction.Clip.STAND_TO_SIT,
	"STAND_TALK": CharacterAction.Clip.STAND_TALK,
	"LOOK_AROUND": CharacterAction.Clip.LOOK_AROUND,
	"HAND_ON_DESK": CharacterAction.Clip.HAND_ON_DESK,
	"HAND_RETRACT": CharacterAction.Clip.HAND_RETRACT,
	"STAND_INPUT": CharacterAction.Clip.STAND_INPUT,
	"LAUGH_SHAKE": CharacterAction.Clip.LAUGH_SHAKE,
	"NOD_FULL": CharacterAction.Clip.NOD_FULL,
	"PICK_PEN": CharacterAction.Clip.PICK_PEN,
	"LOOK_BACK": CharacterAction.Clip.LOOK_BACK,
	"HEAD_SHAKE": CharacterAction.Clip.HEAD_SHAKE,
	"DRAW_GRID": CharacterAction.Clip.DRAW_GRID,
	"LOWER_BOOK": CharacterAction.Clip.LOWER_BOOK,
	"WHISPER_LOOP": CharacterAction.Clip.WHISPER_LOOP,
	"QUIET_SETTLE": CharacterAction.Clip.QUIET_SETTLE,
}
const EMOTION_IDS := {
	"NEUTRAL": TeacherAnimator.Emotion.NEUTRAL,
	"EXCITED": TeacherAnimator.Emotion.EXCITED,
	"DOWN": TeacherAnimator.Emotion.DOWN,
	"PUZZLED": TeacherAnimator.Emotion.PUZZLED,
	"HAPPY": TeacherAnimator.Emotion.HAPPY,
}
## 相机离开主角头部锚点超过该距离时，主角模型才显示（避免第一人称看见脑壳）。
const SIT_CLEAR_DISTANCE := 0.65

@export var camera: DialogueCamera
@export var teacher: TeacherAnimator
@export var seating: Node3D
@export var protagonist_sit: Node3D
@export var protagonist_stand: Node3D
@export var protagonist_look: Node3D
@export var flow_state: L2FlowState
@export var interface: DialogueUI
@export var content_path: String = DEFAULT_CONTENT_PATH
## 时间缩放：1.0 正常；无头检查设小值加速整条时间轴（含镜头补间）。
@export_range(0.01, 4.0) var time_scale: float = 1.0
## 是否由流程引导视线（自动把镜头转向老师/同学/黑板）。
## 默认关闭：第一人称的朝向完全交给玩家（拖动鼠标或方向键），
## 流程只在开场定位和进入 L2 第三人称时改镜头。
@export var auto_look: bool = false

var _content: Dictionary = {}
var _pose_ids: Dictionary = {}
var _seated_poses: Array = []
var _seated_hip_height := 0.47
var _managed_actors: Array[String] = []
var _actor_cache: Dictionary = {}

## 当前阶段：intro / l1 / choice / answer / avoid / ending / l2 / complete。
var stage: StringName = &"intro"
var _beats: Array = []
var _beat_index: int = -1
var _branch: StringName = &""
var _generation: int = 0

var _event_log: Array[Dictionary] = []
var _l2_cards: Array[Dictionary] = []
var _l2_index: int = -1

var _seat := Vector3(-0.7, 0.0, 1.78)
var _seated_height := 1.36
var _standing_height := 1.7
var _rise_seconds := 0.8
## 姿态过渡默认秒数（内容 pose_transition_seconds）；事件可逐条覆盖。
var _pose_default_seconds := 0.5
var _l2_position := Vector3(0.0, 1.75, 2.9)
var _l2_seconds := 2.5
var _podium_position := Vector3(-2.8, 0.0, -3.05)
var _walk_seconds := 2.8
var _board_position := Vector3(0.9, 0.15, -4.44)
## 当前节拍的默认注视点；事件的镜头吸引结束后回到这里。
var _beat_look_target := Vector3.ZERO

var _protagonist_pose: StringName = &"sit"
var _muted: bool = false
var _flow_state_active: bool = false
var _l3_entered: bool = false
var _teacher_tween: Tween = null
var _prop_tween: Tween = null
var _voice: AudioStreamPlayer = null
var _sfx: AudioStreamPlayer = null
var _ambient: AudioStreamPlayer = null
var _pen: MeshInstance3D = null
var _textbook: MeshInstance3D = null
## 开场桌面道具（本子 / 笔 / 课本）的容器；只在第一次复位时生成一次。
var _desk_props: Node3D = null
## 语音/音效缺失只在首次登记时提醒一次，避免每个节拍刷屏。
var _missing_voice: Dictionary = {}
## 玩家自由转头的注视目标（事件05 这类“看到了才发生”的事件）。
var _gaze_events: Array[Dictionary] = []
## 当前节拍已触发过的事件 id，保证 gaze 与兜底时间戳不会重复触发同一事件。
var _beat_fired: Dictionary = {}
var _teacher_move_target: Vector3 = Vector3.ZERO
var _teacher_moving: bool = false
## 已播放过的流程步号（供无头检查核对 0–11 的时序）。
var _played_steps: Array[float] = []


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(content_path))
	if not parsed is Dictionary:
		push_error("DialogueFlow: 无法读取内容配置 " + content_path)
		get_tree().quit(1)
		return
	_content = parsed as Dictionary
	# character_pose.gd 没有 class_name，枚举与常量经脚本常量表反射读取（Pose 字典）。
	var pose_script: Script = load(CHARACTER_POSE_PATH)
	var pose_constants: Dictionary = pose_script.get_script_constant_map()
	_pose_ids = pose_constants.get("Pose", {})
	_seated_poses = pose_constants.get("SEATED_POSES", [])
	_seated_hip_height = float(pose_constants.get("SEATED_HIP_HEIGHT", 0.47))
	for pose_name in REQUIRED_POSES:
		if not _pose_ids.has(pose_name):
			push_error("DialogueFlow: character_pose.gd 的 Pose 枚举缺少 " + pose_name)
	_collect_managed_actors()
	_strip_duplicate_environment()
	interface.configure(_content)
	interface.advance_requested.connect(_on_advance)
	interface.pause_requested.connect(toggle_pause)
	interface.mute_requested.connect(toggle_mute)
	interface.restart_requested.connect(restart)
	interface.quit_requested.connect(quit)
	interface.answer_submitted.connect(_on_answer_submitted)
	interface.struggle_chosen.connect(_on_struggle)
	interface.avoid_chosen.connect(_on_avoid_chosen)
	_build_audio()
	_place_teacher_opening()
	_build_props()
	_read_config()
	_reset_world()

# ——— 阶段推进 ———

func _start_l1() -> void:
	stage = &"l1"
	_beats = _load_beats(_content.get("beats", []))
	_beat_index = -1
	_played_steps.clear()
	interface.hide_card() # 收起内容提示卡，进入课堂
	_advance_phase()
	_refresh_controls()


func _advance_phase() -> void:
	match stage:
		&"l1", &"answer", &"avoid", &"ending":
			_beat_index += 1
			if _beat_index < _beats.size():
				_play_beat(_beats[_beat_index])
			else:
				_next_phase()


func _next_phase() -> void:
	match stage:
		&"l1":
			_enter_choice()
		&"answer", &"avoid":
			_enter_ending()
		&"ending":
			_enter_l2()


func _enter_choice() -> void:
	stage = &"choice"
	_generation += 1
	camera.set_free_look(false) # 选择窗口交给鼠标操作，视线自动回正
	_set_ambient_whispers(true) # 同学们此时议论纷纷
	_start_ambient_loop("murmur_loop")
	interface.show_choice(_content.get("choice", {}))
	_refresh_controls()
	stage_changed.emit(stage)


func _enter_ending() -> void:
	stage = &"ending"
	_beats = _load_beats(_content.get("ending", []))
	_beat_index = -1
	_advance_phase()
	_refresh_controls()


func _enter_l2() -> void:
	stage = &"l2"
	interface.set_transition_text("")
	_l3_entered = false
	_build_l2_cards()
	_l2_index = -1
	_next_card()
	_refresh_controls()
	stage_changed.emit(stage)


func _enter_complete() -> void:
	stage = &"complete"
	_flow_state_active = false
	flow_state.deactivate()
	interface.show_complete()
	_refresh_controls()
	stage_changed.emit(stage)


# ——— 节拍播放 ———

func _play_beat(beat: Dictionary) -> void:
	_generation += 1
	var gen: int = _generation
	_gaze_events.clear()
	_beat_fired.clear()
	_record_step(beat)
	# 上一拍的教师走位若被跳过/超时，先收尾，避免与新节拍的动作打架
	if _teacher_moving:
		_move_teacher(_teacher_move_target, 0.0)
	interface.clear_subtitle()
	interface.set_transition_text("")
	# 教师动作与走位
	var teacher_cue: Dictionary = beat.get("teacher", {})
	if teacher_cue.has("action"):
		teacher.set_state(
			ACTION_IDS.get(str(teacher_cue["action"]), TeacherAnimator.Action.LECTURE),
			EMOTION_IDS.get(str(teacher_cue.get("emotion", "NEUTRAL")), TeacherAnimator.Emotion.NEUTRAL)
		)
	var teacher_at := str(beat.get("teacher_at", ""))
	var teacher_move: Dictionary = beat.get("teacher_move", {})
	if not teacher_move.is_empty():
		var move_target := (
			_board_position if str(teacher_move.get("to", "board")) == "board" else _podium_position
		)
		_move_teacher_walking(
			move_target,
			float(teacher_move.get("seconds", _walk_seconds)),
			str(teacher_move.get("action", "LECTURE")),
			str(teacher_move.get("emotion", "NEUTRAL")),
			gen
		)
	elif teacher_at == "board":
		_move_teacher(_board_position, _walk_seconds)
	elif teacher_at == "podium":
		_move_teacher(_podium_position, _walk_seconds)
	# 主角姿态（第一人称下不可见，但驱动头部高度与 L2 状态）
	if beat.has("protagonist"):
		_set_protagonist_pose(str(beat["protagonist"]))
	if beat.has("protagonist_clip"):
		_play_protagonist_clip(str(beat["protagonist_clip"]))
	# 镜头：朝向默认交给玩家；auto_look 打开时才按节拍引导
	var cam: Dictionary = beat.get("camera", {})
	if auto_look and cam.has("look"):
		_beat_look_target = _camera_target(str(cam["look"]))
		camera.set_look_target(_beat_look_target)
		camera.recenter_free_look() # 新节拍把视线拉回流程给定的方向
	camera.set_scan(float(cam.get("scan", 0.0)) if auto_look else 0.0)
	# 第一人称段全程可以自由转头（正面锥形内）；转第三人称时关闭
	var third_person := bool(cam.get("third_person", false))
	camera.set_free_look(not third_person)
	if not third_person:
		interface.set_look_hint(str(_content.get("ui", {}).get("look_hint", "")))
	if third_person:
		camera.transition_to(_l2_position, _camera_target("self_head"), _l2_seconds * time_scale)
	if beat.has("transition_text"):
		interface.set_transition_text(str(beat["transition_text"]))
	# 通用 cue
	for cue in beat.get("cues", []):
		_schedule(float(cue.get("at", 0.0)), func(): _run_cue(str(cue["do"]), gen))
	# 时间戳事件；带 gaze 的事件在玩家转到该方向时提前触发，at 只作兜底
	for event_cue in beat.get("events", []):
		var event_def: Dictionary = event_cue
		if event_def.has("gaze"):
			_gaze_events.append({
				"id": str(event_def["id"]),
				"target": _camera_target(str(event_def["gaze"])),
				"angle": float(event_def.get("gaze_angle", 12.0)),
				"gen": gen,
			})
		_schedule(float(event_def.get("at", 0.0)), func(): _fire_event(str(event_def["id"]), gen))
	# 字幕分段与配音（segments 可带 at 指定偏移，否则顺序衔接）
	var t := 0.0
	var audio_end := 0.0
	var padding := float(_content.get("voice", {}).get("padding", 0.25))
	for segment in beat.get("segments", []):
		var seg: Dictionary = segment
		var seg_seconds := float(seg.get("seconds", 1.0))
		var seg_at := float(seg.get("at", t))
		var voice_path := _resolve_cue("voice", str(seg.get("voice", "")))
		_schedule(seg_at, func(): _show_segment(seg))
		if not voice_path.is_empty():
			_schedule(seg_at, func(): _play_voice(voice_path))
			audio_end = maxf(audio_end, seg_at + _voice_length(voice_path) + padding)
		t = seg_at + seg_seconds
	# 时长取三者较大值：作者预留、字幕结束、配音实际长度
	var hold := maxf(float(beat.get("hold", t)), maxf(t, audio_end))
	_schedule(hold, func(): _finish_beat_if(gen))
	_refresh_controls()


func _record_step(beat: Dictionary) -> void:
	if not beat.has("step"):
		return
	var step := float(beat["step"])
	if _played_steps.is_empty() or _played_steps[_played_steps.size() - 1] != step:
		_played_steps.append(step)


func _finish_beat_if(gen: int) -> void:
	if gen != _generation:
		return
	_finish_beat()


func _finish_beat() -> void:
	_generation += 1
	_advance_phase()


func _current_beat() -> Dictionary:
	if _beat_index < 0 or _beat_index >= _beats.size():
		return {}
	return _beats[_beat_index]


# ——— 事件 ———

func _fire_event(event_id: String, gen: int) -> void:
	if gen != _generation:
		return
	if _beat_fired.has(event_id):
		return # gaze 与兜底时间戳只触发一次
	_beat_fired[event_id] = true
	_gaze_events = _gaze_events.filter(func(entry: Dictionary) -> bool: return str(entry["id"]) != event_id)
	var event: Dictionary = _content.get("events", {}).get(event_id, {})
	if event.is_empty():
		push_warning("DialogueFlow: 未知事件 " + event_id)
		return
	# 第二层词条：事件发生时登记，L2 回看（按 step 记录时序，回溯从第 0 步开始）
	_event_log.append({
		"label": str(event.get("label", event_id)),
		"step": float(event.get("step", 0.0)),
		"thoughts": event.get("thoughts", []),
	})
	# 感受词条 chip（事件发生时直接加入）
	var feelings: Array = event.get("feelings", [])
	if not feelings.is_empty():
		interface.show_chip(str(event.get("short", event.get("label", ""))), "、".join(feelings))
	# 环境收声 / 全员复位
	if event.get("ambient_to_sit", false):
		_set_ambient_whispers(false)
	if event.get("all_managed_to_sit", false):
		_reset_managed_actors()
	# 程序化动作（人物场景支持 play_clip 时生效，否则由 poses 的静态姿兜底）
	for clip_cue in event.get("clips", []):
		var clip_def: Dictionary = clip_cue
		_schedule(
			float(clip_def.get("at", 0.0)),
			func(): _play_actor_clip(str(clip_def["actor"]), str(clip_def["clip"]))
		)
	# 同学姿态（可带 recover 回到坐姿）
	# transition / recover_transition：该条姿态自己的过渡秒数，缺省用内容里的
	# pose_transition_seconds。慢动作事件（弯腰捡笔、回头）靠它把动作拖长，
	# 静态姿态没有动画层，能调的只有这段 slerp 时间。
	for pose_cue in event.get("poses", []):
		var pose: Dictionary = pose_cue
		var pose_in := float(pose.get("transition", -1.0))
		var pose_out := float(pose.get("recover_transition", -1.0))
		_schedule(
			float(pose.get("at", 0.0)),
			func(): _set_actor_pose(str(pose["actor"]), str(pose["pose"]), pose_in)
		)
		if pose.has("recover"):
			_schedule(
				float(pose["recover"]),
				func(): _set_actor_pose(str(pose["actor"]), "SIT", pose_out)
			)
	# 第一层声音：speech 走字幕条，ambient 只放音频
	var voice: Dictionary = event.get("voice", {})
	if not voice.is_empty():
		var voice_at := float(voice.get("at", 0.0))
		var kind := str(voice.get("kind", "speech"))
		if kind == "speech":
			_schedule(voice_at, func(): _show_segment({
				"speaker": str(voice.get("speaker", "classmate")),
				"text": str(voice.get("text", "")),
				"seconds": float(voice.get("seconds", 2.0)),
			}))
		var cue_path := _resolve_cue("voice" if kind == "speech" else "sfx", str(voice.get("cue", "")))
		if not cue_path.is_empty():
			_schedule(voice_at, func(): _play_cue(cue_path, kind != "speech"))
	# 道具
	for prop_cue in event.get("props", []):
		var prop: Dictionary = prop_cue
		_schedule(
			float(prop.get("at", 0.0)),
			func(): _apply_prop_action(str(prop["prop"]), str(prop["action"]))
		)
	# 镜头吸引：auto_look 打开时事件才转头（默认关闭，朝向交给玩家）
	var event_camera: Dictionary = event.get("camera", {})
	if auto_look and event_camera.has("look"):
		camera.recenter_free_look() # 先交还视线控制权，事件才框得住
		camera.set_look_target(_camera_target(str(event_camera["look"])))
		if event_camera.has("recover"):
			var recover_after := float(event_camera["recover"])
			_schedule(recover_after, func(): camera.set_look_target(_beat_look_target))

	# 三维事件标记：在事件发生处广播「可观察事件」，由 SceneUI3D 生成可点击收集的小球。
	var _ev_world := Vector3.ZERO
	if event_camera.has("look"):
		_ev_world = _camera_target(str(event_camera["look"]))
	elif teacher != null:
		_ev_world = teacher.global_position
	event_observed.emit(StringName(event_id), str(event.get("label", event_id)), _ev_world)


func _run_cue(action: String, gen: int) -> void:
	if gen != _generation:
		return
	match action:
		"activate_flow_state":
			_activate_flow_state()
		"place_textbook":
			if _textbook != null:
				_textbook.visible = true


func _show_segment(segment: Dictionary) -> void:
	var speaker_key := str(segment.get("speaker", "stage"))
	var label := str(_content.get("ui", {}).get("speaker_" + speaker_key, speaker_key))
	interface.set_subtitle(label, str(segment.get("text", "")))
	# —— 3D 字幕 + 声纹（不改动时序）——
	if interface.has_signal("world_subtitle"):
		interface.emit_signal("world_subtitle", StringName(speaker_key), label, str(segment.get("text", "")))
	sound_emitted.emit(_speaker_world_position(speaker_key), 0.6)


## 依据说话者 key 估算其世界坐标，用于把「声纹」放到发声者附近。
func _speaker_world_position(speaker_key: String) -> Vector3:
	match speaker_key:
		"teacher":
			return teacher.global_position if teacher != null else _podium_position
		"protagonist":
			for _p in [protagonist_stand, protagonist_look, protagonist_sit]:
				if _p != null and _p.visible:
					return _p.global_position
			return protagonist_sit.global_position if protagonist_sit != null else Vector3.ZERO
		"classmate":
			return _camera_target("left_neighbor")
		_:
			return _podium_position


# ——— 分支（第 8 步是唯一分支点） ———

## 清晰回应：玩家输入（可留空走固定句）→ 分支一（自信）。
func _on_answer_submitted(text: String) -> void:
	if stage != &"choice":
		return
	_branch = &"confident"
	stage = &"answer"
	interface.hide_choice()
	_stop_ambient()
	var choice: Dictionary = _content.get("choice", {})
	var line := text.strip_edges()
	var fallback := str(choice.get("answer_fallback", ""))
	if line.is_empty():
		line = fallback
	# 留空时走固定句，可以预录配音；玩家自己输入的文字按字数预留时长，不接音频
	var voice := str(choice.get("answer_fallback_voice", "")) if line == fallback else ""
	var per_char := float(choice.get("answer_seconds_per_char", 4.6))
	var seconds := clampf(
		line.length() / per_char,
		float(choice.get("answer_min_seconds", 2.5)),
		float(choice.get("answer_max_seconds", 12.0))
	)
	_beats = [
		_player_answer_beat(line, seconds, "STAND_TALK", voice),
		_teacher_reply_beat(choice.get("confident", {}), "s08_teacher_accept", "HAPPY"),
	]
	_beat_index = -1
	_advance_phase()
	_refresh_controls()


## 勉强开口：断断续续说完同一立场 → 分支二（紧张）。
func _on_struggle() -> void:
	if stage != &"choice":
		return
	_branch = &"struggle"
	stage = &"answer"
	interface.hide_choice()
	_stop_ambient()
	var choice: Dictionary = _content.get("choice", {})
	var seconds := float(choice.get("struggle_seconds", 4.2))
	_beats = [
		_player_answer_beat(
			str(choice.get("struggle_line", "")), seconds, "STAND_TALK",
			str(choice.get("struggle_voice", ""))
		),
		_teacher_reply_beat(choice.get("struggle", {}), "s08_teacher_nervous", "DOWN"),
	]
	_beat_index = -1
	_advance_phase()
	_refresh_controls()


## 躲开视线：低头四处看 → 分支二（紧张，无台词）。
func _on_avoid_chosen() -> void:
	if stage != &"choice":
		return
	_branch = &"avoid"
	stage = &"avoid"
	interface.hide_choice()
	_stop_ambient()
	var choice: Dictionary = _content.get("choice", {})
	var beats := _load_beats(_content.get("branch_avoid", []))
	beats.append(_teacher_reply_beat(choice.get("avoid", {}), "s08_teacher_nervous", "DOWN"))
	_beats = beats
	_beat_index = -1
	_advance_phase()
	_refresh_controls()


func _player_answer_beat(
	line: String, seconds: float, clip: String, voice: String = ""
) -> Dictionary:
	return {
		"step": float(_content.get("choice", {}).get("step", 8)),
		"id": "s08_player_answer",
		"hold": seconds + 0.4,
		"teacher": { "action": "LECTURE", "emotion": "NEUTRAL" },
		"protagonist": "stand",
		"protagonist_clip": clip,
		"segments": [{
			"speaker": "protagonist",
			"text": line,
			"seconds": seconds,
			"voice": voice,
		}],
	}


func _teacher_reply_beat(cfg: Dictionary, beat_id: String, fallback_emotion: String) -> Dictionary:
	var reply: Dictionary = cfg.get("teacher", {})
	var seconds := float(reply.get("seconds", 3.8))
	return {
		"step": float(_content.get("choice", {}).get("step", 8)),
		"id": beat_id,
		"hold": seconds + 0.3,
		"teacher": {
			"action": str(reply.get("action", "LECTURE")),
			"emotion": str(reply.get("emotion", fallback_emotion)),
		},
		"segments": [{
			"speaker": "teacher",
			"text": str(reply.get("text", "")),
			"seconds": seconds,
			"voice": str(reply.get("voice", "")),
		}],
	}


## 按分支过滤 only_branch 节拍（E03 只在清晰回应后出现）。
func _load_beats(source: Variant) -> Array:
	var out: Array = []
	if not source is Array:
		return out
	for item in source:
		var beat: Dictionary = item
		var only := str(beat.get("only_branch", ""))
		if not only.is_empty() and StringName(only) != _branch:
			continue
		out.append(beat)
	return out


# ——— L2 词条序列 ———

func _build_l2_cards() -> void:
	_l2_cards.clear()
	var l2: Dictionary = _content.get("l2", {})
	var base := float(l2.get("card_base_seconds", 1.8))
	var per_line := float(l2.get("card_seconds_per_line", 0.55))
	# 0) 回溯起点：进入 L2 后从第 0 步重新看一遍（“回溯到 0”）
	var rewind_line := str(l2.get("rewind_line", ""))
	if not rewind_line.is_empty():
		_l2_cards.append({
			"title": str(l2.get("rewind_title", "思绪倒放 · 回到最开始")),
			"body": rewind_line,
			"seconds": float(l2.get("rewind_seconds", 2.6)),
			"voice": str(l2.get("rewind_voice", "")),
		})
	# 1) 事件词条：主角想法，按发生的流程步号从第 0 步排起
	for entry in _sorted_event_log():
		var thoughts: Array = entry.get("thoughts", [])
		if thoughts.is_empty():
			continue
		_l2_cards.append({
			"title": str(entry.get("label", "")),
			"body": "\n".join(thoughts),
			"seconds": base + per_line * thoughts.size(),
		})
	# 2) 思绪倒放（按分支）
	var replay: Array = (
		l2.get("replay_confident", []) if _branch == &"confident" else l2.get("replay_nervous", [])
	)
	var replay_title := str(l2.get("replay_title", "思绪倒放"))
	for line in replay:
		var text := str(line)
		var voice := ""
		if line is Dictionary:
			text = str(line.get("text", ""))
			voice = str(line.get("voice", ""))
		_l2_cards.append({"title": replay_title, "body": text, "seconds": 2.8, "voice": voice})
	# 3) 对观察的观察（心理概念）
	var observation_title := str(l2.get("observations_title", "对观察的观察"))
	for observation in l2.get("observations", []):
		var obs: Dictionary = observation
		_l2_cards.append({
			"title": observation_title + " · " + str(obs.get("concept", "")),
			"body": str(obs.get("line", "")),
			"seconds": 3.0,
			"isolate": true,
			"voice": str(obs.get("voice", "")),
		})


func _sorted_event_log() -> Array:
	var entries := _event_log.duplicate()
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("step", 0.0)) < float(b.get("step", 0.0))
	)
	return entries


func _next_card() -> void:
	_generation += 1
	var gen: int = _generation
	_l2_index += 1
	if _l2_index >= _l2_cards.size():
		_enter_complete()
		return
	var card: Dictionary = _l2_cards[_l2_index]
	if bool(card.get("isolate", false)) and not _l3_entered:
		_l3_entered = true
		if flow_state != null:
			flow_state.enter_l3()
	interface.show_card(str(card.get("title", "")), str(card.get("body", "")))
	var voice_path := _resolve_cue("voice", str(card.get("voice", "")))
	var seconds := float(card.get("seconds", 2.8))
	if not voice_path.is_empty():
		_play_voice(voice_path)
		seconds = maxf(seconds, _voice_length(voice_path) + float(_content.get("voice", {}).get("padding", 0.25)))
	_schedule(seconds, func(): _next_card_if(gen))
	_refresh_controls()


func _next_card_if(gen: int) -> void:
	if gen != _generation:
		return
	_next_card()


# ——— 控制 ———

func _on_advance() -> void:
	if stage == &"intro":
		_start_l1()
	elif stage == &"complete":
		restart()
	else:
		skip()


func skip() -> void:
	if get_tree().paused or not _skip_enabled():
		return
	if stage == &"l2":
		_next_card()
		return
	var beat := _current_beat()
	if beat.is_empty():
		return
	if Dictionary(beat.get("camera", {})).get("third_person", false):
		# 跳过 L1→L2 转场：相机立即到位，心流状态立即激活
		camera.snap(_l2_position, _camera_target("self_head"))
		if not _flow_state_active:
			_activate_flow_state()
	_finish_beat()


func toggle_pause() -> void:
	if stage in [&"intro", &"complete"]:
		return
	get_tree().paused = not get_tree().paused
	var paused: bool = get_tree().paused
	interface.show_paused(paused)
	if not paused and stage == &"l2" and _l2_index >= 0 and _l2_index < _l2_cards.size():
		var card: Dictionary = _l2_cards[_l2_index]
		interface.show_card(str(card.get("title", "")), str(card.get("body", "")))
	_refresh_controls()
	interface.focus_primary()


func toggle_mute() -> void:
	_muted = not _muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _muted)
	_refresh_controls()


func restart() -> void:
	get_tree().paused = false
	_reset_world()


func quit() -> void:
	get_tree().paused = false
	if _flow_state_active:
		flow_state.deactivate(true)
		_flow_state_active = false
	camera.cancel()
	get_tree().quit()


func _skip_enabled() -> bool:
	return stage in [&"l1", &"answer", &"avoid", &"ending", &"l2"]


func _refresh_controls() -> void:
	interface.present_controls(get_tree().paused, _muted, _skip_enabled() and not get_tree().paused)


# ——— 世界复位 ———

func _reset_world() -> void:
	_generation += 1
	_kill_tweens()
	_apply_pose_transition_seconds()
	_reset_managed_actors()
	_build_desk_props()
	_apply_ambient_state()  # 开场不是全班端坐：有人写字、有人看书、有人听讲
	_set_ambient_whispers(true) # 开场前教室里本就有低声交谈（覆盖上面同座位的交头接耳）
	_set_protagonist_pose("sit", true)
	# 教师：开场站在讲台前面对大家讲课，全程不移动（反馈：示意回答时不要移动老师）
	teacher.playing = true
	teacher.position = _podium_position
	teacher.rotation_degrees = Vector3(0, 180, 0)
	teacher.set_state(TeacherAnimator.Action.LECTURE, TeacherAnimator.Emotion.NEUTRAL, true)
	# 道具
	if _pen != null:
		_pen.position = _vec(_content.get("props", {}).get("pen", {}).get("desk_position", [0, 0, 0]))
		_pen.rotation_degrees = Vector3(90, 0, 0)
	if _textbook != null:
		_textbook.visible = false
	# 心流状态
	if _flow_state_active:
		flow_state.deactivate(true)
	_flow_state_active = false
	_l3_entered = false
	# 状态机
	stage = &"intro"
	_beats = []
	_beat_index = -1
	_branch = &""
	_event_log.clear()
	_l2_cards.clear()
	_l2_index = -1
	_played_steps.clear()
	_gaze_events.clear()
	_beat_fired.clear()
	_teacher_moving = false
	_beat_look_target = _camera_target("podium_teacher")
	# 音频与自由转头
	_stop_all_audio()
	camera.set_free_look(false)
	# 界面与镜头
	interface.show_intro()
	interface.clear_subtitle()
	interface.set_transition_text("")
	_refresh_controls()


func _kill_tweens() -> void:
	camera.cancel()
	if _teacher_tween != null and _teacher_tween.is_valid():
		_teacher_tween.kill()
	_teacher_tween = null
	_teacher_moving = false
	if _prop_tween != null and _prop_tween.is_valid():
		_prop_tween.kill()
	_prop_tween = null


# ——— 演员姿态 ———

func _collect_managed_actors() -> void:
	_managed_actors.clear()
	var actors: Dictionary = _content.get("actors", {})
	for key in actors:
		if key == "whisper_pairs":
			continue
		_managed_actors.append(str(actors[key]))
	for pair in actors.get("whisper_pairs", []):
		for seat in pair:
			_managed_actors.append(str(seat))


func _actor_node(name: String) -> Node:
	if _actor_cache.has(name):
		return _actor_cache[name]
	var seat := str(_content.get("actors", {}).get(name, name))
	var node: Node = seating.get_node_or_null(seat) if seating != null else null
	_actor_cache[name] = node
	return node


## `transition` 为该次姿态切换的过渡秒数；< 0 表示用内容里的默认值
## （pose_transition_seconds）。事件可以由动作自身把速度放慢。
func _set_actor_pose(actor: String, pose: String, transition: float = -1.0) -> void:
	var pose_id: int = _pose_ids.get(pose, -1)
	if pose_id < 0:
		push_warning("DialogueFlow: 未知姿态 " + pose)
		return
	var node := _actor_node(actor)
	if node == null:
		push_warning("DialogueFlow: 找不到演员节点 " + actor)
		return
	if "pose_transition_seconds" in node:
		node.pose_transition_seconds = _pose_default_seconds if transition < 0.0 else transition
	if int(node.pose) == pose_id:
		return # 姿态未变：跳过，避免无意义地重跑 apply_pose（其内部会先把模型抬回未下沉位）
	node.pose = pose_id
	node.apply_pose()
	_schedule_sink_check(node)


## 程序化动作：人物节点换成 character_action.gd 后自动生效；静态姿态场景静默跳过。
func _play_actor_clip(actor: String, clip_name: String) -> void:
	var node := _actor_node(actor)
	if node == null or not node.has_method("play_clip"):
		return
	var clip_id: int = CLIP_IDS.get(clip_name, -1)
	if clip_id < 0:
		push_warning("DialogueFlow: 未知动作 " + clip_name)
		return
	node.play_clip(clip_id, true)


## 主角动作（起身/坐下/说话/四处看）。当前主角为静态姿态场景，接入动画场景后生效。
func _play_protagonist_clip(clip_name: String) -> void:
	var clip_id: int = CLIP_IDS.get(clip_name, -1)
	if clip_id < 0:
		return
	for node in [protagonist_stand, protagonist_look]:
		if node != null and node.has_method("play_clip"):
			node.play_clip(clip_id, true)


## apply_pose() 内部会 await 两帧再把模型下沉到坐姿髋高，且不是可重入的：
## 场景 _ready 的协程尚未结束时再调一次，后恢复的调用会把已下沉的模型抬回原位
## （同学会“坐高”约 40cm）。这里在协程跑完后校验并校正下沉，窗口只有几帧。
func _schedule_sink_check(node: Node) -> void:
	if not (node is Node3D):
		return
	_correct_sink_soon(node)


func _correct_sink_soon(node: Node) -> void:
	for i in range(3):
		await get_tree().process_frame
	_ensure_seat_sink(node)


func _ensure_seat_sink(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if not _seated_poses.has(int(node.pose)):
		return
	var skeleton := _find_skeleton(node)
	var model := node.get_node_or_null("Model") as Node3D
	if skeleton == null or model == null:
		return
	var hips_idx := skeleton.find_bone("Hips")
	if hips_idx == -1:
		return
	var hips_y: float = (skeleton.global_transform * skeleton.get_bone_global_pose(hips_idx)).origin.y
	var delta: float = _seated_hip_height - hips_y
	if absf(delta) > 0.005:
		model.position.y += delta


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _reset_managed_actors() -> void:
	for actor in _managed_actors:
		_set_actor_pose(actor, "SIT")


## 姿态过渡时间统一由 content.pose_transition_seconds 给：0 即回到“瞬切”。
## 静态姿态本身没有动画层，切换时靠 character_pose.gd 的骨骼 slerp 过渡。
func _apply_pose_transition_seconds() -> void:
	var seconds := float(_content.get("pose_transition_seconds", 0.45))
	_pose_default_seconds = seconds
	if seating == null:
		return
	for child in seating.get_children():
		if "pose_transition_seconds" in child:
			child.pose_transition_seconds = seconds


## 开场教室：按 content.ambient.states 给每张桌子一个已经开始的状态
## （写字 / 看书 / 听讲）。被流程管理的事件座位会被后续事件覆盖，属于预期。
func _apply_ambient_state() -> void:
	var ambient: Dictionary = _content.get("ambient", {})
	for entry in ambient.get("states", []):
		var item: Dictionary = entry
		var pose := str(item.get("pose", ""))
		if pose.is_empty():
			continue
		_set_actor_pose(str(item.get("seat", "")), pose)


## 桌面道具：写字的人桌上放本子和笔，看书的人桌上摊课本。
## 全部用 PropKit 的程序化网格，不引用外部素材；只在第一次复位时生成。
func _build_desk_props() -> void:
	if _desk_props != null or seating == null:
		return
	_desk_props = Node3D.new()
	_desk_props.name = "DeskProps"
	add_child(_desk_props)
	var ambient: Dictionary = _content.get("ambient", {})
	var top_y := float(ambient.get("desk_top_y", 0.775))
	var forward := float(ambient.get("desk_forward", 0.72))
	for entry in ambient.get("states", []):
		var item: Dictionary = entry
		var kind := str(item.get("desk", ""))
		if kind.is_empty():
			continue
		var seat := seating.get_node_or_null(str(item.get("seat", ""))) as Node3D
		if seat == null:
			push_warning("DialogueFlow: ambient 里找不到座位 " + str(item.get("seat", "")))
			continue
		_spawn_desk_prop(seat, kind, top_y, forward)


## 道具摆在座位正前方的课桌台面上：座位局部 -Z 是课桌方向，桌面高 0.775 m。
## 每张桌子按座位名做一点稳定的小偏移/小转角，满座时不至于像印刷品。
func _spawn_desk_prop(seat: Node3D, kind: String, top_y: float, forward: float) -> void:
	var basis := seat.global_transform.basis.orthonormalized()
	var jitter := float(absi(hash(String(seat.name))) % 100) / 100.0
	var root := Node3D.new()
	root.name = "Desk_" + String(seat.name)
	_desk_props.add_child(root)
	root.global_position = seat.global_position - basis.z * forward + basis.x * (jitter - 0.5) * 0.09
	root.global_rotation = Vector3(0.0, (jitter - 0.5) * 18.0, 0.0)
	if kind.begins_with("notebook"):
		var note := PropKit.notebook()
		note.position = Vector3(0.0, top_y + 0.007, 0.0)
		root.add_child(note)
		if kind == "notebook_pen" or kind == "notebook_pencil":
			var tool: Node3D = PropKit.pen() if kind == "notebook_pen" else PropKit.pencil()
			# 摆在靠近人的一侧：写字的手（WRITING 的 IK 落点）正好压在这支笔上
			tool.position = Vector3(0.02, top_y + 0.019, 0.09)
			tool.rotation_degrees = Vector3(0.0, 24.0, 0.0)
			root.add_child(tool)
	elif kind == "textbook":
		var book := PropKit.textbook()
		book.position = Vector3(0.0, top_y + 0.014, 0.0)
		root.add_child(book)


func _set_ambient_whispers(on: bool) -> void:
	# 每对交头接耳：左座向右倾（WHISPER_R），右座向左倾（WHISPER_L）。
	for pair in _content.get("actors", {}).get("whisper_pairs", []):
		var left := str(pair[0])
		var right := str(pair[1])
		if on:
			_set_actor_pose(left, "WHISPER_R")
			_set_actor_pose(right, "WHISPER_L")
		else:
			_set_actor_pose(left, "SIT")
			_set_actor_pose(right, "SIT")


func _set_protagonist_pose(pose: String, immediate: bool = false) -> void:
	_protagonist_pose = StringName(pose)
	var height: float = _standing_height if pose != "sit" else _seated_height
	var target := Vector3(_seat.x, height, _seat.z)
	if immediate:
		camera.snap(target, _camera_target("podium_teacher"))
	else:
		camera.move_to(target, _rise_seconds * time_scale)


# ——— 教师走位 ———

func _move_teacher(target: Vector3, seconds: float, then_callable: Callable = Callable()) -> void:
	if _teacher_tween != null and _teacher_tween.is_valid():
		_teacher_tween.kill()
	_teacher_tween = null
	_teacher_move_target = target
	_teacher_moving = seconds > 0.0
	if seconds > 0.0:
		sound_emitted.emit(teacher.global_position if teacher != null else target, 1.0)
	if seconds <= 0.0:
		teacher.position = target
		if then_callable.is_valid():
			then_callable.call()
		return
	var from := teacher.position
	_teacher_tween = teacher.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_teacher_tween.tween_method(
		func(value: Vector3) -> void: teacher.position = value, from, target, seconds * time_scale
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if then_callable.is_valid():
		_teacher_tween.tween_callback(then_callable)


## 讲台 ↔ 黑板：走路姿态 + 场景位移（位移补间可被重开/跳过打断），到位后切到目标动作。
func _move_teacher_walking(
	target: Vector3, seconds: float, end_action: String, end_emotion: String, gen: int
) -> void:
	teacher.set_state(TeacherAnimator.Action.WALK, TeacherAnimator.Emotion.NEUTRAL, true)
	var finish := func() -> void:
		_teacher_moving = false
		if gen != _generation:
			return
		teacher.set_state(
			ACTION_IDS.get(end_action, TeacherAnimator.Action.LECTURE),
			EMOTION_IDS.get(end_emotion, TeacherAnimator.Emotion.NEUTRAL),
			true
		)
	_move_teacher(target, seconds, finish)


func _place_teacher_opening() -> void:
	# 开场：老师站在讲台前面对大家讲课（用户 2026-10-24 反馈：不要背身写板书）。
	# 板书机位仅保留给结尾“课堂已经往下走了”（新增06）。
	if teacher == null:
		return
	_podium_position = _vec(_content.get("teacher", {}).get("podium_position", [-2.8, 0.0, -3.05]))
	_board_position = _vec(_content.get("teacher", {}).get("board_position", [0.9, 0.15, -4.44]))
	teacher.position = _podium_position
	teacher.rotation_degrees = Vector3(0, 180, 0)
	teacher.set_state(TeacherAnimator.Action.LECTURE, TeacherAnimator.Emotion.NEUTRAL, true)


# ——— 道具（笔 / 课本，运行时生成，无外部素材） ———

func _build_props() -> void:
	var props: Dictionary = _content.get("props", {})
	var pen_cfg: Dictionary = props.get("pen", {})
	_pen = MeshInstance3D.new()
	_pen.name = "Pen"
	var pen_mesh := CylinderMesh.new()
	pen_mesh.top_radius = 0.008
	pen_mesh.bottom_radius = 0.008
	pen_mesh.height = 0.14
	pen_mesh.radial_segments = 10
	_pen.mesh = pen_mesh
	var pen_material := StandardMaterial3D.new()
	pen_material.albedo_color = Color(0.13, 0.24, 0.45)
	pen_material.roughness = 0.55
	_pen.material_override = pen_material
	_pen.rotation_degrees = Vector3(90, 0, 0)
	_pen.position = _vec(pen_cfg.get("desk_position", [0, 0, 0]))
	add_child(_pen)
	var book_cfg: Dictionary = props.get("textbook", {})
	_textbook = MeshInstance3D.new()
	_textbook.name = "Textbook"
	var book_mesh := BoxMesh.new()
	book_mesh.size = _vec(book_cfg.get("size", [0.26, 0.05, 0.19]))
	_textbook.mesh = book_mesh
	var book_material := StandardMaterial3D.new()
	book_material.albedo_color = Color(0.30, 0.42, 0.38)
	book_material.roughness = 0.7
	_textbook.material_override = book_material
	_textbook.position = _vec(book_cfg.get("position", [0, 0, 0]))
	_textbook.visible = false
	add_child(_textbook)


func _apply_prop_action(prop: String, action: String) -> void:
	if prop != "pen" or _pen == null:
		return
	var pen_cfg: Dictionary = _content.get("props", {}).get("pen", {})
	# 落笔/还笔的时长也走内容配置：慢节奏下笔要滚得慢、放得慢。
	var fall_seconds := float(pen_cfg.get("fall_seconds", 0.55))
	var return_seconds := float(pen_cfg.get("return_seconds", 0.45))
	match action:
		"fall":
			_tween_prop(_pen, _vec(pen_cfg.get("floor_position", [0, 0, 0])), fall_seconds, true)
		"return":
			_tween_prop(_pen, _vec(pen_cfg.get("return_position", [0, 0, 0])), return_seconds, false)


func _tween_prop(node: MeshInstance3D, target: Vector3, seconds: float, rolling: bool) -> void:
	if _prop_tween != null and _prop_tween.is_valid():
		_prop_tween.kill()
	var from := node.position
	_prop_tween = node.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_prop_tween.tween_method(
		func(value: Vector3) -> void: node.position = value, from, target, seconds * time_scale
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN if rolling else Tween.EASE_OUT)
	if rolling:
		_prop_tween.parallel().tween_property(
			node, "rotation_degrees:z", -150.0, seconds * time_scale
		)
	else:
		_prop_tween.parallel().tween_property(
			node, "rotation_degrees:z", 0.0, seconds * time_scale
		)


# ——— 配音与音效（voice / sfx 清单，id → 文件） ———

## 三条独立通道：台词、音效、环境底噪。全部走 Master，静音按钮直接静音 Master。
func _build_audio() -> void:
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	add_child(_voice)
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "Sfx"
	add_child(_sfx)
	_ambient = AudioStreamPlayer.new()
	_ambient.name = "Ambient"
	_ambient.volume_db = -9.0
	add_child(_ambient)


## 把配置里的配音 id 解析成资源路径；也接受直接写 res:// 路径（旧配置）。
## 清单里没有的 id 只提醒一次并静默跳过，不影响流程推进。
func _resolve_cue(section: String, key: String) -> String:
	if key.is_empty():
		return ""
	if key.begins_with("res://"):
		return key
	var cfg: Dictionary = _content.get(section, {})
	var table: Dictionary = cfg.get("cues", {})
	var file := ""
	if table.has(key):
		var value: Variant = table[key]
		file = str(value.get("file", "")) if value is Dictionary else str(value)
	else:
		var missing_key := section + ":" + key
		if not _missing_voice.has(missing_key):
			_missing_voice[missing_key] = true
			push_warning("DialogueFlow: %s 清单里没有配音 id %s" % [section, key])
		return ""
	if file.is_empty():
		return ""
	if file.begins_with("res://"):
		return file
	return str(cfg.get("root", "")).path_join(file)


func _stream(path: String) -> AudioStream:
	if path.is_empty():
		return null
	var stream: Variant = load(path) if ResourceLoader.exists(path) else null
	return stream as AudioStream


func _play_voice(path: String) -> void:
	if _voice == null:
		return
	var stream := _stream(path)
	if stream == null:
		return
	_voice.stream = stream
	_voice.play()


## 事件里的环境音/同学低声说话。as_sfx=true 时走音效通道，不打断台词。
func _play_cue(path: String, as_sfx: bool) -> void:
	var player := _sfx if as_sfx else _voice
	if player == null:
		return
	var stream := _stream(path)
	if stream == null:
		return
	player.stream = stream
	player.play()
	# 三维声纹：环境音 / 同学低语等「动静」出现的位置（以教师附近作为教室声源近似）。
	if as_sfx:
		sound_emitted.emit(teacher.global_position if teacher != null else _podium_position, 0.8)


func _voice_length(path: String) -> float:
	var stream := _stream(path)
	if stream == null:
		return 0.0
	return stream.get_length()


func _start_ambient_loop(key: String) -> void:
	if _ambient == null:
		return
	var stream := _stream(_resolve_cue("sfx", key))
	if stream == null:
		return
	# 复制一份再开循环，避免改动导入资源缓存。
	var looped := stream.duplicate() as AudioStream
	if looped is AudioStreamOggVorbis:
		(looped as AudioStreamOggVorbis).loop = true
	elif looped is AudioStreamMP3:
		(looped as AudioStreamMP3).loop = true
	_ambient.stream = looped
	_ambient.play()


func _stop_ambient() -> void:
	if _ambient != null:
		_ambient.stop()


func _stop_all_audio() -> void:
	for player in [_voice, _sfx, _ambient]:
		if player != null:
			(player as AudioStreamPlayer).stop()


# ——— 心流状态（L2） ———

func _activate_flow_state() -> void:
	if _flow_state_active or flow_state == null:
		return
	_flow_state_active = true
	flow_state.activate()


# ——— 场景清理与配置读取 ———

## classroom_seating 自带 WorldEnvironment/Daylight 供独立预览；本场景已实例化
## classroom_static（含烘焙光照），移除重复项，避免双环境与双方向光。
func _strip_duplicate_environment() -> void:
	if seating == null:
		return
	for child_name in ["WorldEnvironment", "Daylight"]:
		var duplicate := seating.get_node_or_null(child_name)
		if duplicate != null:
			seating.remove_child(duplicate)
			duplicate.queue_free()


func _read_config() -> void:
	var cam: Dictionary = _content.get("camera", {})
	_seat = _vec(cam.get("seat", [-0.7, 0.0, 1.78]))
	_seated_height = float(cam.get("seated_height", 1.36))
	_standing_height = float(cam.get("standing_height", 1.7))
	_rise_seconds = float(cam.get("rise_seconds", 0.8))
	_l2_position = _vec(cam.get("l2_position", [0.0, 1.75, 2.9]))
	_l2_seconds = float(cam.get("l2_seconds", 2.5))
	camera.idle_position_amplitude = float(cam.get("idle_position_amplitude", 0.004))
	camera.idle_look_amplitude = float(cam.get("idle_look_amplitude", 0.035))
	camera.free_look_yaw_limit = float(cam.get("free_look_yaw_limit", camera.free_look_yaw_limit))
	camera.free_look_pitch_up = float(cam.get("free_look_pitch_up", camera.free_look_pitch_up))
	camera.free_look_pitch_down = float(cam.get("free_look_pitch_down", camera.free_look_pitch_down))
	camera.free_look_speed = float(cam.get("free_look_speed", camera.free_look_speed))
	var teacher_cfg: Dictionary = _content.get("teacher", {})
	_podium_position = _vec(teacher_cfg.get("podium_position", [-2.8, 0.0, -3.05]))
	_walk_seconds = float(teacher_cfg.get("walk_seconds", 2.8))


func _camera_target(name: String) -> Vector3:
	var targets: Dictionary = _content.get("camera", {}).get("targets", {})
	return _vec(targets.get(name, [0.0, 1.0, 0.0]))


func _vec(value: Variant) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var array: Array = value
		return Vector3(float(array[0]), float(array[1]), float(array[2]))
	return Vector3.ZERO


# ——— 每帧：主角模型只在相机离开头部后显示 ———

func _process(_delta: float) -> void:
	_check_gaze_events()
	var anchor := protagonist_sit.get_node_or_null("ViewAnchor") as Node3D if protagonist_sit != null else null
	if anchor == null:
		return
	var clear: bool = camera.current_position().distance_to(anchor.global_position) > SIT_CLEAR_DISTANCE
	protagonist_sit.visible = clear and _protagonist_pose == &"sit"
	protagonist_stand.visible = clear and _protagonist_pose == &"stand"
	protagonist_look.visible = clear and _protagonist_pose == &"look_around"


## 第 0 步的“看见才发生”：玩家把视线转到侧前方课桌（或到兜底时间）时触发事件05。
func _check_gaze_events() -> void:
	if _gaze_events.is_empty() or get_tree().paused:
		return
	var forward := camera.forward()
	var eye := camera.current_position()
	var remaining: Array[Dictionary] = []
	for entry in _gaze_events:
		var gen: int = int(entry.get("gen", -1))
		if gen != _generation:
			continue
		var to_target: Vector3 = Vector3(entry["target"]) - eye
		if to_target.length_squared() < 0.0001:
			continue
		if rad_to_deg(forward.angle_to(to_target.normalized())) <= float(entry["angle"]):
			_fire_event(str(entry["id"]), gen)
			continue
		remaining.append(entry)
	_gaze_events = remaining


## 供无头检查：强制结束当前分支窗口（不经过 UI）。
func debug_choose(answer_text: String) -> void:
	_on_answer_submitted(answer_text)


func debug_choose_avoid() -> void:
	_on_avoid_chosen()


func debug_choose_struggle() -> void:
	_on_struggle()


## 供无头检查：已播放过的流程步号顺序（0–11，同号只记一次）。
func debug_played_steps() -> Array:
	return _played_steps.duplicate()


## 供无头检查：配音清单逐条解析结果（缺失文件不报错，只标记 exists=false）。
func debug_voice_report() -> Array:
	var report: Array = []
	for section in ["voice", "sfx"]:
		var table: Dictionary = _content.get(section, {}).get("cues", {})
		for key in table.keys():
			var path := _resolve_cue(section, str(key))
			report.append({
				"section": section,
				"id": str(key),
				"path": path,
				"exists": ResourceLoader.exists(path),
			})
	return report


## 供无头检查：配置里实际被引用的配音/音效 id（用于查漏登记与孤儿条目）。
func debug_voice_usage() -> Dictionary:
	var used := {"voice": {}, "sfx": {}}
	var add := func(section: String, key: String) -> void:
		if key.is_empty() or key.begins_with("res://"):
			return
		used[section][key] = true
	for source in ["beats", "ending", "branch_avoid"]:
		for beat in _content.get(source, []):
			_scan_beat_voice(beat, add)
	for event in _content.get("events", {}).values():
		var voice: Dictionary = event.get("voice", {})
		var kind := str(voice.get("kind", "speech"))
		add.call("voice" if kind == "speech" else "sfx", str(voice.get("cue", "")))
	# 第 8 步三条分支的老师回应与勉强开口的台词
	var choice: Dictionary = _content.get("choice", {})
	for branch_key in ["confident", "struggle", "avoid"]:
		var block: Dictionary = choice.get(branch_key, {})
		add.call("voice", str(block.get("teacher", {}).get("voice", "")))
	add.call("voice", str(choice.get("struggle_voice", "")))
	add.call("voice", str(choice.get("answer_fallback_voice", "")))
	var l2: Dictionary = _content.get("l2", {})
	add.call("voice", str(l2.get("rewind_voice", "")))
	for key in ["replay_confident", "replay_nervous"]:
		for line in l2.get(key, []):
			if line is Dictionary:
				add.call("voice", str(line.get("voice", "")))
	for observation in l2.get("observations", []):
		add.call("voice", str(observation.get("voice", "")))
	add.call("sfx", "murmur_loop") # 第 8 步选择窗口的议论纷纷底噪
	return used


func _scan_beat_voice(beat: Dictionary, add: Callable) -> void:
	for segment in beat.get("segments", []):
		add.call("voice", str(segment.get("voice", "")))


## 供无头检查：逻辑演员名 → 实际座位节点名（confident/nod/dissent 这类事件演员）。
func debug_actor_seat(actor: String) -> String:
	return str(_content.get("actors", {}).get(actor, ""))


## 供无头检查：当前阶段、分支、已触发事件与主角姿态。
func debug_event_labels() -> Array[String]:
	var labels: Array[String] = []
	for entry in _event_log:
		labels.append(str(entry.get("label", "")))
	return labels


func debug_branch() -> StringName:
	return _branch


func debug_protagonist_pose() -> StringName:
	return _protagonist_pose


## 供无头检查：L2 词条序列的正文（规划值，不随播放变化）。
func debug_l2_card_bodies() -> Array:
	var bodies: Array = []
	for card in _l2_cards:
		bodies.append(str(card.get("body", "")))
	return bodies


## 供无头检查：按生成代调度（与节拍同一套时间基准）。
## 定时回调统一绑定“当前节拍代号”：节拍被跳过、或被事件提前结束时，之前排好的
## 字幕 / 配音 / 姿态 / 音效不再补发。否则用「跳过」走过几步之后，上一节拍的字幕会
## 在几秒后突然弹出来盖住当前这句（观感上像字幕串台）。
func _schedule(seconds: float, callable: Callable) -> void:
	var gen := _generation
	var timer := get_tree().create_timer(maxf(seconds, 0.0) * time_scale, false)
	timer.timeout.connect(func() -> void:
		if gen != _generation:
			return
		callable.call()
	)
