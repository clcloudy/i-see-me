extends Node
## 教师“情绪排队”预览驱动（2026-10-23）。
## 场景里 5 个教师并排，依次是普通/激昂/失落/疑惑/开心；按 1/2/3 切换
## 同一组动作（讲课/提问/点名），方便横向比较同一动作下的情绪差异。
## 正式流程不需要这个脚本，直接调用 TeacherAnimator.set_action/set_emotion 即可。

@export var action: int = 0
@export var auto_cycle: bool = true
@export var interval: float = 6.0
@export var hud_path: NodePath

const ACTION_NAMES := ["讲课", "提问", "点名"]

var _teachers: Array[TeacherAnimator] = []
var _label: Label
var _timer: float = 0.0


func _ready() -> void:
	for i in 5:
		var teacher := get_node_or_null("../Teacher%d" % i) as TeacherAnimator
		if teacher != null:
			_teachers.append(teacher)
			teacher.action_changed.connect(_on_teacher_action)
	_label = get_node_or_null(hud_path) as Label
	_apply()


func _on_teacher_action(new_action: int) -> void:
	# 外部（例如截图脚本）直接改动作时，HUD 也跟着更新。
	action = new_action
	_refresh_label()


func _process(delta: float) -> void:
	if not auto_cycle or _teachers.is_empty():
		return
	_timer += delta
	if _timer >= interval:
		_timer = 0.0
		action = (action + 1) % 3
		_apply()


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			action = 0
		KEY_2:
			action = 1
		KEY_3:
			action = 2
		KEY_A:
			auto_cycle = not auto_cycle
		_:
			return
	_timer = 0.0
	_apply()


func _apply() -> void:
	for teacher in _teachers:
		teacher.set_action(action)
	_refresh_label()


func _refresh_label() -> void:
	if _label == null:
		return
	_label.text = "教师情绪对照 · 动作：%s\n1 讲课 | 2 提问 | 3 点名 | A 自动轮播（%s）\n每列从左到右：普通 / 激昂 / 失落 / 疑惑 / 开心" % [
		ACTION_NAMES[action],
		"开" if auto_cycle else "关",
	]
