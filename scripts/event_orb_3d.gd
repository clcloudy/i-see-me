class_name EventOrb3D
extends Node3D

## 可观察事件的空间提示：观察符号 + 明确的“点击观察”标签。
## 类名沿用 EventOrb3D 以兼容流程与测试，但视觉不再是发光球体。

signal collected(orb: EventOrb3D)

const MARKER_TEXTURE := preload("res://assets/ui/observe_marker.svg")
const TAG_TEXTURE := preload("res://assets/ui/observation_tag.svg")
const INK := Color(0.84, 0.95, 0.93)
const ACCENT := Color(0.95, 0.80, 0.55)
const SHORT_NAMES := {
	"被悄悄捡回来的笔": "捡笔",
	"同学们稍微松了口气": "松口气",
	"同学们三两回头看主角": "回头",
	"有人还在忙自己的事": "低头",
	"E02｜低笑": "低笑",
	"03｜被听成了另一个意思": "误听",
	"04｜听见不同意见": "分歧",
	"E03｜轻声赞同": "赞同",
}

var _visual: Node3D
var _icon: Sprite3D
var _tag: Sprite3D
var _label: Label3D
var _area: Area3D
var _bob_t: float = 0.0
var _collected: bool = false
var _hovered: bool = false
var _full_text: String = ""
var _short_text: String = ""
var _pending_label: String = ""
var _pending_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	_icon = Sprite3D.new()
	_icon.texture = MARKER_TEXTURE
	_icon.pixel_size = 0.00108
	_icon.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_icon.no_depth_test = false
	_icon.shaded = false
	_icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_icon.render_priority = 3
	_visual.add_child(_icon)

	_tag = Sprite3D.new()
	_tag.texture = TAG_TEXTURE
	_tag.pixel_size = 0.00145
	_tag.scale.x = 0.64
	_tag.position = Vector3(0.0, -0.225, 0.0)
	_tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_tag.no_depth_test = false
	_tag.shaded = false
	_tag.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_tag.modulate.a = 0.94
	_tag.render_priority = 3
	_visual.add_child(_tag)

	_label = Label3D.new()
	_label.font_size = 25
	_label.pixel_size = 0.0022
	_label.modulate = INK
	_label.outline_size = 4
	_label.outline_modulate = Color(0.025, 0.055, 0.075, 0.96)
	_label.position = Vector3(0.0, -0.221, 0.008)
	_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_label.no_depth_test = false
	_visual.add_child(_label)

	_area = Area3D.new()
	_area.input_event.connect(_on_input_event)
	_area.mouse_entered.connect(func() -> void: _set_hovered(true))
	_area.mouse_exited.connect(func() -> void: _set_hovered(false))
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.31
	col.shape = shape
	col.position.y = -0.07
	_area.add_child(col)
	add_child(_area)

	_apply_label(_pending_label)
	if is_inside_tree():
		global_position = _pending_position


func setup(world_position: Vector3, label_text: String) -> void:
	_pending_position = world_position
	_pending_label = label_text
	if _label != null:
		_apply_label(label_text)
	if is_inside_tree():
		global_position = world_position


func _apply_label(label_text: String) -> void:
	_full_text = label_text
	_short_text = str(SHORT_NAMES.get(label_text, label_text))
	if _label != null:
		_label.text = ("点击观察 · " + _full_text) if _hovered else ("观察 · " + _short_text)


func _process(delta: float) -> void:
	if _collected:
		return
	_bob_t += delta
	_visual.position.y = sin(_bob_t * 1.7) * 0.025
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(global_position) if camera != null else 2.2
	var depth_scale := clampf(distance / 2.4, 0.30, 1.0)
	_visual.scale = _visual.scale.lerp(Vector3.ONE * depth_scale, 1.0 - exp(-delta * 6.0))
	# 离得近的桌面提示把文字放到图标上方，否则标签会掉出画面下缘。
	var tag_y := 0.235 if distance < 1.35 else -0.225
	_tag.position.y = lerpf(_tag.position.y, tag_y, 1.0 - exp(-delta * 7.0))
	_label.position.y = _tag.position.y + 0.004
	var pulse := 1.0 + sin(_bob_t * 2.4) * 0.045
	if _hovered:
		pulse += 0.10
	_icon.scale = Vector3.ONE * pulse
	_tag.scale.x = lerpf(_tag.scale.x, 1.0 if _hovered else 0.64, 1.0 - exp(-delta * 10.0))


func _set_hovered(value: bool) -> void:
	if _collected or _hovered == value:
		return
	_hovered = value
	_label.text = ("点击观察 · " + _full_text) if _hovered else ("观察 · " + _short_text)
	_label.modulate = ACCENT if _hovered else INK
	_icon.modulate = Color(1.0, 0.94, 0.82) if _hovered else Color.WHITE


func _on_input_event(_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if _collected:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_viewport().set_input_as_handled()
		_collect()


func collect_external() -> void:
	if not _collected:
		_collect()


func _collect() -> void:
	_collected = true
	_area.input_ray_pickable = false
	collected.emit(self)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position:y", global_position.y + 0.28, 0.34).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_icon, "modulate:a", 0.0, 0.26)
	tween.tween_property(_tag, "modulate:a", 0.0, 0.26)
	tween.tween_property(_label, "modulate:a", 0.0, 0.22)
	tween.chain().tween_callback(queue_free)
