extends SceneTree
## 教师动效自检（2026-10-23）：不依赖画面，检查动作/情绪切换、骨架、转身与预览场景装配。
## 运行：Godot_v4.6.1-stable_win64_console.exe --headless --path . --script res://tests/teacher_anim_check.gd

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_single_teacher()
	await _check_preview_scene(
		"res://scenes/actors/teacher/teacher_emotions_preview.tscn", 5, "emotion lineup"
	)
	await _check_preview_scene(
		"res://scenes/actors/teacher/teacher_writing_preview.tscn", 5, "writing preview"
	)
	await _check_preview_scene(
		"res://scenes/actors/teacher/teacher_classroom_preview.tscn", 1, "classroom preview"
	)
	if _failures == 0:
		print("PASS: teacher animation checks completed.")
	else:
		print("FAIL: %d teacher animation check(s) failed." % _failures)
	quit(0 if _failures == 0 else 1)


func _check_single_teacher() -> void:
	var packed := load("res://scenes/actors/teacher/teacher_animated.tscn") as PackedScene
	_check(packed != null, "teacher_animated.tscn loads")
	if packed == null:
		return
	var teacher: TeacherAnimator = packed.instantiate()
	root.add_child(teacher)
	await process_frame
	var skeleton := _find_skeleton(teacher)
	_check(skeleton != null, "Suit skeleton found")
	if skeleton != null:
		_check(skeleton.get_bone_count() >= 49, "Suit skeleton has expected bones")
	_check(teacher.get_action_label() != "?", "action label available")
	_check(teacher.get_emotion_label() != "?", "emotion label available")

	# 4 动作 × 5 情绪全部切一遍，确认不报错、手部目标有效、道具可见性正确。
	for action in range(4):
		for emotion in range(5):
			teacher.set_state(action, emotion)
			await process_frame
			await process_frame
			_check(teacher._smooth_hand.is_finite(), "hand target finite (%d/%d)" % [action, emotion])
			_check(
				teacher._chalk.visible == (action == TeacherAnimator.Action.WRITE_BOARD),
				"chalk visibility matches action (%d)" % action
			)
			_check(
				teacher._roster_cover.visible == (action == TeacherAnimator.Action.CALL_ROLL),
				"roster visibility matches action (%d)" % action
			)
			if action == TeacherAnimator.Action.WRITE_BOARD:
				var finger: Vector3 = (teacher._bone_world("Index2.R") + teacher._bone_world("Index3.R")) * 0.5
				_check(
					finger.distance_to(teacher._chalk.global_position) < 0.12,
					"chalk is inside the hand grip (%d/%d)" % [action, emotion]
				)
			if action == TeacherAnimator.Action.CALL_ROLL:
				var hand2: Vector3 = teacher._bone_world("Hand.R")
				_check(
					hand2.distance_to(teacher._roster_cover.global_position) < 0.22,
					"roster is held by the hand (%d/%d)" % [action, emotion]
				)

	await _check_face(teacher)
	await _check_grip(teacher)

	# 板书会转身 180°；immediate 时立即到位。
	teacher.set_state(TeacherAnimator.Action.WRITE_BOARD, TeacherAnimator.Emotion.NEUTRAL, true)
	await process_frame
	_check(absf(teacher._model_yaw - 180.0) < 0.1, "writing action turns body to the board")
	teacher.set_state(TeacherAnimator.Action.LECTURE, TeacherAnimator.Emotion.NEUTRAL, true)
	await process_frame
	_check(absf(teacher._model_yaw) < 0.1, "lecture action faces the class")

	# 演示接口：循环与播放开关。
	teacher.set_state(0, 0)
	teacher.cycle_action()
	await process_frame
	_check(teacher.action == TeacherAnimator.Action.ASK, "cycle_action advances")
	teacher.cycle_emotion()
	_check(teacher.emotion == TeacherAnimator.Emotion.EXCITED, "cycle_emotion advances")
	teacher.playing = false
	await process_frame
	teacher.playing = true

	# 黑板对位：教师应站在黑板正面 0.47 m，且 root 局部 +Z 指向黑板。
	var board := load("res://scenes/props/blackboard.tscn").instantiate() as Node3D
	root.add_child(board)
	board.global_position = Vector3(2, 0, -5)
	teacher.align_to_blackboard(board)
	await process_frame
	_check(
		absf(teacher.global_position.z - (-5.0 + 0.47)) < 0.01,
		"align_to_blackboard places teacher 0.47 m from board"
	)
	_check(
		teacher.global_transform.basis.z.is_equal_approx(Vector3(0, 0, -1)),
		"align_to_blackboard turns teacher toward the board"
	)
	board.queue_free()

	teacher.queue_free()
	await process_frame


## 面部：嘴/眉/眼睑面片存在，说话时嘴会开合，talking=false 后闭嘴。
func _check_face(teacher: TeacherAnimator) -> void:
	var face: TeacherFace = teacher.get_node_or_null("Face") as TeacherFace
	_check(face != null, "face overlay node exists")
	if face == null:
		return
	_check(face._mouth != null, "mouth mesh created")
	_check(face._brows.size() == 2, "two eyebrow overlays created")
	_check(face._lids.size() == 2, "two eyelid overlays created")
	_check(face._mouth_half_w > 0.01 and face._mouth_half_w < 0.06, "mouth width measured from head mesh")

	teacher.set_state(TeacherAnimator.Action.LECTURE, TeacherAnimator.Emotion.NEUTRAL, true)
	teacher.talking = true
	teacher.playing = true
	var max_open := 0.0
	var min_open := 1.0
	for i in 90:
		await process_frame
		max_open = maxf(max_open, face.get_mouth_open())
		min_open = minf(min_open, face.get_mouth_open())
	_check(max_open > 0.45, "mouth opens while speaking (max %.2f)" % max_open)
	_check(max_open - min_open > 0.2, "mouth changes shape between visemes")

	teacher.talking = false
	for i in 60:
		await process_frame
	_check(face.get_mouth_open() < 0.06, "mouth closes when talking is off (%.3f)" % face.get_mouth_open())

	# 表情：失落要低头、眉内侧上挑；眼睑在疑惑/失落时更闭合。
	teacher.talking = true
	teacher.set_emotion(TeacherAnimator.Emotion.DOWN)
	for i in 30:
		await process_frame
	var sad_lid: float = face.get_squint()
	teacher.set_emotion(TeacherAnimator.Emotion.EXCITED)
	for i in 30:
		await process_frame
	_check(sad_lid > face.get_squint() + 0.05, "sad emotion narrows the eyes more than excited")


## 握持：手指弯曲后粉笔落在指节之间，点名册贴在掌侧且不穿过手指。
func _check_grip(teacher: TeacherAnimator) -> void:
	teacher.set_state(TeacherAnimator.Action.WRITE_BOARD, TeacherAnimator.Emotion.NEUTRAL, true)
	for i in 10:
		await process_frame
	var skel := _find_skeleton(teacher)
	var rest := skel.get_bone_rest(skel.find_bone("Middle2.R")).basis.get_rotation_quaternion()
	var now := skel.get_bone_pose_rotation(skel.find_bone("Middle2.R"))
	_check(rest.angle_to(now) > 0.1, "fingers curl while holding chalk")
	var grip: Vector3 = (teacher._bone_world("Index2.R") + teacher._bone_world("Index3.R")) * 0.5
	_check(
		grip.distance_to(teacher._chalk.global_position) < 0.14,
		"chalk sits at the finger pinch"
	)
	var palm: Vector3 = (teacher._grip_frame["palm"] as Vector3)
	var hand: Vector3 = teacher._bone_world("Hand.R")
	var to_book: Vector3 = teacher._roster_cover.global_position - hand
	teacher.set_state(TeacherAnimator.Action.CALL_ROLL, TeacherAnimator.Emotion.NEUTRAL, true)
	for i in 10:
		await process_frame
	palm = teacher._grip_frame["palm"]
	hand = teacher._bone_world("Hand.R")
	to_book = teacher._roster_cover.global_position - hand
	_check(to_book.dot(palm) > 0.0, "roster sits on the palm side of the hand")
	_check(to_book.dot(palm) < 0.08, "roster is not floating above the hand")


func _check_preview_scene(path: String, min_teachers: int, label: String) -> void:
	var packed := load(path) as PackedScene
	_check(packed != null, "%s loads" % label)
	if packed == null:
		return
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	var count := _count_teachers(scene)
	_check(count >= min_teachers, "%s has %d teachers (got %d)" % [label, min_teachers, count])
	scene.queue_free()
	await process_frame


func _count_teachers(node: Node) -> int:
	var total := 1 if node is TeacherAnimator else 0
	for child in node.get_children():
		total += _count_teachers(child)
	return total


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  ok  ", message)
	else:
		_failures += 1
		printerr("  FAIL  ", message)
