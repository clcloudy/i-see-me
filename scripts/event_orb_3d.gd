class_name EventOrb3D
extends Node3D

## 三维世界中「可被观察到的事件」标记：一个会轻微浮动与脉动的小球，
## 玩家点击即可收集（收集后缩小上浮并释放）。由 SceneUI3D 在事件触发时生成。

signal collected(orb: EventOrb3D)

const ORB_COLOR := Color(0.55, 0.85, 1.0)
const ORB_EMISSION := Color(0.40, 0.80, 1.0)

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _area: Area3D
var _label: Label3D
var _bob_t := 0.0
var _collected := false


func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	_mesh.mesh = sphere
	_material = StandardMaterial3D.new()
	_material.albedo_color = ORB_COLOR
	_material.emission_enabled = true
	_material.emission = ORB_EMISSION
	_material.emission_energy_multiplier = 1.4
	_material.roughness = 0.45
	_material.metallic = 0.0
	_mesh.material_override = _material
	add_child(_mesh)

	_area = Area3D.new()
	_area.input_event.connect(_on_input_event)
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.4
	col.shape = shape
	_area.add_child(col)
	add_child(_area)

	_label = Label3D.new()
	_label.text = ""
	_label.font_size = 36
	_label.pixel_size = 0.004
	_label.modulate = Color(0.92, 0.97, 1.0)
	_label.outline_size = 5
	_label.outline_modulate = Color(0.05, 0.09, 0.13)
	_label.position = Vector3(0.0, 0.30, 0.0)
	# 用内置公告板（仅绕 Y 轴、保持直立）面向相机——比手动 look_at 安全，
	# 相机贴近小球时也不会产生 NaN 变换。
	_label.billboard = Label3D.BILLBOARD_FIXED_Y
	add_child(_label)


func setup(world_position: Vector3, label_text: String) -> void:
	global_position = world_position
	_label.text = label_text


func _process(delta: float) -> void:
	if _collected:
		return
	_bob_t += delta
	_mesh.position.y = sin(_bob_t * 2.0) * 0.06
	var pulse := 1.0 + sin(_bob_t * 3.0) * 0.18
	_material.emission_energy_multiplier = 1.2 * pulse
	# 标签朝向由 billboard = BILLBOARD_FIXED_Y 自动处理，无需每帧 look_at。


func _on_input_event(_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if _collected:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_collect()


func collect_external() -> void:
	if not _collected:
		_collect()


func _collect() -> void:
	_collected = true
	collected.emit(self)
	var tween := create_tween()
	tween.tween_property(_mesh, "scale", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(self, "global_position:y", global_position.y + 0.45, 0.4)
	tween.tween_callback(queue_free)
