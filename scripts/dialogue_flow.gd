class_name DialogueFlow
extends Node3D

## 课堂对话（事件四）流程与时间轴控制器（主开发，2026-10-24）。
##
## 阶段：intro → l1（第一人称时间轴） → choice（唯一分支点） → answer / avoid（分支演出）
##       → ending（坐下与收束） → l2（第三人称词条） → complete。
##
## 数据全部来自 content/classroom_dialogue.json：
## - beats：L1 节拍，每拍可带 teacher / teacher_at / protagonist / camera / cues / events / segments；
## - segments：字幕分段（speaker + text + seconds + 可选 voice 配音路径）；
## - events：六个补充事件与 E02/E03，按时间戳触发（姿态切换、台词、道具、词条）；
## - 配音：voice 路径存在时播放，节拍时长取 max(预留时长, 音频长度 + 0.25)，未接入时按预留时长走。
##
## 时间基准：所有定时器以 time_scale 缩放（无头检查用）；定时器不随暂停推进
## （create_timer 的 process_always=false），配合 _generation 代守卫，跳过/重开立即使旧回调失效。

signal stage_changed(stage_id: StringName)

const CHARACTER_POSE_PATH := "res://scripts/character_pose.gd"
const DEFAULT_CONTENT_PATH := "res://content/classroom_dialogue.json"
const REQUIRED_POSES := [
	"SIT", "SIDE_GLANCE_L", "SIDE_GLANCE_R", "COVER_MOUTH",
	"NOD", "WHISPER_L", "WHISPER_R", "HEAD_UP", "HEAD_DOWN",
]
const ACTION_IDS := {
	"LECTURE": TeacherAnimator.Action.LECTURE,
	"ASK": TeacherAnimator.Action.ASK,
	"CALL_ROLL": TeacherAnimator.Action.CALL_ROLL,
	"WRITE_BOARD": TeacherAnimator.Action.WRITE_BOARD,
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
var _pen: MeshInstance3D = null
var _textbook: MeshInstance3D = null


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
	interface.avoid_chosen.connect(_on_avoid_chosen)
	_place_teacher_opening()
	_build_props()
	_read_config()
	_reset_world()

# ——— 阶段推进 ———

func _start_l1() -> void:
	stage = &"l1"
	_beats = _content.get("beats", [])
	_beat_index = -1
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
	_set_ambient_whispers(true) # 同学们此时议论纷纷
	interface.show_choice(_content.get("choice", {}))
	_refresh_controls()
	stage_changed.emit(stage)


func _enter_ending() -> void:
	stage = &"ending"
	_beats = _content.get("ending", [])
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
	interface.clear_subtitle()
	interface.set_transition_text("")
	camera.set_scan(0.0)
	# 教师动作与走位
	var teacher_cue: Dictionary = beat.get("teacher", {})
	if teacher_cue.has("action"):
		teacher.set_state(
			ACTION_IDS.get(str(teacher_cue["action"]), TeacherAnimator.Action.LECTURE),
			EMOTION_IDS.get(str(teacher_cue.get("emotion", "NEUTRAL")), TeacherAnimator.Emotion.NEUTRAL)
		)
	var teacher_at := str(beat.get("teacher_at", ""))
	if teacher_at == "board":
		_move_teacher(_board_position, _walk_seconds)
	elif teacher_at == "podium":
		_move_teacher(_podium_position, _walk_seconds)
	# 主角姿态（第一人称下不可见，但驱动头部高度与 L2 状态）
	if beat.has("protagonist"):
		_set_protagonist_pose(str(beat["protagonist"]))
	# 镜头
	var cam: Dictionary = beat.get("camera", {})
	if cam.has("look"):
		_beat_look_target = _camera_target(str(cam["look"]))
		camera.set_look_target(_beat_look_target)
	if cam.has("scan"):
		camera.set_scan(float(cam["scan"]))
	if cam.get("third_person", false):
		camera.transition_to(_l2_position, _camera_target("self_head"), _l2_seconds * time_scale)
	if beat.has("transition_text"):
		interface.set_transition_text(str(beat["transition_text"]))
	# 通用 cue
	for cue in beat.get("cues", []):
		_schedule(float(cue.get("at", 0.0)), func(): _run_cue(str(cue["do"]), gen))
	# 时间戳事件
	for event_cue in beat.get("events", []):
		_schedule(float(event_cue.get("at", 0.0)), func(): _fire_event(str(event_cue["id"]), gen))
	# 字幕分段与配音预留（segments 可带 at 指定偏移，否则顺序衔接）
	var t := 0.0
	var voice_length := 0.0
	for segment in beat.get("segments", []):
		var seg: Dictionary = segment
		var seg_seconds := float(seg.get("seconds", 1.0))
		var seg_at := float(seg.get("at", t))
		_schedule(seg_at, func(): _show_segment(seg))
		if str(seg.get("voice", "")) != "":
			_schedule(seg_at, func(): _play_voice(str(seg["voice"])))
			voice_length = maxf(voice_length, _voice_length(str(seg["voice"])))
		t = seg_at + seg_seconds
	var hold := float(beat.get("hold", t))
	hold = maxf(hold, voice_length + 0.25)
	_schedule(hold, func(): _finish_beat_if(gen))
	_refresh_controls()


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
	var event: Dictionary = _content.get("events", {}).get(event_id, {})
	if event.is_empty():
		push_warning("DialogueFlow: 未知事件 " + event_id)
		return
	# 第二层词条：事件发生时登记，L2 回看
	_event_log.append({
		"label": str(event.get("label", event_id)),
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
	# 同学姿态（可带 recover 回到坐姿）
	for pose_cue in event.get("poses", []):
		var pose: Dictionary = pose_cue
		_schedule(float(pose.get("at", 0.0)), func(): _set_actor_pose(str(pose["actor"]), str(pose["pose"])))
		if pose.has("recover"):
			_schedule(
				float(pose["recover"]), func(): _set_actor_pose(str(pose["actor"]), "SIT")
			)
	# 第一层声音：speech 走字幕条，ambient 只放音频
	var voice: Dictionary = event.get("voice", {})
	if not voice.is_empty():
		var voice_at := float(voice.get("at", 0.0))
		if str(voice.get("kind", "speech")) == "speech":
			_schedule(voice_at, func(): _show_segment({
				"speaker": str(voice.get("speaker", "classmate")),
				"text": str(voice.get("text", "")),
				"seconds": float(voice.get("seconds", 2.0)),
			}))
		if str(voice.get("audio", "")) != "":
			_schedule(voice_at, func(): _play_voice(str(voice["audio"])))
	# 道具
	for prop_cue in event.get("props", []):
		var prop: Dictionary = prop_cue
		_schedule(
			float(prop.get("at", 0.0)),
			func(): _apply_prop_action(str(prop["prop"]), str(prop["action"]))
		)
	# 镜头吸引：第一人称下邻座/后排不在默认画面里，事件时“转头看向”，结束后回位
	var event_camera: Dictionary = event.get("camera", {})
	if event_camera.has("look"):
		camera.set_look_target(_camera_target(str(event_camera["look"])))
		if event_camera.has("recover"):
			var recover_after := float(event_camera["recover"])
			_schedule(recover_after, func(): camera.set_look_target(_beat_look_target))


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


# ——— 分支 ———

func _on_answer_submitted(text: String) -> void:
	if stage != &"choice":
		return
	stage = &"answer"
	_branch = &"answer"
	interface.hide_choice()
	var choice: Dictionary = _content.get("choice", {})
	var line := text.strip_edges()
	if line.is_empty():
		line = str(choice.get("answer_fallback", ""))
	var per_char := float(choice.get("answer_seconds_per_char", 4.6))
	var seconds := clampf(
		line.length() / per_char,
		float(choice.get("answer_min_seconds", 2.5)),
		float(choice.get("answer_max_seconds", 12.0))
	)
	var accept: Dictionary = choice.get("teacher_accept", {})
	var answer_beats: Array[Dictionary] = []
	answer_beats.append({
		"id": "player_answer",
		"hold": seconds + 0.4,
		"teacher": {"action": "LECTURE", "emotion": "NEUTRAL"},
		"segments": [{"speaker": "protagonist", "text": line, "seconds": seconds}],
	})
	answer_beats.append({
		"id": "teacher_accept",
		"hold": float(accept.get("seconds", 3.8)) + 0.3,
		"teacher": {
			"action": str(accept.get("action", "LECTURE")),
			"emotion": str(accept.get("emotion", "HAPPY")),
		},
		"segments": [{
			"speaker": "teacher",
			"text": str(accept.get("text", "")),
			"seconds": float(accept.get("seconds", 3.8)),
			"voice": str(accept.get("voice", "")),
		}],
	})
	_beats = answer_beats
	_beat_index = -1
	_advance_phase()
	_refresh_controls()


func _on_avoid_chosen() -> void:
	if stage != &"choice":
		return
	stage = &"avoid"
	_branch = &"avoid"
	interface.hide_choice()
	_beats = _content.get("branch_avoid", [])
	_beat_index = -1
	_advance_phase()
	_refresh_controls()


# ——— L2 词条序列 ———

func _build_l2_cards() -> void:
	_l2_cards.clear()
	var l2: Dictionary = _content.get("l2", {})
	var base := float(l2.get("card_base_seconds", 1.8))
	var per_line := float(l2.get("card_seconds_per_line", 0.55))
	# 1) 事件词条：主角想法
	for entry in _event_log:
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
		l2.get("replay_confident", []) if _branch == &"answer" else l2.get("replay_nervous", [])
	)
	var replay_title := str(l2.get("replay_title", "思绪倒放"))
	for line in replay:
		_l2_cards.append({"title": replay_title, "body": str(line), "seconds": 2.6})
	# 3) 对观察的观察（心理概念）
	var observation_title := str(l2.get("observations_title", "对观察的观察"))
	for observation in l2.get("observations", []):
		var obs: Dictionary = observation
		_l2_cards.append({
			"title": observation_title + " · " + str(obs.get("concept", "")),
			"body": str(obs.get("line", "")),
			"seconds": 3.0,
			"isolate": true,
		})


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
	_schedule(float(card.get("seconds", 2.8)), func(): _next_card_if(gen))
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
	_reset_managed_actors()
	_set_ambient_whispers(true) # 开场前教室里本就有低声交谈
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
	_beat_look_target = _camera_target("podium_teacher")
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


func _set_actor_pose(actor: String, pose: String) -> void:
	var pose_id: int = _pose_ids.get(pose, -1)
	if pose_id < 0:
		push_warning("DialogueFlow: 未知姿态 " + pose)
		return
	var node := _actor_node(actor)
	if node == null:
		push_warning("DialogueFlow: 找不到演员节点 " + actor)
		return
	if int(node.pose) == pose_id:
		return # 姿态未变：跳过，避免无意义地重跑 apply_pose（其内部会先把模型抬回未下沉位）
	node.pose = pose_id
	node.apply_pose()
	_schedule_sink_check(node)


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

func _move_teacher(target: Vector3, seconds: float) -> void:
	if _teacher_tween != null and _teacher_tween.is_valid():
		_teacher_tween.kill()
	if seconds <= 0.0:
		teacher.position = target
		return
	var from := teacher.position
	_teacher_tween = teacher.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_teacher_tween.tween_method(
		func(value: Vector3) -> void: teacher.position = value, from, target, seconds * time_scale
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
	match action:
		"fall":
			_tween_prop(_pen, _vec(pen_cfg.get("floor_position", [0, 0, 0])), 0.55, true)
		"return":
			_tween_prop(_pen, _vec(pen_cfg.get("return_position", [0, 0, 0])), 0.45, false)


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


# ——— 配音挂载 ———

func _play_voice(path: String) -> void:
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var stream: Variant = load(path)
	if not stream is AudioStream:
		return
	if _voice == null:
		_voice = AudioStreamPlayer.new()
		add_child(_voice)
	_voice.stream = stream as AudioStream
	_voice.play()


func _voice_length(path: String) -> float:
	if path.is_empty() or not ResourceLoader.exists(path):
		return 0.0
	var stream: Variant = load(path)
	if not stream is AudioStream:
		return 0.0
	return (stream as AudioStream).get_length()


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
	var anchor := protagonist_sit.get_node_or_null("ViewAnchor") as Node3D if protagonist_sit != null else null
	if anchor == null:
		return
	var clear: bool = camera.current_position().distance_to(anchor.global_position) > SIT_CLEAR_DISTANCE
	protagonist_sit.visible = clear and _protagonist_pose == &"sit"
	protagonist_stand.visible = clear and _protagonist_pose == &"stand"
	protagonist_look.visible = clear and _protagonist_pose == &"look_around"


## 供无头检查：强制结束当前分支窗口（不经过 UI）。
func debug_choose(answer_text: String) -> void:
	_on_answer_submitted(answer_text)


func debug_choose_avoid() -> void:
	_on_avoid_chosen()


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
func _schedule(seconds: float, callable: Callable) -> void:
	var timer := get_tree().create_timer(maxf(seconds, 0.0) * time_scale, false)
	timer.timeout.connect(callable)
