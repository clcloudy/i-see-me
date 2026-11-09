extends Node
## 独立反思面板，复用现有世界面片输入系统，不修改共享 UI 场景。
signal action_requested(action: String)
signal observation_chosen(index: int)

var interface: DialogueUI
var panel: PanelContainer
var title: Label
var body: Label
var thought: TextEdit
var feeling: LineEdit
var api_key_input: LineEdit
var actions: GridContainer
var _copy: Dictionary
var _shown := false
var _was_paused := false
var _choosing := false
var _observations: Array = []
var _markers: Array = []
var _scroll: ScrollContainer
const MARKER_PADDING := 6.0
const LAYOUT_HYSTERESIS := 24.0
var _layout_valid := false
var _layout_look := Vector2.ZERO
var _layout_size := Vector2.ZERO
var _layout_fov := 0.0
var _presentation_id := 0

func setup(ui: DialogueUI, copy: Dictionary) -> void:
	interface = ui
	_copy = copy
	process_mode = Node.PROCESS_MODE_ALWAYS
	var screen: SubViewport = ui.get_node("Screen")
	# 一次预留反思面板和十个事件。创建 AtlasTexture 后改变画布尺寸会让
	# 其他面片继续使用旧 UV，投影布因此会错误显示输入框和按钮。
	screen.size.y = 4096
	panel = PanelContainer.new()
	panel.name = "ReflectionPanel"
	panel.position = Vector2(280, 1340)
	panel.size = Vector2(720, 590)
	panel.theme = ui.card_panel.theme
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.09, 0.10, 0.97)
	style.border_color = Color(0.69, 0.63, 0.46, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", style)
	screen.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 26)
	box.add_child(title)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.custom_minimum_size.y = 240
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var contents := VBoxContainer.new()
	contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation", 12)
	scroll.add_child(contents)
	body = Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 22)
	contents.add_child(body)
	thought = TextEdit.new()
	thought.custom_minimum_size.y = 100
	thought.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	thought.placeholder_text = str(copy["input_hint"])
	thought.add_theme_font_size_override("font_size", 22)
	thought.text_changed.connect(func():
		if thought.text.length() > 600:
			thought.text = thought.text.left(600)
	)
	contents.add_child(thought)
	feeling = LineEdit.new()
	feeling.placeholder_text = str(copy["feeling_hint"])
	feeling.max_length = 120
	contents.add_child(feeling)
	api_key_input = LineEdit.new()
	api_key_input.secret = true
	api_key_input.placeholder_text = str(copy["key_hint"])
	api_key_input.max_length = 512
	api_key_input.custom_minimum_size.y = 48
	api_key_input.add_theme_font_size_override("font_size", 22)
	api_key_input.clear_button_enabled = true
	contents.add_child(api_key_input)
	actions = GridContainer.new()
	actions.add_theme_constant_override("separation", 7)
	box.add_child(actions)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	box.add_child(controls)
	for command in ["pause", "mute", "restart", "quit"]:
		var button := Button.new()
		button.text = str(copy[command])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 38
		button.pressed.connect(func():
			match command:
				"pause": interface.pause_requested.emit()
				"mute": interface.mute_requested.emit()
				"restart": interface.restart_requested.emit()
				"quit": interface.quit_requested.emit()
		)
		controls.add_child(button)
	panel.hide()
	ui._add_world_panel("Reflection", panel, Rect2(280, 1340, 720, 590), Vector3(0.48, -0.02, -1.16), 1.24, true, 0.0, true)

func present(heading: String, text: String, buttons: Array, editing := false, draft := "", sensation := "", spatial := false) -> void:
	_presentation_id += 1
	_layout_valid = false
	_choosing = heading == str(_copy["select_title"])
	interface.collected_suppressed = not _choosing
	var compact := heading in [str(_copy["select_title"]), str(_copy["moving_title"]), str(_copy["return_title"])]
	_scroll.custom_minimum_size.y = 190 if compact else 240
	panel.size.y = 370 if compact else 590
	_scroll.visible = not spatial or editing
	body.visible = not spatial
	title.visible = not spatial
	if spatial:
		panel.size.y = 100 + ceili(buttons.size() / 2.0) * 45
		if editing:
			_scroll.custom_minimum_size.y = 110
			panel.size.y += 120
	var desired_height := (100.0 + ceili(buttons.size() / 2.0) * 45.0 + (120.0 if editing else 0.0)) if spatial else (370.0 if compact else 590.0)
	for surface in interface._panels:
		if surface["control"] == panel:
			surface["base_position"] = Vector3(-0.55, -0.45, -1.5) if compact else Vector3(0.48, -0.02, -1.16)
			surface["width"] = 1.05 if compact else 1.24
			if spatial:
				surface["base_position"] = Vector3(0, -0.61 if editing else -0.82, -1.8)
				surface["width"] = 1.8
			surface["sprite"].pixel_size = float(surface["width"]) / 720.0
			surface["region"].size.y = panel.size.y
			surface["height"] = float(surface["width"]) * panel.size.y / 720.0
			(surface["sprite"].texture as AtlasTexture).region = surface["region"]
	_shown = true
	panel.visible = not get_tree().paused
	title.text = heading
	body.text = text
	_scroll.scroll_vertical = 0
	thought.visible = editing
	thought.placeholder_text = str(_copy["correction_hint"] if spatial else _copy["input_hint"])
	feeling.visible = editing and not spatial
	thought.text = draft
	feeling.text = sensation
	var entering_key := heading == str(_copy["key_title"])
	api_key_input.visible = entering_key
	api_key_input.clear()
	actions.columns = 2 if spatial or editing or buttons.size() > 2 else 1
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	for item in buttons:
		var button := Button.new()
		button.text = str(item[1])
		button.custom_minimum_size.y = 38
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 20)
		button.pressed.connect(func(): action_requested.emit(str(item[0])))
		actions.add_child(button)
	if entering_key:
		api_key_input.grab_focus.call_deferred()
	elif editing:
		thought.grab_focus.call_deferred()
	else:
		thought.release_focus()
		feeling.release_focus()
		api_key_input.release_focus()
	_fit_surface_height(desired_height, _presentation_id)

func _fit_surface_height(height: float, presentation: int) -> void:
	# 隐藏正文/切换输入后，Container 的旧最小尺寸会暂留一帧；排版完成后再贴合。
	await get_tree().process_frame
	if presentation != _presentation_id or not _shown:
		return
	panel.size.y = maxf(height, panel.get_combined_minimum_size().y)
	for surface in interface._panels:
		if surface["control"] == panel:
			surface["region"].size.y = panel.size.y
			surface["height"] = float(surface["width"]) * panel.size.y / 720.0
			(surface["sprite"].texture as AtlasTexture).region = surface["region"]

func close() -> void:
	_layout_valid = false
	_shown = false
	_choosing = false
	interface.collected_suppressed = false
	for marker in _markers:
		marker["button"].hide()
		marker["anchor"].hide()
		marker.erase("layout_offset")
		marker.erase("layout_rect")
		marker.erase("layout_origin")
		marker.erase("layout_hidden")
	if panel != null:
		panel.hide()
		thought.text = ""
		feeling.text = ""
		api_key_input.clear()
		body.text = ""
		title.text = ""
		thought.release_focus()
		feeling.release_focus()
		api_key_input.release_focus()

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var occupied: Array[Rect2] = []
	var bounds := get_viewport().get_visible_rect().grow(-12.0)
	var flow := get_parent().get_parent()
	var look: Vector2 = flow.camera.free_look_offset()
	# 选人期间机位固定：只在主动转头、窗口或视野变化时重排。
	# 呼吸位移、待机视线和细微头部动画不能不断改变点击目标。
	var stable_view := _layout_valid and look.is_equal_approx(_layout_look) and bounds.size.is_equal_approx(_layout_size) and camera != null and is_equal_approx(camera.fov, _layout_fov)
	if camera != null and _shown and _choosing:
		for surface in interface._panels:
			var control: Control = surface["control"]
			if control.visible and (control == panel or control == interface.collected_box or surface["root"].name == "WorldHeader"):
				var area: Rect2 = surface["region"]
				if control == interface.collected_box:
					area = interface.get_node("Screen/CollectedFolio").get_global_rect()
				var padding := 24.0 if surface["root"].name == "WorldHeader" else 8.0
				occupied.append(_surface_screen_rect(camera, surface, area).grow(padding))
	for i in range(_markers.size()):
		var marker: Dictionary = _markers[i]
		var shown := _shown and _choosing and not get_tree().paused and i < _observations.size()
		marker["button"].visible = shown
		marker["anchor"].visible = shown
		if not shown or camera == null:
			continue
		var entry: Dictionary = _observations[i]
		var actor: Node3D = flow.observation_actor(StringName(str(entry["id"])))
		var point: Vector3 = EventOrb3D.head_position(actor) if actor != null else entry.get("position", Vector3.ZERO)
		if stable_view and marker.has("layout_hidden"):
			if marker["layout_hidden"]:
				marker["button"].hide()
				marker["anchor"].hide()
			else:
				_place_marker(marker, marker["layout_rect"], camera, point)
			continue
		if camera.is_position_behind(point) or not bounds.has_point(camera.unproject_position(point)):
			marker["layout_hidden"] = true
			marker["button"].hide()
			marker["anchor"].hide()
			continue
		# 根据镜头深度维持远近事件的可读字号。
		var width := -camera.to_local(point).z * 0.53
		for surface in interface._panels:
			if surface["control"] == marker["button"]:
				surface["width"] = width
				surface["height"] = width * 130.0 / 720.0
				surface["sprite"].pixel_size = width / 720.0
		marker["anchor"].global_position = point + Vector3.UP * (0.16 + width * 130.0 / 720.0 * 0.5)
		# 放大文字后，优先在头顶附近错开，避让其他事件、输入面板与收集夹。
		var center := camera.unproject_position(marker["anchor"].global_position)
		var edge := camera.unproject_position(marker["anchor"].global_position + camera.global_basis.x * width * 0.5)
		var extent := Vector2(absf(edge.x - center.x) * 2.0, absf(edge.x - center.x) * 2.0 * 130.0 / 720.0)
		var rect := Rect2(center - extent * 0.5, extent).grow(MARKER_PADDING)
		rect.position.x = clampf(rect.position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - rect.size.x))
		rect.position.y = clampf(rect.position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - rect.size.y))
		var original := rect
		# 也为尚未处理的旧标签留位，避免前面的标签先占掉后面的稳定位置，
		# 导致整排连锁跳动。只有真正转头或操作区变化才需要让出这些位置。
		var reserved: Array[Rect2] = occupied.duplicate()
		for later in range(i + 1, _markers.size()):
			var other: Dictionary = _markers[later]
			if other.has("layout_rect") and other["anchor"].visible:
				reserved.append(other["layout_rect"])
		# 保留上次相对头部的排布；每帧重新找最近格子会因呼吸微动与浮点误差
		# 在等距候选间来回跳。用内圈检查旧位置，外圈预留间隔，避免边缘反复重排。
		var retained := original
		retained.position += marker.get("layout_offset", Vector2.ZERO)
		# 贴边标签也保留在边界内；亚像素的相机漂移不应使整行失效。
		retained.position.x = clampf(retained.position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - retained.size.x))
		retained.position.y = clampf(retained.position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - retained.size.y))
		var found := marker.has("layout_offset") and _marker_fits(retained, bounds, reserved, true)
		if found:
			rect = retained
		elif marker.has("layout_rect") and original.get_center().distance_to(marker["layout_origin"]) < LAYOUT_HYSTERESIS and _marker_fits(marker["layout_rect"], bounds, reserved, true):
			# 小幅跟随被相邻牌挡住时停在原位，不为了几像素移动跳到另一列。
			rect = marker["layout_rect"]
			found = true
		else:
			var best_distance := INF
			var columns: Array[float] = []
			var rows: Array[float] = []
			for column in [0, -1, 1, -2, 2]:
				columns.append(original.position.x + column * (original.size.x + MARKER_PADDING))
			for row in range(-_markers.size(), _markers.size() + 1):
				rows.append(original.position.y + row * (original.size.y + MARKER_PADDING))
			# 头部对齐的网格可能漏掉边缘整块空位；始终尝试贴边放置。
			columns.append_array([bounds.position.x, bounds.end.x - original.size.x])
			rows.append_array([bounds.position.y, bounds.end.y - original.size.y])
			var preferred := original.get_center()
			if marker.has("layout_rect"):
				var previous: Rect2 = marker["layout_rect"]
				preferred = previous.get_center()
				columns.append(previous.position.x)
				rows.append(previous.position.y)
				# 真的碰到障碍时沿边缘挪开几像素，不能只能跳一整行/列。
				for obstacle in reserved:
					columns.append_array([obstacle.end.x + MARKER_PADDING, obstacle.position.x - original.size.x - MARKER_PADDING])
					rows.append_array([obstacle.end.y + MARKER_PADDING, obstacle.position.y - original.size.y - MARKER_PADDING])
			for x in columns:
				for y in rows:
					var candidate := Rect2(Vector2(x, y), original.size)
					if not _marker_fits(candidate, bounds, reserved):
						continue
					var distance := candidate.get_center().distance_squared_to(preferred)
					# 等距时固定使用先找到的位置，不受亚像素误差影响。
					if distance < best_distance - 1.0:
						rect = candidate
						best_distance = distance
						found = true
		if not found:
			marker["layout_hidden"] = true
			marker["button"].hide()
			marker["anchor"].hide()
			continue
		marker["layout_offset"] = rect.position - original.position
		if not marker.has("layout_rect") or not rect.is_equal_approx(marker["layout_rect"]):
			marker["layout_origin"] = original.get_center()
		marker["layout_rect"] = rect
		marker["layout_hidden"] = false
		occupied.append(rect)
		_place_marker(marker, rect, camera, point)
	if camera != null and _shown and _choosing and not get_tree().paused:
		_layout_valid = true
		_layout_look = look
		_layout_size = bounds.size
		_layout_fov = camera.fov
	if panel != null:
		panel.visible = _shown and not get_tree().paused
		if _was_paused and not get_tree().paused and _shown:
			if api_key_input.visible:
				api_key_input.grab_focus.call_deferred()
			elif thought.visible:
				thought.grab_focus.call_deferred()
		_was_paused = get_tree().paused

func _place_marker(marker: Dictionary, rect: Rect2, camera: Camera3D, point: Vector3) -> void:
	var depth := maxf(0.05, -camera.to_local(point).z)
	var center := rect.get_center()
	var half_width := (rect.size.x - MARKER_PADDING * 2.0) * 0.5
	var width := camera.project_position(center + Vector2(half_width, 0), depth).distance_to(camera.project_position(center - Vector2(half_width, 0), depth))
	for surface in interface._panels:
		if surface["control"] == marker["button"]:
			surface["width"] = width
			surface["height"] = width * 130.0 / 720.0
			surface["sprite"].pixel_size = width / 720.0
	marker["anchor"].global_position = camera.project_position(center, depth)
	marker["anchor"].global_basis = camera.global_basis

func _marker_fits(rect: Rect2, bounds: Rect2, occupied: Array[Rect2], retaining := false) -> bool:
	if not bounds.encloses(rect):
		return false
	var test_rect := rect.grow(-MARKER_PADDING * 0.5) if retaining else rect
	for previous in occupied:
		if test_rect.intersects(previous):
			return false
	return true

func _surface_screen_rect(camera: Camera3D, surface: Dictionary, area: Rect2) -> Rect2:
	var region: Rect2 = surface["region"]
	var result := Rect2()
	var first := true
	for corner in [area.position, area.position + Vector2(area.size.x, 0), area.end, area.position + Vector2(0, area.size.y)]:
		var relative: Vector2 = (corner - region.position) / region.size
		var local := Vector3((relative.x - 0.5) * float(surface["width"]), (0.5 - relative.y) * float(surface["height"]), 0)
		var projected := camera.unproject_position(surface["root"].to_global(local))
		result = Rect2(projected, Vector2.ZERO) if first else result.expand(projected)
		first = false
	return result

func show_observations(entries: Array, selected: Array) -> void:
	_observations = entries
	var screen: SubViewport = interface.get_node("Screen")
	for i in range(entries.size()):
		if i >= _markers.size():
			var button := Button.new()
			button.position = Vector2(280, 2000 + i * 160)
			button.size = Vector2(720, 130)
			button.theme = panel.theme
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.add_theme_font_size_override("font_size", 42)
			button.pressed.connect(func(): observation_chosen.emit(i))
			screen.add_child(button)
			var anchor := Node3D.new()
			add_child(anchor)
			interface._add_world_panel("ReflectionChoice%d" % i, button, Rect2(button.position, button.size), Vector3.ZERO, 1.35, true, 0.0, true, anchor)
			_markers.append({"button": button, "anchor": anchor})
		_markers[i]["button"].text = ("✓ " if selected.has(i) else "○ ") + str(entries[i].get("label", entries[i]["fact"]))
		_markers[i]["button"].disabled = selected.size() >= 3 and not selected.has(i)

func _input(event: InputEvent) -> void:
	if not _shown or get_tree().paused or not event is InputEventKey:
		return
	if event.keycode == KEY_ESCAPE:
		return
	# 回车保留为换行，不使用 L1 的空输入回退逻辑。
	interface.get_node("Screen").push_input(event.duplicate(), true)
	get_viewport().set_input_as_handled()
