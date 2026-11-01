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
	await _check_orb_click_collect()
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



# ——— L1 收集：真的用鼠标点一下观察提示 ———

## 收集靠 Area3D 的鼠标事件，前提是视口开了三维拾取（默认是关的，关着就永远点不动）。
## 这里走真实路径：相机 unproject → 鼠标按下 → 视口拾取 → collected → 流程登记，
## 点中的那条之后必须出现在第二层的「我看到的」里。
func _check_orb_click_collect() -> void:
	_check(root.physics_object_picking, "The viewport enables 3D picking for observation markers.")
	var world := _main.get_node_or_null("WorldUI")
	_check(world != null, "The world UI node exists.")
	if world == null or _camera == null or _camera.camera == null:
		return
	var viewport_size := Vector2(root.size)
	var center := viewport_size * 0.5
	var target: EventOrb3D = null
	var target_screen := Vector2.ZERO
	var best := INF
	for child in world.get_children():
		if not child is EventOrb3D:
			continue
		var orb := child as EventOrb3D
		if _camera.camera.is_position_behind(orb.global_position):
			continue
		var screen := _camera.camera.unproject_position(orb.global_position)
		if screen.distance_to(center) > minf(viewport_size.x, viewport_size.y) * 0.4:
			continue
		if screen.distance_to(center) < best:
			best = screen.distance_to(center)
			target = orb
			target_screen = screen
	_check(target != null, "An observation marker is on screen to be clicked.")
	if target == null:
		return
	var label := target.label_text()
	var motion := InputEventMouseMotion.new()
	motion.position = target_screen
	motion.global_position = target_screen
	root.push_input(motion)
	var press := InputEventMouseButton.new()
	press.position = target_screen
	press.global_position = target_screen
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press)
	await process_frame
	await physics_frame
	var release := InputEventMouseButton.new()
	release.position = target_screen
	release.global_position = target_screen
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	root.push_input(release)
	await process_frame
	_check(
		_flow.debug_collected_labels().has(label),
		"Clicking a marker collects it into the flow (\"%s\" at %s)." % [label, str(target_screen)]
	)
	# 收集要当场看得见：右下角的收集夹多一条，
	# 而且那块面片确实在画面右下（第二层要从那儿起飞）。
	_check(
		_ui.debug_collected_rows().size() >= 1,
		"The collected observation shows up in the pocket."
	)
	var slot := _ui.collected_world_point()
	_check(slot.is_finite(), "The collection pocket has a world position.")
	if slot.is_finite():
		var slot_screen := _camera.camera.unproject_position(slot)
		var norm := Vector2(slot_screen.x / float(root.size.x), slot_screen.y / float(root.size.y))
		_check(
			norm.x > 0.6 and norm.y > 0.5,
			"The collection pocket sits in the lower-right of the frame (%s)." % str(norm)
		)
	print("CHECK: observation marker click")


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
	# 进入第二层 = 收集窗口结束：没点开的提示不能留到已经灰化的教室里
	var leftover := 0
	var world := _main.get_node_or_null("WorldUI")
	if world != null:
		for child in world.get_children():
			if child is EventOrb3D:
				leftover += 1
	_check(leftover == 0, "Entering the second layer clears the unopened markers (got %d)." % leftover)
	# L1 的收集 → L2 的内心 OS：点开过的那条才回放
	_check_l2_observation_cards()
	# 第二层的思绪长在事件发生的位置上，不是相机前的一块面片
	await _check_l2_thoughts()
	# L1 收进右下角的那几条，是一条条被抽走、飞到教室里的（不是结束时一起清空）
	await _check_collection_pocket()
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
	# 这一轮一个提示都没点：有提示的观察全部不进第二层，环境事件照旧
	_check(
		not _l2_has_line("他们在看我"),
		"Without collecting, no observation inner voice appears in L2."
	)
	_check(_l2_has_line("轮到我说了"), "Environment events still speak when nothing was collected.")
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
	_check(
		_flow.debug_collected_labels().is_empty(),
		"Restart clears the observations collected in the previous run."
	)
	_check(
		_ui.debug_collected_rows().is_empty(),
		"Restart empties the collection pocket in the lower-right corner."
	)
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
	# L2 后处理是一整块不测深度的全屏四边形：它的绘制优先级必须排在三维 UI 之前，
	# 否则第二层的词条卡会被它整块盖住（曾经是 127，整段 L2 卡片都看不见）。
	var screen_node := _flow_state.get_node_or_null("Screen") as GeometryInstance3D
	var screen_material: Material = screen_node.material_override if screen_node != null else null
	var ui_priority := 0
	for panel in _ui._panels:
		ui_priority = maxi(ui_priority, int((panel["sprite"] as Sprite3D).render_priority))
	_check(
		screen_material != null and screen_material.render_priority < ui_priority,
		"The L2 screen effect draws before the world-space UI (effect %s vs UI %d)."
		% [str(screen_material.render_priority) if screen_material != null else "none", ui_priority]
	)
	var seated_self := _seating.get_node_or_null("ProtagonistSit") as Node3D
	_check(seated_self != null and seated_self.visible, "L2 reveals the seated protagonist.")
	_check(_pose_of("SeatB06") == _pose_id("READ"), "Classroom settles before the second layer.")
	# 互动角色不跟着一起变灰：灰泥世界里他们换成暖色
	var seats := _flow.debug_highlight_seats()
	_check(not seats.is_empty(), "Interacting classmates are highlighted in the grey world: " + str(seats))
	_check(seats.has("SeatB06"), "The classmate who laughed is highlighted.")
	_check(seats.has("SeatC06"), "The desk mate who picked the pen up is highlighted.")
	_check(not seats.has("SeatB09"), "Environment-only actors (quiet lookers) stay grey.")
	var highlighted := _flow_state.get_highlight_mesh_count()
	_check(highlighted > 0, "Highlighted characters use the accent clay (got %d meshes)." % highlighted)
	_check(
		highlighted < _flow_state.get_clay_mesh_count(),
		"Only the interacting characters leave the grey clay (%d of %d)."
		% [highlighted, _flow_state.get_clay_mesh_count()]
	)
	_check(
		_flow_state.highlight_color != _flow_state.clay_color,
		"The accent colour is a different colour from the clay."
	)
	# 口径可切到「只标收集到的」：未点开的人回到灰泥
	var l2_config: Dictionary = _flow._content.get("l2", {})
	var mode_before := str(l2_config.get("highlight_actors", "observed"))
	l2_config["highlight_actors"] = "collected"
	var collected_seats := _flow.debug_highlight_seats()
	l2_config["highlight_actors"] = mode_before
	_check(
		collected_seats.size() < seats.size(),
		"Only collected observations highlight when l2.highlight_actors = collected (%d vs %d)."
		% [collected_seats.size(), seats.size()]
	)


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

## L2 的「我看到的」按收集过滤：有提示的事件必须被点开才回放内心 OS，
## 没点开的不能出现；没有提示的环境事件（忽然安静 / 课堂往下走）仍然保留。
func _check_l2_observation_cards() -> void:
	var events := _content_events()
	var collected := _flow.debug_collected_labels()
	_check(not collected.is_empty(), "The run collected at least one observation.")
	var present := 0
	var absent := 0
	for id in events.keys():
		var event: Dictionary = events[id]
		if not bool(event.get("orb", true)):
			continue
		var thoughts: Array = event.get("thoughts", [])
		if thoughts.is_empty():
			continue
		var line := str(thoughts[0])
		if collected.has(str(event.get("label", id))):
			_check(_l2_has_line(line), "Collected observation becomes an inner-voice card: " + line)
			present += 1
		else:
			_check(not _l2_has_line(line), "Uncollected observation stays out of the second layer: " + line)
			absent += 1
	_check(
		present > 0 and absent > 0,
		"The second layer filters observations by collection (%d in / %d out)." % [present, absent]
	)
	# 收集到的观察卡在标题上标出来源，和环境事件（没有提示可点）区分开
	var prefixed := 0
	for title in _flow.debug_l2_card_titles():
		if str(title).begins_with("我看到的 · "):
			prefixed += 1
	_check(
		prefixed == collected.size(),
		"Every collected observation gets a 「我看到的」 card (%d of %d)." % [prefixed, collected.size()]
	)
	_check(_l2_has_line("轮到我说了"), "Environment events (no marker) keep their inner voice.")


func _l2_has_line(text: String) -> bool:
	for body in _flow.debug_l2_card_bodies():
		if str(body).contains(text):
			return true
	return false


## L1 收集 → L2 展开的连贯性：口袋里的每一条要在它对应的卡片播放时被抽走，
## 而不是等到第二层结束再一起清空（那样玩家看不出东西去了哪）。
func _check_collection_pocket() -> void:
	var collected := _flow.debug_collected_labels().size()
	_check(collected > 0, "The run collected at least one observation before the second layer.")
	var pocket := _ui.debug_collected_rows().size()
	_check(pocket <= collected, "The pocket holds at most the observations collected in L1.")
	await _wait_until(func() -> bool: return _ui.debug_expanded_count() > 0, 4000)
	_check(
		_ui.debug_expanded_count() > 0,
		"A collected observation is taken out of the pocket when its card plays."
	)
	_check(
		_ui.debug_collected_rows().size() < pocket or _ui.debug_collected_rows().is_empty(),
		"The pocket shrinks as its observations unfold into the classroom."
	)


# ——— 第二层的三维思绪（长在世界坐标上） ———

## 第二层不再是「相机前的一块面片」：
## - 每一条词条都带世界坐标，落点是它对应的地方（观察 = 事件的 orb_position，
##   回溯 = 自己课桌上方，倒放 = 沿过道往讲台，概念 = 抽离后围着主角的一圈）；
## - 场上同时只有一块 L2Thought3D，并且它必须在这块相机画幅里；
## - 它打进 dialogue_fx 组，所以灰泥材质替换与 L3 隐藏都不会波及它（否则字会跟着变灰/消失）。
func _check_l2_thoughts() -> void:
	await process_frame
	_check(not _ui.card_panel.visible, "L2 does not fall back to the flat camera panel.")
	var world := _main.get_node_or_null("WorldUI")
	_check(world != null, "The world layer exists to host the L2 thoughts.")
	if world == null:
		return
	var thoughts: Array = []
	for child in world.get_children():
		if child is L2Thought3D:
			thoughts.append(child)
	_check(thoughts.size() == 1, "Exactly one thought is on stage in L2 (got %d)." % thoughts.size())
	var entries := _flow.debug_l2_card_positions()
	_check(entries.size() > 0, "Every L2 card carries a world anchor.")
	# 落点必须都在教室里（不是随便飘在虚空或相机原点）
	var outside: Array[String] = []
	var concepts := 0
	for entry in entries:
		var point: Vector3 = entry["position"]
		if absf(point.x) > 6.0 or point.z > 5.0 or point.z < -6.0 or point.y < 0.6 or point.y > 3.0:
			outside.append("%s(%.2f, %.2f, %.2f)" % [str(entry["title"]), point.x, point.y, point.z])
		if str(entry["kind"]) == "concept":
			concepts += 1
			_check(
				point.distance_to(Vector3(-0.7, 1.36, 1.78)) < 1.8,
				"Concept cards float around the seated protagonist (%.2f m)."
				% point.distance_to(Vector3(-0.7, 1.36, 1.78))
			)
	_check(outside.is_empty(), "Every L2 thought anchors inside the classroom: " + ", ".join(outside))
	_check(concepts > 0, "The observation cards become concept cards around the protagonist.")
	# 收集到的观察：落点就是那件事的 orb_position（这支笔就在那张桌子边）
	var events := _content_events()
	for label in _flow.debug_collected_labels():
		var expected := Vector3.ZERO
		var found := false
		for id in events.keys():
			if str((events[id] as Dictionary).get("label", "")) != str(label):
				continue
			var raw: Variant = (events[id] as Dictionary).get("orb_position")
			if raw is Array and (raw as Array).size() >= 3:
				expected = Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
				found = true
		if not found:
			continue
		var matched := false
		for entry in entries:
			if str(entry["title"]).contains(str(label)) and (entry["position"] as Vector3).distance_to(expected) < 0.01:
				matched = true
		_check(matched, "「%s」的思绪落在它发生的位置（%s）。" % [str(label), str(expected)])
	# 场上的那块：在前方、在画幅内、且不进灰泥材质清单
	if thoughts.is_empty():
		return
	var thought := thoughts[0] as L2Thought3D
	_check(
		thought.is_in_group(L2FlowState.TRANSIENT_FX_GROUP),
		"L2 thoughts stay out of the clay material list."
	)
	var card_point := thought.card_position()
	_check(
		not _camera.camera.is_position_behind(card_point),
		"The live thought card faces the camera from inside the room."
	)
	var screen := _camera.camera.unproject_position(card_point)
	_check(
		screen.x > 0.0 and screen.x < float(root.size.x) and screen.y > 0.0 and screen.y < float(root.size.y),
		"The live thought card lands inside the frame (%s)." % str(screen)
	)
	# 镜头逐条「正对」正在播放的那一条：注视点落在它的锚点上方，而不是一直盯着主角。
	var anchor := thought.anchor_position()
	var aimed := _camera.look_target()
	var flat := Vector2(aimed.x - anchor.x, aimed.z - anchor.z).length()
	_check(
		flat < 0.05 and aimed.y > anchor.y,
		"The camera faces the card that is playing (aim %s over anchor %s)." % [str(aimed), str(anchor)]
	)
	# 正对之后牌面应该落在画面中央一带（不再靠 _shift_into_frame 从画面边缘推回来）
	var norm := Vector2(screen.x / float(root.size.x), screen.y / float(root.size.y))
	_check(
		norm.x > 0.28 and norm.x < 0.72 and norm.y > 0.15 and norm.y < 0.8,
		"The aimed card sits in the middle of the frame (%.2f, %.2f)." % [norm.x, norm.y]
	)
	print("CHECK: L2 thoughts in world space")


func _content_events() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/classroom_dialogue.json")
	)
	if not parsed is Dictionary:
		return {}
	return (parsed as Dictionary).get("events", {})


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
