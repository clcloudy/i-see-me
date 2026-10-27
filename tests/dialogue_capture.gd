extends SceneTree

## 课堂对话关键瞬间的渲染截图（需要真实渲染窗口，不能 --headless）。
##
## 取帧点：① 开场（同学写字/看书/听讲）② 第 3 步（站起、捡笔、松口气）
## ③ 第 5 步（前排回头）④ 第 6 步（低笑）。画面仍需人实际检查，
## 自动截图只证明“动作在那几帧真的发生了、并且在默认构图里”。
##
## 运行：
##   Godot_v4.6.1-stable_win64_console.exe --path . --resolution 1280x720 \
##     --script res://tests/dialogue_capture.gd
## 输出：.local/captures/dialogue-0*.png（不提交）

const OUT_DIR := "res://.local/captures"

var _failures: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Capture requires a rendering window.")
		quit(1)
		return
	var packed := load("res://scenes/classroom_dialogue.tscn") as PackedScene
	if packed == null:
		push_error("classroom_dialogue.tscn could not be loaded.")
		quit(1)
		return
	var main := packed.instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	var flow := main.get_node_or_null("Flow") as DialogueFlow
	var ui := main.get_node_or_null("DialogueUI") as DialogueUI
	var camera := main.get_node_or_null("CameraRig") as DialogueCamera
	if flow == null or ui == null or camera == null:
		push_error("Missing dialogue modules.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	flow.time_scale = 1.0
	var primary := ui.get_node("Screen/CardPanel/Box/CardButtons/CardPrimary") as Button
	primary.pressed.emit()
	# 第 0 步：开场教室
	await create_timer(2.0).timeout
	await _save("dialogue-01-open")
	# 低头看一眼前排课桌：桌面道具（本子/笔/课本）与写字的手在不在这张桌上
	camera.nudge_free_look(0.0, -20.0)
	await create_timer(0.4).timeout
	await _save("dialogue-01b-desks")
	camera.reset_free_look()
	# 跳到第 3 步：站起 → 笔落地 → 同桌慢慢弯腰捡 → 放回 → 周围人松了口气
	flow.skip()
	flow.skip()
	flow.skip()
	# 时序（节拍内）：2.6 秒起跳已过、笔 3.5 秒开始滚落 4.9 秒落地、
	# 同桌 5.5 秒开始弯腰（2.6 秒过渡到最低点 8.1 秒）、10.1 秒把笔放回、11.1 秒起身。
	await create_timer(3.9).timeout
	await _save("dialogue-02a-pen-falling")
	await create_timer(1.6).timeout
	await _save("dialogue-02b-pen-on-floor")
	await create_timer(2.0).timeout
	await _save("dialogue-02c-deskmate-bending")
	await create_timer(2.0).timeout
	await _save("dialogue-02d-deskmate-lowest")
	# 转头看同桌：yaw 72°（限制 72）、pitch -38°；第一人称下这才看得见左手边的人
	camera.nudge_free_look(66.0, -50.0)
	await create_timer(0.6).timeout
	await _save("dialogue-02e-look-at-deskmate")
	camera.reset_free_look()
	await create_timer(2.0).timeout
	await _save("dialogue-02f-pen-returned")
	# 跳到第 5 步：前排三个人陆续回头，每个人停 3 秒以上
	flow.skip()
	flow.skip()
	await create_timer(5.6).timeout
	await _save("dialogue-03a-look-back")
	await create_timer(2.4).timeout
	await _save("dialogue-03b-look-back-hold")
	# 第 6 步：低笑
	flow.skip()
	await create_timer(2.6).timeout
	await _save("dialogue-04-laugh")
	main.queue_free()
	await process_frame
	print("PASS: dialogue captures saved." if _failures == 0 else "FAIL: dialogue captures.")
	quit(0 if _failures == 0 else 1)


func _save(file_name: String) -> void:
	for i in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_failures += 1
		push_error("Rendered viewport is empty: " + file_name)
		return
	var output := "%s/%s.png" % [OUT_DIR, file_name]
	if image.save_png(output) != OK:
		_failures += 1
		push_error("Could not save " + output)
		return
	print("CAPTURED: " + output)
