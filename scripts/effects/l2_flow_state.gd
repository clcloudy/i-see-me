class_name L2FlowState
extends Node3D

## L2「心流状态」视觉接口。
##
## 激活时：
## - 把 target_root 下的网格替换为灰黑、无贴图的共享材质；
## - 以 focus 节点（或 set_focus_point 的点）为球心，focus_radius 米内保持清晰，
##   之外经过 focus_falloff 米逐渐模糊，并轻微去饱和/压暗。
##
## 它不推进剧情，也不假设具体场景。流程控制器或任意脚本都可以调用：
##   flow_state.activate(protagonist.get_node("ViewAnchor"))
##   flow_state.deactivate()
##   flow_state.set_focus_point(world_position)
##   flow_state.set_focus_radius(2.0)
##
## 渲染前提：本项目的 Compatibility 渲染器。depth_texture 是反向 Z，
## 着色器用 near/depth 重建视空间距离；若以后切换到 Forward+，需要重新校准。

signal state_changed(active: bool)

@export var target_root_path: NodePath = ^".."
@export var focus_node_path: NodePath
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
			_clay_material.albedo_color = value
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
var _tween: Tween


func _ready() -> void:
	_clay_material = StandardMaterial3D.new()
	_clay_material.albedo_color = clay_color
	_clay_material.roughness = 1.0
	_clay_material.metallic = 0.0
	_clay_material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_screen = get_node_or_null("Screen") as MeshInstance3D
	if _screen == null:
		push_error("L2FlowState: missing Screen MeshInstance3D.")
		return
	_material = _screen.material_override as ShaderMaterial
	if _material == null:
		push_error("L2FlowState: Screen needs a ShaderMaterial override.")
		return
	_screen.visible = false
	_push_static_uniforms()
	set_process(false)
	if auto_activate:
		call_deferred("activate")


func _exit_tree() -> void:
	_kill_tween()
	_restore_materials()


## 当前是否处于心流状态（淡出过程中也算 false）。
func is_active() -> bool:
	return _active


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


## 直接按布尔值切换状态，便于接状态机。
func set_active(value: bool) -> void:
	if value:
		activate()
	else:
		deactivate()


## 在进入/退出之间切换；淡出过程中调用会重新进入。
func toggle() -> void:
	set_active(not _active)


## 退出心流状态。immediate=true 时不做淡出，直接恢复材质（重开/退出用）。
func deactivate(immediate: bool = false) -> void:
	if not _active:
		if immediate and _strength > 0.0001:
			_kill_tween()
			_finish_deactivate()
		return
	_active = false
	if immediate or transition_seconds <= 0.0:
		_kill_tween()
		_finish_deactivate()
	else:
		_fade_to(0.0, _finish_deactivate)
	state_changed.emit(false)


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
		_material.set_shader_parameter("blur_pixels", blur_pixels)


## 场景里新增网格（例如后来实例化的人物）后调用，重新收集并覆盖。
func refresh_targets() -> void:
	if not _active:
		return
	_restore_materials()
	_apply_materials()


func get_clay_mesh_count() -> int:
	return _entries.size()


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
	_material.set_shader_parameter("focus_view", focus_view)
	_material.set_shader_parameter("near", camera.near)
	_material.set_shader_parameter("tan_half_fov", tan_half)
	_material.set_shader_parameter("aspect", aspect)
	_material.set_shader_parameter("strength", _strength)
	_material.set_shader_parameter("radius", focus_radius)
	_material.set_shader_parameter("falloff", focus_falloff)
	_material.set_shader_parameter("blur_pixels", blur_pixels)
	_material.set_shader_parameter("desaturate", desaturate)
	_material.set_shader_parameter("edge_darken", edge_darken)


func _push_static_uniforms() -> void:
	_material.set_shader_parameter("radius", focus_radius)
	_material.set_shader_parameter("falloff", focus_falloff)
	_material.set_shader_parameter("blur_pixels", blur_pixels)
	_material.set_shader_parameter("desaturate", desaturate)
	_material.set_shader_parameter("edge_darken", edge_darken)
	_material.set_shader_parameter("strength", 0.0)


func _apply_materials() -> void:
	_entries.clear()
	var root := _resolved_target_root()
	if root == null:
		push_warning("L2FlowState: target root not found.")
		return
	_collect_meshes(root)


func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D and not _is_own_node(node):
		var mesh := node as MeshInstance3D
		_entries.append({"node": mesh, "override": mesh.material_override})
		mesh.material_override = _clay_material
	for child in node.get_children():
		_collect_meshes(child)


func _restore_materials() -> void:
	for entry in _entries:
		var mesh := entry["node"] as MeshInstance3D
		if mesh == null or not is_instance_valid(mesh):
			continue
		if mesh.material_override == _clay_material:
			mesh.material_override = entry["override"]
	_entries.clear()


func _resolved_target_root() -> Node3D:
	var node := get_node_or_null(target_root_path)
	if node is Node3D:
		return node as Node3D
	return get_parent() as Node3D


func _is_own_node(node: Node) -> bool:
	return node == self or is_ancestor_of(node)


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
	set_process(false)
	_restore_materials()


func _kill_tween() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null
