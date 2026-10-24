extends SceneTree

## 课堂对话流程无头检查（主开发，2026-10-24）。
## 覆盖：初始状态（单环境/教师机位/第一人称相机/交头接耳铺垫）、L1 时间轴与事件、
## 躲避视线分支、输入回答分支、L2 第三人称与心流状态、跳过、暂停冻结、重开复位。
## 运行：Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/dialogue_check.gd

var _failures: int = 0

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
	await _check_initial()
	await _run_avoid_branch()
	await _run_answer_branch()
	await _check_skip_and_pause()
	await _check_restart()
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
	_check(
		_teacher.action == TeacherAnimator.Action.LECTURE,
		"Teacher opens lecturing to the class."
	)
	_check(
		_teacher.position.distance_to(Vector3(-2.8, 0.0, -3.05)) < 0.05,
		"Teacher opens at the podium facing the class."
	)
	# 相机：主角座位坐高，第一人称看向讲台
	_check(
		_camera.current_position().distance_to(Vector3(-0.7, 1.36, 1.78)) < 0.05,
		"Camera opens at the seated eye height."
	)
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


# ——— 分支一：躲避视线 ———

func _run_avoid_branch() -> void:
	_ui.get_node("Screen/CardPanel/Box/CardButtons/CardPrimary").pressed.emit()
	await _wait_until(func() -> bool: return _flow.stage == &"choice", 4000)
	_check(_flow.stage == &"choice", "L1 timeline reaches the choice window.")
	var labels := _flow.debug_event_labels()
	for expected in ["忽然安静下来", "被悄悄捡回来的笔", "E03｜轻声赞同", "被听成了另一个意思", "E02｜低笑", "听见不同意见"]:
		_check(labels.has(expected), "L1 fires event: " + expected)
	# 站起后相机升到站高
	_check(
		_camera.current_position().y > 1.6,
		"Camera rises to standing height while the protagonist answers."
	)
	# 选择窗口：同学们议论纷纷
	_check(_pose_of("SeatC10") == _pose_id("WHISPER_R"), "Classmates whisper during the choice window.")
	# 躲避视线分支
	_flow.debug_choose_avoid()
	await _wait_until(func() -> bool: return _flow.stage == &"ending" or _flow.stage == &"l2", 4000)
	_check(_flow.debug_branch() == &"avoid", "Avoid branch is recorded.")
	_check(_pose_of("SeatB06") == _pose_id("HEAD_DOWN"), "Busy-hands classmate keeps looking down.")
	await _wait_until(func() -> bool: return _flow.stage == &"l2", 4000)
	_check(_flow.stage == &"l2", "Ending reaches the second layer.")
	await _check_seated_sinks("ending")
	await _check_l2_state()
	await _wait_until(func() -> bool: return _flow.stage == &"complete", 8000)
	_check(_flow.stage == &"complete", "L2 cards finish at completion.")
	_check(not _flow_state.is_active(), "Completion leaves the flow state.")
	print("CHECK: avoid branch")


# ——— 分支二：输入回答 ———

func _run_answer_branch() -> void:
	_flow.restart()
	await process_frame
	_check(_flow.stage == &"intro", "Restart returns to the notice card.")
	_flow.time_scale = 0.05
	_ui.get_node("Screen/CardPanel/Box/CardButtons/CardPrimary").pressed.emit()
	await _wait_until(func() -> bool: return _flow.stage == &"choice", 4000)
	_ui.get_node("Screen/ChoicePanel/Box/AnswerButton").pressed.emit()
	await process_frame
	_check(
		_ui.get_node("Screen/ChoicePanel/Box/InputRow").visible,
		"Choosing to answer reveals the input row."
	)
	var input := _ui.get_node("Screen/ChoicePanel/Box/InputRow/Input") as LineEdit
	input.text = "认真试过的人，也可以保留停下的选择。"
	# 回答节拍按真实时长走，便于检查字幕；随后加速跑完剩余流程
	_flow.time_scale = 1.0
	_ui.get_node("Screen/ChoicePanel/Box/InputRow/Submit").pressed.emit()
	await process_frame
	await process_frame
	var line := _ui.get_node("Screen/SubtitleBar/Row/Line") as Label
	_check(line.text == input.text, "The typed answer is spoken as the protagonist.")
	_flow.time_scale = 0.05
	await _wait_until(func() -> bool: return _flow.stage == &"l2", 4000)
	_check(_flow.debug_branch() == &"answer", "Answer branch is recorded.")
	_check(
		_flow.debug_protagonist_pose() == &"sit",
		"Protagonist sits down before the second layer."
	)
	# L2 词条包含分支一的思绪倒放与对观察的观察
	var bodies := _flow.debug_l2_card_bodies()
	_check(bodies.has("我站得很直。"), "Confident replay line appears in the second layer.")
	_check(bodies.has("我能看见自己在紧张，光是看见，就平静了一点。"), "Observation cards appear.")
	await _wait_until(func() -> bool: return _flow.stage == &"complete", 8000)
	print("CHECK: answer branch")


# ——— 跳过与暂停 ———

func _check_skip_and_pause() -> void:
	_flow.restart()
	await process_frame
	_flow.time_scale = 0.05
	_ui.get_node("Screen/CardPanel/Box/CardButtons/CardPrimary").pressed.emit()
	await process_frame
	# 连续跳过整个 L1 时间轴
	for i in range(14):
		_flow.skip()
	_check(_flow.stage == &"choice", "Skip finishes every L1 beat and reaches the choice window.")
	_check(_flow.debug_event_labels().is_empty(), "Skipped beats do not fire events.")
	# 暂停冻结镜头
	_flow.debug_choose_avoid()
	await _wait_until(func() -> bool: return _flow.stage == &"ending" or _flow.stage == &"l2", 4000)
	await _wait_until(func() -> bool: return _flow.stage == &"l2", 4000)
	_flow.toggle_pause()
	await create_timer(0.25).timeout
	var frozen := _camera.camera.global_transform
	await create_timer(0.25).timeout
	_check(
		_camera.camera.global_transform.is_equal_approx(frozen),
		"Camera freezes while paused."
	)
	_flow.toggle_pause()
	await create_timer(0.2).timeout
	_check(not paused, "Resume clears the pause.")
	# 跳过 L1→L2 转场（重开后来到 ending 的最后一拍再跳）
	_flow.restart()
	await process_frame
	_ui.get_node("Screen/CardPanel/Box/CardButtons/CardPrimary").pressed.emit()
	for i in range(14):
		_flow.skip()
	_flow.debug_choose("停一下也可以。")
	for i in range(5):
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
	_check(
		_teacher.position.distance_to(Vector3(-2.8, 0.0, -3.05)) < 0.05,
		"Restart walks the teacher back to the podium."
	)
	_check(_teacher.action == TeacherAnimator.Action.LECTURE, "Restart resumes lecturing.")
	_check(not _flow_state.is_active(), "Restart leaves the flow state.")
	_check(_pose_of("SeatB06") == _pose_id("SIT"), "Restart resets event classmates.")
	_check(_pose_of("SeatC10") == _pose_id("WHISPER_R"), "Restart restores ambient whispers.")
	_check(_flow.debug_protagonist_pose() == &"sit", "Restart seats the protagonist.")
	var seated_self := _seating.get_node_or_null("ProtagonistSit") as Node3D
	_check(seated_self != null and not seated_self.visible, "Restart hides the protagonist again.")
	print("CHECK: restart")


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
