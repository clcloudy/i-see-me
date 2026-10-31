class_name SoundRipple3D
extends Node3D

## 轻量声纹：断续的细弧向外舒展，不使用粗圆环或自定义着色器。
## 纯网格 + StandardMaterial3D，兼容 GL Compatibility。

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _duration: float = 0.9
var _elapsed: float = 0.0
var _max_radius: float = 0.7
var _base_color: Color = Color(0.61, 0.85, 0.84, 0.55)
var _pending_position: Vector3 = Vector3.ZERO
var _pending_color: Color = Color(0.61, 0.85, 0.84, 0.55)


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_base_color = _pending_color
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_material.albedo_color = Color(_base_color, 0.0)
	_material.emission_enabled = true
	_material.emission = _base_color
	_material.emission_energy_multiplier = 0.35

	var geometry := ImmediateMesh.new()
	geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	const ARCS := 3
	const DASHES := 7
	const ARC_SPAN := 1.0123 # 58 度
	for arc in range(ARCS):
		var base := TAU * float(arc) / ARCS + 0.28
		for i in range(DASHES):
			var a0 := base + ARC_SPAN * float(i) / DASHES + 0.025
			var a1 := base + ARC_SPAN * float(i + 1) / DASHES - 0.025
			var inner_a := Vector3(cos(a0), sin(a0), 0.0) * 0.965
			var outer_a := Vector3(cos(a0), sin(a0), 0.0)
			var inner_b := Vector3(cos(a1), sin(a1), 0.0) * 0.965
			var outer_b := Vector3(cos(a1), sin(a1), 0.0)
			for vertex in [inner_a, outer_a, outer_b, inner_a, outer_b, inner_b]:
				geometry.surface_add_vertex(vertex)
	geometry.surface_end()

	_mesh = MeshInstance3D.new()
	_mesh.mesh = geometry
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.scale = Vector3.ONE * 0.01
	add_child(_mesh)
	if is_inside_tree():
		global_position = _pending_position


func setup(world_position: Vector3, color: Color, max_radius: float, duration: float) -> void:
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
	var eased := 1.0 - pow(1.0 - t, 3.0)
	var radius := lerpf(0.08, _max_radius, eased)
	_mesh.scale = Vector3.ONE * radius
	if _material != null:
		var fade_in := clampf(t / 0.10, 0.0, 1.0)
		var alpha := pow(1.0 - t, 1.6) * fade_in * 0.42
		_material.albedo_color = Color(_base_color, alpha)
		_material.emission = Color(_base_color, alpha)
	if t >= 1.0:
		queue_free()
