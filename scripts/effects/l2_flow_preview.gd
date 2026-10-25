extends Node3D

## 独立预览：教室 + 主角 + 头部后方的相机 + L2/L3 状态。
## 用 F6 单独运行本场景：空格切换 L2，L 进入 L3 抽离，Backspace 退回 L2。
## 不改主场景与流程。

@onready var camera: Camera3D = $Camera3D
@onready var look_target: Marker3D = $LookTarget
@onready var flow_state: L2FlowState = $L2FlowState
@onready var toggle: Button = %Toggle
@onready var isolate: Button = %Isolate
@onready var back: Button = %Back
@onready var status: Label = %Status


func _ready() -> void:
	camera.look_at(look_target.global_position, Vector3.UP)
	toggle.pressed.connect(_toggle)
	isolate.pressed.connect(_enter_l3)
	back.pressed.connect(_leave_l3)
	flow_state.state_changed.connect(_on_state_changed)
	flow_state.isolation_changed.connect(_on_isolation_changed)
	flow_state.isolation_finished.connect(_sync)
	_sync()


func _toggle() -> void:
	flow_state.toggle()


func _enter_l3() -> void:
	flow_state.enter_l3()


func _leave_l3() -> void:
	flow_state.leave_l3(true)


func _on_state_changed(_active: bool) -> void:
	_sync()


func _on_isolation_changed(_isolated: bool) -> void:
	_sync()


func _sync() -> void:
	var active := flow_state.is_active()
	var isolating := flow_state.is_l3()
	toggle.text = "关闭心流效果（恢复教室材质）" if active else "开启 L2 心流效果"
	isolate.disabled = not active or isolating
	back.disabled = not isolating
	if isolating:
		if flow_state.is_isolated():
			status.text = "状态：L3 抽离完成 · 只剩地板与主角、纯灰度、无模糊"
		else:
			status.text = "状态：L3 抽离中… · 其余物体淡出、模糊退场"
	elif active:
		status.text = "状态：L2 心流 · 灰黑无贴图，主角周围清晰、之外模糊"
	else:
		status.text = "状态：关闭（正常教室材质）"


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_toggle()
			KEY_L:
				_enter_l3()
			KEY_BACKSPACE:
				_leave_l3()
			_:
				return
		get_viewport().set_input_as_handled()
