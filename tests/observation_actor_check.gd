extends SceneTree

## 头部跟随、同人物排队、真实鼠标拾取及高亮生命周期。
## 加 -- --capture 可保存真实渲染预览至 .local/captures/observation-head.png。
var _failures := 0
const PoseScript := preload("res://scripts/character_pose.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var main := load("res://scenes/classroom_dialogue.tscn").instantiate() as Node
	root.add_child(main)
	await process_frame
	await process_frame
	var flow := main.get_node("Flow") as DialogueFlow
	var world := main.get_node("WorldUI") as SceneUI3D
	var ui := main.get_node("DialogueUI") as DialogueUI
	flow.time_scale = 1000.0
	(ui.get_node("Screen/CardPanel/Box/CardButtons/CardPrimary") as Button).pressed.emit()
	await process_frame
	var camera := Camera3D.new()
	main.add_child(camera)
	camera.global_position = Vector3(-0.7, 1.70, 1.78)
	camera.look_at(Vector3(-1.2, 1.12, -0.02))
	camera.make_current()
	var events: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/classroom_dialogue.json"))["events"]
	var actors: Array[Node3D] = []
	for id in events:
		var event: Dictionary = events[id]
		if not bool(event.get("orb", true)):
			continue
		var actor := flow.observation_actor(StringName(id))
		_check(actor != null, "%s has an explicit observation actor" % id)
		if actor == null:
			continue
		if not actors.has(actor):
			actors.append(actor)
		flow.event_observed.emit(StringName(id), str(event["label"]), Vector3(99, 99, 99))
	await process_frame
	_check(_active_orbs(world).size() == actors.size(), "Only one head target per actor")
	for orb in _active_orbs(world):
		var skeleton: Skeleton3D = orb.get("_skeleton")
		_check(skeleton != null, "Marker resolves a real head bone")
		if skeleton != null:
			var head := skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("Head"))
			_check(orb.global_position.distance_to(head.origin) < 0.10, "Marker centers on the head instead of the event coordinate")
			var area: Area3D = orb.get("_area")
			_check(area.global_position.is_equal_approx(orb.global_position), "Visible marker and click area share the same center")
	var busy := flow.observation_actor(&"busy_hands")
	var target: EventOrb3D
	for orb in _active_orbs(world):
		if orb.get("_actor") == busy:
			target = orb
	var head_before := target.global_position
	busy.set("pose", PoseScript.Pose.PICK_UP)
	busy.apply_pose()
	await create_timer(0.08).timeout
	_check(target.global_position.distance_to(head_before) > 0.01, "Head target follows a changed pose")
	busy.set("pose", PoseScript.Pose.SIT)
	busy.apply_pose()
	await create_timer(0.08).timeout
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		await create_timer(0.7).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.local/captures")
		root.get_texture().get_image().save_png("res://.local/captures/observation-head.png")
		# 固定两个端点，便于直接核对「整体变暗」与「原色复原」的差别。
		for orb in _active_orbs(world):
			orb.set_process(false)
		for phase in [{"pulse": 1.0, "name": "dim"}, {"pulse": 0.0, "name": "restored"}]:
			for orb in _active_orbs(world):
				(orb.get("_highlight") as ShaderMaterial).set_shader_parameter("pulse", phase.pulse)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/captures/observation-head-%s.png" % phase.name)
		for orb in _active_orbs(world):
			orb.set_process(true)
	var first_label := target.label_text()
	var screen := camera.unproject_position(target.global_position)
	var move := InputEventMouseMotion.new()
	move.position = screen
	root.push_input(move)
	await physics_frame
	var click := InputEventMouseButton.new()
	click.position = screen
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	root.push_input(click)
	await process_frame
	await physics_frame
	await process_frame
	var release := click.duplicate() as InputEventMouseButton
	release.pressed = false
	root.push_input(release)
	_check(Dictionary(flow.get("_collected")).size() == 1, "A real click on the head collects exactly one observation")
	var next: EventOrb3D
	for orb in _active_orbs(world):
		if orb.get("_actor") == busy:
			next = orb
	_check(next != null and next != target, "The queued event replaces the collected head target")
	if next != null:
		_check(next.label_text() != first_label, "The next event keeps its own label")
		var overlays: Dictionary = next.get("_original_overlays")
		for mesh in overlays:
			_check(overlays[mesh] == null, "Queued highlight does not inherit the previous highlight")
	var materials := {}
	for orb in _active_orbs(world):
		materials.merge(orb.get("_original_overlays"))
	world._on_stage_changed(&"l2")
	await process_frame
	_check(_active_orbs(world).is_empty(), "L2 removes all head targets")
	for mesh in materials:
		_check(mesh.material_overlay == materials[mesh], "L2 restores original actor material overlays")
	_check(Dictionary(world.get("_observation_queues")).is_empty(), "L2 clears queued observations")
	# 回放必须重新定位到当前头部，不能沿用内容里的旧桌角坐标。
	for id in events:
		var actor := flow.observation_actor(StringName(id))
		if actor == null:
			continue
		flow._present_l2_card({
			"title": str(events[id]["label"]), "body": "内心 OS 定位检查",
			"position": Vector3(99, 99, 99), "source_event": str(id), "kind": &"seen",
		})
		var thought := world.current_thought() as L2Thought3D
		thought.appear(0.0)
		await process_frame
		_check(thought.anchor_position().distance_to(EventOrb3D.head_position(actor)) < 0.001,
			"%s OS uses the same head anchor as observation" % id)
	busy.set("pose_transition_seconds", 0.0)
	busy.set("pose", PoseScript.Pose.PICK_UP)
	busy.apply_pose()
	world._on_thought_presented("内心 OS · 低头", "原来他只是在忙自己的事。",
		Vector3(99, 99, 99), &"seen", Vector3.INF, busy)
	var following := world.current_thought() as L2Thought3D
	await create_timer(0.08).timeout
	var before := following.anchor_position()
	busy.set("pose", PoseScript.Pose.SIT)
	busy.apply_pose()
	await create_timer(0.08).timeout
	_check(following.anchor_position().distance_to(before) > 0.01, "OS follows a changed actor pose")
	_check(following.anchor_position().distance_to(EventOrb3D.head_position(busy)) < 0.001,
		"OS remains attached to the moving head")
	var offset := following.card_position() - following.anchor_position()
	_check(absf(offset.x) < 0.001 and absf(offset.z) < 0.001 and offset.y > 0.0,
		"OS stays directly above the event without screen-edge drift")
	if OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless":
		camera.look_at(following.anchor_position() + Vector3.UP * 0.5)
		await create_timer(0.7).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/captures/os-head-anchor.png")
	await create_timer(1.2).timeout
	main.queue_free()
	await process_frame
	if _failures == 0:
		print("PASS: observation head targets, pose follow, mouse click, queues and cleanup.")
	quit(0 if _failures == 0 else 1)


func _active_orbs(world: Node) -> Array[EventOrb3D]:
	var result: Array[EventOrb3D] = []
	for child in world.get_children():
		if child is EventOrb3D and not child.get("_collected"):
			result.append(child)
	return result


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error(message)
