extends SceneTree

## 课堂对话流程无头检查（时序依据：流程控制(veryimportant).md 的 0–11）。
## 覆盖：初始状态、第 0 步自由转头、第 5 步事件05（视线触发）、0–7 步顺序、第 8 步单框回答
## （改写 / 空文本回退）、第 9–11 步固定后续（E03 无条件出现）、L2 回溯、跳过、暂停冻结、重开复位、
## 配音/音效清单（id 解析、漏登记、孤儿条目）。
## 运行：Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/dialogue_check.gd

var _failures: int = 0

## 教师开场站位（讲台台面上、铁讲台后方居中）。
## 与 content/classroom_dialogue.json 的 teacher.podium_position 保持一致；
## 教室前区布局调整后（铁讲台前移到 z≈-1.5），站位随之改为 (-0.2, 0.15, -2.8)。
const PODIUM_POS := Vector3(-0.2, 0.15, -2.8)

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
	root.size = Vector2i(1280, 720)
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
	await _check_pose_transition()
	await _check_step_zero_free_look()
	await _check_step_five_busy_hands()
	await _run_answer_flow()
	await _run_empty_answer_flow()
	await _check_skip_and_pause()
	await _check_restart()
	await _check_world_panel_click()
	await _check_transient_fx_entries()
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
	# 开场不是全班端坐：有人写字（拿笔）、有人看书、有人抬头听讲
	_check(_pose_of("SeatB03") == _pose_id("WRITING"), "Someone in the front row is writing at the open.")
	_check(_pose_of("SeatB01") == _pose_id("READ"), "Someone in the front row is reading a textbook.")
	_check(_pose_of("SeatB02") == _pose_id("SIT"), "Someone in the front row simply listens to the lecture.")
	_check(_pose_of("SeatC06") == _pose_id("WRITING"), "The desk neighbour is writing at the open.")
	# 桌面道具跟着姿态走：写字的人有本子和笔，看书的人有课本
	var desk_props := _flow.get_node_or_null("DeskProps") as Node3D
	_check(desk_props != null and desk_props.get_child_count() >= 20, "Every varied seat gets desk props.")
	if desk_props != null:
		var writer := desk_props.get_node_or_null("Desk_SeatB03") as Node3D
		_check(
			writer != null and writer.get_node_or_null("PropNotebook") != null
			and writer.get_node_or_null("PropPen") != null,
			"A writing classmate has a notebook and a pen on the desk."
		)
		var reader := desk_props.get_node_or_null("Desk_SeatB01") as Node3D
		_check(
			reader != null and reader.get_node_or_null("PropTextbook") != null,
			"A reading classmate has a textbook on the desk."
		)
		if writer != null:
			var note := writer.get_node("PropNotebook") as Node3D
			_check(
				absf(note.global_position.y - 0.782) < 0.02,
				"The notebook rests on the desk top (y=%.3f)." % note.global_position.y
			)
	# 道具：笔在桌边，课本未出现
	var pen := _flow.get_node_or_null("Pen") as MeshInstance3D
	var textbook := _flow.get_node_or_null("Textbook") as MeshInstance3D
	_check(pen != null and pen.visible, "Pen prop rests on the desk edge.")
	_check(textbook != null and not textbook.visible, "Textbook is not on the podium yet.")
	print("CHECK: initial state")


# ——— 姿态切换必须是过渡，不是瞬切 ———

## 静态姿态没有动画层，切换靠 character_pose.gd 的骨骼 slerp。
## 这里切一次 PICK_UP，在过渡中途取样：头的朝向应当处在起点与终点之间。
func _check_pose_transition() -> void:
	var node := _seating.get_node_or_null("SeatB10") as Node3D
	if node == null:
		_check(false, "Missing seat for the pose transition check.")
		return
	_check(
		is_equal_approx(float(node.get("pose_transition_seconds")), 0.5),
		"The classroom takes the pose transition time from content."
	)
	var skeleton := _skeleton_of(node)
	if skeleton == null:
		_check(false, "Seat has no skeleton.")
		return
	var head := skeleton.find_bone("Head")
	node.pose = _pose_id("SIT")
	node.apply_pose()
	await create_timer(0.1).timeout
	var from_basis := _head_basis(skeleton, head)
	node.pose = _pose_id("PICK_UP")
	node.apply_pose()
	await create_timer(0.15).timeout
	var mid_basis := _head_basis(skeleton, head)
	await create_timer(0.7).timeout
	var end_basis := _head_basis(skeleton, head)
	# 瞬切的参照值：同样的目标姿态，把过渡时间关掉再摆一次
	node.pose = _pose_id("SIT")
	node.set("pose_transition_seconds", 0.0)
	node.apply_pose()
	node.pose = _pose_id("PICK_UP")
	node.apply_pose()
	var instant_basis := _head_basis(skeleton, head)
	node.pose = _pose_id("SIT")
	node.apply_pose()
	node.set("pose_transition_seconds", 0.5)
	var total := rad_to_deg(from_basis.get_rotation_quaternion().angle_to(end_basis.get_rotation_quaternion()))
	var passed := rad_to_deg(from_basis.get_rotation_quaternion().angle_to(mid_basis.get_rotation_quaternion()))
	var settle := rad_to_deg(end_basis.get_rotation_quaternion().angle_to(instant_basis.get_rotation_quaternion()))
	_check(total > 12.0, "The pose change is visible (head turns %.1f deg)." % total)
	_check(
		passed > 2.0 and passed < total * 0.85,
		"Pose change eases over time instead of snapping (%.1f of %.1f deg after 0.15 s)." % [passed, total]
	)
	_check(settle < 2.0, "The eased pose lands on the instant pose (%.2f deg off)." % settle)
	print("CHECK: pose transition (head %.1f deg total, %.1f deg after 0.15 s)" % [total, passed])


func _skeleton_of(node: Node) -> Skeleton3D:
	for sub in node.find_children("*", "Skeleton3D", true, false):
		return sub as Skeleton3D
	return null


func _head_basis(skeleton: Skeleton3D, head: int) -> Basis:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(head)).basis


# ——— 第 0 步：自由转头 ———

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
	# 第 0 步没有要“看见才发生”的事件（事件05 已挪到第 5 步）
	_check(
		not _flow.debug_event_labels().has("有人还在忙自己的事"),
		"Step 0 no longer fires event 05; it belongs to step 5."
	)
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
	print("CHECK: step 0 free look")


# ——— 第 5 步：事件05「有人还在忙自己的事」 ———

## 事件05 与「同学们三两回头看主角」同步在第 5 步。主角正在回答，镜头仍对着老师，
## 侧前方的课桌要玩家自己转过去才看得到——所以它带 gaze：转到位就提前触发，
## 2.6 s 兜底。同时，那个低头的人不能和回头的人是同一个座位。
func _check_step_five_busy_hands() -> void:
	_flow.restart()
	await process_frame
	_press_intro()
	# 不跳过：跳过会连带作废第 3 步的事件（relief / quiet / pen_fall），
	# 这里让时间轴按 time_scale 自然走到第 5 步。
	await _wait_until(_at_step_five, 900)
	var steps := _flow.debug_played_steps()
	_check(
		not steps.is_empty() and is_equal_approx(float(steps[steps.size() - 1]), 5.0),
		"Step 5 is reached with the earlier beats intact (got %s)." % str(steps)
	)
	_check(
		_flow.debug_actor_seat("busy_hands") != _flow.debug_actor_seat("glance_a"),
		"The busy neighbour is not the first one turning back (%s vs %s)."
		% [_flow.debug_actor_seat("busy_hands"), _flow.debug_actor_seat("glance_a")]
	)
	# 像玩家那样把视线转到侧前方的课桌：按当前朝向算出还差多少，再一次性转过去
	var target := _flow.debug_camera_target("busy_desk")
	var eye := _camera.current_position()
	var local := _camera.camera.global_transform.basis.inverse() * (target - eye)
	var yaw := -rad_to_deg(atan2(local.x, -local.z))
	var pitch := rad_to_deg(atan2(local.y, sqrt(local.x * local.x + local.z * local.z)))
	_camera.nudge_free_look(yaw, pitch)
	await process_frame
	await process_frame
	_check(
		_flow.debug_event_labels().has("有人还在忙自己的事"),
		"Looking at the busy desk fires event 05 (step 5, gaze trigger) — turned %s." % str(_camera.free_look_offset())
	)
	_check(
		_pose_of("SeatB06") == _pose_id("HEAD_DOWN"),
		"Busy-hands classmate keeps looking at his notebook."
	)
	_camera.reset_free_look()
	await process_frame
	print("CHECK: step 5 event 05")



# ——— 互动提示坐标（内容静态校验） ———

## 8 个可观察事件必须在站立后默认朝向的视野内，彼此不挤在一起；
## 环境事件（忽然安静 / 课堂往下走）明确不出提示。
func _check_orb_content() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/classroom_dialogue.json")
	)
	if not parsed is Dictionary:
		_check(false, "Could not read orb positions from content.")
		return
	var events: Dictionary = (parsed as Dictionary).get("events", {})
	var expected := ["pen_fall", "relief", "look_back", "busy_hands", "e02_laugh", "misheard", "dissent", "e03_nod"]
	var eye := Vector3(-0.7, 1.70, 1.78)
	var forward := (PODIUM_POS + Vector3(0.0, 1.37, 0.0) - eye).normalized()
	var points: Array[Vector3] = []
	for event_id in expected:
		var event: Dictionary = events.get(event_id, {})
		_check(event.has("orb_position"), "%s has an explicit orb_position." % event_id)
		if not event.has("orb_position"):
			continue
		var raw: Array = event["orb_position"]
		var point := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
		points.append(point)
		var az := _azimuth(eye, forward, point)
		_check(
			absf(float(az["yaw"])) <= 60.0 and float(az["pitch"]) <= 18.0 and -float(az["pitch"]) <= 40.0,
			"%s's marker stays in the normal view (yaw %.1f, pitch %.1f)." % [event_id, az["yaw"], az["pitch"]]
		)
	for i in range(points.size()):
		for j in range(i + 1, points.size()):
			_check(
				points[i].distance_to(points[j]) >= 0.5,
				"Markers %s and %s do not overlap (%.2f m)." % [expected[i], expected[j], points[i].distance_to(points[j])]
			)
	for quiet_id in ["quiet", "class_moves_on"]:
		_check(
			not bool((events.get(quiet_id, {}) as Dictionary).get("orb", true)),
			"%s is an environment event and has no marker." % quiet_id
		)


# ——— 第 8 步：改写回答 → 固定后续 ———

func _run_answer_flow() -> void:
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
	for expected in ["有人还在忙自己的事", "同学们稍微松了口气", "忽然安静下来", "被悄悄捡回来的笔", "同学们三两回头看主角", "E02｜低笑", "03｜被听成了另一个意思"]:
		_check(labels.has(expected), "Steps 0-7 fire event: " + expected)
	for late in ["E03｜轻声赞同", "04｜听见不同意见"]:
		_check(not labels.has(late), "Event waits until after the answer: " + late)
	# 低笑 / 赞同 / 不同意见必须发生在主角正前方的四个同学里，否则第一人称看不见
	_check_front_seats_visible()
	# 站起后相机升到站高
	_check(_camera.current_position().y > 1.6, "Camera rises to standing height while answering.")
	# 选择窗口：议论纷纷；回答只做一个输入框，且视角仍可自由转动
	_check(_pose_of("SeatC10") == _pose_id("WHISPER_R"), "Classmates whisper during the choice window.")
	_check(_camera.is_free_look(), "The answer box keeps free look available.")
	_check(not _camera.is_keyboard_look(), "Arrow keys move the answer caret instead of the view.")
	_check(
		_camera.look_target().is_equal_approx(_initial_look),
		"No beat or event steers the view direction."
	)
	_check_orb_content()
	var panel := _ui.get_node("Screen/ChoicePanel/Box")
	_check((_ui.get_node("Screen/ChoicePanel") as Control).visible, "Choice window shows one answer card.")
	var input := panel.get_node("InputRow/Input") as TextEdit
	_check(input.visible, "The answer input is visible immediately.")
	_check(not input.text.is_empty(), "The answer input is prefilled with the fallback line.")
	_check(not panel.has_node("AnswerButton"), "The old three-way answer buttons are gone.")
	# 改写并提交
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
	_check(
		_flow.debug_protagonist_pose() == &"sit",
		"Protagonist sits down before the second layer (step 10)."
	)
	# 第 9 / 9.1 步：不同意见 → 轻声赞同（不再看回答内容）
	labels = _flow.debug_event_labels()
	_check(labels.has("04｜听见不同意见"), "Step 9 fires the dissent event after the answer.")
	_check(labels.has("E03｜轻声赞同"), "Step 9.1 fires the agreement for every answer.")
	steps = _flow.debug_played_steps()
	for expected_step in [8.0, 9.0, 9.1, 10.0, 11.0]:
		_check(steps.has(expected_step), "Step %.1f is played." % expected_step)
	# L2：回溯到 0，再倒放（只有一套文案）
	var bodies := _flow.debug_l2_card_bodies()
	_check(bodies.has("回到你被点到名字之前。"), "L2 starts by rewinding to step 0.")
	_check(
		bodies.has("我站起来的时候，手扶着桌沿。"),
		"The single replay set appears in the second layer."
	)
	_check(bodies.has("我能看见自己在紧张，光是看见，就平静了一点。"), "Observation cards appear.")
	await _check_seated_sinks("ending")
	await _check_l2_state()
	await _wait_until(func() -> bool: return _flow_state.is_l3(), 1200)
	_check(_flow_state.is_l3(), "Observation cards enter the L3 isolation.")
	await _wait_until(func() -> bool: return _flow.stage == &"complete", 12000)
	_check(_flow.stage == &"complete", "L2 cards finish at completion.")
	_check(not _flow_state.is_active(), "Completion leaves the flow state.")
	print("CHECK: answer flow")


# ——— 演员位置：默认视角内，或转到头就能看见 ———

## 低笑 / 赞同 / 不同意见这三件事的演员，必须是主角正前方第一排的四个人之一，
## 并且默认镜头（垂直 FOV 65°、16:9）里能看到，否则第一人称根本看不见。
## 事件05 那个低头的人也在这一排（他不回头，但必须在这个视角里，玩家一转头就看得到）。
## 捡笔的是同桌（正左侧 90°），不靠默认视角，而是靠放宽后的自由转头；
## 这里校验“把视线转到底时，他弯腰的位置确实进得了画面”。
func _check_front_seats_visible() -> void:
	var front := ["SeatB05", "SeatB06", "SeatB07", "SeatB08"]
	var eye := _camera.current_position()
	var forward := _camera.forward()
	var half_h := rad_to_deg(atan(tan(deg_to_rad(_camera.fov * 0.5)) * 16.0 / 9.0))
	var half_v := _camera.fov * 0.5
	for actor in ["laugh", "nod", "dissent", "busy_hands"]:
		var seat := _flow.debug_actor_seat(actor)
		_check(front.has(seat), "%s happens in the four seats in front (got %s)." % [actor, seat])
		var node := _seating.get_node_or_null(seat) as Node3D
		if node == null:
			_check(false, "Missing front-seat node for " + actor)
			continue
		var to_head := node.global_position + Vector3(0.0, 1.05, 0.0) - eye
		var angle := rad_to_deg(forward.angle_to(to_head.normalized()))
		_check(
			angle < half_h - 6.0,
			"%s is inside the default frame (%.1f deg, limit %.1f)." % [actor, angle, half_h - 6.0]
		)
	# 回头的三个人仍在前排（默认视角里就是这四个人）
	for actor in ["glance_a", "glance_b", "glance_c"]:
		_check(
			front.has(_flow.debug_actor_seat(actor)),
			"%s is staged in the front row (got %s)." % [actor, _flow.debug_actor_seat(actor)]
		)
	# 捡笔的人 = 同桌，就在左手边；画面靠自由转头，不靠默认构图
	var mate_seat := _flow.debug_actor_seat("pen_deskmate")
	_check(mate_seat == "SeatC06", "捡笔的是同桌 SeatC06（got %s）." % mate_seat)
	var mate := _seating.get_node_or_null("SeatC06") as Node3D
	if mate == null:
		_check(false, "Missing desk-neighbour node for pen_deskmate.")
		return
	# 站着看他弯腰时的头，和坐回去之后的头，两个位置都要能看到
	for point in [mate.global_position + Vector3(0.0, 1.05, 0.0),
			mate.global_position + Vector3(0.0, 0.55, -0.30)]:
		var az := _azimuth(eye, forward, point)
		var yaw_ok := absf(float(az["yaw"])) <= _camera.free_look_yaw_limit + half_h - 6.0
		var pitch_ok := (
			float(az["pitch"]) <= _camera.free_look_pitch_up + half_v - 6.0
			and -float(az["pitch"]) <= _camera.free_look_pitch_down + half_v - 6.0
		)
		_check(
			yaw_ok and pitch_ok,
			"The desk neighbour is reachable by free look (yaw %.1f, pitch %.1f)." % [az["yaw"], az["pitch"]]
		)


## 目标点相对当前朝向的偏航（正 = 向左）与俯仰（正 = 向上），单位度。
func _azimuth(eye: Vector3, forward: Vector3, point: Vector3) -> Dictionary:
	var flat := Vector3(point.x - eye.x, 0.0, point.z - eye.z)
	if flat.length() < 0.001:
		return {"yaw": 0.0, "pitch": 90.0}
	var fwd := Vector3(forward.x, 0.0, forward.z).normalized()
	var yaw := rad_to_deg(fwd.signed_angle_to(flat.normalized(), Vector3.UP))
	var pitch := rad_to_deg(atan2(point.y - eye.y, flat.length()))
	return {"yaw": yaw, "pitch": pitch}


# ——— 第 8 步：空文本提交也走默认回答 ———

func _run_empty_answer_flow() -> void:
	_restart_and_enter()
	await _wait_until(func() -> bool: return _flow.stage == &"choice", 6000)
	_check(_flow.stage == &"choice", "Restart reaches the answer box again.")
	_flow.time_scale = 1.0
	_flow.debug_choose("")
	await process_frame
	await process_frame
	var line := _ui.get_node("Screen/SubtitleBar/Row/Line") as Label
	_check(
		line.text.begins_with("认真试过的人"),
		"An empty answer falls back to the default line (got \"%s\")." % line.text
	)
	_flow.time_scale = 0.05
	await _wait_until(func() -> bool: return _flow.stage == &"l2", 8000)
	_check(_flow.stage == &"l2", "An empty answer still reaches the second layer.")
	var labels := _flow.debug_event_labels()
	_check(labels.has("04｜听见不同意见"), "Step 9 fires the dissent after an empty answer.")
	_check(labels.has("E03｜轻声赞同"), "E03 fires no matter what was answered.")
	_check(
		_flow.debug_l2_card_bodies().has("我站起来的时候，手扶着桌沿。"),
		"The same replay set is used for an empty answer."
	)
	print("CHECK: empty answer")


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
	# 跳过之后，被跳过节拍里排好的字幕不能再补发（曾会因为计时器跨节拍存活，
	# 在几秒后弹出上一节拍的字幕，把当前这句盖掉）。
	var subtitle := _ui.get_node("Screen/SubtitleBar") as Control
	await create_timer(1.5).timeout
	_check(not subtitle.visible, "Skipped beats do not leak subtitles into the choice window.")
	# 暂停冻结镜头
	_flow.debug_choose("")
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
	_check(_pose_of("SeatB06") == _pose_id("WRITING"), "Restart restores the opening classroom state.")
	_check(_pose_of("SeatB01") == _pose_id("READ"), "Restart restores the reading classmate.")
	_check(_pose_of("SeatC10") == _pose_id("WHISPER_R"), "Restart restores ambient whispers.")
	_check(_flow.debug_protagonist_pose() == &"sit", "Restart seats the protagonist.")
	_check(_flow.debug_played_steps().is_empty(), "Restart clears the step record.")
	var seated_self := _seating.get_node_or_null("ProtagonistSit") as Node3D
	_check(seated_self != null and not seated_self.visible, "Restart hides the protagonist again.")
	# 上一轮的事件小球属于上一轮的观察记录，复位时必须清掉（否则会一轮轮叠加）
	var world := _main.get_node_or_null("WorldUI")
	var orbs := 0
	if world != null:
		for child in world.get_children():
			if child is EventOrb3D:
				orbs += 1
	_check(orbs == 0, "Restart clears the previous run's observation orbs (got %d)." % orbs)
	print("CHECK: restart")


# ——— 世界面板的真实鼠标点击 ———

## 不直接 emit Button.pressed，而是从三维面片中心反推屏幕坐标，走一遍
## “相机射线 → 面板坐标 → SubViewport GUI”的真实点击路径。
func _check_world_panel_click() -> void:
	_flow.restart()
	await process_frame
	await create_timer(0.35).timeout
	var record: Dictionary = {}
	for panel in _ui._panels:
		if panel["control"] == _ui.card_panel:
			record = panel
			break
	_check(not record.is_empty(), "The intro card has a world-space surface.")
	if record.is_empty():
		return
	var region := record["region"] as Rect2
	var center := (_ui.card_primary as Button).get_global_rect().get_center()
	var local := Vector3(
		((center.x - region.position.x) / region.size.x - 0.5) * float(record["width"]),
		(0.5 - (center.y - region.position.y) / region.size.y) * float(record["height"]),
		0.0
	)
	var world_point := (record["root"] as Node3D).to_global(local)
	var screen := _camera.camera.unproject_position(world_point)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	root.push_input(motion)
	var press := InputEventMouseButton.new()
	press.position = screen
	press.global_position = screen
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press)
	var release := InputEventMouseButton.new()
	release.position = screen
	release.global_position = screen
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release)
	await process_frame
	await process_frame
	_check(_flow.stage == &"l1", "Clicking the world-space card starts the class.")
	print("CHECK: world-space panel click")


# ——— 临时三维效果（声纹/小球）与 L2/L3 材质清单 ———

## 声纹与事件小球都会自己 queue_free。它们以前会被收进 L2 的材质清单，节点释放后
## 清单里留着已释放对象，`entry["node"] as MeshInstance3D` 直接抛
## "Trying to cast a freed object"，L3 渐变与重开复位都会停在半截
## （选择第一项、一路点继续，几轮之后必然复现）。这里按真实节奏制造这两个窗口。
func _check_transient_fx_entries() -> void:
	_flow.restart()
	await process_frame
	var world := _main.get_node_or_null("WorldUI")
	_flow_state.activate()
	await process_frame
	var baseline := _flow_state.get_clay_mesh_count()
	for i in range(4):
		_flow.emit_signal("sound_emitted", Vector3(0.0, 1.5, 0.0), 0.6)
	await process_frame
	_check(_fx_count() >= 4, "The check spawns real sound ripples (got %d)." % _fx_count())
	_flow_state.refresh_targets()
	await process_frame
	_check(
		_flow_state.get_clay_mesh_count() == baseline,
		"Sound ripples stay out of the clay material list (%d vs %d)."
		% [_flow_state.get_clay_mesh_count(), baseline]
	)
	# L2 里事件小球可以被点掉：收集动画结束它就 queue_free。它和声纹不同，是进了
	# 材质清单的（L2 里应当和房间一起变灰、L3 里一起隐藏），所以清单必须能容忍它被释放。
	_flow.emit_signal("event_observed", &"check_orb", "检查用小球", Vector3(0.0, 1.2, 0.0))
	await process_frame
	var orb: EventOrb3D = null
	if world != null:
		for child in world.get_children():
			if child is EventOrb3D:
				orb = child
	_check(orb != null, "The check spawns an observation orb.")
	_flow_state.refresh_targets() # 让小球进入材质清单
	await process_frame
	if orb != null:
		orb.collect_external()
		await create_timer(0.9, true).timeout
		_check(not is_instance_valid(orb), "The collected orb is freed before materials are restored.")
	# 声纹全部过期、小球已释放，再走 L3 与复位：清单里若还留着它们，就会抛已释放转换
	await create_timer(1.0, true).timeout
	_flow_state.enter_l3()
	await process_frame
	_check(_flow_state.is_isolated(), "Isolation completes after the transient nodes are freed.")
	_flow_state.deactivate(true)
	await process_frame
	_check(not _flow_state.is_active(), "Flow state leaves L3 cleanly after those nodes are freed.")
	_check(
		_flow_state.get_clay_mesh_count() == 0,
		"Restoring materials leaves no stale entries (%d)."
		% _flow_state.get_clay_mesh_count()
	)
	print("CHECK: transient effects vs L2 materials")


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
	_check(_pose_of("SeatB06") == _pose_id("READ"), "Classroom settles before the second layer.")


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


## 当前播到第 5 步了吗（节拍列表最后一个 step）。
func _at_step_five() -> bool:
	var played := _flow.debug_played_steps()
	return not played.is_empty() and float(played[played.size() - 1]) >= 5.0


## 当前场上临时三维效果（声纹 / 事件小球）的节点数。
func _fx_count() -> int:
	var world := _main.get_node_or_null("WorldUI")
	if world == null:
		return 0
	var count := 0
	for child in world.get_children():
		if child.is_in_group(L2FlowState.TRANSIENT_FX_GROUP):
			count += 1
	return count


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
