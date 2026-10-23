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
