class_name EventOrb3D
extends Node3D

## 可观察人物：整体变暗再复原 + 跟随头部的点击框与标签。
## 类名沿用 EventOrb3D 以兼容流程与测试，但视觉不再是发光球体。

signal collected(orb: EventOrb3D)

const MARKER_TEXTURE := preload("res://assets/ui/observation_head.svg")
const TAG_TEXTURE := preload("res://assets/ui/observation_tag.svg")
const ACTOR_SHADER := preload("res://assets/shaders/observation_actor.gdshader")
const INK := Color(1.0, 0.89, 0.68)
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
var _actor: Node3D
var _skeleton: Skeleton3D
var _head_bone: int = -1
var _highlight: ShaderMaterial
var _original_overlays: Dictionary = {}
## 被点开之后飞向哪里（屏幕右下角的收集夹）。由世界层在 collected 信号里给出；
## 没给就原地缩掉——调试场景里没有收集夹，也不该让提示卡在半空。
var _fly_target: Vector3 = Vector3.ZERO
var _has_fly_target: bool = false


func _ready() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	_icon = Sprite3D.new()
	_icon.texture = MARKER_TEXTURE
	_icon.pixel_size = 0.0014
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.no_depth_test = true
	_icon.shaded = false
	_icon.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_icon.render_priority = 3
	_visual.add_child(_icon)

	_tag = Sprite3D.new()
	_tag.texture = TAG_TEXTURE
	_tag.pixel_size = 0.00165
	_tag.scale.x = 0.64
	_tag.position = Vector3(0.0, 0.30, 0.0)
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.shaded = false
	_tag.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_tag.modulate.a = 0.94
	_tag.render_priority = 3
	_visual.add_child(_tag)

	_label = Label3D.new()
	_label.font_size = 23
	_label.pixel_size = 0.0020
	_label.modulate = INK
	_label.outline_size = 3
	_label.outline_modulate = Color(0.025, 0.055, 0.075, 0.96)
	_label.position = Vector3(0.0, 0.304, 0.008)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.shaded = false
	_label.render_priority = 4
	_visual.add_child(_label)

	_area = Area3D.new()
	_area.input_event.connect(_on_input_event)
	_area.mouse_entered.connect(func() -> void: _set_hovered(true))
	_area.mouse_exited.connect(func() -> void: _set_hovered(false))
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	col.shape = shape
	# 可见头部框与拾取球共用原点，不再把点击范围偏到标签下方。
	shape.radius = 0.22
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
		_label.text = (_full_text + "\n点击头部观察") if _hovered else ("观察 · " + _short_text)


func _process(delta: float) -> void:
	if _collected:
		return
	_bob_t += delta
	if is_instance_valid(_actor):
		_update_head_position()
	if _highlight != null:
		_highlight.set_shader_parameter("pulse", 0.5 - cos(_bob_t * TAU / 2.4) * 0.5)
	var camera := get_viewport().get_camera_3d()
	var distance := camera.global_position.distance_to(global_position) if camera != null else 2.2
	var depth_scale := clampf(distance / 2.4, 0.65, 1.0)
	_visual.scale = _visual.scale.lerp(Vector3.ONE * depth_scale, 1.0 - exp(-delta * 6.0))
	# 所有观察使用一致布局：头部框 + 上方标签，不随距离上下翻转。
	var tag_y := 0.30
	_tag.position.y = lerpf(_tag.position.y, tag_y, 1.0 - exp(-delta * 7.0))
	_label.position.y = _tag.position.y + 0.004
	var pulse := 1.0 + sin(_bob_t * 1.8) * 0.020
	if _hovered:
		pulse += 0.10
	_icon.scale = Vector3.ONE * pulse
	_tag.scale.x = lerpf(_tag.scale.x, 1.0 if _hovered else 0.64, 1.0 - exp(-delta * 10.0))
	_area.scale = Vector3.ONE * depth_scale


## 复用事件中的同学，头部骨骼随低头、转头、弯腰实时更新。
func bind_actor(actor: Node3D) -> void:
	_actor = actor
	_highlight = ShaderMaterial.new()
	_highlight.shader = ACTOR_SHADER
	var stack: Array[Node] = [actor]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Skeleton3D:
			var bone := (node as Skeleton3D).find_bone("Head")
			if bone >= 0:
				_skeleton = node
				_head_bone = bone
		if node is MeshInstance3D:
			var mesh := node as MeshInstance3D
			_original_overlays[mesh] = mesh.material_overlay
			mesh.material_overlay = _highlight
	_update_head_position()


func _update_head_position() -> void:
	global_position = head_position(_actor, _skeleton, _head_bone)


## 观察与内心 OS 共用同一个头部锚点，避免回放落回旧的内容坐标。
static func head_position(actor: Node3D, skeleton: Skeleton3D = null, bone: int = -1) -> Vector3:
	if not is_instance_valid(skeleton):
		for node in actor.find_children("*", "Skeleton3D", true, false):
			var candidate := node as Skeleton3D
			var index := candidate.find_bone("Head")
			if index >= 0:
				skeleton = candidate
				bone = index
				break
	if is_instance_valid(skeleton) and bone >= 0:
		var head := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
		return head.origin + head.basis.orthonormalized().y * 0.08
	else:
		return actor.global_position + Vector3.UP * 1.2


func _release_actor() -> void:
	for mesh in _original_overlays:
		if is_instance_valid(mesh) and mesh.material_overlay == _highlight:
			mesh.material_overlay = _original_overlays[mesh]
	_original_overlays.clear()
	_actor = null
	_highlight = null


func _exit_tree() -> void:
	_release_actor()


func _set_hovered(value: bool) -> void:
	if _collected or _hovered == value:
		return
	_hovered = value
	_label.text = (_full_text + "\n点击头部观察") if _hovered else ("观察 · " + _short_text)
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


## 收进右下角的收集夹：在 collected 信号里给一个世界坐标，提示就会飞过去再消失，
## 玩家看得见「这一条被我收着了」。不给（或给非有限值）就退回原来的原地缩掉。
func collect_into(world_point: Vector3) -> void:
	if not world_point.is_finite():
		return
	_fly_target = world_point
	_has_fly_target = true


## 完整标签（悬停展开的那句），供流程/检查按名字找到对应的观察。
func label_text() -> String:
	return _full_text


func _collect() -> void:
	_collected = true
	_area.input_ray_pickable = false
	_release_actor()
	collected.emit(self)
	# 信号是同步的：世界层在上面那一刻就把收集夹的位置给了我们。
	if _has_fly_target:
		_fly_into_slot()
		return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position:y", global_position.y + 0.28, 0.34).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_icon, "modulate:a", 0.0, 0.26)
	tween.tween_property(_tag, "modulate:a", 0.0, 0.26)
	tween.tween_property(_label, "modulate:a", 0.0, 0.22)
	tween.chain().tween_callback(queue_free)


## 飞向收集夹：先提一下再滑向右下，同时缩小淡出——像被从教室里捡起来收进口袋。
func _fly_into_slot() -> void:
	var start := global_position
	var target := _fly_target
	var seconds := 0.46
	var tween := create_tween().set_parallel(true)
	tween.tween_method(
		func(t: float) -> void:
			if not is_instance_valid(self):
				return
			global_position = start.lerp(target, t) + Vector3.UP * sin(t * PI) * 0.14,
		0.0, 1.0, seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "scale", Vector3.ONE * 0.06, seconds).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(_icon, "modulate:a", 0.0, seconds * 0.7).set_delay(seconds * 0.3)
	tween.tween_property(_tag, "modulate:a", 0.0, seconds * 0.6).set_delay(seconds * 0.2)
	tween.tween_property(_label, "modulate:a", 0.0, seconds * 0.5)
	tween.chain().tween_callback(queue_free)
