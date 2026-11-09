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
signal world_subtitle(speaker_key: StringName, display: String, text: String)
signal world_subtitle_cleared

## 右下角的收集夹：L1 每点开一个观察就多一条，L2 时逐条被抽走、飞到教室里对应的位置。
## 位置与 Screen 里 Collected 的实际矩形一致（改布局必须一起改）。
const COLLECTED_REGION := Rect2(974, 740, 280, 520)
## 相机局部坐标：画面右下角，贴在镜头前的一块面片（与其他面板同一套世界空间做法）。
## fov 65°、16:9、距离 1.22 m 时可见半宽约 1.38 m，所以右边缘 = 0.90 + 0.38 = 1.28 仍在画内。
const COLLECTED_OFFSET := Vector3(0.90, -0.02, -1.22)
const COLLECTED_WIDTH := 0.76
## 感受放在左侧，与右下角的事件收集夹分开，不再需要向上避让。
const CHIPS_LIFT := 0.0
## 收集夹最多能放几条（可观察事件只有 8 个；放不下时先挤掉最旧的一条）。
const COLLECTED_LIMIT := 8

const SPEAKER_COLORS := {
	&"teacher": Color(0.95, 0.79, 0.52),
	&"protagonist": Color(0.61, 0.85, 0.84),
	&"classmate": Color(0.80, 0.88, 0.78),
	&"stage": Color(0.68, 0.75, 0.77),
}

@export var flat_subtitle: bool = false
@export var world_ui_enabled: bool = true
## 固定在投影布表面；与相机前的其他交互面板分开。
@export var header_surface_path: NodePath

var _copy: Dictionary = {}
var _muted: bool = false
var _paused: bool = false
var _look_hint_done: bool = false
var _chip_records: Array[Dictionary] = []
var _panels: Array[Dictionary] = []
## 收集夹里的一行：event_id → Control，顺序即放入顺序（也是第二层的展开顺序）。
var _collected_rows: Dictionary = {}
var _collected_order: Array[String] = []
## 已经被「从口袋里抽走、飞到教室里」的条数（测试用，不复位就无法验证展开过）。
var _expanded_count: int = 0
var _world_ready: bool = false
var _pressed_panel: int = -1
var _hover_panel: int = -1
var collected_suppressed := false

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
@onready var collected_box: VBoxContainer = %Collected
@onready var collected_title: Label = %CollectedTitle


func _ready() -> void:
	process_priority = -100
	collected_box.position = COLLECTED_REGION.position
	collected_box.size = COLLECTED_REGION.size
	_style_header()
	var title_surface := StyleBoxEmpty.new()
	title_surface.content_margin_left = 15.0
	title_surface.content_margin_right = 15.0
	title_surface.content_margin_top = 8.0
	title_surface.content_margin_bottom = 8.0
	collected_title.get_parent().add_theme_stylebox_override("panel", title_surface)
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


## 小图标由本项目的几何线条绘制，不依赖图标字体或新增外部素材。
func _style_header() -> void:
	var paths := [
		'<path d="M2 12Q12 0 22 12Q12 24 2 12Z"/><circle cx="12" cy="12" r="3"/>',
		'<path d="m3 6 8 6-8 6Zm9 0 8 6-8 6Z"/>',
		'<path d="M8 5v14M16 5v14"/>',
		'<path d="M10 8 6 11H3v4h3l4 3ZM15 9l6 8m0-8-6 8"/>',
		'<path d="M5 8a8 8 0 1 1-1 8M5 3v5h5"/>',
		'<path d="M12 2v9M7 5a9 9 0 1 0 10 0"/>',
	]
	var targets: Array[Control] = [brand, skip_button, pause_button, mute_button, restart_button, quit_button]
	for i in range(targets.size()):
		var image := Image.new()
		var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24"><g fill="none" stroke="#d6c297" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % paths[i]
		if image.load_svg_from_string(svg) != OK:
			continue
		var texture := ImageTexture.create_from_image(image)
		if i == 0:
			var icon := TextureRect.new()
			icon.texture = texture
			icon.custom_minimum_size = Vector2(60, 48)
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			brand.get_parent().add_child(icon)
			brand.get_parent().move_child(icon, 0)
		else:
			var button := targets[i] as Button
			button.icon = texture
			button.add_theme_constant_override("icon_max_width", 40)
			button.add_theme_constant_override("h_separation", 12)



## ——— 世界空间面板与输入转发 ———

func _build_world_panels() -> void:
	if _world_ready or not world_ui_enabled:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		call_deferred("_build_world_panels")
		return
	_world_ready = true
	var header_surface := get_node_or_null(header_surface_path) as Node3D
	if header_surface != null:
		_add_world_panel("Header", %Header, Rect2(24, 740, 806, 560), Vector3(0.0, 0.0, 0.018), 2.14, true, 1.0, false, header_surface)
	_add_world_panel("Choice", choice_panel, Rect2(320, 230, 640, 260), Vector3(0.0, -0.03, -1.22), 1.02, true)
	_add_world_panel("Card", card_panel, Rect2(280, 130, 720, 460), Vector3(0.0, 0.0, -1.16), 1.12, true)
	# 离屏画布上的感受区与收集区也必须分开，否则左侧面片会采样到右侧收集条目。
	_add_world_panel("Chips", chips, Rect2(24, 170, 300, 330), Vector3(-0.95, -0.02, -1.35), 0.50, false, 0.0, true)
	_add_world_panel("Transition", transition_label, Rect2(350, 105, 580, 55), Vector3(0.0, 0.12, -1.12), 0.72, false)
	_add_world_panel("LookHint", look_hint, Rect2(300, 610, 680, 52), Vector3(0.0, -0.53, -1.15), 0.90, false)
	# 收集夹是屏幕上的一块「口袋」，不该被课桌或同学挡住：叠在所有三维内容之上。
	_add_world_panel(
		"Collected", collected_box, COLLECTED_REGION, COLLECTED_OFFSET, COLLECTED_WIDTH, false, 0.0, true
	)


func _add_world_panel(
	panel_name: String,
	control: Control,
	region: Rect2,
	camera_offset: Vector3,
	world_width: float,
	interactive: bool,
	initial_alpha: float = 0.0,
	overlay: bool = false,
	surface: Node3D = null
) -> void:
	var camera := get_viewport().get_camera_3d()
	var root_3d := Node3D.new()
	root_3d.name = "World" + panel_name
	var panel_parent: Node3D = surface if surface != null else camera
	panel_parent.add_child(root_3d)
	root_3d.position = camera_offset
	if surface == null:
		root_3d.rotation_degrees.x = -4.0 if panel_name in ["Choice", "Card"] else -2.0
	var sprite := Sprite3D.new()
	sprite.name = "Surface"
	var atlas := AtlasTexture.new()
	atlas.atlas = _screen.get_texture()
	atlas.region = region
	sprite.texture = atlas
	sprite.pixel_size = world_width / region.size.x
	sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	# 收集夹是一块 HUD 性质的口袋：永远浮在最上面，不参与遮挡关系。
	sprite.no_depth_test = overlay or panel_name == "Card"
	sprite.shaded = false
	sprite.double_sided = true
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	# 相机前的菜单优先显示；投影布控制条遵循世界中的遮挡关系。
	if panel_name == "Card":
		# 暂停/说明卡必须盖住思绪和收集夹，保证继续与退出按钮可见。
		sprite.render_priority = 12
	elif overlay:
		sprite.render_priority = 9
	else:
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
		"lift": 0.0,
	})


func _process(delta: float) -> void:
	if not _world_ready:
		return
	# 菜单出现时暂收观察夹，既让按钮无遮挡，也避免两个离屏区域交叠采样。
	collected_box.visible = not _collected_rows.is_empty() and not card_panel.visible and not collected_suppressed
	# 背板随实际条目高度贴底伸展，仍在原有离屏采样区域内。
	var folio := _screen.get_node_or_null("CollectedFolio") as Panel
	if folio != null:
		folio.visible = collected_box.visible
		var height := minf(COLLECTED_REGION.size.y, collected_box.get_combined_minimum_size().y)
		folio.position = COLLECTED_REGION.position + Vector2(0, COLLECTED_REGION.size.y - height)
		folio.size = Vector2(COLLECTED_REGION.size.x, height)
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
		# 感受与事件收集分居两侧；保留面板的平滑位置更新。
		var lift := 0.0
		if control == chips and not _collected_rows.is_empty():
			lift = CHIPS_LIFT
		panel["lift"] = move_toward(float(panel["lift"]), lift, delta * 0.55)
		root_3d.position = (
			(panel["base_position"] as Vector3)
			+ Vector3(0.0, float(panel["lift"]) - (1.0 - alpha) * 0.025, 0.0)
		)


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
	style.bg_color = Color(0.09, 0.18, 0.17, 0.94)
	style.border_color = Color(0.65, 0.79, 0.75, 0.78)
	style.set_border_width_all(0)
	style.border_width_left = 2
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	chip.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var title_label := Label.new()
	title_label.text = title
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 18)
	title_label.add_theme_color_override("font_color", Color(0.65, 0.79, 0.75))
	var body_label := Label.new()
	body_label.text = body
	body_label.add_theme_font_size_override("font_size", 24)
	body_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title_label)
	box.add_child(body_label)
	chip.add_child(box)
	chip.modulate = Color(1, 1, 1, 0)
	chips.add_child(chip)
	var record := {"chip": chip, "done": false}
	_chip_records.append(record)
	if _chip_records.size() > 2:
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


## ——— 右下角的收集夹（L1 收集 → L2 展开） ———

## L1 每点开一个观察就往右下角放一条：序号 + 名字，堆成一小叠。
## 只是「我收着了」的反馈，不参与任何判定（判定仍然只看 flow 的 _collected）。
func collect_observation(event_id: StringName, label: String) -> void:
	var key := String(event_id)
	if _collected_rows.has(key):
		return
	if _collected_order.size() >= COLLECTED_LIMIT:
		_drop_collected_row(_collected_order[0])
	_collected_order.append(key)
	var row := _build_collected_row(_collected_order.size() - 1, label)
	collected_box.add_child(row)
	collected_box.visible = true
	_collected_rows[key] = row
	_refresh_collected_title()
	# 从口袋里弹出来：只做透明度与轻微放大（容器会覆盖 position，位移动画会打架）。
	row.modulate.a = 0.0
	row.pivot_offset = Vector2(COLLECTED_REGION.size.x * 0.5, 15.0)
	row.scale = Vector2(0.95, 0.95)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(row, "modulate:a", 1.0, 0.22)
	tween.tween_property(row, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## L2 展开：把这一条从收集夹里抽出来，返回它此刻所在的世界坐标（思绪牌从这里起飞）。
## 返回 Vector3.INF 表示没有这一条（或界面还没准备好）——调用方按「不飞、直接出现」处理。
func expand_collected(event_id: StringName) -> Vector3:
	var key := String(event_id)
	var row_variant: Variant = _collected_rows.get(key)
	if row_variant == null:
		# 没有对应的一行（环境事件本来就没有提示可点）：不飞，直接出现。
		return Vector3.INF
	var origin := collected_world_point()
	_collected_rows.erase(key)
	_collected_order.erase(key)
	_expanded_count += 1
	var row := row_variant as Control
	if is_instance_valid(row):
		# 先亮一下（像被抽出来），再淡出；下面的条目自然补位。
		var tween := create_tween()
		tween.tween_property(row, "modulate", Color(1.16, 1.12, 1.04, 1.0), 0.10)
		tween.tween_property(row, "modulate:a", 0.0, 0.22)
		tween.tween_callback(row.queue_free)
	_refresh_collected_title()
	if _collected_rows.is_empty():
		# 口袋空了就收起来，别在画面角落留一个空框。
		var hide := create_tween()
		hide.tween_interval(0.30)
		hide.tween_callback(func() -> void: collected_box.visible = not _collected_rows.is_empty())
	return origin


## 收集夹当前所在的世界坐标（相机前的右下角）。取不到时返回 Vector3.INF。
func collected_world_point() -> Vector3:
	for panel in _panels:
		if panel["control"] == collected_box:
			var root_3d := panel["root"] as Node3D
			if is_instance_valid(root_3d):
				return root_3d.global_position
	return Vector3.INF


func clear_collected() -> void:
	for key in _collected_rows.keys():
		var row_variant: Variant = _collected_rows[key]
		if is_instance_valid(row_variant):
			(row_variant as Control).queue_free()
	_collected_rows.clear()
	_collected_order.clear()
	_expanded_count = 0
	if collected_box != null:
		collected_box.visible = false
	_refresh_collected_title()


## 测试用：收集夹里还剩哪几条（按放入顺序）。
func debug_collected_rows() -> Array[String]:
	return _collected_order.duplicate()


## 测试用：有多少条已经被抽走、展开到教室里。
func debug_expanded_count() -> int:
	return _expanded_count


func _drop_collected_row(key: String) -> void:
	var row_variant: Variant = _collected_rows.get(key)
	_collected_rows.erase(key)
	_collected_order.erase(key)
	if is_instance_valid(row_variant):
		var row := row_variant as Control
		var tween := create_tween()
		tween.tween_property(row, "modulate:a", 0.0, 0.18)
		tween.tween_callback(row.queue_free)


func _build_collected_row(index: int, label: String) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0.0, 30.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(0.65, 0.79, 0.75, 0.20)
	style.border_width_top = 1
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	row.add_theme_stylebox_override("panel", style)
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 8)
	row.add_child(box)
	var index_label := Label.new()
	index_label.text = "%02d" % (index + 1)
	index_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	index_label.add_theme_font_size_override("font_size", 14)
	index_label.add_theme_color_override("font_color", Color(0.94, 0.80, 0.57, 0.90))
	box.add_child(index_label)
	var name_label := Label.new()
	name_label.text = str(label)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	box.add_child(name_label)
	return row


func _refresh_collected_title() -> void:
	if collected_title != null:
		collected_title.text = "我看到的 · %d" % _collected_order.size()


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
	clear_collected()
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
	skip_button.visible = true


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


func thought_heading() -> String:
	return _text("inner_os")
