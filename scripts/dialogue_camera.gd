class_name DialogueCamera
extends Node3D

## 课堂对话镜头控制（主开发，2026-10-24）。
## L1 第一人称：相机固定在主角头部（坐 1.36 / 站 1.70），由流程给注视点；
## L2 第三人称：位置与注视点一起补间到座位旁过道，看向坐着的自己。
##
## 设计要点：
## - 位置与注视点分离：_position 由补间驱动，_look_target 由流程/事件切换，
##   每帧 look_at 平滑逼近，因此“边转身走位边看”不需要额外状态。
## - 待机微动：极小幅的呼吸位移与视线游移，避免第一人称完全静止。
## - scan_amplitude：躲避视线“四处看”时放大视线摆幅（流程设置，0 为关闭）。
## - 补间绑定本节点：节点随场景树暂停而暂停，暂停时镜头冻结。
## - 重开：cancel() 杀掉进行中的补间，由流程重新 snap。

@export var fov: float = 65.0
@export var idle_position_amplitude: float = 0.004 ## 呼吸位移幅度（米）
@export var idle_look_amplitude: float = 0.035 ## 待机视线游移幅度（米）
@export var look_smoothing: float = 6.0 ## 注视点平滑速度（越大越跟手）

## 四处看时的视线摆幅（米）；流程在躲避视线节拍设置，其余时间为 0。
var scan_amplitude: float = 0.0

var _position: Vector3 = Vector3.ZERO
var _look_target: Vector3 = Vector3.ZERO
var _smoothed_look: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _tween: Tween = null

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	camera.fov = fov
	camera.near = 0.05
	camera.far = 50.0


func _process(delta: float) -> void:
	_time += delta
	var idle := Vector3(sin(_time * 0.9), sin(_time * 1.31 + 1.7), 0.0) * idle_position_amplitude
	var drift := Vector3(
		sin(_time * 0.41 + 0.6), cos(_time * 0.53), sin(_time * 0.37) * 0.5
	) * (idle_look_amplitude + scan_amplitude)
	camera.global_position = _position + idle
	var target := _look_target + drift
	var blend: float = 1.0 - exp(-delta * look_smoothing)
	_smoothed_look = _smoothed_look.lerp(target, blend)
	camera.look_at(_smoothed_look, Vector3.UP)


## 立即到位（重开、跳转用）。
func snap(position: Vector3, look_target: Vector3) -> void:
	cancel()
	_position = position
	_look_target = look_target
	_smoothed_look = look_target
	camera.global_position = position
	camera.look_at(look_target, Vector3.UP)


## 只切换注视点（事件吸引、节拍切换）。
func set_look_target(target: Vector3) -> void:
	_look_target = target


## 设置四处看摆幅（米）。
func set_scan(amplitude: float) -> void:
	scan_amplitude = amplitude


## 平滑移动机位（起立/坐下改头部高度、教师走位时的跟随等）。
func move_to(position: Vector3, seconds: float) -> void:
	if seconds <= 0.0:
		snap(position, _look_target)
		return
	cancel()
	var from := _position
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_tween.tween_method(
		func(value: Vector3) -> void: _position = value, from, position, seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## L1→L2 转场：位置与注视点同时补间（第三人称构图）。
func transition_to(position: Vector3, look_target: Vector3, seconds: float) -> void:
	cancel()
	var from_position := _position
	var from_look := _look_target
	_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_BOUND)
	_tween.set_parallel(true)
	_tween.tween_method(
		func(value: Vector3) -> void: _position = value, from_position, position, seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(
		func(value: Vector3) -> void: _look_target = value, from_look, look_target, seconds
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


## 结束进行中的补间并停在当前值（重开/跳转前调用）。
func cancel() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func current_position() -> Vector3:
	return camera.global_position
