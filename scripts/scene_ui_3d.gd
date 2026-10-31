class_name SceneUI3D
extends Node3D

## 世界空间表现：说话者旁的分行字幕、可点击观察标记，以及轻量声纹。
## 只监听流程与界面信号，不推进任何剧情时序。

const EventOrbScript := preload("res://scripts/event_orb_3d.gd")
const SoundRippleScript := preload("res://scripts/sound_ripple_3d.gd")
const FX_GROUP := L2FlowState.TRANSIENT_FX_GROUP
const SPEAKER_COLORS := {
	&"teacher": Color(0.95, 0.79, 0.52),
	&"protagonist": Color(0.61, 0.85, 0.84),
	&"classmate": Color(0.82, 0.89, 0.76),
	&"stage": Color(0.67, 0.77, 0.80),
}

@export var flow: NodePath
@export var interface: NodePath
@export var camera_path: NodePath
@export var teacher_anchor: NodePath
@export var protagonist_sit_anchor: NodePath
@export var protagonist_stand_anchor: NodePath
@export var protagonist_look_anchor: NodePath
@export var classmate_anchor: NodePath
@export var stage_anchor: NodePath
@export var subtitle_height: float = 1.75
@export var ripple_color: Color = Color(0.61, 0.85, 0.84, 0.60)

var _flow: Node = null
var _interface: Node = null
var _camera: Camera3D = null
var _subtitle: Sprite3D = null
var _subtitle_viewport: SubViewport = null
var _subtitle_speaker: Label = null
var _subtitle_line: Label = null
var _subtitle_tween: Tween = null


func _ready() -> void:
	_flow = get_node_or_null(flow)
	_interface = get_node_or_null(interface)
	_camera = get_node_or_null(camera_path)
	_build_subtitle()
	if _interface != null and _interface.has_signal("world_subtitle"):
		_interface.world_subtitle.connect(_on_world_subtitle)
		_interface.world_subtitle_cleared.connect(_on_world_subtitle_cleared)
	if _flow != null:
		if _flow.has_signal("event_observed"):
			_flow.event_observed.connect(_on_event_observed)
		if _flow.has_signal("sound_emitted"):
			_flow.sound_emitted.connect(_on_sound_emitted)
		if _flow.has_signal("stage_changed"):
			_flow.stage_changed.connect(_on_stage_changed)


func _build_subtitle() -> void:
	_subtitle_viewport = SubViewport.new()
	_subtitle_viewport.name = "SubtitleViewport"
	_subtitle_viewport.size = Vector2i(640, 180)
	_subtitle_viewport.disable_3d = true
	_subtitle_viewport.transparent_bg = true
	_subtitle_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_subtitle_viewport)

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.048, 0.068, 0.88)
	style.border_color = Color(0.48, 0.68, 0.70, 0.52)
	style.set_border_width_all(1)
	style.set_corner_radius_all(18)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 17
	style.content_margin_bottom = 18
	style.shadow_color = Color(0, 0, 0, 0.32)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 5)
	panel.add_theme_stylebox_override("panel", style)
	_subtitle_viewport.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	_subtitle_speaker = Label.new()
	_subtitle_speaker.add_theme_font_size_override("font_size", 23)
	_subtitle_speaker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_subtitle_speaker)
	_subtitle_line = Label.new()
	_subtitle_line.add_theme_font_size_override("font_size", 36)
	_subtitle_line.add_theme_color_override("font_color", Color(0.93, 0.96, 0.94))
	_subtitle_line.add_theme_constant_override("line_spacing", 5)
	_subtitle_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_subtitle_line)

	_subtitle = Sprite3D.new()
	_subtitle.name = "WorldSubtitle"
	_subtitle.texture = _subtitle_viewport.get_texture()
	_subtitle.pixel_size = 0.0027
	_subtitle.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	# 字幕可读优先：前排同学的头可以挡住动作，但不能挡掉正在说的字。
	_subtitle.no_depth_test = true
	_subtitle.shaded = false
	_subtitle.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	_subtitle.render_priority = 10
	_subtitle.visible = false
	add_child(_subtitle)


func _on_stage_changed(stage_id: StringName) -> void:
	if stage_id == &"intro":
		_clear_orbs()


func _clear_orbs() -> void:
	for child in get_children():
		if child is EventOrbScript:
			remove_child(child)
			child.queue_free()


func _add_ripple(ripple: Node3D) -> void:
	add_child(ripple)
	ripple.add_to_group(FX_GROUP)


## ——— 说话字幕 ———

func _on_world_subtitle(speaker_key: StringName, display: String, text: String) -> void:
	if _subtitle_tween != null and _subtitle_tween.is_valid():
		_subtitle_tween.kill()
	var anchor := _anchor_for_speaker(speaker_key)
	var pos := anchor.global_position if anchor != null else Vector3.ZERO
	match speaker_key:
		&"teacher":
			pos.y += subtitle_height
		&"classmate":
			pos.y += 0.85
		&"protagonist":
			pos.y += 1.55
		&"stage":
			pass # StageAnchor 已经是旁白面板的实际高度，不再重复加人物身高。
	if speaker_key == &"protagonist" and _camera != null and _camera.global_position.distance_to(pos) < 0.9:
		pos = _camera.global_position - _camera.global_basis.z * 1.95 - _camera.global_basis.y * 0.40
	_subtitle.global_position = pos

	_subtitle.pixel_size = 0.0021 if speaker_key == &"protagonist" else 0.0027
	_subtitle_speaker.text = str(display)
	_subtitle_speaker.add_theme_color_override(
		"font_color", SPEAKER_COLORS.get(speaker_key, Color(0.72, 0.82, 0.83))
	)
	_subtitle_line.text = str(text)
	var lines := maxi(1, ceili(float(str(text).length()) / 16.0))
	_subtitle_viewport.size = Vector2i(680, 124 + lines * 56)
	_subtitle.visible = true
	_subtitle.modulate.a = 0.0
	_subtitle_tween = create_tween()
	_subtitle_tween.tween_property(_subtitle, "modulate:a", 1.0, 0.18)


func _on_world_subtitle_cleared() -> void:
	if _subtitle == null or not _subtitle.visible:
		return
	if _subtitle_tween != null and _subtitle_tween.is_valid():
		_subtitle_tween.kill()
	_subtitle_tween = create_tween()
	_subtitle_tween.tween_property(_subtitle, "modulate:a", 0.0, 0.14)
	_subtitle_tween.tween_callback(func() -> void: _subtitle.visible = false)


## ——— 可观察事件 ———

func _on_event_observed(event_id: StringName, label: String, world_position: Vector3) -> void:
	var orb := EventOrbScript.new()
	orb.setup(world_position, str(label))
	orb.collected.connect(_on_orb_collected.bind(event_id))
	add_child(orb)


func _on_orb_collected(orb: Node, _event_id: StringName) -> void:
	_spawn_ripple((orb as Node3D).global_position, 0.35)


## ——— 声纹 ———

func _on_sound_emitted(world_position: Vector3, intensity: float) -> void:
	_spawn_ripple(world_position, intensity)


func _spawn_ripple(world_position: Vector3, intensity: float) -> void:
	# 自己说话的声源就在相机上，向外扩的弧会铺满整块屏幕；这种位置不放声纹。
	if _camera != null and _camera.global_position.distance_to(world_position) < 0.65:
		return
	var alive := 0
	for child in get_children():
		if child is SoundRippleScript:
			alive += 1
	if alive >= 18:
		return
	var first := SoundRippleScript.new()
	first.setup(world_position, ripple_color, 0.24 + intensity * 0.12, 0.78)
	_add_ripple(first)
	var timer := get_tree().create_timer(0.12, false)
	timer.timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		var second := SoundRippleScript.new()
		second.setup(world_position, ripple_color, 0.33 + intensity * 0.16, 0.94)
		_add_ripple(second)
	)


func _anchor_for_speaker(speaker_key: StringName) -> Node3D:
	match speaker_key:
		&"teacher":
			return get_node_or_null(teacher_anchor)
		&"protagonist":
			for path in [protagonist_stand_anchor, protagonist_look_anchor, protagonist_sit_anchor]:
				var node := get_node_or_null(path)
				if node != null and node.visible:
					return node
			return get_node_or_null(protagonist_sit_anchor)
		&"classmate":
			return get_node_or_null(classmate_anchor)
		&"stage":
			return get_node_or_null(stage_anchor)
		_:
			return get_node_or_null(stage_anchor)
