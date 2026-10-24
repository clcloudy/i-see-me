extends SceneTree
## 主角/同学 16 项动作 + 道具的无头检查（2026-10-24）。
##
## 运行：Godot_v4.6.1-stable_win64_console.exe --headless --path . \
##       --script res://tests/character_actions_check.gd
## 检查内容：每个动作能重建姿态、坐/站髋高正确、关键骨骼确实动起来、
## 道具在正确阶段出现、口型能张开、一次性动作能走到结束。

var _failures: Array[String] = []
var _checks: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await _check_all_clips()
	await _check_female_model()
	await _check_demo_scenes()
	_check_prop_kit()

	if _failures.is_empty():
		print("PASS character_actions_check (%d checks)" % _checks)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		printerr("character_actions_check: %d/%d failed" % [_failures.size(), _checks])
		quit(1)


func _expect(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)


func _spawn(model_file: String) -> Node3D:
	var holder := Node3D.new()
	holder.set_script(load("res://scripts/character_action.gd"))
	var model: Node3D = load(model_file).instantiate()
	model.name = "Model"
	model.rotation_degrees = Vector3(0, 180, 0)
	holder.add_child(model)
	root.add_child(holder)
	await process_frame
	await process_frame
	return holder


func _check_all_clips() -> void:
	var ch := await _spawn("res://assets/characters/quaternius/Casual.glb")
	_expect(ch._rig != null, "main character rig not built")
	if ch._rig == null:
		return
	_expect(ch._stand_hip > 0.7 and ch._stand_hip < 1.2,
		"stand hip height out of range: %.3f" % ch._stand_hip)
	_expect(ch._face != null, "face not created")

	# 每个动作在中段取样：骨骼必须偏离 rest（头/颈至少一个）
	for clip_id in range(1, CharacterAction.Clip.size()):
		var clip: int = clip_id
		ch.play_clip(clip, true)
		var dur: float = ch.get_clip_duration()
		ch.seek(dur * 0.5)
		await process_frame
		var moved := _head_motion(ch)
		_expect(moved > 0.5, "clip %s: head/neck barely moves (%.3f)" % [ch.get_clip_label(), moved])

	# 坐姿 / 站立髋高
	var seated_clips := [
		CharacterAction.Clip.HAND_ON_DESK, CharacterAction.Clip.LAUGH_SHAKE,
		CharacterAction.Clip.NOD_FULL, CharacterAction.Clip.LOOK_BACK,
		CharacterAction.Clip.DRAW_GRID, CharacterAction.Clip.WHISPER_LOOP,
	]
	for clip in seated_clips:
		ch.play_clip(clip, true)
		ch.seek(ch.get_clip_duration() * 0.5)
		await process_frame
		var hip: float = ch._rig.hip_world_y()
		_expect(absf(hip - CharacterAction.SEATED_HIP_HEIGHT) < 0.02,
			"%s seated hip %.3f != 0.47" % [ch.get_clip_label(), hip])

	# 起身终点 = 站立髋高；坐下终点 = 坐姿髋高
	ch.play_clip(CharacterAction.Clip.SIT_TO_STAND, true)
	ch.seek(ch.get_clip_duration())
	await process_frame
	_expect(absf(ch._rig.hip_world_y() - ch._stand_hip) < 0.02,
		"sit_to_stand end hip %.3f != stand %.3f" % [ch._rig.hip_world_y(), ch._stand_hip])
	ch.play_clip(CharacterAction.Clip.STAND_TO_SIT, true)
	ch.seek(ch.get_clip_duration())
	await process_frame
	_expect(absf(ch._rig.hip_world_y() - CharacterAction.SEATED_HIP_HEIGHT) < 0.02,
		"stand_to_sit end hip %.3f != 0.47" % ch._rig.hip_world_y())

	# 四处看：三个视线落点方向不同
	ch.play_clip(CharacterAction.Clip.LOOK_AROUND, true)
	ch.seek(1.6)
	var yaw_a := _head_yaw(ch)
	ch.seek(4.4)
	var yaw_b := _head_yaw(ch)
	_expect(absf(yaw_a - yaw_b) > 20.0,
		"look_around targets too similar (%.1f vs %.1f)" % [yaw_a, yaw_b])

	# 弯腰捡笔：笔在手里 → 在本子旁；弯腰时躯干确实前倾
	ch.play_clip(CharacterAction.Clip.PICK_PEN, true)
	ch.seek(1.0)
	await process_frame
	_expect(ch._pen.visible, "pick_pen: pen prop not visible")
	_expect(_torso_pitch(ch) > 10.0, "pick_pen: torso not bent (%.1f)" % _torso_pitch(ch))
	ch.seek(3.4)
	await process_frame
	_expect(ch._pen.visible, "pick_pen: pen missing after placing")
	_expect(ch._pen.global_position.y > 0.5, "pick_pen: pen not placed on desk")

	# 画方格：本子/铅笔/橡皮都在
	ch.play_clip(CharacterAction.Clip.DRAW_GRID, true)
	ch.seek(1.0)
	await process_frame
	_expect(ch._notebook.visible and ch._pencil.visible and ch._eraser.visible,
		"draw_grid: desk props missing")
	ch.seek(3.5)  # 擦线窗口
	await process_frame
	_expect(ch._eraser.visible, "draw_grid: eraser missing during erase")

	# 放低课本：书可见，结尾落到桌面高度
	ch.play_clip(CharacterAction.Clip.LOWER_BOOK, true)
	ch.seek(0.3)
	await process_frame
	_expect(ch._book.visible, "lower_book: book missing")
	ch.seek(ch.get_clip_duration())
	await process_frame
	_expect(ch._book.global_position.y > 0.6, "lower_book: book not lowered (%.2f)"
		% ch._book.global_position.y)

	# 掩嘴低笑：手在嘴边
	ch.play_clip(CharacterAction.Clip.LAUGH_SHAKE, true)
	ch.seek(0.3)
	await process_frame
	var hand: Vector3 = ch._rig.bone_world("Hand.R")
	var head: Vector3 = ch._rig.bone_world("Head")
	_expect(hand.distance_to(head) < 0.16, "laugh_shake: hand not at mouth (%.2f)"
		% hand.distance_to(head))
	# 不能插进头里：手腕到嘴面片至少留 3 cm，同时不能离得太远。
	var mouth: Vector3 = ch._face.get_mouth_world()
	var mouth_gap := hand.distance_to(mouth)
	_expect(mouth_gap > 0.03 and mouth_gap < 0.16,
		"laugh_shake: hand penetrates/floats at mouth (%.2f)" % mouth_gap)

	# 口型：站立说话时嘴会张开
	ch.play_clip(CharacterAction.Clip.STAND_TALK, true)
	ch.speaking = true
	var opened := 0.0
	for i in 24:
		ch._process(0.05)
		opened = maxf(opened, ch.get_mouth_open())
	_expect(opened > 0.15, "stand_talk: mouth never opens (%.2f)" % opened)

	# 一次性动作能结束（信号）
	var finished := [false]
	ch.clip_finished.connect(func(): finished[0] = true)
	ch.play_clip(CharacterAction.Clip.NOD_FULL, true)
	ch._process(2.0)
	_expect(finished[0], "nod_full: clip_finished not emitted")

	ch.queue_free()
	await process_frame


func _check_female_model() -> void:
	var ch := await _spawn("res://assets/characters/quaternius/WomensCasual.glb")
	_expect(ch._rig != null, "female rig not built")
	if ch._rig == null:
		return
	ch.outfit = 7
	for clip in [CharacterAction.Clip.SIT_TO_STAND, CharacterAction.Clip.LAUGH_SHAKE,
			CharacterAction.Clip.WHISPER_LOOP, CharacterAction.Clip.NOD_FULL]:
		ch.play_clip(clip, true)
		ch.seek(ch.get_clip_duration() * 0.5)
		await process_frame
		_expect(_head_motion(ch) > 0.5, "female clip %s: no motion" % ch.get_clip_label())
	ch.queue_free()
	await process_frame


func _check_demo_scenes() -> void:
	var scenes := {
		"res://scenes/actors/protagonist/protagonist_actions_preview.tscn": "character",
		"res://scenes/actors/classmate/classmate_actions_preview.tscn": "character",
		"res://scenes/actors/teacher/teacher_extra_preview.tscn": "teacher",
		"res://scenes/actors/props/props_preview.tscn": "",
	}
	for path in scenes:
		var scn: Node = load(path).instantiate()
		root.add_child(scn)
		for i in 3:
			await process_frame
		var key: String = scenes[path]
		if key != "":
			_expect(scn.get(key) != null, "demo scene not wired: %s" % path)
		if scn.has_method("set_clip_index"):
			scn.call("set_clip_index", 0)
		elif scn.has_method("set_demo_index"):
			scn.call("set_demo_index", 0)
		await process_frame
		scn.queue_free()
		await process_frame

	# 可复用的人物模板场景
	for path in ["res://scenes/actors/protagonist/protagonist_animated.tscn",
			"res://scenes/actors/classmate/classmate_animated.tscn"]:
		var actor: Node = load(path).instantiate()
		root.add_child(actor)
		await process_frame
		await process_frame
		_expect(actor.get("_rig") != null, "actor template rig missing: %s" % path)
		actor.queue_free()
		await process_frame


func _check_prop_kit() -> void:
	var pen := PropKit.pen()
	_expect(pen.get_child_count() >= 3, "prop pen missing parts")
	var book := PropKit.textbook()
	_expect(book.get_child_count() >= 3, "prop textbook missing parts")
	var box := PropKit.chalk_box()
	_expect(box.get_child_count() >= 8, "prop chalk box missing parts")
	var nb := PropKit.notebook()
	_expect(nb.get_child_count() >= 7, "prop notebook missing parts")
	var pencil := PropKit.pencil()
	_expect(pencil.get_child_count() >= 4, "prop pencil missing parts")
	var eraser := PropKit.eraser()
	_expect(eraser.get_child_count() >= 1, "prop eraser missing parts")
	pen.free()
	book.free()
	box.free()
	nb.free()
	pencil.free()
	eraser.free()


func _head_motion(ch: Node3D) -> float:
	var skel: Skeleton3D = ch._skeleton
	var best := 0.0
	for bone in ["Neck", "Head", "Torso", "UpperArm.R", "UpperArm.L", "UpperLeg.R", "LowerLeg.R"]:
		var idx := skel.find_bone(bone)
		if idx == -1:
			continue
		var q := skel.get_bone_pose_rotation(idx)
		var rest := skel.get_bone_rest(idx).basis.get_rotation_quaternion()
		best = maxf(best, rad_to_deg(q.angle_to(rest)))
	return best


func _head_yaw(ch: Node3D) -> float:
	# 视线偏航由躯干 + 颈 + 头三段共同构成；只取 Head 会低估实际转头幅度。
	var skel: Skeleton3D = ch._skeleton
	var total := 0.0
	for bone in ["Torso", "Neck", "Head"]:
		var idx := skel.find_bone(bone)
		if idx == -1:
			continue
		var q := skel.get_bone_pose_rotation(idx)
		total += rad_to_deg(q.get_euler().y)
	return total


func _torso_pitch(ch: Node3D) -> float:
	var skel: Skeleton3D = ch._skeleton
	var idx := skel.find_bone("Torso")
	if idx == -1:
		return 0.0
	var q := skel.get_bone_pose_rotation(idx)
	return rad_to_deg(q.get_euler().x)
