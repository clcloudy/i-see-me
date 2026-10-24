extends SceneTree
## 教师新增 5 个动作（17~21）的无头检查（2026-10-24）。
##
## 运行：Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##       --script res://tests/teacher_extra_check.gd

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene: Node3D = load("res://scenes/actors/teacher/teacher_animated.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame

	var t: TeacherAnimator = scene
	_expect(t._skeleton != null, "teacher skeleton missing")

	# 讲台锚点
	var lectern := Marker3D.new()
	lectern.position = Vector3(0.0, 0.95, -0.45)
	root.add_child(lectern)
	var box := Marker3D.new()
	box.position = Vector3(0.18, 0.95, -0.45)
	root.add_child(box)
	var point := Marker3D.new()
	point.position = Vector3(0.7, 1.1, 2.2)
	root.add_child(point)
	t.lectern_node = lectern
	t.chalk_box_node = box
	t.point_target = point

	# 新动作标签齐全
	for action in [TeacherAnimator.Action.CHALK_DOWN, TeacherAnimator.Action.BOOK_PLACE,
			TeacherAnimator.Action.POINT, TeacherAnimator.Action.WALK,
			TeacherAnimator.Action.BOOK_FLIP]:
		_expect(t.ACTION_LABELS.has(action), "missing label for action %d" % action)

	# 17 放下粉笔：握着粉笔下降，末尾收手且粉笔消失
	t.set_action(TeacherAnimator.Action.WRITE_BOARD, true)
	t.seek_action(0.0)
	_expect(t._chalk.visible, "chalk_down: chalk not visible while writing")
	t.set_action(TeacherAnimator.Action.CHALK_DOWN)
	t.seek_action(0.5)
	await process_frame
	_expect(t._chalk.visible, "chalk_down: chalk disappeared too early")
	t.seek_action(1.58)
	await process_frame
	_expect(not t._chalk.visible, "chalk_down: chalk still in hand at end")
	_expect(t._chalk_dropped, "chalk_down: not marked dropped")

	# 18 把课本放到讲台：书出现 → 落在讲台高度
	t.set_action(TeacherAnimator.Action.BOOK_PLACE)
	t.seek_action(0.4)
	await process_frame
	_expect(t._textbook.visible, "book_place: textbook not visible")
	t.seek_action(1.98)
	await process_frame
	_expect(t._book_placed, "book_place: not marked placed")
	_expect(absf(t._textbook.global_position.y - (lectern.global_position.y + 0.02)) < 0.06,
		"book_place: book not at lectern (%.2f vs %.2f)"
		% [t._textbook.global_position.y, lectern.global_position.y])

	# 19 指向：手伸向目标、食指伸直
	t.set_action(TeacherAnimator.Action.POINT, true)
	t.seek_action(0.0)
	await process_frame
	var sh := t._bone_world("UpperArm.R")
	var hand := t._bone_world("Hand.R")
	var to_target := (point.global_position - sh).normalized()
	var to_hand := (hand - sh).normalized()
	_expect(to_hand.dot(to_target) > 0.80, "point: hand not toward target (dot %.2f)"
		% to_hand.dot(to_target))
	_expect(hand.distance_to(sh) > 0.30, "point: arm not extended")

	# 20 走路：位置移动 + 腿摆动 + 到点切动作
	var start := t.global_position
	var target_pos := Vector3(-1.4, t.global_position.y, -4.0)
	t.walk_to(target_pos, 1.0)
	t._walk_elapsed = 0.5
	t._step_walk(0.0)
	await process_frame
	_expect(t.global_position.distance_to(start) > 0.2, "walk: no displacement")
	var leg_idx := t._skeleton.find_bone("UpperLeg.R")
	var rest := t._skeleton.get_bone_rest(leg_idx).basis.get_rotation_quaternion()
	_expect(rad_to_deg(t._skeleton.get_bone_pose_rotation(leg_idx).angle_to(rest)) > 3.0,
		"walk: legs not swinging")
	t._walk_elapsed = 1.0
	t._step_walk(0.0)
	await process_frame
	_expect(t.global_position.distance_to(target_pos) < 0.05, "walk: did not reach target")

	# 21 翻课本：书在手里，翻页纸出现
	t.set_action(TeacherAnimator.Action.BOOK_FLIP)
	t.seek_action(0.50)
	await process_frame
	_expect(t._textbook.visible, "book_flip: textbook missing")
	_expect(t._page_pivot.visible, "book_flip: page not visible")
	var x_mid := t._page_pivot.global_transform.basis.x
	t.seek_action(0.80)
	await process_frame
	_expect(t._page_pivot.global_transform.basis.x.dot(x_mid) < 0.98,
		"book_flip: page did not rotate")

	# 原四个动作不回归：逐一摆一帧
	for action in [TeacherAnimator.Action.LECTURE, TeacherAnimator.Action.ASK,
			TeacherAnimator.Action.CALL_ROLL, TeacherAnimator.Action.WRITE_BOARD]:
		t.set_action(action, true)
		t.seek_action(0.0)
		await process_frame
		_expect(t._grip_frame.size() > 0, "legacy action %d lost grip frame" % action)

	scene.queue_free()
	await process_frame
	lectern.queue_free()
	box.queue_free()
	point.queue_free()

	if _failures.is_empty():
		print("PASS teacher_extra_check (%d checks)" % _checks)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		printerr("teacher_extra_check: %d/%d failed" % [_failures.size(), _checks])
		quit(1)


func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
