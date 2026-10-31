class_name L2FlowState
extends Node3D

## L2「心流状态」/ L3「抽离状态」视觉接口。
##
## L2（activate）：
## - 把 target_root 下的网格替换为灰黑、无贴图的共享材质；
## - 以 focus 节点（或 set_focus_point 的点）为球心，focus_radius 米内保持清晰，
##   之外经过 focus_falloff 米逐渐模糊，并轻微去饱和/压暗。
##
## L3（enter_l3）：
## - 在 L2 的基础上继续：只保留地板（keep_floor_names）与主角（protagonist_path）子树；
## - 进入时把当前带模糊的 L2 画面抓进一个 SubViewport 快照，盖在已切到 L3 的实时画面上，
##   再用 isolation_seconds 淡出快照；模糊、去饱和与压暗一起退场，天空退成虚空；
## - 最后画面只剩纯灰度的地板与主角。
##
## 它不推进剧情，也不假设具体场景。流程控制器或任意脚本都可以调用：
##   flow_state.activate(protagonist.get_node("ViewAnchor"))
##   flow_state.enter_l3()          # L2 → L3，默认 1.6 s 渐变
##   flow_state.leave_l3()          # 退回 L2
##   flow_state.deactivate()
##   flow_state.set_focus_point(world_position)
##   flow_state.set_focus_radius(2.0)
##
## 渲染前提：本项目的 Compatibility 渲染器。depth_texture 是反向 Z，
## 着色器用 near/depth 重建视空间距离；若以后切换到 Forward+，需要重新校准。

signal state_changed(active: bool)
signal isolation_changed(isolated: bool)
signal isolation_finished

const L3_FLOOR_SHADER = preload("res://shaders/l3_floor.gdshader")
## 临时反馈效果（声纹）由 SceneUI3D 生成时打进这个组。它们播完就自己 queue_free，
## 淡出靠自己的材质 alpha；不参与 L2/L3 的灰泥材质替换（分组名两边必须一致）。
const TRANSIENT_FX_GROUP := &"dialogue_fx"

@export var target_root_path: NodePath = ^".."
@export var focus_node_path: NodePath
## L3 保留的主角根节点（相对本节点）。为空时只保留地板。
@export var protagonist_path: NodePath
@export_range(0.0, 4.0, 0.01) var focus_height: float = 1.36
@export_range(0.1, 10.0, 0.1) var focus_radius: float = 2.0
@export_range(0.05, 5.0, 0.05) var focus_falloff: float = 1.2
@export_range(0.0, 64.0, 1.0) var blur_pixels: float = 20.0
@export_range(0.0, 1.0, 0.01) var desaturate: float = 0.15
@export_range(0.0, 0.8, 0.01) var edge_darken: float = 0.25
@export var clay_color: Color = Color(0.27, 0.28, 0.30, 1.0):
	set(value):
		clay_color = value
		if _clay_material != null:
			_clay_material.albedo_color = value.lerp(l3_clay_color, _isolation)
## L3 中保留物件的中性灰（纯灰度，不带蓝/暖色偏）。
@export var l3_clay_color: Color = Color(0.30, 0.30, 0.30, 1.0)
## L3 中天空/背景退成的中性灰，让画面只剩地板与主角。
@export var void_color: Color = Color(0.11, 0.11, 0.11, 1.0)
## 名字匹配的节点（含其子树）在 L3 中保留；默认是教室地板与舞台地台。
@export var keep_floor_names: PackedStringArray = PackedStringArray(["Floor", "StageFloor"])
## L3 专用地面：纯色 + 细线，不接收光照/烘焙阴影，远处淡入虚空。
@export var l3_floor_enabled: bool = true
@export var l3_floor_height: float = 0.0
@export var l3_floor_color: Color = Color(0.42, 0.44, 0.46, 1.0)
@export var l3_floor_line_color: Color = Color(0.22, 0.23, 0.24, 1.0)
@export_range(0.25, 8.0, 0.05) var l3_floor_tile: float = 3.0
@export_range(0.5, 6.0, 0.1) var l3_floor_line_width: float = 0.8
@export_range(4.0, 80.0, 0.5) var l3_floor_fade_start: float = 12.0
@export_range(6.0, 120.0, 0.5) var l3_floor_fade_end: float = 30.0
## L2 → L3 的渐变时长；模糊与颜色在这个时长内一起退场。
@export_range(0.0, 8.0, 0.05) var isolation_seconds: float = 1.6
@export_range(0.0, 3.0, 0.05) var transition_seconds: float = 0.6
@export var auto_activate: bool = false

var _active := false
var _strength := 0.0
var _focus_point := Vector3.ZERO
var _focus_override: Node3D
var _focus_point_override := Vector3.ZERO
var _has_focus_point_override := false
var _clay_material: StandardMaterial3D
var _entries: Array[Dictionary] = []
var _screen: MeshInstance3D
var _material: ShaderMaterial
var _snapshot_viewport: SubViewport
var _snapshot_camera: Camera3D
var _overlay_layer: CanvasLayer
var _overlay: TextureRect
var _l3_floor: MeshInstance3D
var _snapshot_pending := false
var _tween: Tween
var _isolating := false
var _isolation := 0.0
var _isolation_ready := false
var _isolation_tween: Tween


func _ready() -> void:
	_clay_material = _make_clay_material(clay_color)
	_screen = get_node_or_null("Screen") as MeshInstance3D
	if _screen == null:
		push_error("L2FlowState: missing Screen MeshInstance3D.")
		return
	_material = _screen.material_override as ShaderMaterial
	if _material == null:
		push_error("L2FlowState: Screen needs a ShaderMaterial override.")
		return
	_setup_snapshot()
	_setup_l3_floor()
	_screen.visible = false
	_push_static_uniforms()
	set_process(false)
	if auto_activate:
		call_deferred("activate")


func _setup_snapshot() -> void:
	_snapshot_viewport = SubViewport.new()
	_snapshot_viewport.size = _viewport_size()
	_snapshot_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_snapshot_viewport)
	_snapshot_camera = Camera3D.new()
	_snapshot_camera.cull_mask = 0xFFFFF
	_snapshot_camera.current = true
	_snapshot_viewport.add_child(_snapshot_camera)
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 0
	add_child(_overlay_layer)
	_overlay = TextureRect.new()
	_overlay.texture = _snapshot_viewport.get_texture()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.visible = false
	_overlay_layer.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _setup_l3_floor() -> void:
	if not l3_floor_enabled:
		return
	_l3_floor = MeshInstance3D.new()
	_l3_floor.name = "L3Floor"
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	_l3_floor.mesh = plane
	_l3_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_l3_floor.top_level = true
	_l3_floor.visible = false
	var material := ShaderMaterial.new()
	material.shader = L3_FLOOR_SHADER
	_l3_floor.material_override = material
	add_child(_l3_floor)
	_update_l3_floor_material()


func _update_l3_floor_material() -> void:
	if _l3_floor == null:
		return
	var material := _l3_floor.material_override as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("base_color", Vector3(l3_floor_color.r, l3_floor_color.g, l3_floor_color.b))
	material.set_shader_parameter(
		"line_color", Vector3(l3_floor_line_color.r, l3_floor_line_color.g, l3_floor_line_color.b)
	)
	material.set_shader_parameter("void_color", Vector3(void_color.r, void_color.g, void_color.b))
	material.set_shader_parameter("tile_size", maxf(l3_floor_tile, 0.05))
	material.set_shader_parameter("line_width", maxf(l3_floor_line_width, 0.1))
	material.set_shader_parameter("fade_start", maxf(l3_floor_fade_start, 0.0))
	material.set_shader_parameter(
		"fade_end", maxf(l3_floor_fade_end, l3_floor_fade_start + 0.5)
	)


func _show_l3_floor() -> void:
	if _l3_floor == null:
		return
	_l3_floor.global_position = Vector3(
		_focus_point.x, l3_floor_height + 0.002, _focus_point.z
	)
	_update_l3_floor_material()
	_l3_floor.visible = true


func _hide_l3_floor() -> void:
	if _l3_floor != null:
		_l3_floor.visible = false


func _exit_tree() -> void:
	_kill_tween()
	_kill_isolation_tween()
	_restore_materials()


## 当前是否处于心流状态（淡出过程中也算 false）。
func is_active() -> bool:
	return _active


## 当前是否进入/处于 L3 抽离（渐变过程中也算 true）。
func is_l3() -> bool:
	return _isolating


## 抽离渐变进度：0 = 完整 L2 画面，1 = 只剩地板与主角。
func get_isolation_progress() -> float:
	return _isolation


## 抽离是否已经完成（物件已淡出、模糊已归零）。
func is_isolated() -> bool:
	return _isolation_ready


## 进入心流状态。focus 为空时使用 focus_node_path 指向的节点。
func activate(focus: Node3D = null) -> void:
	if _screen == null or _material == null:
		return
	if focus != null:
		_focus_override = focus
		focus_node_path = NodePath()
		_has_focus_point_override = false
	if _active:
		if _strength < 1.0:
			_fade_to(1.0)
		return
	_active = true
	if _entries.is_empty():
		_apply_materials()
	_update_focus_point()
	_screen.visible = true
	set_process(true)
	_fade_to(1.0)
	state_changed.emit(true)


## 进入 L3：从当前 L2 画面渐变到「只有地板与主角、纯灰度、无模糊」。
## focus 同 activate()，可用于临时指定主角清晰球心。
func enter_l3(focus: Node3D = null) -> void:
	if _screen == null or _material == null:
		return
	if focus != null:
		_focus_override = focus
		focus_node_path = NodePath()
		_has_focus_point_override = false
	if not _active:
		activate()
	_update_focus_point()
	_screen.visible = true
	set_process(true)
	if _isolating:
		if _snapshot_pending:
			return
		if not _isolation_ready and _isolation < 1.0:
			_tween_isolation(1.0)
		return
	_prepare_isolation()
	_isolating = true
	isolation_changed.emit(true)
	if isolation_seconds <= 0.0 or not is_inside_tree():
		_hide_unkept_meshes()
		_show_l3_floor()
		_set_isolation_progress(1.0)
		_finish_isolation()
	else:
		_take_snapshot()


## 从 L3 退回 L2：其余网格重新出现、材质回到 L2 灰黑、模糊恢复。
func leave_l3(immediate: bool = false) -> void:
	if not _isolating and _isolation <= 0.0001:
		return
	_isolating = false
	_kill_isolation_tween()
	_show_unkept_meshes()
	_hide_overlay()
	if immediate or isolation_seconds <= 0.0 or not is_inside_tree():
		_finish_leave_isolation()
	else:
		_tween_isolation(0.0, isolation_seconds)
	isolation_changed.emit(false)


func _take_snapshot() -> void:
	var camera := get_viewport().get_camera_3d()
	# 无头测试/服务器没有实际绘制帧，frame_post_draw 不会来；直接切到 L3 结果。
	if camera == null or DisplayServer.get_name() == "headless":
		_hide_unkept_meshes()
		_show_l3_floor()
		_tween_isolation(1.0)
		return
	_snapshot_viewport.size = _viewport_size()
	_snapshot_camera.global_transform = camera.global_transform
	_snapshot_camera.projection = camera.projection
	_snapshot_camera.fov = camera.fov
	_snapshot_camera.size = camera.size
	_snapshot_camera.frustum_offset = camera.frustum_offset
	_snapshot_camera.near = camera.near
	_snapshot_camera.far = camera.far
	_snapshot_camera.keep_aspect = camera.keep_aspect
	_snapshot_camera.h_offset = camera.h_offset
	_snapshot_camera.v_offset = camera.v_offset
	_snapshot_pending = true
	_snapshot_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.frame_post_draw.connect(_on_snapshot_ready, CONNECT_ONE_SHOT)


## 快照渲染完成后，用它盖住刚切到 L3 的实时画面，再开始淡出。
func _on_snapshot_ready() -> void:
	if not _snapshot_pending:
		return
	_snapshot_pending = false
	_snapshot_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if not _isolating:
		return
	_overlay.texture = _snapshot_viewport.get_texture()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.modulate = Color(1.0, 1.0, 1.0, 1.0)
	_overlay.visible = true
	_hide_unkept_meshes()
	_show_l3_floor()
	_set_isolation_progress(0.0)
	_tween_isolation(1.0)


func _hide_overlay() -> void:
	_snapshot_pending = false
	if _overlay != null:
		_overlay.visible = false
	if _snapshot_viewport != null:
		_snapshot_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _hide_unkept_meshes() -> void:
	for entry in _entries:
		if bool(entry.get("kept", true)):
			continue
		var mesh := _entry_mesh(entry)
		if mesh == null:
			continue
		if not entry.has("visible_before"):
			entry["visible_before"] = mesh.visible
		entry["hidden_by_isolation"] = true
		mesh.visible = false


func _show_unkept_meshes() -> void:
	for entry in _entries:
		if bool(entry.get("kept", true)):
			continue
		var mesh := _entry_mesh(entry)
		if mesh == null:
			continue
		if not bool(entry.get("hidden_by_isolation", false)):
			continue
		entry["hidden_by_isolation"] = false
		if entry.has("visible_before"):
			mesh.visible = bool(entry["visible_before"])
		else:
			mesh.visible = true


## 直接按布尔值切换状态，便于接状态机。
func set_active(value: bool) -> void:
	if value:
		activate()
	else:
		deactivate()


## 在进入/退出之间切换；淡出过程中调用会重新进入。
func toggle() -> void:
	set_active(not _active)


## 退出。immediate=true 时不做淡出，直接恢复材质（重开/退出用）。
func deactivate(immediate: bool = false) -> void:
	if not _active:
		if immediate and (_isolation > 0.0001 or _isolating):
			_kill_tween()
			_isolating = false
			_kill_isolation_tween()
			_finish_deactivate()
		return
	_active = false
	var had_isolation := _isolating or _isolation > 0.0001
	if had_isolation:
		_isolating = false
		_kill_isolation_tween()
		_show_unkept_meshes()
		_hide_overlay()
		if immediate or transition_seconds <= 0.0:
			_finish_leave_isolation()
		else:
			_tween_isolation(0.0, transition_seconds)
	if immediate or transition_seconds <= 0.0:
		_kill_tween()
		_finish_deactivate()
	else:
		_fade_to(0.0, _finish_deactivate)
	state_changed.emit(false)
	if had_isolation:
		isolation_changed.emit(false)


## 用世界坐标指定球心；之后不再跟随 focus_node_path。
func set_focus_point(point: Vector3) -> void:
	_focus_override = null
	focus_node_path = NodePath()
	_focus_point_override = point
	_has_focus_point_override = true
	_focus_point = point
	if _active:
		_update_focus_point()


## 用节点指定球心；height 为相对节点原点的抬高量（米），默认沿用 focus_height。
func set_focus_node(node: Node3D, height: float = NAN) -> void:
	_focus_override = node
	focus_node_path = NodePath()
	_has_focus_point_override = false
	if not is_nan(height):
		focus_height = height


func set_focus_radius(value: float) -> void:
	focus_radius = maxf(value, 0.0)
	if _material != null:
		_material.set_shader_parameter("radius", focus_radius)


func set_blur_pixels(value: float) -> void:
	blur_pixels = maxf(value, 0.0)
	if _material != null:
		_material.set_shader_parameter("blur_pixels", blur_pixels * (1.0 - _isolation))


## 场景里新增网格（例如后来实例化的人物）后调用，重新收集并覆盖。
func refresh_targets() -> void:
	if not _active:
		return
	var was_isolating := _isolating
	var was_ready := _isolation_ready
	var progress := _isolation
	_kill_isolation_tween()
	_isolating = false
	_isolation_ready = false
	_restore_materials()
	_apply_materials()
	if not was_isolating:
		return
	_prepare_isolation()
	_isolating = true
	_set_isolation_progress(progress)
	if was_ready or progress >= 0.999:
		_finish_isolation()
	elif progress > 0.0001:
		_tween_isolation(1.0)


func get_clay_mesh_count() -> int:
	return _entries.size()


## L3 中被保留下来的网格数（地板 + 主角 + keep_floor_names 子树）。
func get_kept_mesh_count() -> int:
	var count := 0
	for entry in _entries:
		if bool(entry.get("kept", true)):
			count += 1
	return count


## L3 专用地面（纯色 + 网格线）；`l3_floor_enabled = false` 时为 null。
func get_l3_floor_mesh() -> MeshInstance3D:
	return _l3_floor


func _process(_delta: float) -> void:
	if not _active and _strength <= 0.0001:
		set_process(false)
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null or _screen == null:
		if _screen != null:
			_screen.visible = false
		return
	_update_focus_point()
	_update_screen(camera)
	_screen.visible = _active or _strength > 0.0001


func _update_focus_point() -> void:
	var node := _focus_override
	if node == null and not focus_node_path.is_empty():
		node = get_node_or_null(focus_node_path) as Node3D
	if node != null and is_instance_valid(node):
		_focus_point = node.global_position + Vector3.UP * focus_height
	elif _has_focus_point_override:
		_focus_point = _focus_point_override


func _update_screen(camera: Camera3D) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y <= 1.0:
		return
	var aspect := viewport_size.x / viewport_size.y
	var tan_half := tan(deg_to_rad(camera.fov) * 0.5)
	const SCREEN_DISTANCE := 1.0
	var height := 2.0 * SCREEN_DISTANCE * tan_half
	_screen.global_transform = camera.global_transform * Transform3D(
		Basis().scaled(Vector3(height * aspect, height, 1.0)),
		Vector3(0.0, 0.0, -SCREEN_DISTANCE)
	)
	var focus_view := camera.global_transform.affine_inverse() * _focus_point
	var sharp := 1.0 - _isolation
	_material.set_shader_parameter("focus_view", focus_view)
	_material.set_shader_parameter("near", camera.near)
	_material.set_shader_parameter("tan_half_fov", tan_half)
	_material.set_shader_parameter("aspect", aspect)
	_material.set_shader_parameter("strength", _strength)
	_material.set_shader_parameter("radius", focus_radius)
	_material.set_shader_parameter("falloff", focus_falloff)
	_material.set_shader_parameter("blur_pixels", blur_pixels * sharp)
	_material.set_shader_parameter("desaturate", desaturate * sharp)
	_material.set_shader_parameter("edge_darken", edge_darken * sharp)
	_material.set_shader_parameter("grayscale", _isolation)
	_material.set_shader_parameter("void_blend", _isolation)
	_material.set_shader_parameter("void_color", Vector3(void_color.r, void_color.g, void_color.b))


func _push_static_uniforms() -> void:
	_material.set_shader_parameter("radius", focus_radius)
	_material.set_shader_parameter("falloff", focus_falloff)
	_material.set_shader_parameter("blur_pixels", blur_pixels)
	_material.set_shader_parameter("desaturate", desaturate)
	_material.set_shader_parameter("edge_darken", edge_darken)
	_material.set_shader_parameter("grayscale", 0.0)
	_material.set_shader_parameter("void_blend", 0.0)
	_material.set_shader_parameter("void_color", Vector3(void_color.r, void_color.g, void_color.b))
	_material.set_shader_parameter("strength", 0.0)


func _apply_materials() -> void:
	_entries.clear()
	var root := _resolved_target_root()
	if root == null:
		push_warning("L2FlowState: target root not found.")
		return
	_collect_meshes(root)


func _collect_meshes(node: Node) -> void:
	# 声纹这类临时反馈整棵子树跳过：换成灰泥会让它的淡出失效，节点释放后还会
	# 在清单里变成已释放对象（见 _entry_mesh）。
	if node.is_in_group(TRANSIENT_FX_GROUP):
		return
	if node is MeshInstance3D and not _is_own_node(node):
		var mesh := node as MeshInstance3D
		_entries.append({"node": mesh, "override": mesh.material_override})
		mesh.material_override = _clay_material
	for child in node.get_children():
		_collect_meshes(child)


## 从清单里取网格。清单会跨帧、跨数秒存活，期间节点可能已被释放（临时效果、
## 运行时生成的网格等）。Variant 里若存着已释放对象，直接 `as` 会抛
## "Trying to cast a freed object" 并中断整个函数——L3 渐变、复位都会停在半截，
## 所以必须先 is_instance_valid 判活（它对已释放对象安全返回 false），再取类型。
func _entry_mesh(entry: Dictionary) -> MeshInstance3D:
	var node: Variant = entry.get("node")
	if not is_instance_valid(node):
		return null
	return node as MeshInstance3D


func _restore_materials() -> void:
	for entry in _entries:
		var mesh := _entry_mesh(entry)
		if mesh == null:
			continue
		if mesh.material_override == _clay_material:
			mesh.material_override = entry["override"]
		if entry.has("visible_before"):
			mesh.visible = bool(entry["visible_before"])
	_entries.clear()
	_isolation_ready = false


func _prepare_isolation() -> void:
	var protagonist := _resolved_protagonist()
	var target_root := _resolved_target_root()
	for entry in _entries:
		var mesh := _entry_mesh(entry)
		if mesh == null:
			continue
		if not entry.has("visible_before"):
			entry["visible_before"] = mesh.visible
		entry["kept"] = _should_keep(mesh, protagonist, target_root)
		entry["hidden_by_isolation"] = false


func _should_keep(mesh: MeshInstance3D, protagonist: Node3D, target_root: Node3D) -> bool:
	if protagonist != null and is_instance_valid(protagonist):
		if mesh == protagonist or protagonist.is_ancestor_of(mesh):
			return true
	var node: Node = mesh
	while node != null:
		if keep_floor_names.has(String(node.name)):
			return true
		if node == self or node == target_root:
			break
		node = node.get_parent()
	return false


func _finish_isolation() -> void:
	if not _isolating or _isolation_ready:
		return
	_isolation_ready = true
	_set_isolation_progress(1.0)
	_hide_unkept_meshes()
	_show_l3_floor()
	_hide_overlay()
	isolation_finished.emit()


func _finish_leave_isolation() -> void:
	_set_isolation_progress(0.0)
	_show_unkept_meshes()
	_hide_overlay()
	_hide_l3_floor()
	_isolation_ready = false


func _set_isolation_progress(value: float) -> void:
	_isolation = clampf(value, 0.0, 1.0)
	var current := clay_color.lerp(l3_clay_color, _isolation)
	if _clay_material != null:
		_clay_material.albedo_color = current
	if _overlay != null:
		_overlay.modulate.a = 1.0 - _isolation
		if _isolation >= 0.999:
			_overlay.visible = false
	if _material != null:
		var sharp := 1.0 - _isolation
		_material.set_shader_parameter("grayscale", _isolation)
		_material.set_shader_parameter("void_blend", _isolation)
		_material.set_shader_parameter("blur_pixels", blur_pixels * sharp)
		_material.set_shader_parameter("desaturate", desaturate * sharp)
		_material.set_shader_parameter("edge_darken", edge_darken * sharp)


func _tween_isolation(target: float, seconds: float = -1.0) -> void:
	_kill_isolation_tween()
	var duration := isolation_seconds if seconds < 0.0 else seconds
	if target >= 0.999:
		_isolation_ready = false
	if not is_inside_tree() or duration <= 0.0:
		_set_isolation_progress(target)
		if target >= 0.999:
			_finish_isolation()
		else:
			_finish_leave_isolation()
		return
	_isolation_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_isolation_tween.tween_method(_set_isolation_progress, _isolation, target, duration).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	if target >= 0.999:
		_isolation_tween.tween_callback(_finish_isolation)
	else:
		_isolation_tween.tween_callback(_finish_leave_isolation)


func _resolved_protagonist() -> Node3D:
	if protagonist_path.is_empty():
		return null
	return get_node_or_null(protagonist_path) as Node3D


func _resolved_target_root() -> Node3D:
	var node := get_node_or_null(target_root_path)
	if node is Node3D:
		return node as Node3D
	return get_parent() as Node3D


func _is_own_node(node: Node) -> bool:
	return node == self or is_ancestor_of(node)


func _make_clay_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


func _viewport_size() -> Vector2i:
	var size := get_viewport().get_visible_rect().size
	return Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))


func _fade_to(target: float, on_finished: Callable = Callable()) -> void:
	_kill_tween()
	if not is_inside_tree() or transition_seconds <= 0.0:
		_strength = target
		if on_finished.is_valid():
			on_finished.call()
		return
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_tween.tween_property(self, "_strength", target, transition_seconds).set_trans(
		Tween.TRANS_SINE
	).set_ease(Tween.EASE_IN_OUT)
	if on_finished.is_valid():
		_tween.tween_callback(on_finished)


func _finish_deactivate() -> void:
	if _active:
		return
	_strength = 0.0
	if _screen != null:
		_screen.visible = false
	_hide_overlay()
	_hide_l3_floor()
	_show_unkept_meshes()
	set_process(false)
	_isolating = false
	_kill_isolation_tween()
	_set_isolation_progress(0.0)
	_restore_materials()


func _kill_tween() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null


func _kill_isolation_tween() -> void:
	if _isolation_tween != null:
		_isolation_tween.kill()
		_isolation_tween = null
