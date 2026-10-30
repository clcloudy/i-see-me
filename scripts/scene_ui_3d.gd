class_name SceneUI3D
extends Node3D

## 把本来铺在 2D 视图上的界面，搬进三维场景里：
##  - 说话字幕：显示在该说话者头部附近的 3D 标签（billboard 朝向相机）；
##  - 可被观察到的事件：在事件发生处生成可点击收集的小球（EventOrb3D）；
##  - 发出动静的地方：生成向外扩散的声纹（SoundRipple3D）。
##
## 通过 DialogueFlow / DialogueUI 的信号接入，不改动任何流程时序
## （符合仓库 AGENTS.md「只有流程控制器推进阶段，模块通过信号连接」的约定）。

const EventOrbScript := preload("res://scripts/event_orb_3d.gd")
const SoundRippleScript := preload("res://scripts/sound_ripple_3d.gd")

@export var flow: NodePath
@export var interface: NodePath
@export var camera_path: NodePath
@export var teacher_anchor: NodePath
@export var protagonist_sit_anchor: NodePath
@export var protagonist_stand_anchor: NodePath
@export var protagonist_look_anchor: NodePath
@export var classmate_anchor: NodePath
@export var stage_anchor: NodePath

## 字幕悬浮在说话者头部上方的高度（米）。
@export var subtitle_height: float = 1.55
## 声纹基础颜色。
@export var ripple_color: Color = Color(0.62, 0.86, 1.0, 1.0)

var _flow: Node = null
var _interface: Node = null
var _camera: Camera3D = null
var _subtitle: Label3D = null


func _ready() -> void:
	_flow = get_node_or_null(flow)
	_interface = get_node_or_null(interface)
	_camera = get_node_or_null(camera_path)

	_subtitle = Label3D.new()
	_subtitle.visible = false
	_subtitle.font_size = 48
	_subtitle.pixel_size = 0.0025
	_subtitle.modulate = Color(1.0, 1.0, 1.0)
	_subtitle.outline_size = 6
	_subtitle.outline_modulate = Color(0.05, 0.08, 0.12)
	# 用内置公告板（仅绕 Y 轴、保持直立）面向相机——比手动 look_at 安全，
	# 相机贴近说话者头部时也不会产生 NaN 变换导致崩溃。
	_subtitle.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	add_child(_subtitle)

	if _interface != null and _interface.has_signal("world_subtitle"):
		_interface.world_subtitle.connect(_on_world_subtitle)
		_interface.world_subtitle_cleared.connect(_on_world_subtitle_cleared)
	if _flow != null:
		if _flow.has_signal("event_observed"):
			_flow.event_observed.connect(_on_event_observed)
		if _flow.has_signal("sound_emitted"):
			_flow.sound_emitted.connect(_on_sound_emitted)


# 3D 字幕朝向由 Label3D.billboard = BILLBOARD_FIXED_Y 自动处理（比手动 look_at 安全，
# 可避免相机贴近说话者锚点时出现 NaN 变换导致场景卡死/闪退）。


## —— 说话字幕：在该说话者头部附近显示 3D 标签 ——

func _on_world_subtitle(speaker_key: StringName, _display: String, _text: String) -> void:
	var anchor := _anchor_for_speaker(speaker_key)
	var pos := Vector3.ZERO
	if anchor != null:
		pos = anchor.global_position
	pos.y += subtitle_height
	_subtitle.global_position = pos
	_subtitle.text = str(_display) + "：" + str(_text)
	_subtitle.visible = true


func _on_world_subtitle_cleared() -> void:
	if _subtitle != null:
		_subtitle.visible = false


## —— 可观察事件：生成可点击收集的小球 ——

func _on_event_observed(event_id: StringName, label: String, world_position: Vector3) -> void:
	var orb := EventOrbScript.new()
	orb.setup(world_position, str(label))
	orb.collected.connect(_on_orb_collected.bind(event_id))
	add_child(orb)


func _on_orb_collected(_orb: Node, _event_id: StringName) -> void:
	# 收集动作本身也是一个「动静」：在收集点补一圈声纹反馈。
	_spawn_ripple(_orb.global_position, 0.5)


## —— 发出动静：生成向外扩散的声纹 ——

func _on_sound_emitted(world_position: Vector3, intensity: float) -> void:
	_spawn_ripple(world_position, intensity)


func _spawn_ripple(world_position: Vector3, intensity: float) -> void:
	# 防御性上限：极端情况下（如某次 play 密集触发）避免声纹节点无限堆积拖垮显存。
	var alive := 0
	for c in get_children():
		if c is SoundRippleScript:
			alive += 1
	if alive >= 24:
		return
	var r1 := SoundRippleScript.new()
	r1.setup(world_position, ripple_color, 1.4 + intensity * 0.8, 1.1)
	add_child(r1)
	var r2 := SoundRippleScript.new()
	r2.setup(world_position, ripple_color, 0.9 + intensity * 0.5, 0.9)
	add_child(r2)
	var timer := get_tree().create_timer(0.18, false)
	timer.timeout.connect(func() -> void:
		var r3 := SoundRippleScript.new()
		r3.setup(world_position, ripple_color, 1.1 + intensity * 0.6, 1.0)
		add_child(r3)
	)


## —— 说话者 → 3D 锚点 ——

func _anchor_for_speaker(speaker_key: StringName) -> Node3D:
	match speaker_key:
		&"teacher":
			return get_node_or_null(teacher_anchor)
		&"protagonist":
			for p in [protagonist_stand_anchor, protagonist_look_anchor, protagonist_sit_anchor]:
				var n := get_node_or_null(p)
				if n != null and n.visible:
					return n
			return get_node_or_null(protagonist_sit_anchor)
		&"classmate":
			return get_node_or_null(classmate_anchor)
		&"stage":
			return get_node_or_null(stage_anchor)
		_:
			return get_node_or_null(stage_anchor)
