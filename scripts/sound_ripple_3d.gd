class_name SoundRipple3D
extends Node3D

## 在「发出动静」的地方播放一圈向外扩散的声纹（环形波纹）。
## 用一张面向相机的 Quad + 极简片段着色器绘制，兼容 GL Compatibility 渲染器。

const SHADER := preload("res://shaders/ring_expand.gdshader")

var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _duration: float = 1.1
var _elapsed: float = 0.0
var _max_radius: float = 1.6


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(_max_radius * 2.0, _max_radius * 2.0)
	_mesh.mesh = quad
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("max_radius", _max_radius)
	_mesh.material_override = _material
	add_child(_mesh)


func setup(world_position: Vector3, color: Color, max_radius: float, duration: float) -> void:
	global_position = world_position
	_max_radius = max_radius
	_duration = duration
	if _material != null:
		_material.set_shader_parameter("ring_color", color)
		_material.set_shader_parameter("max_radius", max_radius)
		var quad := _mesh.mesh as QuadMesh
		if quad != null:
			quad.size = Vector2(_max_radius * 2.0, _max_radius * 2.0)


func _process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	if _material != null:
		_material.set_shader_parameter("progress", t)
	# 安全朝向：仅绕 Y 轴偏航面向相机（避免 look_at 在相机贴近本节点时产生 NaN 退化矩阵）。
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var to_cam := cam.global_position - global_position
		if abs(to_cam.x) > 0.001 or abs(to_cam.z) > 0.001:
			rotation.y = atan2(to_cam.x, to_cam.z)
	if t >= 1.0:
		queue_free()
