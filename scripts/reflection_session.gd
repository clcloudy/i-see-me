extends Node
## 本轮反思的数据和交互；阶段切换只通过信号交回 DialogueFlow。
signal isolation_requested
signal finished
signal observation_requested(entry: Dictionary, text: String)
signal replay_requested(entry: Dictionary)
signal replay_stopped
signal selection_presented
signal focus_requested(entry: Dictionary)
signal return_requested
signal passage_requested(position: Vector3, target: Vector3)

const PanelScript = preload("res://scripts/reflection_panel.gd")
const ClientScript = preload("res://scripts/reflection_client.gd")
const GalleryScript = preload("res://scripts/reflection_gallery.gd")
var gallery: Node3D
var gallery_config: Dictionary
var _passage_heading := ""
var _passage_text := ""
var _passage_buttons: Array = []
var panel: Node
var client: Node
var copy: Dictionary
var camera_config: Dictionary
var theories: Array = []
var theory_index := 0
var entries: Array = []
var selected: Array = []
var drafts: Dictionary = {}
var feedback: Dictionary = {}
var result: Dictionary = {}
var page := "closed"
var index := 0
var _theory_from_review := false
var _pending_response: Array = []

func setup(ui: DialogueUI) -> void:
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/reflection.json"))
	copy = config["ui"]
	camera_config = config["camera"]
	theories = config["theories"]
	gallery_config = config["gallery"]
	gallery = GalleryScript.new()
	gallery.name = "ReflectionGallery"
	add_child(gallery)
	gallery.setup(gallery_config)
	gallery.focus_requested.connect(func(position: Vector3, target: Vector3): passage_requested.emit(position, target))
	ui._copy.merge(config["completion"], true)
	panel = PanelScript.new()
	add_child(panel)
	panel.setup(ui, copy)
	panel.observation_chosen.connect(func(chosen: int): _action("select:%d" % chosen))
	panel.action_requested.connect(_action)
	client = ClientScript.new()
	add_child(client)
	client.setup(config["ai"], theories)
	client.completed.connect(_generated)

func begin(observations: Array) -> void:
	reset()
	var facts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/reflection.json"))["facts"]
	for source in observations:
		var id := str(source.get("id", ""))
		if not facts.has(id):
			continue
		var entry: Dictionary = source.duplicate(true)
		entry["fact"] = facts[id]
		entries.append(entry)
	page = "select"
	_show_selection()

func reset() -> void:
	replay_stopped.emit()
	if client != null:
		client.cancel()
	if panel != null:
		panel.close()
	if gallery != null:
		gallery.clear()
	_passage_buttons.clear()
	_passage_heading = ""
	_passage_text = ""
	entries.clear()
	selected.clear()
	drafts.clear()
	feedback.clear()
	result.clear()
	_pending_response.clear()
	page = "closed"
	index = 0
	theory_index = 0
	_theory_from_review = false

func _show_selection() -> void:
	page = "select"
	var buttons: Array = [["complete", str(copy["complete_selection"]) if not selected.is_empty() else str(copy["continue_empty"])]]
	selection_presented.emit()
	panel.show_observations(entries, selected)
	panel.present(str(copy["select_title"]), str(copy["select_body"]) + "\n%d / 3" % selected.size(), buttons)

func _open_observation(chosen: int) -> void:
	if not selected.has(chosen):
		if selected.size() >= 3:
			return
		selected.append(chosen)
	index = selected.find(chosen)
	page = "approach"
	panel.present(str(copy["moving_title"]), str(entries[chosen]["fact"]), [])
	focus_requested.emit(entries[chosen])

func arrived_at_observation() -> void:
	if page == "approach":
		_show_editor()

func _return_to_self() -> void:
	page = "returning"
	replay_stopped.emit()
	panel.present(str(copy["return_title"]), str(copy["return_body"]), [])
	return_requested.emit()

func returned_to_self() -> void:
	if page != "returning":
		return
	_show_selection()

func _show_editor() -> void:
	page = "write"
	var entry: Dictionary = entries[selected[index]]
	var draft: Dictionary = drafts.get(entry["id"], {})
	observation_requested.emit(entry, str(draft.get("thought", "")))
	replay_requested.emit(entry)
	panel.present(str(copy["write_title"]) + " · %d / %d" % [index + 1, selected.size()], str(entry["fact"]), [
		["next", str(copy["save_next"])],
		["unsure", str(copy["unsure"])], ["none", str(copy["none"])],
		["skip", str(copy["skip"])]
	], true, str(draft.get("thought", "")), str(draft.get("feeling", "")))

func _save(status := "written") -> void:
	var entry: Dictionary = entries[selected[index]]
	var text := str(panel.thought.text).strip_edges().left(600)
	var previous: Dictionary = drafts.get(entry["id"], {})
	if status == "written" and previous.get("thought") == text and previous.get("status", "written") != "written":
		status = str(previous["status"])
	if text.is_empty() and status == "written":
		status = "skipped"
	drafts[entry["id"]] = {"id": entry["id"], "fact": entry["fact"], "thought": text, "feeling": str(panel.feeling.text).strip_edges().left(120), "status": status}
	observation_requested.emit(entry, text if status == "written" else "")

func submissions() -> Array:
	var out: Array = []
	for i in selected:
		var draft: Dictionary = drafts.get(entries[i]["id"], {})
		if draft.get("status") == "written" and not str(draft.get("thought", "")).is_empty():
			# 不传送坐标、角色节点、L1 回答或未选择的观察。
			out.append({"id": draft["id"], "fact": draft["fact"], "thought": draft["thought"], "feeling": draft["feeling"]})
	return out

func _show_consent() -> void:
	replay_stopped.emit()
	page = "consent"
	var preview := str(copy["consent_body"])
	for entry in submissions():
		preview += "\n\n" + str(entry["fact"]) + "\n“" + str(entry["thought"]) + "”"
		if not str(entry["feeling"]).is_empty():
			preview += "\n" + str(entry["feeling"])
	var buttons: Array = [["local", str(copy["local"])] ]
	if not submissions().is_empty():
		buttons.push_front(["send", str(copy["send"])])
		buttons.append(["key_setup", str(copy["key_setup"])])
	buttons.append(["back", str(copy["back_edit"])])
	panel.present(str(copy["consent_title"]), preview, buttons)

func _show_key_setup() -> void:
	page = "key"
	panel.present(str(copy["key_title"]), str(copy["key_body"]), [
		["use_key", str(copy["use_key"])], ["back", str(copy["key_back"])],
		["local", str(copy["local"])]
	])

func _request_analysis() -> void:
	if submissions().is_empty():
		_show_consent()
		return
	if not client.has_api_key():
		_show_key_setup()
		return
	page = "waiting"
	panel.present(str(copy["waiting_title"]), str(copy["waiting_body"]), [["local", str(copy["cancel_wait"])]])
	client.generate(submissions())

func _start_review() -> void:
	isolation_requested.emit()
	index = 0
	theory_index = 0
	_theory_from_review = false
	_show_theory()

func _theory(id: String) -> Dictionary:
	for theory in theories:
		if theory["id"] == id:
			return theory
	return {}

func _show_theory() -> void:
	page = "theory"
	var theory: Dictionary = theories[theory_index]
	var text := str(theory["name"]) + "\n\n" + str(copy["theory_definition"]) + "\n" + str(theory["introduction"])
	if theory_index == 0 and not _theory_from_review:
		text = str(copy["theory_intro"]) + "\n\n" + text
	text += "\n\n" + str(copy["theory_scene"]) + "\n" + str(theory["game_example"])
	text += "\n\n" + str(copy["theory_limit"]) + "\n" + str(theory["limit"])
	text += "\n\n" + str(copy["theory_source"]) + "\n" + str(theory["citation"]) + "\n\n" + str(theory["url"])
	var buttons: Array = []
	if theory_index > 0:
		buttons.append(["theory_previous", str(copy["theory_previous"])])
	if theory_index + 1 < theories.size():
		buttons.append(["theory_next", str(copy["theory_next"])])
	buttons.append(["theory_done", str(copy["theory_return"] if _theory_from_review else copy["theory_done"])])
	var group_key := "theory:%d:%s" % [theory_index, "review" if _theory_from_review else "intro"]
	_present_passages(group_key, str(copy["theory_title"]) + " · %d / %d" % [theory_index + 1, theories.size()], text, buttons)

func _present_passages(key: String, heading: String, text: String, buttons: Array) -> void:
	_passage_heading = heading
	_passage_text = text
	_passage_buttons = buttons
	gallery.present(key, heading, text)
	_refresh_passage_controls()

func passage_arrived() -> void:
	if page not in ["theory", "review", "summary", "correction"]:
		return
	gallery.arrived()
	_refresh_passage_controls()

func _refresh_passage_controls() -> void:
	var buttons: Array = []
	if not gallery.moving:
		if gallery.current > gallery.first:
			buttons.append(["passage_previous", str(copy["passage_previous"])])
		if gallery.current < gallery.last:
			buttons.append(["passage_next", str(copy["passage_next"])])
		if gallery.current == gallery.last:
			buttons.append_array(_passage_buttons)
		elif page == "theory":
			buttons.append(["theory_done", str(copy["theory_return"] if _theory_from_review else copy["theory_done"])])
	panel.present(_passage_heading, _passage_text, buttons, page == "correction" and not gallery.moving and gallery.current == gallery.last, "", "", true)

func _show_review() -> void:
	page = "review"
	if index >= selected.size():
		_show_summary()
		return
	var entry: Dictionary = entries[selected[index]]
	var draft: Dictionary = drafts.get(entry["id"], {})
	var text := str(copy["event_label"]) + "\n" + str(entry["fact"]) + "\n\n" + str(copy["your_words"]) + "\n"
	var status := str(draft.get("status", "skipped"))
	text += str(draft.get("thought", "")) if status == "written" else str(copy.get("review_" + status, copy["review_skipped"]))
	var item := _current_item()
	var buttons: Array = []
	if not item.is_empty():
		var theory := _theory(str(item["theory_id"]))
		if not theory.is_empty():
			text += "\n\n" + str(copy["theory_basis"]) + "\n" + str(theory["name"])
			text += "\n\n" + str(copy["theory_evidence"]) + "\n“" + str(item["evidence"]) + "”"
		else:
			text += "\n\n" + str(copy["theory_no_match"])
		text += "\n\n" + str(copy["ai_label"]) + "\n" + str(item["reading"])
		text += "\n\n" + str(copy["observation_label"]) + "\n" + str(item["uncertainty"])
		buttons = [["fit", str(copy["fit"])], ["partly", str(copy["partly"])], ["reject", str(copy["reject"])]]
	else:
		text += "\n\n" + str(copy["local_note"])
		buttons = [["review_next", str(copy["continue"])]]
	buttons.append(["theories", str(copy["theories"])])
	observation_requested.emit(entry, str(draft.get("thought", "")))
	_present_passages("review:%d" % index, str(copy["review_title"]) + " · %d / %d" % [index + 1, selected.size()], text, buttons)

func _current_item() -> Dictionary:
	if index >= selected.size():
		return {}
	var id: String = str(entries[selected[index]]["id"])
	for item in result.get("items", []):
		if item["id"] == id:
			return item
	return {}

func _show_summary() -> void:
	page = "summary"
	var text := str(copy["closing"])
	# 只展示所有相关解读均被确认贴近时的跨观察总结。
	var accepted: bool = result.get("items", []).size() >= 2
	for item in result.get("items", []):
		accepted = accepted and feedback.get(item["id"], {}).get("fit") == "fit"
	if accepted and not str(result.get("summary", "")).is_empty():
		text = str(copy["summary_label"]) + "\n" + str(result["summary"]) + "\n\n" + text
	_present_passages("summary", str(copy["summary_title"]), text, [["finish", str(copy["finish"])]])

func _generated(data: Dictionary, error: String) -> void:
	if page != "waiting":
		return
	if get_tree().paused:
		_pending_response = [data, error]
		return
	if not error.is_empty():
		page = "error"
		panel.present(str(copy["error_title"]), str(copy.get("error_" + error, copy["error_network"])), [["retry", str(copy["retry"])], ["key_setup", str(copy["key_setup"])], ["local", str(copy["local"])], ["back", str(copy["back_edit"])]])
		return
	result = data.duplicate(true)
	_start_review()

func _process(_delta: float) -> void:
	if not _pending_response.is_empty() and not get_tree().paused:
		var response := _pending_response
		_pending_response = []
		_generated(response[0], response[1])

func _action(action: String) -> void:
	if get_tree().paused or page == "closed":
		return
	if page in ["theory", "review", "summary", "correction"]:
		if gallery.moving:
			return
		if action in ["passage_next", "passage_previous"]:
			gallery.step(1 if action == "passage_next" else -1)
			_refresh_passage_controls()
			return
	if page == "select":
		if action.begins_with("select:"):
			var chosen := action.get_slice(":", 1).to_int()
			if chosen < 0 or chosen >= entries.size():
				return
			_open_observation(chosen)
		elif action == "complete":
			_show_consent()
	elif page == "write":
		if not action in ["next", "unsure", "none", "skip"]:
			return
		_save()
		match action:
			"next":
				_return_to_self()
			"unsure", "none", "skip":
				_save("skipped" if action == "skip" else action)
				_return_to_self()
	elif page in ["consent", "error"]:
		match action:
			"send", "retry":
				_request_analysis()
			"key_setup":
				_show_key_setup()
			"local":
				result.clear()
				_start_review()
			"back":
				_show_selection()
	elif page == "key":
		match action:
			"use_key":
				var key := str(panel.api_key_input.text).strip_edges()
				if key.is_empty() or key.contains(" ") or key.contains("\t") or key.contains("\n") or key.contains("\r"):
					panel.body.text = str(copy["key_required"])
					panel.api_key_input.grab_focus()
					return
				client.set_api_key(key)
				_request_analysis()
			"back":
				_show_consent()
			"local":
				result.clear()
				_start_review()
	elif page == "waiting" and action == "local":
		client.cancel()
		result.clear()
		_start_review()
	elif page == "theory":
		if action == "theory_previous" and theory_index > 0:
			theory_index -= 1
			_show_theory()
		elif action == "theory_next" and theory_index + 1 < theories.size():
			theory_index += 1
			_show_theory()
		elif action == "theory_done":
			_show_review()
	elif page == "review":
		if action == "theories":
			_theory_from_review = true
			theory_index = 0
			for i in range(theories.size()):
				if theories[i]["id"] == _current_item().get("theory_id", ""):
					theory_index = i
			_show_theory()
		elif action in ["fit", "partly", "reject"]:
			var id: String = str(entries[selected[index]]["id"])
			feedback[id] = {"fit": action}
			if action == "fit":
				index += 1
				_show_review()
			else:
				page = "correction"
				_present_passages("correction:%d" % index, str(copy["correction_title"]), str(copy["correction_body"]), [["corrected", str(copy["continue"])]])
		elif action == "review_next":
			index += 1
			_show_review()
	elif page == "correction" and action == "corrected":
		feedback[str(entries[selected[index]]["id"])]["correction"] = str(panel.thought.text).left(600)
		index += 1
		page = "review"
		_show_review()
	elif page == "summary" and action == "finish":
		reset()
		finished.emit()
