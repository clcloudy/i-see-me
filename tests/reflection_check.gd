extends SceneTree
## 新流程的真实场景集成与响应契约验证；不使用真实凭据或在线请求。
var failures := 0
var flow: DialogueFlow
var session: Node
var transport_result: Array = []

func _initialize() -> void:
	call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	root.size = Vector2i(960, 540) if "--small" in OS.get_cmdline_user_args() else Vector2i(1280, 720)
	if "--capture" in OS.get_cmdline_user_args():
		DisplayServer.window_set_size(root.size)
	var main: Node = load("res://scenes/classroom_dialogue.tscn").instantiate()
	root.add_child(main)
	for i in range(4):
		await process_frame
	flow = main.get_node("Flow")
	session = flow.reflection
	flow.time_scale = 0.01
	flow.flow_state.transition_seconds = 0
	flow.flow_state.isolation_seconds = 0
	flow.interface.advance_requested.emit()
	for i in range(25):
		if flow.stage == &"choice":
			break
		flow.skip()
	flow.debug_choose("测试课堂回答")
	for i in range(25):
		if flow.stage == &"l2":
			break
		flow.skip()
	check(flow.stage == &"l2", "Classroom reaches L2 after step 11.")
	flow.skip()
	check(session.page == "select", "Rewind is followed by selection.")
	# 真实课堂事件数据；覆盖三条收集观察，未被点开的不可从 begin 之外混入。
	var observations: Array = []
	for id in ["pen_fall", "look_back", "e02_laugh", "busy_hands"]:
		observations.append({"id": id, "position": Vector3(0, 1.3, 0), "label": flow._content["events"][id]["label"]})
	var canvas_size: Vector2i = flow.interface.get_node("Screen").size
	session.begin(observations)
	check(flow.interface.get_node("Screen").size == canvas_size, "Selection never resizes the shared texture after world surfaces exist.")
	# 保留可观察的镜头转场；课堂/事件时间仍加速。
	session.camera_config["travel_seconds"] = 30.0
	flow.camera.snap(Vector3(0, 1.75, 2.9), EventOrb3D.head_position(flow.observation_actor(&"pen_fall")) + Vector3.UP * 0.36)
	await create_timer(0.35).timeout
	await click_world(session.panel._markers[0]["button"])
	check(session.selected.has(0), "World-space mouse input selects an observation.")
	check(session.page == "approach", "One click starts camera travel, without batch selection.")
	session._action("select:1")
	check(session.selected.size() == 1, "Another observation cannot be selected during camera travel.")
	await wait_page("write")
	await create_timer(0.03).timeout
	session.camera_config["travel_seconds"] = 1.4
	check(flow.camera.current_position().distance_to(flow._l2_position) > 0.5, "Camera moves from behind the protagonist to the selected person.")
	check(flow._reflection_replay_id == "pen_fall", "Selecting a head marker starts its own event replay.")
	var editor_buttons: Array = []
	for button in session.panel.actions.get_children():
		editor_buttons.append(button.text)
	check(editor_buttons.size() == 4 and not editor_buttons.has("只是看着"), "Editor keeps save, unsure, no thought and skip without watch or manual replay.")
	var cycles: int = flow._reflection_replay_cycles
	var logged: int = flow._event_log.size()
	await create_timer(0.4).timeout
	check(flow._reflection_replay_cycles > cycles, "The selected event loops without a second click.")
	check(flow._event_log.size() == logged, "Replay does not register another classroom event.")
	flow.toggle_pause()
	cycles = flow._reflection_replay_cycles
	await create_timer(0.25).timeout
	check(flow._reflection_replay_cycles == cycles, "Pause freezes replay timers.")
	flow.toggle_pause()
	await create_timer(0.03).timeout
	var typed := InputEventKey.new()
	typed.pressed = true
	typed.unicode = 0x6211
	root.push_input(typed)
	await process_frame
	check(session.panel.thought.text == "我", "Chinese text reaches the focused reflection editor once.")
	session.panel.thought.text = "他捡起笔，也许是在帮我。"
	session.panel.feeling.text = "有一点安心"
	session._action("next")
	check(session.page == "returning", "Saving returns the camera before offering the next choice.")
	check(flow._reflection_replay_id.is_empty() and not flow._voice.playing and not flow._sfx.playing, "Return stops the current action and sound replay.")
	session._action("complete")
	check(session.page == "returning", "Completion cannot bypass the return journey.")
	flow.toggle_pause()
	var returning_position := flow.camera.current_position()
	await create_timer(0.1).timeout
	check(session.page == "returning" and flow.camera.current_position().is_equal_approx(returning_position), "Pause freezes the return camera and its completion.")
	flow.toggle_pause()
	await wait_page("select")
	check(flow.camera.current_position().distance_to(flow._l2_position) < 0.02, "Selection resumes automatically behind the protagonist.")
	check(session.panel.actions.get_child_count() == 1 and session.panel._choosing, "Returning exposes head markers directly with only the completion button.")
	check(flow.stage == &"l2", "Saving alone does not enter L3.")
	session._action("select:1")
	await wait_page("write")
	session.panel.thought.text = "他们在看我，我担心说错。"
	session._action("next")
	await wait_page("select")
	session._action("select:0")
	await wait_page("write")
	check(session.panel.thought.text == "他捡起笔，也许是在帮我。", "Going back preserves the first draft.")
	check(session.panel.feeling.text == "有一点安心", "Revisiting preserves the optional feeling.")
	check(session.selected.size() == 2, "Revisiting a person does not add a duplicate selection.")
	session._action("next")
	await wait_page("select")
	session._action("select:1")
	await wait_page("write")
	check(session.panel.thought.text == "他们在看我，我担心说错。", "Going forward preserves the second draft.")
	flow.toggle_pause()
	await create_timer(0.03).timeout
	check(not session.panel.panel.visible, "Pause hides reflection behind the pause menu.")
	var page: String = session.page
	session._action("next")
	check(session.page == page, "Paused actions cannot advance reflection.")
	flow.toggle_pause()
	await create_timer(0.03).timeout
	check(session.panel.thought.text == "他们在看我，我担心说错。", "Pause and resume preserve typed text.")
	var before_resume: String = session.panel.thought.text
	root.push_input(typed)
	await process_frame
	check(session.panel.thought.text.length() == before_resume.length() + 1, "Resumed editor accepts keyboard input without another click.")
	session.panel.thought.text = before_resume
	flow.skip()
	check(session.page == "write", "Global skip does not submit or discard an active input.")
	session._action("next")
	await wait_page("select")
	session._action("select:2")
	await wait_page("write")
	session._action("unsure")
	await wait_page("select")
	session._action("select:3")
	check(session.selected.size() == 3 and session.page == "select", "Selection retains the existing three-observation limit.")
	session._action("complete")
	check(session.page == "consent", "Explicit completion opens the next-stage preparation.")
	check(flow._reflection_replay_id.is_empty(), "Leaving L2 editing stops event replay.")
	var submitted: Array = session.submissions()
	check(submitted.size() == 2, "Uncertain entries are excluded from the AI request.")
	check(submitted[0].keys().size() == 4 and not submitted[0].has("position"), "Request includes only id, fact, thought and optional feeling.")
	check(session.result.is_empty(), "No interpretation is invented before a request.")
	session._action("send")
	check(session.page == "key" and session.panel.api_key_input.secret, "Sending first opens a masked in-game key input.")
	session._action("use_key")
	check(session.page == "key" and not session.client.has_api_key(), "An empty key keeps the player on the key entry page.")
	await process_frame
	await process_frame
	var key_character := InputEventKey.new()
	key_character.pressed = true
	key_character.unicode = 0x61
	root.push_input(key_character)
	await process_frame
	check(session.panel.api_key_input.text == "a", "Keyboard input reaches the masked key field exactly once.")
	flow.toggle_pause()
	await create_timer(0.03).timeout
	check(not session.panel.panel.visible, "Pause hides the key entry surface.")
	session._action("use_key")
	check(not session.client.has_api_key(), "Paused input cannot submit a key.")
	flow.toggle_pause()
	await create_timer(0.03).timeout
	root.push_input(key_character)
	await process_frame
	check(session.panel.api_key_input.text == "aa", "Resume restores focus to the masked key field.")
	session._action("back")
	check(session.page == "consent" and session.panel.api_key_input.text.is_empty(), "Leaving key entry clears the field.")
	session._action("key_setup")
	session.panel.api_key_input.text = "local-ui-fixture-only"
	var service_endpoint: String = session.client.config["endpoint"]
	session.client.config["endpoint"] = "http://127.0.0.1:1/chat/completions"
	session._action("use_key")
	check(session.page == "waiting" and session.client.has_api_key(), "Using an entered key starts the request with an in-memory credential.")
	check(session.panel.api_key_input.text.is_empty() and not session.panel.api_key_input.visible, "Submitting clears and hides the key field.")
	session.client.cancel()
	session.client.config["endpoint"] = service_endpoint
	session._show_consent()
	var items: Array = []
	for entry in submitted:
		var reading := "你把同学看向你与回答时的表现联系起来。认知模型可以帮助你梳理，对这件事的理解怎样影响了你当时关注的细节。"
		if entry["id"] == "pen_fall":
			reading = "你把同桌捡笔理解为一种帮助。按照认知模型，这种理解可能与你写下的“有一点安心”相联系。"
		items.append({"id": entry["id"], "quote": entry["thought"], "theory_id": "cognitive_model", "evidence": entry["thought"], "reading": reading, "uncertainty": "回顾这一刻时，可以留意对方的动作、神情与后续反应，看看自己怎样从这些细节形成当时的理解。"})
	var valid := {"items": items, "summary": "也许你在留意自己的表达如何被别人接住。"}
	var envelope := {"choices": [{"finish_reason": "stop", "message": {"content": JSON.stringify(valid)}}]}
	check(not session.client.parse_response(envelope, submitted).is_empty(), "Matching response is accepted.")
	var malformed: Dictionary = envelope.duplicate(true)
	malformed["choices"][0]["message"]["content"] = " "
	check(session.client.parse_response(malformed, submitted).is_empty(), "Blank JSON content is rejected.")
	malformed = envelope.duplicate(true)
	malformed["choices"][0]["finish_reason"] = "length"
	check(session.client.parse_response(malformed, submitted).is_empty(), "Truncated responses are rejected.")
	var changed: Dictionary = valid.duplicate(true)
	changed["items"][0]["quote"] = "AI改写的原话"
	malformed = envelope.duplicate(true)
	malformed["choices"][0]["message"]["content"] = JSON.stringify(changed)
	check(session.client.parse_response(malformed, submitted).is_empty(), "Changed quotes are rejected.")
	for invalid_field in ["theory_id", "evidence"]:
		changed = valid.duplicate(true)
		changed["items"][0][invalid_field] = "未经提供的理论" if invalid_field == "theory_id" else "玩家没说过的话"
		malformed["choices"][0]["message"]["content"] = JSON.stringify(changed)
		check(session.client.parse_response(malformed, submitted).is_empty(), "Unknown theories and invented evidence are rejected: " + invalid_field)
	changed = valid.duplicate(true)
	changed["items"][0]["theory_id"] = ""
	changed["items"][0]["evidence"] = ""
	malformed["choices"][0]["message"]["content"] = JSON.stringify(changed)
	check(not session.client.parse_response(malformed, submitted).is_empty(), "Insufficient evidence may leave the theory unset.")
	# 模拟响应到达暂停窗口：直到恢复才进入 L3。
	session.page = "waiting"
	flow.toggle_pause()
	session._generated(valid, "")
	check(flow.stage == &"l2", "An AI response cannot change stage while paused.")
	flow.toggle_pause()
	await process_frame
	await process_frame
	check(flow.stage == &"l3" and session.page == "theory", "Valid generation enters L3 with trusted theory introductions.")
	check(flow.flow_state.is_l3(), "L3 keeps the existing isolation effect.")
	check(session.panel.body.text.contains("认知模型") and session.panel.body.text.contains("beckinstitute.org"), "Theory introduction includes a classroom example, limits and source.")
	check(session.panel.body.text.contains("自动思维") and session.panel.body.text.contains(session.copy["theory_intro"]), "First theory explains automatic thoughts after the opening introduction.")
	check(str(session.gallery.stops[session.gallery.last]["body"].text) == str(session.theories[0]["url"]), "The source URL stays complete on its own passage.")
	for i in range(1, session.gallery.stops.size()):
		var before: Vector3 = session.gallery.stops[i - 1]["root"].global_position
		var after: Vector3 = session.gallery.stops[i]["root"].global_position
		check(before.x * after.x < 0 and after.z < before.z, "L3 passages alternate sides and extend into depth.")
	flow.toggle_pause()
	session._action("theory_next")
	check(session.theory_index == 0, "Pause prevents theory navigation.")
	flow.toggle_pause()
	await gallery_action("theory_next")
	check(session.panel.body.text.contains("聚光灯效应"), "Second theory concerns classroom attention.")
	check(not session.panel.body.text.contains(session.copy["theory_intro"]) and session.panel.body.text.contains("高估自己受到的关注"), "Later theories start with their own explanation instead of repeating the opening.")
	await gallery_action("theory_next")
	check(session.panel.body.text.contains("自我疏离") and session.panel.body.text.contains("镜头"), "Third theory explains the observer perspective without inferring change.")
	await gallery_action("theory_previous")
	check(session.theory_index == 1, "Theory pages permit going back.")
	await gallery_action("theory_done")
	check(session.page == "review" and session.panel.body.text.contains("认知模型") and session.panel.body.text.contains(submitted[0]["thought"]), "Analysis displays the trusted theory and exact supporting words.")
	await gallery_action("theories")
	check(session.page == "theory" and session.theory_index == 0, "Review reopens the relevant theory.")
	check(not session.panel.body.text.contains(session.copy["theory_intro"]), "Reopening a theory from a record starts directly with the viewpoint.")
	check(not str(session.gallery.stops[session.gallery.first]["body"].text).contains("刚才，你记录了"), "Cached world passages also reopen directly on the viewpoint.")
	await gallery_action("theory_done")
	check(session.index == 0 and session.feedback.is_empty(), "Reading theory does not confirm or advance a response.")
	await gallery_action("reject")
	check(session.page == "correction", "Player can reject the AI reading.")
	session.panel.thought.text = "我更在意的是他有没有注意到笔。"
	session._action("corrected")
	await gallery_action("fit")
	await gallery_action("review_next")
	check(session.page == "summary", "Review includes uncertain entries without AI analysis.")
	check(not session.panel.body.text.contains(valid["summary"]), "Rejected interpretations are excluded from the final summary.")
	check(session.feedback[submitted[0]["id"]]["correction"].contains("笔"), "Player correction is retained in memory.")
	await gallery_action("finish")
	check(flow.stage == &"complete", "Explicit finish completes the experience.")
	check(session.drafts.is_empty() and session.feedback.is_empty(), "Finish clears personal drafts and corrections.")
	flow.restart()
	check(flow.stage == &"intro" and session.page == "closed", "Restart resets both stage and reflection.")
	check(session.client.has_api_key() and session.panel.api_key_input.text.is_empty(), "Restart retains only the in-memory credential for this game run.")
	# 网络失败、无密钥和过期响应的路径用注入错误覆盖，不发任何在线请求。
	flow.stage = &"l2"
	session.begin(observations)
	session._action("select:0")
	await wait_page("write")
	session.panel.thought.text = "测试"
	session._action("next")
	await wait_page("select")
	session._action("complete")
	session._action("back")
	check(session.page == "select", "Returning from preview permits selecting a saved person to edit.")
	session._action("complete")
	session.page = "waiting"
	session._generated({}, "missing_key")
	check(session.page == "error", "Missing key offers a local fallback.")
	session._action("local")
	check(session.result.is_empty() and session.page == "theory", "Offline fallback also offers theory introductions without fake AI output.")
	await gallery_action("theory_done")
	check(session.page == "review" and session.panel.body.text.contains(session.copy["local_note"]), "Offline review retains original words without invented analysis.")
	flow.restart()
	session._generated(valid, "")
	check(flow.stage == &"intro" and session.result.is_empty(), "Late results cannot revive a restarted session.")
	flow.stage = &"l2"
	session.begin(observations)
	session._action("select:0")
	flow.restart()
	await create_timer(0.05).timeout
	check(session.page == "closed" and flow._reflection_replay_id.is_empty(), "Restart during approach cancels pending editor and playback.")
	# 用仓库已有的赞同配音验证自动回放与离开后的停播。
	flow.stage = &"l2"
	flow.time_scale = 1.0
	session.camera_config["travel_seconds"] = 0.05
	session.begin([{ "id": "e03_nod", "position": Vector3.ZERO }])
	session._action("select:0")
	await wait_page("write")
	await create_timer(1.85).timeout
	check(flow._voice.playing and flow._voice.stream.resource_path.ends_with("classmate_agree.wav"), "Selecting a voiced person automatically replays their existing recording.")
	session._action("skip")
	await wait_page("select")
	check(not flow._voice.playing, "Voice remains stopped after returning behind the protagonist.")
	flow.restart()
	flow.time_scale = 0.01
	session.camera_config["travel_seconds"] = 1.4
	flow.stage = &"l2"
	session.begin([])
	session._action("complete")
	session._action("back")
	check(session.page == "select", "Empty selection can return from preparation safely.")
	session._action("complete")
	session._action("local")
	check(session.page == "theory", "Zero entries still permit learning about the theories.")
	await gallery_action("theory_done")
	check(session.page == "summary", "Zero entries can skip the introduction and finish without analysis.")
	flow.restart()
	await check_transport(submitted, envelope)
	if "--capture" in OS.get_cmdline_user_args():
		await capture(observations, valid)
	main.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: L2/L3 reflection checks (no online requests).")
	quit(0 if failures == 0 else 1)

func wait_page(expected: String) -> void:
	for i in range(300):
		if session.page == expected:
			await create_timer(0.03).timeout
			return
		await create_timer(0.01).timeout
	check(false, "Reflection reaches page: " + expected)

func wait_gallery() -> void:
	for i in range(600):
		if not session.gallery.moving:
			return
		await create_timer(0.01).timeout
	check(false, "L3 camera arrives at its world-space passage.")

func gallery_action(action: String) -> void:
	await wait_gallery()
	session._action(action)
	await wait_gallery()

func check_transport(submitted: Array, envelope: Dictionary) -> void:
	# 仅回环地址、伪造测试密钥。永不调用真实服务。
	var server := TCPServer.new()
	if server.listen(0, "127.0.0.1") != OK:
		check(false, "Local HTTP fixture can listen.")
		return
	var client: Node = load("res://scripts/reflection_client.gd").new()
	root.add_child(client)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/reflection.json"))
	var settings: Dictionary = catalog["ai"]
	settings["endpoint"] = "http://127.0.0.1:%d/chat/completions" % server.get_local_port()
	client.setup(settings, catalog["theories"])
	client.completed.connect(func(data: Dictionary, error: String): transport_result = [data, error])
	check(not client.has_api_key(), "A newly created client starts with an empty credential.")
	transport_result = []
	client.generate(submitted)
	check(transport_result.size() == 2 and transport_result[1] == "missing_key", "A request requires an in-game credential.")
	client.set_api_key(" local-fixture-only ")
	for status in [200, 401, 503]:
		transport_result = []
		client.generate(submitted)
		var peer: StreamPeerTCP = null
		var received := PackedByteArray()
		var answered := false
		for i in range(300):
			if peer == null and server.is_connection_available():
				peer = server.take_connection()
			if peer != null:
				peer.poll()
				var available := peer.get_available_bytes() if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED else 0
				if available > 0:
					received.append_array(peer.get_data(available)[1])
				var wire := received.get_string_from_utf8()
				var split := wire.find("\r\n\r\n")
				if split >= 0 and not answered:
					var length := 0
					for header in wire.left(split).split("\r\n"):
						if header.to_lower().begins_with("content-length:"):
							length = header.get_slice(":", 1).strip_edges().to_int()
					if received.size() >= split + 4 + length:
						var request: Dictionary = JSON.parse_string(wire.substr(split + 4))
						check(wire.left(split).contains("Authorization: Bearer local-fixture-only"), "The entered credential is used only in the authorization header.")
						check(not wire.substr(split + 4).contains("local-fixture-only"), "The credential stays outside player data and the AI prompt.")
						check(request["response_format"]["type"] == "json_object", "HTTP request asks for structured JSON.")
						check(request["messages"].size() == 2 and request["stream"] == false, "HTTP request is a single non-streaming round.")
						check(str(request["messages"][0]["content"]).contains("application_rule") and str(request["messages"][0]["content"]).contains("spotlight_effect"), "HTTP request supplies the trusted theory catalog and applicability rules.")
						check(JSON.parse_string(request["messages"][1]["content"])["entries"] == submitted, "Theory grounding adds no personal fields to the request.")
						var response := JSON.stringify(envelope).to_utf8_buffer()
						peer.put_data(("HTTP/1.1 %d Fixture\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, response.size()]).to_utf8_buffer())
						peer.put_data(response)
						answered = true
			if not transport_result.is_empty():
				break
			await create_timer(0.005).timeout
		check(not transport_result.is_empty(), "HTTP fixture completes the request.")
		if not transport_result.is_empty():
			var expected_error := ""
			if status == 401:
				expected_error = "authentication"
			elif status == 503:
				expected_error = "network"
			check(transport_result[1] == expected_error, "HTTP success, authentication and service errors are distinguished.")
		if peer != null:
			peer.disconnect_from_host()
	client.cancel()
	server.stop()
	client.queue_free()
	await process_frame
	var next_client: Node = load("res://scripts/reflection_client.gd").new()
	check(not next_client.has_api_key(), "A fresh game client starts empty after the previous client is destroyed.")
	next_client.free()

func click_world(button: Control, mouse_button := MOUSE_BUTTON_LEFT) -> void:
	var record: Dictionary = {}
	for surface in flow.interface._panels:
		if surface["control"] == button or surface["control"] == session.panel.panel and session.panel.panel.is_ancestor_of(button):
			record = surface
	check(not record.is_empty(), "Reflection has an interactive world surface.")
	if record.is_empty():
		return
	var region: Rect2 = record["region"]
	var center := button.get_global_rect().get_center()
	var local := Vector3(((center.x - region.position.x) / region.size.x - 0.5) * float(record["width"]), (0.5 - (center.y - region.position.y) / region.size.y) * float(record["height"]), 0)
	var point: Vector2 = flow.camera.camera.unproject_position(record["root"].to_global(local))
	for down in [true, false]:
		var mouse := InputEventMouseButton.new()
		mouse.position = point
		mouse.global_position = point
		mouse.button_index = mouse_button
		mouse.pressed = down
		# 相机投影返回视口坐标；避免小窗口拉伸时再次按系统坐标缩放。
		root.push_input(mouse, true)
	await process_frame
	await process_frame

func capture(observations: Array, valid: Dictionary) -> void:
	await create_timer(0.8).timeout
	flow.stage = &"l2"
	flow.camera.snap(Vector3(0, 1.75, 2.9), Vector3(-0.7, 1.36, 1.78))
	flow._activate_flow_state()
	flow.interface.hide_card()
	flow.time_scale = 1.0
	# 八条事件同时填满收集夹，验证标题和全部条目没有被裁掉。
	flow.interface.clear_collected()
	for id in ["relief", "quiet", "pen_fall", "look_back", "busy_hands", "e02_laugh", "misheard", "dissent"]:
		flow.interface.collect_observation(StringName(id), str(flow._content["events"][id]["label"]))
	session.begin(observations)
	await save_image("selection")
	var region := DialogueUI.COLLECTED_REGION
	for child in flow.interface.collected_box.get_children():
		check(region.encloses(child.get_global_rect()), "Full event pocket keeps its heading and every row inside the texture region.")
	for surface in flow.interface._panels:
		if surface["root"].name == "WorldHeader":
			check(not surface["region"].intersects(region), "Projection controls never sample the event pocket.")
	var crowded: Array = []
	for id in ["pen_fall", "look_back", "busy_hands", "e02_laugh", "misheard", "dissent", "e03_nod", "relief"]:
		crowded.append({"id": id, "label": flow._content["events"][id]["label"], "position": Vector3(0, 1.3, 0)})
	session.begin(crowded)
	await save_image("selection-crowded")
	var marker_rects: Array[Rect2] = []
	for marker in session.panel._markers:
		if not marker["button"].visible:
			continue
		for surface in flow.interface._panels:
			if surface["control"] != marker["button"]:
				continue
			var rect: Rect2 = session.panel._surface_screen_rect(flow.camera.camera, surface, surface["region"])
			check(root.get_visible_rect().encloses(rect), "Enlarged head labels stay fully inside the viewport.")
			for previous in marker_rects:
				check(not rect.intersects(previous), "Crowded head labels do not cover each other.")
			marker_rects.append(rect)
	session.begin(observations)
	session._action("select:0")
	await wait_page("write")
	session.panel.thought.text = "他捡起笔，也许是在帮我。"
	await save_image("input")
	check_actor_framing(&"pen_fall")
	session._action("next")
	await wait_page("select")
	await save_image("returned-selection")
	session._action("select:1")
	await wait_page("write")
	session.panel.thought.text = "他们在看我，我担心说错。"
	await save_image("input-look-back")
	check_actor_framing(&"look_back")
	session._action("next")
	await wait_page("select")
	session._action("complete")
	await save_image("consent")
	session._action("key_setup")
	session.panel.api_key_input.text = "local-capture-fixture-only"
	await save_image("key-entry")
	check(session.panel.api_key_input.secret, "Key entry captures show masked characters.")
	for button in session.panel.actions.get_children():
		check(session.panel.panel.get_global_rect().encloses(button.get_global_rect()), "Key entry keeps its actions inside the panel.")
	session._action("back")
	session.page = "waiting"
	session._generated(valid, "")
	await wait_gallery()
	await save_image("theory-opening")
	while not str(session.gallery.stops[session.gallery.current]["body"].text).contains("认知模型认为") and session.gallery.current < session.gallery.last:
		await gallery_action("passage_next")
	await save_image("theory-cognitive")
	check(not session.panel._scroll.visible and not session.panel.title.visible, "L3 prose is absent from the camera-attached surface.")
	var anchor_index: int = session.gallery.current
	var anchor: Vector3 = session.gallery.stops[anchor_index]["root"].global_position
	await click_world(session.panel.actions.get_child(0))
	check(session.gallery.moving, "A world-space next button starts camera travel.")
	var traveling := flow.camera.current_position()
	flow.toggle_pause()
	await create_timer(0.15).timeout
	check(flow.camera.current_position().is_equal_approx(traveling), "Pause freezes L3 camera movement.")
	flow.toggle_pause()
	await wait_gallery()
	check(anchor == session.gallery.stops[anchor_index]["root"].global_position, "Text remains fixed in world space while the camera travels.")
	check(flow.camera.current_position().distance_to(traveling) > 1, "Camera physically follows the next passage.")
	await save_image("theory-spatial-next")
	while not str(session.gallery.stops[session.gallery.current]["body"].text).contains("同桌捡起") and session.gallery.current < session.gallery.last:
		await gallery_action("passage_next")
	await save_image("theory-cognitive-example")
	while not str(session.gallery.stops[session.gallery.current]["body"].text).contains("发生了什么") and session.gallery.current < session.gallery.last:
		await gallery_action("passage_next")
	await save_image("theory-cognitive-method")
	while session.gallery.current < session.gallery.last:
		await gallery_action("passage_next")
	await save_image("theory-source")
	for button in session.panel.actions.get_children():
		check(session.panel.panel.get_global_rect().encloses(button.get_global_rect()), "L3 controls remain within their small footer.")
	await gallery_action("theory_next")
	check(session.theory_index == 1, "World-space mouse input can navigate theory pages.")
	while not str(session.gallery.stops[session.gallery.current]["body"].text).contains("聚光灯效应指的是") and session.gallery.current < session.gallery.last:
		await gallery_action("passage_next")
	await save_image("theory-spotlight")
	await gallery_action("theory_next")
	while not str(session.gallery.stops[session.gallery.current]["body"].text).contains("自我疏离指的是") and session.gallery.current < session.gallery.last:
		await gallery_action("passage_next")
	await save_image("theory-distance")
	await gallery_action("theory_done")
	while not str(session.gallery.stops[session.gallery.current]["body"].text).contains(session.copy["ai_label"]) and session.gallery.current < session.gallery.last:
		await gallery_action("passage_next")
	await save_image("review-mock")
	while session.gallery.current < session.gallery.last:
		await gallery_action("passage_next")
	await gallery_action("reject")
	while session.gallery.current < session.gallery.last:
		await gallery_action("passage_next")
	check(session.panel.thought.visible and not session.panel.body.visible, "Correction keeps instructions in the world and only the writing field in the footer.")
	session.panel.thought.text = "我想补充自己的理解。"
	check(session.panel.thought.placeholder_text == session.copy["correction_hint"], "L3 correction uses its own approved writing prompt.")
	await save_image("correction-spatial")
	for surface in flow.interface._panels:
		if surface["control"] == session.panel.panel:
			check(root.get_visible_rect().encloses(session.panel._surface_screen_rect(flow.camera.camera, surface, surface["region"])), "Correction footer stays entirely within the viewport.")
	flow.toggle_pause()
	await save_image("paused")
	flow.toggle_pause()
	session._action("corrected")
	flow.restart()
	await create_timer(0.1).timeout
	check(session.gallery.stops.is_empty() and session.page == "closed", "Restart clears passages and cancels L3 camera callbacks.")

func save_image(name: String) -> void:
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var folder := "res://.local/captures/reflection-small" if "--small" in OS.get_cmdline_user_args() else "res://.local/captures/reflection"
	DirAccess.make_dir_recursive_absolute(folder)
	var rendered := root.get_texture().get_image()
	rendered.save_png(folder + "/" + name + ".png")
	if session.page in ["theory", "review", "summary", "correction"] and not paused and not session.gallery.moving:
		# L3 后处理不能把世界文字盖掉：检查正文中心区域确实有明亮字形。
		var center := flow.camera.camera.unproject_position(session.gallery.stops[session.gallery.current]["root"].global_position)
		var bright := 0
		for y in range(maxi(0, int(center.y) - 90), mini(rendered.get_height(), int(center.y) + 90)):
			for x in range(maxi(0, int(center.x) - 250), mini(rendered.get_width(), int(center.x) + 250)):
				if rendered.get_pixel(x, y).get_luminance() > 0.82:
					bright += 1
		check(bright > 100, "World-space text is actually rendered above the L3 post-process: " + name)

func check_actor_framing(id: StringName) -> void:
	var head := EventOrb3D.head_position(flow.observation_actor(id))
	var projected := flow.camera.camera.unproject_position(head) / flow.camera.get_viewport().get_visible_rect().size
	check(projected.x > 0.1 and projected.x < 0.43 and projected.y > 0.15 and projected.y < 0.7, "Selected person stays visible beside the input panel: " + str(id))
