extends Node3D

## 独立预览：教室 + 主角 + 头部后方的相机 + L2 心流状态。
## 用 F6 单独运行本场景，空格或按钮切换效果；不改主场景与流程。

@onready var camera: Camera3D = $Camera3D
@onready var look_target: Marker3D = $LookTarget
@onready var flow_state: L2FlowState = $L2FlowState
@onready var toggle: Button = %Toggle
@onready var status: Label = %Status


func _ready() -> void:
	camera.look_at(look_target.global_position, Vector3.UP)
	toggle.pressed.connect(_toggle)
	flow_state.state_changed.connect(_on_state_changed)
	_sync(flow_state.is_active())


func _toggle() -> void:
	flow_state.toggle()


func _on_state_changed(active: bool) -> void:
	_sync(active)


func _sync(active: bool) -> void:
	toggle.text = "关闭心流效果" if active else "开启心流效果"
	status.text = "状态：开启 · 2.0 m 内清晰，之外模糊" if active else "状态：关闭（正常教室材质）"


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle()
		get_viewport().set_input_as_handled()
