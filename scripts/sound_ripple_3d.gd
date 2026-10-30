class_name SoundRipple3D
extends Node3D

## 在「发出动静」的地方播放一圈向外扩散的声纹（环形波纹）。
## 用 TorusMesh（内置图元）+ StandardMaterial3D 实现，零自定义着色器，
## 完全兼容 GL Compatibility 渲染器，规避自定义 ShaderMaterial 在部分后端运行时崩溃的风险。

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _duration: float = 1.1
var _elapsed: float = 0.0
var _max_radius: float = 1.6
var _base_color: Color = Color(0.62, 0.86, 1.0, 1.0)
# setup() 可能在 add_child 之前被调用（此时 _material 尚未创建，且节点未入树，
# 设 global_position 会被当成局部坐标导致位置错乱），故先暂存，_ready 里再应用。
var _pending_position: Vector3 = Vector3.ZERO
var _pending_color: Color = Color(0.62, 0.86, 1.0, 1.0)


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.05
	torus.outer_radius = 0.12
	_mesh.mesh = torus
	_material = StandardMaterial3D.new()
	_base_color = _pending_color
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = _base_color
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_material.emission_enabled = true
	_material.emission = _base_color
	_material.emission_energy_multiplier = 1.2
	_mesh.material_override = _material
	add_child(_mesh)
	# 起始极小，避免第一帧突兀出现
	_mesh.scale = Vector3(0.01, 0.01, 0.01)
	# _ready 在 add_child 时同步触发，此时已入树，可安全应用 setup() 暂存的数据。
	if is_inside_tree():
		global_position = _pending_position


func setup(world_position: Vector3, color: Color, max_radius: float, duration: float) -> void:
	# 先暂存；若节点尚未入树，_material 还没创建，等 _ready 再应用。
	_pending_position = world_position
	_pending_color = color
	_max_radius = max_radius
	_duration = duration
	_base_color = color
	if _material != null:
		_material.albedo_color = color
		_material.emission = color
	if is_inside_tree():
		global_position = world_position


func _process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	var s := lerpf(0.15, _max_radius, t)
	_mesh.scale = Vector3(s, s, s)
	if _material != null:
		var a := 1.0 - t
		_material.albedo_color.a = a
		_material.emission.a = a
	if t >= 1.0:
		queue_free()
