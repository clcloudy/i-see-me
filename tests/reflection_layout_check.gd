extends SceneTree
## 连续帧回归：相机呼吸微动不能使头顶选择框换位、闪现或覆盖操作区。
var failures := 0
var main: Node
var flow: DialogueFlow
var panel: Node
var capture_enabled := false

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	capture_enabled = "--capture" in OS.get_cmdline_user_args()
	main = load("res://scenes/classroom_dialogue.tscn").instantiate()
	root.add_child(main)
	for i in range(4):
		await process_frame
	flow = main.get_node("Flow")
	panel = flow.reflection.panel
	flow.stage = &"l2"
	flow.interface.hide_card()
	flow.camera.snap(Vector3(0, 1.75, 2.9), Vector3(-0.7, 1.36, 1.78))
	flow._activate_flow_state()
	for size in [Vector2i(1280, 720), Vector2i(960, 540)]:
		root.size = size
		if capture_enabled:
			DisplayServer.window_set_size(size)
		for crowded in [false, true]:
			var ids := ["relief", "quiet", "look_back", "pen_fall", "busy_hands", "class_moves_on"]
			if crowded:
				ids = ["pen_fall", "look_back", "busy_hands", "e02_laugh", "misheard", "dissent", "e03_nod", "relief"]
			flow.interface.clear_collected()
			var entries: Array = []
			for id in ids:
				var event: Dictionary = flow._content["events"][id]
				entries.append({"id": id, "label": event["label"], "position": flow._event_anchor(event, {})})
				flow.interface.collect_observation(StringName(id), str(event["label"]))
			flow.reflection.begin(entries)
			await create_timer(0.6).timeout
			await check_stability(180, "%s crowded=%s" % [size, crowded])
			if capture_enabled:
				await RenderingServer.frame_post_draw
				DirAccess.make_dir_recursive_absolute("res://.local/captures/reflection-layout")
				root.get_texture().get_image().save_png("res://.local/captures/reflection-layout/%dx%d-%s.png" % [size.x, size.y, "crowded" if crowded else "selection"])
			flow.toggle_pause()
			await create_timer(0.03).timeout
			for marker in panel._markers:
				check(not marker["anchor"].visible, "Pause hides observation prompts.")
			flow.toggle_pause()
			await create_timer(0.3).timeout
			await check_stability(20, "resumed")
			flow.camera.nudge_free_look(8.0, -3.0)
			await create_timer(0.3).timeout
			await check_stability(20, "after looking around")
			flow.camera.reset_free_look()
			await create_timer(0.3).timeout
	# 在安全候选都用完时隐藏这一张，不能退回遮住按钮的原位置。
	var bounds := Rect2(0, 0, 300, 100)
	var occupied: Array[Rect2] = [bounds]
	check(not panel._marker_fits(Rect2(10, 10, 200, 60), bounds, occupied), "A full layout rejects an overlapping fallback.")
	flow.restart()
	for marker in panel._markers:
		check(not marker.has("layout_offset") and not marker.has("layout_rect") and not marker.has("layout_origin") and not marker["anchor"].visible, "Restart clears retained layout and prompts.")
	main.queue_free()
	await process_frame
	print("PASS: stable reflection prompts at both window sizes." if failures == 0 else "FAIL: reflection prompt layout.")
	quit(0 if failures == 0 else 1)

func check_stability(frames: int, context: String) -> void:
	var previous: Dictionary = {}
	var moved := false
	var blinked := false
	var overlapped := false
	var clipped := false
	var visible_count := 0
	for frame in range(frames):
		await create_timer(0.016).timeout
		var rects: Array[Rect2] = []
		visible_count = 0
		for i in range(panel._markers.size()):
			var marker: Dictionary = panel._markers[i]
			var shown: bool = marker["anchor"].visible
			if previous.has(i):
				if shown != previous[i]["shown"] and not blinked:
					print("VISIBILITY: ", context, " frame=", frame, " marker=", i, " shown=", shown)
					var entry: Dictionary = panel._observations[i]
					var actor := flow.observation_actor(StringName(entry["id"]))
					var point: Vector3 = EventOrb3D.head_position(actor) if actor != null else entry["position"]
					print("HEAD: ", flow.camera.camera.unproject_position(point), " bounds=", root.get_visible_rect(), " cached=", marker.get("layout_rect"))
				blinked = blinked or shown != previous[i]["shown"]
			var center := Vector2.ZERO
			if shown:
				visible_count += 1
				center = flow.camera.camera.unproject_position(marker["anchor"].global_position)
				if previous.has(i) and previous[i]["shown"]:
					if center.distance_to(previous[i]["center"]) > 8.0 and not moved:
						print("JUMP: ", context, " frame=", frame, " marker=", i, " from=", previous[i]["center"], " to=", center)
					moved = moved or center.distance_to(previous[i]["center"]) > 8.0
				for surface in flow.interface._panels:
					if surface["control"] != marker["button"]:
						continue
					var rect: Rect2 = panel._surface_screen_rect(flow.camera.camera, surface, surface["region"])
					clipped = clipped or not root.get_visible_rect().encloses(rect)
					for other in rects:
						overlapped = overlapped or rect.intersects(other)
					rects.append(rect)
			previous[i] = {"shown": shown, "center": center}
		for surface in flow.interface._panels:
			var control: Control = surface["control"]
			if not control.visible or not (control == panel.panel or control == flow.interface.collected_box or surface["root"].name == "WorldHeader"):
				continue
			var area: Rect2 = surface["region"]
			if control == flow.interface.collected_box:
				area = flow.interface.get_node("Screen/CollectedFolio").get_global_rect()
			var blocker: Rect2 = panel._surface_screen_rect(flow.camera.camera, surface, area)
			for rect in rects:
				overlapped = overlapped or rect.intersects(blocker)
	check(visible_count > 0, "Prompts remain available: " + context)
	check(not moved, "Idle camera never makes prompts jump: " + context)
	check(not blinked, "Idle camera never blinks prompts: " + context)
	check(not overlapped, "Prompts avoid each other and controls: " + context)
	check(not clipped, "Prompts stay within the window: " + context)
