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
## 自由转头（第 0 步“可以在正面的角度内自由旋转”）：按住右键拖动 / 方向键，
## 在正面锥形范围内叠加到流程给定的注视点之上；关闭后平滑回到流程视线。
@export var free_look_yaw_limit: float = 42.0 ## 左右各多少度
@export var free_look_pitch_up: float = 18.0 ## 向上多少度
@export var free_look_pitch_down: float = 26.0 ## 向下多少度
@export var free_look_speed: float = 0.16 ## 度 / 像素

## 四处看时的视线摆幅（米）；流程在躲避视线节拍设置，其余时间为 0。
var scan_amplitude: float = 0.0

var _position: Vector3 = Vector3.ZERO
var _look_target: Vector3 = Vector3.ZERO
var _smoothed_look: Vector3 = Vector3.ZERO
var _time: float = 0.0
var _tween: Tween = null
var _free_look: bool = false
var _free_yaw: float = 0.0
var _free_pitch: float = 0.0
## 节拍切换时把视线平滑拉回流程给定的方向；玩家一动鼠标就交还控制权。
var _recenter: bool = false

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	camera.fov = fov
	camera.near = 0.05
	camera.far = 50.0


func _process(delta: float) -> void:
	_time += delta
	_step_free_look(delta)
	var idle := Vector3(sin(_time * 0.9), sin(_time * 1.31 + 1.7), 0.0) * idle_position_amplitude
	var drift := Vector3(
		sin(_time * 0.41 + 0.6), cos(_time * 0.53), sin(_time * 0.37) * 0.5
	) * (idle_look_amplitude + scan_amplitude)
	camera.global_position = _position + idle
	var target := _look_target + drift
	var blend: float = 1.0 - exp(-delta * look_smoothing)
	_smoothed_look = _smoothed_look.lerp(target, blend)
	camera.look_at(_smoothed_look, Vector3.UP)
	# 自由转头叠加在流程注视点之上（每帧 look_at 会重算基底，所以放在其后）
	if absf(_free_yaw) > 0.001 or absf(_free_pitch) > 0.001:
		camera.rotate_object_local(Vector3.UP, deg_to_rad(_free_yaw))
		camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(_free_pitch))


## 用 _input 而不是 _unhandled_input：抬头显示（顶部控制条、字幕条）是 Control，
## 会把鼠标移动当成 GUI 事件吃掉，导致“拖了没反应”。
func _input(event: InputEvent) -> void:
	if not _free_look or not (event is InputEventMouseMotion):
		return
	var motion := event as InputEventMouseMotion
	if motion.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT) == 0:
		return
	nudge_free_look(-motion.relative.x * free_look_speed, -motion.relative.y * free_look_speed)
	_recenter = false


func _step_free_look(delta: float) -> void:
	if not _free_look:
		# 关闭后平滑归零，避免镜头突然弹回
		var t: float = 1.0 - exp(-delta * 8.0)
		_free_yaw = lerpf(_free_yaw, 0.0, t)
		_free_pitch = lerpf(_free_pitch, 0.0, t)
		return
	var key_step := 55.0 * delta
	var keyed := false
	if Input.is_key_pressed(KEY_LEFT):
		_free_yaw += key_step
		keyed = true
	if Input.is_key_pressed(KEY_RIGHT):
		_free_yaw -= key_step
		keyed = true
	if Input.is_key_pressed(KEY_UP):
		_free_pitch += key_step
		keyed = true
	if Input.is_key_pressed(KEY_DOWN):
		_free_pitch -= key_step
		keyed = true
	if keyed:
		_recenter = false
	_clamp_free_look()
	if not _recenter:
		return
	var blend: float = 1.0 - exp(-delta * 5.0)
	_free_yaw = lerpf(_free_yaw, 0.0, blend)
	_free_pitch = lerpf(_free_pitch, 0.0, blend)
	if absf(_free_yaw) < 0.2 and absf(_free_pitch) < 0.2:
		_free_yaw = 0.0
		_free_pitch = 0.0
		_recenter = false


## 开启/关闭自由转头。第一人称段全程开启，转第三人称时关闭。
func set_free_look(enabled: bool) -> void:
	_free_look = enabled


func is_free_look() -> bool:
	return _free_look


## 平滑把视线拉回流程给定的方向（节拍切换、事件转头时调用）。
func recenter_free_look() -> void:
	_recenter = true


## 叠加一次转头偏移（度），并夹在正面锥形范围内。供输入与无头检查使用。
func nudge_free_look(yaw_delta: float, pitch_delta: float) -> void:
	_free_yaw += yaw_delta
	_free_pitch += pitch_delta
	_clamp_free_look()


func _clamp_free_look() -> void:
	_free_yaw = clampf(_free_yaw, -free_look_yaw_limit, free_look_yaw_limit)
	_free_pitch = clampf(_free_pitch, -free_look_pitch_down, free_look_pitch_up)


## 当前自由转头偏移（度），测试用。
func free_look_offset() -> Vector2:
	return Vector2(_free_yaw, _free_pitch)


## 把自由转头归零（重开/测试用）。
func reset_free_look() -> void:
	_free_yaw = 0.0
	_free_pitch = 0.0
	_recenter = false


## 当前视线方向（世界坐标，单位向量）。
func forward() -> Vector3:
	return -camera.global_transform.basis.z.normalized()


## 当前注视点（测试用：确认流程没有擅自改方向）。
func look_target() -> Vector3:
	return _look_target


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
