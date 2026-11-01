class_name L2Thought3D
extends Node3D

## 第二层的「思绪」在教室里的样子。
##
## 它不是贴在相机前的一块面片，而是长在那件事发生的位置上：一个亮点钉住真正发生的地方，
## 一条细线往上拉起一块朝向镜头的文字牌。相机不动时牌面按距离缩放（屏幕上占比基本恒定），
## 转头时会看出它确实在那个座位、那张桌子那边，而不是浮在屏幕中央。
##
## 由 SceneUI3D 按 DialogueFlow.thought_presented 生成；生命周期只由呈现层控制，
## 不推进任何剧情时序。文字牌是 Sprite3D、亮点与引线是 MeshInstance3D，整棵子树打进
## L2FlowState.TRANSIENT_FX_GROUP：灰泥材质替换会跳过它，L3 抽离也不会把它一起隐藏。
##
## 两条取值原则：
## 1. 屏幕占比固定（而不是世界尺寸固定）：远处的事件不能小到读不出来——可读性优先于透视正确。
## 2. 牌面始终贴回画内：锚点可能靠画面边缘（事件坐标来自内容），牌面按相机上/右方向平移，
##    只平移、不缩小，所以「它挂在那儿」的关系还在。

## 与 L2FlowState.TRANSIENT_FX_GROUP 必须一致：临时三维效果不进灰泥材质清单。
const FX_GROUP := &"dialogue_fx"
const TEXT_WIDTH := 480.0
## 正文 28 px 时一行大约放得下多少汉字（用于估算面板高度，不参与排版）。
const CHARS_PER_LINE := 15.0
const LINE_HEIGHT := 34.0
const TITLE_HEIGHT := 20.0
## 牌面四周至少留出这么多屏幕像素，别贴着画面边缘。
const FRAME_MARGIN := 20.0
## 顶端还要避开顶部控制条（世界面板；它排在思绪牌之上，别让牌钻到它下面去）。
const FRAME_TOP_MARGIN := 122.0

## 文字牌占屏幕宽度的比例。
@export var screen_fraction: float = 0.26
## 牌下沿离锚点（那个亮点）的高度，米。
@export var lift_gap: float = 0.14
## 锚点亮点的半径，米。
@export var anchor_radius: float = 0.038

var _accent := Color(0.61, 0.85, 0.84)
var _viewport: SubViewport
var _panel: PanelContainer
var _sprite: Sprite3D
var _line: MeshInstance3D
var _marker: MeshInstance3D
var _material: StandardMaterial3D
var _alpha := 0.0
var _time := 0.0
var _tween: Tween
var _leaving := false
## 正在从收集夹飞向锚点：飞行中不做「拉回画内」的平移，否则牌会被一路按住。
var _flying := false


func setup(title: String, body: String, accent: Color) -> void:
	add_to_group(FX_GROUP)
	_accent = accent
	_build_viewport(str(title), str(body))
	_build_marker()
	set_process(true)


## 锚点世界坐标（那个亮点的位置）。测试用。
func anchor_position() -> Vector3:
	return global_position


## 文字牌当前的世界坐标（平移之后）。测试用。
func card_position() -> Vector3:
	if _sprite == null:
		return global_position
	return _sprite.global_position


func appear(seconds: float = 0.28) -> void:
	_kill_tween()
	_leaving = false
	_flying = false
	if seconds <= 0.0 or not is_inside_tree():
		_apply_alpha(1.0)
		return
	_apply_alpha(0.0)
	_tween = create_tween()
	_tween.tween_method(_apply_alpha, 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE)


## 从收集夹的位置飞出来，落在这条思绪该在的地方。
## L1 收着的那一条在 L2 被抽走 → 从这里起飞，玩家看得见「口袋里那件事长回了教室里」。
func appear_from(origin: Vector3, seconds: float = 0.62) -> void:
	var anchor := global_position
	if seconds <= 0.0 or not is_inside_tree() or origin.distance_to(anchor) < 0.08:
		appear()
		return
	_kill_tween()
	_leaving = false
	_flying = true
	_apply_alpha(0.0)
	var start := origin
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(
		func(t: float) -> void:
			if not is_inside_tree():
				return
			# 先往上抛一点再落位：直线会像被瞬移，弧线才像「飞过去」。
			global_position = start.lerp(anchor, t) + Vector3.UP * sin(t * PI) * 0.24,
		0.0, 1.0, seconds
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_method(_apply_alpha, 0.0, 1.0, seconds * 0.7)
	_tween.chain().tween_callback(func() -> void: _flying = false)


func dismiss(seconds: float = 0.30) -> void:
	if _leaving:
		return
	_leaving = true
	_kill_tween()
	if seconds <= 0.0 or not is_inside_tree():
		queue_free()
		return
	_tween = create_tween()
	_tween.tween_method(_apply_alpha, _alpha, 0.0, seconds).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(queue_free)


func _process(delta: float) -> void:
	_time += delta
	_layout()


## 按相机距离重算缩放、并把牌面拉回画内；引线从锚点连到牌下沿。
func _layout() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null or _sprite == null or _viewport == null:
		return
	var view := get_viewport().get_visible_rect().size
	if view.y <= 1.0:
		return
	var aspect := view.x / view.y
	var distance := clampf(camera.global_position.distance_to(global_position), 0.8, 9.0)
	var visible_width := 2.0 * distance * tan(deg_to_rad(camera.fov * 0.5)) * aspect
	var pixel := screen_fraction * visible_width / float(_viewport.size.x)
	_sprite.pixel_size = pixel
	var half_width := float(_viewport.size.x) * pixel * 0.5
	var half_height := float(_viewport.size.y) * pixel * 0.5

	var bob := sin(_time * 1.25) * 0.01
	var center := Vector3(0.0, lift_gap + bob + half_height, 0.0)
	if not _flying:
		center = _shift_into_frame(camera, center, half_width, half_height, view, distance)
	_sprite.position = center
	_connect_leader(center - Vector3(0.0, half_height, 0.0))


## 牌面若会顶出画外，就沿相机的上/右方向平移回来（只平移，不缩小）。
func _shift_into_frame(
	camera: Camera3D,
	center: Vector3,
	half_width: float,
	half_height: float,
	view: Vector2,
	distance: float
) -> Vector3:
	var basis_inv := global_transform.basis.inverse()
	var up_local := (basis_inv * camera.global_basis.y).normalized()
	var right_local := (basis_inv * camera.global_basis.x).normalized()
	var screen := camera.unproject_position(to_global(center))
	var top := camera.unproject_position(to_global(center + up_local * half_height))
	var bottom := camera.unproject_position(to_global(center - up_local * half_height))
	var left := camera.unproject_position(to_global(center - right_local * half_width))
	var right := camera.unproject_position(to_global(center + right_local * half_width))
	var half_h := maxf(absf(top.y - screen.y), absf(bottom.y - screen.y))
	var half_w := maxf(absf(left.x - screen.x), absf(right.x - screen.x))
	var shift := Vector2.ZERO
	if screen.y - half_h < FRAME_TOP_MARGIN:
		shift.y = FRAME_TOP_MARGIN - (screen.y - half_h)
	elif screen.y + half_h > view.y - FRAME_MARGIN:
		shift.y = (view.y - FRAME_MARGIN) - (screen.y + half_h)
	if screen.x - half_w < FRAME_MARGIN:
		shift.x = FRAME_MARGIN - (screen.x - half_w)
	elif screen.x + half_w > view.x - FRAME_MARGIN:
		shift.x = (view.x - FRAME_MARGIN) - (screen.x + half_w)
	if shift.is_zero_approx():
		return center
	var world_per_pixel := 2.0 * tan(deg_to_rad(camera.fov * 0.5)) * distance / view.y
	return center + up_local * (-shift.y * world_per_pixel) + right_local * (shift.x * world_per_pixel)


## 从锚点（原点）到牌下沿的一条细线：牌被平移过，线也跟着斜过去。
func _connect_leader(bottom: Vector3) -> void:
	var length := bottom.length()
	if length < 0.02:
		_line.visible = false
		return
	_line.visible = true
	var basis := Basis(Quaternion(Vector3.UP, bottom / length)).scaled(
		Vector3(1.0, length, 1.0)
	)
	_line.transform = Transform3D(basis, bottom * 0.5)


func _build_viewport(title: String, body: String) -> void:
	_viewport = SubViewport.new()
	_viewport.name = "ThoughtViewport"
	_viewport.size = Vector2i(int(TEXT_WIDTH), _estimate_height(body))
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.020, 0.037, 0.050, 0.74)
	style.border_color = Color(_accent.r, _accent.g, _accent.b, 0.62)
	style.set_border_width_all(1)
	style.set_corner_radius_all(15)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 13
	style.content_margin_bottom = 14
	style.shadow_color = Color(0, 0, 0, 0.34)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 4)
	panel.add_theme_stylebox_override("panel", style)
	_viewport.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 17)
	title_label.add_theme_color_override("font_color", _accent)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title_label)

	var body_label := Label.new()
	body_label.text = body
	body_label.add_theme_font_size_override("font_size", 28)
	body_label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.93))
	body_label.add_theme_constant_override("line_spacing", 5)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(body_label)

	_sprite = Sprite3D.new()
	_sprite.name = "Surface"
	_sprite.texture = _viewport.get_texture()
	# 只在水平方向转向镜头：字始终是立的，像一块插在那里的牌子。
	_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	# 可读优先：灰泥教室里课桌、椅背不能把正在说的字挡掉（与世界字幕同一条规则）。
	_sprite.no_depth_test = true
	_sprite.shaded = false
	_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_sprite.render_priority = 6
	_sprite.modulate.a = 0.0
	add_child(_sprite)
	# 正文换行后的真实高度只有排版完才知道（估算值只用于第一帧）：
	# 差太多会把最后一行切掉，所以排完版再按内容高度把视口贴紧。
	call_deferred("_fit_to_content", 0)


## 把离屏视口的高度贴到内容高度：面板本身是 PRESET_FULL_RECT，视口多高它就多高，
## 内容顶对齐，所以视口高度 = 内容高度时正好贴边，不多不少。
func _fit_to_content(attempt: int) -> void:
	if _panel == null or _viewport == null:
		return
	var needed := int(ceili(_panel.get_combined_minimum_size().y))
	if needed < 4 or attempt > 3 or absi(needed - _viewport.size.y) <= 1:
		return
	_viewport.size = Vector2i(int(TEXT_WIDTH), needed)
	call_deferred("_fit_to_content", attempt + 1)


func _build_marker() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.disable_receive_shadows = true
	# 必须排在 L2 后处理四边形之后（它是 render_priority 2 的全屏模糊/灰化）：
	# 否则这个 20 多像素的点会被一起糊掉，看起来像根本没画。
	_material.render_priority = 5
	_material.albedo_color = _accent

	# 亮点：从任何角度看都是一个点，比平躺的圆环更容易看见「就在这儿」。
	var dot := SphereMesh.new()
	dot.radius = anchor_radius
	dot.height = anchor_radius * 2.0
	dot.radial_segments = 12
	dot.rings = 6
	_marker = MeshInstance3D.new()
	_marker.name = "Anchor"
	_marker.mesh = dot
	_marker.material_override = _material
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_marker)

	var needle := CylinderMesh.new()
	needle.top_radius = 0.0032
	needle.bottom_radius = 0.0032
	needle.height = 1.0
	needle.radial_segments = 6
	needle.rings = 0
	_line = MeshInstance3D.new()
	_line.name = "Leader"
	_line.mesh = needle
	_line.material_override = _material
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)


## 面板高度按正文字数估算（与世界字幕同一套粗略排版，够用即可）。
func _estimate_height(body: String) -> int:
	var lines := 0
	for raw in body.split("\n"):
		lines += maxi(1, ceili(float(str(raw).length()) / CHARS_PER_LINE))
	return int(27 + TITLE_HEIGHT + 7 + float(lines) * LINE_HEIGHT)


func _apply_alpha(value: float) -> void:
	_alpha = clampf(value, 0.0, 1.0)
	if _sprite != null:
		_sprite.modulate.a = _alpha
	if _material != null:
		var color := _accent
		color.a = _alpha * 0.85
		_material.albedo_color = color


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _exit_tree() -> void:
	_kill_tween()
