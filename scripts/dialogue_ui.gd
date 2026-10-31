class_name DialogueUI
extends CanvasLayer

## 课堂对话界面。控件在离屏 SubViewport 中排版，再作为世界空间面片显示；
## 主视口没有平铺 HUD，鼠标通过相机射线转回面板坐标，保留中文输入与键盘操作。

signal advance_requested
signal pause_requested
signal mute_requested
signal restart_requested
signal quit_requested
signal answer_submitted(text: String)
signal struggle_chosen ## 保留给既有流程调试接口；玩家界面不再提供分支按钮。
signal avoid_chosen
signal world_subtitle(speaker_key: StringName, display: String, text: String)
signal world_subtitle_cleared

const SPEAKER_COLORS := {
	&"teacher": Color(0.95, 0.79, 0.52),
	&"protagonist": Color(0.61, 0.85, 0.84),
	&"classmate": Color(0.80, 0.88, 0.78),
	&"stage": Color(0.68, 0.75, 0.77),
}

@export var flat_subtitle: bool = false
@export var world_ui_enabled: bool = true

var _copy: Dictionary = {}
var _muted: bool = false
var _paused: bool = false
var _look_hint_done: bool = false
var _chip_records: Array[Dictionary] = []
var _panels: Array[Dictionary] = []
var _world_ready: bool = false
var _pressed_panel: int = -1
var _hover_panel: int = -1

@onready var _screen: SubViewport = $Screen
@onready var brand: Label = %Brand
@onready var skip_button: Button = %Skip
@onready var pause_button: Button = %Pause
@onready var mute_button: Button = %Mute
@onready var restart_button: Button = %Restart
@onready var quit_button: Button = %Quit
@onready var subtitle_bar: PanelContainer = %SubtitleBar
@onready var speaker_label: Label = %Speaker
@onready var line_label: Label = %Line
@onready var chips: VBoxContainer = %Chips
@onready var choice_panel: PanelContainer = %ChoicePanel
@onready var choice_title: Label = %ChoiceTitle
@onready var input_row: HBoxContainer = %InputRow
@onready var input: TextEdit = %Input
@onready var submit_button: Button = %Submit
@onready var card_panel: PanelContainer = %CardPanel
@onready var card_title: Label = %CardTitle
@onready var card_body: Label = %CardBody
@onready var card_primary: Button = %CardPrimary
@onready var card_restart: Button = %CardRestart
@onready var card_quit: Button = %CardQuit
@onready var transition_label: Label = %Transition
@onready var look_hint: PanelContainer = %LookHint
@onready var look_hint_text: Label = %LookText


func _ready() -> void:
	process_priority = -100
	skip_button.pressed.connect(func() -> void: advance_requested.emit())
	pause_button.pressed.connect(func() -> void: pause_requested.emit())
	mute_button.pressed.connect(func() -> void: mute_requested.emit())
	restart_button.pressed.connect(func() -> void: restart_requested.emit())
	quit_button.pressed.connect(func() -> void: quit_requested.emit())
	submit_button.pressed.connect(_on_submit)
	card_primary.pressed.connect(_on_card_primary)
	card_restart.pressed.connect(func() -> void: restart_requested.emit())
	card_quit.pressed.connect(func() -> void: quit_requested.emit())
	call_deferred("_build_world_panels")


func configure(content: Dictionary) -> void:
	_copy = content.get("ui", {})
	brand.text = _text("brand")
	skip_button.text = _text("skip")
	pause_button.text = _text("pause")
	mute_button.text = _text("mute")
	restart_button.text = _text("restart")
	quit_button.text = _text("quit")


## ——— 世界空间面板与输入转发 ———

func _build_world_panels() -> void:
	if _world_ready or not world_ui_enabled:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		call_deferred("_build_world_panels")
		return
	_world_ready = true
	_add_world_panel("Header", %Header, Rect2(24, 22, 806, 66), Vector3(-0.37, 0.52, -1.20), 1.12, true, 1.0)
	_add_world_panel("Choice", choice_panel, Rect2(320, 230, 640, 260), Vector3(0.0, -0.03, -1.22), 1.02, true)
	_add_world_panel("Card", card_panel, Rect2(280, 130, 720, 460), Vector3(0.0, 0.0, -1.16), 1.12, true)
	_add_world_panel("Chips", chips, Rect2(950, 170, 300, 330), Vector3(0.92, 0.02, -1.35), 0.46, false)
	_add_world_panel("Transition", transition_label, Rect2(350, 105, 580, 55), Vector3(0.0, 0.12, -1.12), 0.72, false)
	_add_world_panel("LookHint", look_hint, Rect2(300, 610, 680, 52), Vector3(0.0, -0.53, -1.15), 0.90, false)


func _add_world_panel(
	panel_name: String,
	control: Control,
	region: Rect2,
	camera_offset: Vector3,
	world_width: float,
	interactive: bool,
	initial_alpha: float = 0.0
) -> void:
	var camera := get_viewport().get_camera_3d()
	var root_3d := Node3D.new()
	root_3d.name = "World" + panel_name
	camera.add_child(root_3d)
	root_3d.position = camera_offset
	root_3d.rotation_degrees.x = -4.0 if panel_name in ["Choice", "Card"] else -2.0
	var sprite := Sprite3D.new()
	sprite.name = "Surface"
	var atlas := AtlasTexture.new()
	atlas.atlas = _screen.get_texture()
	atlas.region = region
	sprite.texture = atlas
	sprite.pixel_size = world_width / region.size.x
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sprite.no_depth_test = false
	sprite.shaded = false
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	sprite.render_priority = 4
	root_3d.add_child(sprite)
	_panels.append({
		"control": control,
		"root": root_3d,
		"sprite": sprite,
		"region": region,
		"width": world_width,
		"height": world_width * region.size.y / region.size.x,
		"interactive": interactive,
		"alpha": initial_alpha,
		"base_position": camera_offset,
	})


func _process(delta: float) -> void:
	if not _world_ready:
		return
	for panel in _panels:
		var control := panel["control"] as Control
		var root_3d := panel["root"] as Node3D
		var shown := control.visible
		if control == choice_panel and card_panel.visible:
			shown = false
		if control == chips and card_panel.visible:
			shown = false
		var alpha := move_toward(float(panel["alpha"]), 1.0 if shown else 0.0, delta * 5.5)
		panel["alpha"] = alpha
		root_3d.visible = alpha > 0.01
		(panel["sprite"] as Sprite3D).modulate.a = alpha
		root_3d.position = (panel["base_position"] as Vector3) + Vector3(0.0, -(1.0 - alpha) * 0.025, 0.0)


func _input(event: InputEvent) -> void:
	if not _world_ready:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE:
			return
		if (
			choice_panel.visible and key_event.pressed and not key_event.echo
			and key_event.keycode in [KEY_ENTER, KEY_KP_ENTER]
		):
			_on_submit()
			get_viewport().set_input_as_handled()
			return
		if choice_panel.visible or card_panel.visible:
			_screen.push_input(event.duplicate(), true)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)
	elif event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	var index := _pressed_panel if _pressed_panel >= 0 else _panel_at(event.position)
	if index >= 0:
		_forward_mouse(event, index, _virtual_mouse_position(index, event.position))
		_hover_panel = index
		get_viewport().set_input_as_handled()
	elif _hover_panel >= 0:
		_forward_mouse(event, _hover_panel, Vector2(-100, -100))
		_hover_panel = -1


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.pressed:
		var index := _panel_at(event.position)
		if index < 0:
			return
		_pressed_panel = index
		_forward_mouse(event, index, _virtual_mouse_position(index, event.position))
		get_viewport().set_input_as_handled()
	elif _pressed_panel >= 0:
		var index := _pressed_panel
		_pressed_panel = -1
		_forward_mouse(event, index, _virtual_mouse_position(index, event.position))
		get_viewport().set_input_as_handled()


func _panel_at(screen_position: Vector2) -> int:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return -1
	var from := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var nearest := -1
	var nearest_distance := INF
	for i in range(_panels.size()):
		var panel: Dictionary = _panels[i]
		if not bool(panel["interactive"]) or float(panel["alpha"]) < 0.5:
			continue
		var control := panel["control"] as Control
		if not control.visible or (control == choice_panel and card_panel.visible):
			continue
		var root_3d := panel["root"] as Node3D
		var normal := root_3d.global_basis.z.normalized()
		var plane := Plane(normal, normal.dot(root_3d.global_position))
		var hit: Variant = plane.intersects_ray(from, direction)
		if hit == null:
			continue
		var local := root_3d.to_local(hit as Vector3)
		if absf(local.x) > float(panel["width"]) * 0.5 or absf(local.y) > float(panel["height"]) * 0.5:
			continue
		var distance := from.distance_to(hit as Vector3)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = i
	return nearest


func _virtual_mouse_position(index: int, screen_position: Vector2) -> Vector2:
	var panel: Dictionary = _panels[index]
	var camera := get_viewport().get_camera_3d()
	var root_3d := panel["root"] as Node3D
	var normal := root_3d.global_basis.z.normalized()
	var plane := Plane(normal, normal.dot(root_3d.global_position))
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(screen_position), camera.project_ray_normal(screen_position))
	if hit == null:
		return Vector2(-100, -100)
	var local := root_3d.to_local(hit as Vector3)
	var region := panel["region"] as Rect2
	return region.position + Vector2(
		(local.x / float(panel["width"]) + 0.5) * region.size.x,
		(0.5 - local.y / float(panel["height"])) * region.size.y
	)


func _forward_mouse(event: InputEventMouse, index: int, virtual_position: Vector2) -> void:
	var copy := event.duplicate() as InputEventMouse
	copy.position = virtual_position
	copy.global_position = virtual_position
	_screen.push_input(copy, true)


## ——— 字幕（兼容接口；实际显示由 SceneUI3D 的世界字幕完成） ———

func set_subtitle(speaker: String, text: String) -> void:
	subtitle_bar.visible = flat_subtitle
	speaker_label.text = speaker
	speaker_label.add_theme_color_override(
		"font_color", SPEAKER_COLORS.get(StringName(speaker), Color(0.85, 0.86, 0.84))
	)
	line_label.text = text


func clear_subtitle() -> void:
	subtitle_bar.visible = false
	line_label.text = ""
	world_subtitle_cleared.emit()


## ——— 感受词条 ———

func show_chip(title: String, body: String) -> void:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.063, 0.09, 0.9)
	style.border_color = Color(0.47, 0.69, 0.71, 0.55)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(13)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	chip.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var title_label := Label.new()
	title_label.text = "第二层  /  " + title
	title_label.add_theme_font_size_override("font_size", 15)
	title_label.add_theme_color_override("font_color", Color(0.61, 0.82, 0.82))
	var body_label := Label.new()
	body_label.text = body
	body_label.add_theme_font_size_override("font_size", 19)
	body_label.add_theme_color_override("font_color", Color(0.93, 0.94, 0.9))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title_label)
	box.add_child(body_label)
	chip.add_child(box)
	chip.modulate = Color(1, 1, 1, 0)
	chips.add_child(chip)
	var record := {"chip": chip, "done": false}
	_chip_records.append(record)
	if _chip_records.size() > 3:
		_retire_chip(_chip_records[0])
	var tween := create_tween()
	tween.tween_property(chip, "modulate:a", 1.0, 0.25)
	var hold := get_tree().create_timer(3.6, true)
	hold.timeout.connect(func() -> void:
		if not bool(record.get("done", true)):
			_retire_chip(record)
	)


func _retire_chip(record: Dictionary) -> void:
	if bool(record.get("done", true)):
		return
	record["done"] = true
	var chip_variant: Variant = record.get("chip")
	_chip_records.erase(record)
	if not is_instance_valid(chip_variant):
		return
	var chip := chip_variant as Control
	var tween := create_tween()
	tween.tween_property(chip, "modulate:a", 0.0, 0.5)
	tween.tween_callback(chip.queue_free)


func clear_chips() -> void:
	for record in _chip_records.duplicate():
		_retire_chip(record)
	_chip_records.clear()


## ——— 第 8 步：一个回答框，预填默认回答 ———

func show_choice(choice: Dictionary) -> void:
	subtitle_bar.visible = false
	world_subtitle_cleared.emit()
	card_panel.visible = false
	look_hint.visible = false
	choice_panel.visible = true
	choice_title.text = str(choice.get("title", ""))
	submit_button.text = str(choice.get("input_submit", "说出口"))
	input.placeholder_text = str(choice.get("input_placeholder", "写下你想说的话……"))
	input.text = str(choice.get("answer_fallback", ""))
	input_row.visible = true
	var last_line := maxi(0, input.get_line_count() - 1)
	input.set_caret_line(last_line)
	input.set_caret_column(input.get_line(last_line).length())
	input.grab_focus.call_deferred()


func _on_submit() -> void:
	answer_submitted.emit(input.text)


func hide_choice() -> void:
	choice_panel.visible = false
	input.release_focus()


## ——— 卡片 / 暂停 / 完成 ———

func show_card(title: String, body: String) -> void:
	subtitle_bar.visible = false
	world_subtitle_cleared.emit()
	look_hint.visible = false
	card_panel.visible = true
	card_title.text = title
	card_body.text = body
	card_primary.visible = false
	card_restart.visible = false
	card_quit.visible = false


func hide_card() -> void:
	card_panel.visible = false


func show_intro() -> void:
	clear_chips()
	clear_subtitle()
	hide_choice()
	_look_hint_done = false
	look_hint.visible = false
	card_panel.visible = true
	card_title.text = _text("intro_title")
	card_body.text = _text("intro_body")
	card_primary.visible = true
	card_primary.text = _text("intro_primary")
	card_restart.visible = false
	card_quit.visible = true
	card_primary.grab_focus.call_deferred()


func show_complete() -> void:
	clear_subtitle()
	card_panel.visible = true
	card_title.text = _text("complete_title")
	card_body.text = _text("complete_body")
	card_primary.visible = true
	card_primary.text = _text("complete_primary")
	card_restart.visible = false
	card_quit.visible = true
	card_primary.grab_focus.call_deferred()


func show_paused(paused: bool) -> void:
	_paused = paused
	if paused:
		card_panel.visible = true
		card_title.text = _text("paused_title")
		card_body.text = _text("paused_body")
		card_primary.visible = true
		card_primary.text = _text("resume")
		card_restart.visible = true
		card_quit.visible = true
		card_primary.grab_focus.call_deferred()
	else:
		card_panel.visible = false


func set_transition_text(text: String) -> void:
	transition_label.text = text
	transition_label.visible = not text.is_empty()


func set_look_hint(text: String) -> void:
	if text.is_empty():
		look_hint.visible = false
		return
	if _look_hint_done:
		return
	_look_hint_done = true
	look_hint_text.text = text
	look_hint.visible = true
	look_hint.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(look_hint, "modulate:a", 1.0, 0.4)
	tween.tween_interval(4.0)
	tween.tween_property(look_hint, "modulate:a", 0.0, 0.8)
	tween.tween_callback(func() -> void: look_hint.visible = false)


func present_controls(paused: bool, muted: bool, skip_enabled: bool) -> void:
	_paused = paused
	_muted = muted
	pause_button.text = _text("resume" if paused else "pause")
	mute_button.text = _text("unmute" if muted else "mute")
	skip_button.disabled = not skip_enabled
	skip_button.visible = skip_enabled


func focus_primary() -> void:
	if card_panel.visible and card_primary.visible:
		card_primary.grab_focus()
	elif choice_panel.visible:
		input.grab_focus()


func _on_card_primary() -> void:
	if _paused:
		pause_requested.emit()
	elif card_title.text == _text("complete_title"):
		restart_requested.emit()
	else:
		advance_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		pause_requested.emit()
		get_viewport().set_input_as_handled()


func _text(key: String) -> String:
	return str(_copy.get(key, key))
