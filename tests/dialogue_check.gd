extends SceneTree

## 课堂对话流程无头检查（时序依据：流程控制(veryimportant).md 的 0–11）。
## 覆盖：初始状态、第 0 步自由转头与事件05、0–7 步顺序、唯一分支点的三个选项、
## 三条分支的第 8–11 步（E03 只在清晰回应后）、L2 回溯、跳过、暂停冻结、重开复位、
## 配音/音效清单（id 解析、漏登记、孤儿条目）。
## 运行：Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/dialogue_check.gd

var _failures: int = 0

## 教师开场站位（讲台台面上、铁讲台后方居中）。
const PODIUM_POS := Vector3(-0.35, 0.15, -4.35)

var _initial_look: Vector3 = Vector3.ZERO

var _main: Node = null
var _flow: DialogueFlow = null
var _camera: DialogueCamera = null
var _teacher: TeacherAnimator = null
var _ui: DialogueUI = null
var _flow_state: L2FlowState = null
var _seating: Node3D = null


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load("res://scenes/classroom_dialogue.tscn") as PackedScene
	if packed == null:
		_check(false, "classroom_dialogue.tscn could not be loaded.")
		quit(1)
		return
	_main = packed.instantiate()
	root.add_child(_main)
	for i in range(3):
		await process_frame
	_flow = _main.get_node_or_null("Flow") as DialogueFlow
	_camera = _main.get_node_or_null("CameraRig") as DialogueCamera
	_teacher = _main.get_node_or_null("Teacher") as TeacherAnimator
	_ui = _main.get_node_or_null("DialogueUI") as DialogueUI
	_flow_state = _main.get_node_or_null("L2FlowState") as L2FlowState
	_seating = _main.get_node_or_null("Seating") as Node3D
	if (
		_flow == null or _camera == null or _teacher == null or _ui == null
		or _flow_state == null or _seating == null
	):
		_check(false, "Missing dialogue modules.")
		quit(1)
		return
	_flow.time_scale = 0.05
	_flow_state.transition_seconds = 0.0
	_flow_state.isolation_seconds = 0.0
	await _check_initial()
	await _check_step_zero_free_look()
	await _run_confident_branch()
	await _run_struggle_branch()
	await _run_avoid_branch()
	await _check_skip_and_pause()
	await _check_restart()
	_check_voice_manifest()
	_main.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: dialogue flow checks completed.")
	quit(0 if _failures == 0 else 1)


# ——— 初始状态 ———

func _check_initial() -> void:
	_check(_flow.stage == &"intro", "Flow starts at the notice card.")
	# seating 自带的 WorldEnvironment/Daylight 应已被移除，场景里各剩一个
	var lighting := _count_lighting(_main)
	_check(
		int(lighting["environments"]) == 1,
		"Exactly one WorldEnvironment remains (got %d)." % int(lighting["environments"])
	)
	_check(
		int(lighting["directionals"]) == 1,
		"Exactly one directional light remains (got %d)." % int(lighting["directionals"])
	)
	# 教师：开场站在讲台前面对大家讲课（不背身板书、不移动）
	_check(_teacher.action == TeacherAnimator.Action.LECTURE, "Teacher opens lecturing to the class.")
	_check(
		_teacher.position.distance_to(PODIUM_POS) < 0.05,
		"Teacher opens in front of the podium facing the class."
	)
	# 相机：主角座位坐高，第一人称看向讲台
	_check(
		_camera.current_position().distance_to(Vector3(-0.7, 1.36, 1.78)) < 0.05,
		"Camera opens at the seated eye height."
	)
	_initial_look = _camera.look_target()
	# 主角模型在第一人称下隐藏
	var seated_self := _seating.get_node_or_null("ProtagonistSit") as Node3D
	_check(seated_self != null and not seated_self.visible, "Protagonist is hidden in first person.")
	# 所有受管理同学都必须正常下沉到座面（ apply_pose 重入曾把模型抬回“坐高” ）
	await _check_seated_sinks("intro")
	# 开场前已有同学交头接耳（为“忽然安静”铺垫）
	_check(_pose_of("SeatB04") == _pose_id("WHISPER_R"), "Ambient whisper pair murmurs before the call.")
	_check(_pose_of("SeatB05") == _pose_id("WHISPER_L"), "Ambient whisper partner leans the other way.")
	# 道具：笔在桌边，课本未出现
	var pen := _flow.get_node_or_null("Pen") as MeshInstance3D
	var textbook := _flow.get_node_or_null("Textbook") as MeshInstance3D
	_check(pen != null and pen.visible, "Pen prop rests on the desk edge.")
	_check(textbook != null and not textbook.visible, "Textbook is not on the podium yet.")
	print("CHECK: initial state")


# ——— 第 0 步：自由转头与事件05 ———

func _check_step_zero_free_look() -> void:
	_press_intro()
	await process_frame
	_check(_camera.is_free_look(), "Step 0 allows free look inside the frontal cone.")
	# 记录初始机位，确认转头只改朝向、不改机位
	var eye := _camera.current_position()
	_camera.nudge_free_look(-900.0, 900.0)
	var offset := _camera.free_look_offset()
	_check(
		is_equal_approx(offset.x, -_camera.free_look_yaw_limit)
		and is_equal_approx(offset.y, _camera.free_look_pitch_up),
		"Free look stays inside the frontal cone (got %s)." % str(offset)
	)
	_check(
		_camera.current_position().distance_to(eye) < 0.02,
		"Free look changes the view direction, not the camera position."
	)
	_camera.reset_free_look()
	# 转向侧前方课桌 → 事件05 提前触发（不必等兜底时间戳）
	_camera.nudge_free_look(16.5, -17.0)
	await process_frame
	await process_frame
	_check(_flow.debug_event_labels().has("有人还在忙自己的事"),
		"Looking at the busy desk fires event 05 (step 0)."
	)
	_check(_pose_of("SeatB06") == _pose_id("HEAD_DOWN"), "Busy-hands classmate keeps looking at his notebook.")
	# 朝向交给玩家：节拍推进不改注视点，玩家自己转的视角也不会被拉回
	_check(_camera.is_free_look(), "Free look stays available through the first-person steps.")
	var target := _camera.look_target()
	_camera.reset_free_look()
	_camera.nudge_free_look(-20.0, 0.0)
	_flow.skip()
	for i in range(90):
		await process_frame
	_check(
		_camera.look_target().is_equal_approx(target),
		"Beats do not steer the view direction."
	)
	_check(
		absf(_camera.free_look_offset().x) > 15.0,
		"The player's own turn is not recentered (%.1f)." % _camera.free_look_offset().x
	)
	_camera.reset_free_look()
	print("CHECK: step 0 free look and event 05")


# ——— 分支一：清晰回应 ———

func _run_confident_branch() -> void:
	await _wait_until(func() -> bool: return _flow.stage == &"choice", 6000)
	_check(_flow.stage == &"choice", "Steps 0-7 reach the choice window.")
	# 0–7 的时序
	var steps := _flow.debug_played_steps()
	_check(
		steps == [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0],
		"Steps 0-7 play in order (got %s)." % str(steps)
	)
	# 第 0–7 步应触发的事件；E03 与不同意见属于回答之后（第 9 步），此处不应出现
	var labels := _flow.debug_event_labels()
	for expected in ["有人还在忙自己的事", "忽然安静下来", "被悄悄捡回来的笔", "同学们三两回头看主角", "E02｜低笑", "03｜被听成了另一个意思"]:
		_check(labels.has(expected), "Steps 0-7 fire event: " + expected)
	for late in ["E03｜轻声赞同", "04｜听见不同意见"]:
		_check(not labels.has(late), "Event waits until after the answer: " + late)
	# 站起后相机升到站高
	_check(_camera.current_position().y > 1.6, "Camera rises to standing height while answering.")
	# 选择窗口：议论纷纷，三个选项；镜头交回固定构图
	_check(_pose_of("SeatC10") == _pose_id("WHISPER_R"), "Classmates whisper during the choice window.")
	_check(not _camera.is_free_look(), "Free look is released at the choice window.")
	_check(
		_camera.look_target().is_equal_approx(_initial_look),
		"No beat or event steers the view direction."
	)
	var panel := _ui.get_node("Screen/ChoicePanel/Box")
	for button_name in ["AnswerButton", "StruggleButton", "AvoidButton"]:
		var button := panel.get_node_or_null(button_name) as Button
		_check(button != null and button.visible, "Choice window shows " + button_name)
	# 清晰回应：输入并提交
	panel.get_node("AnswerButton").pressed.emit()
	await process_frame
	_check((panel.get_node("InputRow") as Control).visible, "Choosing to answer reveals the input row.")
	var input := panel.get_node("InputRow/Input") as LineEdit
	input.text = "认真试过的人，也可以保留停下的选择。"
	_flow.time_scale = 1.0
	panel.get_node("InputRow/Submit").pressed.emit()
	await process_frame
	await process_frame
	var line := _ui.get_node("Screen/SubtitleBar/Row/Line") as Label
	_check(line.text == input.text, "The typed answer is spoken as the protagonist.")
	_flow.time_scale = 0.05
	await _wait_until(func() -> bool: return _flow.stage == &"l2", 6000)
	_check(_flow.stage == &"l2", "Ending reaches the second layer.")
	_check(_flow.debug_branch() == &"confident", "Confident branch is recorded.")
	_check(
		_flow.debug_protagonist_pose() == &"sit",
		"Protagonist sits down before the second layer (step 10)."
	)
	# 第 9 / 9.1 步：不同意见 → 轻声赞同（只在清晰回应后）
	labels = _flow.debug_event_labels()
	_check(labels.has("04｜听见不同意见"), "Step 9 fires the dissent event after the answer.")
	_check(labels.has("E03｜轻声赞同"), "Step 9.1 fires the agreement only after a clear answer.")
	steps = _flow.debug_played_steps()
	for expected_step in [8.0, 9.0, 9.1, 10.0, 11.0]:
		_check(steps.has(expected_step), "Step %.1f is played." % expected_step)
	# L2：回溯到 0，再按分支倒放
	var bodies := _flow.debug_l2_card_bodies()
	_check(bodies.has("回到你被点到名字之前。"), "L2 starts by rewinding to step 0.")
	_check(bodies.has("我站得很直。"), "Confident replay line appears in the second layer.")
	_check(bodies.has("我能看见自己在紧张，光是看见，就平静了一点。"), "Observation cards appear.")
	await _check_seated_sinks("ending")
	await _check_l2_state()
	await _wait_until(func() -> bool: return _flow_state.is_l3(), 1200)
	_check(_flow_state.is_l3(), "Observation cards enter the L3 isolation.")
	await _wait_until(func() -> bool: return _flow.stage == &"complete", 12000)
	_check(_flow.stage == &"complete", "L2 cards finish at completion.")
	_check(not _flow_state.is_active(), "Completion leaves the flow state.")
	print("CHECK: confident branch")


# ——— 分支二之一：勉强开口 ———

func _run_struggle_branch() -> void:
	_restart_and_enter()
	await _wait_until(func() -> bool: return _flow.stage == &"choice", 6000)
	_check(_flow.stage == &"choice", "Restart reaches the choice window again.")
	_flow.time_scale = 1.0
	_flow.debug_choose_struggle()
	await process_frame
	await process_frame
	var line := _ui.get_node("Screen/SubtitleBar/Row/Line") as Label
	_check(
		line.text.begins_with("我……我是说"),
		"Struggle branch speaks the broken line (got \"%s\")." % line.text
	)
	_flow.time_scale = 0.05
	await _wait_until(func() -> bool: return _flow.stage == &"l2", 6000)
	_check(_flow.debug_branch() == &"struggle", "Struggle branch is recorded.")
	var labels := _flow.debug_event_labels()
	_check(labels.has("04｜听见不同意见"), "Struggle branch still hears the dissent (step 9).")
	_check(not labels.has("E03｜轻声赞同"), "Struggle branch has no agreement (E03 is step 9.1 only).")
	var bodies := _flow.debug_l2_card_bodies()
	_check(bodies.has("我的声音在抖。"), "Nervous replay line appears after a struggle.")
	_check(_flow.debug_played_steps().has(11.0), "Struggle branch still reaches step 11 (L2).")
	print("CHECK: struggle branch")


# ——— 分支二之二：躲开视线 ———

func _run_avoid_branch() -> void:
	_restart_and_enter()
	await _wait_until(func() -> bool: return _flow.stage == &"choice", 6000)
	_flow.debug_choose_avoid()
	await process_frame
	await process_frame
	_check(
		_flow.debug_protagonist_pose() == &"look_around",
		"Avoid branch looks around instead of answering (step 8)."
	)
	await _wait_until(func() -> bool: return _flow.stage == &"l2", 6000)
	_check(_flow.debug_branch() == &"avoid", "Avoid branch is recorded.")
	_check(_pose_of("SeatB06") == _pose_id("SIT"), "Classroom settles before the second layer.")
	var labels := _flow.debug_event_labels()
	_check(not labels.has("E03｜轻声赞同"), "Avoid branch has no agreement either.")
	_check(_flow.debug_l2_card_bodies().has("我的声音在抖。"), "Avoid branch uses the nervous replay.")
	await _check_l2_state()
	print("CHECK: avoid branch")


# ——— 跳过与暂停 ———

func _check_skip_and_pause() -> void:
	_restart_and_enter()
	await process_frame
	# 连续跳过整个 L1 时间轴（10 拍）
	for i in range(30):
		if _flow.stage == &"choice":
			break
		_flow.skip()
	_check(_flow.stage == &"choice", "Skip finishes every step and reaches the choice window.")
	_check(_flow.debug_event_labels().is_empty(), "Skipped beats do not fire events.")
	# 暂停冻结镜头
	_flow.debug_choose_avoid()
	await _wait_until(func() -> bool: return _flow.stage == &"l2", 6000)
	_flow.toggle_pause()
	await create_timer(0.25).timeout
	var frozen := _camera.camera.global_transform
	await create_timer(0.25).timeout
	_check(_camera.camera.global_transform.is_equal_approx(frozen), "Camera freezes while paused.")
	_flow.toggle_pause()
	await create_timer(0.2).timeout
	_check(not paused, "Resume clears the pause.")
	# 跳过第 11 步转场
	_flow.restart()
	await process_frame
	_press_intro()
	for i in range(30):
		if _flow.stage == &"choice":
			break
		_flow.skip()
	_flow.debug_choose("")
	await process_frame
	await process_frame
	var line := _ui.get_node("Screen/SubtitleBar/Row/Line") as Label
	_check(
		line.text.begins_with("认真试过的人"),
		"An empty answer falls back to the fixed line (got \"%s\")." % line.text
	)
	for i in range(12):
		if _flow.stage == &"l2":
			break
		_flow.skip()
	_check(_flow.stage == &"l2", "Skip through the transition lands in the second layer.")
	_check(_flow_state.is_active(), "Skipped transition still activates the flow state.")
	print("CHECK: skip and pause")


# ——— 重开复位 ———

func _check_restart() -> void:
	_flow.restart()
	await process_frame
	_check(_flow.stage == &"intro", "Restart returns to the notice card.")
	_check(
		_camera.current_position().distance_to(Vector3(-0.7, 1.36, 1.78)) < 0.05,
		"Restart snaps the camera back to the seat."
	)
	_check(not _camera.is_free_look(), "Restart disables free look.")
	_check(
		_teacher.position.distance_to(PODIUM_POS) < 0.05,
		"Restart walks the teacher back in front of the podium."
	)
	_check(_teacher.action == TeacherAnimator.Action.LECTURE, "Restart resumes lecturing.")
	_check(not _flow_state.is_active(), "Restart leaves the flow state.")
	_check(_pose_of("SeatB06") == _pose_id("SIT"), "Restart resets event classmates.")
	_check(_pose_of("SeatC10") == _pose_id("WHISPER_R"), "Restart restores ambient whispers.")
	_check(_flow.debug_protagonist_pose() == &"sit", "Restart seats the protagonist.")
	_check(_flow.debug_played_steps().is_empty(), "Restart clears the step record.")
	var seated_self := _seating.get_node_or_null("ProtagonistSit") as Node3D
	_check(seated_self != null and not seated_self.visible, "Restart hides the protagonist again.")
	print("CHECK: restart")


# ——— 配音清单 ———

func _check_voice_manifest() -> void:
	var report := _flow.debug_voice_report()
	_check(report.size() > 0, "Voice manifest is loaded.")
	var missing_path: Array[String] = []
	for entry in report:
		if str(entry["path"]).is_empty():
			missing_path.append(str(entry["id"]))
	_check(missing_path.is_empty(), "Every cue resolves to a path: " + ", ".join(missing_path))
	var usage: Dictionary = _flow.debug_voice_usage()
	var voice_used: Dictionary = usage["voice"]
	var sfx_used: Dictionary = usage["sfx"]
	var registered := {"voice": {}, "sfx": {}}
	for entry in report:
		registered[str(entry["section"])][str(entry["id"])] = true
	var unregistered: Array[String] = []
	for key in voice_used.keys():
		if not registered["voice"].has(key):
			unregistered.append("voice:" + str(key))
	for key in sfx_used.keys():
		if not registered["sfx"].has(key):
			unregistered.append("sfx:" + str(key))
	_check(unregistered.is_empty(), "No referenced cue is missing from the manifest: " + ", ".join(unregistered))
	var orphans: Array[String] = []
	for key in registered["voice"].keys():
		if not voice_used.has(key):
			orphans.append("voice:" + str(key))
	for key in registered["sfx"].keys():
		if not sfx_used.has(key):
			orphans.append("sfx:" + str(key))
	_check(orphans.is_empty(), "No orphan manifest entries: " + ", ".join(orphans))
	var present: Array[String] = []
	for entry in report:
		if bool(entry["exists"]):
			present.append(str(entry["id"]))
	# 录音文件尚未提交，这里只给出现状，不作为失败条件
	print("VOICE: %d cues registered, %d recorded (%s)" % [report.size(), present.size(), ", ".join(present)])
	print("CHECK: voice manifest")


# ——— L2 状态 ———

func _check_l2_state() -> void:
	await process_frame
	_check(
		_camera.current_position().distance_to(Vector3(0.0, 1.75, 2.9)) < 0.2,
		"L2 camera sits in the aisle behind the protagonist."
	)
	_check(_flow_state.is_active(), "L2 activates the flow state.")
	_check(_flow_state.get_clay_mesh_count() > 0, "L2 applies the clay material.")
	var seated_self := _seating.get_node_or_null("ProtagonistSit") as Node3D
	_check(seated_self != null and seated_self.visible, "L2 reveals the seated protagonist.")
	_check(_pose_of("SeatB06") == _pose_id("SIT"), "Classroom settles before the second layer.")


# ——— 坐姿下沉校验 ———

## 所有受管理同学的髋部都应落在座面高度（SEATED_HIP_HEIGHT=0.47）：
## apply_pose() 不可重入，重复调用会把已下沉的模型抬回“坐高”状态。
func _check_seated_sinks(where: String) -> void:
	await create_timer(0.3, true).timeout # 等 apply_pose 协程与下沉校正跑完（真实时间）
	var pose_script: Script = load("res://scripts/character_pose.gd")
	var constants: Dictionary = pose_script.get_script_constant_map()
	var seated: Array = constants.get("SEATED_POSES", [])
	var hip_height: float = float(constants.get("SEATED_HIP_HEIGHT", 0.47))
	var bad: Array[String] = []
	for seat in ["SeatB06", "SeatB07", "SeatB08", "SeatC06", "SeatD02", "SeatD03", "SeatB04", "SeatC10"]:
		var node := _seating.get_node_or_null(seat)
		if node == null:
			continue
		if not seated.has(int(node.pose)):
			continue
		var skeleton: Skeleton3D = null
		for sub in (node as Node3D).find_children("*", "Skeleton3D", true, false):
			skeleton = sub as Skeleton3D
			break
		if skeleton == null:
			continue
		var hips_idx := skeleton.find_bone("Hips")
		var hips_y: float = (
			skeleton.global_transform * skeleton.get_bone_global_pose(hips_idx)
		).origin.y
		if absf(hips_y - hip_height) > 0.02:
			bad.append("%s(%.2f)" % [seat, hips_y])
	_check(bad.is_empty(), "Seated classmates sit on the chair at " + where + ": " + ", ".join(bad))


# ——— 工具 ———

func _press_intro() -> void:
	var primary := _ui.get_node("Screen/CardPanel/Box/CardButtons/CardPrimary") as Button
	primary.pressed.emit()


func _restart_and_enter() -> void:
	_flow.restart()
	_flow.time_scale = 0.05
	_press_intro()


func _count_lighting(node: Node) -> Dictionary:
	var counts := {"environments": 0, "directionals": 0}
	if node is WorldEnvironment:
		counts["environments"] = int(counts["environments"]) + 1
	if node is DirectionalLight3D:
		counts["directionals"] = int(counts["directionals"]) + 1
	for child in node.get_children():
		var child_counts := _count_lighting(child)
		counts["environments"] = int(counts["environments"]) + int(child_counts["environments"])
		counts["directionals"] = int(counts["directionals"]) + int(child_counts["directionals"])
	return counts


func _pose_of(seat_name: String) -> int:
	var node := _seating.get_node_or_null(seat_name)
	if node == null:
		return -1
	return node.pose


func _pose_id(pose_name: String) -> int:
	var pose_script: Script = load("res://scripts/character_pose.gd")
	return int(pose_script.get_script_constant_map().get("Pose", {}).get(pose_name, -1))


func _wait_until(check: Callable, max_frames: int) -> void:
	for i in range(max_frames):
		if check.call():
			return
		await process_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
