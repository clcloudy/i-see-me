extends SceneTree

var _failures: int = 0
var _finished: Array[StringName] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	if scene == null:
		_check(false, "Main scene could not be loaded.")
		quit(1)
		return
	var main := scene.instantiate()
	root.add_child(main)
	await process_frame
	var flow := main.get_node_or_null("Flow") as PrototypeFlow
	var rig := main.get_node_or_null("CameraRig") as PrototypeCameraRig
	var classroom := main.get_node_or_null("Classroom") as PrototypeClassroom
	var ui := main.get_node_or_null("PrototypeUI") as PrototypeUI
	if flow == null or rig == null or classroom == null or ui == null:
		_check(false, "Missing prototype modules.")
		quit(1)
		return
	_check(rig.camera.current, "An active camera is required.")
	for mesh_name in ["Floor", "Ceiling", "BackWall", "FrontWall", "LeftWall", "RightWall"]:
		var mesh := classroom.room.get_node_or_null(mesh_name) as MeshInstance3D
		_check(mesh != null and mesh.mesh != null, "Missing room geometry: " + mesh_name)
	rig.transition_finished.connect(func(view: StringName) -> void: _finished.append(view))
	if OS.get_cmdline_user_args().has("--quit-check"):
		await _prepare_quit(flow)
		# Drop coroutine-local scene references before the engine shuts down.
		call_deferred("_emit_quit", ui)
		return
	elif OS.get_cmdline_user_args().has("--capture"):
		await _capture(flow, rig, ui, classroom)
	else:
		await _test_flow(flow, rig, ui, classroom)
	main.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: prototype checks completed.")
	quit(0 if _failures == 0 else 1)


func _test_flow(
	flow: PrototypeFlow, rig: PrototypeCameraRig, ui: PrototypeUI, classroom: PrototypeClassroom
) -> void:
	rig.transition_seconds = 0.12
	_check(flow.stage == &"intro" and ui.modal.visible, "Start at content notice.")
	await process_frame
	ui.modal_primary.pressed.emit()
	_check(flow.stage == &"l1", "Notice enters L1.")
	ui.continue_button.pressed.emit()
	_check(not flow.transitioning, "Repeated input in the same frame must not advance twice.")
	_check(not classroom.seated_self.visible and not classroom.observer.visible, "L1 hides selves.")
	await process_frame
	ui.continue_button.pressed.emit()
	_check(flow.stage == &"l1" and flow.transitioning, "Stage changes only after camera completion.")
	_check(ui.continue_button.disabled and ui.skip_button.visible, "Lock continue during transition.")
	for click in range(5):
		ui.continue_button.pressed.emit()
	_check(_finished.is_empty(), "Rapid input must not finish or skip a transition.")
	ui.pause_button.pressed.emit()
	_check(paused and ui.modal.visible, "Pause opens a working pause menu.")
	var frozen := rig.camera.global_transform
	await create_timer(0.2).timeout
	_check(rig.camera.global_transform.is_equal_approx(frozen), "Camera must freeze while paused.")
	flow.skip_transition()
	flow.advance()
	_check(flow.transitioning and _finished.is_empty(), "Paused input cannot advance or skip.")
	ui.mute_button.pressed.emit()
	_check(AudioServer.is_bus_mute(0) and flow.muted, "Mute controls the Master bus while paused.")
	ui.modal_primary.pressed.emit()
	_check(not paused, "Resume from pause menu.")
	await create_timer(0.25).timeout
	_check(flow.stage == &"l2" and _finished == [&"l2"], "Natural completion emits once.")
	_check(classroom.seated_self.visible and not classroom.observer.visible, "L2 reveals seated self.")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	_check(paused, "Escape pauses through viewport input.")
	escape = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	root.push_input(escape)
	_check(not paused, "Escape resumes through viewport input.")
	ui.continue_button.pressed.emit()
	_check(flow.transitioning, "L2 starts L3 transition.")
	_check(not classroom.get_node("Room/FrontWall").visible, "L3 removes blocking boundary.")
	ui.skip_button.pressed.emit()
	flow.skip_transition()
	_check(flow.stage == &"l3" and _finished == [&"l2", &"l3"], "Skip completes exactly once.")
	_check(classroom.observer.visible, "L3 reveals the observer.")
	await create_timer(0.2).timeout
	_check(_finished.size() == 2, "Skipped tween must not call completion later.")
	ui.continue_button.pressed.emit()
	_check(flow.stage == &"complete" and ui.modal.visible, "L3 ends at prototype completion.")
	await process_frame
	ui.modal_primary.pressed.emit()
	_check(flow.stage == &"intro" and flow.muted, "Replay returns to notice and preserves mute.")
	for target in [&"l1", &"l2", &"l3"]:
		await _enter_view(flow, target)
		flow.toggle_pause()
		ui.modal_restart.pressed.emit()
		_check(not paused and flow.stage == &"intro", "Paused restart at " + String(target))
		_check(not rig.is_transitioning(), "Restart cancels camera at " + String(target))
		_check(not classroom.seated_self.visible and not classroom.observer.visible, "Reset visibility.")
		_check(classroom.get_node("Room/FrontWall").visible, "Reset stage boundaries.")
		_check(flow.muted, "Restart preserves mute setting.")
	for source in [&"l1", &"l2"]:
		for pause_before_restart in [false, true]:
			await _enter_view(flow, source)
			await process_frame
			flow.advance()
			await process_frame
			var finished_before := _finished.size()
			if pause_before_restart:
				flow.toggle_pause()
			flow.restart()
			await create_timer(0.25).timeout
			_check(flow.stage == &"intro" and not flow.transitioning, "Restart cancels in-flight state.")
			_check(_finished.size() == finished_before, "Canceled transition must not emit later.")
	await _enter_view(flow, &"l1")
	await process_frame
	flow.advance()
	rig.cancel_transition()
	var finished_before := _finished.size()
	await create_timer(0.2).timeout
	_check(_finished.size() == finished_before, "Explicit camera cancellation must not emit.")
	flow.restart()
	flow.toggle_mute()
	_check(not AudioServer.is_bus_mute(0), "Unmute restores Master bus.")
	print("PASS: sequence, duplicate input, natural/skip/cancel completion, pause, mute and restart.")


func _prepare_quit(flow: PrototypeFlow) -> void:
	var source := StringName(OS.get_cmdline_user_args()[-1])
	if source in [&"l1", &"l2", &"l3"]:
		await _enter_view(flow, source)
	elif source == &"complete":
		await _enter_view(flow, &"l3")
		await process_frame
		flow.advance()
	elif source in [&"transition", &"paused-transition"]:
		await _enter_view(flow, &"l1")
		await process_frame
		flow.advance()
		if source == &"paused-transition":
			flow.toggle_pause()
	print("CHECK: quit from " + String(source))


func _emit_quit(ui: PrototypeUI) -> void:
	if ui.modal.visible:
		ui.modal_quit.pressed.emit()
	else:
		ui.quit_button.pressed.emit()
	_check(not paused and not (root.get_node("Main/CameraRig") as PrototypeCameraRig).is_transitioning(),
		"Quit must unpause and cancel.")
	if _failures > 0:
		quit(1)
	create_timer(0.2).timeout.connect(func() -> void:
		_check(false, "Quit did not close the SceneTree.")
		quit(1)
	)


func _enter_view(flow: PrototypeFlow, target: StringName) -> void:
	flow.restart()
	await process_frame
	flow.advance()
	for view in [&"l2", &"l3"]:
		if flow.stage == target:
			break
		await process_frame
		flow.advance()
		flow.skip_transition()
	_check(flow.stage == target, "Could not enter " + String(target))


func _capture(
	flow: PrototypeFlow, rig: PrototypeCameraRig, ui: PrototypeUI, classroom: PrototypeClassroom
) -> void:
	if DisplayServer.get_name() == "headless":
		_check(false, "Capture requires an actual rendering window.")
		return
	DirAccess.make_dir_recursive_absolute("res://.local/captures")
	rig.transition_seconds = 1.0
	for dimensions in [Vector2i(1280, 720), Vector2i(960, 540)]:
		DisplayServer.window_set_size(dimensions)
		root.size = dimensions
		flow.restart()
		await _save_capture(&"intro", dimensions, ui)
		for view in [&"l1", &"l2", &"l3"]:
			await process_frame
			flow.advance()
			if flow.transitioning:
				await create_timer(0.1).timeout
				await _save_capture(StringName("to-" + String(view)), dimensions, ui)
			flow.skip_transition()
			_check(flow.stage == view, "Capture view mismatch.")
			await _save_capture(view, dimensions, ui)
		_check(classroom.observer.visible, "Observer is visible for capture.")
		flow.toggle_pause()
		await _save_capture(&"paused", dimensions, ui)
		flow.toggle_pause()
		await process_frame
		flow.advance()
		await _save_capture(&"complete", dimensions, ui)


func _save_capture(view: StringName, dimensions: Vector2i, ui: PrototypeUI) -> void:
	for frame in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	_check_ui_layout(ui)
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_check(false, "Rendered viewport is empty.")
		return
	_check(image.get_size() == dimensions, "Capture dimensions do not match the requested window.")
	var darkest := 1.0
	var lightest := 0.0
	for y in range(90, image.get_height() - 150, 12):
		for x in range(0, image.get_width(), 12):
			var brightness := image.get_pixel(x, y).get_luminance()
			darkest = minf(darkest, brightness)
			lightest = maxf(lightest, brightness)
	_check(lightest - darkest >= 0.08, "Viewport lacks scene contrast: " + String(view))
	var output := "res://.local/captures/%s-%dx%d.png" % [view, dimensions.x, dimensions.y]
	_check(image.save_png(output) == OK, "Could not save " + output)
	print("PASS: captured %s at %dx%d." % [view, dimensions.x, dimensions.y])


func _check_ui_layout(node: Node) -> void:
	if node is Control and node.is_visible_in_tree():
		var control := node as Control
		var bounds := control.get_viewport_rect()
		_check(bounds.grow(1).encloses(control.get_global_rect()), "UI outside viewport: " + node.name)
		if node.get_parent() is Control:
			var parent_control := node.get_parent() as Control
			_check(
				parent_control.get_global_rect().grow(1).encloses(control.get_global_rect()),
				"UI outside parent: " + node.name
			)
		if node is Label:
			_check(
				control.size.y + 1 >= control.get_minimum_size().y,
				"Text does not fit vertically: " + node.name
			)
	for child in node.get_children():
		_check_ui_layout(child)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
